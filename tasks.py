from invoke import task

import os
import re
import shlex
import signal
import subprocess
import time
import urllib.request
import urllib.error
from urllib.parse import urlparse
from pathlib import Path


SERVER_HOST = "0.0.0.0"
SERVER_PORT = "3000"
TEST_BASE_URL = f"http://127.0.0.1:{SERVER_PORT}"
BLACKBOX_BASE_URL = TEST_BASE_URL
BLACKBOX_INTERNAL_BASE_URL = "http://app:3000"
BLACKBOX_SOURCE_INTERNAL_BASE_URL = "http://source-app:3000"
BLACKBOX_FOLLOWER_INTERNAL_BASE_URL = "http://follower-app:3000"
BLACKBOX_SOURCE_HOST_PORT = "3002"
BLACKBOX_FOLLOWER_HOST_PORT = "3003"

E2E_EMAIL = "e2e@example.com"
E2E_PASSWORD = "password123"
E2E_USERNAME = "e2e-user"
E2E_ALT_EMAIL = "e2e-alt@example.com"
E2E_ALT_PASSWORD = "password123"
E2E_ALT_USERNAME = "e2e-alt-user"

PRODUCTION_TAG = "registry.gitlab.com/turniere/turniere-backend/production/commits:local"
TEST_TAG = "registry.gitlab.com/turniere/turniere-backend/test/commits:local"
BLACKBOX_COMPOSE_FILE = "docker-compose.blackbox.yml"
BLACKBOX_PROJECT = "turniere-blackbox"
BLACKBOX_FOLLOW_COMPOSE_FILE = "docker-compose.blackbox-follow.yml"
BLACKBOX_FOLLOW_PROJECT = "turniere-blackbox-follow"
BLACKBOX_POSTGRES_IMAGE = "postgres:16"
BLACKBOX_DB_NAME = "turniere_blackbox"
BLACKBOX_SOURCE_DB_NAME = "turniere_source_blackbox"
BLACKBOX_FOLLOWER_DB_NAME = "turniere_follower_blackbox"
BLACKBOX_DB_USER = "turniere"
BLACKBOX_DB_PASSWORD = "turniere"
BLACKBOX_SECRET_KEY_BASE = "turniere-blackbox-secret-key-base-please-change-in-real-prod"
BLACKBOX_MAILGUN_API_KEY = "blackbox-test-api-key"
BLACKBOX_MAILGUN_DOMAIN = "blackbox.example.com"
SPEC_ROOT = Path("spec")
E2E_SPEC_ROOT = SPEC_ROOT / "e2e" / "http"
BUNDLER_VERSION = Path("Gemfile.lock").read_text(encoding="utf-8").split("BUNDLED WITH", 1)[1].strip().splitlines()[-1].strip()
ROOT = Path(__file__).resolve().parent
DB_DIR = ROOT / "db"


def _env(**overrides):
    env = os.environ.copy()
    env.update({key: str(value) for key, value in overrides.items()})
    return env


def _rails_env(env=None):
    return str(env or os.environ.get("RAILS_ENV", "development"))


def _sqlite_db_path(env=None):
    rails_env = _rails_env(env)

    if rails_env == "development":
        return DB_DIR / "development.sqlite3"
    if rails_env == "test":
        return DB_DIR / "test.sqlite3"

    return None


def _delete_sqlite_db(env=None):
    db_path = _sqlite_db_path(env)
    if db_path is None:
        return None

    for suffix in ("", "-shm", "-wal", ".journal"):
        candidate = Path(f"{db_path}{suffix}")
        if candidate.exists():
            candidate.unlink()

    return db_path


def _bundle_command(*parts):
    return " ".join(["bundle", f"_{BUNDLER_VERSION}_", *parts])


def _bundle_exec(*parts):
    return _bundle_command("exec", *parts)


def _wait_for_http(base_url=TEST_BASE_URL, timeout=60):
    deadline = time.time() + timeout
    healthz_url = f"{base_url}/healthz"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    last_error = None

    while time.time() < deadline:
        try:
            with opener.open(healthz_url) as response:
                if response.status == 200:
                    return
                last_error = f"unexpected status {response.status}"
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            last_error = f"http {error.code}: {body}"
            time.sleep(0.5)
        except Exception as error:
            last_error = repr(error)
            time.sleep(0.5)

    detail = f" last error: {last_error}" if last_error else ""
    raise RuntimeError(f"healthcheck did not become ready within {timeout}s: {healthz_url}.{detail}")


def _docker_compose_cmd(project_name=BLACKBOX_PROJECT, compose_file=BLACKBOX_COMPOSE_FILE):
    return ["docker-compose", "-p", project_name, "-f", compose_file]


def _run_subprocess(command, env=None, capture_output=False, check=True):
    completed = subprocess.run(
        command,
        env=env,
        text=True,
        capture_output=capture_output,
        check=False,
    )
    if check and completed.returncode != 0:
        raise subprocess.CalledProcessError(
            completed.returncode,
            command,
            output=completed.stdout,
            stderr=completed.stderr,
        )
    return completed


def _stream_subprocess(command, env=None, check=True):
    process = subprocess.Popen(
        command,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )

    output_chunks = []
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="", flush=True)
        output_chunks.append(line)

    process.wait()
    output = "".join(output_chunks)

    if check and process.returncode != 0:
        raise subprocess.CalledProcessError(process.returncode, command, output=output, stderr=None)

    return subprocess.CompletedProcess(command, process.returncode, stdout=output, stderr="")


def _compose_env(
    host_port=SERVER_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
    expect_profiling="true",
):
    return _env(
        TURNIERE_BLACKBOX_HOST_PORT=host_port,
        TURNIERE_BLACKBOX_APP_IMAGE=app_image,
        TURNIERE_BLACKBOX_RUNNER_IMAGE=runner_image,
        TURNIERE_BLACKBOX_POSTGRES_IMAGE=postgres_image,
        TURNIERE_BLACKBOX_POSTGRES_DB=BLACKBOX_DB_NAME,
        TURNIERE_BLACKBOX_POSTGRES_USER=BLACKBOX_DB_USER,
        TURNIERE_BLACKBOX_POSTGRES_PASSWORD=BLACKBOX_DB_PASSWORD,
        TURNIERE_BLACKBOX_SECRET_KEY_BASE=BLACKBOX_SECRET_KEY_BASE,
        TURNIERE_BLACKBOX_MAILGUN_API_KEY=BLACKBOX_MAILGUN_API_KEY,
        TURNIERE_BLACKBOX_MAILGUN_DOMAIN=BLACKBOX_MAILGUN_DOMAIN,
        TURNIERE_E2E_BASE_URL=BLACKBOX_INTERNAL_BASE_URL,
        TURNIERE_E2E_EXPECT_PROFILING=expect_profiling,
        TURNIERE_E2E_EMAIL=E2E_EMAIL,
        TURNIERE_E2E_PASSWORD=E2E_PASSWORD,
        TURNIERE_E2E_USERNAME=E2E_USERNAME,
        TURNIERE_E2E_ALT_EMAIL=E2E_ALT_EMAIL,
        TURNIERE_E2E_ALT_PASSWORD=E2E_ALT_PASSWORD,
        TURNIERE_E2E_ALT_USERNAME=E2E_ALT_USERNAME,
    )


def _follow_compose_env(
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    return _env(
        TURNIERE_BLACKBOX_SOURCE_HOST_PORT=source_host_port,
        TURNIERE_BLACKBOX_FOLLOWER_HOST_PORT=follower_host_port,
        TURNIERE_BLACKBOX_APP_IMAGE=app_image,
        TURNIERE_BLACKBOX_RUNNER_IMAGE=runner_image,
        TURNIERE_BLACKBOX_POSTGRES_IMAGE=postgres_image,
        TURNIERE_BLACKBOX_SOURCE_POSTGRES_DB=BLACKBOX_SOURCE_DB_NAME,
        TURNIERE_BLACKBOX_FOLLOWER_POSTGRES_DB=BLACKBOX_FOLLOWER_DB_NAME,
        TURNIERE_BLACKBOX_POSTGRES_USER=BLACKBOX_DB_USER,
        TURNIERE_BLACKBOX_POSTGRES_PASSWORD=BLACKBOX_DB_PASSWORD,
        TURNIERE_BLACKBOX_SECRET_KEY_BASE=BLACKBOX_SECRET_KEY_BASE,
        TURNIERE_BLACKBOX_MAILGUN_API_KEY=BLACKBOX_MAILGUN_API_KEY,
        TURNIERE_BLACKBOX_MAILGUN_DOMAIN=BLACKBOX_MAILGUN_DOMAIN,
        TURNIERE_SOURCE_E2E_BASE_URL=BLACKBOX_SOURCE_INTERNAL_BASE_URL,
        TURNIERE_FOLLOWER_E2E_BASE_URL=BLACKBOX_FOLLOWER_INTERNAL_BASE_URL,
        TURNIERE_E2E_EMAIL=E2E_EMAIL,
        TURNIERE_E2E_PASSWORD=E2E_PASSWORD,
        TURNIERE_E2E_USERNAME=E2E_USERNAME,
        TURNIERE_E2E_ALT_EMAIL=E2E_ALT_EMAIL,
        TURNIERE_E2E_ALT_PASSWORD=E2E_ALT_PASSWORD,
        TURNIERE_E2E_ALT_USERNAME=E2E_ALT_USERNAME,
    )


def _format_command(command):
    return " ".join(shlex.quote(part) for part in command)


def _rspec_command(*paths):
    command = ["bundle", "exec", "rspec", *paths]
    if os.environ.get("CI"):
        command.extend(["--format", "documentation", "--no-color"])
    else:
        command.extend(["--format", "progress", "--tty"])
    return command


def _compose_run(compose_args, env, capture_output=False, check=True, project_name=BLACKBOX_PROJECT, compose_file=BLACKBOX_COMPOSE_FILE):
    command = _docker_compose_cmd(project_name=project_name, compose_file=compose_file) + compose_args
    return _run_subprocess(command, env=env, capture_output=capture_output, check=check)


def _print_header(title):
    print(f"\n== {title} ==", flush=True)


def _blackbox_network_smoke(c, target_base_url):
    command = [
        "ruby",
        "-rnet/http",
        "-ruri",
        "-e",
        (
            "uri = URI.parse(ARGV.fetch(0) + '/healthz'); "
            "res = Net::HTTP.get_response(uri); "
            "abort(\"healthcheck #{res.code}\") unless res.is_a?(Net::HTTPSuccess); "
            "puts(\"network smoke ok #{uri}\")"
        ),
        target_base_url,
    ]
    c.run(_format_command(command), pty=True)


def _blackbox_service_to_service_smoke(c, env, source_label, target_base_url):
    command = [
        "bundle",
        "exec",
        "rails",
        "runner",
        (
            "require 'net/http'; "
            "require 'uri'; "
            "uri = URI.parse(ENV.fetch('BLACKBOX_SMOKE_TARGET_URL') + '/healthz'); "
            "Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 3, read_timeout: 3) do |http| "
            "res = http.get(uri.request_uri); "
            "abort(\"service smoke #{res.code}\") unless res.is_a?(Net::HTTPSuccess); "
            "puts(\"service smoke ok #{ENV.fetch('BLACKBOX_SMOKE_SOURCE_LABEL')} -> #{uri}\"); "
            "end"
        ),
    ]
    smoke_env = env.copy()
    smoke_env.update(
        BLACKBOX_SMOKE_SOURCE_LABEL=source_label,
        BLACKBOX_SMOKE_TARGET_URL=target_base_url,
    )
    c.run(_format_command(command), env=smoke_env, pty=True)


def _bootstrap_user_command(email, password, username):
    return (
        f"{_bundle_exec('rails', 'runner')} "
        f"\"user = User.find_or_initialize_by(email: '{email}'); "
        f"user.username = '{username}'; "
        f"user.password = '{password}'; "
        f"user.password_confirmation = '{password}'; "
        "user.confirmed_at = Time.current; "
        "user.uid = user.email; "
        "user.provider = 'email'; "
        "user.save!\""
    )


def _parse_rspec_report(output):
    summary_match = re.search(r"(\d+)\s+examples?,\s+(\d+)\s+failures?(?:,\s+(\d+)\s+pending)?", output)
    failed_examples = re.findall(r"^\s*rspec\s+(.+)$", output, flags=re.MULTILINE)

    return {
        "examples": int(summary_match.group(1)) if summary_match else None,
        "failures": int(summary_match.group(2)) if summary_match else None,
        "pending": int(summary_match.group(3)) if summary_match and summary_match.group(3) else 0,
        "failed_examples": failed_examples,
    }


def _print_rspec_report(report):
    examples = report["examples"]
    failures = report["failures"]
    pending = report["pending"]
    failed_examples = report["failed_examples"]

    if examples is None or failures is None:
        print("Rerun summary could not be parsed from the RSpec output.")
        return

    print(f"Examples: {examples}")
    print(f"Failures: {failures}")
    print(f"Pending: {pending}")
    if failed_examples:
        print("Failed examples:")
        for example in failed_examples:
            print(f"- {example}")


def _print_service_logs(env, service, tail=120):
    _print_header(f"{service} logs (last {tail} lines)")
    logs = _compose_run(["logs", "--tail", str(tail), service], env=env, capture_output=True, check=False)
    output = logs.stdout or logs.stderr or "<no logs>"
    print(output.rstrip())


def _spec_files():
    return sorted(
        path for path in SPEC_ROOT.rglob("*_spec.rb")
        if not path.is_relative_to(E2E_SPEC_ROOT)
    )


def _spec_weight(path):
    return sum(1 for _ in path.open("r", encoding="utf-8"))


def _spec_shards(node_total):
    if node_total <= 0:
        raise ValueError("node_total must be positive")

    shards = [{"weight": 0, "files": []} for _ in range(node_total)]
    weighted_files = sorted(
        ((path, _spec_weight(path)) for path in _spec_files()),
        key=lambda item: (-item[1], str(item[0])),
    )

    for path, weight in weighted_files:
        shard = min(shards, key=lambda item: (item["weight"], len(item["files"])))
        shard["files"].append(path)
        shard["weight"] += weight

    return shards


def _shared_production_env():
    return _env(
        RAILS_ENV="production",
        POSTGRES_URL=os.environ.get(
            "POSTGRES_URL",
            f"postgres://{BLACKBOX_DB_USER}:{BLACKBOX_DB_PASSWORD}@postgres:5432/{BLACKBOX_DB_NAME}",
        ),
        POSTGRES_USERNAME=os.environ.get("POSTGRES_USERNAME", BLACKBOX_DB_USER),
        POSTGRES_PASSWORD=os.environ.get("POSTGRES_PASSWORD", BLACKBOX_DB_PASSWORD),
        SECRET_KEY_BASE=os.environ.get("SECRET_KEY_BASE", BLACKBOX_SECRET_KEY_BASE),
        MAILGUN_API_KEY=os.environ.get("MAILGUN_API_KEY", BLACKBOX_MAILGUN_API_KEY),
        MAILGUN_DOMAIN=os.environ.get("MAILGUN_DOMAIN", BLACKBOX_MAILGUN_DOMAIN),
        RAILS_LOG_TO_STDOUT=os.environ.get("RAILS_LOG_TO_STDOUT", "1"),
        RAILS_SERVE_STATIC_FILES=os.environ.get("RAILS_SERVE_STATIC_FILES", "1"),
    )


def _production_env_for(db_host, db_name):
    return _env(
        RAILS_ENV="production",
        POSTGRES_URL=f"postgres://{BLACKBOX_DB_USER}:{BLACKBOX_DB_PASSWORD}@{db_host}:5432/{db_name}",
        POSTGRES_USERNAME=BLACKBOX_DB_USER,
        POSTGRES_PASSWORD=BLACKBOX_DB_PASSWORD,
        SECRET_KEY_BASE=BLACKBOX_SECRET_KEY_BASE,
        MAILGUN_API_KEY=BLACKBOX_MAILGUN_API_KEY,
        MAILGUN_DOMAIN=BLACKBOX_MAILGUN_DOMAIN,
        RAILS_LOG_TO_STDOUT="1",
        RAILS_SERVE_STATIC_FILES="1",
    )


def _run_blackbox_rspec(base_url, email, password, username, alt_email=E2E_ALT_EMAIL, alt_password=E2E_ALT_PASSWORD,
                        alt_username=E2E_ALT_USERNAME, spec_path="spec/e2e/http", extra_env=None):
    env = _env(
        TURNIERE_E2E_BASE_URL=base_url,
        TURNIERE_E2E_EXPECT_PROFILING="false",
        TURNIERE_E2E_EMAIL=email,
        TURNIERE_E2E_PASSWORD=password,
        TURNIERE_E2E_USERNAME=username,
        TURNIERE_E2E_ALT_EMAIL=alt_email,
        TURNIERE_E2E_ALT_PASSWORD=alt_password,
        TURNIERE_E2E_ALT_USERNAME=alt_username,
    )
    if extra_env:
        env.update(extra_env)
    command = _rspec_command(spec_path)
    print(_format_command(command), flush=True)
    result = _stream_subprocess(command, env=env, check=False)

    report = _parse_rspec_report(f"{result.stdout}\n{result.stderr}")
    _print_header("Blackbox report")
    _print_rspec_report(report)

    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            result.args,
            output=result.stdout,
            stderr=result.stderr,
        )


def _start_server(command, env, log_path="/tmp/turniere-e2e-server.log"):
    log_handle = open(log_path, "w")
    process = subprocess.Popen(
        ["/bin/sh", "-lc", command],
        env=env,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        preexec_fn=os.setsid,
    )
    return process, log_handle


def _start_test_server(host=SERVER_HOST, port=SERVER_PORT):
    return _start_server(
        f"{_bundle_exec('rails', 's')} -e test -b {host} -p {port}",
        _env(),
    )


def _stop_process(process, log_handle):
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except ProcessLookupError:
        pass
    finally:
        log_handle.close()


def _bootstrap_blackbox_users(c, env, email, password, username, alt_email, alt_password, alt_username):
    c.run(
        _bootstrap_user_command(email, password, username),
        env=env,
        pty=True,
    )
    c.run(
        _bootstrap_user_command(alt_email, alt_password, alt_username),
        env=env,
        pty=True,
    )


@task
def setup(c):
    """Install the pinned Bundler and local backend gem dependencies."""
    install_bundler = c.run(
        f"gem list -i bundler -v {BUNDLER_VERSION}",
        warn=True,
        hide=True,
    )
    if not install_bundler.ok:
        c.run(f"gem install bundler:{BUNDLER_VERSION}", pty=True)

    c.run(f"{_bundle_command('config', 'set', 'without', 'production')}", pty=True)
    c.run(f"{_bundle_command('config', 'set', 'with', 'development test')}", pty=True)
    c.run(_bundle_command("install"), pty=True)


@task(name="db-migrate")
def db_migrate(c, env=None):
    """Run database migrations locally."""
    c.run(f"RAILS_ENV={_rails_env(env)} {_bundle_exec('rails', 'db:migrate')}", pty=True)


@task(name="db-reset")
def db_reset(c, env="test"):
    """Delete the local SQLite database for the requested non-production Rails env."""
    rails_env = _rails_env(env)
    if rails_env == "production":
        raise ValueError("db-reset refuses to run in production")

    deleted_path = _delete_sqlite_db(rails_env)
    if deleted_path is None:
        print(f"No local SQLite database configured for RAILS_ENV={rails_env}. Nothing deleted.")
        return

    print(f"Deleted {deleted_path}")


@task
def server(c, host=SERVER_HOST, port=SERVER_PORT, env=None):
    """Start the backend locally in development."""
    c.run(f"RAILS_ENV={_rails_env(env)} {_bundle_exec('rails', 's')} -b {host} -p {port}", pty=True)


@task(name="start-local")
def start_local(c, host=SERVER_HOST, port=SERVER_PORT, bootstrap_user=False):
    """Install local deps if needed, migrate the dev database, and start the server."""
    setup(c)
    db_migrate(c, env="development")
    if bootstrap_user:
        bootstrap_dev_user(c)
    server(c, host=host, port=port, env="development")


@task(name="server-test")
def server_test(c, host=SERVER_HOST, port=SERVER_PORT):
    """Start the backend locally in test mode."""
    server(c, host=host, port=port, env="test")


@task(name="start-test-local")
def start_test_local(
    c,
    host=SERVER_HOST,
    port=SERVER_PORT,
    bootstrap_user=True,
    reset_db=True,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    alt_email=E2E_ALT_EMAIL,
    alt_password=E2E_ALT_PASSWORD,
    alt_username=E2E_ALT_USERNAME,
):
    """Install deps, recreate the local test DB, bootstrap HTTP E2E users, and start the test server."""
    setup(c)
    if reset_db:
        db_reset(c, env="test")
    db_migrate(c, env="test")
    if bootstrap_user:
        bootstrap_e2e_user(c, email=email, password=password, username=username)
        bootstrap_e2e_user(c, email=alt_email, password=alt_password, username=alt_username)
    server(c, host=host, port=port, env="test")


@task
def test(c):
    """Run the normal RSpec suite."""
    _stream_subprocess(_rspec_command(), env=_env())


@task(name="test-shard")
def test_shard(c, node_index=1, node_total=8, dry_run=False):
    """Run one deterministic shard of the non-E2E RSpec suite."""
    node_index = int(node_index)
    node_total = int(node_total)

    if node_index < 1 or node_index > node_total:
        raise ValueError(f"node_index must be between 1 and {node_total}, got {node_index}")

    shards = _spec_shards(node_total)
    shard = shards[node_index - 1]
    files = [str(path) for path in shard["files"]]

    _print_header(f"RSpec shard {node_index}/{node_total}")
    print(f"Files: {len(files)}")
    print(f"Estimated weight: {shard['weight']}")
    if files:
        print("Included specs:")
        for path in files:
            print(f"- {path}")
    else:
        print("No spec files assigned to this shard.")

    if dry_run:
        return

    if not files:
        return

    _stream_subprocess(
        _rspec_command("--require", "./spec/rails_helper", *files),
        env=_env(),
    )


@task
def lint(c):
    """Run RuboCop."""
    c.run(_bundle_exec("rubocop"), pty=True)


@task(name="bootstrap-dev-user")
def bootstrap_dev_user(c, email=E2E_EMAIL, password=E2E_PASSWORD, username=E2E_USERNAME):
    """Create or update a confirmed local development user."""
    command = (
        f"RAILS_ENV=development {_bundle_exec('rails', 'runner')} "
        f"\"user = User.find_or_initialize_by(email: '{email}'); "
        f"user.username = '{username}'; "
        f"user.password = '{password}'; "
        f"user.password_confirmation = '{password}'; "
        "user.confirmed_at = Time.current; "
        "user.uid = user.email; "
        "user.provider = 'email'; "
        "user.save!\""
    )
    c.run(command, pty=True)


@task(name="bootstrap-e2e-user")
def bootstrap_e2e_user(c, email=E2E_EMAIL, password=E2E_PASSWORD, username=E2E_USERNAME):
    """Create or update the confirmed HTTP E2E user in test env."""
    command = (
        f"RAILS_ENV=test {_bundle_exec('rails', 'runner')} "
        f"\"user = User.find_or_initialize_by(email: '{email}'); "
        f"user.username = '{username}'; "
        f"user.password = '{password}'; "
        f"user.password_confirmation = '{password}'; "
        "user.confirmed_at = Time.current; "
        "user.uid = user.email; "
        "user.provider = 'email'; "
        "user.save!\""
    )
    c.run(command, pty=True)


@task(name="test-http-e2e")
def test_http_e2e(
    c,
    base_url=TEST_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    alt_email=E2E_ALT_EMAIL,
    alt_password=E2E_ALT_PASSWORD,
    alt_username=E2E_ALT_USERNAME,
):
    """Run HTTP E2E specs against an already running backend."""
    c.run(
        f"{_bundle_exec('rspec')} spec/e2e/http",
        env=_env(
            TURNIERE_E2E_BASE_URL=base_url,
            TURNIERE_E2E_EMAIL=email,
            TURNIERE_E2E_PASSWORD=password,
            TURNIERE_E2E_USERNAME=username,
            TURNIERE_E2E_ALT_EMAIL=alt_email,
            TURNIERE_E2E_ALT_PASSWORD=alt_password,
            TURNIERE_E2E_ALT_USERNAME=alt_username,
        ),
        pty=True,
    )


@task(name="verify-http")
def verify_http(
    c,
    base_url=TEST_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    alt_email=E2E_ALT_EMAIL,
    alt_password=E2E_ALT_PASSWORD,
    alt_username=E2E_ALT_USERNAME,
    reset_db=True,
):
    """Boot a local test server, then run the HTTP E2E suite against it."""
    if reset_db:
        db_reset(c, env="test")
    db_migrate(c, env="test")
    bootstrap_e2e_user(c, email=email, password=password, username=username)
    bootstrap_e2e_user(c, email=alt_email, password=alt_password, username=alt_username)
    parsed_base_url = urlparse(base_url)
    server_host = parsed_base_url.hostname or "127.0.0.1"
    server_port = parsed_base_url.port or 3000

    process, log_handle = _start_test_server(host=server_host, port=server_port)
    try:
        _wait_for_http(base_url=base_url, timeout=60)
        test_http_e2e(
            c,
            base_url=base_url,
            email=email,
            password=password,
            username=username,
            alt_email=alt_email,
            alt_password=alt_password,
            alt_username=alt_username,
        )
    finally:
        _stop_process(process, log_handle)


@task
def verify(c):
    """Run lint, normal specs, and HTTP E2E locally."""
    lint(c)
    test(c)
    verify_http(c)


@task(name="scenario-main-usecase")
def scenario_main_usecase(
    c,
    base_url=TEST_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    stop_at="final_finish_attempted",
):
    """Materialize the main 4x4 group-stage scenario over HTTP."""
    c.run(
        f"ruby script/e2e_scenarios.rb group_stage_main_usecase --stop-at {stop_at}",
        env=_env(
            TURNIERE_E2E_BASE_URL=base_url,
            TURNIERE_E2E_EMAIL=email,
            TURNIERE_E2E_PASSWORD=password,
            TURNIERE_E2E_USERNAME=username,
        ),
        pty=True,
    )


@task(name="scenario-intermediate")
def scenario_intermediate(
    c,
    base_url=TEST_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    stop_at="final_finish_attempted",
):
    """Materialize the 3-group intermediate-round scenario over HTTP."""
    c.run(
        f"ruby script/e2e_scenarios.rb group_stage_intermediate_round --stop-at {stop_at}",
        env=_env(
            TURNIERE_E2E_BASE_URL=base_url,
            TURNIERE_E2E_EMAIL=email,
            TURNIERE_E2E_PASSWORD=password,
            TURNIERE_E2E_USERNAME=username,
        ),
        pty=True,
    )


@task(name="scenario-playoff")
def scenario_playoff(
    c,
    team_count=8,
    base_url=TEST_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    stop_at="completed",
):
    """Materialize a playoff-only scenario over HTTP."""
    c.run(
        f"ruby script/e2e_scenarios.rb playoff_only --team-count {team_count} --stop-at {stop_at}",
        env=_env(
            TURNIERE_E2E_BASE_URL=base_url,
            TURNIERE_E2E_EMAIL=email,
            TURNIERE_E2E_PASSWORD=password,
            TURNIERE_E2E_USERNAME=username,
        ),
        pty=True,
    )


@task(name="scenario-render-profile")
def scenario_render_profile(
    c,
    group_count=8,
    teams_per_group=4,
    playoff_teams_amount=8,
    base_url=TEST_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    stop_at="profiled_show",
):
    """Materialize a group-stage tournament over HTTP and print tournament show profiling."""
    c.run(
        "ruby script/e2e_scenarios.rb group_stage_render_profile "
        f"--group-count {group_count} "
        f"--teams-per-group {teams_per_group} "
        f"--playoff-teams-amount {playoff_teams_amount} "
        f"--stop-at {stop_at}",
        env=_env(
            TURNIERE_E2E_BASE_URL=base_url,
            TURNIERE_E2E_EMAIL=email,
            TURNIERE_E2E_PASSWORD=password,
            TURNIERE_E2E_USERNAME=username,
        ),
        pty=True,
    )


@task(name="docker-build-production")
def docker_build_production(c, tag=PRODUCTION_TAG):
    """Build the production Docker image."""
    c.run(f"docker build -t {tag} -f docker/production/Dockerfile .", pty=True)


@task(name="docker-build-test")
def docker_build_test(c, tag=TEST_TAG):
    """Build the test Docker image."""
    c.run(f"docker build --build-arg base_commit=local -t {tag} -f docker/test/Dockerfile .", pty=True)


@task(name="docker-build-all")
def docker_build_all(c):
    """Build the production and test Docker images."""
    docker_build_production(c)
    docker_build_test(c)


@task(name="docker-blackbox-up")
def docker_blackbox_up(
    c,
    host_port=SERVER_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
    build=True,
):
    """Build the Docker images, then boot Postgres and the production app for blackbox testing."""
    if build:
        docker_build_all(c)

    env = _compose_env(
        host_port=host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
        expect_profiling="false",
    )

    _print_header("Starting production blackbox stack")
    _compose_run(["down", "-v", "--remove-orphans"], env=env, check=False)
    _compose_run(["up", "-d", "postgres", "app"], env=env)

    base_url = f"http://127.0.0.1:{host_port}"
    _print_header(f"Waiting for app healthcheck at {base_url}")
    _wait_for_http(base_url=base_url, timeout=120)

    _print_header("Bootstrapping confirmed E2E user")
    for bootstrap_email, bootstrap_password, bootstrap_username in (
        (E2E_EMAIL, E2E_PASSWORD, E2E_USERNAME),
        (E2E_ALT_EMAIL, E2E_ALT_PASSWORD, E2E_ALT_USERNAME),
    ):
        bootstrap = _compose_run(
            ["exec", "-T", "app", "bash", "-lc", _bootstrap_user_command(bootstrap_email, bootstrap_password, bootstrap_username)],
            env=env,
            capture_output=True,
            check=False,
        )
        if bootstrap.returncode != 0:
            print(bootstrap.stdout or "", end="")
            print(bootstrap.stderr or "", end="")
            raise subprocess.CalledProcessError(
                bootstrap.returncode,
                bootstrap.args,
                output=bootstrap.stdout,
                stderr=bootstrap.stderr,
            )

    print("Production app is ready for blackbox E2E.")


@task(name="docker-blackbox-down")
def docker_blackbox_down(
    c,
    host_port=SERVER_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Stop and remove the production blackbox stack."""
    env = _compose_env(
        host_port=host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )
    _compose_run(["down", "-v", "--remove-orphans"], env=env, check=False)


@task(name="docker-blackbox-test")
def docker_blackbox_test(
    c,
    host_port=SERVER_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Run the HTTP E2E suite against the running production blackbox stack."""
    env = _compose_env(
        host_port=host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
        expect_profiling="false",
    )

    _print_header("Running HTTP E2E against production image")
    command = [
        "run",
        "--rm",
        "e2e",
        "bundle",
        "exec",
        "rspec",
        "spec/e2e/http",
        "--format",
        "documentation",
    ]
    print(_format_command(_docker_compose_cmd() + command))
    result = _compose_run(command, env=env, capture_output=True, check=False)
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip())

    report = _parse_rspec_report(f"{result.stdout}\n{result.stderr}")
    _print_header("Blackbox report")
    _print_rspec_report(report)

    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            result.args,
            output=result.stdout,
            stderr=result.stderr,
        )


@task(name="docker-blackbox-follow-up")
def docker_blackbox_follow_up(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
    build=True,
):
    """Build Docker images, then boot source/follower Postgres and production apps for follower blackbox testing."""
    if build:
        docker_build_all(c)

    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    _print_header("Starting follower production blackbox stack")
    _compose_run(
        ["down", "-v", "--remove-orphans"],
        env=env,
        check=False,
        project_name=BLACKBOX_FOLLOW_PROJECT,
        compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
    )
    _compose_run(
        ["up", "-d", "source-postgres", "follower-postgres", "source-app", "follower-app"],
        env=env,
        project_name=BLACKBOX_FOLLOW_PROJECT,
        compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
    )

    source_base_url = f"http://127.0.0.1:{source_host_port}"
    follower_base_url = f"http://127.0.0.1:{follower_host_port}"
    _print_header(f"Waiting for source app healthcheck at {source_base_url}")
    _wait_for_http(base_url=source_base_url, timeout=120)

    _print_header(f"Waiting for follower app healthcheck at {follower_base_url}")
    _wait_for_http(base_url=follower_base_url, timeout=120)

    print("Follower production apps ready for blackbox E2E.")


@task(name="docker-blackbox-follow-manual-up")
def docker_blackbox_follow_manual_up(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
    build=True,
):
    """Boot local leader/follower production setup for manual testing and print next steps."""
    docker_blackbox_follow_up(
        c,
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
        build=build,
    )

    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    _print_header("Running source production database migrations")
    _compose_run(
        ["exec", "-T", "source-app", "bash", "-lc", "bundle exec rails db:migrate"],
        env=env,
        project_name=BLACKBOX_FOLLOW_PROJECT,
        compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
    )

    _print_header("Running follower production database migrations")
    _compose_run(
        ["exec", "-T", "follower-app", "bash", "-lc", "bundle exec rails db:migrate"],
        env=env,
        project_name=BLACKBOX_FOLLOW_PROJECT,
        compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
    )

    _print_header("Bootstrapping confirmed E2E users on source and follower")
    docker_blackbox_follow_bootstrap_users(
        c,
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    source_base_url = f"http://127.0.0.1:{source_host_port}"
    follower_base_url = f"http://127.0.0.1:{follower_host_port}"
    _print_header("Leader/follower manual setup ready")
    print(f"Leader URL:   {source_base_url}")
    print(f"Follower URL: {follower_base_url}")
    print(f"E2E owner email: {E2E_EMAIL}")
    print(f"E2E owner password: {E2E_PASSWORD}")
    print("Next steps:")
    print("1. Create read-only follower tournament on follower backend.")
    print("2. Create normal leader tournament on leader backend.")
    print("3. Configure leader sync_target_url to follower /sync_state endpoint with shared token.")
    print("4. Point frontend local leader view at leader URL and remote view at follower URL.")
    print("5. Tear down with: inv docker-blackbox-follow-down")


@task(name="docker-blackbox-follow-down")
def docker_blackbox_follow_down(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Stop and remove follower production blackbox stack."""
    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )
    _compose_run(
        ["down", "-v", "--remove-orphans"],
        env=env,
        check=False,
        project_name=BLACKBOX_FOLLOW_PROJECT,
        compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
    )


@task(name="docker-blackbox-follow-test")
def docker_blackbox_follow_test(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Run follower-sync HTTP E2E suite against running source/follower production blackbox stack."""
    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    _print_header("Running follower sync HTTP E2E against production images")
    command = [
        "run",
        "--rm",
        "e2e",
        "inv",
        "blackbox-follow-service",
    ]
    full_command = _docker_compose_cmd(project_name=BLACKBOX_FOLLOW_PROJECT, compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE) + command
    print(_format_command(full_command), flush=True)
    result = _run_subprocess_live(full_command, env=env, check=False)

    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            result.args,
            output=result.stdout,
            stderr=result.stderr,
        )


@task(name="docker-blackbox-follow-bootstrap-users")
def docker_blackbox_follow_bootstrap_users(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Bootstrap confirmed E2E users in local source/follower production blackbox DBs."""
    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    for app_service in ("source-app", "follower-app"):
        _print_header(f"Bootstrapping confirmed E2E users in {app_service}")
        for bootstrap_email, bootstrap_password, bootstrap_username in (
            (E2E_EMAIL, E2E_PASSWORD, E2E_USERNAME),
            (E2E_ALT_EMAIL, E2E_ALT_PASSWORD, E2E_ALT_USERNAME),
        ):
            bootstrap = _compose_run(
                ["exec", "-T", app_service, "bash", "-lc", _bootstrap_user_command(bootstrap_email, bootstrap_password, bootstrap_username)],
                env=env,
                capture_output=True,
                check=False,
                project_name=BLACKBOX_FOLLOW_PROJECT,
                compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
            )
            if bootstrap.returncode != 0:
                print(bootstrap.stdout or "", end="")
                print(bootstrap.stderr or "", end="")
                raise subprocess.CalledProcessError(
                    bootstrap.returncode,
                    bootstrap.args,
                    output=bootstrap.stdout,
                    stderr=bootstrap.stderr,
                )


@task(name="docker-blackbox-follow-debug-auth")
def docker_blackbox_follow_debug_auth(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Debug source/follower login and first authenticated create inside local follower blackbox runner."""
    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    script = """
require_relative 'e2e/lib/api_client'

def inspect_client(base_url)
  client = TurniereE2E::ApiClient.new(base_url: base_url)
  login = client.login!(email: ENV.fetch('TURNIERE_E2E_EMAIL'), password: ENV.fetch('TURNIERE_E2E_PASSWORD'))
  puts({ base_url: base_url, login_status: login[:status], login_headers: login[:headers].slice('access-token', 'client', 'uid', 'expiry', 'token-type', 'authorization'), authenticated: client.authenticated? }.inspect)

  create = client.post('/tournaments', body: {
    name: "Debug #{base_url}",
    description: 'Debug tournament',
    public: false,
    teams: [
      { name: 'One' },
      { name: 'Two' },
      { name: 'Three' },
      { name: 'Four' }
    ]
  })
  puts({ base_url: base_url, create_status: create[:status], create_json: create[:json], create_headers: create[:headers].slice('access-token', 'client', 'uid', 'expiry', 'token-type', 'authorization') }.inspect)
end

inspect_client(ENV.fetch('TURNIERE_SOURCE_E2E_BASE_URL'))
inspect_client(ENV.fetch('TURNIERE_FOLLOWER_E2E_BASE_URL'))
"""
    command = [
        "run",
        "--rm",
        "e2e",
        "ruby",
        "-e",
        script,
    ]
    print(_format_command(_docker_compose_cmd(project_name=BLACKBOX_FOLLOW_PROJECT, compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE) + command))
    result = _compose_run(
        command,
        env=env,
        capture_output=True,
        check=False,
        project_name=BLACKBOX_FOLLOW_PROJECT,
        compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
    )
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip())

    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            result.args,
            output=result.stdout,
            stderr=result.stderr,
        )


@task(name="docker-blackbox-follow-debug-seed")
def docker_blackbox_follow_debug_seed(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Debug repeated mixed tournament creation inside local follower blackbox runner."""
    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    script = """
require_relative 'e2e/lib/api_client'

def create_playoff_payload(name)
  {
    name: name,
    description: 'Debug playoff tournament',
    public: false,
    teams: [
      { name: 'One' },
      { name: 'Two' },
      { name: 'Three' },
      { name: 'Four' }
    ]
  }
end

def create_group_payload(name)
  {
    name: name,
    description: 'Debug group tournament',
    public: true,
    group_stage: true,
    playoff_teams_amount: 8,
    teams: 4.times.flat_map do |group_index|
      4.times.map do |seed_index|
        { name: "#{name}-G#{group_index + 1}-S#{seed_index + 1}", group: group_index }
      end
    end
  }
end

def inspect_seed(base_url)
  client = TurniereE2E::ApiClient.new(base_url: base_url)
  login = client.login!(email: ENV.fetch('TURNIERE_E2E_EMAIL'), password: ENV.fetch('TURNIERE_E2E_PASSWORD'))
  puts({ base_url: base_url, login_status: login[:status], authenticated: client.authenticated? }.inspect)

  [
    ['playoff-1', create_playoff_payload('Debug Playoff 1')],
    ['group-1', create_group_payload('Debug Group 1')],
    ['playoff-2', create_playoff_payload('Debug Playoff 2')],
    ['group-2', create_group_payload('Debug Group 2')]
  ].each do |label, payload|
    response = client.post('/tournaments', body: payload)
    puts({
      base_url: base_url,
      step: label,
      status: response[:status],
      json: response[:json],
      headers: response[:headers].slice('access-token', 'client', 'uid', 'expiry', 'token-type', 'authorization'),
      authenticated: client.authenticated?
    }.inspect)
  end
end

inspect_seed(ENV.fetch('TURNIERE_SOURCE_E2E_BASE_URL'))
inspect_seed(ENV.fetch('TURNIERE_FOLLOWER_E2E_BASE_URL'))
"""
    command = [
        "run",
        "--rm",
        "e2e",
        "ruby",
        "-e",
        script,
    ]
    print(_format_command(_docker_compose_cmd(project_name=BLACKBOX_FOLLOW_PROJECT, compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE) + command))
    result = _compose_run(
        command,
        env=env,
        capture_output=True,
        check=False,
        project_name=BLACKBOX_FOLLOW_PROJECT,
        compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
    )
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip())

    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            result.args,
            output=result.stdout,
            stderr=result.stderr,
        )


@task(name="docker-blackbox-follow-debug-group-create")
def docker_blackbox_follow_debug_group_create(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Debug single fresh-login group-stage tournament creation inside local follower blackbox runner."""
    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    script = """
require_relative 'e2e/lib/api_client'

def create_group_payload(name)
  {
    name: name,
    description: 'Debug group tournament',
    public: true,
    group_stage: true,
    playoff_teams_amount: 8,
    teams: 4.times.flat_map do |group_index|
      4.times.map do |seed_index|
        { name: "#{name}-G#{group_index + 1}-S#{seed_index + 1}", group: group_index }
      end
    end
  }
end

def inspect_group_create(base_url)
  client = TurniereE2E::ApiClient.new(base_url: base_url)
  login = client.login!(email: ENV.fetch('TURNIERE_E2E_EMAIL'), password: ENV.fetch('TURNIERE_E2E_PASSWORD'))
  puts({ base_url: base_url, login_status: login[:status], authenticated: client.authenticated? }.inspect)
  response = client.post('/tournaments', body: create_group_payload('Fresh Debug Group'))
  puts({ base_url: base_url, create_status: response[:status], create_json: response[:json], create_headers: response[:headers].slice('access-token', 'client', 'uid', 'expiry', 'token-type', 'authorization') }.inspect)
end

inspect_group_create(ENV.fetch('TURNIERE_SOURCE_E2E_BASE_URL'))
inspect_group_create(ENV.fetch('TURNIERE_FOLLOWER_E2E_BASE_URL'))
"""
    command = [
        "run",
        "--rm",
        "e2e",
        "ruby",
        "-e",
        script,
    ]
    print(_format_command(_docker_compose_cmd(project_name=BLACKBOX_FOLLOW_PROJECT, compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE) + command))
    result = _compose_run(
        command,
        env=env,
        capture_output=True,
        check=False,
        project_name=BLACKBOX_FOLLOW_PROJECT,
        compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
    )
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip())

    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            result.args,
            output=result.stdout,
            stderr=result.stderr,
        )


@task(name="docker-blackbox-follow-debug-sync")
def docker_blackbox_follow_debug_sync(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
    log_tail=120,
):
    """Print local follower blackbox sync queue state and recent app logs."""
    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    script = """
puts '== Source tournaments =='
Tournament.order(:id).pluck(:id, :name, :read_only_mode, :sync_target_url, :sync_last_pushed_at, :sync_last_push_error).each { |row| p row }
puts '== Source sync queue =='
TournamentSyncQueueEntry.order(:id).pluck(:id, :tournament_id, :status, :attempts, :last_error, :next_attempt_at, :last_attempt_at).each { |row| p row }
puts '== Follower tournaments =='
Tournament.order(:id).pluck(:id, :name, :read_only_mode, :sync_target_url, :sync_last_pushed_at, :sync_last_push_error).each { |row| p row }
"""

    for service, db_host in (("source-app", "source-postgres"), ("follower-app", "follower-postgres")):
        _print_header(f"Sync state from {service}")
        db_name = BLACKBOX_SOURCE_DB_NAME if service == "source-app" else BLACKBOX_FOLLOWER_DB_NAME
        service_env = _production_env_for(db_host, db_name)
        runner = _compose_run(
            ["run", "--rm", "-e", f"POSTGRES_URL={service_env['POSTGRES_URL']}", "-e", f"POSTGRES_USERNAME={service_env['POSTGRES_USERNAME']}", "-e", f"POSTGRES_PASSWORD={service_env['POSTGRES_PASSWORD']}", "-e", f"SECRET_KEY_BASE={service_env['SECRET_KEY_BASE']}", "-e", f"MAILGUN_API_KEY={service_env['MAILGUN_API_KEY']}", "-e", f"MAILGUN_DOMAIN={service_env['MAILGUN_DOMAIN']}", "-e", f"RAILS_LOG_TO_STDOUT={service_env['RAILS_LOG_TO_STDOUT']}", "-e", f"RAILS_SERVE_STATIC_FILES={service_env['RAILS_SERVE_STATIC_FILES']}", "-e", "RAILS_ENV=production", "e2e", "bundle", "exec", "rails", "runner", script],
            env=env,
            capture_output=True,
            check=False,
            project_name=BLACKBOX_FOLLOW_PROJECT,
            compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
        )
        if runner.stdout:
            print(runner.stdout.rstrip())
        if runner.stderr:
            print(runner.stderr.rstrip())
        if runner.returncode != 0:
            raise subprocess.CalledProcessError(
                runner.returncode,
                runner.args,
                output=runner.stdout,
                stderr=runner.stderr,
            )

        _print_header(f"Recent logs from {service}")
        logs = _compose_run(
            ["logs", "--tail", str(log_tail), service],
            env=env,
            capture_output=True,
            check=False,
            project_name=BLACKBOX_FOLLOW_PROJECT,
            compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
        )
        output = logs.stdout or logs.stderr or "<no logs>"
        print(output.rstrip())


@task(name="docker-blackbox-follow-debug-compare")
def docker_blackbox_follow_debug_compare(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
):
    """Compare latest leader tournament and follower read-only tournament via HTTP API."""
    env = _follow_compose_env(
        source_host_port=source_host_port,
        follower_host_port=follower_host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
    )

    script = """
def signature(tournament)
  {
    id: tournament.id,
    name: tournament.name,
    public: tournament.public,
    playoff_teams_amount: tournament.playoff_teams_amount,
    instant_finalists_amount: tournament.instant_finalists_amount,
    intermediate_round_participants_amount: tournament.intermediate_round_participants_amount,
    sync_source_tournament_id: tournament.respond_to?(:sync_source_tournament_id) ? tournament.sync_source_tournament_id : nil,
    team_names: tournament.teams.order(:id).pluck(:name),
    stage_levels: tournament.stages.order(:level).map { |stage| [stage.level, stage.state, stage.groups.count, stage.matches.count] },
    total_matches: tournament.matches.count,
    decider_matches: tournament.matches.count(&:decider?)
  }
end

tournament = if ENV['FOLLOW_COMPARE_MODE'] == 'leader'
               Tournament.where.not(sync_target_url: nil).order(:id).last
             else
               Tournament.where(read_only_mode: true).order(:id).last
             end

puts signature(tournament).inspect
"""

    for mode, db_host, db_name in (("leader", "source-postgres", BLACKBOX_SOURCE_DB_NAME), ("follower", "follower-postgres", BLACKBOX_FOLLOWER_DB_NAME)):
        _print_header(f"Compare {mode} tournament")
        service_env = _production_env_for(db_host, db_name)
        runner = _compose_run(
            ["run", "--rm", "-e", f"POSTGRES_URL={service_env['POSTGRES_URL']}", "-e", f"POSTGRES_USERNAME={service_env['POSTGRES_USERNAME']}", "-e", f"POSTGRES_PASSWORD={service_env['POSTGRES_PASSWORD']}", "-e", f"SECRET_KEY_BASE={service_env['SECRET_KEY_BASE']}", "-e", f"MAILGUN_API_KEY={service_env['MAILGUN_API_KEY']}", "-e", f"MAILGUN_DOMAIN={service_env['MAILGUN_DOMAIN']}", "-e", f"RAILS_LOG_TO_STDOUT={service_env['RAILS_LOG_TO_STDOUT']}", "-e", f"RAILS_SERVE_STATIC_FILES={service_env['RAILS_SERVE_STATIC_FILES']}", "-e", "RAILS_ENV=production", "-e", f"FOLLOW_COMPARE_MODE={mode}", "e2e", "bundle", "exec", "rails", "runner", script],
            env=env,
            capture_output=True,
            check=False,
            project_name=BLACKBOX_FOLLOW_PROJECT,
            compose_file=BLACKBOX_FOLLOW_COMPOSE_FILE,
        )
        if runner.stdout:
            print(runner.stdout.rstrip())
        if runner.stderr:
            print(runner.stderr.rstrip())
        if runner.returncode != 0:
            raise subprocess.CalledProcessError(
                runner.returncode,
                runner.args,
                output=runner.stdout,
                stderr=runner.stderr,
            )


@task(name="docker-blackbox-follow-run")
def docker_blackbox_follow_run(
    c,
    source_host_port=BLACKBOX_SOURCE_HOST_PORT,
    follower_host_port=BLACKBOX_FOLLOWER_HOST_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
    build=True,
    keep_running=False,
):
    """Build, boot, run follower-sync blackbox E2E, then tear down unless keep_running=true."""
    exit_error = None
    try:
        docker_blackbox_follow_up(
            c,
            source_host_port=source_host_port,
            follower_host_port=follower_host_port,
            app_image=app_image,
            runner_image=runner_image,
            postgres_image=postgres_image,
            build=build,
        )
        docker_blackbox_follow_test(
            c,
            source_host_port=source_host_port,
            follower_host_port=follower_host_port,
            app_image=app_image,
            runner_image=runner_image,
            postgres_image=postgres_image,
        )
    except subprocess.CalledProcessError as error:
        exit_error = error
        raise
    finally:
        if keep_running:
            print("Keeping follower production blackbox stack running.")
        else:
            docker_blackbox_follow_down(
                c,
                source_host_port=source_host_port,
                follower_host_port=follower_host_port,
                app_image=app_image,
                runner_image=runner_image,
                postgres_image=postgres_image,
            )
        if exit_error is not None:
            print("Follower blackbox run failed.")


@task(name="blackbox-service")
def blackbox_service(
    c,
    base_url=BLACKBOX_INTERNAL_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    alt_email=E2E_ALT_EMAIL,
    alt_password=E2E_ALT_PASSWORD,
    alt_username=E2E_ALT_USERNAME,
):
    """Run blackbox HTTP E2E against an already running production app plus Postgres sidecars."""
    _print_header("Running production database migrations")
    c.run("bundle exec rails db:migrate", env=_shared_production_env(), pty=True)

    _print_header(f"Waiting for app healthcheck at {base_url}")
    _wait_for_http(base_url=base_url, timeout=120)

    _print_header("Bootstrapping confirmed E2E user")
    _bootstrap_blackbox_users(c, _shared_production_env(), email, password, username, alt_email, alt_password, alt_username)

    _print_header("Running HTTP E2E against production image")
    _run_blackbox_rspec(base_url, email, password, username, alt_email, alt_password, alt_username)


@task(name="blackbox-follow-service")
def blackbox_follow_service(
    c,
    source_base_url=BLACKBOX_SOURCE_INTERNAL_BASE_URL,
    follower_base_url=BLACKBOX_FOLLOWER_INTERNAL_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
    alt_email=E2E_ALT_EMAIL,
    alt_password=E2E_ALT_PASSWORD,
    alt_username=E2E_ALT_USERNAME,
):
    """Run follower-sync HTTP E2E against two independent production app services."""
    source_env = _production_env_for("source-postgres", BLACKBOX_SOURCE_DB_NAME)
    follower_env = _production_env_for("follower-postgres", BLACKBOX_FOLLOWER_DB_NAME)

    _print_header("Running source production database migrations")
    c.run("bundle exec rails db:migrate", env=source_env, pty=True)

    _print_header("Running follower production database migrations")
    c.run("bundle exec rails db:migrate", env=follower_env, pty=True)

    _print_header(f"Waiting for source app healthcheck at {source_base_url}")
    _wait_for_http(base_url=source_base_url, timeout=120)

    _print_header(f"Waiting for follower app healthcheck at {follower_base_url}")
    _wait_for_http(base_url=follower_base_url, timeout=120)

    _print_header("Running source/follower network smoke")
    _blackbox_network_smoke(c, source_base_url)
    _blackbox_network_smoke(c, follower_base_url)
    _blackbox_service_to_service_smoke(c, source_env, "source-app", follower_base_url)
    _blackbox_service_to_service_smoke(c, follower_env, "follower-app", source_base_url)

    _print_header("Bootstrapping confirmed E2E users on source and follower")
    _bootstrap_blackbox_users(c, source_env, email, password, username, alt_email, alt_password, alt_username)
    _bootstrap_blackbox_users(c, follower_env, email, password, username, alt_email, alt_password, alt_username)

    _print_header("Running follower sync HTTP E2E against production images")
    _run_blackbox_rspec(
        source_base_url,
        email,
        password,
        username,
        alt_email,
        alt_password,
        alt_username,
        spec_path="spec/e2e/http/tournament_follow_sync_spec.rb",
        extra_env={
            "TURNIERE_SOURCE_E2E_BASE_URL": source_base_url,
            "TURNIERE_FOLLOWER_E2E_BASE_URL": follower_base_url,
        },
    )


@task(name="blackbox-production")
def blackbox_production(
    c,
    host_port=SERVER_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
    build=True,
    keep_running=False,
):
    """Build the production image, boot a Postgres-backed stack, run HTTP E2E, and print a summary."""
    env = _compose_env(
        host_port=host_port,
        app_image=app_image,
        runner_image=runner_image,
        postgres_image=postgres_image,
        expect_profiling="false",
    )

    exit_error = None
    try:
        docker_blackbox_up(
            c,
            host_port=host_port,
            app_image=app_image,
            runner_image=runner_image,
            postgres_image=postgres_image,
            build=build,
        )
        docker_blackbox_test(
            c,
            host_port=host_port,
            app_image=app_image,
            runner_image=runner_image,
            postgres_image=postgres_image,
        )
    except (RuntimeError, subprocess.CalledProcessError) as error:
        exit_error = error
        _print_service_logs(env, "app")
        _print_service_logs(env, "postgres")
    finally:
        if keep_running:
            _print_header("Stack kept running")
            print(
                f"Production app: http://127.0.0.1:{host_port}\n"
                f"Stop it later with: {_format_command(_docker_compose_cmd() + ['down', '-v', '--remove-orphans'])}"
            )
        else:
            docker_blackbox_down(
                c,
                host_port=host_port,
                app_image=app_image,
                runner_image=runner_image,
                postgres_image=postgres_image,
            )

    if exit_error:
        raise exit_error


@task(name="docker-test-http-e2e")
def docker_test_http_e2e(
    c,
    image=TEST_TAG,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
):
    """Run the HTTP E2E suite inside the test Docker image against a live Rails server."""
    command = (
        f"docker run --rm {image} bash -lc "
        f"\"cd /app && "
        "bundle exec rails db:migrate && "
        "bundle exec rails runner -e test "
        f"\\\"user = User.find_or_initialize_by(email: '{email}'); "
        f"user.username = '{username}'; "
        f"user.password = '{password}'; "
        f"user.password_confirmation = '{password}'; "
        "user.confirmed_at = Time.current; "
        "user.uid = user.email; "
        "user.provider = 'email'; "
        "user.save!\\\" && "
        f"bundle exec rails s -e test -p {SERVER_PORT} -b 0.0.0.0 >/tmp/turniere-e2e-server.log 2>&1 & "
        "SERVER_PID=\\$! && "
        f"ruby script/wait_for_http.rb {TEST_BASE_URL} 60 && "
        f"TURNIERE_E2E_BASE_URL={TEST_BASE_URL} "
        f"TURNIERE_E2E_EMAIL={email} "
        f"TURNIERE_E2E_PASSWORD={password} "
        f"TURNIERE_E2E_USERNAME={username} "
        "bundle exec rspec spec/e2e/http && "
        "kill \\$SERVER_PID\""
    )
    c.run(command, pty=True)


@task(name="docker-test-shard")
def docker_test_shard(c, node_index=1, node_total=8, image=TEST_TAG, build=True):
    """Run one Rails-spec shard inside the test Docker image."""
    if build:
        docker_build_all(c)

    command = (
        f"docker run --rm {image} bash -lc "
        f"\"cd /app && bundle exec rails db:migrate && "
        f"inv test-shard --node-index={node_index} --node-total={node_total}\""
    )
    c.run(command, pty=True)
