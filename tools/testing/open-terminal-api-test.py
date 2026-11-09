import asyncio
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import httpx
import websockets

root = Path('/opt/open-terminal_data')
qa_root = Path(__file__).resolve().parent
env_path = Path('/etc/open-terminal/open-terminal.env')
if not env_path.exists():
    env_path = root / '.env'
env = dict(line.split('=', 1) for line in env_path.read_text().splitlines())
key = env['OPEN_TERMINAL_API_KEY']
client = httpx.Client(base_url='http://127.0.0.1:8000', headers={'Authorization': f'Bearer {key}'}, timeout=15)
results = []

def checked(name, condition):
    assert condition, name
    results.append(name)
    print('PASS', name, flush=True)

def execute(command, **kwargs):
    response = client.post('/execute?wait=5', json={'command': command, **kwargs})
    response.raise_for_status()
    return response.json()

def output(response):
    return ''.join(item.get('data', '') for item in response['output'])

def state():
    paths = ['.env', 'persist.txt', '.config/open-terminal-qa/settings.json', 'uploads/roundtrip.bin']
    return {p: hashlib.sha256((env_path if p == '.env' else root / p).read_bytes()).hexdigest() for p in paths}

async def terminal_tests():
    response = client.post('/api/terminals')
    response.raise_for_status()
    sid = response.json()['id']
    url = f'ws://127.0.0.1:8000/api/terminals/{sid}'
    for payload in ({'type': 'auth'}, {'type': 'auth', 'token': 'wrong'}):
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps(payload))
            try:
                await asyncio.wait_for(ws.recv(), 4)
                raise AssertionError('unauthorized websocket was accepted')
            except websockets.ConnectionClosed as exc:
                checked('websocket rejects missing/wrong key', exc.rcvd.code == 4001)

    async def interact(marker, command):
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({'type': 'auth', 'token': key}))
            await ws.send(json.dumps({'type': 'resize', 'cols': 100, 'rows': 30}))
            await ws.send(command.encode())
            received = b''
            deadline = time.monotonic() + 5
            while marker not in received and time.monotonic() < deadline:
                chunk = await asyncio.wait_for(ws.recv(), 5)
                received += chunk if isinstance(chunk, bytes) else chunk.encode()
            checked('PTY input/output and resize' if marker == b'PTY_42' else 'PTY reconnect and working directory', marker in received)

    await interact(b'PTY_42', "printf 'PTY_%s\\n' 42\n")
    await asyncio.sleep(.2)
    await interact(b'HOME_/opt/open-terminal_data', "printf 'HOME_%s\\n' \"$PWD\"\n")
    checked('terminal cleanup', client.delete(f'/api/terminals/{sid}').status_code == 200)

checked('public health', client.get('/health').json() == {'status': 'ok'})
features = client.get('/api/config').json()['features']
checked('minimal feature flags', features['terminal'] and not any(features[k] for k in ('browser', 'desktop', 'notebooks')))
checked('generated key and file mode', len(key) == 48 and key.isalnum() and env_path.stat().st_mode & 0o777 == 0o600)
state_path = qa_root / 'persistent-hashes.json'
if state_path.exists():
    checked('persistent key/files/settings hashes before any writes', state() == json.loads(state_path.read_text()))

for auth in (None, 'wrong'):
    headers = {} if auth is None else {'Authorization': f'Bearer {auth}'}
    with httpx.Client(base_url='http://127.0.0.1:8000', headers=headers) as unauth:
        for method, path, body in [('POST', '/execute', {'command': 'true'}), ('POST', '/files/write', {'path': 'unauthorized', 'content': 'x'}), ('GET', '/files/read?path=/etc/hostname', None), ('POST', '/files/upload?directory=uploads', None), ('POST', '/api/terminals', None)]:
            checked(f'HTTP rejects {auth or "missing"} key: {method} {path.split("?")[0]}', unauth.request(method, path, json=body).status_code == 401)

result = execute('printf OUT; printf ERR >&2; exit 7')
checked('command output/error/exit code', result['exit_code'] == 7 and 'OUT' in output(result) and 'ERR' in output(result))
checked('default persistent working directory', result['cwd'] == str(root))
checked('explicit working directory', '/tmp' in output(execute('pwd', cwd='/tmp')))
checked('API key excluded from child environment', 'OPEN_TERMINAL_API_KEY' not in output(execute('env')))
checked('Python runtime on command PATH', '3.12.' in output(execute('python3 --version')))

started = time.monotonic()
result = client.post('/execute?wait=0.1', json={'command': 'sleep 2; printf finished'}).json()
checked('wait timeout returns running process', result['status'] == 'running' and time.monotonic() - started < 1.5)
finished = client.get(f'/execute/{result["id"]}/status?wait=5').json()
checked('timed wait process completes', finished['exit_code'] == 0 and 'finished' in output(finished))
result = client.post('/execute', json={'command': 'sleep 90'}).json()
checked('stop command', client.delete(f'/execute/{result["id"]}?force=true').status_code == 200)
finished = client.get(f'/execute/{result["id"]}/status?wait=5').json()
checked('stopped command exit status', finished['status'] != 'running' and finished['exit_code'] != 0)

for path, content in [('persist.txt', 'persistent work file\n'), ('.config/open-terminal-qa/settings.json', '{"theme":"test"}\n')]:
    response = client.post('/files/write', json={'path': path, 'content': content})
    checked(f'write {path}', response.status_code == 200)
    read = client.get('/files/read', params={'path': path})
    checked(f'read {path}', read.status_code == 200 and read.json()['content'] == content)

payload = bytes(range(256)) * 64
uploaded = client.post('/files/upload?directory=uploads', files={'file': ('roundtrip.bin', payload, 'application/octet-stream')})
checked('multipart upload', uploaded.status_code == 200 and uploaded.json()['size'] == len(payload))
download = client.get('/files/view', params={'path': str(root / 'uploads/roundtrip.bin')})
checked('binary download exact bytes', download.status_code == 200 and download.content == payload)

asyncio.run(terminal_tests())
if state_path.exists():
    checked('persistent key/files/settings hashes', state() == json.loads(state_path.read_text()))
else:
    state_path.write_text(json.dumps(state(), indent=2) + '\n')
report = {'architecture': os.uname().machine, 'python': sys.version, 'app_version': __import__('importlib.metadata').metadata.version('open-terminal'), 'checks': results}
(qa_root / f'api-results-{report["app_version"]}.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'{len(results)} checks passed')
