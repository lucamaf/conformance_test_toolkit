# Device Supplier Conformance — Setup and Execution Guide

**Persona:** Device Supplier  
**Spec baseline:** Margo `1.0.0-rc.3` (MIAF / mTLS authentication)  
**Audience:** Device vendors, device-agent engineers, Margo adopters

This guide walks you from a clean checkout to a conformance report.
The Device Supplier persona is self-contained: **no external WFM is needed**.
The CTT provides a spec-compliant mock WFM server locally and a simulated
device-agent that exercises every required protocol flow against it.

> **What the report covers.** The conformance result of a device comes from the
> group `core`: it judges the requests your real device sends to the mock WFM.
> Do Phases 1 and 2, then follow
> [Testing a real device-agent](#testing-a-real-device-agent); its last step
> runs `core`.
> Phase 3 is a check of the setup only: the group `self-check` runs the CTT's
> *own* simulated device against the mock WFM and says nothing about your device.

---

## How the Device Supplier test works

Your device is the system under test and the CTT acts as a **mock WFM**. For
the demo the device is the Margo sandbox device-agent; a vendor uses their own
device.

```
 Device under test                        CTT
 (sandbox device-agent                    ┌──────────────────────────────────────────┐
  or your own device)                     │  Mock WFM server                         │
 ┌────────────────────┐   HTTPS / mTLS    │  port 3003  Management Interface (mTLS)  │
 │  WFM Client        │ ────────────────► │  port 3001  health / telemetry status    │
 └────────────────────┘                   │  judges every request with               │
                                          │  assertions.json and records it          │
                                          └───────────────────┬──────────────────────┘
                                                              │ group `core` reads the verdicts
                                                              ▼
                                          ctt-runner/reports/device-supplier/
                                            conformance-report-<timestamp>.html
```

The mock WFM implements the rc.3 Management Interface: it enforces mTLS and
accepts only SVIDs that belong to its own WFM identity, serves desired-state
manifests, bundles and deployments with correct ETag / digest, validates every
request body, and returns errors as RFC 9457 problem details.

There are two kinds of test groups:

- **`core` and its subsets judge your device.** The device connects to the mock
  WFM and the CTT checks what it sends — also when the mock WFM serves a
  manifest the device must reject. See
  [Testing a real device-agent](#testing-a-real-device-agent).
- **`self-check` needs no device.** The CTT's own simulated device runs against
  the mock WFM, to confirm the setup before a device is connected (Phase 3).

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Go | 1.21+ (1.24 used) | compiles `bin/server` and `bin/run_tests`. Install from [go.dev](https://go.dev/doc/install), or `apt install golang-go` on Ubuntu 24.04. An older Go (1.21–1.23) downloads the 1.24 toolchain by itself on the first build, which needs internet access. |
| OpenSSL | 1.1+ | certificate checks; usually pre-installed |
| jq | any | group file parsing; `apt install jq` |
| bash | 4+ | |
| OS | Linux | tested on Ubuntu 24.04; macOS is not supported |

**1. Clone the CTT repo:**

```bash
mkdir -p ~/workspace && cd ~/workspace
git clone https://github.com/margo/conformance_test_toolkit.git
cd conformance_test_toolkit
git checkout feature/multi-persona-conformance
```

**2. Clone the Margo sandbox** (provides `mis.sh` — the MIS used for SVID generation):

```bash
cd ~
git clone https://github.com/margo/sandbox.git sandbox
```

> The sandbox scripts expect to be in `~/sandbox`. Set the sandbox environment
> as its own guide describes (`~/sandbox/docs/setup-guide.md`, Steps 1 and 2)
> before using `mis.sh`.

**3. Verify tooling:**

```bash
go version      # 1.21 or newer
openssl version
jq --version
```

---

## Phase 1 — Identity setup (one-time)

All conformance tests use MIAF mTLS (port 3003). The mock WFM and the CTT
test runner each need an X.509-SVID from a **shared MIS** — the same MIS that
the vendor's real device trusts. This CA alignment is what makes the test
production-representative.

```
MIS  ──issues SVIDs──►  mock WFM server  (MIAF TLS identity, port 3003)
     ──issues SVIDs──►  CTT test runner  (mTLS client identity)
     ──issues SVID──►   vendor device    (connects to mock WFM on port 3003)
```

> **CA alignment:** `certs/svid-ca.pem` placed here must be the CA that the
> vendor's device trusts. For sandbox testing this is the sandbox MIS CA. For
> real vendor conformance testing, use the CA from whichever MIS the vendor's
> device is enrolled in.

### Centralized MIS

**Step 1 — Generate SVIDs via MIS**

One MIS issues every SVID: one for the mock WFM, one for the CTT's test runner,
and later one for each real device you test. The examples below use the WFM ID
`ctt-mock-wfm`.

If the sandbox MIS is not installed on this machine yet, install it first. Run
the menu three times, with options 1, 3 and 4 in this order; each time press
Enter at "Press Enter to continue..." and then `7` to exit:

```bash
sudo -E bash ~/sandbox/scripts/mis.sh     # → 1) PreRequisites: Setup
sudo -E bash ~/sandbox/scripts/mis.sh     # → 3) Factory Bootstrap: Generate Root CAs
sudo -E bash ~/sandbox/scripts/mis.sh     # → 4) Margo Identity Service: Install
```

> If the MIS is already installed (for example for the WFM Supplier setup on
> this machine), skip this: option 3 creates new CAs, and every SVID issued
> before stops being trusted.

Then generate the two SVIDs. Run the command from inside `~/mis-deployment` —
`mis.sh` writes each SVID folder into the directory you run it from:

```bash
cd ~/mis-deployment
sudo -E bash ~/sandbox/scripts/mis.sh generate-svid     # run 1: the mock WFM
sudo -E bash ~/sandbox/scripts/mis.sh generate-svid     # run 2: the CTT test runner
sudo chown -R $USER:$USER ~/mis-deployment
```

Answer the prompts like this:

| Prompt | Run 1 — mock WFM | Run 2 — CTT test runner |
|---|---|---|
| `Enter Trust Domain [default: margo.org]:` | press Enter | press Enter |
| `Enter choice [1/2]:` | `1` | `2` |
| `Enter WFM ID:` | `ctt-mock-wfm` | `ctt-mock-wfm` |
| `Enter WFM Client ID:` | (not asked) | `ctt-runner` |
| `Enter TTL in seconds [default: 7776000]:` | press Enter | press Enter |
| `DNS SANs:` | press Enter | press Enter |
| `Proceed? [Y/n]:` | press Enter | press Enter |

The WFM ID must be the same in both runs. The client's SPIFFE ID is then
`<WFM SPIFFE ID>/client/<client-id>`, which is what the spec requires and what
both the mock WFM and the test runner check.

**Step 2 — Check what was generated:**

```bash
ls ~/mis-deployment/ | grep x509svid
# x509svid-ctt-mock-wfm              ← WFM SVID (the mock WFM's identity)
# x509svid-ctt-mock-wfm-ctt-runner   ← client SVID (the CTT test runner's identity)
```

You do not need to copy these by hand — the CTT CLI lists them and copies the
right files in Step 3.

For a vendor-provided or external MIS: use your MIS tooling to obtain a WFM
SVID cert/key pair, a client SVID cert/key pair, and the MIS CA cert, then
copy them to the CTT machine before Step 3.

**Step 3 — Place SVIDs into the CTT cert directory**

The SVIDs must be on the CTT machine before this step. Two scenarios:

**MIS on the same machine as CTT** (sandbox setup):
`~/mis-deployment/` is already local — go straight to the CTT CLI:
  
Now, execute below CTT command, it will copy the certs generated by Sandbox mis.sh script to the certs folder inside CTT.
```bash
cd ~/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 2) Device Supplier → 1) Setup Identity
#
# When prompted:
#   Folder containing the SVIDs [~/mis-deployment]:   press Enter
#   Which one is the WFM SVID?    [1]:   the number of x509svid-ctt-mock-wfm
#   Which one is the Client SVID? [2]:   the number of x509svid-ctt-mock-wfm-ctt-runner
#
# The CLI lists every SVID folder it finds. Type the numbers shown next to
# those two folders. With the names used in this guide they are 1 and 2, the
# defaults — press Enter twice.
```

It must end with `Identity setup complete — both SVIDs verified against the MIS CA`
and print the two SPIFFE IDs.

**MIS on a different machine** (vendor setup):

On the MIS machine, collect the required files into a staging directory, then transfer the whole directory to the CTT machine using `scp -r` — scp will create the destination directory automatically:

```bash
# On the MIS machine — stage cert files into a local folder
mkdir -p ~/vendor-certs
cp MIS_DIR/x509svid-WFM_ID/payload-cert.pem           ~/vendor-certs/wfm-svid-cert.pem
cp MIS_DIR/x509svid-WFM_ID/payload-key.pem            ~/vendor-certs/wfm-svid-key.pem
cp MIS_DIR/x509svid-WFM_ID-CLIENT_ID/payload-cert.pem ~/vendor-certs/client-svid-cert.pem
cp MIS_DIR/x509svid-WFM_ID-CLIENT_ID/payload-key.pem  ~/vendor-certs/client-svid-key.pem
cp MIS_DIR/certs/ca.crt                               ~/vendor-certs/mis-ca.crt

# Transfer the folder to the CTT machine's home directory.
# Creates ~/vendor-certs/ there on the first run; on a re-run it overwrites the files in place.
scp -r ~/vendor-certs <CTT_HOST>:~/
```

Then on the CTT machine, run the CLI and point it at the folder the files were transferred to:

```bash
cd ~/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 2) Device Supplier → 1) Setup Identity
#
# When prompted:
#   Folder containing the SVIDs [~/mis-deployment]:   ~/vendor-certs
```

The CLI picks up the five files by the names used above. The folder can be
anywhere on the CTT machine and may be owned by root or by your user — the CLI
uses `sudo` only when it cannot read the folder itself, and never changes the
source folder. A whole MIS output folder (with `x509svid-*` sub-folders and
`certs/ca.crt`) can be given instead of a flat folder.

Before anything is replaced, the CLI checks that both SVIDs were issued by the
given MIS CA. If a file is missing or the CA does not match, it stops and leaves
the existing certs untouched.

All certs land in `ctt-runner/device-supplier/certs/`.

**Verify:**

```bash
cd ctt-runner/device-supplier
openssl verify -CAfile certs/svid-ca.pem certs/miaf-server-cert.pem
# → certs/miaf-server-cert.pem: OK
openssl verify -CAfile certs/svid-ca.pem certs/svid-cert.pem
# → certs/svid-cert.pem: OK
```

**SVID validity:** MIS issues SVIDs with a ~90-day TTL. Re-run Steps 1 and 3
when certs expire.

---

## Phase 2 — Start the mock WFM server

The CTT CLI builds the binaries from the current source every time it starts
the server (a few seconds; ~1 minute the very first time). Use option 2:

```bash
cd ~/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 2) Device Supplier → 2) Start Mock WFM Server
```

The CLI prints what a device needs to connect:

```
  Management Interface : https://<ctt-host-ip>:3003/v1alpha2/margo
  WFM SPIFFE ID        : spiffe://<trust-domain>/margo/wfm/<wfm-id>
  Trusted CA (MIS)     : .../ctt-runner/device-supplier/certs/svid-ca.pem
  Health / telemetry   : https://<ctt-host-ip>:3001/health
  Server log           : /tmp/wfm-server.log
```

The server listens on two ports:
- **Port 3003** — the Margo Management Interface, mTLS with the SVIDs from Phase 1.
  This is the only port a device talks to.
- **Port 3001** — health and telemetry status. Management Interface requests sent
  here are rejected with `403`, because they are not authenticated by mTLS.

The server keeps running after you leave the menu. Stop it with option 4.

---

## Phase 3 — Check the setup (no device needed)

### Via the interactive menu

The mock WFM server must already be running (Phase 2).

```bash
cd ~/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 2) Device Supplier → 3) Run Tests
```

The menu will:
1. Prompt for a test group selection
2. Prompt for the two server URLs
3. Run all scenarios and print results as they execute
4. Write the HTML report

The server is left running afterwards; stop it with option 4 when you are done.

### Select a test group

```
📋 Available Device Test Groups:
   1) core                     (v1.0.0-rc.3)
        Real device: the full Device Supplier conformance set for Margo
        1.0.0-rc.3. Judges the device connected to the mock WFM ...
  ...
   8) self-check               (v1.0.0-rc.3)
        No device needed: the CTT's own device client against the mock WFM. ...
```

Select `self-check` (enter its number from the list — `8` above). It runs the
CTT's own device client against the mock WFM: 90 steps that must all pass. It
confirms that the identity, the URLs and the mock WFM are in order before a
real device is connected.

A group is a named set of scenarios, so you can run one area at a time and the
report states which set was run. Each description in the list starts with
"Real device:" or "No device needed:".

| Group | Needs a device | What it checks | When to run it |
|---|---|---|---|
| `quick-check` | no | Capabilities, manifest, deployment, bundle, status (11 steps) | First, to confirm the URLs and the identity setup |
| `self-check` | no | The CTT's own device client against the mock WFM: every API call, its errors, the manifests a device must reject | Before connecting a device; after changing `assertions.json` |
| `random-order` | no | The self-check lifecycle scenarios in a different random order on every run | To show that no scenario depends on another |
| `management-interface` | yes | Capabilities, desired state, fetch, status, a deployment added and withdrawn | While working on the API client |
| `manifest-integrity` | yes | Manifests and content a device MUST reject, one it MUST accept, state kept across a restart | While working on manifest validation |
| `identity` | yes | The device's SVID, refusing a WFM the MIS did not certify, SVID rotation | While working on MIAF |
| `observability` | yes | The device's OpenTelemetry collector pushes telemetry to the CTT | When a collector is configured (NOT RUN otherwise) |
| `core` | yes | All of the "yes" groups together | For the conformance result of a device — see [Testing a real device-agent](#testing-a-real-device-agent) |

### URLs to enter

```
Enter Mock WFM Server URL [https://192.168.x.x:3001/v1alpha2/margo]:
```

Press Enter to use the default (auto-detected from your machine's IP).

```
Enter Management Interface (mTLS) URL [https://192.168.x.x:3003/v1alpha2/margo]:
```

Press Enter. All conformance steps go to the mTLS port (3003); port 3001 is
only used for the health check and telemetry status.

A `self-check` run takes a few seconds. Two SVID Rotation steps are reported as
NOT RUN until the CTT's client SVID has been re-issued and installed again with
Setup Identity.

### The report and its signed PDF

The report is written to `ctt-runner/reports/device-supplier/`. Every run leaves
three files there:

```
conformance-report_<timestamp>.html          the report, open it in any browser
conformance-report_<timestamp>_signed.pdf    the same report as a digitally signed PDF
ca_cert.pem                           the certificate needed to check the signature
```

The WFM Supplier and the Device Supplier reports use the same layout:

| Part | What it shows |
|------|---------------|
| Header | Persona, group, claimed version, CTT Margo version, system under test (the SPIFFE ID of the device that sent requests to the mock WFM; `no device identified in this run` for the groups that need no device), run time |
| Result line | Steps passed, failed, not run, total |
| Requirements Coverage | One row per requirement ID: `PASS`, `FAIL` or `NOT RUN`, and the steps that check it |
| Scenario Summary | Passed, failed and not run steps per scenario |
| Step Details | Every step: requirement IDs, method, endpoint, expected and actual HTTP code, result, reason |

A requirement is `FAIL` when any step that checks it failed, `PASS` when at
least one of its steps passed and none failed, and `NOT RUN` when none of its
steps ran.

#### The signed PDF

The signed PDF is created automatically at the end of every run; there is no
extra command. The run prints:

```
🔏 Creating the signed PDF report (the first time this installs the PDF tools and may ask for sudo)...
✅ Signed report: .../ctt-runner/reports/device-supplier/conformance-report_<timestamp>_signed.pdf
ℹ️  Signer CA certificate (send it with the report): .../ctt-runner/reports/device-supplier/ca_cert.pem
```

The first run installs the PDF tools (needs sudo and internet, about one
minute). Later runs take about 15 seconds.

The signature shows that the PDF was not changed after the run. The CTT signs
with its own certificate authority, created on this machine the first time and
kept in `scripts/signing-identity/`. All reports signed on this machine use
that one authority, so one `ca_cert.pem` checks all of them. Send `ca_cert.pem`
together with the PDF.

Check a signed report (use the file name the run printed):

```bash
cd $HOME/workspace/conformance_test_toolkit
scripts/.venv/bin/python scripts/pdf_verify.py \
  ctt-runner/reports/device-supplier/conformance-report_<timestamp>_signed.pdf \
  ctt-runner/reports/device-supplier/ca_cert.pem
```

Expected:

```
Unchanged since signing : yes
Signer chains to ctt-runner/reports/device-supplier/ca_cert.pem : yes
RESULT    : signature OK
```

Options, set in front of the run command:

| To do this | Run |
|------------|-----|
| Skip the signed PDF | `CTT_SIGN_REPORT=no bash ctt-runner/ctt-start.sh` |
| Sign with your own certificate (a `.p12` file) | `CTT_SIGN_CERT=/path/to/signer.p12 CTT_SIGN_PASSPHRASE=secret bash ctt-runner/ctt-start.sh` |
| Sign an older HTML report by hand | `bash scripts/pdf_ops.sh ctt-runner/reports/device-supplier/name-of-report.html` (the PDF goes to `./generatedReport/`) |

If the signed PDF cannot be created, the run says so and the reason is in
`ctt-runner/reports/device-supplier/report-signing.log`. The test result and the
HTML report are not affected.

A step shown as `NOT RUN` was not judged because its precondition is missing
(for example no SVID was rotated, or the device does not declare that role) —
it is neither a pass nor a failure.

---

## Testing a real device-agent

The mock WFM from Phase 2 is the target. The device gets its identity from the
same MIS and connects to the mock WFM. You can watch the mock WFM's log to see
what it sends (Step 3), and the `core` group writes the report (Step 4).

### Step 1 — Issue the device an SVID

On the MIS machine, generate one more client SVID for the **same WFM ID** as
the mock WFM, with a client ID that names the device:

```bash
cd ~/mis-deployment
sudo -E bash ~/sandbox/scripts/mis.sh generate-svid
# Enter choice [1/2]:     2
# Enter WFM ID:           ctt-mock-wfm
# Enter WFM Client ID:    vendor-device-1        ← one name per device
# every other prompt:     press Enter
sudo chown -R $USER:$USER ~/mis-deployment
```

This creates `~/mis-deployment/x509svid-ctt-mock-wfm-vendor-device-1/`.

### Step 2 — Give the device owner these five things

| What | Where it comes from |
|---|---|
| Device SVID and key | `~/mis-deployment/x509svid-ctt-mock-wfm-vendor-device-1/payload-cert.pem` and `payload-key.pem` |
| Management Interface URL | printed by Phase 2: `https://<ctt-host-ip>:3003/v1alpha2/margo` |
| WFM SPIFFE ID to accept | printed by Phase 2: `spiffe://margo.org/margo/wfm/ctt-mock-wfm` |
| Trust, option A — a CA file | `~/mis-deployment/certs/ca.crt` (the CA that signed every SVID) |
| Trust, option B — fetch it from the MIS | MIS address `https://mis.margo.org:9443`, its HTTPS CA `~/mis-deployment/certs/https-ca.crt`, and a hosts entry on the device: `<MIS-machine-IP> mis.margo.org` |

Use option A or B, whichever the device supports. The device must be able to
reach the CTT machine on port **3003** (and the MIS machine on **9443** for
option B).

### Step 3 — Start the device and watch the log

```bash
tail -f /tmp/wfm-server.log
```

Every request is logged with the status it was answered with. A device that
behaves correctly produces lines like these, in this order:

```
[MIAF/Capabilities] accepted for spiffe://margo.org/margo/wfm/ctt-mock-wfm/client/vendor-device-1 (deviceId=<its device id>)
[Router] PUT  /v1alpha2/margo/api/v1/capabilities/<device id> ... → 201
[Router] GET  /v1alpha2/margo/api/v1/deployments ... → 200
[Router] GET  /v1alpha2/margo/api/v1/deployments/<deployment id>/sha256:<digest> ... → 200
[MIAF/Status] update for deployment <deployment id> from spiffe://.../client/vendor-device-1
[Router] POST /v1alpha2/margo/api/v1/deployments/<deployment id>/status ... → 200
[Router] GET  /v1alpha2/margo/api/v1/deployments ... → 304
```

What to check:

| You should see | It shows the device |
|---|---|
| `PUT .../capabilities/...  → 201` (or `200` on a repeat) | reports valid capabilities |
| `GET .../deployments → 200`, then a `GET` of each deployment (or the bundle) by digest `→ 200` | polls the desired state and fetches what it lists |
| `POST .../status → 200` after the fetch | reports status, with `adoptedManifestVersion` |
| later polls `GET .../deployments → 304` | re-polls with `If-None-Match` instead of downloading again |

Lines that mean something is wrong:

| Line | Meaning |
|---|---|
| `[MIAF] answered 422 Semantic Error — ... \| capabilities-006: properties.modelNumber is required` | the device sent a body the spec does not allow; the rule and reason follow the `\|` |
| `TLS handshake error ... is not a client of this WFM (expected .../client/<wfm-client-id>)` | the device's SVID was issued for a different WFM ID — repeat Step 1 with the mock WFM's ID |
| `TLS handshake error ... client didn't provide a certificate` | the device connected without its SVID |
| `TLS handshake error ... unknown certificate authority` | the device's SVID comes from a different MIS |
| nothing at all | the device cannot reach port 3003, or does not accept the WFM SPIFFE ID |

The mock WFM assigns every new device one sample deployment. Its component
points at a placeholder package that cannot be pulled, so a device is expected
to report that deployment as `failed`. To test a real installation, stop the
mock WFM, export a package the device can pull, and start it again:

```bash
export CTT_SAMPLE_REPOSITORY=oci://<registry>/<path>   # e.g. a compose package in your Harbor
export CTT_SAMPLE_REVISION=<version>                    # e.g. 1.0.0
bash ctt-runner/ctt-start.sh    # → 2) Device Supplier → 2) Start Mock WFM Server
```

### Step 4 — Get the conformance report for the device

With the mock WFM running and the device connected to it:

```bash
cd ~/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
```

Select **2) Device Supplier → 3. Run Tests** and choose the group `core`.
Press Enter for the two URLs. (Without the menu:
`bash ctt-runner/ctt-start.sh device core`.)

In this group the CTT sends nothing to the device. The mock WFM records every
request your device sends and judges it with the rules of `assertions.json`,
which it loads when it starts. Each step reads one of those verdicts. Between
steps the CTT changes the desired state on the mock WFM — also to manifests and
content a device must reject — and waits for the device to read it. A run takes
about 12 minutes with the sandbox device-agent (it reads its desired state every
15 seconds); lines starting with `⏳ waiting for the device` are normal.

| Scenario | What the device must do |
|---|---|
| Identity | connect over mTLS with an X.509-SVID that is a leaf certificate with one URI SAN |
| Capabilities | report capabilities that pass the mock WFM's validation; declare an OCI runtime, an OpenTelemetry collector, a deployment type, memory, storage and CPUs |
| Desired state, fetch and status | read the manifest, fetch the bundle or the deployment by digest, report status, re-read with the ETag (304) |
| A deployment is added and withdrawn | report status for the new deployment, then `removing` or `removed` after it is withdrawn |
| Manifest version does not increase | not act on it, and keep its previous state |
| Unsupported digest algorithm (`sha512`) | not act on it, not fetch anything it names, and keep its previous state |
| Bundle / deployment file does not match its digest | not act on it — judged only if the device downloaded that content, otherwise NOT RUN "not applicable" |
| Wrong `sizeBytes`, correct digests | accept the manifest and report status for its new deployment |
| A WFM the MIS did not certify | send no request while the mock WFM presents a certificate the MIS did not issue (50 seconds), then continue |
| State survives a restart | after a restart, still send the ETag of the adopted manifest and still reject a lower manifest version |
| SVID rotation | keep working with a re-issued SVID for the same SPIFFE ID |
| Observability | push telemetry to the CTT (NOT RUN when no collector is pointed at the CTT) |

**The one thing you do during the run:** when this line appears, restart the
device (you have 3 minutes):

```
👉 Restart the device under test now (within 3 minutes). To also test SVID rotation, replace its SVID with a re-issued one for the same SPIFFE ID before starting it.
```

If the device is not restarted, the "State survives a restart" steps are
reported as NOT RUN. If its SVID is not replaced, "SVID rotation" is reported as
NOT RUN. To replace it, issue the device a new SVID exactly as in Step 1 (same WFM
ID and client ID) and install it on the device before starting it again.

How to read the result:

- **PASS** on a "must not" step means the device did not send the forbidden
  request after it had read the manifest two or three times.
- **FAIL** shows the request that was wrong, or the rule of `assertions.json`
  it did not meet, for example
  `the device sent a request it must not send here: GET /api/v1/bundles/sha512:...`.
- **"it does not send the ETag of the rejected manifest back"** fails when the
  device answers the next poll with `If-None-Match` of a manifest it had to
  reject: it has stored that manifest as its state.
- **NOT RUN "not applicable"** means the check could not be judged on this device
  or in this run; the reason is given.
- The deployments added during the run point at the same placeholder package as
  the first one, so a device reports them as `failed` unless
  `CTT_SAMPLE_REPOSITORY` is set. Any status report counts as "acted on it".

The mock WFM keeps everything it received since it was started, and a device
keeps the manifest version it adopted. For a clean run, stop and start the mock
WFM (options 4 and 2) and start the device with empty state.

The report and its signed PDF are written to `ctt-runner/reports/device-supplier/`
(see [The report and its signed PDF](#the-report-and-its-signed-pdf)) with the
requirement IDs next to each step. Which requirement is judged by which step,
and which requirements cannot be judged, is listed in
`docs/device-supplier-requirements-coverage.md`.

---

### Testing the Margo sandbox device-agent (the demo device)

The Margo sandbox ships a reference device-agent
(`workload-fleet-management-client`). These are the steps to set it up from
nothing and test it against the mock WFM. They were run exactly as written, with
the device-agent on the same machine as the CTT and the MIS; the differences for
a separate device machine are noted.

It needs the Margo sandbox cloned to `~/sandbox` on the device machine, with its
environment set as the sandbox setup guide describes
(`~/sandbox/docs/setup-guide.md`, Steps 1 and 2).

#### Step 1 — Phase 1, Phase 2 and the device SVID

Complete Phase 1 and Phase 2 above, then issue the device its SVID as in
[Step 1 — Issue the device an SVID](#step-1--issue-the-device-an-svid)
(WFM ID `ctt-mock-wfm`, client ID `vendor-device-1`).

#### Step 2 — Give the device-agent its certificates

The sandbox device-agent takes its files from `~/certs`:

```bash
mkdir -p $HOME/certs/compose-identity
cp ~/mis-deployment/x509svid-ctt-mock-wfm-vendor-device-1/payload-cert.pem $HOME/certs/compose-identity/
cp ~/mis-deployment/x509svid-ctt-mock-wfm-vendor-device-1/payload-key.pem  $HOME/certs/compose-identity/
cp ~/mis-deployment/certs/https-ca.crt                                     $HOME/certs/
sudo cp ~/sandbox/scripts/harbor/certs/harbor.crt                          $HOME/certs/
sudo chown -R $USER:$USER $HOME/certs
```

On a separate device machine, create `~/certs/compose-identity` there and copy
the same four files from the MIS / WFM machine with `scp`.

#### Step 3 — Make the MIS reachable by name

The device-agent fetches its trust bundle from `https://mis.margo.org:9443`. In
`/etc/hosts` of the device machine that name must point at the MIS machine's
network address. `127.0.0.1` does not work, also on the same machine, because
the device-agent runs in a container:

```bash
sudo sed -i '/mis\.margo\.org/d' /etc/hosts
echo "$(hostname -I | awk '{print $1}') mis.margo.org" | sudo tee -a /etc/hosts
```

(On a separate device machine, write the MIS machine's address in place of
`$(hostname -I | awk '{print $1}')`.)

#### Step 4 — Point the device-agent at the mock WFM

Edit `~/sandbox/scripts/device-agent.env` so that it has these two lines, with
the address the CLI printed in Phase 2 (`Management Interface : https://<ctt-host-ip>:3003/...`):

```bash
export WFM_HOST=<ctt-host-ip>     # for example 10.0.0.7 — not localhost
export WFM_PORT=3003              # the mock WFM's mTLS port
```

`device-agent.sh` writes this URL into the agent's config every time it starts
the agent, so change it here and not in `config.yaml`.

#### Step 5 — Install, allow the mock WFM, start

```bash
sudo -E bash ~/sandbox/scripts/device-agent.sh docker install
# must end with: prerequisites installation completed.
```

The device-agent only talks to the WFM on its allowlist. Add the WFM SPIFFE ID
the CLI printed in Phase 2:

```bash
sudo -E bash ~/sandbox/scripts/device-agent.sh docker
```

| Prompt | Answer |
|---|---|
| `Enter choice [1-12]:` | `11` |
| `Use default path? [Y/n]:` | press Enter |
| `Enter choice [1-2]:` | `1` (Set SPIFFE ID) |
| `Enter SPIFFE ID:` | `spiffe://margo.org/margo/wfm/ctt-mock-wfm` |
| `Enter choice [1-2]:` | `2` (Back) |
| `Press Enter to continue...` | press Enter |
| `Enter choice [1-12]:` | `12` (Exit) |

Start it:

```bash
sudo -E bash ~/sandbox/scripts/device-agent.sh docker start-docker
sudo docker ps --filter name=workload-fleet-management-client --format "{{.Names}}\t{{.Status}}"
# Should show: workload-fleet-management-client   Up N seconds
```

If it shows `Restarting`, look at the reason:

```bash
sudo docker logs workload-fleet-management-client 2>&1 | tail -5
```

| Message | Fix |
|---|---|
| `mis.margo.org ... dial tcp 127.0.0.1:9443: connect: connection refused` | Step 3 — the hosts entry is `127.0.0.1` |
| `Required certificate file not found` | Step 2 — a file is missing in `~/certs` |

Within a few seconds the mock WFM's log (`tail -f /tmp/wfm-server.log`) shows
the lines listed under
[Step 3 — Start the device and watch the log](#step-3--start-the-device-and-watch-the-log).

#### Step 6 — Run `core` and restart the device when asked

Run the group `core` as in
[Step 4 — Get the conformance report for the device](#step-4--get-the-conformance-report-for-the-device).
When the line `👉 Restart the device under test now` appears, restart the
device-agent — and, to include SVID rotation, give it a re-issued SVID first:

```bash
# re-issue the device's SVID (same answers as in Step 1) and install it:
cd ~/mis-deployment
sudo -E bash ~/sandbox/scripts/mis.sh generate-svid      # 2, ctt-mock-wfm, vendor-device-1
sudo cp -f ~/mis-deployment/x509svid-ctt-mock-wfm-vendor-device-1/payload-cert.pem \
           ~/mis-deployment/x509svid-ctt-mock-wfm-vendor-device-1/payload-key.pem \
           ~/sandbox/poc/device/agent/config/compose-identity/

# restart the device-agent:
sudo -E bash ~/sandbox/scripts/device-agent.sh docker stop-docker
sudo -E bash ~/sandbox/scripts/device-agent.sh docker start-docker
```

You have 3 minutes from the moment the line appears; have the commands ready.

#### What to expect with the sandbox device-agent

A `core` run takes about 12 minutes. With the sandbox device-agent tested with
this guide (October 2026, restarted with a re-issued SVID when asked) it ends
with **53 passed, 3 failed, 5 not run**:

| Result | Step | Why |
|---|---|---|
| FAIL | "does not fetch anything by a digest of the unsupported algorithm" | on a `sha512` manifest the device-agent still asks for `.../sha512:...` |
| FAIL | "keeps its previous state" (unsupported digest algorithm) | it stores the ETag of the manifest it had to reject |
| FAIL | "keeps its previous state" (deployment file does not match its digest) | it stores the ETag of the manifest it had to reject |
| NOT RUN | standalone cluster role | the device-agent declares Compose, not Helm |
| NOT RUN | bundle does not match its digest (2 steps) | this device-agent fetches the deployment files, not the bundle |
| NOT RUN | observability (2 steps) | no OpenTelemetry collector is pointed at the CTT |

These are findings about that device-agent build, not problems of your setup.

For a K3s device-agent the commands are `device-agent.sh k3s install`,
`start-k3s` and `stop-k3s`, and the certificates go to `~/certs/helm-identity`;
this path was not run for this guide.

#### Putting the sandbox device-agent back on Symphony

Change `~/sandbox/scripts/device-agent.env` back, set the allowlist to
Symphony's WFM SPIFFE ID (menu option 11), and restart:

```bash
# in ~/sandbox/scripts/device-agent.env:
export WFM_HOST=symphony.machine
export WFM_PORT=8084

sudo -E bash ~/sandbox/scripts/device-agent.sh docker stop-docker
sudo -E bash ~/sandbox/scripts/device-agent.sh docker start-docker
```

The device then also needs an SVID for Symphony's WFM ID in
`~/sandbox/poc/device/agent/config/compose-identity/`.

---

## Certificate expiry and renewal

| Cert type | Validity | Renewal |
|---|---|---|
| MIS SVIDs (`miaf-server-cert.pem`, `svid-cert.pem`) | ~90 days (MIS default TTL) | Re-run Steps 1 and 3 from Phase 1 |
| MIS CA (`svid-ca.pem`) | Long-lived (MIS CA cert) | Rare; re-run Step 3 from Phase 1 if the MIS CA rotates |

Check expiry:

```bash
# MIS SVID (mock WFM server identity)
openssl x509 -in ctt-runner/device-supplier/certs/miaf-server-cert.pem \
    -noout -enddate

# MIS SVID (CTT device identity)
openssl x509 -in ctt-runner/device-supplier/certs/svid-cert.pem \
    -noout -enddate
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `MIAF identity not found ... Please run 'Setup Identity' first` | Phase 1 Step 3 not done in this checkout | Run option 1) Setup Identity |
| Setup Identity: `... was not issued by the given MIS CA` | SVIDs and CA come from different MIS setups | Give the folder (or CA file) that belongs to the MIS that issued the SVIDs; nothing was changed in `certs/` |
| Setup Identity: `Missing file: ...` | Folder does not hold all five files | Check the folder; for a flat folder use the file names shown in Phase 1 |
| `Failed to build mock server` / `Failed to build test runner` | Go missing, or no internet for the first build | Install Go (Prerequisites); the first build downloads the Go toolchain and modules |
| `Failed to start mock server` | The last log lines are printed with the error | Read them; full log in `/tmp/wfm-server.log` |
| `cannot use the WFM SVID: ... is not a WFM identity` | The cert chosen as WFM SVID is a client SVID (or not an SVID) | Re-run Setup Identity and pick the WFM SVID folder for "WFM SVID" |
| Every step fails: `server presented ..., expected the WFM ...` | Client SVID was generated for a different WFM ID than the WFM SVID | Generate the client SVID for the same WFM ID (Phase 1 Step 1), re-run Setup Identity |
| Every step fails: `x509: certificate signed by unknown authority` | `svid-ca.pem` is not the CA that issued the WFM SVID | Re-run Setup Identity with the right MIS folder |
| Every step fails with `403` (or a certificate error naming port 3001) | The Management Interface (mTLS) URL was pointed at port 3001 | Press Enter at the URL prompts to use the defaults (mTLS on 3003) |
| `x509: certificate has expired` | SVID older than its TTL (~90 days) | Generate new SVIDs (Phase 1 Step 1) and re-run Setup Identity |
| Device: `TLS handshake error ... is not a client of this WFM` in `/tmp/wfm-server.log` | Device SVID belongs to a different WFM ID | Issue the device an SVID for the mock WFM's ID (Testing a real device-agent, Step 1) |
| Device: `TLS handshake error ... unknown certificate authority` | Device SVID issued by a different MIS than `svid-ca.pem` | Use the CA of the MIS that issued the device's SVID |
| Sandbox device-agent keeps talking to Symphony | `WFM_HOST` / `WFM_PORT` in `device-agent.env` unchanged | Set them to the CTT host and `3003`, then restart the device-agent |
| Sandbox device-agent refuses the mock WFM | Mock WFM's SPIFFE ID not on the device's allowlist | `device-agent.sh` → 11) Manage SPIFFE ID allowlist |
| `container 'margo-identity-service' is not running` from `mis.sh` | MIS not installed/started, or `mis.sh` run without `sudo` | `sudo -E bash ~/sandbox/scripts/mis.sh` → 4) Margo Identity Service: Install |
| `~/mis-deployment/` owned by root | `mis.sh` runs as root | `sudo chown -R $USER:$USER ~/mis-deployment` (optional — Setup Identity can read root-owned folders) |
| `Signed PDF not created` at the end of a run | Shown on screen under the message. Usual causes: the repository folder is owned by root (cloned or run with `sudo`), or no internet for the first-time tool install | Fix the cause shown (for ownership: `sudo chown -R $USER:$USER $HOME/workspace/conformance_test_toolkit`), then run the `PDF_OUTPUT_DIR=... bash .../scripts/pdf_ops.sh ...` command the run printed. The test result and the HTML report are not affected |
| Report not generated | Test runner stopped early | Check `ctt-runner/reports/device-supplier/test-execution.log` |

---

## Quick-reference checklist

```
Phase 1 — Identity setup (once per MIS deployment; re-run when SVIDs expire)
  □ MIS installed (sandbox setup guide: mis.sh options 1, 3, 4)
  □ Generate SVIDs: cd ~/mis-deployment && sudo -E bash ~/sandbox/scripts/mis.sh generate-svid
                    run 1: choice 1, WFM ID ctt-mock-wfm
                    run 2: choice 2, WFM ID ctt-mock-wfm, client ID ctt-runner
  □ Fix ownership:  sudo chown -R $USER:$USER ~/mis-deployment
  □ Copy to CTT:    ctt-start.sh → 2) Device Supplier → 1) Setup Identity
                    (enter the folder holding the SVIDs — default ~/mis-deployment; root-owned folders are fine)
  □ The CLI must end with: Identity setup complete — both SVIDs verified against the MIS CA

Phase 2 — Start the mock WFM
  □ ctt-start.sh → 2) Device Supplier → 2) Start Mock WFM Server  (builds from source each time)
  □ Note the Management Interface URL and WFM SPIFFE ID it prints

Phase 3 — Check the setup (no device needed)
  □ ctt-start.sh → 2) Device Supplier → 3) Run Tests → self-check → Enter, Enter at the URL prompts
  □ Must end with: Test Results: 90 PASSED, 0 FAILED

Testing a real device (this is the conformance result)
  □ Issue it an SVID: generate-svid → choice 2, WFM ID ctt-mock-wfm, client ID = a name for the device
  □ Give the owner: the SVID + key, the Management Interface URL, the WFM SPIFFE ID,
      and either ~/mis-deployment/certs/ca.crt or the MIS address + https-ca.crt + hosts entry
  □ Mock WFM running (Phase 2); device can reach port 3003
  □ tail -f /tmp/wfm-server.log → capabilities 201, deployments 200, deployment fetch 200, status 200, later polls 304
  □ ctt-start.sh → 2) Device Supplier → 3) Run Tests → core → Enter, Enter; restart the device when asked
  □ Open report: ctt-runner/reports/device-supplier/conformance-report-<ts>.html
  □ Signed PDF:  ctt-runner/reports/device-supplier/conformance-report-<ts>_signed.pdf (+ ca_cert.pem)

Sandbox device-agent (the demo device) — see "Testing the Margo sandbox device-agent"
  □ ~/certs/compose-identity/payload-cert.pem + payload-key.pem, ~/certs/https-ca.crt, ~/certs/harbor.crt
  □ /etc/hosts: <MIS machine's address> mis.margo.org   (not 127.0.0.1)
  □ ~/sandbox/scripts/device-agent.env: WFM_HOST=<ctt-host-ip>, WFM_PORT=3003
  □ sudo -E bash ~/sandbox/scripts/device-agent.sh docker install
  □ sudo -E bash ~/sandbox/scripts/device-agent.sh docker → 11 → Enter → 1 → spiffe://margo.org/margo/wfm/ctt-mock-wfm → 2 → Enter → 12
  □ sudo -E bash ~/sandbox/scripts/device-agent.sh docker start-docker
  □ core: 53 passed, 3 failed, 5 not run with the sandbox device-agent of October 2026
```
