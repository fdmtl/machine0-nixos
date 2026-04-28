#!/usr/bin/env bash
#
# test-draft-images.sh — boot a fresh VM from each draft image listed in
# TARGETS, then time how long `machine0 provision` takes once SSH is up.
# The VM boot/SSH-wait time is excluded — we only time the provision
# command itself, so the number reflects rsync + nixos-rebuild and
# nothing else.
#
# Flow:
#   1. Destroy any leftover VM with the same name.
#   2. Submit `machine0 new` for every target in parallel.
#   3. Race SSH readiness — whichever VM comes up first is provisioned
#      first. The remaining VMs are provisioned as soon as they are
#      reachable (in declaration order).
#   4. Print per-VM provision wall time.
#
# To add a target, append "vm-name|image-name|profile" to TARGETS.

set -euo pipefail

# === CONFIG =================================================================

REGION="eu"
DEFAULT_SIZE="small"    # per-profile override via manifest.json `testSize`
SSH_PROBE_TIMEOUT=900   # max seconds to wait for any VM to reach SSH-ready
SSH_POLL_INTERVAL=3     # seconds between SSH probes

LOG_DIR="/tmp/test-draft-images-logs"

cd "$(dirname "$0")"

if [ ! -f manifest.json ]; then
  echo "Error: manifest.json not found in $(pwd)" >&2
  exit 1
fi

# Per-image target version is auto-detected: prefer the latest DRAFT, but
# fall back to the latest version overall if none exists. The fallback
# covers brand-new images, where the first uploaded version is
# auto-promoted to ACTIVE by the backend (no prior version to keep active).
draft_version_for() {
  machine0 images versions ls "$1" --json \
    | jq -r '
        ([.[] | select(.displayStatus == "DRAFT")] | sort_by(.version) | last | .version) //
        (sort_by(.version) | last | .version) // ""
      '
}

# Each target = "vm-name|image-name|profile|version|size" — derived from manifest.json.
#   vm-name : test VM to (re)create (test-<profile>-v<version>)
#   image   : machine0 image slug
#   profile : flake attribute (passed as ".#<profile>" to provision)
#   version : draft version (auto-detected per-image)
#   size    : machine0 VM size (manifest.json `testSize`, falls back to DEFAULT_SIZE)
TARGETS=()
while IFS='|' read -r IMAGE PROFILE SIZE; do
  [[ -z "$SIZE" ]] && SIZE="$DEFAULT_SIZE"
  VERSION=$(draft_version_for "$IMAGE")
  if [ -z "$VERSION" ]; then
    echo "Error: no version found for image $IMAGE — run ./update-all-images.sh first" >&2
    exit 1
  fi
  TARGETS+=("test-${PROFILE}-v${VERSION}|${IMAGE}|${PROFILE}|${VERSION}|${SIZE}")
done < <(jq -r '.profiles[] | "\(.image)|\(.profile)|\(.testSize // "")"' manifest.json)

# === HELPERS ================================================================

now_s()      { date +%s; }
log()        { echo "[$(date -Iseconds)] $*"; }
fmt_secs()   { printf "%dm%02ds" $(( $1 / 60 )) $(( $1 % 60 )); }
target_vm()      { echo "$1" | cut -d'|' -f1; }
target_image()   { echo "$1" | cut -d'|' -f2; }
target_profile() { echo "$1" | cut -d'|' -f3; }
target_version() { echo "$1" | cut -d'|' -f4; }
target_size()    { echo "$1" | cut -d'|' -f5; }

vm_exists() {
  machine0 ls --json | jq -e --arg n "$1" '.[] | select(.name == $n)' >/dev/null
}

destroy_vm_if_exists() {
  local vm="$1"
  if vm_exists "$vm"; then
    log ">> Removing existing VM $vm"
    machine0 rm "$vm" --yes >/dev/null
  fi
}

create_vm() {
  local vm="$1" image="$2" version="$3" size="$4"
  log ">> Creating $vm from $image v$version (size=$size)"
  machine0 new "$vm" \
    --size "$size" --region "$REGION" \
    --image "$image" --image-version "$version" >/dev/null
}

ssh_ready() {
  machine0 ssh "$1" 'true' >/dev/null 2>&1
}

wait_until_ssh_ready() {
  # Block until $1 accepts SSH or SSH_PROBE_TIMEOUT elapses.
  local vm="$1" deadline=$(( $(now_s) + SSH_PROBE_TIMEOUT ))
  while [ "$(now_s)" -lt "$deadline" ]; do
    if ssh_ready "$vm"; then return 0; fi
    sleep "$SSH_POLL_INTERVAL"
  done
  return 1
}

wait_for_first_ready() {
  # Echo the first target spec from $@ that becomes SSH-ready.
  local deadline=$(( $(now_s) + SSH_PROBE_TIMEOUT ))
  while [ "$(now_s)" -lt "$deadline" ]; do
    for spec in "$@"; do
      if ssh_ready "$(target_vm "$spec")"; then
        echo "$spec"
        return 0
      fi
    done
    sleep "$SSH_POLL_INTERVAL"
  done
  return 1
}

time_provision() {
  # Run provision, capture full output to $log_file, echo elapsed seconds.
  local vm="$1" profile="$2" log_file="$3"
  local start end
  start=$(now_s)
  if machine0 provision "$vm" ".#$profile" >"$log_file" 2>&1; then
    end=$(now_s)
    echo $(( end - start ))
  else
    end=$(now_s)
    echo "FAIL:$(( end - start ))"
    return 1
  fi
}

cleanup_targets() {
  for spec in "${TARGETS[@]}"; do
    destroy_vm_if_exists "$(target_vm "$spec")"
  done
}

create_all_in_parallel() {
  local pids=()
  for spec in "${TARGETS[@]}"; do
    create_vm "$(target_vm "$spec")" "$(target_image "$spec")" "$(target_version "$spec")" "$(target_size "$spec")" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
}

# === MAIN ===================================================================

rm -rf "$LOG_DIR"; mkdir -p "$LOG_DIR"

log "================ PHASE 0: clean any leftover VMs ================"
cleanup_targets

log "================ PHASE 1: create VMs in parallel ================"
create_all_in_parallel

log "================ PHASE 2: race SSH readiness, provision in order ================"
declare -A TIMINGS=()
ORDER=()
remaining=("${TARGETS[@]}")

while [ "${#remaining[@]}" -gt 0 ]; do
  log ">> Waiting for any of: $(printf '%s ' "${remaining[@]/|*/}")"
  if ! next_spec=$(wait_for_first_ready "${remaining[@]}"); then
    log "ERROR: no remaining VM became SSH-ready within ${SSH_PROBE_TIMEOUT}s"
    exit 1
  fi
  vm=$(target_vm "$next_spec")
  profile=$(target_profile "$next_spec")
  log ">> $vm is SSH-ready — provisioning with .#$profile"
  if result=$(time_provision "$vm" "$profile" "$LOG_DIR/provision-$vm.log"); then
    log ">> $vm provisioned in $(fmt_secs "$result") (${result}s)"
  else
    log ">> $vm provision FAILED (see $LOG_DIR/provision-$vm.log)"
  fi
  TIMINGS[$vm]="$result"
  ORDER+=("$next_spec")

  # Drop $next_spec from remaining
  new_remaining=()
  for spec in "${remaining[@]}"; do
    [ "$spec" != "$next_spec" ] && new_remaining+=("$spec")
  done
  remaining=("${new_remaining[@]:-}")
  # Bash treats empty-array expansion as unset under set -u; guard above.
  [ -z "${remaining[0]:-}" ] && remaining=()
done

log "================ TIMINGS ================"
for spec in "${ORDER[@]}"; do
  vm=$(target_vm "$spec")
  profile=$(target_profile "$spec")
  result="${TIMINGS[$vm]}"
  if [[ "$result" =~ ^[0-9]+$ ]]; then
    printf "  %-18s .#%-7s %s (%ss)\n" "$vm" "$profile" "$(fmt_secs "$result")" "$result"
  else
    printf "  %-18s .#%-7s %s\n" "$vm" "$profile" "$result"
  fi
done
echo
echo "Per-VM provision logs in $LOG_DIR"
