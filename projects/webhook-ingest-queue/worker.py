"""Store a small idempotency record for each accepted webhook event."""

import hashlib
import json
import os
import time


def _canonical_payload(payload) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def handler(event, context):
    import boto3
    from botocore.exceptions import ClientError

    table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    ttl_days = int(os.environ["TTL_DAYS"])
    failures = []

    for record in event.get("Records", []):
        message_id = record.get("messageId", "")
        event_id = "-"
        try:
            envelope = json.loads(record["body"])
            event_id = envelope["event_id"]
            payload = envelope["payload"]
            if not isinstance(payload, dict) or payload.get("type") == "poison":
                raise ValueError("poison payload")

            payload_bytes = _canonical_payload(payload)
            item = {
                "event_id": event_id,
                "received_at": int(envelope["received_at"]),
                "processed_at": int(time.time()),
                "payload_sha256": hashlib.sha256(payload_bytes).hexdigest(),
                "event_type": str(payload.get("type", "unknown"))[:64],
                "expires_at": int(time.time()) + ttl_days * 86400,
            }
            try:
                table.put_item(
                    Item=item,
                    ConditionExpression="attribute_not_exists(event_id)",
                )
                print(json.dumps({"event_id": event_id, "outcome": "processed"}, separators=(",", ":")))
            except ClientError as exc:
                if exc.response.get("Error", {}).get("Code") != "ConditionalCheckFailedException":
                    raise
                print(json.dumps({"event_id": event_id, "outcome": "DUPLICATE"}, separators=(",", ":")))
        except Exception as exc:
            failures.append({"itemIdentifier": message_id})
            print(json.dumps({
                "event_id": event_id,
                "message_id": message_id,
                "outcome": "failed",
                "error_type": type(exc).__name__,
            }, separators=(",", ":")))

    return {"batchItemFailures": failures}
