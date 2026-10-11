# Margo Conformance Framework

## Objective

The Margo conformance Framework shall be a downloadable Conformance Test Toolkit (CTT) which shall allow Margo adopters to test their Margo conformant component(s) against a specific version of the Margo Specification and generate a Conformance Report. 

The conformance toolkit shall allow the Margo adopter to choose a specific, pre-defined collection of tests, available in the Margo Specifications, for generating the Conformance Report.

This report may be used as evidence of conformance to Margo specifications.

## Key requirements for the Conformance Framework

- The Conformance Tests shall be built as Persona Specific Suites

- The Conformance Tests shall be mapped directly to one or more requirements (having CR-IDs) defined in the Margo specifications, 

- The Conformance Test shall be easy to develop using a well-known / easy to use tool or representation

- It should be possible to select a pre-defined grouping or collection of tests (Test-Suite)

- The Conformance Framework shall be capable of running the tests in an 'on-premise' Linux host

- The Conformance Framework shall record the date/time, version of MARGO specification and the version of the tested component in the test report and sign it with a Digital Signature

- The Conformance Framework shall provide the pass / fail status for each test in the test report along with trace links and evidence references

- The conformance framework may collect the OTEL traces and telemetry as evidence of the test

- The conformance framework may allow upload of test-results to a Margo hosted registry.

## Exclusions from the scope of the Conformance Framework

- The function of the Conformance Framework is to validate ONLY conformance against the Margo specification, hence the Conformance Framework will not validate usability or other aspects of the Margo adopter’s component.

- The Conformance Framework will not be a hosted service provided by Margo.

- The Conformance Framework will not include the Centralized Margo hosted Registry for Supplier Conformance Reports, this will be an independent service.

- The Conformance Framework is not intended to be used in the production deployment environment to classify a workload or device as Margo conformant.

- The Conformance Framework will not validate requirements which cannot be expressed as a series of API exchanges or with checks  (value or regex format) on the content of the API exchange. For example – performance, load e.t.c.

- Platform Supplier Persona is currently in the process of being defined in Margo specification, hence not supported in the initial scope of the Conformance Framework.

## Working with the Conformance Framework 

### High Level Use-Case

- The Conformance Framework shall allow the Margo Development team & Specification authors (SUP Authors and Test-Case Developers) to create Test-Cases from the Margo OpenAPI specification as well as functional requirements from the Margo Conformance Requirements. 

- The Specification Author shall write test-cases in a prescribed format, or generate the test-cases from the OpenAPI specification.

- Test-cases can be grouped into one or more Test-Suites. 

- A Test-Suite can have test-cases corresponding to only a single persona.

- In the Conformance Test Toolkit a Test-Suite is called a **group**. A group is a named list of test IDs with a specification version: its `group.json` holds the name, version, description, the folder where the test files live, and the IDs of the scenarios, steps or Postman requests to run. The Specification Author puts the test-case files in a folder and creates the group with `ctt-creator`; the Vendor selects the group by name in `ctt-runner`, and the Conformance Report carries the group name and version. The groups shipped with the toolkit and the reasons for grouping are described in `docs/ARCHITECTURE.md`, section "The Test Data Model".

```mermaid
flowchart LR
    Author[SUP Creator / Specification Author]
    OpenAPI[Conformance Specification: OpenAPI]
    Functional[Conformance Specification: Functional Requirements]
    Contract[Conformance Framework Task: Create API Contract Tests]
    Context[Conformance Framework Task: Functional and Context specific tests]
    Suite[Conformance Test-Suite: Test cases, Persona Specific]

    Vendor[Vendor / Tester, Persona Specific]
    Clone[Clone Conformance Repo]
    Build[Build Conformance Framework for Persona: App / WFM / Device Supplier]

    subgraph Framework[Conformance Framework]
      Env[Create Test Environment]
      Configure[Request configuration for System Under Test: WFM / Device]
      Select[Request Conformance Suite to Run]
      Execute[Execute Tests, Validate Assertions and collect logs]
      Report[Generate Report and sign with MARGO Digital Signature]
      Env --> Configure --> Select --> Execute --> Report
    end

    ConformanceReport[Conformance Report]

    Author --> OpenAPI
    Author --> Functional
    OpenAPI -->|Generate| Contract
    Functional -->|Manually Create| Context
    Contract --> Suite
    Context --> Suite
    Vendor --> Clone --> Build --> Framework
    Suite --> Execute
    Report --> ConformanceReport
```


*Figure 1 : Top-Level use-case for the Conformance Framework*

### Supplier Personas

- The Margo architecture defines different Suppliers as Personas.

- Conformance test-cases will be persona specific.

- Each persona will have a unique test-configuration consisting of several ‘Elements’.

- The following Supplier Personas are identified by Margo – 

- Application Supplier.

- Workload Fleet Manager (WFM) Supplier.

- Device Supplier.

- Note: Platform Supplier Persona is currently not clearly defined in scope

### Persona Specific Use-Cases

- The Conformance Frameworks will have different components (Elements) as required for the testing of a specific persona.

- The role of a Margo Element may change from persona to persona, for example – For testing conformance for a WFM Supplier, the Device shall act as a simulated Client Element, however for testing conformance for a Device Supplier, the Device shall be real and the WFM will be a simulated Server Element.

<table>
<tr>
<th>
- **Supplier Persona**
</th>
<th>
- **Conformance Framework ****Simulated ****Elements**
</th>
<th>
- **Real Element from Supplier**
</th>
</tr>
<tr>
<td>
- App Supplier
</td>
<td>
- App Container Registry, OCI Component Registry &amp; App Registry<br>- WFM <br>- WFM Client<br>- OTEL Telemetry Collector
</td>
<td>
- Application container images and Margo Manifest
</td>
</tr>
<tr>
<td>
- WFM Supplier
</td>
<td>
- App Container Registry, OCI Component Registry &amp; App Registry<br>- Margo Manifest<br>- WFM Client &amp; OTEL Telemetry 
</td>
<td>
- WFM with OTEL Server and<br>- (Optional) OCI Registry
</td>
</tr>
<tr>
<td>
- Device Supplier
</td>
<td>
- WFM<br>- App Container Registry, OCI Component Registry &amp; App Registry<br>- OTEL Telemetry  Server
</td>
<td>
- Device with Margo WFM Client and OTEL Telemetry Client
</td>
</tr>
</table>

## Framework Design

- The Conformance Framework will be provided as a set of docker images and a Docker-Compose file, the Supplier can also clone the Margo Github repository and build the docker images.

- Note: Further design details will evolve as we progress.

- Key elements of the Conformance Framework are mentioned in [Figure 1]

- These include – 

- **A ****common ****format**** (schema)** for generating or manually writing conformance test-cases.

- **A test-configurator** that brings up the persona specific elements.

- **A test****-runner** or engine that can read test-cases from a collection (test-suite) and execute the test-cases and record the result

- **A test-report format** that provides the results of the tests, the reason for failures

- **A test-report generator** that reads log files and generates the test-report.

- The Framework will need to cater to different configurations of ‘Elements’ for each Persona as mentioned above.

- Additionally, the Supplier can have a “Server” or a “Client” component as defined in the Margo System Design. This needs to be accommodated in the Conformance Framework, which needs to serve as the peer element and allow the Margo Community to create test-cases for each perspective. This is explained in the following sections.

- The Framework shall attempt to re-use existing open-source frameworks like Portman for generating API Contract Tests. The generated tests are executed by the runner of the Conformance Test Toolkit, which sends them over mutual TLS. These tools are selected from a range of available tools for writing “Client-Side” tests for API contracts with a high degree of automation. There is a table of alternative tools also discussed in the Appendix section.

- The Framework shall provide a format / schema for manually writing “Server-Side” test-cases (where the Margo Supplier is providing the “Client-Side” component, for example the Device) as there is a lack of available tooling for verifying Client API conformance. The format / schema is discussed in the following sections.

## Creating Conformance Test-Cases

### Types of Conformance tests

- API Contract tests – Tests which check for compliance against Margo OpenAPI Specification

- Functional & Context specific tests – Tests which check for compliance against functional aspects of the Margo Specification, which includes sequence of API calls, specific attributes whose values should be re-used in subsequent API exchanges.

### Client and Server Perspectives for tests

- Client Perspective – When the Supplier Persona has a component that acts as a OpenAPI ‘Client’ and the Conformance Framework components act as Servers. These test-cases require the Conformance Framework to validate the incoming API Request from the Supplier component, validate the Request and respond with the pre-defined Response.

- Server Perspective – When the Supplier Persona has a component that acts as a OpenAPI ‘Server’ and the Conformance Framework components act as a Client. These test-cases require the Conformance Framework to send an API Request to the Supplier component, and validate the response.

```mermaid
flowchart LR
    Author[SUP Creator / Specification Author]

    subgraph Client[Supplier Persona: component under test acts as an OpenAPI Server; tests written from client perspective]
      OA1[OpenAPI]
      FR1[Functional Requirements]
      Portman[Portman]
      Postman[Postman]
      ACT1[Create API Contract Tests]
      FCT1[Functional and Context specific tests]
      OA1 -->|Generate| Portman --> ACT1
      FR1 -->|Manually Create| Postman --> FCT1
    end

    subgraph Server[Supplier Persona: component under test acts as an OpenAPI Client; tests written from server perspective]
      OA2[OpenAPI]
      FR2[Functional Requirements]
      Format[Margo format]
      ACT2[Create API Contract Tests]
      FCT2[Functional and Context specific tests]
      OA2 -->|Manually Create| Format --> ACT2
      FR2 -->|Manually Create| Format --> FCT2
    end

    Suite[Conformance Test-Suite: Test cases, Persona Specific]
    Author --> OA1
    Author --> FR1
    Author --> OA2
    Author --> FR2
    ACT1 --> Suite
    FCT1 --> Suite
    ACT2 --> Suite
    FCT2 --> Suite
```


*Figure 2 : Creating Conformance Test-Cases and adding to Test-Suite*

### API Contract Tests : Test-case generation from Margo OpenAPI Specification

- Conformance test-cases, which directly draw from API contracts defined in the OpenAPI specification, can be generated using open-source tools like Portman

- _For the __WFM__ __Supplier persona_, the Margo conformance test-cases will mostly consist of test-cases written from the ‘Client’ perspective with the WFM as the system under test, as specified from the Margo OpenAPI based specification.

- The Margo Conformance Framework shall allow import of API Contract tests, generated using tools like Portman. The Conformance Test Toolkit executes them with its own runner (`ctt-runner` → WFM Supplier → OpenAPI spec based contract tests), because every request has to be sent over mutual TLS with the X.509-SVID of the toolkit.

- This will allow the addition of specific, tailored, hand-written test-cases written using Postman, to be added the Conformance Suite.

- _For the __Device Supplier persona_, the  Margo conformance test-cases will mostly consist of test-cases written from the ‘Server’ perspective with the Device as the system under test, as specified from the Margo OpenAPI based specification.

- The Margo Conformance Framework will define a format (JSON Schema) to write tailored, hand-written test-cases which can evaluate the conformance of the Device’s WFM Client to the Margo OpenAPI specification.

- Note : It may be possible to generate these test-cases from the Margo specification using LLMs, but this is not part of the initial scope.

- _For the App Supplier persona_, the  Margo conformance test-cases will mostly validate the Margo Application Description against the Margo specification. This shall be done using a JSON Schema based validation, however there may be test-cases which require access to the App Supplier’s artefacts, which can be written as ‘Client’ side test-cases in Postman.

#### Automated Client-Side test-case generation for API Contracts using Portman

Portman requires the OpenAPI YAML file as input and then generates tests as PostMan collections. The mechanism will be enabled by the Conformance Framework scripting & tooling with necessary documentation.

Postman allows a variety of validations and assertions; these are documented in Postman user-guide. 

#### Manual Server-Side test-case writing for API Contract tests

These tests require a specific schema, which will be defined as part of the Conformance Framework, to be followed while writing the test-cases. The schema follows the patter of Client side tests written in Postman, but does not include JavaScript based validation hooks. Instead, there will be specific validation an assertion elements that can be added in the test-case. 

Further details are described below in the section [Margo schema for server-side test-cases].

### Functional & Context specific tests 

- This class of Conformance test-cases require the ability to check functional requirements which check if :

- The APIs are in an intended sequence as defined by the Margo specification

- Or, a matching rule is applied between fields of an API sequence. For example – the encoding of the API Header is as per the rules defined in the Margo API specification

- Or, a matching value is used in a subsequent API call. For example – The Device reports the status of a deployment with the `deploymentId` and the `manifestVersion` it received in the desired-state manifest

- Or, other cases as defined below.

Note : Further details are described below in the section [Margo schema for server-side test-cases].

- These test-cases need to be manually written using Postman for Client-side test-cases, but the Conformance Framework needs to provide a format / schema to write Server-side test-cases

#### Postman Template for Expressing sequences of API exchanges, Client-Side test-cases

- Postman allows API sequences as well as validations and assertions

- The schema is provided here – [https://schema.postman.com/collection/json/v2.1.0/draft-07/docs/index.html]

- Write the requests in Postman, export the collection (v2.1), place the file in a folder and create a group from it with `ctt-creator`. `ctt-runner` then runs that group against the Workload Fleet Manager. Every request is sent over mutual TLS with the X.509-SVID set up in the CTT (Margo 1.0.0-rc.3).

- A working example is `test-suites/wfm-supplier/postman-lifecycle/test-cases/postman_collection.json` (positive cases) and `test-suites/wfm-supplier/postman-error-handling/test-cases/postman_collection.json` (negative cases).

- How the Conformance Framework reads a collection:

<table>
<tr>
<th>
**In the Postman collection**
</th>
<th>
**What the Conformance Framework does**
</th>
</tr>
<tr>
<td>
Order of the requests, folders
</td>
<td>
Requests run top to bottom. Folders are opened in place. The whole collection is one scenario.
</td>
</tr>
<tr>
<td>
`{{baseUrl}}`
</td>
<td>
Replaced by the WFM URL entered in `ctt-runner`.
</td>
</tr>
<tr>
<td>
`{{name}}` in the URL, a header or the body; `:name` in the path
</td>
<td>
Replaced by the variable `name`. Its starting value is the collection variable of that name. A literal typed in the Path Variables table is not used.
</td>
</tr>
<tr>
<td>
`GET /api/v1/deployments`
</td>
<td>
After a successful response these variables are set for the following requests: `deploymentId`, `deploymentDigest`, `bundleDigest`, `manifestVersion`, `manifestEtag`.
</td>
</tr>
<tr>
<td>
Request `id`
</td>
<td>
The test ID listed in `group.json` and shown in the report. When a request has no `id`, its name is used in lower case with `\_` for spaces.
</td>
</tr>
<tr>
<td>
Expected status
</td>
<td>
The status code of the saved example. Without a saved example: the status in the test script (`pm.response.to.have.status(200)` or `pm.expect(\[200, 201]).to.include(pm.response.code)`), otherwise 200.
</td>
</tr>
<tr>
<td>
Test scripts
</td>
<td>
Not executed. Add the checks in the `validations` field (see below).
</td>
</tr>
<tr>
<td>
Requirement IDs
</td>
<td>
Every ID written in the request name or description (for example `MARGO-WFM-MANAGEMENTINTERFACE-030`) is shown next to the test in the report.
</td>
</tr>
</table>

*Table : How a Postman collection is read*

- These fields can be added to a request in the exported JSON file. They are written exactly as in the Margo schema described below.

<table>
<tr>
<th>
**Field**
</th>
<th>
**Purpose**
</th>
</tr>
<tr>
<td>
`crIds`
</td>
<td>
Requirement IDs for the report, when they are not written in the name or description
</td>
</tr>
<tr>
<td>
`expected\_status`
</td>
<td>
Expected HTTP status code
</td>
</tr>
<tr>
<td>
`accepted\_statuses`
</td>
<td>
Other status codes that also pass, for example `\[200]` for a request that expects 201
</td>
</tr>
<tr>
<td>
`validations`
</td>
<td>
Checks on the response body and headers
</td>
</tr>
<tr>
<td>
`extract\_context`
</td>
<td>
Save response values as variables for later requests
</td>
</tr>
</table>

*Table : Margo fields in a Postman request*

```json
{
  "id": "8ac42a20-2df5-4833-bcae-3b3c28946784",
  "name": "GET Deployments — If-None-Match returns 304 Not Modified",
  "request": {
    "method": "GET",
    "url": { "raw": "{{baseUrl}}/api/v1/deployments", "host": ["{{baseUrl}}"], "path": ["api", "v1", "deployments"] },
    "header": [
      { "key": "Accept", "value": "application/vnd.margo.manifest.v1+json" },
      { "key": "If-None-Match", "value": "{{manifestEtag}}" }
    ]
  },
  "crIds": ["MARGO-WFM-MANAGEMENTINTERFACE-030"],
  "expected_status": 304
}
```

- A collection generated from the OpenAPI file (`ctt-creator` → WFM Supplier → OpenAPI spec based contract tests) describes each endpoint once, with several saved responses. For such a collection the Conformance Framework sends its own valid request for each endpoint, runs the endpoints in device order (capabilities, deployments, deployment, bundle, status, unregister) and turns every saved response into one check. A response that a client cannot provoke (for example 403 by WFM policy) is reported as NOT RUN.

#### Margo template for Expressing sequence of API exchanges , Server side test-cases

See the section below [Margo schema for server-side test-cases].

## Margo schema for server-side test-cases

- The test-cases are a collection of one or more scenarios (API exchanges) which consist of a sequence of ‘steps’.

### Scenarios

- Scenarios will be run in order of appearance, top to bottom.

- Each scenarios will have its own set of variables, context will not be preserved between scenarios.

```json
[
  { "id": "lorem", "name": "", "description": "", "steps": [ ... ] },
  { "id": "ipsum", "name": "", "description": "", "steps": [ ... ] },
  { "id": "stratos", "name": "", "description": "", "steps": [ ... ] }
]
```

```json
{
  "id": "scenario-unique-id",
  "name": "Human Readable Name",
  "description": "What this scenario validates",
  "crIds": ["MARGO-DEV-MANAGEMENTINTERFACE-016"],
  "steps": [ ... ]
}
```

<table>
<tr>
<th>
**Field**
</th>
<th>
**Required**
</th>
<th>
**Description**
</th>
</tr>
<tr>
<td>
`id`
</td>
<td>
Yes
</td>
<td>
Unique string among all scenarios. Listed in `group.json` to select the scenario. Used for filtering: `./bin/run\_tests -scenario scenario-capabilities`
</td>
</tr>
<tr>
<td>
`name`
</td>
<td>
Yes
</td>
<td>
Displayed in terminal output and HTML report
</td>
</tr>
<tr>
<td>
`description`
</td>
<td>
Yes
</td>
<td>
One-line explanation of what this scenario covers
</td>
</tr>
<tr>
<td>
`steps`
</td>
<td>
Yes
</td>
<td>
Ordered array of step objects (see below)
</td>
</tr>
<tr>
<td>
`crIds`
</td>
<td>
No
</td>
<td>
Summary of the requirement IDs its steps list. In the report a step is shown as evidence only for the IDs the step lists itself.
</td>
</tr>
<tr>
<td>
`optional`
</td>
<td>
No
</td>
<td>
Default `false`. Set `true` for a scenario that needs something not present on every setup (for example an OpenTelemetry collector). A failure is then reported as SKIP.
</td>
</tr>
</table>

*Table 1 : Field descripotion of Scenario object*

- Scenarios consist of ‘steps’, which are again run in sequence of appearance.

### Steps

- A ‘step’ is an API expected from the Margo Supplier component, the test-case ‘step’ defines the expected HTTP Request Header, encryption and validations. If the received API has the right HTTP Request, the HTTP Response defined in the step is sent, otherwise the specified failure response is sent.

- Each step can have the following content - 

```json
{
  "id": "step-2.1",
  "name": "Report Capabilities",
  "crIds": ["MARGO-DEV-DEPLOYMENT-002"],
  "method": "PUT",
  "endpoint": "/api/v1/capabilities/device-001",
  "mtls": true,
  "request_body":
  {
    "properties":
    {
      "id": "device-001",
      "vendor": "Acme Corp",
      "modelNumber": "ACM-XYZ",
      "serialNumber": "SN-12345",
      "cpus": [{ "cores": 4, "architecture": "arm64" }],
      "memory": "16Gi",
      "storage": "256Gi",
      "interfaces": [{ "type": "ethernet" }],
      "peripherals": [],
      "otelCollector": false,
      "supportedRuntimes": ["oci"],
      "supportedDeploymentTypes": ["helm", "compose"]
    }
  },
  "headers": {},
  "expected_status": 201,
  "accepted_statuses": [200],
  "validations":
  [
    { "field": "status", "operation": "equals", "value": "capabilities_received" }
  ],
  "extract_context": {}
}
```

<table>
<tr>
<th>
**Field**
</th>
<th>
**Required**
</th>
<th>
**Type**
</th>
<th>
**Description**
</th>
</tr>
<tr>
<td>
`id`
</td>
<td>
Yes
</td>
<td>
string
</td>
<td>
Unique step ID. Convention: `step-X.Y` where X is scenario number and Y is step number. Listed in `group.json` to select the step. Used for filtering: `./bin/run\_tests -step step-2.1`
</td>
</tr>
<tr>
<td>
`name`
</td>
<td>
Yes
</td>
<td>
string
</td>
<td>
Displayed in terminal and HTML report
</td>
</tr>
<tr>
<td>
`method`
</td>
<td>
Yes
</td>
<td>
string
</td>
<td>
HTTP verb: `"GET"`, `"POST"`, `"PUT"`, or `"DELETE"`
</td>
</tr>
<tr>
<td>
`endpoint`
</td>
<td>
Yes
</td>
<td>
string
</td>
<td>
URL path (without base URL). Supports `{placeholder}` substitution
</td>
</tr>
<tr>
<td>
`request\_body`
</td>
<td>
No
</td>
<td>
object
</td>
<td>
JSON body sent with POST/PUT. Omit entirely for GET requests. Values support `{placeholder}` substitution
</td>
</tr>
<tr>
<td>
`headers`
</td>
<td>
No
</td>
<td>
object
</td>
<td>
Custom HTTP headers. Values support `{placeholder}` substitution
</td>
</tr>
<tr>
<td>
`expected\_status`
</td>
<td>
Yes
</td>
<td>
number
</td>
<td>
HTTP status code the step expects. Anything else → FAIL, unless listed in `accepted\_statuses`
</td>
</tr>
<tr>
<td>
`validations`
</td>
<td>
No
</td>
<td>
array
</td>
<td>
Response field checks (see Validations section below)
</td>
</tr>
<tr>
<td>
`extract\_context`
</td>
<td>
No
</td>
<td>
object
</td>
<td>
Save response values as variables for later steps (see Context section below)
</td>
</tr>
<tr>
<td>
`crIds`
</td>
<td>
No
</td>
<td>
array
</td>
<td>
Margo requirement IDs this step is evidence for, shown next to the step in the report. List an ID only on a step that checks it
</td>
</tr>
<tr>
<td>
`mtls`
</td>
<td>
Yes (rc.3)
</td>
<td>
bool
</td>
<td>
Set `true`. The request is sent over mutual TLS: the Conformance Framework presents its X.509-SVID and checks the SPIFFE ID of the other side. All Margo 1.0.0-rc.3 Management Interface requests use it
</td>
</tr>
<tr>
<td>
`accepted\_statuses`
</td>
<td>
No
</td>
<td>
array
</td>
<td>
Other HTTP status codes that also pass, for example `\[200]` on a step that expects 201 so the test-case can be run again
</td>
</tr>
<tr>
<td>
`poll`
</td>
<td>
No
</td>
<td>
object
</td>
<td>
Repeat the request until the response meets the conditions: `{ "interval\_seconds": 5, "timeout\_seconds": 120, "until": \[ ...validations... ] }`. FAIL when the time is over
</td>
</tr>
<tr>
<td>
`expect\_manifest\_rejected`
</td>
<td>
No
</td>
<td>
bool
</td>
<td>
Device test-cases. PASS when the desired-state manifest in the response breaks a rule a device MUST enforce (unsupported digest algorithm, digest that does not match, `manifestVersion` that does not increase)
</td>
</tr>
<tr>
<td>
`expect\_manifest\_accepted`
</td>
<td>
No
</td>
<td>
bool
</td>
<td>
Device test-cases. PASS when the desired-state manifest in the response breaks none of those rules
</td>
</tr>
<tr>
<td>
`expect\_transport\_error`
</td>
<td>
No
</td>
<td>
bool
</td>
<td>
PASS when the connection is refused during the TLS handshake, for example when the other side presents an identity that must not be accepted
</td>
</tr>
<tr>
<td>
`svid\_source`
</td>
<td>
No
</td>
<td>
string
</td>
<td>
Which identity an `mtls` step presents. `"untrusted"`: a certificate with the right SPIFFE ID that the MIS did not issue — use with `expect\_transport\_error`. `"previous"` and `"refreshed"`: the SVID before and after a rotation; reported as NOT RUN / SKIP when no SVID was rotated. Device test-cases also have `"none"` (no client certificate)
</td>
</tr>
<tr>
<td>
`observe`
</td>
<td>
No
</td>
<td>
object
</td>
<td>
Device test-cases. The step sends nothing: it judges a request a real device sent to the mock WFM (see [Judging a real device: observe steps])
</td>
</tr>
<tr>
<td>
`skip\_signing`, `skip\_certificate\_injection`
</td>
<td>
No
</td>
<td>
bool
</td>
<td>
Used before 1.0.0-rc.3 (HTTP Message Signatures and the onboarding API). Not used in rc.3 test-cases
</td>
</tr>
</table>

*Table 2 : Fields in the Step object*

### Enablement for Functional & Context specific tests 

This class of tests requires validation of a sequence of incoming API requests from a Margo Supplier’s component. It also includes tests on values of fields as well as consistency checks in the form of context-variables for checking across steps.

#### Validations

- The ‘validations’ field in the ‘step’ object is an array of all validations to be applied on the received HTTP request. An example of validations that can be specified is given below.

```json
"validations":
 [
  { "field": "manifestVersion",   "operation": "is_number" },
  { "field": "status",            "operation": "equals",    "value": "capabilities_received" },
  { "field": "detail",            "operation": "contains",  "value": "supportedDeploymentTypes" },
  { "field": "bundle.digest",     "operation": "matches_regex", "value": "^sha256:[0-9a-f]{64}$" },
  { "field": "deployments",       "operation": "is_array"  },
  { "field": "_headers.ETag",     "operation": "not_empty" }
]
```

- The following ‘operations’ can be specified as a validation – 

<table>
<tr>
<th>
**Operation**
</th>
<th>
**`value` needed?**
</th>
<th>
**Passes when**
</th>
</tr>
<tr>
<td>
`equals`
</td>
<td>
Yes
</td>
<td>
Field value matches `value` exactly
</td>
</tr>
<tr>
<td>
`contains`
</td>
<td>
Yes
</td>
<td>
Field value (string) contains `value` as substring
</td>
</tr>
<tr>
<td>
`not\_empty`
</td>
<td>
No
</td>
<td>
Field is present and not `""`, `null`, or `\[]`
</td>
</tr>
<tr>
<td>
`exists`
</td>
<td>
No
</td>
<td>
Field is present (any value including empty)
</td>
</tr>
<tr>
<td>
`is\_string`
</td>
<td>
No
</td>
<td>
Field value is a JSON string
</td>
</tr>
<tr>
<td>
`is\_number`
</td>
<td>
No
</td>
<td>
Field value is a JSON number
</td>
</tr>
<tr>
<td>
`is\_array`
</td>
<td>
No
</td>
<td>
Field value is a JSON array
</td>
</tr>
<tr>
<td>
`is\_object`
</td>
<td>
No
</td>
<td>
Field value is a JSON object
</td>
</tr>
<tr>
<td>
`not\_contains`
</td>
<td>
Yes
</td>
<td>
Field value (string) does not contain `value`
</td>
</tr>
<tr>
<td>
`one\_of`
</td>
<td>
Yes (array)
</td>
<td>
Field value equals one of the entries of `value`
</td>
</tr>
<tr>
<td>
`matches\_regex`
</td>
<td>
Yes
</td>
<td>
Field value (string) matches the regular expression in `value`
</td>
</tr>
<tr>
<td>
`gte`
</td>
<td>
Yes
</td>
<td>
Field value is a number greater than or equal to `value`
</td>
</tr>
<tr>
<td>
`greater\_than`
</td>
<td>
Yes
</td>
<td>
Field value is a number greater than `value`
</td>
</tr>
<tr>
<td>
`array\_length\_gte`
</td>
<td>
Yes
</td>
<td>
Field value is an array with at least `value` entries
</td>
</tr>
<tr>
<td>
`array\_length\_equals`
</td>
<td>
Yes
</td>
<td>
Field value is an array with exactly `value` entries
</td>
</tr>
</table>

- An operation that the Conformance Framework does not know fails the step, with the name of the operation in the report.

- WFM test-cases have these additional operations: `etag\_is\_body\_digest` (the `ETag` header is the sha256 digest of the exact response body), `body\_sha256\_equals` (the exact response body has the digest given in `value`), `manifest\_urls\_are\_content\_addressed` (the URLs in the manifest have the form defined by the specification), `bundle\_null\_iff\_no\_deployments` (`bundle` is `null` exactly when `deployments` is empty) and `bundle\_contains\_exactly\_deployments` (the bundle archive holds exactly the files of the `deployments` array given in `value`, compared by digest).

#### Context or State Variables

- The Conformance Framework will extract and maintain the following ‘state variables’ between ‘steps’ in a ‘scenario’.

- This allows the test-case to apply consistency checks as part of Context specific tests.

<table>
<tr>
<th>
**Path**
</th>
<th>
**Accesses**
</th>
</tr>
<tr>
<td>
`"manifestVersion"`
</td>
<td>
Top-level field
</td>
</tr>
<tr>
<td>
`"status.state"`
</td>
<td>
Nested field
</td>
</tr>
<tr>
<td>
`"deployments.0.deploymentId"`
</td>
<td>
First array element's `deploymentId`
</td>
</tr>
<tr>
<td>
`"\_headers.ETag"`
</td>
<td>
HTTP response header (prefix with `\_headers.`)
</td>
</tr>
</table>

- Example of using this :

- `extract\_context` saves values from a response. 

- `{placeholders}` injects the extracted value into a later step.

- Saving a value:

```json
"extract\_context": {
  "deploymentId":  "deployments.0.deploymentId",
  "manifestEtag":  "\_headers.ETag"
}
```

- On the left side is the variable name. On the right side is the JSON path (same syntax used in the validations).

- Using a saved value:

```json
"endpoint": "/api/v1/deployments/{deploymentId}/status",

"headers": {
  "If-None-Match": "{manifestEtag}"
},

"request\_body": {
  "deploymentId": "{deploymentId}"
}

```

### Enablement for API Contract tests

- API Contracts are defined as part of the Margo OpenAPI specification’s swagger YAML.

- Being static in nature, these set of tests are tied to a specific version of the Margo specification.

- They will be represented in a single file (`ctt-runner/device-supplier/utils/manifests/assertions.json`), with the following generic structure :

```json
{
  "endpoints": 
  {
    "PUT_capabilities":   { ... },
    "POST_status":        { ... }
  },
  "device_expectations": 
  {
    "PUT_capabilities":   [ ... ]
  },
  "error_responses": 
  {
    "badRequest":    { "status_code": 400, "format": "error_string" },
    "notFound":      { "status_code": 404, "format": "error_string" },
    "unprocessable": { "status_code": 422, "format": "validation_errors" }
  }
}
```

- The mock WFM loads this file when it starts and it decides the validation: change a rule, restart the mock WFM, and the verdict changes.

- `endpoints` holds the rules of the Margo 1.0.0-rc.3 API: `PUT_capabilities` for `PUT /api/v1/capabilities/{deviceId}` and `POST_status` for `POST /api/v1/deployments/{deploymentId}/status`. A request that breaks a rule is rejected with problem details.

- `device_expectations` holds rules in the same format for what a Margo device must declare beyond the API schema, for example an OCI runtime or an OpenTelemetry collector. A request that breaks one is still accepted; the verdict of every rule is recorded with the request (`expectations.<rule_id>` is `pass` or says what is wrong) and read by the observe steps of the device group `core`.

<table>
<tr>
<th>
**Key**
</th>
<th>
**Purpose**
</th>
</tr>
<tr>
<td>
`endpoints`
</td>
<td>
Map of `METHOD\_name` → validation rules for that endpoint
</td>
</tr>
<tr>
<td>
`error\_responses`
</td>
<td>
Defines what error format each type of failure uses
</td>
</tr>
</table>

*Table 3: Fields in the API Contract test*

- An element of  ‘endponts’ has the following structure – 

```json
"PUT_capabilities": 
{
  "path": "/api/v1/capabilities/{deviceId}",
  "method": "PUT",
  "status_code": 201,
  "validation_error_key": "unprocessable",
  "validations": [ ... ],
  "response_structure": 
  {
    "matches": 
    [
      { "description": "Response must indicate success", "json": "status", "value": "capabilities_received" }
    ]
  }
}
```

- Field descriptions of the ‘endpoints’ object are given below :

<table>
<tr>
<th>
**Field**
</th>
<th>
**Required**
</th>
<th>
**Meaning**
</th>
</tr>
<tr>
<td>
`path`
</td>
<td>
Yes
</td>
<td>
URL path (informational, not used for routing)
</td>
</tr>
<tr>
<td>
`method`
</td>
<td>
Yes
</td>
<td>
HTTP method (informational)
</td>
</tr>
<tr>
<td>
`status\_code`
</td>
<td>
Yes
</td>
<td>
Expected HTTP status on success
</td>
</tr>
<tr>
<td>
`validation\_error\_key`
</td>
<td>
Only for write endpoints
</td>
<td>
Which `error\_responses` entry to use when validation fails (`"badRequest"` or `"unprocessable"`). The response is sent as RFC 9457 problem details (`application/problem+json`) with that status code
</td>
</tr>
<tr>
<td>
`validations`
</td>
<td>
Yes
</td>
<td>
Array of rule objects (see below)
</td>
</tr>
<tr>
<td>
`response\_structure`
</td>
<td>
No
</td>
<td>
Documents expected response fields (informational)
</td>
</tr>
</table>

*Table 4 : Fields in the 'endpints' object of a API Contract*

#### Validations

- ‘Validations’ are rules used to evaluate the API contract as specified in the OpenAPI specification

```json
{
  "rule_id": "capabilities-019",
  "field": "properties.supportedDeploymentTypes",
  "type": "array",
  "required": false,
  "minItems": 1,
  "itemsType": "string",
  "itemsEnum": ["helm", "compose", "custom"],
  "description": "properties.supportedDeploymentTypes is required and must contain at least one supported deployment type"
}
```

<table>
<tr>
<th>
**Field**
</th>
<th>
**Type**
</th>
<th>
**Required**
</th>
<th>
**Description**
</th>
</tr>
<tr>
<td>
`rule\_id`
</td>
<td>
string
</td>
<td>
Yes
</td>
<td>
Unique identifier. Naming convention: `endpoint-NNN` e.g., `"capabilities-011"`
</td>
</tr>
<tr>
<td>
`field`
</td>
<td>
string
</td>
<td>
Yes
</td>
<td>
JSON path to the field being validated (see Path Syntax below)
</td>
</tr>
<tr>
<td>
`type`
</td>
<td>
string
</td>
<td>
Yes
</td>
<td>
One of: `"string"`, `"number"`, `"boolean"`, `"object"`, `"array"`
</td>
</tr>
<tr>
<td>
`required`
</td>
<td>
bool
</td>
<td>
Yes
</td>
<td>
If `true`, server rejects request if field is absent
</td>
</tr>
<tr>
<td>
`requiredIf`
</td>
<td>
string
</td>
<td>
No
</td>
<td>
Path of another field. The rule is applied only when that field is present, for example `"properties.cpus"` for a rule on `properties.cpus.\*.cores`
</td>
</tr>
<tr>
<td>
`value`
</td>
<td>
string/any
</td>
<td>
No
</td>
<td>
If set, field must match exactly this value
</td>
</tr>
<tr>
<td>
`enum`
</td>
<td>
string[]
</td>
<td>
No
</td>
<td>
If set, field value must be one of these strings
</td>
</tr>
<tr>
<td>
`minLength`
</td>
<td>
number
</td>
<td>
No
</td>
<td>
For `"string"` type: minimum character count
</td>
</tr>
<tr>
<td>
`pattern`
</td>
<td>
string
</td>
<td>
No
</td>
<td>
For `"string"` type: a regular expression the value must match
</td>
</tr>
<tr>
<td>
`itemsInclude`
</td>
<td>
string\[]
</td>
<td>
No
</td>
<td>
For `"array"` type: every listed value must be among the items
</td>
</tr>
<tr>
<td>
`minItems`
</td>
<td>
number
</td>
<td>
No
</td>
<td>
For `"array"` type: minimum number of items
</td>
</tr>
<tr>
<td>
`itemsType`
</td>
<td>
string
</td>
<td>
No
</td>
<td>
For `"array"` type: each item must be this type (`"string"` or `"object"`)
</td>
</tr>
<tr>
<td>
`itemsEnum`
</td>
<td>
string[]
</td>
<td>
No
</td>
<td>
For `"array"` type: each item must be one of these values
</td>
</tr>
<tr>
<td>
`description`
</td>
<td>
string
</td>
<td>
Yes
</td>
<td>
Human-readable explanation used in error messages
</td>
</tr>
</table>

- Pre-built validations are supported for the following types :

<table>
<tr>
<th>
**`type`**
</th>
<th>
**What the engine checks**
</th>
</tr>
<tr>
<td>
`"string"`
</td>
<td>
Value is a string; optionally checks `value` (exact match), `enum`, `minLength`
</td>
</tr>
<tr>
<td>
`"number"`
</td>
<td>
Value is a JSON number (float64 internally)
</td>
</tr>
<tr>
<td>
`"object"`
</td>
<td>
Value is a JSON object `{}`
</td>
</tr>
<tr>
<td>
`"array"`
</td>
<td>
Value is a JSON array `\[]`; optionally checks `minItems`, `itemsType`, `itemsEnum`
</td>
</tr>
</table>

### Providing the Identity (X.509-SVID) for mutual TLS

- In Margo 1.0.0-rc.3 every Management Interface request is sent over mutual TLS. Both sides present an X.509-SVID issued by the Margo Identity Service (MIS).

- The test-case does not carry certificates. A step only sets `"mtls": true`:

```json
{
  "id": "step-3.1",
  "name": "Get Deployments",
  "method": "GET",
  "endpoint": "/api/v1/deployments",
  "mtls": true,
  "headers": { "Accept": "application/vnd.margo.manifest.v1+json" },
  "expected_status": 200
}
```

- The SVID, its private key and the MIS CA certificate are given to the Conformance Framework once, in `ctt-runner` (Device Supplier → Setup Identity, WFM Supplier → Setup MIAF Identity). The steps are in `docs/device-supplier-setup-guide.md` and `docs/wfm-supplier-setup-guide.md`.

- On every `mtls` step the Conformance Framework checks the certificate of the other side against the MIS CA and checks its SPIFFE ID: the WFM is `spiffe://<trust-domain>/margo/wfm/<wfm-id>` and its client is `spiffe://<trust-domain>/margo/wfm/<wfm-id>/client/<wfm-client-id>`.

### Judging a real device: observe steps

- A real device only calls out; the Conformance Framework cannot send it a request. For a real device the mock WFM records every request it receives, and an `observe` step checks what the device sent — or, for a manifest the device must reject, what it did not send.

- The device group `core` (`test-suites/device-supplier/core`) is written this way. The mock WFM judges each request with the rules of `assertions.json` (see [Enablement for API Contract tests]); a step reads the verdict: the status the request was answered with, and `expectations.<rule\_id>`, which is `pass` or says what is wrong. A normal step that changes the desired state on the mock WFM (`PUT /api/v1/test/deployments?client={deviceClient}`) starts a new observation window.

```json
{
  "id": "rd-2-desired-state-status",
  "name": "The device reports the deployment status with the manifest version it adopted",
  "crIds": ["MARGO-DEV-MANAGEMENTINTERFACE-007"],
  "observe":
  {
    "method": "POST",
    "path_regex": "^/api/v1/deployments/[^/]+/status$",
    "status": [200, 201],
    "within_seconds": 300,
    "check":
    [
      { "field": "body.adoptedManifestVersion", "operation": "is_number" }
    ]
  }
}
```

<table>
<tr>
<th>
**Field**
</th>
<th>
**Description**
</th>
</tr>
<tr>
<td>
`method`, `path\_regex`
</td>
<td>
Which request of the device is meant. The path is the part after the base URL
</td>
</tr>
<tr>
<td>
`where`
</td>
<td>
Validations a request must meet to be the one that is meant. Fields: `status`, `client`, `headers.Accept`, `headers.If-None-Match`, `body.\*` (request body), `response.\*` (the answer of the mock WFM)
</td>
</tr>
<tr>
<td>
`expect`
</td>
<td>
`"present"` (default): the request must be seen. `"absent"`: the request must not be seen
</td>
</tr>
<tr>
<td>
`status`
</td>
<td>
`present`: the answers of the mock WFM that pass. Default: any 2xx or 304
</td>
</tr>
<tr>
<td>
`check`
</td>
<td>
`present`: validations on the request that was seen. A failed one fails the step
</td>
</tr>
<tr>
<td>
`within\_seconds`
</td>
<td>
How long to wait for the device. Default 180
</td>
</tr>
<tr>
<td>
`after\_polls`, `settle\_seconds`
</td>
<td>
`absent`: the device must first have read the desired state this many times, plus the settle time, before its silence is judged
</td>
</tr>
<tr>
<td>
`only\_if`, `only\_if\_reason`
</td>
<td>
`absent`: a request (`method`, `path\_regex`, `where`) the device must have sent for the check to apply. Otherwise the step is reported as SKIP "not applicable" with the reason
</td>
</tr>
<tr>
<td>
`for\_seconds`
</td>
<td>
`absent`: watch for this long instead of counting reads of the desired state — used while the mock WFM presents a certificate the device must refuse
</td>
</tr>
<tr>
<td>
`if\_absent`, `skip\_reason`
</td>
<td>
`present`: `"skip"` reports SKIP "not applicable" instead of FAIL when the request is not seen; `"skip\_scenario"` also skips the rest of the scenario
</td>
</tr>
<tr>
<td>
`since`, `mark\_after`
</td>
<td>
`"since": "now"` looks only at requests received from this step on. `"mark\_after": true` makes the following steps look only at requests after the one seen here
</td>
</tr>
<tr>
<td>
`instruct`
</td>
<td>
A line printed for the operator before waiting, for example "Restart the device now"
</td>
</tr>
</table>

- `extract\_context` on an observe step saves values of the request that was seen. `{deviceClient}` is set to the SPIFFE ID of the first device that sent a request.

## APPENDIX

### Example test-case

```json
[
  { "id": "scenario-capabilities", ... },
  { "id": "scenario-desired-state", ... },
  {
    "id": "X",
    "name": "My New Test",
    "description": "Tests X behavior",
    "steps": 
    [
      { ...step X.1... },
      { ...step X.2... }
    ]
  }
]
```

### Examples of ‘Steps’ in the Test-Cases

- Example ‘Step’ in a test-case: Verify the desired-state manifest is returned.

```json
{
  "id": "step-X.1",
  "name": "Get Deployments",
  "method": "GET",
  "endpoint": "/api/v1/deployments",
  "mtls": true,
  "headers": 
  {
    "Accept": "application/vnd.margo.manifest.v1+json"
  },
  "expected_status": 200,
  "validations": 
  [
    { "field": "manifestVersion", "operation": "is_number" },
    { "field": "deployments", "operation": "is_array" },
    { "field": "_headers.ETag", "operation": "not_empty" }
  ],
  "extract_context": 
  {
    "manifestEtag": "_headers.ETag"
  }
}
```

- Example ‘Step’ in a test-case: Error / Rejection (expect failure)

```json
{
  "id": "step-X.2",
  "name": "Reject capabilities with an unknown deployment type",
  "method": "PUT",
  "endpoint": "/api/v1/capabilities/my-device-001",
  "mtls": true,
  "request_body": 
  {
    "properties": 
    {
      "id": "my-device-001",
      "vendor": "MyVendor",
      "modelNumber": "MDL-100",
      "serialNumber": "SN-99999",
      "supportedRuntimes": ["oci"],
      "supportedDeploymentTypes": ["not-a-deployment-type"]
    }
  },
  "expected_status": 422,
  "validations": 
  [
    { "field": "_headers.Content-Type", "operation": "contains", "value": "application/problem+json" },
    { "field": "type", "operation": "not_empty" }
  ],
  "extract_context": {}
}
```

- Example ‘Step’ in a test-case: Multi-Step Flow (chain steps with context)

```json
{
  "id": "step-X.1",
  "name": "Get Deployments",
  "method": "GET",
  "endpoint": "/api/v1/deployments",
  "mtls": true,
  "headers": 
  {
    "Accept": "application/vnd.margo.manifest.v1+json"
  },
  "expected_status": 200,
  "validations": 
  [
    { "field": "deployments", "operation": "array_length_gte", "value": 1 }
  ],
  "extract_context": 
  {
    "deploymentId": "deployments.0.deploymentId",
    "manifestVersion": "manifestVersion"
  }
}
{
  "id": "step-X.2",
  "name": "Report Deployment Status",
  "method": "POST",
  "endpoint": "/api/v1/deployments/{deploymentId}/status",
  "mtls": true,
  "request_body": 
  {
    "deploymentId": "{deploymentId}",
    "adoptedManifestVersion": "{manifestVersion}",
    "status": { "state": "installed" },
    "components": []
  },
  "expected_status": 200,
  "accepted_statuses": [201],
  "validations": [],
  "extract_context": {}
}
```

- Example ‘Step’ in a test-case: Repeat a request until a condition is met

```json
{
  "id": "step-X.3",
  "name": "Wait for a deployment to be assigned",
  "method": "GET",
  "endpoint": "/api/v1/deployments",
  "mtls": true,
  "headers": 
  {
    "Accept": "application/vnd.margo.manifest.v1+json"
  },
  "expected_status": 200,
  "poll": 
  {
    "interval_seconds": 5,
    "timeout_seconds": 120,
    "until": 
    [
      { "field": "deployments", "operation": "array_length_gte", "value": 1 }
    ]
  }
}
```

### Examples of Assertions used in API Contract test

**Pattern 1: Required object**  
_(e.g., __properties__ — the body must contain it)_

```json
{
  "rule\_id": "capabilities-003",
  "field": "properties",
  "type": "object",
  "required": true,
  "description": "properties field is required"
}

```

**Pattern 2: Required non-empty string**  
_(e.g., __serialNumber__ — must be present, no fixed value)_

```json

{
  "rule\_id": "capabilities-007",
  "field": "properties.serialNumber",
  "type": "string",
  "required": true,
  "minLength": 1,
  "description": "properties.serialNumber is required"
}

```

**Pattern 3: Optional string from allowed set (****enum****)**  
_(e.g., CPU architecture — optional but must be a known value if present)_

```json

{
  "rule\_id": "capabilities-010",
  "field": "properties.cpus.\*.architecture",
  "type": "string",
  "required": false,
  "requiredIf": "properties.cpus",
  "enum": \["amd64", "arm64", "arm"],
  "description": "properties.cpus\[].architecture must use a supported architecture value when present"
}

```

**Pattern 4: Required ****enum**** string**  
_(e.g., deployment state — required, only allowed values)_

```json
{
  "rule\_id": "status-005",
  "field": "status.state",
  "type": "string",
  "required": true,
  "enum": \["pending", "installing", "installed", "failed", "removing", "removed"],
  "description": "status.state must be a valid deployment state"
}
```

**Pattern 5: Array with ****enum**** items**  
_(e.g., supported runtimes — array, each item must be a known runtime)_

```json
{
  "rule\_id": "capabilities-018",
  "field": "properties.supportedRuntimes",
  "type": "array",
  "required": false,
  "minItems": 1,
  "itemsType": "string",
  "itemsEnum": \["oci", "custom"],
  "description": "properties.supportedRuntimes is required and must contain at least one supported runtime"
}
```

**Pattern 6: Wildcard array item validation**  
_(e.g., every interface must have a recognized type)_

```json
{
  "rule\_id": "capabilities-014",
  "field": "properties.interfaces.\*.type",
  "type": "string",
  "required": false,
  "requiredIf": "properties.interfaces",
  "enum": \["ethernet", "wifi", "cellular", "bluetooth", "usb", "canbus", "rs232"],
  "description": "Each interface must declare a supported type"
}
```

### Comparison of tools for generating Server-Side test-cases

<table>
<tr>
<th>
**Approach**
</th>
<th>
**What it does**
</th>
<th>
**Why not used**
</th>
</tr>
<tr>
<td>
**Schemathesis**** / ****har**** / Bruno**
</td>
<td>

</td>
<td>

</td>
</tr>
<tr>
<td>
**Postman / Newman**
</td>
<td>
GUI-based HTTP test collections; newman runs tests
</td>
<td>
Does not support use as a OpenAPI Server<br>Requires Postman install, complex export/import
</td>
</tr>
<tr>
<td>
**Pytest**** + requests**
</td>
<td>
Python test code
</td>
<td>
Requires Python, coding knowledge
</td>
</tr>
<tr>
<td>
**Cucumber / Gherkin**
</td>
<td>
BDD test language
</td>
<td>
Requires framework install, feature files
</td>
</tr>
<tr>
<td>
**test-****scenarios.json**** (this suite)**
</td>
<td>
Pure JSON, interpreted by Go runner, but needs test-cases in a prescribed format
</td>
<td>
No tools needed; edit file and re-run
</td>
</tr>
</table>
