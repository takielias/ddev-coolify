setup() {
  set -eu -o pipefail

  export GITHUB_REPO=takielias/ddev-coolify

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p ~/tmp
  export TESTDIR=$(mktemp -d ~/tmp/${PROJNAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"

  # Create a minimal Laravel project structure
  mkdir -p app bootstrap config database public resources/views routes storage/logs storage/framework/{cache/data,sessions,views}
  echo '<?php' > artisan
  echo '{}' > composer.json
  echo '{}' > composer.lock
  echo '{"name":"test","lockfileVersion":3}' > package-lock.json
  cat > package.json <<'PKGJSON'
{
  "private": true,
  "scripts": { "build": "echo build" },
  "devDependencies": {}
}
PKGJSON
  cat > bootstrap/app.php <<'BOOTSTRAP'
<?php
return \Illuminate\Foundation\Application::configure(basePath: dirname(__DIR__))->create();
BOOTSTRAP
  echo '<?php return [];' > bootstrap/providers.php

  run ddev config --project-name="${PROJNAME}" --project-type=laravel --php-version=8.4 --project-tld=ddev.site
  assert_success
}

health_checks() {
  # Verify the command exists after install
  run ddev coolify --help
  assert_success
  assert_output --partial "Generate a production Dockerfile"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

@test "generates frankenphp + supervisor dockerfile" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev start -y
  assert_success

  # Add horizon to composer.json to trigger worker detection
  cat > composer.json <<'JSON'
{
  "require": {
    "laravel/horizon": "^5.0",
    "spatie/laravel-medialibrary": "^11.0"
  }
}
JSON
  mkdir -p routes
  mkdir -p app/Console
  echo 'schedule' > routes/console.php

  run ddev coolify --server=frankenphp --supervisor --force
  assert_success

  # Verify generated files
  assert_file_exist docker/Dockerfile
  assert_file_exist docker/.dockerignore
  assert_file_exist docker/start.sh
  assert_file_exist docker/supervisord.conf

  # Check Dockerfile content
  run cat docker/Dockerfile
  assert_output --partial "serversideup/php:8.4-frankenphp"
  assert_output --partial "supervisor"
  assert_output --partial "install-php-extensions exif gd"
  assert_output --partial "start.sh"

  # Check supervisord has horizon + scheduler
  run cat docker/supervisord.conf
  assert_output --partial "[program:frankenphp]"
  assert_output --partial "[program:horizon]"
  assert_output --partial "[program:scheduler]"
}

@test "generates nginx + s6 dockerfile" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev start -y
  assert_success

  cat > composer.json <<'JSON'
{
  "require": {
    "laravel/horizon": "^5.0"
  }
}
JSON
  mkdir -p routes
  mkdir -p app/Console
  echo 'schedule' > routes/console.php

  run ddev coolify --server=nginx --supervisor --force
  assert_success

  # Verify S6 service files instead of supervisor
  assert_file_exist docker/Dockerfile
  assert_file_exist docker/s6/horizon/run
  assert_file_exist docker/s6/horizon/type
  assert_file_exist docker/s6/scheduler/run
  assert_file_exist docker/s6/scheduler/type
  assert_file_not_exist docker/supervisord.conf
  assert_file_not_exist docker/start.sh

  # Check Dockerfile uses fpm-nginx
  run cat docker/Dockerfile
  assert_output --partial "serversideup/php:8.4-fpm-nginx"
  assert_output --partial "s6-overlay"

  # Check S6 service type
  run cat docker/s6/horizon/type
  assert_output --partial "longrun"
}

@test "generates multi-container dockerfile" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev start -y
  assert_success

  cat > composer.json <<'JSON'
{
  "require": {
    "laravel/horizon": "^5.0"
  }
}
JSON

  run ddev coolify --server=frankenphp --no-supervisor --force
  assert_success

  # Only Dockerfile and .dockerignore — no supervisor or s6 files
  assert_file_exist docker/Dockerfile
  assert_file_exist docker/.dockerignore
  assert_file_not_exist docker/supervisord.conf
  assert_file_not_exist docker/start.sh

  # Dockerfile should NOT contain supervisor
  run cat docker/Dockerfile
  assert_output --partial "serversideup/php:8.4-frankenphp"
  refute_output --partial "supervisor"
  assert_output --partial "Multi container"
}

@test "dry-run does not write files" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev start -y
  assert_success

  run ddev coolify --server=frankenphp --supervisor --dry-run
  assert_success
  assert_output --partial "dry run"

  # No files should be written
  assert_file_not_exist docker/Dockerfile
}

@test "detects php extensions from composer.json" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev start -y
  assert_success

  cat > composer.json <<'JSON'
{
  "require": {
    "spatie/laravel-medialibrary": "^11.0",
    "barryvdh/laravel-dompdf": "^3.0",
    "maatwebsite/excel": "^3.1"
  }
}
JSON

  run ddev coolify --server=frankenphp --no-supervisor --force
  assert_success

  run cat docker/Dockerfile
  assert_output --partial "install-php-extensions exif gd"
}

@test "detects node version from .nvmrc" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev start -y
  assert_success

  echo "20" > .nvmrc

  run ddev coolify --server=frankenphp --no-supervisor --force
  assert_success

  run cat docker/Dockerfile
  assert_output --partial "node:20-alpine"
}
