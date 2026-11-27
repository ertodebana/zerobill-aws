import json
import os
from datetime import datetime, timedelta, timezone

import boto3

cloudtrail = boto3.client("cloudtrail")


def handler(event, context):
    now = datetime.now(timezone.utc)
    lookback = timedelta(hours=int(os.environ.get("LOOKBACK_HOURS", "24")))
    # ponytail: one page only (max 50 events); busier accounts get a truncated digest, add a NextToken loop with throttling backoff if needed.
    resp = cloudtrail.lookup_events(
        LookupAttributes=[{"AttributeKey": "ReadOnly", "AttributeValue": "false"}],
        StartTime=now - lookback,
        EndTime=now,
        MaxResults=int(os.environ.get("MAX_EVENTS", "50")),
    )
    events = resp.get("Events", [])
    for e in events:
        print(json.dumps({
            "EventTime": e["EventTime"].isoformat(),
            "EventName": e.get("EventName"),
            "EventSource": e.get("EventSource"),
            "Username": e.get("Username"),
        }))
    print(json.dumps({"count": len(events)}))
    return len(events)
