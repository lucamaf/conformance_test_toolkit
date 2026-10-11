# Device Supplier — requirements and the tests that judge them

The device group `core` judges a real device from the requests it sends to the mock WFM. This page lists, for every requirement of the Device Supplier persona, the step of `core` that is the evidence for it, and says which requirements are not judged and why. It is generated from `test-suites/device-supplier/core/test-cases/device-supplier.json`; requirement texts are from the Margo conformance requirement list.

Every test step of `core` lists at least one requirement ID. Steps named "The device is connected to the mock WFM" and "Mock WFM: ..." are not tests: they find the device and change the desired state.

## Requirements judged on the device (28)

| Requirement | Text | Steps of `core` |
|---|---|---|
| `APPLICATIONDESCRIPTION-001` | MUST — After deployment, the device MUST provide the specified amount of memory for the application. | `rd-02-capabilities-resources` |
| `APPLICATIONDESCRIPTION-002` | MUST — After deployment, the device MUST provide the specified amount of storage for the application. | `rd-02-capabilities-resources` |
| `APPLICATIONDESCRIPTION-003` | MUST — After deployment, the device MUST provide the specified number of CPU cores for the application. | `rd-02-capabilities-resources` |
| `DEPLOYMENT-002` | MUST — All current device roles MUST meet the listed requirements to be considered Margo compliant. | `rd-02-capabilities-deployment-type` |
| `DEPLOYMENT-003` | MUST — All devices MUST provide a workload fleet management client. | `rd-01-identity-accepted` |
| `DEPLOYMENT-004` | MUST — All devices MUST provide an OCI container runtime. | `rd-02-capabilities-runtime` |
| `DEPLOYMENT-005` | MUST — All devices MUST provide an OTEL collector. | `rd-02-capabilities-otel` |
| `DEPLOYMENT-006` | MUST — Devices filling the standalone cluster role MUST provide a Kubernetes orchestration platform. | `rd-02-capabilities-role-cluster` |
| `DEPLOYMENT-007` | MUST — Devices filling the standalone cluster role MUST provide capabilities for deploying Helm charts. | `rd-02-capabilities-role-cluster` |
| `DEPLOYMENT-008` | MUST — Devices filling the standalone device role MUST provide Compose-compliant software as the orchestration platform. | `rd-02-capabilities-role-device` |
| `DEPLOYMENT-009` | MUST — Devices filling the standalone device role MUST provide capabilities for deploying Compose applications. | `rd-02-capabilities-role-device` |
| `MANAGEMENTINTERFACE-004` | MUST — All client certificates MUST conform to RFC 5280 standards. | `rd-01-identity-svid-profile` |
| `MANAGEMENTINTERFACE-005` | MUST — Both the WFM and Device client MUST utilize X.509 certificates to represent themselves within API interactions. | `rd-01-identity-accepted` |
| `MANAGEMENTINTERFACE-006` | MUST — Clients MUST verify computed digests match manifest values; any mismatch MUST abort update and preserve previous state. | `rd-07-bundle-content-rejected`, `rd-08-deployment-content-rejected` |
| `MANAGEMENTINTERFACE-007` | MUST — For every change in deployment state, the client MUST report the corresponding status to the WFM using the Deployment Status API. | `rd-03-desired-state-status`, `rd-04-deployment-lifecycle-status`, `rd-04-deployment-lifecycle-removed` |
| `MANAGEMENTINTERFACE-008` | MUST — If a manifest references an unsupported digest algorithm, the client MUST treat the manifest as invalid and abort processing. | `rd-06-digest-algorithm-rejected`, `rd-06-digest-algorithm-no-fetch`, `rd-06-digest-algorithm-state-kept` |
| `MANAGEMENTINTERFACE-009` | MUST — If any digest validation fails, the client MUST abort the update and retain the previous state. | `rd-07-bundle-content-rejected`, `rd-07-bundle-content-state-kept`, `rd-08-deployment-content-state-kept` |
| `MANAGEMENTINTERFACE-010` | MUST — If manifestVersion is not strictly greater than stored, the update MUST be rejected. | `rd-05-manifest-version-rejected`, `rd-05-manifest-version-state-kept` |
| `MANAGEMENTINTERFACE-015` | MUST — Once reconciliation succeeds, the client MUST durably persist the new manifestVersion and associated ETag. | `rd-03-desired-state-etag`, `rd-05-manifest-version-state-kept`, `rd-06-digest-algorithm-state-kept`, `rd-07-bundle-content-state-kept`, `rd-08-deployment-content-state-kept`, `rd-11-restart-etag` |
| `MANAGEMENTINTERFACE-016` | MUST — The Device supplier, via its WFM Client, MUST implement the client side of the API specification contract. | `rd-02-capabilities-accepted`, `rd-03-desired-state-read`, `rd-03-desired-state-fetch`, `rd-03-desired-state-status`, `rd-04-deployment-lifecycle-read` |
| `MANAGEMENTINTERFACE-017` | MUST — The client MUST persist both the last accepted manifestVersion and ETag to prevent rollback across restarts. | `rd-11-restart-etag`, `rd-11-restart-rollback` |
| `MANAGEMENTINTERFACE-018` | MUST — The client MUST trust the WFM's server certificate through a pre-provisioned or securely obtained root CA. | `rd-10-wfm-trust-refused`, `rd-10-wfm-trust-resumed` |
| `MANAGEMENTINTERFACE-019` | MUST — The client MUST verify the digest of every fetched artifact before use. | `rd-03-desired-state-fetch`, `rd-07-bundle-content-rejected`, `rd-08-deployment-content-rejected` |
| `MANAGEMENTINTERFACE-025` | MUST NOT — bundle.sizeBytes MUST NOT be used for integrity verification. | `rd-09-size-bytes-accepted` |
| `MANAGEMENTINTERFACE-026` | MUST NOT — deployments[].sizeBytes MUST NOT be used for integrity verification. | `rd-09-size-bytes-accepted` |
| `OBSERVABILITY-006` | MUST — End users MUST be able to export observability data from a device or cluster to collectors/backends. | `rd-13-observability-otlp`, `rd-13-observability-remote-write` |
| `OBSERVABILITY-010` | MUST — For standalone and clustered devices there MUST be at least one OpenTelemetry collector deployed. | `rd-13-observability-otlp` |
| `OBSERVABILITY-023` | MUST — The device owner MUST deploy and configure an OpenTelemetry collector on their device. | `rd-13-observability-otlp` |

Notes:

- `APPLICATIONDESCRIPTION-001` to `-003` are judged by what the device declares in its capabilities (memory, storage, CPUs), not by measuring a running application.
- `DEPLOYMENT-006`/`-007` (standalone cluster) and `DEPLOYMENT-008`/`-009` (standalone device) are judged for the role the device declares; the steps of the other role are reported as SKIP "not applicable".
- `MANAGEMENTINTERFACE-017` and the restart part of `-015` are judged when the operator restarts the device during the run; otherwise NOT RUN.
- `MANAGEMENTINTERFACE-006`/`-009`/`-019` with tampered content are judged only if the device downloaded that content; a device that used the bundle is not judged on the single deployment file, and the other way round.
- `OBSERVABILITY-006`/`-010`/`-023` are judged when the device's collector is pointed at the CTT; otherwise NOT RUN.

## Requirements the suite adds (6)

These points of Margo 1.0.0-rc.3 and MIAF have no ID in the published requirement list. The suite gives them its own IDs so that every test maps to a requirement.

| Requirement | Text | Source | Steps of `core` |
|---|---|---|---|
| `MANAGEMENTINTERFACE-MIAF-001` | The device presents a valid X.509-SVID in the mTLS handshake and the WFM accepts it. | MIAF: WFM identity profile | `rd-01-identity-accepted` |
| `MANAGEMENTINTERFACE-MIAF-002` | The device refuses a WFM whose certificate was not issued by the MIS of its trust domain. | MIAF: SVID validation by the WFM Client | `rd-10-wfm-trust-refused` |
| `MANAGEMENTINTERFACE-MIAF-003` | After its SVID is replaced by a re-issued one for the same SPIFFE ID, the device continues without registering again. | MIAF: identity lifecycle, renewal | `rd-12-svid-rotation-accepted` |
| `MANAGEMENTINTERFACE-MIAF-004` | The device's SVID is a leaf certificate with exactly one URI SAN. | MIAF: SVID profile | `rd-01-identity-svid-profile` |
| `MANAGEMENTINTERFACE-RC3-001` | Capabilities are reported with PUT /api/v1/capabilities/{deviceId}, and the deviceId of the path is the ID in the report. | Management Interface 1.0.0-rc.3: device capabilities | `rd-02-capabilities-device-id` |
| `MANAGEMENTINTERFACE-RC3-002` | Every status report carries adoptedManifestVersion, the manifest version the device has adopted. | Management Interface 1.0.0-rc.3: deployment status | `rd-03-desired-state-status`, `rd-04-deployment-lifecycle-status` |

## Requirements not judged (30)

| Requirement | Text | Why |
|---|---|---|
| `APPLICATIONDESCRIPTION-004` | MUST — If compose component wait is True, the device MUST wait until the compose file has finished starting before starting the next. | Needs a real installation of a multi-component Compose package to see the order; not automated. |
| `APPLICATIONDESCRIPTION-005` | MUST — If helm component wait is True, the device MUST wait for helm chart to finish installing before installing the next. | Needs a real installation of a multi-component Helm package to see the order; not automated. |
| `DEPLOYMENT-001` | MUST — A device MUST support onboarding and management from only a single workload fleet manager. | Would need a second WFM to try to manage the device; not automated. |
| `MANAGEMENTINTERFACE-027` | PREFERRED — Running the device's management client as containerized services is preferred (not required). | A preference, and not visible in the requests a device sends. |
| `MANAGEMENTINTERFACE-028` | SHOULD — If manifestVersion is not strictly greater, the event SHOULD be logged as a security event (logging specifics TBD). | Logging inside the device; not visible in the requests a device sends. |
| `OBSERVABILITY-001` to `-028` except `-006`, `-010`, `-023` (25) | Deployment model, receivers and processors of the collector, and what data it collects | The CTT sees that telemetry arrives; how the collector is deployed and configured on the device is not visible from outside. |

## Requirements that no longer apply in 1.0.0-rc.3 (12)

They describe HTTP Message Signatures and the certificate API of the onboarding flow, which MIAF (mTLS with X.509-SVIDs) replaced.

| Requirement | Text |
|---|---|
| `MANAGEMENTINTERFACE-001` | MAY — Additional signature algorithms MAY be supported. |
| `MANAGEMENTINTERFACE-002` | MAY — Clients MAY choose any of the required algorithms that fits their hardware capabilities. |
| `MANAGEMENTINTERFACE-003` | MAY — The Certificate API MAY be used to retrieve the root CA over an already trusted channel. |
| `MANAGEMENTINTERFACE-011` | MUST — Implementations MUST support allowable signature algorithm: ecdsa-p256-sha256. |
| `MANAGEMENTINTERFACE-012` | MUST — Implementations MUST support allowable signature algorithm: ecdsa-p384-sha384. |
| `MANAGEMENTINTERFACE-013` | MUST — Implementations MUST support allowable signature algorithm: rsa-pss-sha256. |
| `MANAGEMENTINTERFACE-014` | MUST — Implementations MUST support allowable signature algorithm: rsa-v1_5-sha256. |
| `MANAGEMENTINTERFACE-020` | MUST — The device management client MUST Base64-encode the digest and include it in the Content-Digest header. |
| `MANAGEMENTINTERFACE-021` | MUST — The device management client MUST create a Signature Base String including @method, @target-uri, and Content-Digest. |
| `MANAGEMENTINTERFACE-022` | MUST — The device management client MUST generate a SHA256 digest of the HTTP request body. |
| `MANAGEMENTINTERFACE-023` | MUST — The device management client MUST generate the Signature header by signing the Signature Base String using the client's X.509 private key. |
| `MANAGEMENTINTERFACE-024` | MUST — The device management client MUST insert Content-Digest, Signature-Input, and Signature headers in the HTTP/1.1 request. |
