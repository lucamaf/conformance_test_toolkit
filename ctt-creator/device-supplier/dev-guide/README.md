# CTT Creator — Device Supplier Dev Guide

## Overview

The **Device Supplier** persona verifies that a Margo device (its WFM Client) conforms to the Margo specification. The CTT runs a mock WFM server that the device, or the CTT's own device client, sends its requests to. This guide is for people who write or change the device test cases and groups.

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
├── scripts/cmd/device-supplier/ # The mock WFM server the device under test connects to
└── utils/manifests/             # assertions.json, deployment templates
```

## Key Concepts

| Term | Meaning |
|---|---|
| **Test Group** | A named list of test IDs (for example the groups `core`, `quick-check`, `manifest-integrity`), with the spec version it targets. Each group has a `group.json`, written by `ctt-creator`. |
| **group.json** | Describes a test group: its name, version, persona, description, the folder with its test-case files, and the scenario and step IDs to run. |
| **Test Case JSON** | Declarative scenario file (`test-suites/device-supplier/<group>/test-cases/*.json`) read by the CTT Runner. The format is in `docs/margo-conformance-approach.md`, section "Margo schema for server-side test-cases". |
| **MIAF / SVID** | The mTLS identity mechanism. The mock WFM holds a WFM SVID (`spiffe://<trust-domain>/margo/wfm/<wfm-id>`); the device presents a client SVID (`spiffe://<trust-domain>/margo/wfm/<wfm-id>/client/<wfm-client-id>`). Both are issued by the MIS. |
| **Negative Fixture** | A test-control mechanism of the mock WFM that makes it serve a manifest a device must reject (wrong digest, unsupported algorithm, version not increasing), so the device's rejection logic can be tested. |
| **manifestVersion** | A monotonically increasing counter the WFM increments each time the desired state changes. Used by the device to detect updates via `If-None-Match`. |

## Test Groups

| Group | Purpose |
|---|---|
| `core` | Real device — the conformance result: observation steps (`"observe"`) that judge the requests a real device sends to the mock WFM |
| `management-interface`, `manifest-integrity`, `identity`, `observability` | Real device — the scenarios of `core` for one area |
| `self-check` | No device — the CTT's own device client against the mock WFM: every API call, its errors, the negative fixtures. Run it after changing `assertions.json` or the mock WFM |
| `quick-check` | No device — capabilities, manifest, deployment, bundle, status: first check of the setup |
| `random-order` | No device — the self-check lifecycle scenarios in random order (`"flexibleOrder": true` in `group.json`) |

The mock WFM decides what is valid: it loads `ctt-runner/device-supplier/utils/manifests/assertions.json` when it starts. `endpoints` holds the rules of the rc.3 API (a request that breaks one is answered 422); `device_expectations` holds what a Margo device must declare beyond the API schema (the request is accepted, the verdict of each rule is recorded with it). The steps of `core` read those verdicts; they contain no rules of their own.

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
3. A new real-device scenario that belongs to the conformance set goes into `core/test-cases/device-supplier.json` as well; a new self-run scenario goes into `self-check/test-cases/self-check.json`. Then run the creator again for that group.

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
  -url https://localhost:3003/v1alpha2/margo -scenario rd-02-capabilities
```

| Flag | Description |
|---|---|
| `-file` | Path to the test-case JSON file |
| `-url`, `-miaf-url` | Base URL of the mock WFM's Management Interface (mTLS, port 3003) |
| `-scenario`, `-step` | Run only the scenario / step with this ID |
| `-flexible-order` | Randomise scenario execution order |
| `-verbose` | Print the full response body and headers for every step |
