from invoke import task

import os
import re
import shlex
import signal
import subprocess
import time
import urllib.request
import urllib.error
from pathlib import Path


SERVER_HOST = "0.0.0.0"
SERVER_PORT = "3000"
TEST_BASE_URL = f"http://127.0.0.1:{SERVER_PORT}"
BLACKBOX_BASE_URL = TEST_BASE_URL
BLACKBOX_INTERNAL_BASE_URL = "http://app:3000"

E2E_EMAIL = "e2e@example.com"
E2E_PASSWORD = "password123"
E2E_USERNAME = "e2e-user"

PRODUCTION_TAG = "registry.gitlab.com/turniere/turniere-backend/production/commits:local"
DEVELOPMENT_TAG = "registry.gitlab.com/turniere/turniere-backend/development/commits:local"
TEST_TAG = "registry.gitlab.com/turniere/turniere-backend/test/commits:local"
BLACKBOX_COMPOSE_FILE = "docker-compose.blackbox.yml"
BLACKBOX_PROJECT = "turniere-blackbox"
BLACKBOX_POSTGRES_IMAGE = "postgres:16"
BLACKBOX_DB_NAME = "turniere_blackbox"
BLACKBOX_DB_USER = "turniere"
BLACKBOX_DB_PASSWORD = "turniere"
BLACKBOX_SECRET_KEY_BASE = "turniere-blackbox-secret-key-base-please-change-in-real-prod"
BLACKBOX_MAILGUN_API_KEY = "blackbox-test-api-key"
BLACKBOX_MAILGUN_DOMAIN = "blackbox.example.com"
SPEC_ROOT = Path("spec")
E2E_SPEC_ROOT = SPEC_ROOT / "e2e" / "http"


def _env(**overrides):
    env = os.environ.copy()
    env.update({key: str(value) for key, value in overrides.items()})
    return env


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


def _compose_env(
    host_port=SERVER_PORT,
    app_image=PRODUCTION_TAG,
    runner_image=TEST_TAG,
    postgres_image=BLACKBOX_POSTGRES_IMAGE,
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
        TURNIERE_E2E_EMAIL=E2E_EMAIL,
        TURNIERE_E2E_PASSWORD=E2E_PASSWORD,
        TURNIERE_E2E_USERNAME=E2E_USERNAME,
    )


def _format_command(command):
    return " ".join(shlex.quote(part) for part in command)


def _compose_run(compose_args, env, capture_output=False, check=True):
    command = _docker_compose_cmd() + compose_args
    return _run_subprocess(command, env=env, capture_output=capture_output, check=check)


def _print_header(title):
    print(f"\n== {title} ==")


def _bootstrap_user_command(email, password, username):
    return (
        "bundle exec rails runner "
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


def _run_blackbox_rspec(base_url, email, password, username):
    env = _env(
        TURNIERE_E2E_BASE_URL=base_url,
        TURNIERE_E2E_EMAIL=email,
        TURNIERE_E2E_PASSWORD=password,
        TURNIERE_E2E_USERNAME=username,
    )
    command = ["bundle", "exec", "rspec", "spec/e2e/http", "--format", "documentation"]
    print(_format_command(command))
    result = _run_subprocess(command, env=env, capture_output=True, check=False)
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


def _start_test_server():
    return _start_server(
        f"bundle exec rails s -e test -b {SERVER_HOST} -p {SERVER_PORT}",
        _env(),
    )


def _stop_process(process, log_handle):
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except ProcessLookupError:
        pass
    finally:
        log_handle.close()


@task
def setup(c):
    """Install gem dependencies locally."""
    c.run("bundle install", pty=True)


@task(name="db-migrate")
def db_migrate(c):
    """Run database migrations locally."""
    c.run("bundle exec rails db:migrate", pty=True)


@task
def server(c, host=SERVER_HOST, port=SERVER_PORT):
    """Start the backend locally in development."""
    c.run(f"bundle exec rails s -b {host} -p {port}", pty=True)


@task(name="server-test")
def server_test(c, host=SERVER_HOST, port=SERVER_PORT):
    """Start the backend locally in test mode."""
    c.run(f"bundle exec rails s -e test -b {host} -p {port}", pty=True)


@task
def test(c):
    """Run the normal RSpec suite."""
    c.run("bundle exec rspec", pty=True)


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

    c.run(
        "bundle exec rspec --require ./spec/rails_helper " + " ".join(shlex.quote(path) for path in files),
        pty=True,
    )


@task
def lint(c):
    """Run RuboCop."""
    c.run("bundle exec rubocop", pty=True)


@task(name="bootstrap-e2e-user")
def bootstrap_e2e_user(c, email=E2E_EMAIL, password=E2E_PASSWORD, username=E2E_USERNAME):
    """Create or update the confirmed HTTP E2E user in test env."""
    command = (
        "bundle exec rails runner -e test "
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
):
    """Run HTTP E2E specs against an already running backend."""
    c.run(
        "bundle exec rspec spec/e2e/http",
        env=_env(
            TURNIERE_E2E_BASE_URL=base_url,
            TURNIERE_E2E_EMAIL=email,
            TURNIERE_E2E_PASSWORD=password,
            TURNIERE_E2E_USERNAME=username,
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
):
    """Boot a local test server, then run the HTTP E2E suite against it."""
    db_migrate(c)
    bootstrap_e2e_user(c, email=email, password=password, username=username)

    process, log_handle = _start_test_server()
    try:
        _wait_for_http(base_url=base_url, timeout=60)
        test_http_e2e(c, base_url=base_url, email=email, password=password, username=username)
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


@task(name="docker-build-production")
def docker_build_production(c, tag=PRODUCTION_TAG):
    """Build the production Docker image."""
    c.run(f"docker build -t {tag} -f docker/production/Dockerfile .", pty=True)


@task(name="docker-build-development")
def docker_build_development(c, tag=DEVELOPMENT_TAG):
    """Build the development Docker image."""
    c.run(
        f"docker build --build-arg base_commit=local -t {tag} -f docker/development/Dockerfile .",
        pty=True,
    )


@task(name="docker-build-test")
def docker_build_test(c, tag=TEST_TAG):
    """Build the test Docker image."""
    c.run(f"docker build --build-arg base_commit=local -t {tag} -f docker/test/Dockerfile .", pty=True)


@task(name="docker-build-all")
def docker_build_all(c):
    """Build the production, development, and test Docker images."""
    docker_build_production(c)
    docker_build_development(c)
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
    )

    _print_header("Starting production blackbox stack")
    _compose_run(["down", "-v", "--remove-orphans"], env=env, check=False)
    _compose_run(["up", "-d", "postgres", "app"], env=env)

    base_url = f"http://127.0.0.1:{host_port}"
    _print_header(f"Waiting for app healthcheck at {base_url}")
    _wait_for_http(base_url=base_url, timeout=120)

    _print_header("Bootstrapping confirmed E2E user")
    bootstrap = _compose_run(
        ["exec", "-T", "app", "bash", "-lc", _bootstrap_user_command(E2E_EMAIL, E2E_PASSWORD, E2E_USERNAME)],
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


@task(name="blackbox-service")
def blackbox_service(
    c,
    base_url=BLACKBOX_INTERNAL_BASE_URL,
    email=E2E_EMAIL,
    password=E2E_PASSWORD,
    username=E2E_USERNAME,
):
    """Run blackbox HTTP E2E against an already running production app plus Postgres sidecars."""
    _print_header("Running production database migrations")
    c.run("bundle exec rails db:migrate", env=_shared_production_env(), pty=True)

    _print_header(f"Waiting for app healthcheck at {base_url}")
    _wait_for_http(base_url=base_url, timeout=120)

    _print_header("Bootstrapping confirmed E2E user")
    c.run(
        _bootstrap_user_command(email, password, username),
        env=_shared_production_env(),
        pty=True,
    )

    _print_header("Running HTTP E2E against production image")
    _run_blackbox_rspec(base_url, email, password, username)


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
