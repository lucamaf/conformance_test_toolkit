# WFM Supplier Conformance — Setup and Execution Guide

**Persona:** WFM Supplier  
**Spec baseline:** Margo `1.0.0-rc.3` (MIAF / mTLS authentication)  
**Audience:** WFM vendors, Margo adopters, integration engineers

This guide walks you from a clean checkout to a conformance report,
step by step. Follow it once and you will understand every moving part; on
subsequent runs only the identity setup (Phase 1) needs attention if certs
have expired.

---

## What CTT does in this persona

Your WFM is the system under test and the CTT acts as a **mock device** (a WFM
Client). It fires real HTTPS requests at your WFM, checks the responses against
the Margo spec, and generates an HTML report where every test row is traced to
a specific requirement ID. For the demo the WFM is the sandbox Symphony; a
vendor uses their own WFM.

Authentication is **mutual TLS (MIAF)**: the CTT presents an X.509-SVID
(a SPIFFE-based certificate) that your WFM's MIS issued, and your WFM
presents its own. No username/password, no API keys.

```
CTT (mock device)                Your WFM (demo: Symphony)
  svid-cert.pem  ──mTLS──►  validates against trust-bundle-ca.pem
                 ◄──mTLS──  validates CTT trusts WFM's own cert
        ▼
  run_wfm_scenarios.js
  fires scenario steps
        ▼
  ctt-runner/reports/wfm-supplier/
  wfm-scenario-report-core_<timestamp>.html
```

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Node.js | 18 or newer | drives `run_wfm_scenarios.js`; no `npm install` needed |
| OpenSSL | 1.1+ | certificate inspection; usually pre-installed |
| jq | any | group file parsing; `apt install jq` |
| bash | 4+ | |
| OS | Linux | tested on Ubuntu 24.04; macOS is not supported |
| oras | 1.x | used by the Application Registry scenario of the `core` group; [oras.land](https://oras.land/docs/installation). Run `oras login <registry>` once if the registry needs credentials. |

Clone the repo and check out the conformance branch:

```bash
mkdir -p ~/workspace && cd ~/workspace
git clone https://github.com/margo/conformance_test_toolkit.git
cd conformance_test_toolkit
git checkout feature/multi-persona-conformance
```

Then verify tooling:

```bash
node --version     # v18 or newer
openssl version
jq --version
oras version
```

---

## Phase 1 — Identity Setup

The CTT needs a client SVID issued by the MIS of the WFM under test, for that
WFM's ID: `<WFM SPIFFE ID>/client/<client-id>`. The CTT verifies the WFM's
certificate against the MIS CA and checks that the WFM presents exactly
`<WFM SPIFFE ID>`; the WFM must have the CTT's client SPIFFE ID on its
accepted-client list.

One MIS — the Margo sandbox MIS — issues both: the WFM's own SVID and the CTT's
client SVID. That is what makes them trust each other.

- Testing **Symphony in the sandbox** — follow the steps below.
- Testing **your own WFM** — skip to [Testing a vendor WFM](#testing-a-vendor-wfm).

### Sandbox MIS as Centralized SVID Authority (Symphony)

The Margo sandbox MIS (`mis.sh`) acts as the centralized SVID authority for
all CTT identity setup. Use this path when testing the CTT against Symphony
(WFM) in a local or sandbox environment.

**Before you start — the sandbox itself.** Clone the Margo sandbox to
`~/sandbox` and set its environment as the sandbox setup guide describes
(`~/sandbox/docs/setup-guide.md`, Steps 1 and 2: the `.env` files in
`~/sandbox/scripts/` and the `symphony.machine` / `harbor.machine` entries in
`/etc/hosts`):

```bash
git clone https://github.com/margo/sandbox.git ~/sandbox
```

**Install the sandbox WFM prerequisites (once per machine):**

```bash
sudo -E bash ~/sandbox/scripts/wfm.sh
# → 1) PreRequisites: Setup
# When it ends with "Press Enter to continue...": press Enter, then 8 to exit
```

This is the sandbox's own installation of everything Symphony needs: Docker,
Go, k3s, Redis, ORAS, the Harbor registry, the Symphony sources and its sample
packages. It takes 3 to 15 minutes.

> **Run it only once.** On a machine where Symphony is already set up, skip it:
> running it again empties Symphony's accepted-client list and rebuilds Harbor
> with a new certificate.

It runs as root and leaves the Docker settings of your user owned by root, which
later stops `oras` from reaching the registry. Give them back to your user:

```bash
sudo chown -R $USER:$USER ~/.docker
```

Note:
    > **If `$HOME/symphony/` does not exist after prerequisites:** wfm.sh may have
    > installed symphony to `/root/symphony/` (happens if the `-E` flag was not
    > passed or was dropped internally). Fix it with:
    > ```bash
    > sudo mv /root/symphony $HOME/symphony
    > sudo chown -R $USER:$USER $HOME/symphony
    > ```

After prerequisites, Symphony prints the three steps that must be completed
before starting it:

```
1. Place your WFM SVID & Key in:   $HOME/symphony/api/certificates/
2. Place the MIS HTTPS CA cert in: $HOME/symphony/api/mis/https-ca.crt
3. Register SPIFFE IDs of WFM Clients via menu option 7
Then: Start Symphony via menu option 3
```

The steps below do exactly that.

**Step 1 — Generate identity via sandbox mis.sh:**

If the sandbox MIS is not installed on this machine yet, install it first. Run
the menu three times, with options 1, 3 and 4 in this order; each time press
Enter at "Press Enter to continue..." and then `7` to exit:

```bash
sudo -E bash ~/sandbox/scripts/mis.sh     # → 1) PreRequisites: Setup
sudo -E bash ~/sandbox/scripts/mis.sh     # → 3) Factory Bootstrap: Generate Root CAs
sudo -E bash ~/sandbox/scripts/mis.sh     # → 4) Margo Identity Service: Install
```

> Option 3 creates new CAs. Do not run it again on a MIS that has already
> issued SVIDs: every SVID issued before stops being trusted.

Then generate the two SVIDs. Run the command from inside `~/mis-deployment` —
`mis.sh` writes each SVID folder into the directory you run it from:

```bash
cd ~/mis-deployment
sudo -E bash ~/sandbox/scripts/mis.sh generate-svid     # run 1: Symphony (the WFM)
sudo -E bash ~/sandbox/scripts/mis.sh generate-svid     # run 2: the CTT (a client of that WFM)

# the folders are created with root ownership — fix it:
sudo chown -R $USER:$USER ~/mis-deployment
```

Answer the prompts like this:

| Prompt | Run 1 — Symphony | Run 2 — CTT |
|---|---|---|
| `Enter Trust Domain [default: margo.org]:` | press Enter | press Enter |
| `Enter choice [1/2]:` | `1` | `2` |
| `Enter WFM ID:` | `wfm` | `wfm` |
| `Enter WFM Client ID:` | (not asked) | `ctt-client` |
| `Enter TTL in seconds [default: 7776000]:` | press Enter | press Enter |
| `DNS SANs:` | press Enter | press Enter |
| `Proceed? [Y/n]:` | press Enter | press Enter |

The WFM ID must be the same in both runs.

**Step 2 — Check what was generated:**

```bash
ls ~/mis-deployment/ | grep x509svid
# x509svid-wfm              ← Symphony's WFM SVID (server identity)
# x509svid-wfm-ctt-client   ← the CTT's client SVID

WFM_SVID_DIR=~/mis-deployment/x509svid-wfm     # change "wfm" if you entered a different WFM ID
```

**Step 3 — Place WFM SVID & key in Symphony's certificates directory:**

```bash
sudo cp ${WFM_SVID_DIR}/payload-cert.pem  $HOME/symphony/api/certificates/
sudo cp ${WFM_SVID_DIR}/payload-key.pem   $HOME/symphony/api/certificates/
sudo chown $USER:$USER \
    $HOME/symphony/api/certificates/payload-cert.pem \
    $HOME/symphony/api/certificates/payload-key.pem

# Verify the cert and key match (public keys must be identical):
openssl x509 -in $HOME/symphony/api/certificates/payload-cert.pem -noout -pubkey | openssl md5
openssl ec  -in $HOME/symphony/api/certificates/payload-key.pem  -pubout 2>/dev/null | openssl md5
# Both lines must print the same MD5 hash — if they differ, re-run mis.sh
```

**Step 4 — Place MIS HTTPS CA in Symphony's mis directory:**

```bash
sudo cp ~/mis-deployment/certs/https-ca.crt  $HOME/symphony/api/mis/
sudo chown $USER:$USER $HOME/symphony/api/mis/https-ca.crt
```

**Step 5 — Point mis.margo.org at this machine in /etc/hosts:**

Symphony, and any device-agent you run later, reach the MIS by this hostname.
The entry must be this machine's own network address — not `127.0.0.1`, which
a device-agent running in a container cannot use, and not a public address,
which times out.

```bash
sudo sed -i '/mis\.margo\.org/d' /etc/hosts
echo "$(hostname -I | awk '{print $1}') mis.margo.org" | sudo tee -a /etc/hosts

# Verify — prints this machine's address followed by mis.margo.org:
grep "mis.margo.org" /etc/hosts
```

**Step 6 — Register the CTT's client SPIFFE ID (wfm.sh option 7):**

```bash
sudo -E bash ~/sandbox/scripts/wfm.sh
```

Answer the prompts like this:

| Prompt | Answer |
|---|---|
| `Enter choice [1-8]:` | `7` |
| `Use default path? [Y/n]:` | press Enter |
| `Enter choice [1-3]:` | `1` (Add SPIFFE IDs) |
| `>` | `spiffe://margo.org/margo/wfm/wfm/client/ctt-client` |
| `Enter choice [1-3]:` | `3` (Back) |
| `Press Enter to continue...` | press Enter |
| `Enter choice [1-8]:` | `8` (Exit) |

The ID is the CTT's client SPIFFE ID that `mis.sh` printed in run 2.

**Step 7 — Copy the MIS-generated client SVID into the CTT (via the CLI):**

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 1) WFM Supplier → 1. Setup MIAF Identity → 2) MIS-issued identity
#
# When prompted:
#   Folder containing the client SVID [~/mis-deployment]:   press Enter
#   Which one is the CTT's client SVID? [2]:   the number of x509svid-wfm-ctt-client
#
# The CLI lists every SVID folder it finds. Type the number shown next to
# x509svid-wfm-ctt-client. With only the two folders above it is 2, the default;
# with more folders (for example after the Device Supplier setup) it is not.
```

The CLI copies the client SVID, its key and the MIS CA into
`ctt-runner/wfm-supplier/utils/fixtures/miaf/real/`, after checking that the
SVID was issued by that CA and is a client SVID. It reads root-owned folders
with `sudo` when needed, and prints the client SPIFFE ID — the same one you
registered in Step 6.

**Step 8 — Verify certs before starting Symphony:**

```bash
# 1. CTT SVID cert chains to the trust bundle CA (the CLI already checked this in Step 7):
openssl verify \
    -CAfile ctt-runner/wfm-supplier/utils/fixtures/miaf/real/trust-bundle-ca.pem \
    ctt-runner/wfm-supplier/utils/fixtures/miaf/real/client-svid-cert.pem
# → client-svid-cert.pem: OK

# 2. MIS HTTPS server cert is reachable and chains to the MIS HTTPS CA:
echo | openssl s_client \
    -connect 127.0.0.1:9443 \
    -CAfile ~/mis-deployment/certs/https-ca.crt 2>&1 | grep "Verify return code"
# → Verify return code: 0 (ok)  (if non-zero, re-run mis.sh to regenerate certs)
```

**Step 9 — Start Symphony:**

```bash
sudo -E bash ~/sandbox/scripts/wfm.sh
# → 3) Symphony: Start
# When it ends with "Press Enter to continue...": press Enter, then 8 to exit
```

After a few seconds, verify it stays running:

```bash
sudo docker ps --filter name=symphony-api-container --format "{{.Names}}\t{{.Status}}"
# Should show: symphony-api-container   Up N seconds
# If it shows "Exited", check: sudo docker logs symphony-api-container 2>&1 | tail -20
```

**Step 10 — Put the CTT's test package into the sandbox Harbor:**

The `core` group uses one Application Package in the registry, for the
Application Registry checks and for the deployment it asks Symphony to deliver.
Push it once:

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/wfm-supplier/utils/fixtures/margo-ctt-package/push.sh
# → Pushed [registry] harbor.machine:8443/library/margo-ctt-hello-world:1.0.0
```

If it fails with `~/.docker/config.json: permission denied`, run
`sudo chown -R $USER:$USER ~/.docker` and repeat.

### Testing a vendor WFM

Use this instead of the Symphony steps above when the WFM under test is your
own. The same sandbox MIS issues the SVID your WFM presents and the SVID the
CTT presents. The examples use the WFM ID `acme-wfm` — use one name per WFM.

**Step 1 — On the MIS machine, generate the two SVIDs:**

```bash
cd ~/mis-deployment
sudo -E bash ~/sandbox/scripts/mis.sh generate-svid     # run 1: the vendor's WFM
sudo -E bash ~/sandbox/scripts/mis.sh generate-svid     # run 2: the CTT (a client of that WFM)
sudo chown -R $USER:$USER ~/mis-deployment
```

| Prompt | Run 1 — vendor's WFM | Run 2 — CTT |
|---|---|---|
| `Enter choice [1/2]:` | `1` | `2` |
| `Enter WFM ID:` | `acme-wfm` | `acme-wfm` |
| `Enter WFM Client ID:` | (not asked) | `ctt-client` |
| every other prompt | press Enter | press Enter |

**Step 2 — Give the WFM's owner these three things:**

| What | Where it comes from |
|---|---|
| The WFM's SVID and key, to serve on its mTLS port | `~/mis-deployment/x509svid-acme-wfm/payload-cert.pem` and `payload-key.pem` |
| What to trust client SVIDs with | the CA file `~/mis-deployment/certs/ca.crt` — or the MIS itself: `https://mis.margo.org:9443`, its HTTPS CA `~/mis-deployment/certs/https-ca.crt`, and a hosts entry `<MIS-machine-IP> mis.margo.org` |
| The client to accept | `spiffe://margo.org/margo/wfm/acme-wfm/client/ctt-client` |

**Step 3 — Install the CTT's client SVID through the CLI:**

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
# Select: 1) WFM Supplier → 1. Setup MIAF Identity → 2) MIS-issued identity
#
# When prompted:
#   Folder containing the client SVID [~/mis-deployment]:   press Enter
#   Which one is the CTT's client SVID?:   the number of x509svid-acme-wfm-ctt-client
```

It must end with `Identity setup complete` and print
`CTT client SVID : spiffe://margo.org/margo/wfm/acme-wfm/client/ctt-client`.

**Step 4 — Point the Application Registry checks at the vendor's registry:**

The `core` group also checks the Application Registry. Before starting the CLI
in Phase 2, name one Application Package in that registry:

```bash
oras login <registry-host>                          # only if it needs credentials
export REGISTRY_REF=<registry-host>/<repository>:<tag>
```

The CTT machine must trust the registry's TLS certificate. If the registry uses
its own CA, add that CA to the machine's trust store first
(`sudo cp registry-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`).

---

## Phase 2 — Run the conformance suite

Once the identity from Phase 1 is in place, everything else is driven by the
CLI prompts.

### Launch the runner

```bash
cd $HOME/workspace/conformance_test_toolkit
bash ctt-runner/ctt-start.sh
```

You will see an interactive menu. Select:

```
1) WFM Supplier
```

Then:

```
2) Functional tests   (Group-based test management)
```

Then select the group. A group is a named set of tests from the suite, so you
can run one area at a time and the report states which set was run:

| Group | What it checks | When to run it |
|---|---|---|
| `quick-check` | Identity accepted over mTLS, a device registered, manifest served, conditional request answered (4 steps) | First, to confirm the URL and the identity setup |
| `management-interface` | The Management Interface API: capabilities, desired state, content negotiation, status, ETag and cache headers | While working on the API |
| `deployment-delivery` | A multi-component deployment: manifest URLs, deployment YAML, bundle archive and their digests | While working on deployment delivery |
| `identity` | mTLS handshake, trust bundle, refused clients, SVID rotation | While working on MIAF |
| `application-registry` | The OCI Application Registry: manifest, media types, pulls, tags | While working on the registry |
| `observability` | A device reporting an OpenTelemetry collector is accepted | While working on observability |
| `device-unregister` | `DELETE /api/v1/capabilities/{deviceId}` | Against your own WFM, as a separate run |
| `postman-lifecycle`, `postman-error-handling` | Positive and negative requests written in Postman | As examples for adding your own tests from Postman |
| `core` | Everything above except `device-unregister` | For the conformance result |

For the full WFM conformance test set:

```
2) core            (v1.0.0-rc.3)
```

Enter the number shown next to `core` in the list.

`core` does not include the `DELETE /api/v1/capabilities/{deviceId}` check
(unregister a device). That one is in its own group, `device-unregister`, so it
is only sent when you choose to: the Symphony sandbox build stopped responding
when it received this request (its service restarts by itself after about a
minute). Run `device-unregister` against your own WFM as a separate run.

The two Postman groups, `postman-lifecycle` (10 requests) and
`postman-error-handling` (7 requests), run the same way as `core`. The format is
described in `docs/MARGO_Conformance _Approach.md`, section "Postman Template
for Expressing sequences of API exchanges".

### Enter your WFM endpoints

The runner will prompt for two URLs:

```
  The WFM SBI URL is everything before /api/v1 — the CTT adds /api/v1/... itself.
    Symphony sandbox : https://localhost:8084/v1alpha2/margo
    Your own WFM     : https://<wfm-host>:<port>   (plus a path prefix, if your WFM has one)
Enter WFM SBI URL:
```

This is the **SBI (South-Bound Interface)** — the port the WFM exposes for
device agents. It is the mTLS port. Enter the address up to, but not including,
`/api/v1`:

- Symphony sandbox: `https://localhost:8084/v1alpha2/margo`
- A WFM that serves `https://wfm.example.com/api/v1/deployments`: `https://wfm.example.com`

```
Enter MIAF mTLS URL for mtls:true steps [Enter = same as above, ...]:
```

Press Enter to use the same URL — the first URL is already the mTLS port. Only
enter a different URL if your WFM serves mTLS on another port than the URL you
gave first. For Symphony sandbox: press Enter.

### Multi-component deployment

If the selected group includes the `wfm-multi-component-deployment` scenario,
the runner detects it and, for Symphony, provisions the deployment automatically:

```
────────────────────────────────────────────────────────────────
[INFO] Group includes 'wfm-multi-component-deployment'
[INFO] Pre-seeding a multi-component ApplicationDeployment via the WFM NBI...
[INFO]   Detected device SPIFFE ID: spiffe://your-domain.com/.../margo-ctt

  WFM NBI base URL [https://localhost:8082/v1alpha2]:
  NBI username [admin]:
  NBI password (leave empty for Symphony default — empty password):
────────────────────────────────────────────────────────────────
```

This scenario requires a deployment to be assigned to the CTT's client. The
CTT then polls the WFM for it (up to 300 seconds).

**Symphony sandbox:** press Enter at all three prompts. The CTT creates the
deployment through Symphony's NBI, so you do not need to create it in the WFM
console. It uses the package you pushed in Phase 1, Step 10.

**Your own WFM:** the automatic provisioning speaks Symphony's NBI and will
report `Provision script failed` — press Enter at the three prompts and let the
run continue. When it reaches this scenario it registers a device named
`multi-component-test-device` and then prints, every 10 seconds:

```
⏳ [poll attempt 1] not ready yet (deployments expected length >= 1, got 0) — retrying in 10s...
```

While it is printing that (you have 5 minutes), use your WFM's own console to
assign a deployment to `multi-component-test-device` — the device of client
`.../client/ctt-client`. The deployment needs **two components, one with
`wait: true` and one with `wait: false`**. As soon as your WFM lists it, the
run continues by itself. What the deployment must contain is described in
`ctt-runner/wfm-supplier/utils/fixtures/multi-component-app-deployment.yaml`.

The SPIFFE ID is read automatically from the client SVID installed in Phase 1 —
you do not enter it.

After provisioning, the runner proceeds into the scenario execution loop.

### The HTML report

The report is written to:

```
ctt-runner/reports/wfm-supplier/wfm-scenario-report-core_<timestamp>.html
```

Open it in any browser. It contains:
- A conformance requirement coverage table (green = at least one passing step covers the CR-ID, red = all steps for that CR-ID failed, grey = its steps were not run)
- A scenario-level summary table
- A full step-detail table with status, method, endpoint, expected/actual HTTP code, and failure reason

A step shown as `NOT RUN` was not sent because its precondition is missing —
it is neither a pass nor a failure. Today this applies to the SVID Rotation
scenario (below).

This report is the artifact you submit as evidence of conformance.

### What to expect on the sandbox Symphony

A `core` run takes about one minute. Against the sandbox Symphony build tested
with this guide (October 2026) it ends with **45 steps: 32 passed, 11 failed,
2 not run**. The failures are places where that Symphony build differs from
Margo 1.0.0-rc.3; they are not a problem of your setup:

| Failing step | What Symphony does |
|---|---|
| `wfm-core-cap-3`, `wfm-core-cap-4`, `wfm-core-cap-5` | accepts capabilities with an invalid deployment type, an invalid runtime, or without `vendor` (201 instead of 422) |
| `wfm-core-cn-1` | answers an unsupported `Accept` with 400 instead of 406 |
| `wfm-core-ds-2` | answers a request without `Accept` with 400 instead of the manifest |
| `wfm-core-ds-1`, the poll step of the multi-component scenario | marks the manifest `Cache-Control: ... immutable` |
| `wfm-core-status-1` | answers a status report for an unknown deployment with 500 |
| `step-wfm-hi-1.3` | the manifest `ETag` is not the digest of the response body |
| `wfm-mc-manifest-urls` | manifest URLs have the form `/api/v1/clients/<spiffe-id>/...` |
| `wfm-mc-bundle-fetch` | the bundle's `Cache-Control` is `public` instead of `private` |

The 2 steps not run are the SVID Rotation scenario; they run and pass after the
steps in the next section.

### SVID Rotation scenario

This scenario checks that the WFM keeps accepting the CTT after its client SVID
is re-issued, without the client being registered again. It needs two SVIDs for
the same SPIFFE ID, so it is `NOT RUN` on a first setup. To run it:

1. Complete Phase 1 and run the suite once with the first SVID.
2. Re-issue the client SVID for the **same** WFM ID and client ID
   (sandbox: `cd ~/mis-deployment`, then `sudo -E bash ~/sandbox/scripts/mis.sh`
   → 6) Generate SVID → principal 2, same IDs).
3. Run Setup MIAF Identity again (Phase 1, Step 7). The CLI installs the new
   SVID and keeps the one it replaces, and says so.
4. Run the suite again (the group `identity` is enough to see this scenario).
   It now sends one request with the earlier SVID and one with the new SVID;
   both must succeed.

---

## Certificate expiry and renewal

| File | TTL | What to do when expired |
|---|---|---|
| `miaf/real/client-svid-cert.pem` | ~90 days (MIS-issued) | Generate a new client SVID and re-run Setup MIAF Identity (Phase 1) |
| `miaf/real/trust-bundle-ca.pem` | Matches the MIS CA lifetime | Re-run Setup MIAF Identity (Phase 1) |

Check expiry any time:

```bash
openssl x509 -in ctt-runner/wfm-supplier/utils/fixtures/miaf/real/client-svid-cert.pem \
    -noout -enddate
```

If you see TLS handshake errors (`certificate required`, `unknown CA`,
`certificate has expired`) during a test run, the SVID or trust bundle is the
first thing to check.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Setup MIAF Identity: `The client SVID was not issued by the given MIS CA` | SVID and CA come from different MIS setups | Give the folder (or CA file) of the MIS that issued the SVID; nothing was changed |
| Setup MIAF Identity: `That is not a client SVID` | The WFM's own SVID folder was picked | Run it again and pick the client SVID (`.../client/<client-id>`) |
| `MIAF cert validation failed` when a run starts | Identity files replaced by hand with a mismatched cert / key / CA | Re-run Setup MIAF Identity (Phase 1) |
| Every step: `unable to verify the first certificate` | The WFM's certificate was not issued by the MIS CA in `trust-bundle-ca.pem` — Phase 1 was skipped, the wrong MIS was used, or `git checkout` / `git pull` put the repository's sample certs back | Re-run Setup MIAF Identity with the folder of the MIS that issued the WFM's SVID |
| Every step: `WFM presented ..., expected ...` | The WFM's SVID is not the WFM the CTT's client SVID belongs to | Issue the CTT a client SVID for this WFM's ID (`<WFM SPIFFE ID>/client/<client-id>`) |
| Every step: `certificate required` / `bad certificate` / `403` | The WFM does not accept the CTT's client SVID | Add the client SPIFFE ID printed by Setup MIAF Identity to the WFM's accepted-client list (Symphony: `wfm.sh` → 7) |
| Every step: `ECONNREFUSED` / `could not reach the WFM` | Wrong SBI URL, or the WFM is not running | Check the URL and port (Symphony: `https://localhost:8084/v1alpha2/margo`) |
| `certificate has expired` | Client SVID or WFM SVID past its TTL | Generate new SVIDs and re-run Setup MIAF Identity |
| Application Registry steps fail | `oras` not installed, not logged in, or the package is not in the registry | Install `oras`, `oras login <registry>`; Symphony sandbox: run `push.sh` (see Phase 2); own WFM: set `REGISTRY_REF` |
| Application Registry steps fail with `tls: failed to verify certificate` | The CTT machine does not trust the registry's certificate | Add the registry's CA to the machine's trust store (see Testing a vendor WFM, Step 4) |
| Multi-component poll times out (300s) | No deployment was assigned to the CTT's client | Symphony: check the NBI URL / credentials you entered, or run `bash ctt-runner/wfm-supplier/utils/fixtures/provision-multi-component.sh` by hand to see the error. Own WFM: assign the deployment in your console |
| `ERROR: failed to get auth token` from provision script | NBI credentials wrong, or the WFM is not Symphony | Symphony: verify username/password. Own WFM: expected — assign the deployment in your console |
| Steps fail with unexpected 500 | WFM internal error | This is a WFM implementation gap — note the CR-ID in the report and report to your WFM vendor |
| `Cache-Control: immutable` failure on manifest endpoint | WFM sets immutable on a mutable resource | WFM implementation gap — the manifest changes when deployments are added/removed (MI-035) |

---

## Cleanup after a test run

The provision script creates a deployment with a timestamp-based name
(`ctt-multi-component-<timestamp>`) so re-runs never collide with leftovers.
To clean up all CTT-created deployments from your WFM after testing:

```bash
bash ctt-runner/wfm-supplier/utils/fixtures/provision-multi-component.sh \
    --nbi-url <your-nbi-url> \
    --nbi-user <your-username> \
    --cleanup
```

For Symphony sandbox (no args):

```bash
bash ctt-runner/wfm-supplier/utils/fixtures/provision-multi-component.sh --cleanup
```

---

## Quick-reference checklist

```
Phase 1 — Identity (once per WFM, re-run only if cert expires)

  Symphony in the sandbox (sandbox MIS, mis.sh):
  □ Sandbox cloned to ~/sandbox, its .env files and /etc/hosts set (sandbox setup guide, Steps 1-2)
  □ sudo -E bash ~/sandbox/scripts/wfm.sh → 1) PreRequisites: Setup   (once per machine; Enter, then 8)
  □ sudo chown -R $USER:$USER ~/.docker
  □ MIS installed: sudo -E bash ~/sandbox/scripts/mis.sh → 1, then again → 3, then again → 4
  □ cd ~/mis-deployment && sudo -E bash ~/sandbox/scripts/mis.sh generate-svid
      run 1: choice 1, WFM ID wfm      run 2: choice 2, WFM ID wfm, client ID ctt-client
  □ sudo chown -R $USER:$USER ~/mis-deployment
  □ ls ~/mis-deployment/ | grep x509svid   (note the directory names)
  □ sudo cp ~/mis-deployment/x509svid-wfm/payload-cert.pem + payload-key.pem → $HOME/symphony/api/certificates/
  □ sudo cp ~/mis-deployment/certs/https-ca.crt  $HOME/symphony/api/mis/
  □ /etc/hosts: <this machine's address> mis.margo.org   (not 127.0.0.1)
  □ sudo -E bash ~/sandbox/scripts/wfm.sh → 7 → Enter → 1 → spiffe://margo.org/margo/wfm/wfm/client/ctt-client → 3 → Enter → 8
  □ ctt-start.sh → 1) WFM Supplier → 1. Setup MIAF Identity → 2) MIS-issued identity
      (Enter for ~/mis-deployment, then pick the client SVID)
  □ sudo -E bash ~/sandbox/scripts/wfm.sh → 3) Symphony: Start   (then 8)
  □ bash ctt-runner/wfm-supplier/utils/fixtures/margo-ctt-package/push.sh

  Your own WFM (same sandbox MIS):
  □ cd ~/mis-deployment && sudo -E bash ~/sandbox/scripts/mis.sh generate-svid
      run 1: choice 1, WFM ID acme-wfm            → give x509svid-acme-wfm to the WFM's owner
      run 2: choice 2, WFM ID acme-wfm, client ID ctt-client
  □ WFM's owner: serve that SVID on the mTLS port, trust ~/mis-deployment/certs/ca.crt,
      accept client spiffe://margo.org/margo/wfm/acme-wfm/client/ctt-client
  □ ctt-start.sh → 1) WFM Supplier → 1. Setup MIAF Identity → 2) MIS-issued identity → pick x509svid-acme-wfm-ctt-client
  □ export REGISTRY_REF=<registry-host>/<repository>:<tag>   (an Application Package in that registry)

Phase 2 — Run (repeat for each test run)
  □ bash ctt-runner/ctt-start.sh
  □ Select: 1) WFM Supplier → 2) Functional tests → core (2 in the list)
  □ Enter WFM SBI URL — everything before /api/v1 (Symphony: https://localhost:8084/v1alpha2/margo)
  □ Press Enter for MIAF URL (same port unless WFM splits them)
  □ Multi-component prompts: press Enter x3
      (Symphony: provisioned automatically; own WFM: while the CTT prints "poll attempt",
       assign a two-component deployment to device multi-component-test-device)
  □ Wait for run to complete (under a minute once the deployment is assigned; up to ~5 min while polling)
  □ Open report: ctt-runner/reports/wfm-supplier/wfm-scenario-report-core_<ts>.html
      (sandbox Symphony: 32 passed, 11 failed, 2 not run — see "What to expect on the sandbox Symphony")
```
