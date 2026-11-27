# Step Functions hello

Creates a Step Functions **Standard** state machine written in Amazon States Language. It uses only built-in states (Pass, Choice, Succeed, Fail), so it calls no other AWS service. It validates input with a Choice state, then shows input/output processing with `Parameters` and branching with a second Choice state. Start executions by hand and inspect them in the console's execution graph.

Resources created:

- `aws_iam_role.sfn`: execution role trusted by `states.amazonaws.com` (limited to your account), with no policies attached because the workflow calls nothing.
- `aws_sfn_state_machine.hello`: `STANDARD` type, logging off, tracing off.

## Always Free and cost notes

AWS lists Step Functions Standard workflows with an Always Free offer of **4,000 state transitions per month** that does not expire. Check [Step Functions pricing](https://aws.amazon.com/step-functions/pricing/) and the [AWS Free Tier page](https://aws.amazon.com/free/) for current limits.

- Each run uses about 2 to 5 state transitions, so roughly 1,000 runs fit in the monthly allowance.
- **Express workflows have no free tier.** The type is hard-coded to `STANDARD`; don't change it.
- Logging (`level = "OFF"`) and X-Ray tracing are off, so no CloudWatch Logs or X-Ray usage.
- No schedule, no loops, no `Retry`, `Map` or `Wait` states. Retries would count as extra transitions.
- If you add Task states later, the services they call (Lambda and others) bill under their own pricing and free tiers.

## Requirements

- Terraform installed
- AWS CLI configured with an IAM Identity Center profile
- Permissions: `states:*` on the state machine, plus `iam:CreateRole`, `iam:DeleteRole`, `iam:GetRole` and `iam:PassRole` on the role
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Start an execution that succeeds through the `Shout` branch:

```sh
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw state_machine_arn) \
  --input '{"name":"Ada","loud":true}'
aws stepfunctions describe-execution --execution-arn <executionArn from above>
```

The output is `{"greeting":"Hello, Ada! (LOUD)"}`. With `"loud":false` it is `{"greeting":"Hello, Ada!","loud":false}`.

An input that fails at the `BadInput` state:

```sh
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw state_machine_arn) \
  --input '{"name":"Ada","loud":"yes"}'
```

`describe-execution` shows `status: FAILED` with error `BadInput`. Input missing `name` or `loud` fails the same way, because `CheckInput` runs before `Greet`.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Execution history is deleted with the state machine. Check:

- `aws stepfunctions list-state-machines` no longer lists `step-functions-hello`
- `aws iam get-role --role-name step-functions-hello-role` returns `NoSuchEntity`
- `terraform state list` is empty
