#!/usr/bin/env bash
# SANDBOX SYMPHONY HELPER — not part of the conformance run.
#
# The deployment scenario (wfm-multi-component-deployment) needs an application
# deployment assigned to the CTT's client. Assigning one is an operator action
# in the WFM and is outside the Margo specification, so the CTT run never does
# it. This helper does it for the sandbox Symphony, through Symphony's own
# operator API (NBI, port 8082) — the same API the sandbox's wfm-cli.sh uses.
# For any other WFM, assign the deployment with that WFM's own console or API.
#
# WHAT THIS DOES
#   1. Logs in to Symphony's NBI and gets a token.
#   2. Registers the CTT's test app package from the sandbox Harbor.
#   3. Creates an ApplicationDeployment with two components
#      (one wait:true, one wait:false) assigned to the CTT's client SPIFFE ID.
#
# USAGE (sandbox Symphony, no arguments needed; run it before the CTT run)
#   bash provision-multi-component.sh
#
# OPTIONS
#   --nbi-url URL         Symphony NBI base URL (default: https://localhost:8082/v1alpha2)
#   --nbi-user USER       NBI username      (default: admin)
#   --nbi-pass PASS       NBI password      (default: empty string — Symphony test-user default)
#   --registry-url URL    OCI registry host (default: harbor.machine:8443)
#   --registry-repo REPO  OCI repository    (default: library/margo-ctt-hello-world)
#   --registry-tag TAG    OCI tag           (default: 1.0.0)
#   --device-id ID        Client SPIFFE ID  (default: read from the client SVID installed by
#                         ctt-runner "Setup MIAF Identity")
#   --mi-url URL          Symphony Management Interface URL, used for the check at the end
#                         (default: https://localhost:8084/v1alpha2/margo)
#   --compose-image REF   oci:// ref for compose components (default: oci://harbor.machine:8443/library/nextcloud-compose-archive)
#
# CLEANUP
#   Pass --cleanup to delete the provisioned package and deployment (idempotent).

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
NBI_URL="https://localhost:8082/v1alpha2"
NBI_USER="admin"
NBI_PASS=""
REGISTRY_URL="harbor.machine:8443"
REGISTRY_REPO="library/margo-ctt-hello-world"
REGISTRY_TAG="1.0.0"
DEVICE_ID=""   # default: the SPIFFE ID of the installed client SVID (see below)
COMPOSE_IMAGE="oci://harbor.machine:8443/library/nextcloud-compose-archive"
CLEANUP=false
PKG_NAME="ctt-multi-component-app"
DEPLOY_NAME="ctt-multi-component-deployment"

ORIG_ARGS=("$@")
MI_URL="https://localhost:8084/v1alpha2/margo"   # Symphony's Management Interface, for the check at the end

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --nbi-url)      NBI_URL="$2";       shift 2 ;;
    --nbi-user)     NBI_USER="$2";      shift 2 ;;
    --nbi-pass)     NBI_PASS="$2";      shift 2 ;;
    --registry-url) REGISTRY_URL="$2";  shift 2 ;;
    --registry-repo)REGISTRY_REPO="$2"; shift 2 ;;
    --registry-tag) REGISTRY_TAG="$2";  shift 2 ;;
    --device-id)    DEVICE_ID="$2";     shift 2 ;;
    --compose-image)COMPOSE_IMAGE="$2"; shift 2 ;;
    --mi-url)       MI_URL="$2";        shift 2 ;;
    --cleanup)      CLEANUP=true;       shift   ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# The deployment is assigned to the identity the CTT presents: read it from the
# client SVID that "Setup MIAF Identity" installed, unless --device-id was given.
if [[ -z "$DEVICE_ID" && "$CLEANUP" != "true" ]]; then
  SVID_CERT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/miaf/real/client-svid-cert.pem"
  if [[ -f "$SVID_CERT" ]]; then
    DEVICE_ID=$(openssl x509 -in "$SVID_CERT" -text -noout 2>/dev/null \
      | grep -oE 'URI:spiffe://[^[:space:]]+' | head -1 | sed 's/URI://' || true)
  fi
  if [[ -z "$DEVICE_ID" ]]; then
    echo "ERROR: no client SVID installed yet. Run ctt-runner/ctt-start.sh → WFM Supplier → Setup MIAF Identity first,"
    echo "       or pass --device-id with the client SPIFFE ID."
    exit 1
  fi
fi
echo "Client SPIFFE ID: ${DEVICE_ID:-(not needed for cleanup)}"

PKGS_URL="$NBI_URL/margo/nbi/v1/app-packages"
DEPS_URL="$NBI_URL/margo/nbi/v1/app-deployments"

# ── Auth ─────────────────────────────────────────────────────────────────────
echo "Authenticating with WFM NBI at $NBI_URL ..."
TOKEN=$(curl -sk -X POST "$NBI_URL/users/auth" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$NBI_USER\",\"password\":\"$NBI_PASS\"}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('accessToken',''))" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: failed to get auth token from $NBI_URL/users/auth"
  echo "  Check --nbi-url, --nbi-user, --nbi-pass"
  exit 1
fi
echo "  Auth OK"

# ── Helper: curl with auth ────────────────────────────────────────────────────
nbi() { curl -sk -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$@"; }

# ── Helper: finish the removal of the CTT client's deleted deployments ───────
# Symphony keeps a deleted deployment in REMOVING until the device reports
# "removed" (Margo Deployment Status). Here the device is the CTT's client, so the
# helper reports it, over the Management Interface with the CTT's own client SVID,
# and only for deployments assigned to that client. Without this the deployments
# stay REMOVING, and once their package is deleted the sandbox Symphony crashes
# when it rebuilds the Deployment Bundle.
SVID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/miaf/real"
CLIENT_ID=""
if [[ -f "$SVID_DIR/client-svid-cert.pem" && -f "$SVID_DIR/client-svid-key.pem" ]]; then
  CLIENT_ID=$(openssl x509 -in "$SVID_DIR/client-svid-cert.pem" -text -noout 2>/dev/null \
    | grep -oE 'URI:spiffe://[^[:space:]]+' | head -1 | sed 's/URI://' || true)
fi
removing_ids() {
  nbi "$DEPS_URL" | python3 -c "
import sys,json
for i in json.load(sys.stdin).get('items') or []:
    if i.get('status',{}).get('state','') == 'REMOVING' and i.get('spec',{}).get('deviceRef',{}).get('id','') == '$CLIENT_ID':
        print(i.get('id',''))
" 2>/dev/null || true
}
finish_removals() {
  [[ -n "$CLIENT_ID" ]] || return 0
  local ids id code
  ids=$(removing_ids)
  [[ -n "$ids" ]] || return 0
  for id in $ids; do
    code=$(curl -sk -m 15 --cert "$SVID_DIR/client-svid-cert.pem" --key "$SVID_DIR/client-svid-key.pem" \
      -H "Content-Type: application/json" -X POST "$MI_URL/api/v1/deployments/$id/status" \
      -d "{\"deploymentId\":\"$id\",\"adoptedManifestVersion\":1,\"status\":{\"state\":\"removed\"},\"components\":[]}" \
      -o /dev/null -w '%{http_code}' || true)
    echo "  Reported 'removed' for deployment $id (HTTP $code)"
  done
  for _ in 1 2 3 4 5; do
    [[ -z "$(removing_ids)" ]] && return 0
    sleep 2
  done
  echo "  WARNING: deployments still REMOVING: $(removing_ids | tr '\n' ' ')"
}

# ── Cleanup mode ─────────────────────────────────────────────────────────────
if [[ "$CLEANUP" == "true" ]]; then
  echo "Cleanup: looking for provisioned package and deployment..."
  PKGS=$(nbi "$PKGS_URL")
  PKG_ID=$(echo "$PKGS" | python3 -c "
import sys,json
items=json.load(sys.stdin).get('items') or []
for i in items:
    if i.get('metadata',{}).get('name','') == '$PKG_NAME':
        print(i.get('id',''))
        break
" 2>/dev/null)
  DEPS=$(nbi "$DEPS_URL")
  DEP_IDS=$(echo "$DEPS" | python3 -c "
import sys,json
items=json.load(sys.stdin).get('items') or []
for i in items:
    n = i.get('metadata',{}).get('name','')
    if n.startswith('ctt-multi-component-'):
        print(i.get('id',''))
" 2>/dev/null)
  for DEP_ID in $DEP_IDS; do
    nbi -X DELETE "$DEPS_URL/$DEP_ID" >/dev/null && echo "  Deleted deployment $DEP_ID"
  done
  finish_removals
  # Delete the package only when no deployment refers to it any more.
  IN_USE=$(nbi "$DEPS_URL" | python3 -c "
import sys,json
print(sum(1 for i in json.load(sys.stdin).get('items') or [] if i.get('spec',{}).get('appPackageRef',{}).get('id','') == '$PKG_ID'))
" 2>/dev/null || echo 0)
  if [[ -n "$PKG_ID" && "$IN_USE" != "0" ]]; then
    echo "  Package $PKG_ID kept: $IN_USE deployment(s) still refer to it"
  elif [[ -n "$PKG_ID" ]]; then
    nbi -X DELETE "$PKGS_URL/$PKG_ID" >/dev/null && echo "  Deleted package $PKG_ID"
  fi
  echo "Cleanup done."
  exit 0
fi

# Deployments left in REMOVING by earlier runs would crash Symphony on the next
# bundle rebuild (when the deployment below is created): finish their removal first.
finish_removals

# ── Step 1: Register app package ─────────────────────────────────────────────
echo "Checking for existing app package '$PKG_NAME'..."
PKGS=$(nbi "$PKGS_URL")
PKG_ID=$(echo "$PKGS" | python3 -c "
import sys,json
items=json.load(sys.stdin).get('items') or []
for i in items:
    if i.get('metadata',{}).get('name','') == '$PKG_NAME':
        print(i.get('id',''))
        break
" 2>/dev/null)

if [[ -n "$PKG_ID" ]]; then
  echo "  App package already registered: $PKG_ID"
else
  echo "Registering app package from $REGISTRY_URL/$REGISTRY_REPO:$REGISTRY_TAG ..."
  RESP=$(nbi -X POST "$PKGS_URL" -d "{
    \"apiVersion\": \"v1\",
    \"metadata\": {\"name\": \"$PKG_NAME\"},
    \"spec\": {
      \"sourceType\": \"OCI_REPO\",
      \"source\": {
        \"registryUrl\": \"$REGISTRY_URL\",
        \"repository\": \"$REGISTRY_REPO\",
        \"tag\": \"$REGISTRY_TAG\"
      }
    }
  }")
  PKG_ID=$(echo "$RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('Package',d).get('id',''))
" 2>/dev/null)
  if [[ -z "$PKG_ID" ]]; then
    echo "ERROR: failed to register app package. Response:"
    echo "$RESP"
    exit 1
  fi
  echo "  Registered package: $PKG_ID"

  # Poll until COMPLETED
  echo "  Waiting for package onboarding to complete..."
  for i in $(seq 1 20); do
    sleep 2
    STATUS=$(nbi "$PKGS_URL/$PKG_ID" | python3 -c "
import sys,json
items=json.load(sys.stdin).get('items') or [{}]
print(items[0].get('recentOperation',{}).get('status',''))
" 2>/dev/null)
    [[ "$STATUS" == "COMPLETED" ]] && echo "  Package onboarded (COMPLETED)" && break
    [[ "$STATUS" == "FAILED" ]]    && echo "ERROR: package onboarding FAILED" && exit 1
    echo "  ... ($STATUS)"
  done
fi

# ── Step 2: Create deployment ─────────────────────────────────────────────────
# Use a timestamp suffix so re-runs after a stuck REMOVING deployment always get a fresh one.
DEPLOY_NAME="ctt-multi-component-$(date -u +%Y%m%d%H%M%S)"

echo "Checking for active deployment for device '$DEVICE_ID'..."
DEPS=$(nbi "$DEPS_URL")
DEP_ID=$(echo "$DEPS" | python3 -c "
import sys,json
items=json.load(sys.stdin).get('items') or []
for i in items:
    state = i.get('status',{}).get('state','')
    dev_id = i.get('spec',{}).get('deviceRef',{}).get('id','')
    # Only reuse an actively deployed deployment (not REMOVING/FAILED)
    if dev_id == '$DEVICE_ID' and state not in ('REMOVING','FAILED',''):
        print(i.get('id',''))
        break
" 2>/dev/null)

if [[ -n "$DEP_ID" ]]; then
  echo "  Active deployment already exists: $DEP_ID"
else
  echo "Creating deployment targeting device: $DEVICE_ID ..."
  RESP=$(nbi -X POST "$DEPS_URL" -d "{
    \"metadata\": {\"name\": \"$DEPLOY_NAME\"},
    \"spec\": {
      \"appPackageRef\": {\"id\": \"$PKG_ID\"},
      \"deviceRef\": {\"id\": \"$DEVICE_ID\"},
      \"deploymentProfile\": {
        \"type\": \"compose\",
        \"components\": [
          {
            \"name\": \"wait-true-component\",
            \"properties\": {
              \"repository\": \"$COMPOSE_IMAGE\",
              \"revision\": \"1.0.0\",
              \"wait\": true
            }
          },
          {
            \"name\": \"wait-false-component\",
            \"properties\": {
              \"repository\": \"$COMPOSE_IMAGE\",
              \"revision\": \"1.0.0\",
              \"wait\": false
            }
          }
        ]
      }
    }
  }")
  DEP_ID=$(echo "$RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('id',''))
" 2>/dev/null)
  if [[ -z "$DEP_ID" ]]; then
    echo "ERROR: failed to create deployment. Response:"
    echo "$RESP"
    exit 1
  fi
  echo "  Deployment created: $DEP_ID"
fi

# ── Check: does Symphony deliver the deployment on the Management Interface? ──
# After a reboot or a re-created Symphony container the deployment can exist on
# the NBI while the Management Interface lists none, or its bundle download
# fails (the bundle file was lost). The CTT run would then wait or fail. So ask
# the Management Interface with the CTT's own client SVID, and repair once or
# twice by deleting and creating the deployment again.
mi_state() {
  python3 - "$MI_URL" "$SVID_DIR/client-svid-cert.pem" "$SVID_DIR/client-svid-key.pem" <<'PY'
import json, subprocess, sys
url, cert, key = sys.argv[1:4]
def get(path, accept, out):
    return subprocess.run(["curl", "-sk", "-m", "10", "--cert", cert, "--key", key,
        "-H", "Accept: " + accept, "-o", out, "-w", "%{http_code}", url + path],
        capture_output=True, text=True).stdout.strip()
code = get("/api/v1/deployments", "application/vnd.margo.manifest.v1+json", "/tmp/.ctt-provision-manifest.json")
if code != "200":
    print("unreachable (HTTP %s)" % (code or "none")); sys.exit(0)
m = json.load(open("/tmp/.ctt-provision-manifest.json"))
if not m.get("deployments"):
    print("not-listed"); sys.exit(0)
digest = (m.get("bundle") or {}).get("digest", "")
code = get("/api/v1/bundles/" + digest, "application/vnd.margo.bundle.v1+tar+gzip", "/dev/null")
print("ok" if code == "200" else "bundle-broken (HTTP %s)" % code)
PY
}
if [[ -f "$SVID_DIR/client-svid-cert.pem" && -f "$SVID_DIR/client-svid-key.pem" ]]; then
  STATE="not-listed"
  for _ in 1 2 3 4 5; do
    STATE="$(mi_state)"
    [[ "$STATE" == "not-listed" ]] || break
    sleep 2
  done
  echo "Check on the Management Interface ($MI_URL): $STATE"
  if [[ "$STATE" == not-listed || "$STATE" == bundle-broken* ]]; then
    ATTEMPT="${CTT_PROVISION_ATTEMPT:-1}"
    if (( ATTEMPT >= 3 )); then
      echo "ERROR: Symphony still does not deliver the deployment after $ATTEMPT attempts."
      echo "       Restart Symphony (wfm.sh options 4 and 3) and run this helper again."
      exit 1
    fi
    echo "Symphony does not deliver the deployment correctly (usual after a reboot or a Symphony restart)."
    echo "Deleting it and creating it again (attempt $((ATTEMPT + 1)) of 3)..."
    CTT_PROVISION_ATTEMPT=$((ATTEMPT + 1)) bash "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]}" --cleanup
    CTT_PROVISION_ATTEMPT=$((ATTEMPT + 1)) exec bash "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]}"
  elif [[ "$STATE" != ok ]]; then
    echo "WARNING: could not check the Management Interface ($STATE). Is --mi-url right, and is the CTT's client on Symphony's allowlist?"
  fi
fi

echo ""
echo "Done. Multi-component deployment provisioned:"
echo "  Package ID   : $PKG_ID"
echo "  Deployment ID: $DEP_ID"
echo "  Device       : $DEVICE_ID"
echo ""
echo "You can now run the wfm-multi-component-deployment scenario."
echo "To clean up afterwards: bash provision-multi-component.sh --cleanup"
