"""Persistent local leader paired explicitly with the remote beta follower."""
import argparse
import getpass
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / '.beta-local'
ENV = STATE / 'compose.env'
PAIR = STATE / 'pair.json'
BETA_API = 'https://beta.api.turnie.re'


def private_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        stream.write(content)
    path.chmod(0o600)


def settings():
    if not ENV.exists():
        raise SystemExit('Run inv beta-local-init first.')
    return dict(line.split('=', 1) for line in ENV.read_text().splitlines() if line and not line.startswith('#'))


def compose(*args, **kwargs):
    settings()
    docker = shutil.which('docker')
    if docker and subprocess.run([docker, 'compose', 'version'], capture_output=True).returncode == 0:
        command = [docker, 'compose']
    elif shutil.which('docker-compose'):
        command = [shutil.which('docker-compose')]
    else:
        raise SystemExit('Install Docker Compose v2 (docker compose or docker-compose).')
    return subprocess.run([*command, '--env-file', str(ENV), '-f',
                           str(ROOT / 'compose.beta-local.yml'), *args], cwd=ROOT, check=True, **kwargs)


def initialize():
    if ENV.exists():
        print(f'Keeping existing configuration: {ENV}')
        return
    private_write(ENV, '\n'.join([
        'BETA_LOCAL_API_PORT=4300', 'BETA_LOCAL_WEB_PORT=4301',
        f'BETA_LOCAL_DB_PASSWORD={secrets.token_hex(24)}',
        f'BETA_LOCAL_SECRET_KEY_BASE={secrets.token_hex(64)}',
        'BETA_LOCAL_OWNER_EMAIL=beta-local@example.test',
        f'BETA_LOCAL_OWNER_PASSWORD={secrets.token_hex(16)}',
    ]) + '\n')
    print(f'Created {ENV}; edit ports here if needed. Keep this file private.')


def up(build=True):
    initialize()
    config = settings()
    env = os.environ.copy()
    for label, directory in [('BACKEND', ROOT), ('FRONTEND', ROOT.parent / 'turniere-frontend')]:
        env[f'BETA_LOCAL_{label}_SHA'] = subprocess.check_output(
            ['git', '-C', str(directory), 'rev-parse', 'HEAD'], text=True).strip()
    compose('up', '-d', '--wait', '--wait-timeout', '240', *(['--build'] if build else []), env=env)
    # Only this isolated Compose backend is touched. Keep credentials off argv/logs.
    attributes = dict(email=config['BETA_LOCAL_OWNER_EMAIL'], password=config['BETA_LOCAL_OWNER_PASSWORD'])
    ruby = "require 'json'; a = JSON.parse(" + json.dumps(json.dumps(attributes)) + "); "
    ruby += ("u = User.find_or_initialize_by(email: a.fetch('email')); "
             "u.username = 'beta-local-owner' if u.new_record?; "
             "u.password = a.fetch('password'); u.password_confirmation = u.password; "
             "u.confirmed_at ||= Time.current; u.uid = u.email; u.provider = 'email'; u.save!; "
             "puts 'Local owner ready'")
    compose('exec', '-T', 'backend', 'bundle', 'exec', 'rails', 'runner', '-', input=ruby, text=True)
    print(f"Local leader: http://127.0.0.1:{config['BETA_LOCAL_WEB_PORT']}")
    print(f"Login: {config['BETA_LOCAL_OWNER_EMAIL']}; password in {ENV}")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        raise urllib.error.HTTPError(request.full_url, code, 'Redirect refused', headers, file_pointer)


class API:
    def __init__(self, base):
        self.base = base
        self.headers = {'Content-Type': 'application/json', 'Accept': 'application/json'}

    def call(self, method, path, body=None):
        request = urllib.request.Request(self.base + path, method=method, headers=self.headers,
                                         data=None if body is None else json.dumps(body).encode())
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
                for key in ('access-token', 'client', 'uid'):
                    if response.headers.get(key):
                        self.headers[key] = response.headers[key]
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise SystemExit(f'{method} {self.base}{path}: HTTP {error.code}; no credentials printed.') from None

    def login(self, email, password):
        self.call('POST', '/users/sign_in', {'email': email, 'password': password})


def pair(leader_id):
    config = settings()
    local = API(f"http://127.0.0.1:{config['BETA_LOCAL_API_PORT']}")
    local.login(config['BETA_LOCAL_OWNER_EMAIL'], config['BETA_LOCAL_OWNER_PASSWORD'])
    leader = local.call('GET', f'/tournaments/{leader_id}')
    if leader.get('read_only_mode'):
        raise SystemExit('Select a writable local leader tournament.')
    if PAIR.exists():
        state = json.loads(PAIR.read_text())
        if state['leader_id'] != leader_id:
            raise SystemExit('Already paired with another tournament; keep its state or archive pair.json explicitly.')
    else:
        if leader.get('sync_target_url'):
            raise SystemExit('Leader already has a sync target; refusing to replace it without saved pairing state.')
        remote = API(BETA_API)
        remote.login(input('Beta owner email: ').strip(), getpass.getpass('Beta owner password: '))
        token = secrets.token_hex(32)
        follower = remote.call('POST', '/tournaments', {
            'name': f"Local beta test: {leader['name']}", 'public': False,
            'read_only_mode': True, 'sync_auth_token': token,
        })
        state = {'leader_id': leader_id, 'follower_id': follower['id'], 'sync_token': token}
        # Persist before configuring the local side so retries reuse the follower.
        private_write(PAIR, json.dumps(state, indent=2) + '\n')
    target = f"{BETA_API}/tournaments/{state['follower_id']}/sync_state"
    if leader.get('sync_target_url') not in (None, '', target):
        raise SystemExit('Leader sync target changed; refusing to overwrite it.')
    local.call('PATCH', f'/tournaments/{leader_id}', {'sync_target_url': target, 'sync_auth_token': state['sync_token']})
    local.call('POST', f'/tournaments/{leader_id}/test_sync')
    print(f"Paired. Remote follower: https://beta.turnie.re/t/{state['follower_id']}")
    print('Provision beta player memberships as documented before submitting proposals.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['init', 'up', 'down', 'status', 'logs', 'pair', 'config'])
    parser.add_argument('--no-build', action='store_true')
    parser.add_argument('--leader-id', type=int)
    args = parser.parse_args()
    if args.action == 'init':
        initialize()
    elif args.action == 'up':
        up(not args.no_build)
    elif args.action == 'pair':
        if not args.leader_id or args.leader_id < 1:
            parser.error('pair requires --leader-id with a positive ID')
        pair(args.leader_id)
    else:
        compose(*{'down': ['down'], 'status': ['ps'], 'logs': ['logs', '--tail=100', '-f'],
                  'config': ['config', '--quiet']}[args.action])


if __name__ == '__main__':
    main()
