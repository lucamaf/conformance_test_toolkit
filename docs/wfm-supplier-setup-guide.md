# WFM Supplier Conformance — Setup and Execution Guide

**Persona:** WFM Supplier (Margo persona: Fleet Management Supplier)  
**Specification baseline:** Margo `1.0.0-rc.3`  
**Audience:** WFM suppliers, Margo adopters, integration engineers

This guide describes how to verify a Workload Fleet Manager (WFM) for
conformance with the Margo specification using the Margo Conformance Test
Toolkit (CTT). It covers the prerequisites, identity provisioning, test
execution and the conformance report.

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

In this persona the WFM is the system under test. The CTT acts as a Workload
Fleet Management Client (WFM Client): it accesses the Margo Management
Interface exposed by the WFM and checks each response for conformance with the
specification. Every check is traced to a conformance requirement ID in the
report.

For demonstration, the Symphony WFM of the Margo sandbox is used. A WFM
supplier is expected to bring their own WFM, against which conformance is
checked.

The CTT implements Margo `1.0.0-rc.3` and therefore the Margo Identity and
Authorization Framework (MIAF). The WFM and the CTT authenticate each other by
mutual TLS with X.509-SVIDs, and each side authorizes its peer locally, based
on the peer's verified SPIFFE ID. This has two consequences for the setup:

- A Margo Identity Service (MIS) must exist for the Trust Domain. It issues the
  X.509-SVID of the WFM and the X.509-SVID the CTT presents as a WFM Client,
  and it publishes the Trust Bundle of the Trust Domain.
- The WFM must authorize the SPIFFE ID of the CTT in its local authorization
  policy.

```
CTT (WFM Client)                              WFM under test (demo: Symphony)
  presents its X.509-SVID      ── mTLS ──►    validates it against the Trust Bundle,
                                              authorizes the SPIFFE ID by local policy
  validates the WFM's X.509-SVID  ◄── mTLS ── presents its X.509-SVID
  against the Trust Bundle
        │
        ▼  requests on the Margo Management Interface, checked against the specification
        ▼
  ctt-runner/reports/wfm-supplier/
  wfm-scenario-report-core_<timestamp>.html  and  ..._signed.pdf
```

---

## Prerequisites

### Tools on the CTT host

| Tool | Version | Purpose |
|---|---|---|
| Node.js | 18 or later | Runs the test runner (`run_wfm_scenarios.js`); no `npm install` is required |
| OpenSSL | 1.1 or later | Certificate inspection |
| jq | any | Reads the test group files |
| bash | 4 or later | Runs the CLI |
| oras | 1.x | Application Registry checks of the `core` group ([installation](https://oras.land/docs/installation)) |
| Operating system | Linux | Verified on Ubuntu 24.04 |

### Network connectivity

When the MIS, the WFM and the CTT run on different hosts, the following
connections must be permitted before testing. A host that is reachable over SSH
can still have these ports closed.

| From | To | Port | Purpose |
|---|---|---|---|
| CTT host | WFM host | Margo Management Interface exposed by the WFM (Symphony: 8084) | All WFM conformance tests |
| WFM host | MIS host | MIS trust endpoints (sandbox MIS: 9443) | The WFM connects to the MIS for discovery and to obtain the Trust Bundle. Not required when the operator provides the Trust Bundle and the Trust Domain to the WFM by configuration (out-of-band delivery) |
| CTT host | Application Registry | Registry port (sandbox Harbor: 8443) | Application Registry checks |
| CTT host | MIS host | none | The CTT receives its identity and trust material out of band (see [Phase 1](#phase-1--identity-provisioning-miaf)) and does not connect to the MIS |

The host name under which the MIS is reachable is a configuration value, not a
fixed name. In the Margo sandbox it is `EXPOSED_MIS_HOST` in `mis.env`
(default `mis.margo.org`), and every host that connects to the MIS must resolve
that name to the MIS host. The CTT has no MIS host name configured.

### CTT repository

```bash
mkdir -p $HOME/workspace && cd $HOME/workspace
git clone https://github.com/margo/conformance_test_toolkit.git
cd conformance_test_toolkit
git checkout feature/multi-persona-conformance

node --version     # v18 or later
openssl version
jq --version
oras version
```

---

## Phase 1 — Identity provisioning (MIAF)

### Identities

| Principal | SPIFFE ID | X.509-SVID held by |
|---|---|---|
| WFM | `spiffe://<trust-domain>/margo/wfm/<wfm-id>` | The WFM under test |
| WFM Client | `spiffe://<trust-domain>/margo/wfm/<wfm-id>/client/<wfm-client-id>` | The CTT |

Both X.509-SVIDs are issued by the MIS of the Trust Domain. Each side validates
the X.509-SVID of its peer against the Trust Bundle of the Trust Domain and
then authorizes the peer by its SPIFFE ID:

- The **WFM** obtains the Trust Bundle from the MIS (discovery document and
  Trust Bundle retrieval endpoint) or from operator-provided configuration. Its
  local authorization policy must contain the WFM Client SPIFFE ID of the CTT.
- The **CTT** receives its trust material out of band, together with its
  X.509-SVID: the SVID Root CA certificate of the MIS (`ca.crt` in the sandbox),
  which is the X.509 trust anchor the Trust Bundle publishes. The CTT validates
  the X.509-SVID of the WFM against this trust anchor and additionally verifies
  that the WFM presents exactly the WFM SPIFFE ID its own WFM Client SPIFFE ID
  is derived from.

The HTTPS CA of the MIS (`https-ca.crt` in the sandbox) has a different role:
it authenticates the TLS connection to the MIS trust endpoints (initial trust
bootstrap). Only components that retrieve the Trust Bundle from the MIS need it.
It is not used to validate X.509-SVIDs.

Two setups are described:

- [Margo sandbox (Symphony)](#margo-sandbox-symphony) — the demonstration setup.
- [WFM of a supplier](#wfm-of-a-supplier) — the conformance setup.

### Margo sandbox (Symphony)

The MIS and Symphony are installed as described in the Margo sandbox
[Setup Guide](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md).
That guide is the reference for those steps and they are not repeated here.
The sandbox scripts obtain the sandbox and Symphony sources themselves; no
additional clone is required. In the sandbox, the MIS is a container
(`margo-identity-service`) that mints the X.509-SVIDs; `mis.sh` installs it and
provides the SVID generation helper.

Follow the sections of the sandbox Setup Guide in its order — the MIS is built
before the WFM, because the WFM configuration requires the HTTPS CA of the MIS —
and apply the following CTT-specific inputs:

| Section of the sandbox Setup Guide | CTT-specific input |
|---|---|
| [Step 1: Get the Setup Files](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#step-1-get-the-setup-files), [Step 2: Set Up Environment](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#step-2-set-up-environment) | None |
| [Build and Run MIS](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#build-and-run-mis) | None |
| [Generate X.509-SVIDs for WFM and WFM client](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#generate-x509-svids-for-wfm-and-wfm-client) | In addition to the WFM SVID, generate one WFM Client SVID for the CTT: principal `2`, the WFM ID of Symphony (`wfm`), WFM Client ID `ctt-client`. Result: `$HOME/workspace/sandbox/scripts/x509svid-wfm-ctt-client` |
| [Build and Run WFM (Symphony)](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#build-and-run-wfmsymphony), step "Add WFM Client SPIFFE IDs as authorised clients" | Add the WFM Client SPIFFE ID of the CTT: `spiffe://margo.org/margo/wfm/wfm/client/ctt-client` |
| "On Each Device VM" and later sections | Not required for this persona |

Notes on the sandbox installation:

- Run the sandbox scripts with `sudo -E`, as the sandbox Setup Guide specifies.
- `PreRequisites: Setup` of `wfm.sh` is intended to run once per host. To set
  the WFM up again, first follow
  [Cleaning Up (Starting Fresh)](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#cleaning-up-starting-fresh)
  in the sandbox Setup Guide, then repeat the installation.
- `Factory Bootstrap: Generate Root CAs` of `mis.sh` generates the factory PKI
  of the MIS. Running it again regenerates the CA certificates, which
  invalidates every previously issued X.509-SVID and the HTTPS CA of the MIS
  trust endpoints. Do not run it more than once, unless the intention is to
  revoke all previously issued principal identities and start again.
- The sandbox scripts run as root and leave `$HOME/.docker` owned by root. The
  CTT uses `oras` as the current user; restore the ownership once:
  `sudo chown -R $USER:$USER $HOME/.docker`

After the sandbox is running, complete the following CTT steps.

**Step 1 — Install the identity of the CTT**

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 1) WFM Supplier → 1. Setup MIAF Identity → 2) MIS-issued identity
#
# Folder containing the client SVID:   $HOME/workspace/sandbox/scripts/x509svid-wfm-ctt-client
```

The CLI installs the X.509-SVID, its private key and the SVID Root CA
certificate (`$HOME/mis-deployment/certs/ca.crt`) into
`ctt-runner/wfm-supplier/utils/fixtures/miaf/real/`. It first verifies that the
X.509-SVID chains to that trust anchor and carries a WFM Client SPIFFE ID.
Folders owned by root are read with `sudo`. The step ends with
`Identity setup complete` and prints
`CTT client SVID : spiffe://margo.org/margo/wfm/wfm/client/ctt-client`.

**Step 2 — Publish the CTT test Application Package to the Application Registry**

The `core` group uses one Application Package in the sandbox Harbor registry,
for the Application Registry checks and for the deployment the WFM delivers as Desired State.

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/wfm-supplier/utils/fixtures/margo-ctt-package/push.sh
# → Pushed [registry] harbor.machine:8443/library/margo-ctt-hello-world:1.0.0
```

**Step 3 — Assign the test deployment to the CTT**

The `core` and `deployment-delivery` groups verify how the WFM delivers a
deployment. A deployment must therefore be assigned to the WFM Client identity
of the CTT. For the sandbox Symphony a helper performs this assignment; it
requires Step 1 and Step 2:

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/wfm-supplier/utils/fixtures/provision-multi-component.sh
# → Check on the Management Interface (...): ok
# → Done. Multi-component deployment provisioned:
```

Run the helper again after a different WFM Client SVID is installed, after a
reboot of the host, and after Symphony is restarted or rebuilt. In those cases
Symphony may list no deployment in the State Manifest or fail the Deployment Bundle download; the helper detects
this and assigns the deployment again. Details are given in
[Deployment scenario](#deployment-scenario-assign-a-deployment-to-the-ctts-client).

### WFM of a supplier

The WFM under test and the CTT must belong to the same Trust Domain. Its MIS
issues both X.509-SVIDs. The examples use the sandbox MIS and the WFM ID
`acme-wfm`; the WFM ID is assigned by the operator of the Trust Domain.

**Step 1 — Issue the X.509-SVIDs**

On the MIS host, generate the SVIDs as described in
[Generate X.509-SVIDs for WFM and WFM client](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#generate-x509-svids-for-wfm-and-wfm-client)
of the sandbox Setup Guide, with these inputs:

| Prompt | WFM under test | CTT |
|---|---|---|
| Principal | `1` (WFM) | `2` (WFM Client) |
| WFM ID | `acme-wfm` | `acme-wfm` |
| WFM Client ID | not asked | `ctt-client` |

**Step 2 — Provide the WFM with its identity and trust material**

| Item | Source in the sandbox MIS |
|---|---|
| X.509-SVID and private key of the WFM, served on its mTLS endpoint | `x509svid-acme-wfm/payload-cert.pem`, `payload-key.pem` |
| Trust Bundle of the Trust Domain | Retrieved from the MIS: `https://mis.margo.org:9443`, authenticated with the HTTPS CA `$HOME/mis-deployment/certs/https-ca.crt` — or provided by configuration: the SVID Root CA certificate `$HOME/mis-deployment/certs/ca.crt` |
| WFM Client SPIFFE ID to authorize in the local authorization policy | `spiffe://margo.org/margo/wfm/acme-wfm/client/ctt-client` |

When the WFM retrieves the Trust Bundle from the MIS, verify from the WFM host
that the Trust Bundle retrieval endpoint is reachable:

```bash
curl --cacert https-ca.crt https://mis.margo.org:9443/.well-known/spiffe/bundle.json
# → a SPIFFE bundle (JSON document with "keys")
```

**Step 3 — Install the identity of the CTT**

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 1) WFM Supplier → 1. Setup MIAF Identity → 2) MIS-issued identity
#
# Folder containing the client SVID:   the folder x509svid-acme-wfm-ctt-client
```

The step ends with `Identity setup complete` and prints
`CTT client SVID : spiffe://margo.org/margo/wfm/acme-wfm/client/ctt-client`.

When the MIS runs on a different host than the CTT, transfer the three files
the CTT requires and provide the folder to the same CLI step:

```bash
# On the MIS host, in the folder that contains the x509svid-* folders
mkdir -p ~/ctt-certs
cp x509svid-acme-wfm-ctt-client/payload-cert.pem ~/ctt-certs/client-svid-cert.pem
cp x509svid-acme-wfm-ctt-client/payload-key.pem  ~/ctt-certs/client-svid-key.pem
cp ~/mis-deployment/certs/ca.crt                 ~/ctt-certs/mis-ca.crt

# Transfer the folder to the home directory of the CTT host
scp -r ~/ctt-certs ctt-user@ctt-host:~/
```

The same folder serves the Device Supplier setup when it also contains the
X.509-SVID of the mock WFM as `wfm-svid-cert.pem` and `wfm-svid-key.pem`.

**Step 4 — Select the Application Package for the Application Registry checks**

The `core` group also verifies the Application Registry. Before the CLI is
started in Phase 2, name one Application Package in the registry of the
supplier:

```bash
oras login <registry-host>                          # only if the registry requires credentials
export REGISTRY_REF=<registry-host>/<repository>:<tag>
```

The CTT host must trust the TLS certificate of the registry. If the registry
uses a private CA, add that CA to the trust store of the host first
(`sudo cp registry-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`).

**Step 5 — Assign a deployment to the CTT**

In the WFM, assign an application deployment to the WFM Client identity of the
CTT. The requirements for that deployment are given in
[Deployment scenario](#deployment-scenario-assign-a-deployment-to-the-ctts-client).

---

## Phase 2 — Test execution

### Start the CLI and select a test group

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 1) WFM Supplier → 2) Functional tests (Group-based test management) → the group
```

A group is a named set of tests of the suite. The report states the group that
was executed.

| Group | Scope | Typical use |
|---|---|---|
| `core` | All groups below except `device-unregister` | Conformance result |
| `quick-check` | mTLS authentication, Device Capabilities, Desired State, conditional request (6 steps) | Verification of the URL and the identity setup |
| `management-interface` | Margo Management Interface: Device Capabilities, Desired State, content negotiation, Deployment Status, ETag and cache headers | Work on the Management Interface |
| `deployment-delivery` | Delivery of a multi-component deployment: State Manifest URLs, ApplicationDeployment YAML, Deployment Bundle and their digests | Work on deployment delivery |
| `identity` | MIAF: mTLS handshake, rejected clients, SVID rotation | Work on MIAF |
| `application-registry` | Application Registry (OCI): manifest, media types, pulls, tags | Work on the registry |
| `observability` | A device that declares an OpenTelemetry collector is accepted | Work on observability |
| `device-unregister` | `DELETE /api/v1/capabilities/{deviceId}` | Separate run against the WFM of a supplier |
| `postman-lifecycle`, `postman-error-handling` | Positive and negative requests authored in Postman | Examples for tests authored in Postman |

The `device-unregister` group is separate from `core` because the sandbox
Symphony build stops responding when it receives this request (its service
restarts after about one minute). The format of the Postman groups is described
in `docs/MARGO_Conformance _Approach.md`, section "Postman Template for
Expressing sequences of API exchanges".

### Provide the Margo Management Interface URL

```
  Base URL of the Margo Management Interface exposed by the WFM: everything before /api/v1.
    Symphony sandbox : https://localhost:8084/v1alpha2/margo
    Your own WFM     : https://<wfm-host>:<port>   (plus a path prefix, if your WFM has one)
Enter Margo Management Interface URL:
```

Enter the address up to, but not including, `/api/v1`; the CTT appends the API
paths. Examples:

- Sandbox Symphony: `https://localhost:8084/v1alpha2/margo`
- A WFM that serves `https://wfm.example.com/api/v1/deployments`: `https://wfm.example.com`

```
Enter MIAF mTLS URL for mtls:true steps [Enter = same as above, ...]:
```

Press Enter. A different URL is required only when the WFM serves its mTLS
endpoint on another port than the URL entered first.

### Deployment scenario: assign a deployment to the CTT's client

The groups `core` and `deployment-delivery` contain the scenario
`wfm-multi-component-deployment`. It verifies how the WFM delivers a deployment
(State Manifest, ApplicationDeployment YAML, Deployment Bundle). The WFM must therefore have
an application deployment assigned to the WFM Client identity of the CTT.

Assigning a deployment is an operator action in the WFM. It is not defined by
the Margo specification; the CTT therefore does not perform it and does not use
any operator (northbound) API of the WFM. The run states what is required:

```
ℹ️  This group tests deployment delivery. The WFM must have an application
ℹ️  deployment assigned to the CTT's client:
ℹ️      spiffe://margo.org/margo/wfm/wfm/client/ctt-client
ℹ️  with two components, one 'wait: true' and one 'wait: false'.
```

- **Sandbox Symphony:** run the helper of
  [Phase 1, Step 3](#margo-sandbox-symphony) before the run. The helper is not
  part of the conformance run: it uses the operator API of Symphony, as the
  sandbox `wfm-cli.sh` does.
- **WFM of a supplier:** in the WFM, assign an application deployment to the
  WFM Client SPIFFE ID shown. The deployment must have two components, one with
  `wait: true` and one with `wait: false`; its required content is described in
  `ctt-runner/wfm-supplier/utils/fixtures/multi-component-app-deployment.yaml`.

When no deployment is assigned at the time the run reaches the scenario, the
run prints the instructions again and waits up to 5 minutes:

```
  [efd8ad9d-...]  Wait For The Multi-Component Deployment To Be Assigned To The CTT's Client
    👉 The WFM lists no deployment for the CTT's client yet: spiffe://margo.org/margo/wfm/wfm/client/ctt-client
    ...
    ⏳ [poll attempt 1] not ready yet (deployments expected length >= 1, got 0) — retrying in 10s (waiting up to 299s more)...
```

The run continues as soon as the State Manifest lists the deployment. If none is listed
within 5 minutes, the waiting step and the following steps of the scenario are
reported as `NOT RUN` with the reason. They are not failures, because the WFM
was not assessed on them. Assign the deployment and execute the group again to
obtain a result for these steps.

### Conformance report and signed PDF

Each run writes three files to `ctt-runner/reports/wfm-supplier/`:

```
wfm-scenario-report-core_<timestamp>.html          conformance report
wfm-scenario-report-core_<timestamp>_signed.pdf    the same report as a digitally signed PDF
ca_cert.pem                                        certificate required to verify the signature
```

The WFM Supplier and Device Supplier reports use the same layout:

| Part | Content |
|---|---|
| Header | Persona, group, claimed version, CTT Margo version, system under test, time of the run |
| Result line | Steps passed, failed, not run, total |
| Requirements Coverage | One row per requirement ID: `PASS`, `FAIL` or `NOT RUN`, and the steps that verify it |
| Scenario Summary | Passed, failed and not run steps per scenario |
| Step Details | Every step: requirement IDs, method, endpoint, expected and actual HTTP status, result, reason |

A requirement is `FAIL` when any step that verifies it failed, `PASS` when at
least one of its steps passed and none failed, and `NOT RUN` when none of its
steps was executed. A step is `NOT RUN` when its precondition is absent; it is
neither a pass nor a failure.

**Signed PDF.** The signed PDF is created automatically at the end of every
run. The first run installs the PDF tools (requires `sudo` and internet access,
about one minute); later runs take about 15 seconds. The signature proves that
the PDF was not modified after the run. By default the CTT signs with its own
certificate authority, created on the host at first use and kept in
`scripts/signing-identity/`; all reports signed on that host verify against the
same `ca_cert.pem`. Submit the signed PDF together with `ca_cert.pem` as the
evidence of the conformance run.

Verify a signed report:

```bash
cd $HOME/workspace/conformance_test_toolkit
scripts/.venv/bin/python scripts/pdf_verify.py \
  ctt-runner/reports/wfm-supplier/wfm-scenario-report-core_<timestamp>_signed.pdf \
  ctt-runner/reports/wfm-supplier/ca_cert.pem
# Unchanged since signing : yes
# Signer chains to ctt-runner/reports/wfm-supplier/ca_cert.pem : yes
# RESULT    : signature OK
```

| Option | Command |
|---|---|
| Skip the signed PDF | `CTT_SIGN_REPORT=no bash ctt-runner/ctt-start.sh` |
| Sign with a provided certificate (`.p12`) | `CTT_SIGN_CERT=/path/to/signer.p12 CTT_SIGN_PASSPHRASE=secret bash ctt-runner/ctt-start.sh` |
| Sign an existing HTML report | `bash scripts/pdf_ops.sh ctt-runner/reports/wfm-supplier/name-of-report.html` (output in `./generatedReport/`) |

If the signed PDF cannot be created, the run reports the cause; the test result
and the HTML report are not affected.

### Reference result: sandbox Symphony

A `core` run takes about one minute. Against the sandbox Symphony build
verified with this guide (October 2026) the result is **52 steps: 39 passed,
11 failed, 2 not run**, and **28 of 36 requirements passing, 7 failing,
1 not run**. The failures are deviations of that Symphony build from Margo
`1.0.0-rc.3`; they do not indicate a setup error:

| Failing step | Behaviour of Symphony | Requirement reported as FAIL |
|---|---|---|
| `wfm-core-cap-3`, `wfm-core-cap-4`, `wfm-core-cap-5` | Accepts Device Capabilities with an invalid deployment type, an invalid runtime, or without `vendor` (201 instead of 422) | MANAGEMENTINTERFACE-023 |
| `wfm-core-cn-1` | Answers an unsupported `Accept` header with 400 instead of 406 | MANAGEMENTINTERFACE-008 |
| `wfm-core-ds-2` | Answers a request without `Accept` header with 400 instead of the State Manifest | MANAGEMENTINTERFACE-007 |
| `wfm-core-ds-not-immutable`, `wfm-mc-manifest-not-immutable` | Marks the State Manifest `Cache-Control: ... immutable` | MANAGEMENTINTERFACE-035 |
| `wfm-core-status-1` | Answers a Deployment Status report for an unknown deployment with 500 | MANAGEMENTINTERFACE-023 |
| `step-wfm-hi-1.3` | The `ETag` of the State Manifest is not the digest of the response body | MANAGEMENTINTERFACE-015, -036 |
| `wfm-mc-manifest-urls` | URLs in the State Manifest have the form `/api/v1/clients/<spiffe-id>/...` | MANAGEMENTINTERFACE-023 |
| `wfm-mc-bundle-cache` | `Cache-Control` of the Deployment Bundle is `public` instead of `private` | MANAGEMENTINTERFACE-038 |

Each step carries only the requirement IDs its own checks verify; one deviation
therefore affects only its own requirement. The 2 steps not run belong to the
SVID rotation scenario described below.

### SVID rotation scenario

This scenario verifies that the WFM continues to accept the CTT after its
X.509-SVID is reissued for the same SPIFFE ID, without any change to the local
authorization policy. It requires two X.509-SVIDs for the same SPIFFE ID and is
therefore `NOT RUN` after the initial setup. To execute it:

1. Complete Phase 1 and run a group once with the first X.509-SVID.
2. Reissue the WFM Client SVID of the CTT with the same WFM ID and WFM Client
   ID, as described in
   [Renewal and Reissuance](https://github.com/margo/sandbox/blob/main/docs/identity-lifecycle.md#renewal-and-reissuance)
   of the sandbox Identity Lifecycle guide.
3. Repeat the identity installation of Phase 1 (`Setup MIAF Identity`). The
   CLI installs the new X.509-SVID, retains the one it replaces and reports
   this.
4. Run the group `identity`. It sends one request with the previous X.509-SVID
   and one with the new one; both must succeed.

---

## Certificate validity and renewal

| File in `ctt-runner/wfm-supplier/utils/fixtures/miaf/real/` | Validity | Action on expiry |
|---|---|---|
| `client-svid-cert.pem` — X.509-SVID of the CTT | About 90 days (sandbox MIS default) | Reissue the WFM Client SVID and repeat `Setup MIAF Identity` |
| `trust-bundle-ca.pem` — SVID Root CA certificate (trust anchor) | Lifetime of the Root CA of the MIS | Repeat `Setup MIAF Identity` after the Root CA is replaced |

```bash
openssl x509 -in ctt-runner/wfm-supplier/utils/fixtures/miaf/real/client-svid-cert.pem -noout -enddate
```

TLS handshake errors during a run (`certificate required`, `unknown CA`,
`certificate has expired`) indicate that the X.509-SVID or the trust anchor
must be checked first.

---

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| `Setup MIAF Identity`: `The client X.509-SVID does not chain to the given SVID Root CA` | The X.509-SVID and the Root CA certificate originate from different MIS installations | Provide the folder (or Root CA certificate) of the MIS that issued the X.509-SVID. No file is changed by the failed attempt |
| `Setup MIAF Identity`: `That is not a client SVID` | The SVID folder of the WFM was selected | Repeat the step and select the WFM Client SVID (`.../client/<wfm-client-id>`) |
| `Setup MIAF Identity`: `No known layout found` | The folder contains neither `x509svid-*` folders nor the flat file set | Provide the SVID folder of the CTT (`x509svid-<wfm-id>-<wfm-client-id>`), the folder that contains it, or a folder with `client-svid-cert.pem`, `client-svid-key.pem` and `mis-ca.crt` |
| `MIAF cert validation failed` at the start of a run | Identity files were replaced manually with an inconsistent certificate, key or Root CA | Repeat `Setup MIAF Identity` |
| Every step: `unable to verify the first certificate` | The X.509-SVID of the WFM does not chain to the installed trust anchor: Phase 1 was skipped or a different MIS issued the WFM SVID | Repeat `Setup MIAF Identity` with the material of the MIS that issued the WFM SVID |
| Every step: `WFM presented ..., expected ...` | The WFM SPIFFE ID is not the one the WFM Client SPIFFE ID of the CTT is derived from | Issue the CTT a WFM Client SVID for the WFM ID of this WFM |
| Every step: `certificate required`, `bad certificate` or `403` | The WFM does not authorize the X.509-SVID of the CTT | Add the WFM Client SPIFFE ID printed by `Setup MIAF Identity` to the local authorization policy of the WFM (Symphony: `wfm.sh` option 7) |
| Every step: `ECONNREFUSED` or `could not reach the WFM` | Incorrect Margo Management Interface URL, or the WFM is not running | Verify the URL and port (Symphony: `https://localhost:8084/v1alpha2/margo`) |
| `certificate has expired` | An X.509-SVID has exceeded its validity | Reissue the SVIDs and repeat `Setup MIAF Identity` |
| Application Registry steps fail with `not found` | The Application Package is not in the registry | Sandbox: publish it (Phase 1, Step 2). WFM of a supplier: set `REGISTRY_REF` |
| Application Registry steps fail otherwise | `oras` is not installed or not logged in | Install `oras`; run `oras login` for the registry |
| Application Registry steps fail with `tls: failed to verify certificate` | The CTT host does not trust the TLS certificate of the registry | Add the CA of the registry to the trust store of the host |
| Steps of the deployment scenario are `NOT RUN` ("no application deployment ... appeared within 5 minutes") | No deployment is assigned to the WFM Client identity of the CTT | Sandbox: run `provision-multi-component.sh`, then repeat the run. WFM of a supplier: assign the deployment to the SPIFFE ID the run printed. If a deployment was assigned, the WFM does not list it in `GET /api/v1/deployments` |
| `wfm-mc-bundle-fetch` and `wfm-mc-bundle-contents` fail with HTTP 500 on Symphony | The host was rebooted or Symphony was restarted, and Symphony lost the Deployment Bundle archive | Run `provision-multi-component.sh` again; it detects the condition and assigns the deployment again. Then repeat the run |
| `ERROR: failed to get auth token` from the Symphony helper | Symphony is not running, or its operator API is not at `https://localhost:8082/v1alpha2` with user `admin` | Start Symphony, or pass `--nbi-url`, `--nbi-user`, `--nbi-pass` to the helper. The helper supports Symphony only |
| `Signed PDF not created` at the end of a run | Stated below the message. Typical causes: the repository folder is owned by root, or no internet access for the initial tool installation | Resolve the stated cause (ownership: `sudo chown -R $USER:$USER $HOME/workspace/conformance_test_toolkit`), then run the `pdf_ops.sh` command the run printed |
| A step fails with an unexpected 500 | Internal error of the WFM | Deviation of the WFM; refer to the requirement ID in the report |

---

## Cleanup

- **Sandbox Symphony:** remove the Application Package registration and the
  deployments created by the helper:
  `bash ctt-runner/wfm-supplier/utils/fixtures/provision-multi-component.sh --cleanup`
- **WFM of a supplier:** remove the test deployment by the same means it was
  assigned.
- **Sandbox environment:** see
  [Cleaning Up (Starting Fresh)](https://github.com/margo/sandbox/blob/main/docs/setup-guide.md#cleaning-up-starting-fresh)
  in the sandbox Setup Guide.

---

## Checklist

```
Phase 1 — Identity provisioning (once per WFM; repeat when an X.509-SVID is reissued)

  Margo sandbox (Symphony):
  □ MIS and Symphony installed per the sandbox Setup Guide (MIS first, then WFM)
  □ WFM Client SVID for the CTT generated: WFM ID wfm, WFM Client ID ctt-client
  □ spiffe://margo.org/margo/wfm/wfm/client/ctt-client added to the SPIFFE ID allowlist of Symphony
  □ sudo chown -R $USER:$USER $HOME/.docker
  □ ctt-start.sh → 1) WFM Supplier → 1. Setup MIAF Identity → 2) MIS-issued identity
      folder: $HOME/workspace/sandbox/scripts/x509svid-wfm-ctt-client
  □ bash ctt-runner/wfm-supplier/utils/fixtures/margo-ctt-package/push.sh
  □ bash ctt-runner/wfm-supplier/utils/fixtures/provision-multi-component.sh

  WFM of a supplier:
  □ WFM SVID and WFM Client SVID (for the CTT) issued by the MIS of the Trust Domain
  □ WFM: serves its X.509-SVID, has the Trust Bundle, authorizes the WFM Client SPIFFE ID of the CTT
  □ ctt-start.sh → 1) WFM Supplier → 1. Setup MIAF Identity → 2) MIS-issued identity
  □ export REGISTRY_REF=<registry-host>/<repository>:<tag>
  □ Application deployment (two components) assigned to the WFM Client identity of the CTT

Phase 2 — Test execution (every run)
  □ bash ctt-runner/ctt-start.sh → 1) WFM Supplier → 2) Functional tests → core
  □ Margo Management Interface URL: everything before /api/v1 (Symphony: https://localhost:8084/v1alpha2/margo)
  □ MIAF mTLS URL: press Enter
  □ Report:     ctt-runner/reports/wfm-supplier/wfm-scenario-report-core_<timestamp>.html
  □ Signed PDF: ctt-runner/reports/wfm-supplier/wfm-scenario-report-core_<timestamp>_signed.pdf (+ ca_cert.pem)
      (sandbox Symphony reference: 39 passed, 11 failed, 2 not run)
```
