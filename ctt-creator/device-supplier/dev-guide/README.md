# CTT Creator — Device Supplier Dev Guide

## Overview

The **Device Supplier** persona verifies that a Margo device (its WFM Client) correctly uses the Margo Management Interface. The CTT plays the WFM: a mock WFM server that the device, or the CTT's own device client, sends its requests to. This guide is for people who write or change the device test cases and groups.

## Directory Layout

```
ctt-creator/device-supplier/
└── dev-guide/README.md          # This file

test-suites/device-supplier/
├── core/
│   ├── group.json               # Written by ctt-creator
│   └── test-cases/device-supplier.json   # The full set of scenarios
└── <group>/
    ├── group.json
    └── test-cases/<group>.json  # The scenarios this group runs

ctt-runner/device-supplier/
├── scripts/run_tests.go         # The CTT's device client (runs the scenarios)
├── scripts/cmd/device-supplier/ # The mock WFM server
└── utils/manifests/             # assertions.json, deployment templates
```

## Key Concepts

| Term | Meaning |
|---|---|
| **Test Group** | A named list of test IDs with a spec version (e.g. `core`, `quick-check`, `manifest-integrity`). Each group has a `group.json`, written by `ctt-creator`. |
| **group.json** | Describes a test group: its name, version, persona, description, the folder with its test-case files, and the scenario and step IDs to run. |
| **Test Case JSON** | Declarative scenario file (`test-suites/device-supplier/<group>/test-cases/*.json`) read by the CTT Runner. The format is in `docs/MARGO_Conformance _Approach.md`, section "Margo schema for server-side test-cases". |
| **MIAF / SVID** | The mTLS identity mechanism. The mock WFM holds a WFM SVID (`spiffe://<trust-domain>/margo/wfm/<wfm-id>`); the device presents a client SVID (`spiffe://<trust-domain>/margo/wfm/<wfm-id>/client/<wfm-client-id>`). Both are issued by the MIS. |
| **Negative Fixture** | A test-control mechanism of the mock WFM that makes it serve a manifest a device must reject (wrong digest, unsupported algorithm, version not increasing), so the device's rejection logic can be tested. |
| **manifestVersion** | A monotonically increasing counter the WFM increments each time the desired state changes. Used by the device to detect updates via `If-None-Match`. |

## Test Groups

| Group | Purpose |
|---|---|
| `core` | Every scenario of the suite — the conformance result |
| `quick-check` | Capabilities, manifest, deployment, bundle, status — first check of the setup |
| `management-interface` | The Management Interface API as a device uses it, with the errors for each call |
| `manifest-integrity` | Manifests a device MUST reject and one it MUST accept (negative fixtures) |
| `identity` | mTLS handshake, certificate conformance, trust in the WFM, SVID rotation |
| `observability` | The device's OpenTelemetry collector pushes telemetry to the CTT |
| `random-order` | The lifecycle scenarios executed in random order (`"flexibleOrder": true` in `group.json`) |
| `real-device` | Observation steps (`"observe"`) that judge the requests a real device sent to the mock WFM |

## How to Add or Update a Test Group

1. Write or change the scenarios in a file under `test-suites/device-supplier/<group>/test-cases/`. Every scenario and every step needs a unique `id`.
2. Run the creator and answer its prompts:

   ```bash
   bash ctt-creator/ctt-start.sh
   # 2 (Device Supplier) → 0 (new group, or the number of an existing group)
   # → group name → version (Enter = 1.0.0-rc.3) → description
   # → folder: test-suites/device-supplier/<group>/test-cases
   ```

   It writes `test-suites/device-supplier/<group>/group.json` with every scenario and step ID found in that folder.
3. A new scenario that belongs to the full set goes into `core/test-cases/device-supplier.json` as well; then run the creator again for `core`.

`random-order` additionally has `"flexibleOrder": true` in its `group.json`. The creator has no prompt for this field; it keeps the value when the group is updated.

## Running Tests

Tests are executed by the **CTT Runner**. The steps, including the identity setup, are in `docs/device-supplier-setup-guide.md`.

```bash
bash ctt-runner/ctt-start.sh
# 2 (Device Supplier) → 1. Setup Identity (once) → 2. Start Mock WFM Server → 3. Run Tests → choose a group
```

Or, once the identity is set up, one group without the menu:

```bash
bash ctt-runner/ctt-start.sh device quick-check
```

## Useful Flags of the Device Client

The menu builds `ctt-runner/device-supplier/bin/run_tests` and runs it. To repeat one scenario or step while the mock WFM is running:

```bash
cd ctt-runner/device-supplier
./bin/run_tests -file ../../test-suites/device-supplier/core/test-cases/device-supplier.json \
  -url https://localhost:3003/v1alpha2/margo -scenario scenario-capabilities
```

| Flag | Description |
|---|---|
| `-file` | Path to the test-case JSON file |
| `-url`, `-miaf-url` | Base URL of the mock WFM's Management Interface (mTLS, port 3003) |
| `-scenario`, `-step` | Run only the scenario / step with this ID |
| `-flexible-order` | Randomise scenario execution order |
| `-verbose` | Print the full response body and headers for every step |
