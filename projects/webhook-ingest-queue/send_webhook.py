"""Send a signed test webhook to a Lambda Function URL."""

import argparse
import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.request
import uuid


def sign(secret: str, ts: str, body: bytes) -> str:
    digest = hmac.new(
        secret.encode("utf-8"), ts.encode("ascii") + b"." + body, hashlib.sha256
    ).hexdigest()
    return "sha256=" + digest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="Lambda Function URL")
    parser.add_argument("--id", default=str(uuid.uuid4()), help="Unique event ID")
    parser.add_argument("--type", default="order.created", help="Payload type; poison exercises the DLQ")
    parser.add_argument("--stale", action="store_true", help="Use a timestamp one hour old")
    parser.add_argument("--bad-sig", action="store_true", help="Send an invalid signature")
    args = parser.parse_args()

    secret = os.environ.get("WEBHOOK_SECRET")
    if not secret:
        parser.error("set WEBHOOK_SECRET to the out-of-band SSM secret first")

    timestamp = str(int(time.time()) - (3600 if args.stale else 0))
    body = json.dumps({"type": args.type, "data": {"example": True}}, separators=(",", ":")).encode("utf-8")
    signature = sign(secret, timestamp, body)
    if args.bad_sig:
        signature = "sha256=" + ("0" * 64)

    request = urllib.request.Request(
        args.url,
        data=body,
        method="POST",
        headers={
            "content-type": "application/json",
            "x-webhook-id": args.id,
            "x-webhook-timestamp": timestamp,
            "x-webhook-signature": signature,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            status = response.status
            response_body = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        status = exc.code
        response_body = exc.read().decode("utf-8", errors="replace")
    print(f"status={status} body={response_body}")
    return 0 if status < 500 else 1


if __name__ == "__main__":
    raise SystemExit(main())
