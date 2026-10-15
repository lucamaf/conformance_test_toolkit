#!/usr/bin/env python3
"""
pdf_verify.py
=============
Checks the digital signature of a signed conformance report (PDF).

Usage:
    scripts/.venv/bin/python scripts/pdf_verify.py <signed.pdf> [ca_cert.pem]

Prints who signed the report, when, whether the document was changed after
signing, and (when ca_cert.pem is given) whether the signer chains to that CA.
Exit code 0 only when the signature is intact, valid and — if a CA was given —
trusted.
"""

import sys

from pyhanko.keys import load_cert_from_pemder
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko.sign.validation import validate_pdf_signature
from pyhanko_certvalidator import ValidationContext


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    pdf_path = sys.argv[1]
    ca_path = sys.argv[2] if len(sys.argv) > 2 else None

    vc = None
    if ca_path:
        vc = ValidationContext(trust_roots=[load_cert_from_pemder(ca_path)], allow_fetching=False)

    with open(pdf_path, "rb") as fh:
        reader = PdfFileReader(fh)
        signatures = reader.embedded_signatures
        if not signatures:
            print(f"NOT SIGNED: {pdf_path} has no digital signature")
            return 1
        ok = True
        for sig in signatures:
            status = validate_pdf_signature(sig, vc)
            covers_all = status.coverage.name == "ENTIRE_FILE"
            print(f"File      : {pdf_path}")
            print(f"Signed by : {status.signing_cert.subject.human_friendly}")
            print(f"Signed at : {status.signer_reported_dt}")
            print(f"Unchanged since signing : {'yes' if status.intact and status.valid and covers_all else 'NO'}")
            if ca_path:
                print(f"Signer chains to {ca_path} : {'yes' if status.trusted else 'NO'}")
            ok = ok and status.intact and status.valid and covers_all and (status.trusted or not ca_path)
        print("RESULT    : " + ("signature OK" if ok else "signature NOT OK"))
        return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
