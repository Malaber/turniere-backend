from invoke import task

import os
import signal
import subprocess
import time
import urllib.request


SERVER_HOST = "0.0.0.0"
SERVER_PORT = "3000"
TEST_BASE_URL = f"http://127.0.0.1:{SERVER_PORT}"

E2E_EMAIL = "e2e@example.com"
E2E_PASSWORD = "password123"
E2E_USERNAME = "e2e-user"

PRODUCTION_TAG = "registry.gitlab.com/turniere/turniere-backend/production/commits:local"
DEVELOPMENT_TAG = "registry.gitlab.com/turniere/turniere-backend/development/commits:local"
TEST_TAG = "registry.gitlab.com/turniere/turniere-backend/test/commits:local"


def _env(**overrides):
    env = os.environ.copy()
    env.update({key: str(value) for key, value in overrides.items()})
    return env


def _wait_for_http(base_url=TEST_BASE_URL, timeout=60):
    deadline = time.time() + timeout
    healthz_url = f"{base_url}/healthz"

    while time.time() < deadline:
        try:
            with urllib.request.urlopen(healthz_url) as response:
                if response.status == 200:
                    return
        except Exception:
            time.sleep(0.5)

    raise RuntimeError(f"healthcheck did not become ready within {timeout}s: {healthz_url}")


def _start_test_server():
    log_handle = open("/tmp/turniere-e2e-server.log", "w")
    process = subprocess.Popen(
        f"bundle exec rails s -e test -b {SERVER_HOST} -p {SERVER_PORT}",
        shell=True,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        preexec_fn=os.setsid,
    )
    return process, log_handle


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
