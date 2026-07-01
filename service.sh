#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$ROOT_DIR/.service"
PID_FILE="$STATE_DIR/hugo.pid"
LOG_FILE="$STATE_DIR/hugo.log"
HOST="${HUGO_HOST:-127.0.0.1}"
PORT="${HUGO_PORT:-1313}"
BASE_URL="${HUGO_BASE_URL:-http://$HOST:$PORT/}"

usage() {
  cat <<'EOF'
Usage: ./service.sh {start|stop|status|test|help}

Commands:
  start   Start the local Hugo development server in the background.
  stop    Stop the running Hugo development server.
  status  Show whether the Hugo development server is running.
  test    Run a production Hugo build for verification.
  help    Show this help message.
EOF
}

resolve_hugo() {
  if command -v hugo >/dev/null 2>&1; then
    command -v hugo
    return 0
  fi

  if [[ -x "$HOME/go/bin/hugo" ]]; then
    printf '%s\n' "$HOME/go/bin/hugo"
    return 0
  fi

  return 1
}

HUGO_BIN="$(resolve_hugo || true)"

if [[ -z "$HUGO_BIN" ]]; then
  printf 'Hugo binary not found. Install Hugo or make it available in PATH.\n' >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

read_pid() {
  if [[ -f "$PID_FILE" ]]; then
    tr -d '[:space:]' < "$PID_FILE"
  fi
}

is_running() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

listening_pid() {
  lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1 || true
}

start_service() {
  local pid
  pid="$(read_pid)"

  if is_running "$pid"; then
    printf 'Hugo is already running. pid=%s url=%s\n' "$pid" "$BASE_URL"
    return 0
  fi

  if [[ -n "$pid" ]]; then
    rm -f "$PID_FILE"
  fi

  local port_pid
  port_pid="$(listening_pid)"
  if [[ -n "$port_pid" ]]; then
    printf 'Port %s is already in use by pid %s.\n' "$PORT" "$port_pid" >&2
    return 1
  fi

  local previous_dir
  previous_dir="$PWD"
  cd "$ROOT_DIR"

  if command -v setsid >/dev/null 2>&1; then
    setsid "$HUGO_BIN" server --bind "$HOST" --baseURL "$BASE_URL" -D >"$LOG_FILE" 2>&1 < /dev/null &
  else
    nohup "$HUGO_BIN" server --bind "$HOST" --baseURL "$BASE_URL" -D >"$LOG_FILE" 2>&1 < /dev/null &
  fi

  pid=$!
  disown "$pid" 2>/dev/null || true
  echo "$pid" > "$PID_FILE"
  cd "$previous_dir"

  sleep 1
  pid="$(read_pid)"
  if is_running "$pid"; then
    printf 'Started Hugo. pid=%s url=%s log=%s\n' "$pid" "$BASE_URL" "$LOG_FILE"
    return 0
  fi

  rm -f "$PID_FILE"
  printf 'Failed to start Hugo. Check %s\n' "$LOG_FILE" >&2
  return 1
}

stop_service() {
  local pid
  pid="$(read_pid)"

  if [[ -z "$pid" ]]; then
    printf 'Hugo is not running.\n'
    return 0
  fi

  if ! is_running "$pid"; then
    rm -f "$PID_FILE"
    printf 'Removed stale pid file.\n'
    return 0
  fi

  kill "$pid"

  for _ in {1..10}; do
    if ! is_running "$pid"; then
      rm -f "$PID_FILE"
      printf 'Stopped Hugo. pid=%s\n' "$pid"
      return 0
    fi
    sleep 1
  done

  printf 'Timed out stopping pid=%s\n' "$pid" >&2
  return 1
}

status_service() {
  local pid
  pid="$(read_pid)"

  if is_running "$pid"; then
    printf 'running pid=%s url=%s log=%s\n' "$pid" "$BASE_URL" "$LOG_FILE"
    return 0
  fi

  if [[ -n "$pid" ]]; then
    rm -f "$PID_FILE"
  fi

  printf 'stopped\n'
  return 1
}

test_service() {
  (
    cd "$ROOT_DIR"
    "$HUGO_BIN" --environment production --config hugo.toml,hugo.production.toml --minify
  )
}

case "${1:-}" in
  start)
    start_service
    ;;
  stop)
    stop_service
    ;;
  status)
    status_service
    ;;
  test)
    test_service
    ;;
  help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
