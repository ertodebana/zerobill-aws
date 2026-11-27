import json
import os
import time
import urllib.error
import urllib.request

import boto3

URLS = json.loads(os.environ.get("URLS", "[]"))
TABLE_NAME = os.environ.get("TABLE_NAME", "")
NAMESPACE = os.environ.get("NAMESPACE", "TwoDollarAws/Uptime")
TTL_DAYS = int(os.environ.get("TTL_DAYS", "7"))


def is_up(status):
    return 200 <= status < 400


def check(url):
    start = time.monotonic()
    status, error = 0, None
    try:
        req = urllib.request.Request(
            url, method="GET", headers={"User-Agent": "zerobill-uptime-monitor"}
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        status, error = e.code, "HTTPError"
    except Exception as e:  # a failed check is data, not an error
        error = type(e).__name__
    return {
        "url": url,
        "ok": 1 if is_up(status) else 0,
        "status_code": status,
        "latency_ms": int((time.monotonic() - start) * 1000),
        "error": error,
    }


def handler(event, context):
    results = [check(u) for u in URLS]
    ts = int(time.time())

    boto3.client("cloudwatch").put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {
                "MetricName": "Up",
                "Dimensions": [{"Name": "Url", "Value": r["url"]}],
                "Value": r["ok"],
                "Unit": "None",
            }
            for r in results
        ],
    )

    ddb = boto3.client("dynamodb")
    for r in results:
        item = {
            "url": {"S": r["url"]},
            "ts": {"N": str(ts)},
            "ok": {"N": str(r["ok"])},
            "status_code": {"N": str(r["status_code"])},
            "latency_ms": {"N": str(r["latency_ms"])},
            "expires_at": {"N": str(ts + TTL_DAYS * 86400)},
        }
        if r["error"]:
            item["error"] = {"S": r["error"]}
        ddb.put_item(TableName=TABLE_NAME, Item=item)
        print(json.dumps({"ts": ts, **r}))

    return {"checked": len(results), "down": [r["url"] for r in results if not r["ok"]]}


if __name__ == "__main__":
    assert is_up(200)
    assert is_up(301)
    assert not is_up(404)
    assert not is_up(500)
    assert not is_up(0)
    print("ok")
