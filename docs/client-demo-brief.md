# Margo Conformance Test Toolkit — Summary

Margo defines how a **device** and a **WFM** (Workload Fleet Manager, the cloud/control-plane side) talk to each other over HTTPS. This toolkit lets a vendor who built *either side* prove their implementation follows that spec — without needing the other side's real system. We provide a correct stand-in, run real HTTP calls against it, and hand back a pass/fail report. The spec baseline is Margo `1.0.0-rc.3`: every call is made over mutual TLS with X.509-SVID identities (MIAF).

## Two CLIs

- **`ctt-creator/ctt-start.sh`** — Authoring. Takes a folder of test cases (scenario files, or a Postman collection for the WFM persona) and creates a named test group from it.
- **`ctt-runner/ctt-start.sh`** — Execution. Sets up the identity, picks a group, fires the actual HTTP calls at the system under test, and produces the HTML report.

## Three personas

- **Device Supplier** — vendor brings a real device; we provide a mock WFM to test it against.
- **WFM Supplier** — vendor brings a real WFM; we provide a device client that fires test calls at it.
- **Application Supplier** — validates that an application package is correctly structured per spec.

## Test groups

A group is a named set of tests with a spec version. A vendor picks one name instead of choosing tests: `quick-check` to confirm the setup, a themed group (`identity`, `management-interface`, ...) while developing, and `core` for the full conformance result. The report carries the group name and version, so two vendors' results are comparable.

## Why it holds up

Tests trace directly to the spec requirements, cover both success and deliberately-broken cases (identity that must be refused, wrong digest, invalid values, etc.), and every report row is a real request/response — expected vs. actual, side by side.
