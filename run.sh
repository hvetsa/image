#!/usr/bin/env bash
set -euo pipefail

IMAGE="hvetsa"
VERSION_FILE="$(dirname "$0")/VERSION"

# ─── Helpers ──────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [-- COMMAND]

Run the $IMAGE Docker container.

Options:
  -v, --version       VERSION   Image version tag to run (default: contents of VERSION file)
  -w, --workdir       PATH      Host directory to mount at /workspace (default: current dir)
  -k, --api-key       KEY       Anthropic API key (default: \$ANTHROPIC_API_KEY env var)
  -i, --ssh-key       PATH      Path to SSH private key file on host (sets SSH_PRIVATE_KEY_PATH env var)
  -e, --secrets       PATH      Path to secrets .env file on host (sets SECRETS_FILE_PATH env var)
  -s, --secure-zone   PATH      Host directory containing id_rsa and .env files (mounts at /Documents/secure_zone)
  -c, --copy          HOST_FILE:CONTAINER_PATH  Copy file from host to container after startup (repeatable)
  --docker                      Mount /var/run/docker.sock for Docker-in-Docker access (default: enabled)
  --no-docker                   Disable Docker socket mounting
  --name              NAME      Container name (default: hvetsa-dev)
  --port              PORT      Expose a port  HOST:CONTAINER  (repeatable)
  -d, --detach                  Run container in background
  -h, --help                    Show this help

Examples:
  $(basename "$0")                                   # interactive shell, current dir mounted
  $(basename "$0") -w ~/projects/myapp               # mount specific workspace
  $(basename "$0") -i ~/.ssh/id_rsa -e ~/secrets.env # pass SSH key and secrets file paths
  $(basename "$0") -s ~/secure                       # mount secure zone with SSH key and secrets
  $(basename "$0") -c ~/.config/claude.json:/root/.config/claude.json  # copy config file
  $(basename "$0") --no-docker                       # disable Docker socket mounting
  $(basename "$0") -v 1.2.0                          # run a specific version
  $(basename "$0") --port 8888:8888 -- jupyter lab   # start JupyterLab
  $(basename "$0") -- claude                         # open Claude Code directly
EOF
}

# ─── Defaults ─────────────────────────────────────────────────────────────────
VERSION=""
WORKDIR="$(pwd)"
API_KEY="${ANTHROPIC_API_KEY:-}"
SSH_KEY_PATH=""
SECRETS_PATH=""
SECURE_ZONE=""
COPY_FILES=()
MOUNT_DOCKER=true
CONTAINER_NAME="hvetsa-dev"
DETACH=false
PORTS=()
CMD=()

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)  VERSION="$2";         shift 2 ;;
    -w|--workdir)  WORKDIR="$2";         shift 2 ;;
    -k|--api-key)  API_KEY="$2";         shift 2 ;;
    -i|--ssh-key)  SSH_KEY_PATH="$2";    shift 2 ;;
    -e|--secrets)  SECRETS_PATH="$2";    shift 2 ;;
    -s|--secure-zone) SECURE_ZONE="$2"; shift 2 ;;
    -c|--copy)     COPY_FILES+=("$2");    shift 2 ;;
    --docker)      MOUNT_DOCKER=true;    shift ;;
    --no-docker)   MOUNT_DOCKER=false;   shift ;;
    --name)        CONTAINER_NAME="$2";  shift 2 ;;
    --port)        PORTS+=("$2");        shift 2 ;;
    -d|--detach)   DETACH=true;          shift ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; CMD=("$@");    break ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done



# ─── Resolve version ──────────────────────────────────────────────────────────
if [[ -z "$VERSION" ]]; then
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "ERROR: VERSION file not found at $VERSION_FILE" >&2; exit 1
  fi
  VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
fi

# ─── Assemble docker run flags ────────────────────────────────────────────────
RUN_FLAGS=(
  --rm
  --name "$CONTAINER_NAME"
  -v "$WORKDIR:/workspace"
  -w /workspace
  -d  # Always run detached first for copying
)

[[ "$DETACH" == true ]] && RUN_FLAGS+=(-d) || RUN_FLAGS+=(-it)

if [[ -n "$API_KEY" ]]; then
  RUN_FLAGS+=(-e "ANTHROPIC_API_KEY=$API_KEY")
else
  echo "WARNING: ANTHROPIC_API_KEY is not set — Claude Code will not be able to authenticate." >&2
fi

if [[ -n "$SSH_KEY_PATH" ]]; then
  RUN_FLAGS+=(-e "SSH_PRIVATE_KEY_PATH=$SSH_KEY_PATH")
fi

if [[ -n "$SECRETS_PATH" ]]; then
  RUN_FLAGS+=(-e "SECRETS_FILE_PATH=$SECRETS_PATH")
fi

if [[ "$MOUNT_DOCKER" == true ]]; then
  RUN_FLAGS+=(-v /var/run/docker.sock:/var/run/docker.sock)
fi

if [[ -n "$SECURE_ZONE" ]]; then
  RUN_FLAGS+=(-v "$SECURE_ZONE:/Documents/secure_zone")
fi

for port in "${PORTS[@]}"; do
  RUN_FLAGS+=(-p "$port")
done

# ─── Run ──────────────────────────────────────────────────────────────────────
echo "Starting $IMAGE:$VERSION ..."
echo "  Workspace : $WORKDIR → /workspace"
[[ -n "$API_KEY" ]]        && echo "  API key   : set"
[[ -n "$SSH_KEY_PATH" ]]   && echo "  SSH key   : $SSH_KEY_PATH"
[[ -n "$SECRETS_PATH" ]]   && echo "  Secrets   : $SECRETS_PATH"
[[ -n "$SECURE_ZONE" ]]    && echo "  Secure zone: $SECURE_ZONE → /Documents/secure_zone"
[[ ${#COPY_FILES[@]} -gt 0 ]] && echo "  Copy files: ${COPY_FILES[*]}"
[[ "$MOUNT_DOCKER" == true ]] && echo "  Docker    : socket mounted"
[[ "$MOUNT_DOCKER" == false ]] && echo "  Docker    : socket not mounted"
[[ ${#PORTS[@]} -gt 0 ]]   && echo "  Ports     : ${PORTS[*]}"
echo ""

# Start container detached
docker run "${RUN_FLAGS[@]}" "$IMAGE:$VERSION" "${CMD[@]}"

# Copy files if specified
for copy_spec in "${COPY_FILES[@]}"; do
  IFS=':' read -r HOST_FILE CONTAINER_PATH <<< "$copy_spec"
  echo "Copying $HOST_FILE to container:$CONTAINER_PATH ..."
  docker cp "$HOST_FILE" "$CONTAINER_NAME:$CONTAINER_PATH"
done

# Attach if not detached
if [[ "$DETACH" == false ]]; then
  docker attach "$CONTAINER_NAME"
fi
