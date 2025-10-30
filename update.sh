#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./update.sh

Synchronise the local repository with the configured online target using rsync.
Conflicts are detected and you will be prompted to choose whether the local or
online version should win for each conflicting file.

Configuration is loaded from environment variables (optionally via .env):
  TRP_ONLINE_HOST   Hostname or IP of the online target (required)
  TRP_ONLINE_PATH   Remote path that should mirror this repository (required)
  TRP_ONLINE_USER   SSH user for the remote host (defaults to current user)
  TRP_ONLINE_PORT   SSH port (optional)
  TRP_ONLINE_SSH_KEY  Path to SSH identity file (optional)
  TRP_ONLINE_SSH_OPTS Extra ssh options (quoted, optional)

Example:
  export TRP_ONLINE_HOST=example.com
  export TRP_ONLINE_USER=deployer
  export TRP_ONLINE_PATH=/opt/trp
  ./update.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

ONLINE_HOST=${TRP_ONLINE_HOST:-}
ONLINE_PATH=${TRP_ONLINE_PATH:-}
ONLINE_USER=${TRP_ONLINE_USER:-$(whoami)}
ONLINE_PORT=${TRP_ONLINE_PORT:-}
ONLINE_SSH_KEY=${TRP_ONLINE_SSH_KEY:-}
ONLINE_SSH_OPTS=${TRP_ONLINE_SSH_OPTS:-}

if [[ -z "$ONLINE_HOST" || -z "$ONLINE_PATH" ]]; then
  echo "Error: TRP_ONLINE_HOST and TRP_ONLINE_PATH must be provided (via environment or .env)." >&2
  exit 1
fi

for cmd in rsync ssh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is required but was not found in PATH." >&2
    exit 1
  fi
done

SSH_CMD=(ssh)
if [[ -n "$ONLINE_PORT" ]]; then
  SSH_CMD+=(-p "$ONLINE_PORT")
fi
if [[ -n "$ONLINE_SSH_KEY" ]]; then
  SSH_CMD+=(-i "$ONLINE_SSH_KEY")
fi
if [[ -n "$ONLINE_SSH_OPTS" ]]; then
  # shellcheck disable=SC2206
  extra_opts=($ONLINE_SSH_OPTS)
  SSH_CMD+=("${extra_opts[@]}")
fi
export RSYNC_RSH="${SSH_CMD[*]}"

REMOTE_TARGET="${ONLINE_USER}@${ONLINE_HOST}:${ONLINE_PATH%/}/"

EXCLUDES=(
  ".git"
  "node_modules"
  "api/node_modules"
  "web/node_modules"
  "web/dist"
  "web/.svelte-kit"
  "web/.vite"
  "api_node_modules"
  "pg_data"
  "redis_data"
  "*.log"
)

exclude_file=$(mktemp)
trap 'rm -f "$exclude_file" ${push_tmp:-} ${pull_tmp:-}' EXIT
printf '%s\n' "${EXCLUDES[@]}" >"$exclude_file"

RSYNC_DRY_ARGS=(--archive --verbose --exclude-from="$exclude_file" --out-format="%n" --dry-run)
RSYNC_RUN_ARGS=(--archive --verbose --exclude-from="$exclude_file")

cd "$REPO_ROOT"

declare -a local_candidates remote_candidates
mapfile -t local_candidates < <(rsync "${RSYNC_DRY_ARGS[@]}" ./ "$REMOTE_TARGET")
mapfile -t remote_candidates < <(rsync "${RSYNC_DRY_ARGS[@]}" "$REMOTE_TARGET" ./)

declare -A local_map
for path in "${local_candidates[@]}"; do
  [[ -z "$path" ]] && continue
  [[ "$path" == */ ]] && continue
  local_map["$path"]=1
done

local_only=()
for path in "${!local_map[@]}"; do
  local_only+=("$path")
fi

remote_only=()
conflicts=()

declare -A conflict_seen
for path in "${remote_candidates[@]}"; do
  [[ -z "$path" ]] && continue
  [[ "$path" == */ ]] && continue
  if [[ -n "${local_map[$path]:-}" ]]; then
    conflicts+=("$path")
    conflict_seen["$path"]=1
    unset 'local_map[$path]'
  else
    remote_only+=("$path")
  fi
done

# Remove conflict entries from local_only list
if (( ${#conflicts[@]} > 0 )); then
  tmp_local=()
  for path in "${local_only[@]}"; do
    if [[ -n "${conflict_seen[$path]:-}" ]]; then
      continue
    fi
    tmp_local+=("$path")
  done
  local_only=("${tmp_local[@]}")
fi

if (( ${#local_only[@]} == 0 && ${#remote_only[@]} == 0 && ${#conflicts[@]} == 0 )); then
  echo "No differences detected between local workspace and online target."
  exit 0
fi

echo "Summary of detected changes:"\n
echo "  Local-only updates to push:   ${#local_only[@]}"
echo "  Online-only updates to pull:  ${#remote_only[@]}"
echo "  Conflicts requiring choice:   ${#conflicts[@]}"\n
push_list=("${local_only[@]}")
pull_list=("${remote_only[@]}")

if (( ${#conflicts[@]} > 0 )); then
  echo "Resolving conflicts..."
  for path in "${conflicts[@]}"; do
    while true; do
      read -rp "Conflict for '$path'. Choose [l]ocal / [o]nline / [s]kip: " choice
      case "$choice" in
        l|L)
          push_list+=("$path")
          break
          ;;
        o|O)
          pull_list+=("$path")
          break
          ;;
        s|S)
          echo "  Skipping '$path'."
          break
          ;;
        *)
          echo "  Invalid choice. Please enter l, o, or s."
          ;;
      esac
    done
  done
fi

if (( ${#push_list[@]} > 0 )); then
  push_tmp=$(mktemp)
  printf '%s\n' "${push_list[@]}" >"$push_tmp"
  echo "\nUploading ${#push_list[@]} item(s) to online target..."
  rsync "${RSYNC_RUN_ARGS[@]}" --files-from="$push_tmp" ./ "$REMOTE_TARGET"
fi

if (( ${#pull_list[@]} > 0 )); then
  pull_tmp=$(mktemp)
  printf '%s\n' "${pull_list[@]}" >"$pull_tmp"
  echo "\nDownloading ${#pull_list[@]} item(s) from online target..."
  rsync "${RSYNC_RUN_ARGS[@]}" --files-from="$pull_tmp" "$REMOTE_TARGET" ./
fi

echo "\nSync complete. Review changes with 'git status'."
