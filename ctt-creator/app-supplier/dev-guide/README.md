# CTT Creator — Application Supplier Dev Guide

## Overview

The **Application Supplier** persona verifies that a Margo application package conforms to the Margo Application Description specification. There is no network exchange: the CTT Runner reads a package folder and checks its `margo.yaml` and the resources it refers to.

## Directory Layout

```
test-suites/app-supplier/
└── app-package/             # A package folder: one entry in the runner's list
    ├── margo.yaml           # Application description file (the artifact under test)
    └── resources/           # Resources referenced by margo.yaml

ctt-runner/app-supplier/scripts/   # The validator (Go)
ctt-runner/reports/application-supplier/   # Generated HTML reports
```

## Key Concepts

| Term | Meaning |
|---|---|
| **margo.yaml** | The application description file. This is the primary artifact the Application Supplier persona validates. |
| **Application Package** | A folder containing `margo.yaml` and the resources it refers to. |
| **CTT Runner (App Supplier)** | A Go program (`ctt-runner/app-supplier/scripts/`) that reads a package folder and validates `margo.yaml` against the spec. |
| **MARGO-APP-APPLICATIONDESCRIPTION-\*** | Requirement IDs for the Application Description spec. |

## Adding a Package

Copy the package folder into `test-suites/app-supplier/`:

```
test-suites/app-supplier/<your-package>/
├── margo.yaml
└── resources/
    ├── description.md
    ├── license.txt
    ├── release-notes.md
    └── <icon>.png
```

This persona has no test groups and is not in the CTT Creator menu: every folder under `test-suites/app-supplier/` is listed by the runner.

## Running Tests

```bash
bash ctt-runner/ctt-start.sh
# 3 (Application Supplier) → select the package
```

Or directly:

```bash
cd ctt-runner/app-supplier/scripts
go run . ../../../test-suites/app-supplier/<your-package>
```

The report is written to `ctt-runner/reports/application-supplier/`.

## Key Requirement IDs

| CR ID | Area |
|---|---|
| `MARGO-APP-APPLICATIONDESCRIPTION-001` | margo.yaml must be present in the package |
| `MARGO-APP-APPLICATIONDESCRIPTION-002` | margo.yaml must conform to the application description schema |
| `MARGO-WFM-APPLICATIONDESCRIPTION-001/002` | WFM must serve packages with correct OCI media types |
