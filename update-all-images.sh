#!/usr/bin/env bash
#
# update-all-images.sh — wipe the public web folder, delete every DRAFT
# version of each image listed in manifest.json, then call
# ./upload-new-image-version.sh to publish a fresh DRAFT for each
# (image, profile) pair.
#
# Single source of truth for (profile -> image) is manifest.json.

set -euo pipefail

PUBLIC_PATH="${HOME}/docker-webserver/public"

cd "$(dirname "$0")"

if [ ! -f manifest.json ]; then
  echo "Error: manifest.json not found in $(pwd)" >&2
  exit 1
fi

# (image_name, profile) pairs to refresh — derived from manifest.json.
mapfile -t PAIRS < <(jq -r '.profiles[] | "\(.image):\(.profile)"' manifest.json)

echo ">> Detecting public IP..."
PUBLIC_IP=$(curl -fsS https://api.ipify.org)
echo ">> Public IP: ${PUBLIC_IP}"

if [ ! -d "$PUBLIC_PATH" ]; then
  echo "Error: public path does not exist: $PUBLIC_PATH" >&2
  exit 1
fi

echo ">> Cleaning ${PUBLIC_PATH}"
find "$PUBLIC_PATH" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -exec rm -rf {} +

for pair in "${PAIRS[@]}"; do
  IMAGE_NAME="${pair%%:*}"
  EXISTS=$(machine0 images ls --json | jq -r --arg n "$IMAGE_NAME" '[.[] | select(.name == $n)] | length')
  if [ "$EXISTS" -eq 0 ]; then
    echo ">> Image ${IMAGE_NAME} does not exist yet — nothing to clean"
    continue
  fi
  DRAFTS=$(machine0 images versions ls "$IMAGE_NAME" --json | jq -r '.[] | select(.displayStatus == "DRAFT") | .version')
  if [ -z "$DRAFTS" ]; then
    echo ">> No draft versions to delete for ${IMAGE_NAME}"
    continue
  fi
  for v in $DRAFTS; do
    echo ">> Deleting draft v${v} of ${IMAGE_NAME}"
    machine0 images versions rm "$IMAGE_NAME" "$v" --yes
  done
done

for pair in "${PAIRS[@]}"; do
  IMAGE_NAME="${pair%%:*}"
  PROFILE="${pair##*:}"
  echo
  echo "====================================================================="
  echo ">> Uploading ${IMAGE_NAME} (profile: ${PROFILE})"
  echo "====================================================================="
  ./upload-new-image-version.sh \
    --profile "$PROFILE" \
    --imageName "$IMAGE_NAME" \
    --publicPath "$PUBLIC_PATH" \
    --publicIp "$PUBLIC_IP"
done

echo
echo ">> All done. New DRAFT versions:"
for pair in "${PAIRS[@]}"; do
  IMAGE_NAME="${pair%%:*}"
  machine0 images versions ls "$IMAGE_NAME" --json \
    | jq -r --arg n "$IMAGE_NAME" '.[] | select(.displayStatus == "DRAFT") | "  \($n) v\(.version) (\(.metadata.branch // "?")@\(.metadata.sha // "?" | .[0:7]))"'
done
