# Device Supplier Conformance — Setup and Execution Guide

**Persona:** Device Supplier  
**Specification baseline:** Margo `1.0.0-rc.3`  
**Audience:** Device suppliers, WFM Client engineers, Margo adopters

This guide describes how to verify an Edge Compute Device — more precisely the
Workload Fleet Management Client (WFM Client) it hosts — for conformance with
the Margo specification using the Margo Conformance Test Toolkit (CTT). It
covers the prerequisites, identity provisioning, test execution and the
conformance report.

Terms are used as defined by Margo:
[Technical Lexicon](https://docs.margo.org/personas-and-definitions/technical-lexicon),
[Margo Identity and Authorization Framework](https://docs.margo.org/specification/identity/identity-framework),
[WFM Identity Profile](https://docs.margo.org/specification/identity/wfm-identity-profile)
and the Margo Management Interface
([API Requirements and Security](https://docs.margo.org/specification/margo-management-interface/api-requirements-and-security),
[Device Capabilities](https://docs.margo.org/specification/margo-management-interface/device-capabilities),
[Desired State](https://docs.margo.org/specification/margo-management-interface/desired-state),
[Deployment Status](https://docs.margo.org/specification/margo-management-interface/deployment-status)).

---

## Overview

In this persona the WFM Client of the device is the system under test. The CTT
acts as a Workload Fleet Manager (WFM): it runs a mock WFM that exposes the
Margo Management Interface. No external WFM is required. For demonstration,
the device agent of the Margo sandbox is used; a Device Supplier is expected to
bring their own device.

```
 Device under test                        CTT
 (sandbox device agent                    ┌──────────────────────────────────────────────┐
  or the device of a supplier)            │  Mock WFM                                    │
 ┌────────────────────┐      mTLS         │  port 3003  Margo Management Interface (mTLS)│
 │  WFM Client        │ ────────────────► │  port 3001  health and telemetry status      │
 └────────────────────┘                   │  assesses and records every request          │
                                          │  (rules: assertions.json)                    │
                                          └───────────────────┬──────────────────────────┘
                                                              │ group `core` reads the assessments
                                                              ▼
                                          ctt-runner/reports/device-supplier/
                                            conformance-report-<timestamp>.html  and  ..._signed.pdf
```

The mock WFM implements the Margo Management Interface of Margo `1.0.0-rc.3`.
It enforces mTLS and accepts only WFM Clients of its own WFM identity, serves
the State Manifest, the Deployment Bundle and the ApplicationDeployment YAML
with correct ETag and digest, validates every request body, and reports errors
as RFC 9457 problem details.

The CTT implements the Margo Identity and Authorization Framework (MIAF). The
mock WFM and the device authenticate each other by mutual TLS with X.509-SVIDs,
and each side authorizes its peer locally, based on the peer's verified SPIFFE
ID. A Margo Identity Service (MIS) must therefore exist for the Trust Domain;
it issues the X.509-SVIDs of the mock WFM and of the device.

There are two kinds of test groups:

- **`core` and its subsets assess the device.** The device connects to the mock
  WFM, and the CTT evaluates the requests it sends — including its reaction to
  a State Manifest it must reject. See
  [Phase 4](#phase-4--conformance-test-of-a-device).
- **`self-check` requires no device.** The test client of the CTT runs against
  the mock WFM to verify the setup before a device is connected
  ([Phase 3](#phase-3--verify-the-setup-no-device-required)). It makes no
  statement about a device.

---

## Prerequisites

### Tools on the CTT host

| Tool | Version | Purpose |
|---|---|---|
| Go | 1.21 or later (1.24 used) | Builds the mock WFM and the test runner ([installation](https://go.dev/doc/install)) |
| OpenSSL | 1.1 or later | Certificate inspection |
| jq | any | Reads the test group files |
| bash | 4 or later | Runs the CLI |
| Operating system | Linux | Verified on Ubuntu 24.04 |

### Network connectivity

When the MIS, the CTT and the device run on different hosts, the following
connections must be permitted before testing. A host that is reachable over SSH
can still have these ports closed.

| From | To | Port | Purpose |
|---|---|---|---|
| Device | CTT host | 3003 | Margo Management Interface exposed by the mock WFM; all device conformance tests |
| Device | MIS host | MIS trust endpoints (sandbox MIS: 9443) | The WFM Client connects to the MIS for discovery and to obtain the Trust Bundle (the sandbox device agent does). Not required when the operator provides the Trust Bundle to the device by configuration (out-of-band delivery) |
| Device | CTT host | 4318 and 9090 | `observability` group only |
| CTT host | MIS host | none | The CTT receives its identities and trust material out of band and does not connect to the MIS |

The host name under which the MIS is reachable is a configuration value. In
the Margo sandbox it is `EXPOSED_MIS_HOST` (default `mis.margo.org`), and every
host that connects to the MIS must resolve that name to the MIS host.

### CTT repository

```bash
mkdir -p $HOME/workspace && cd $HOME/workspace
git clone https://github.com/margo/conformance_test_toolkit.git
cd conformance_test_toolkit
git checkout feature/multi-persona-conformance

go version         # go1.21 or later
openssl version
jq --version
```

---

## Phase 1 — Identity provisioning (MIAF)

### Identities

All principals belong to one Trust Domain; its MIS issues every X.509-SVID.

| Principal | SPIFFE ID | X.509-SVID held by |
|---|---|---|
| WFM | `spiffe://<trust-domain>/margo/wfm/<wfm-id>` | The mock WFM of the CTT |
| WFM Client | `spiffe://<trust-domain>/margo/wfm/<wfm-id>/client/<wfm-client-id>` | The test client of the CTT (`self-check`, test control) |
| WFM Client | `spiffe://<trust-domain>/margo/wfm/<wfm-id>/client/<wfm-client-id>` | The device under test (issued in [Phase 4](#phase-4--conformance-test-of-a-device)) |

Each side validates the X.509-SVID of its peer against the Trust Bundle of the
Trust Domain and then authorizes the peer by its SPIFFE ID. The CTT receives
its trust material out of band: the SVID Root CA certificate of the MIS
(`ca.crt` in the sandbox), which is the X.509 trust anchor the Trust Bundle
publishes. The mock WFM authorizes every WFM Client whose SPIFFE ID is derived
from its own WFM SPIFFE ID.

The examples use the sandbox MIS, the WFM ID `ctt-mock-wfm` and the WFM Client
ID `ctt-runner`.

**Step 1 — Provide an MIS**

Use the MIS of the Trust Domain the device belongs to. For the Margo sandbox,
install the MIS as described in
[Build and Run MIS](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#build-and-run-mis)
of the sandbox Setup Guide (preceded by its Step 1 and Step 2). An MIS that is
already installed, for example for the WFM Supplier setup, is used as it is:
`Factory Bootstrap: Generate Root CAs` regenerates the CA certificates and
invalidates every previously issued X.509-SVID.

**Step 2 — Issue the X.509-SVIDs of the CTT**

Generate the SVIDs as described in
[Generate X.509-SVIDs for WFM and WFM client](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#generate-x509-svids-for-wfm-and-wfm-client)
of the sandbox Setup Guide, with these inputs:

| Prompt | Mock WFM | Test client of the CTT |
|---|---|---|
| Principal | `1` (WFM) | `2` (WFM Client) |
| WFM ID | `ctt-mock-wfm` | `ctt-mock-wfm` |
| WFM Client ID | not asked | `ctt-runner` |

Result, in the folder the generator was run from
(`$HOME/workspace/sandbox/scripts`): `x509svid-ctt-mock-wfm` and
`x509svid-ctt-mock-wfm-ctt-runner`. The WFM ID must be identical for both.

**Step 3 — Install the identities of the CTT**

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 2) Device Supplier → 1) Setup Identity
#
# Folder containing the SVIDs:       $HOME/workspace/sandbox/scripts   (press Enter for the default)
# Which one is the WFM SVID?:        the number of x509svid-ctt-mock-wfm
# Which one is the Client SVID?:     the number of x509svid-ctt-mock-wfm-ctt-runner
```

The CLI lists every SVID folder it finds and installs the two X.509-SVIDs,
their private keys and the SVID Root CA certificate
(`$HOME/mis-deployment/certs/ca.crt`) into `ctt-runner/device-supplier/certs/`.
It first verifies that both X.509-SVIDs chain to that trust anchor and that the
WFM Client SPIFFE ID is derived from the WFM SPIFFE ID. Folders owned by root
are read with `sudo`. The step ends with `Identity setup complete` and prints
both SPIFFE IDs.

When the MIS runs on a different host than the CTT, transfer the five files
the CTT requires and provide the folder to the same CLI step:

```bash
# On the MIS host, in the folder that contains the x509svid-* folders
mkdir -p ~/ctt-certs
cp x509svid-ctt-mock-wfm/payload-cert.pem            ~/ctt-certs/wfm-svid-cert.pem
cp x509svid-ctt-mock-wfm/payload-key.pem             ~/ctt-certs/wfm-svid-key.pem
cp x509svid-ctt-mock-wfm-ctt-runner/payload-cert.pem ~/ctt-certs/client-svid-cert.pem
cp x509svid-ctt-mock-wfm-ctt-runner/payload-key.pem  ~/ctt-certs/client-svid-key.pem
cp ~/mis-deployment/certs/ca.crt                     ~/ctt-certs/mis-ca.crt

# Transfer the folder to the home directory of the CTT host
scp -r ~/ctt-certs ctt-user@ctt-host:~/
```

---

## Phase 2 — Start the mock WFM

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 2) Device Supplier → 2) Start Mock WFM Server
```

The CLI builds the mock WFM and the test runner from source (a few seconds;
about one minute for the first build) and prints the values a device requires:

```
  Management Interface : https://<ctt-host-ip>:3003/v1alpha2/margo
  WFM SPIFFE ID        : spiffe://<trust-domain>/margo/wfm/<wfm-id>
  Trust anchor (MIS)   : .../ctt-runner/device-supplier/certs/svid-ca.pem
  Health / telemetry   : https://<ctt-host-ip>:3001/health
  Server log           : /tmp/wfm-server.log
```

- **Port 3003** is the Margo Management Interface, served over mTLS with the
  X.509-SVID of Phase 1. A device uses this port only.
- **Port 3001** serves health and telemetry status. Management Interface
  requests sent to it are rejected with `403`, because they are not
  authenticated by mTLS.

The mock WFM continues to run after the menu is left. Option 4 stops it.

---

## Phase 3 — Verify the setup (no device required)

With the mock WFM running:

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 2) Device Supplier → 3) Run Tests → self-check
# Press Enter at both URL prompts (defaults: port 3001 for health, port 3003 for mTLS)
```

`self-check` runs the test client of the CTT against the mock WFM: 92 steps, of
which 90 must pass. It takes a few seconds. The two steps of the SVID rotation
scenario are `NOT RUN` until the WFM Client SVID of the CTT is reissued and
installed again with `Setup Identity`. A successful `self-check` confirms the
identities, the URLs and the mock WFM before a device is connected.

### Test groups

A group is a named set of scenarios. The report states the group that was
executed.

| Group | Device required | Scope | Typical use |
|---|---|---|---|
| `core` | yes | All groups below that require a device | Conformance result of a device ([Phase 4](#phase-4--conformance-test-of-a-device)) |
| `management-interface` | yes | Device Capabilities, Desired State, retrieval, Deployment Status, a deployment added and withdrawn | Work on the Management Interface client |
| `manifest-integrity` | yes | State Manifests and content a device MUST reject, one it MUST accept, state retained across a restart | Work on manifest validation |
| `identity` | yes | X.509-SVID of the device, rejection of a WFM the MIS did not certify, SVID rotation | Work on MIAF |
| `observability` | yes | The OpenTelemetry collector of the device publishes telemetry to the CTT | When a collector is configured (`NOT RUN` otherwise) |
| `self-check` | no | The test client of the CTT against the mock WFM: every API call, its errors, the State Manifests a device must reject | Before a device is connected; after a change to `assertions.json` |
| `quick-check` | no | Device Capabilities, State Manifest, deployment, Deployment Bundle, Deployment Status (11 steps) | Verification of the URLs and the identity setup |
| `random-order` | no | The `self-check` lifecycle scenarios in a different random order on every run | Demonstrates that no scenario depends on another |

### Conformance report and signed PDF

Each run writes three files to `ctt-runner/reports/device-supplier/`:

```
conformance-report-<timestamp>.html          conformance report
conformance-report-<timestamp>_signed.pdf    the same report as a digitally signed PDF
ca_cert.pem                                  certificate required to verify the signature
```

The WFM Supplier and Device Supplier reports use the same layout:

| Part | Content |
|---|---|
| Header | Persona, group, claimed version, CTT Margo version, system under test (the SPIFFE ID of the device that sent requests to the mock WFM; `no device identified in this run` for groups that require no device), time of the run |
| Result line | Steps passed, failed, not run, total |
| Requirements Coverage | One row per requirement ID: `PASS`, `FAIL` or `NOT RUN`, and the steps that verify it |
| Scenario Summary | Passed, failed and not run steps per scenario |
| Step Details | Every step: requirement IDs, method, endpoint, expected and actual HTTP status, result, reason |

A requirement is `FAIL` when any step that verifies it failed, `PASS` when at
least one of its steps passed and none failed, and `NOT RUN` when none of its
steps was executed. A step is `NOT RUN` when its precondition is absent (for
example no X.509-SVID was reissued, or the device does not declare that role);
it is neither a pass nor a failure.

**Signed PDF.** The signed PDF is created automatically at the end of every
run. The first run installs the PDF tools (requires `sudo` and internet access,
about one minute); later runs take about 15 seconds. The signature proves that
the PDF was not modified after the run. By default the CTT signs with its own
certificate authority, created on the host at first use and kept in
`scripts/signing-identity/`; all reports signed on that host verify against the
same `ca_cert.pem`. Submit the signed PDF together with `ca_cert.pem` as the
evidence of the conformance run.

```bash
cd $HOME/workspace/conformance_test_toolkit
scripts/.venv/bin/python scripts/pdf_verify.py \
  ctt-runner/reports/device-supplier/conformance-report-<timestamp>_signed.pdf \
  ctt-runner/reports/device-supplier/ca_cert.pem
# RESULT    : signature OK
```

| Option | Command |
|---|---|
| Skip the signed PDF | `CTT_SIGN_REPORT=no bash ctt-runner/ctt-start.sh` |
| Sign with a provided certificate (`.p12`) | `CTT_SIGN_CERT=/path/to/signer.p12 CTT_SIGN_PASSPHRASE=secret bash ctt-runner/ctt-start.sh` |
| Sign an existing HTML report | `bash scripts/pdf_ops.sh ctt-runner/reports/device-supplier/name-of-report.html` (output in `./generatedReport/`) |

---

## Phase 4 — Conformance test of a device

The mock WFM of Phase 2 is the WFM of the device under test. The device
receives its identity from the same MIS and connects to the mock WFM.

### Step 1 — Issue the X.509-SVID of the device

On the MIS host, generate one WFM Client SVID with the WFM ID of the mock WFM
and a WFM Client ID that identifies the device, as described in
[Generate X.509-SVIDs for WFM and WFM client](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#generate-x509-svids-for-wfm-and-wfm-client):
principal `2`, WFM ID `ctt-mock-wfm`, WFM Client ID for example
`vendor-device-1`. Result: `x509svid-ctt-mock-wfm-vendor-device-1`.

### Step 2 — Provide the device with its identity, trust material and configuration

| Item | Value |
|---|---|
| X.509-SVID and private key of the device | `x509svid-ctt-mock-wfm-vendor-device-1/payload-cert.pem`, `payload-key.pem` |
| URL of the Margo Management Interface | Printed in Phase 2: `https://<ctt-host-ip>:3003/v1alpha2/margo` |
| WFM SPIFFE ID to authorize in the local authorization policy of the device | Printed in Phase 2: `spiffe://margo.org/margo/wfm/ctt-mock-wfm` |
| Trust Bundle of the Trust Domain | Retrieved from the MIS: `https://mis.margo.org:9443`, authenticated with the HTTPS CA `$HOME/mis-deployment/certs/https-ca.crt` (initial trust bootstrap), with `mis.margo.org` resolving to the MIS host — or delivered out of band: the SVID Root CA certificate `$HOME/mis-deployment/certs/ca.crt` |

### Step 3 — Start the device and observe the mock WFM

```bash
tail -f /tmp/wfm-server.log
```

Every request is logged with its response status. A conformant WFM Client
produces this sequence:

```
[MIAF/Capabilities] accepted for spiffe://margo.org/margo/wfm/ctt-mock-wfm/client/vendor-device-1 (deviceId=<device id>)
[Router] PUT  /v1alpha2/margo/api/v1/capabilities/<device id> ... → 201
[Router] GET  /v1alpha2/margo/api/v1/deployments ... → 200
[Router] GET  /v1alpha2/margo/api/v1/deployments/<deployment id>/sha256:<digest> ... → 200
[MIAF/Status] update for deployment <deployment id> from spiffe://.../client/vendor-device-1
[Router] POST /v1alpha2/margo/api/v1/deployments/<deployment id>/status ... → 200
[Router] GET  /v1alpha2/margo/api/v1/deployments ... → 304
```

| Log line | Indicates that the WFM Client |
|---|---|
| `PUT .../capabilities/... → 201` (`200` on a repetition) | Reports valid Device Capabilities |
| `GET .../deployments → 200`, followed by a `GET` of each ApplicationDeployment YAML (or of the Deployment Bundle) by digest `→ 200` | Retrieves the State Manifest and the content it lists |
| `POST .../status → 200` after the retrieval | Reports Deployment Status, with `adoptedManifestVersion` |
| Later `GET .../deployments → 304` | Revalidates with `If-None-Match` instead of downloading again |

| Log line | Meaning |
|---|---|
| `[MIAF] answered 422 Semantic Error — ... \| capabilities-006: properties.modelNumber is required` | The request body violates the specification; the rule and the reason follow the `\|` |
| `TLS handshake error ... is not a client of this WFM (expected .../client/<wfm-client-id>)` | The X.509-SVID of the device was issued for a different WFM ID; repeat Step 1 with the WFM ID of the mock WFM |
| `TLS handshake error ... client didn't provide a certificate` | The device connected without its X.509-SVID |
| `TLS handshake error ... unknown certificate authority` | The X.509-SVID of the device was issued by a different MIS |
| No line | The device cannot reach port 3003, or does not authorize the WFM SPIFFE ID |

The mock WFM assigns every new device one sample deployment. Its component
refers to a placeholder package that cannot be retrieved; the device is
therefore expected to report that deployment as `failed`. To verify an actual
installation, stop the mock WFM, export a package the device can retrieve, and
start the mock WFM again:

```bash
export CTT_SAMPLE_REPOSITORY=oci://<registry>/<path>
export CTT_SAMPLE_REVISION=<version>
bash ctt-runner/ctt-start.sh    # → 2) Device Supplier → 2) Start Mock WFM Server
```

### Step 4 — Run the group `core`

With the mock WFM running and the device connected:

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 2) Device Supplier → 3) Run Tests → core, then press Enter at both URL prompts
# Without the menu: bash ctt-runner/ctt-start.sh device core
```

In this group the CTT sends no request to the device. The mock WFM records
every request of the device and assesses it with the rules of
`assertions.json`, which it loads at start. Each step reads one of these
assessments. Between steps the CTT changes the Desired State on the mock WFM —
also to State Manifests and content a device must reject — and waits for the
device to retrieve it. A run takes about 12 minutes with the sandbox device
agent, which retrieves its Desired State every 15 seconds; lines starting with
`⏳ waiting for the device` are expected.

| Scenario | Required behaviour of the device |
|---|---|
| Identity | Connects over mTLS with an X.509-SVID that is a leaf certificate with one URI SAN |
| Device Capabilities | Reports Device Capabilities that pass validation; declares an OCI runtime, an OpenTelemetry collector, a deployment type, memory, storage and CPUs |
| Desired State, retrieval and Deployment Status | Retrieves the State Manifest, retrieves the Deployment Bundle or the ApplicationDeployment YAML by digest, reports Deployment Status, revalidates with the ETag (304) |
| A deployment is added and withdrawn | Reports Deployment Status for the new deployment, then `removing` or `removed` after it is withdrawn |
| Manifest version does not increase | Does not act on it and retains its previous state |
| Unsupported digest algorithm (`sha512`) | Does not act on it, does not retrieve anything it names, and retains its previous state |
| Deployment Bundle or ApplicationDeployment YAML does not match its digest | Does not act on it — assessed only if the device retrieved that content, otherwise `NOT RUN` "not applicable" |
| Incorrect `sizeBytes`, correct digests | Accepts the State Manifest and reports Deployment Status for its new deployment |
| A WFM the MIS did not certify | Sends no request while the mock WFM presents a certificate the MIS did not issue (50 seconds), then continues |
| State is retained across a restart | After a restart, still sends the ETag of the adopted State Manifest and still rejects a lower manifest version |
| SVID rotation | Continues to operate with a reissued X.509-SVID for the same SPIFFE ID |
| Observability | Publishes telemetry to the CTT (`NOT RUN` when no collector is directed at the CTT) |

**Operator action during the run.** When the following line appears, restart
the device within 3 minutes:

```
👉 Restart the device under test now (within 3 minutes). To also test SVID rotation, replace its SVID with a re-issued one for the same SPIFFE ID before starting it.
```

If the device is not restarted, the steps of "State is retained across a
restart" are `NOT RUN`. If its X.509-SVID is not replaced, "SVID rotation" is
`NOT RUN`. To replace it, reissue the SVID as in Step 1 (same WFM ID and WFM
Client ID) and install it on the device before it is started again.

Interpretation of the result:

- **PASS** on a "must not" step: the device did not send the prohibited request
  after it had retrieved the State Manifest two or three times.
- **FAIL** states the incorrect request, or the rule of `assertions.json` that
  was not met, for example
  `the device sent a request it must not send here: GET /api/v1/bundles/sha512:...`.
- **"it does not send the ETag of the rejected manifest back"** fails when the
  device revalidates with the `If-None-Match` of a State Manifest it had to
  reject: it has stored that manifest as its state.
- **NOT RUN "not applicable"**: the check could not be assessed on this device
  or in this run; the reason is stated.
- The deployments added during the run refer to the same placeholder package as
  the first one; a device reports them as `failed` unless
  `CTT_SAMPLE_REPOSITORY` is set. Any Deployment Status report counts as
  "acted on it".

The mock WFM retains every request received since its start, and a device
retains the manifest version it adopted. For a clean run, stop and start the
mock WFM (options 4 and 2) and start the device with empty state.

The requirement verified by each step, and the requirements that cannot be
verified, are listed in `docs/device-supplier-requirements-coverage.md`.

### Margo sandbox device agent (demonstration)

The device agent of the Margo sandbox is set up as described in
[On Each Device VM](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#on-each-device-vm)
and
[Start Device Services](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#start-device-services)
of the sandbox Setup Guide. Those steps are not repeated here. Apply the
following CTT-specific inputs, so that the device agent connects to the mock
WFM instead of Symphony:

| Step of the sandbox Setup Guide | CTT-specific input |
|---|---|
| Copy Security Files (WFM Client SVID, HTTPS server CA, Harbor CA) | Use the WFM Client SVID issued in Step 1 (`x509svid-ctt-mock-wfm-vendor-device-1`) in place of `x509svid-wfm-docker-client` |
| Environment (`device-agent.env`) | `WFM_HOST` = address of the CTT host (not `localhost`), `WFM_PORT=3003` |
| Add WFM SPIFFE ID in local allow list policy | The WFM SPIFFE ID of the mock WFM: `spiffe://margo.org/margo/wfm/ctt-mock-wfm` |
| `/etc/hosts` entry for the MIS | The address of the MIS host. `127.0.0.1` is not usable, also on the same host, because the device agent runs in a container |

Notes:

- `Install-prerequisites` of `device-agent.sh` copies the files of
  `$HOME/certs` into the configuration folder of the device agent
  (`$HOME/sandbox/poc/device/agent/config/`). A file changed in `$HOME/certs`
  after the installation — a reissued X.509-SVID, or the HTTPS CA of another
  MIS — must also be copied there, followed by a restart of the device agent.
  The procedure is described in
  [Renewal and Reissuance](https://github.com/margo/sandbox/blob/main/docs/identity-lifecycle.md#renewal-and-reissuance)
  of the sandbox Identity Lifecycle guide. A device agent with an incorrect
  HTTPS CA restarts repeatedly with
  `failed to retrieve margo spiffe trust bundle ... certificate signed by unknown authority`.
- Empty state: the device agent keeps its state in
  `$HOME/sandbox/docker-compose/data`. When it is stopped
  (`device-agent.sh docker stop-docker`), the script asks
  `Do you want to delete data folder ...? (y/n)`; answer `y`.
- Restart during the `core` run:
  `sudo -E bash device-agent.sh docker stop-docker`, then
  `sudo -E bash device-agent.sh docker start-docker`
  (from `$HOME/workspace/sandbox/scripts`).

**Reference result.** A `core` run takes about 12 minutes. With the sandbox
device agent verified with this guide (October 2026, Compose-capable device,
restarted with a reissued X.509-SVID when requested) the result is
**53 passed, 3 failed, 5 not run**:

| Result | Step | Reason |
|---|---|---|
| FAIL | "does not fetch anything by a digest of the unsupported algorithm" | For a `sha512` State Manifest the device agent still requests `.../sha512:...` |
| FAIL | "keeps its previous state" (unsupported digest algorithm) | It stores the ETag of the State Manifest it had to reject |
| FAIL | "keeps its previous state" (ApplicationDeployment YAML does not match its digest) | It stores the ETag of the State Manifest it had to reject |
| NOT RUN | Standalone cluster role | The device agent declares Compose, not Helm |
| NOT RUN | Deployment Bundle does not match its digest (2 steps) | This device agent retrieves the ApplicationDeployment YAML files, not the Deployment Bundle |
| NOT RUN | Observability (2 steps) | No OpenTelemetry collector is directed at the CTT |

These are deviations of that device agent build; they do not indicate a setup
error. The Helm-capable device agent (`device-agent.sh k3s`) was not verified
for this guide.

To return the sandbox device agent to Symphony, restore `WFM_HOST` and
`WFM_PORT` in `device-agent.env`, set the local allow list policy to the WFM
SPIFFE ID of Symphony, install the WFM Client SVID issued for the WFM ID of
Symphony, and restart the device agent.

---

## Certificate validity and renewal

| File in `ctt-runner/device-supplier/certs/` | Validity | Action on expiry |
|---|---|---|
| `miaf-server-cert.pem` — X.509-SVID of the mock WFM; `svid-cert.pem` — X.509-SVID of the test client | About 90 days (sandbox MIS default) | Reissue the SVIDs (Phase 1, Step 2) and repeat `Setup Identity` |
| `svid-ca.pem` — SVID Root CA certificate (trust anchor) | Lifetime of the Root CA of the MIS | Repeat `Setup Identity` after the Root CA is replaced |

```bash
openssl x509 -in ctt-runner/device-supplier/certs/miaf-server-cert.pem -noout -enddate
openssl x509 -in ctt-runner/device-supplier/certs/svid-cert.pem -noout -enddate
```

---

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| `MIAF identity not found ... Please run 'Setup Identity' first` | Phase 1, Step 3 was not performed in this checkout | Run `Setup Identity` |
| `Setup Identity`: `... does not chain to the given SVID Root CA` | The X.509-SVIDs and the Root CA certificate originate from different MIS installations | Provide the folder (or Root CA certificate) of the MIS that issued the SVIDs. No file is changed by the failed attempt |
| `Setup Identity`: `Missing file: ...` | The folder does not contain all five files | Verify the folder; for a flat folder use the file names of Phase 1 |
| `Failed to build mock server` or `Failed to build test runner` | Go is not installed, or no internet access for the first build | Install Go; the first build downloads the Go toolchain and modules |
| `Failed to start mock server` | Stated in the log lines printed with the error | Full log: `/tmp/wfm-server.log` |
| `cannot use the WFM SVID: ... is not a WFM identity` | A WFM Client SVID was selected as WFM SVID | Repeat `Setup Identity` and select the WFM SVID folder |
| Every step fails: `server presented ..., expected the WFM ...` | The WFM Client SVID was issued for a different WFM ID than the WFM SVID | Issue the WFM Client SVID for the same WFM ID and repeat `Setup Identity` |
| Every step fails: `x509: certificate signed by unknown authority` | The installed trust anchor is not the Root CA that issued the WFM SVID | Repeat `Setup Identity` with the material of the correct MIS |
| Every step fails with `403` | The mTLS URL was set to port 3001 | Press Enter at the URL prompts to use the defaults (mTLS on port 3003) |
| `x509: certificate has expired` | An X.509-SVID has exceeded its validity | Reissue the SVIDs and repeat `Setup Identity` |
| Device: `TLS handshake error ... is not a client of this WFM` in `/tmp/wfm-server.log` | The X.509-SVID of the device belongs to a different WFM ID | Issue the device a WFM Client SVID for the WFM ID of the mock WFM (Phase 4, Step 1) |
| Device: `TLS handshake error ... unknown certificate authority` | The X.509-SVID of the device was issued by a different MIS | Use one MIS for the mock WFM and the device |
| Every step of a device group fails with `no request from any device was received` | The device does not reach the mock WFM, or does not authorize its WFM SPIFFE ID | Verify port 3003, the Management Interface URL and the local authorization policy of the device |
| Sandbox device agent continues to connect to Symphony | `WFM_HOST` and `WFM_PORT` in `device-agent.env` are unchanged | Set them to the CTT host and `3003`, then restart the device agent |
| Sandbox device agent rejects the mock WFM | The WFM SPIFFE ID of the mock WFM is not in its local allow list policy | `device-agent.sh` option 11 (Manage SPIFFE ID allowlist) |
| Sandbox device agent reports `potential rollback attack: new version ... < current version ...` | The mock WFM was restarted and serves a lower manifest version than the device agent adopted | Start the device agent with empty state |
| `Signed PDF not created` at the end of a run | Stated below the message. Typical causes: the repository folder is owned by root, or no internet access for the initial tool installation | Resolve the stated cause (ownership: `sudo chown -R $USER:$USER $HOME/workspace/conformance_test_toolkit`), then run the `pdf_ops.sh` command the run printed |
| No report is written | The test runner stopped early | See `ctt-runner/reports/device-supplier/test-execution.log` |

---

## Checklist

```
Phase 1 — Identity provisioning (once; repeat when an X.509-SVID is reissued)
  □ MIS of the Trust Domain available (sandbox: sandbox Setup Guide, "Build and Run MIS")
  □ SVIDs generated: WFM (WFM ID ctt-mock-wfm) and WFM Client (WFM Client ID ctt-runner)
  □ ctt-start.sh → 2) Device Supplier → 1) Setup Identity
      folder: $HOME/workspace/sandbox/scripts → select the WFM SVID and the Client SVID

Phase 2 — Mock WFM
  □ ctt-start.sh → 2) Device Supplier → 2) Start Mock WFM Server
  □ Note the Management Interface URL and the WFM SPIFFE ID

Phase 3 — Verification of the setup
  □ ctt-start.sh → 2) Device Supplier → 3) Run Tests → self-check (90 passed, 2 not run)

Phase 4 — Conformance test of a device
  □ WFM Client SVID issued for the device (WFM ID ctt-mock-wfm)
  □ Device: X.509-SVID and key installed, Management Interface URL set,
      WFM SPIFFE ID authorized, Trust Bundle available (MIS or out of band)
  □ tail -f /tmp/wfm-server.log shows capabilities → 201, deployments → 200, status → 200
  □ ctt-start.sh → 2) Device Supplier → 3) Run Tests → core; restart the device when requested
  □ Report:     ctt-runner/reports/device-supplier/conformance-report-<timestamp>.html
  □ Signed PDF: ctt-runner/reports/device-supplier/conformance-report-<timestamp>_signed.pdf (+ ca_cert.pem)
```
