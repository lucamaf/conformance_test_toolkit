# MIAF (mTLS) test identity — placeholder fixtures

These are **throwaway, self-signed** SPIFFE-shaped certificates, generated
locally with `openssl` (no MIS involved). The runner falls back to them only
when no identity has been installed in `real/`.

They are **not** conformance-meaningful: no real WFM trusts their CA. A
conformance run needs an X.509-SVID issued by the MIS of the WFM's trust
domain, installed with `ctt-runner/ctt-start.sh` → WFM Supplier → *Setup MIAF
Identity* (see `docs/wfm-supplier-setup-guide.md`). That step writes into
`real/`.

## Files

- `ca.pem` / `ca-key.pem` — a throwaway test CA (stands in for a trust domain's MIS).
- `wfm-svid-cert.pem` / `wfm-svid-key.pem` — a test WFM identity
  (`spiffe://margo-ctt.test/margo/wfm/margo-ctt-test-wfm`).
- `client-svid-cert.pem` / `client-svid-key.pem` — a test WFM Client identity
  (`spiffe://margo-ctt.test/margo/wfm/margo-ctt-test-wfm/client/margo-ctt-test-device`).
- `real/` — the identity installed by *Setup MIAF Identity* (see `real/README.md`).

## How the runner uses an identity

At the start of every WFM run, `ctt-start.sh` copies the identity into
`ctt-runner/wfm-supplier/utils/certs/` under the names the runner reads:

```
svid-cert.pem   svid-key.pem   svid-ca.pem
```

It takes `real/` when that folder holds a client SVID, otherwise the
placeholder files above, and checks that the certificate and key match and
that the certificate chains to the CA.

## Regenerating these placeholder fixtures

```bash
openssl ecparam -name prime256v1 -genkey -noout -out ca-key.pem
openssl req -new -x509 -key ca-key.pem -days 3650 -out ca.pem \
  -subj "/CN=margo-ctt-test-ca" -addext "basicConstraints=critical,CA:true" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

# then for each identity (wfm-svid / client-svid):
openssl ecparam -name prime256v1 -genkey -noout -out <name>-key.pem
openssl req -new -key <name>-key.pem -subj "/CN=<name>" -out <name>.csr
openssl x509 -req -in <name>.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
  -out <name>-cert.pem -days 365 \
  -extfile <(printf "basicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=URI:<spiffe-id>")
```
