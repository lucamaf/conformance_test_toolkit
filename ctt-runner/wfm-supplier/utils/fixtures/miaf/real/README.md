# The CTT's WFM-Client identity

This folder holds the identity the CTT presents to the WFM under test. It is
written by `ctt-runner/ctt-start.sh` → WFM Supplier → *1. Setup MIAF
Identity*; do not edit the files by hand. The steps are in
`docs/wfm-supplier-setup-guide.md`.

| File | What it is |
|---|---|
| `client-svid-cert.pem`, `client-svid-key.pem` | The CTT's client X.509-SVID and its private key, issued by the MIS: `spiffe://<trust-domain>/margo/wfm/<wfm-id>/client/<wfm-client-id>` |
| `trust-bundle-ca.pem` | The MIS CA certificate. The CTT verifies the WFM's certificate against it. |
| `previous-client-svid-cert.pem`, `previous-client-svid-key.pem` | The SVID that was in use before the last *Setup MIAF Identity*, kept when the new SVID has the same SPIFFE ID. Used by the SVID Rotation scenario. |

To see which identity is installed:

```bash
openssl x509 -in client-svid-cert.pem -noout -ext subjectAltName -enddate
openssl verify -CAfile trust-bundle-ca.pem client-svid-cert.pem
```

At the start of every WFM run the files are copied to
`ctt-runner/wfm-supplier/utils/certs/` as `svid-cert.pem`, `svid-key.pem`
and `svid-ca.pem`.

When the SVID expires, or the WFM under test changes, issue a new client SVID
with the MIS and run *Setup MIAF Identity* again.
