#!/usr/bin/env bash
# One-shot local launcher: resolve a supported Node, install and build only when
# inputs changed, then serve the gateway and operator console on loopback.
#
#   ./scripts/start.sh              first run installs and builds; later runs
#                                   start immediately when nothing changed
#   ./scripts/start.sh -p 9000      listen on another port (also PORT=9000)
#   ./scripts/start.sh --host 0.0.0.0
#                                   bind beyond loopback; see the warning below
#   ./scripts/start.sh --rebuild    force reinstall and rebuild
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

node_min="22.19.0"
env_file="$repo_dir/.env.local"
work_dir="$repo_dir/.cursor-sdk2api"
deps_stamp="$work_dir/deps.stamp"
build_stamp="$work_dir/build.stamp"
host=${HOST:-127.0.0.1}
port=${PORT:-8080}
state_dir=${STATE_DIR:-$work_dir/state}
force=0

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | cut -c3-; }

# A flag beats the matching environment variable, so `PORT=1 ... -p 2` listens on 2.
while (( $# )); do
  case "$1" in
    -p|--port)
      [[ -n "${2:-}" ]] || die "$1 requires a port number"
      port=$2
      shift 2
      ;;
    --port=*) port=${1#*=}; shift ;;
    -H|--host)
      [[ -n "${2:-}" ]] || die "$1 requires a host or address"
      host=$2
      shift 2
      ;;
    --host=*) host=${1#*=}; shift ;;
    --rebuild|-r) force=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# Reject anything the kernel would refuse anyway, but with a clearer message.
# Port 0 is excluded on purpose: the kernel picks a random port, and the banner
# would then advertise a URL that nothing is listening on.
[[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) \
  || die "invalid port: $port (expected 1-65535)"
if (( port < 1024 )) && (( EUID != 0 )); then
  die "port $port needs root on most systems. Pick a port above 1023."
fi

version_ok() {
  local have=${1#v}
  [[ -n "$have" && "$(printf '%s\n%s\n' "$node_min" "$have" | sort -V | head -1)" == "$node_min" ]]
}

# The newest Node on PATH is often too old, so probe known install roots and
# nvm's version dir, which stays outside PATH until nvm.sh is sourced.
resolve_node() {
  local candidate
  for candidate in "${NODE_BIN:-}" "$(command -v node || true)" \
    /usr/local/bin/node /opt/homebrew/bin/node; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    version_ok "$("$candidate" -v 2>/dev/null || true)" && { printf '%s\n' "$candidate"; return 0; }
  done

  local nvm_dir=${NVM_DIR:-$HOME/.nvm}
  if [[ -d "$nvm_dir/versions/node" ]]; then
    while read -r candidate; do
      [[ -x "$candidate/bin/node" ]] || continue
      version_ok "$(basename "$candidate")" && { printf '%s\n' "$candidate/bin/node"; return 0; }
    done < <(find "$nvm_dir/versions/node" -maxdepth 1 -mindepth 1 -type d | sort -Vr)
  fi

  # Nothing suitable installed; let nvm fetch a current release.
  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    log "no Node >= $node_min found, installing Node 22 via nvm" >&2
    # shellcheck disable=SC1091
    . "$nvm_dir/nvm.sh" >/dev/null
    nvm install 22 >&2 || return 1
    printf '%s\n' "$(nvm which 22)"
    return 0
  fi
  return 1
}

node_bin=$(resolve_node) || die "Node >= $node_min is required. Install it from https://nodejs.org or via nvm."
PATH="$(dirname "$node_bin"):$PATH"
export PATH
log "using node $("$node_bin" -v) ($node_bin)"

# Gateway key: reuse the saved one so clients keep working across restarts.
# .env.local is gitignored by the .env* rule.
if [[ -z "${GATEWAY_ACCESS_KEY:-}" && -f "$env_file" ]]; then
  # shellcheck disable=SC1090
  set -a; . "$env_file"; set +a
fi
if [[ -z "${GATEWAY_ACCESS_KEY:-}" ]]; then
  GATEWAY_ACCESS_KEY=$("$node_bin" -e 'console.log(require("node:crypto").randomBytes(24).toString("hex"))')
  umask 077
  printf 'GATEWAY_ACCESS_KEY=%s\n' "$GATEWAY_ACCESS_KEY" > "$env_file"
  log "generated a new gateway key and saved it to ${env_file##*/}"
fi
export GATEWAY_ACCESS_KEY

if [[ -n "${CURSOR_API_KEY:-}" && "$CURSOR_API_KEY" == "$GATEWAY_ACCESS_KEY" ]]; then
  die "CURSOR_API_KEY must differ from GATEWAY_ACCESS_KEY"
fi

mkdir -p "$work_dir"

# Skip npm ci / npm run build when their inputs are unchanged, so a warm start
# goes straight to listening. Stamps hold a digest of the relevant inputs.
fingerprint() {
  # shasum is present on macOS and Linux; sha256sum is not on macOS.
  find "$@" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.json' -o -name '*.html' -o -name '*.css' -o -name '*.svg' \) \
    -not -path '*/node_modules/*' -exec shasum -a 256 {} + 2>/dev/null | shasum -a 256 | cut -d' ' -f1
}

deps_want=$(shasum -a 256 package-lock.json package.json | shasum -a 256 | cut -d' ' -f1)
if (( force )) || [[ ! -d node_modules ]] || [[ "$(cat "$deps_stamp" 2>/dev/null)" != "$deps_want" ]]; then
  log "installing dependencies"
  npm ci
  printf '%s\n' "$deps_want" > "$deps_stamp"
fi

build_want=$(fingerprint src web tsconfig.build.json tsconfig.json package.json)
if (( force )) || [[ ! -f dist/index.js || ! -f dist/console/index.html ]] \
  || [[ "$(cat "$build_stamp" 2>/dev/null)" != "$build_want" ]]; then
  log "building server and console"
  npm run build
  printf '%s\n' "$build_want" > "$build_stamp"
else
  log "build is up to date, skipping (use --rebuild to force)"
fi

if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  die "port $port is already in use. Stop the other process or rerun with PORT=<free-port>."
fi

if [[ "$host" != "127.0.0.1" && "$host" != "localhost" && "$host" != "::1" ]]; then
  # /console/ and /v0/management/* have no auth of their own in v0.1: they can
  # add and remove pooled Cursor credentials and reveal the gateway key.
  log "WARNING: binding $host exposes /console/ and /v0/management/* with no authentication."
  log "         Put an authenticating reverse proxy in front, or use the default 127.0.0.1."
fi

url="http://${host}:${port}"
cat <<BANNER

  console   ${url}/console/
  health    ${url}/health
  key       ${GATEWAY_ACCESS_KEY}

  Import a Cursor User API Key in the console, then point clients at ${url}
  using the gateway key above. Ctrl-C stops the gateway.

BANNER

mkdir -p "$state_dir"
chmod 700 "$state_dir" 2>/dev/null || true
exec env \
  HOST="$host" \
  PORT="$port" \
  AUTH_MODE=managed \
  STATE_DIR="$state_dir" \
  "$node_bin" dist/index.js
