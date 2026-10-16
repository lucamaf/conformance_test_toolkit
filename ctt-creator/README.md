# CTT Creator

The CTT Creator is responsible for **authoring and managing test groups** for each Margo persona. It reads the test-case files in a folder and writes the `group.json` that the CTT Runner uses to run them.

## Structure

```
ctt-creator/
├── ctt-start.sh      # Entry point — launches the interactive test group CLI
├── device-supplier/  # Dev guide for the Device Supplier persona
├── wfm-supplier/     # Dev guide, and the Postman collection generated from the OpenAPI file
└── app-supplier/     # Dev guide for the Application Supplier persona
```

## Quick Start

```bash
bash ctt-creator/ctt-start.sh
```

1. Select the persona: WFM Supplier or Device Supplier. For WFM Supplier, then choose *2. Functional tests*.
2. Enter `0` to create a group, or the number of an existing group to update it.
3. Enter the group name, the Margo specification version (Enter = `1.0.0-rc.3`) and a short description.
4. Enter the folder that holds the test-case files, for example `test-suites/wfm-supplier/quick-check/test-cases`.

The CLI writes `test-suites/<persona>/<group>/group.json` with the name, version, description, the folder, and the ID of every scenario, step or Postman request found in that folder. The group then appears in the CTT Runner's group list with its description.

A group contains every test in its folder. To make a group with fewer tests, put only those test cases in the group's own `test-cases` folder.

The test-case formats are described in [`docs/margo-conformance-approach.md`](../docs/margo-conformance-approach.md).

## Personas

| Persona | Dev Guide |
|---|---|
| Device Supplier | [device-supplier/dev-guide/README.md](device-supplier/dev-guide/README.md) |
| WFM Supplier | [wfm-supplier/dev-guide/README.md](wfm-supplier/dev-guide/README.md) |
| Application Supplier | [app-supplier/dev-guide/README.md](app-supplier/dev-guide/README.md) — no groups: a package is a folder under `test-suites/app-supplier/` |
