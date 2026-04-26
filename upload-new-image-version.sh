#!/usr/bin/env bash
set -euo pipefail

if [ ! -f /etc/NIXOS ]; then
  echo "Error: this script must be run on NixOS" >&2
  exit 1
fi

usage() {
  cat >&2 <<EOF
Usage: $0 --profile <profile> --imageName <image_name> --publicPath <public_path> --publicIp <public_ip> [--region <region>]

  --region defaults to eu (valid: us, uk, eu, asia)

Example:
  $0 --profile base --imageName nixos-25-11-next \\
    --publicPath ~/docker-webserver/public/ \\
    --publicIp \$(curl -fsS https://api.ipify.org)
EOF
  exit 1
}

PROFILE=""
IMAGE_NAME=""
PUBLIC_PATH=""
PUBLIC_IP=""
REGION="eu"
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)     PROFILE="${2:-}";     shift 2 ;;
    --imageName)   IMAGE_NAME="${2:-}";  shift 2 ;;
    --publicPath)  PUBLIC_PATH="${2:-}"; shift 2 ;;
    --publicIp)    PUBLIC_IP="${2:-}";   shift 2 ;;
    --region)      REGION="${2:-}";      shift 2 ;;
    -h|--help)     usage ;;
    *)             usage ;;
  esac
done

[ -n "$PROFILE" ] && [ -n "$IMAGE_NAME" ] && [ -n "$PUBLIC_PATH" ] && [ -n "$PUBLIC_IP" ] && [ -n "$REGION" ] || usage

PUBLIC_PATH="${PUBLIC_PATH/#\~/$HOME}"
PUBLIC_PATH="${PUBLIC_PATH%/}"

cd "$(dirname "$0")"

echo ">> Checking webserver at http://${PUBLIC_IP}/"
if ! curl -fsS -o /dev/null "http://${PUBLIC_IP}/"; then
  echo "Error: http://${PUBLIC_IP}/ is not reachable" >&2
  exit 1
fi

if [ ! -d "$PUBLIC_PATH" ]; then
  echo "Error: public path does not exist: $PUBLIC_PATH" >&2
  exit 1
fi
if [ ! -w "$PUBLIC_PATH" ]; then
  echo "Error: public path is not writable: $PUBLIC_PATH" >&2
  exit 1
fi

REPO=$(git config --get remote.origin.url 2>/dev/null || echo "")
SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
NIX_PROFILE="./flake.nix#${PROFILE}"
METADATA=$(jq -nc \
  --arg repo "$REPO" \
  --arg sha "$SHA" \
  --arg branch "$BRANCH" \
  --arg profile "$NIX_PROFILE" \
  '{repo: $repo, sha: $sha, branch: $branch, nixProfile: $profile}')

EXISTS=$(machine0 images ls --json | jq -r --arg n "$IMAGE_NAME" '[.[] | select(.name == $n)] | length')
if [ "$EXISTS" -gt 0 ]; then
  LATEST_META=$(machine0 images versions ls "$IMAGE_NAME" --json | jq -c 'sort_by(.version) | last | .metadata // {}')
  LATEST_SHA=$(echo "$LATEST_META" | jq -r '.sha // ""')
  LATEST_BRANCH=$(echo "$LATEST_META" | jq -r '.branch // ""')
  LATEST_PROFILE=$(echo "$LATEST_META" | jq -r '.nixProfile // ""')
  if [ "$LATEST_SHA" = "$SHA" ] && [ "$LATEST_BRANCH" = "$BRANCH" ] && [ "$LATEST_PROFILE" = "$NIX_PROFILE" ]; then
    echo "Warning: latest version of ${IMAGE_NAME} already matches current sha/branch/nixProfile — no update needed" >&2
    exit 0
  fi
fi

echo ">> Building image for profile: $PROFILE"
IMAGE_PATH=$(./make-image.sh "$PROFILE")
echo ">> Built: $IMAGE_PATH"

FILENAME="${IMAGE_NAME}.qcow2.gz"
DEST="${PUBLIC_PATH}/${FILENAME}"
URL="http://${PUBLIC_IP}/${FILENAME}"

echo ">> Copying to ${DEST}"
cp -f "$IMAGE_PATH" "$DEST"
chmod 644 "$DEST"

echo ">> Verifying ${URL}"
if ! curl -fsSI -o /dev/null "$URL"; then
  echo "Error: uploaded image is not reachable at $URL" >&2
  exit 1
fi

if [ "$EXISTS" -gt 0 ]; then
  echo ">> Waiting for image ${IMAGE_NAME} to reach READY state before mutating"
  for i in $(seq 1 120); do
    STATUS=$(machine0 images get "$IMAGE_NAME" --json | jq -r '.image.status')
    case "$STATUS" in
      READY)    echo ">> Image is READY";                                 break ;;
      CREATING) sleep 5 ;;
      *)        echo "Error: image ${IMAGE_NAME} is in status ${STATUS}; refusing to proceed" >&2; exit 1 ;;
    esac
  done
  if [ "$STATUS" != "READY" ]; then
    echo "Error: image ${IMAGE_NAME} did not reach READY state in time (last: ${STATUS})" >&2
    exit 1
  fi

  DRAFTS=$(machine0 images versions ls "$IMAGE_NAME" --json | jq -r '.[] | select(.displayStatus == "DRAFT") | .version')
  for v in $DRAFTS; do
    echo ">> Deleting existing draft version v${v} of ${IMAGE_NAME}"
    machine0 images versions rm "$IMAGE_NAME" "$v" --yes
  done
else
  echo ">> Image ${IMAGE_NAME} does not exist yet — will be created"
fi

echo ">> Uploading ${URL} as ${IMAGE_NAME} (region: ${REGION})"
echo ">> Metadata: ${METADATA}"
machine0 images upload "$URL" \
  --name "$IMAGE_NAME" \
  --region "$REGION" \
  --distribution nixos \
  --metadata "$METADATA" \
  --force-system-version

echo
echo ">> Done. The image \"${IMAGE_NAME}\" is uploading."
echo ">> Once ready, try it with: machine0 new <vm> --image ${IMAGE_NAME}"
