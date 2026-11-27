"""Validate an order and start its Step Functions execution."""

import json
import os
import re
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

_ORDER_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_SKU = re.compile(r"^[A-Z0-9-]{1,32}$")
_SIMULATIONS = {"none", "decline", "fail_after_charge"}
_sfn = boto3.client("stepfunctions")


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(payload),
    }


def validate_order(body):
    """Return a normalized input dict or raise ValueError with a safe message."""
    if not isinstance(body, dict):
        raise ValueError("request body must be a JSON object")

    order_id = body.get("orderId") or str(uuid.uuid4())
    sku = body.get("sku")
    qty = body.get("qty")
    amount_cents = body.get("amountCents")
    simulate = body.get("simulate", "none")

    if not isinstance(order_id, str) or not _ORDER_ID.fullmatch(order_id):
        raise ValueError("orderId must match ^[A-Za-z0-9_-]{1,64}$")
    if not isinstance(sku, str) or not _SKU.fullmatch(sku):
        raise ValueError("sku must match ^[A-Z0-9-]{1,32}$")
    if isinstance(qty, bool) or not isinstance(qty, int) or not 1 <= qty <= 5:
        raise ValueError("qty must be an integer from 1 to 5")
    if (
        isinstance(amount_cents, bool)
        or not isinstance(amount_cents, int)
        or not 1 <= amount_cents <= 100000
    ):
        raise ValueError("amountCents must be an integer from 1 to 100000")
    if simulate not in _SIMULATIONS:
        raise ValueError("simulate must be none, decline, or fail_after_charge")

    return {
        "orderId": order_id,
        "sku": sku,
        "qty": str(qty),
        "amountCents": amount_cents,
        "simulate": simulate,
    }


def handler(event, context):
    raw_body = event.get("body") if isinstance(event, dict) else None
    if not isinstance(raw_body, str):
        return _response(400, {"error": "request body must be JSON"})
    if len(raw_body.encode("utf-8")) > 4096:
        return _response(400, {"error": "request body exceeds 4 KB"})

    try:
        body = json.loads(raw_body)
        order = validate_order(body)
    except (json.JSONDecodeError, ValueError) as exc:
        return _response(400, {"error": str(exc)})

    ttl_days = int(os.environ["ORDER_TTL_DAYS"])
    expires_at = int(datetime.now(timezone.utc).timestamp()) + ttl_days * 86400
    execution_input = {
        **order,
        "expiresAt": str(expires_at),
    }

    try:
        started = _sfn.start_execution(
            stateMachineArn=os.environ["STATE_MACHINE_ARN"],
            name=order["orderId"],
            input=json.dumps(execution_input, separators=(",", ":")),
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "Unknown")
        if code == "ExecutionAlreadyExists":
            return _response(409, {"error": "orderId already has an execution"})
        return _response(502, {"error": "could not start order execution"})

    return _response(
        202,
        {"orderId": order["orderId"], "executionArn": started["executionArn"]},
    )


if __name__ == "__main__":
    valid = {
        "orderId": "o-1",
        "sku": "SKU-RED",
        "qty": 1,
        "amountCents": 1999,
    }
    assert validate_order(valid)["qty"] == "1"
    assert validate_order({**valid, "simulate": "decline"})["simulate"] == "decline"
    for invalid in (
        {**valid, "orderId": "has spaces"},
        {**valid, "sku": "lowercase"},
        {**valid, "qty": True},
        {**valid, "qty": 0},
        {**valid, "amountCents": 100001},
        {**valid, "simulate": "surprise"},
    ):
        try:
            validate_order(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid input accepted: {invalid!r}")
