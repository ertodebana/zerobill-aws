"""Deterministic payment mock used by the order saga."""


class PaymentDeclined(Exception):
    """A reproducible simulated decline surfaced to Step Functions."""


def handler(event, context):
    action = event.get("action")
    order_id = event.get("orderId")
    print(f"payment action={action} orderId={order_id}")

    if action == "charge":
        if event.get("simulate") == "decline":
            raise PaymentDeclined("simulated payment decline")
        return {"paymentId": "pay_" + order_id}
    if action == "refund":
        return {"refundId": "ref_" + order_id}
    raise ValueError("action must be charge or refund")
