import json
import os
import subprocess
from pathlib import Path
import httpx

config=Path('/etc/open-terminal/open-terminal.env')
root=Path('/opt/open-terminal_data')
key=dict(line.split('=',1) for line in config.read_text().splitlines())['OPEN_TERMINAL_API_KEY']
client=httpx.Client(base_url='http://127.0.0.1:8000', headers={'Authorization': f'Bearer {key}'}, timeout=20)
checks=[]
marker=Path('/tmp/open-terminal-qa-host-marker')
marker.write_text('outside the service temporary directory')
def check(name, ok):
    assert ok, name
    checks.append(name)
    print('PASS',name,flush=True)
def run(command):
    r=client.post('/execute?wait=10',json={'command': command})
    r.raise_for_status()
    data=r.json()
    return data['exit_code'], ''.join(x.get('data','') for x in data['output'])
check('configuration owned by root with mode 0600', config.stat().st_uid==0 and config.stat().st_mode & 0o777==0o600)
check('configuration directory root-owned and not user-writable',config.parent.stat().st_uid==0 and config.parent.stat().st_mode & 0o777==0o755)
check('legacy workspace secret absent', not (root/'.env').exists())
rc,out=run('whoami; id -u; id -Gn')
check('non-root identity without administrative groups',rc==0 and out.splitlines()[0]=='open-terminal' and int(out.splitlines()[1])>0 and out.splitlines()[2]=='open-terminal')
for name,cmd in [
 ('shell cannot read secret',f'cat {config}'),
 ('shell cannot overwrite secret',f'printf denied > {config}'),
 ('shell cannot create system file','touch /etc/open-terminal-qa-denied'),
 ('shell cannot alter service','touch /etc/systemd/system/open-terminal.service'),
 ('shell cannot write application','touch /opt/open-terminal/qa-denied'),
 ('shell cannot write virtualenv','touch /opt/open-terminal/.venv/qa-denied'),
 ('shell cannot write Python runtime','touch /opt/open-terminal-python/qa-denied'),
 ('shell cannot read root home','ls /root'),
 ('shell cannot sudo','sudo -n true'),
 ('shell cannot become root','su -s /bin/sh root -c id </dev/null'),
]:
    rc,out=run(cmd)
    check(name,rc is not None and rc!=0 and key not in out)
for method,path,body in [('GET','/files/read',None),('POST','/files/write',{'path':str(config),'content':'denied'})]:
    r=client.request(method,path,params={'path':str(config)} if method=='GET' else None,json=body)
    check('file API cannot '+('read' if method=='GET' else 'overwrite')+' secret',r.status_code!=200 and key not in r.text)
rc,out=run("python3 -c 'import os; print(os.umask(0)); print(open(\"/proc/self/status\").read())'")
check('private umask',rc==0 and out.splitlines()[0]=='63')
check('no-new-privileges inherited', 'NoNewPrivs:\t1' in out)
check('empty capabilities inherited', 'CapEff:\t0000000000000000' in out and 'CapBnd:\t0000000000000000' in out)
rc,out=run("python3 -c 'from pathlib import Path; p=Path(\"qa-private-file\"); p.write_text(\"private\"); print(oct(p.stat().st_mode & 511))'")
check('new workspace file mode 0600', rc==0 and '0o600' in out)
rc,out=run('uv venv --clear .qa-user-venv && .qa-user-venv/bin/python3 -c "print(42)"')
check('user can create own Python environment',rc==0 and '42' in out)
rc,out=run('uv pip install --python .qa-user-venv/bin/python packaging && .qa-user-venv/bin/python -c "import packaging; print(packaging.__version__)"')
check('user can install packages in own environment',rc==0 and 'packaging' in out)
rc,out=run("python3 -c 'from pathlib import Path; print(Path(\"/tmp/open-terminal-qa-host-marker\").exists())'")
check('private temporary directory',rc==0 and 'False' in out)
check('key unchanged after denied writes',dict(line.split('=',1) for line in config.read_text().splitlines())['OPEN_TERMINAL_API_KEY']==key)
for prop,value in [('User','open-terminal'),('Group','open-terminal'),('NoNewPrivileges','yes'),('ProtectSystem','strict'),('ProtectHome','yes'),('PrivateTmp','yes'),('PrivateDevices','yes'),('UMask','0077')]:
    actual=subprocess.check_output(['systemctl','show','open-terminal','--property='+prop,'--value'],text=True).strip()
    check('real systemd '+prop,actual==value)
(Path(__file__).resolve().parent / 'hardening-results.json').write_text(json.dumps({'architecture':os.uname().machine,'checks':checks},indent=2)+'\n')
marker.unlink()
print(f'{len(checks)} hardening checks passed')
