import time


def handler(event, context):
    time.sleep(0.1)  # visible duration on the X-Ray timeline
    return {"ok": True}
