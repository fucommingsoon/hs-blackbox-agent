#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/pb-dtc-runner.sh --task=<owner__repo.commit> [options] -- <args...>

Modes:
  --mode=hsbb     Run: hsbb <args...> inside the PB task container. Default.
  --mode=app      Run: /workspace/executable <args...> inside the PB task container.

Options:
  --image=<image>           PB task image. Defaults to programbench/<owner>_1776_<repo>.<commit>:task.
  --out=<host-dir>          Host output directory. Default: /private/tmp/hsbb-pb-run-<task>-<timestamp>.
  --container-out=<dir>     Container DTC output dir to copy back in hsbb mode. Default: /tmp/hsbb-dtc-run.
  --hsbb-linux=<path>       Linux hsbb binary. Default: /private/tmp/hsbb-linux-amd64.
  --build-hsbb              Build/rebuild Linux hsbb with the reusable builder container.
  --builder=<name>          Builder container name. Default: hsbb-pb-builder.
  --builder-image=<image>   Builder image. Default: programbench/eradman_1776_entr.8e2e8b4:task.
  --keep-container          Keep the runner container after execution.
  -h, --help                Show this help.

Examples:
  scripts/pb-dtc-runner.sh --task=ariga__atlas.6d81150 --mode=app -- --help
  scripts/pb-dtc-runner.sh --task=eradman__entr.8e2e8b4 -- dtc run entr --app=/workspace/executable --out=/tmp/hsbb-dtc-run
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task=""
image=""
mode="hsbb"
timestamp="$(date +%Y%m%d-%H%M%S)"
host_out=""
container_out="/tmp/hsbb-dtc-run"
hsbb_linux="${HSBB_LINUX:-/private/tmp/hsbb-linux-amd64}"
build_hsbb=0
builder="${HSBB_PB_BUILDER:-hsbb-pb-builder}"
builder_image="${HSBB_PB_BUILDER_IMAGE:-programbench/eradman_1776_entr.8e2e8b4:task}"
keep_container=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task=*) task="${1#*=}" ;;
    --image=*) image="${1#*=}" ;;
    --mode=*) mode="${1#*=}" ;;
    --out=*) host_out="${1#*=}" ;;
    --container-out=*) container_out="${1#*=}" ;;
    --hsbb-linux=*) hsbb_linux="${1#*=}" ;;
    --build-hsbb) build_hsbb=1 ;;
    --builder=*) builder="${1#*=}" ;;
    --builder-image=*) builder_image="${1#*=}" ;;
    --keep-container) keep_container=1 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ -z "$task" ]]; then
  echo "--task is required" >&2
  usage >&2
  exit 2
fi

if [[ "$mode" != "hsbb" && "$mode" != "app" ]]; then
  echo "--mode must be hsbb or app" >&2
  exit 2
fi

if [[ -z "$image" ]]; then
  owner="${task%%__*}"
  rest="${task#*__}"
  if [[ "$owner" == "$task" || "$rest" == "$task" || "$rest" != *.* ]]; then
    echo "Cannot infer image from task '$task'; pass --image explicitly" >&2
    exit 2
  fi
  repo="${rest%.*}"
  commit="${rest##*.}"
  image="programbench/${owner}_1776_${repo}.${commit}:task"
fi

safe_task="$(printf '%s' "$task" | tr -c '[:alnum:]_.-' '-')"
container="hsbb-pb-runner-${safe_task}-${timestamp}-$$"
if [[ -z "$host_out" ]]; then
  host_out="/private/tmp/hsbb-pb-run-${safe_task}-${timestamp}"
fi

log() {
  printf '[pb-dtc-runner] %s\n' "$*" >&2
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -Fxq "$1"
}

ensure_builder() {
  if container_exists "$builder"; then
    running="$(docker inspect -f '{{.State.Running}}' "$builder")"
    if [[ "$running" != "true" ]]; then
      docker start "$builder" >/dev/null
    fi
    return
  fi

  log "creating builder container $builder from $builder_image"
  docker run -d --platform linux/amd64 \
    --name "$builder" \
    -v "$repo_root:/hostrepo:ro" \
    "$builder_image" \
    sleep infinity >/dev/null
}

ensure_builder_deps() {
  if docker exec "$builder" sh -lc 'test -x /root/.ghcup/bin/cabal && test -x /root/.ghcup/bin/ghc-9.6.7' >/dev/null 2>&1; then
    return
  fi

  log "installing builder dependencies and ghcup toolchain"
  docker exec "$builder" sh -lc '
    apt-get update &&
    apt-get install -y curl ca-certificates build-essential libffi-dev libgmp-dev zlib1g-dev xz-utils git pkg-config python3
  '
  docker exec "$builder" sh -lc '
    export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
    export BOOTSTRAP_HASKELL_INSTALL_STACK=0
    export BOOTSTRAP_HASKELL_ADJUST_BASHRC=P
    export BOOTSTRAP_HASKELL_GHC_VERSION=9.6.7
    export BOOTSTRAP_HASKELL_CABAL_VERSION=3.12.1.0
    curl --proto "=https" --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
  '
}

build_linux_hsbb() {
  ensure_builder
  ensure_builder_deps

  log "building Linux hsbb in $builder"
  docker exec "$builder" sh -lc '
    rm -rf /tmp/hsbb-src &&
    mkdir -p /tmp/hsbb-src &&
    cd /hostrepo &&
    tar --exclude=.git --exclude=dist-newstyle -cf - . | tar -C /tmp/hsbb-src -xf - &&
    cd /tmp/hsbb-src &&
    /root/.ghcup/bin/cabal build --with-compiler=/root/.ghcup/bin/ghc-9.6.7
  '

  binary_path="$(docker exec "$builder" sh -lc 'find /tmp/hsbb-src/dist-newstyle -name hsbb -type f -perm /111 | head -1')"
  if [[ -z "$binary_path" ]]; then
    echo "Linux hsbb binary was not found in builder output" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$hsbb_linux")"
  docker cp "$builder:$binary_path" "$hsbb_linux"
  chmod +x "$hsbb_linux"
  log "copied Linux hsbb to $hsbb_linux"
}

if [[ "$build_hsbb" -eq 1 || ! -x "$hsbb_linux" ]]; then
  build_linux_hsbb
fi

if [[ ! -x "$hsbb_linux" ]]; then
  echo "Linux hsbb binary is missing or not executable: $hsbb_linux" >&2
  echo "Run again with --build-hsbb, or set --hsbb-linux=<path>." >&2
  exit 1
fi

mkdir -p "$host_out"

cleanup() {
  if [[ "$keep_container" -eq 0 ]]; then
    docker rm -f "$container" >/dev/null 2>&1 || true
  else
    log "kept runner container: $container"
  fi
}
trap cleanup EXIT

log "starting runner $container from $image"
docker run -d --platform linux/amd64 --name "$container" "$image" sleep infinity >/dev/null
docker cp "$hsbb_linux" "$container:/usr/local/bin/hsbb"
docker exec "$container" chmod +x /usr/local/bin/hsbb

cat >"$host_out/runner.env" <<EOF
task=$task
image=$image
mode=$mode
container=$container
hsbb_linux=$hsbb_linux
container_out=$container_out
repo_root=$repo_root
EOF

set +e
if [[ "$mode" == "app" ]]; then
  log "running /workspace/executable $*"
  docker exec "$container" /workspace/executable "$@" >"$host_out/stdout.txt" 2>"$host_out/stderr.txt"
  exit_code=$?
else
  if [[ $# -eq 0 ]]; then
    echo "hsbb mode requires args after --" >&2
    exit 2
  fi
  log "running hsbb $*"
  docker exec "$container" hsbb "$@" >"$host_out/stdout.txt" 2>"$host_out/stderr.txt"
  exit_code=$?
fi
set -e

printf '%s\n' "$exit_code" >"$host_out/exit_code"

if [[ "$mode" == "hsbb" ]]; then
  if docker exec "$container" test -e "$container_out" >/dev/null 2>&1; then
    docker cp "$container:$container_out" "$host_out/container-out"
  fi
fi

log "exit code: $exit_code"
log "host output: $host_out"
exit "$exit_code"
