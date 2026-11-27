# SWF domain (hand-driven workflow)

> **Warning: `terraform destroy` does not delete the domain.** It only **deprecates** it, permanently. A deprecated SWF domain cannot be deleted or reused, stays visible with `--registration-status DEPRECATED`, and uses one of the 100 domain slots per account and region for good. Each apply/destroy cycle uses up one more slot. It costs nothing once no executions are open or retained.

Creates one Amazon Simple Workflow Service (SWF) domain, `swf-learning-<suffix>`, with closed executions kept for 1 day. That is the only resource Terraform manages. There is no IAM role, Lambda, EC2 or network resource.

You then play both the **decider** and the **activity worker** with the AWS CLI. You register a workflow type and an activity type, start an execution, poll for decision and activity tasks, complete them, and read the event history. This shows what sets SWF apart from Step Functions: the split between decider and worker, task lists, timeouts and event history.

The workflow type `HelloWorkflow` v1 and activity type `SayHello` v1 are registered with the CLI because AWS provider 5.x has no resource for SWF types. They live inside the domain, cost nothing, and are deprecated along with it.

## Always Free and cost notes

Sources: [AWS Free Tier](https://aws.amazon.com/free/) and [Amazon SWF pricing](https://aws.amazon.com/swf/pricing/) (checked 2026-11-27). The free usage resets monthly, does not roll over, and applies to new and existing customers.

| Dimension | Always Free limit / month | Expected usage (walkthrough run ~5 times) |
|---|---|---|
| Workflow executions started | 1,000 | ~5 |
| Activity tasks + timers + signals + markers | 10,000 | ~5 activity tasks, 0 timers/signals/markers |
| Workflow-days (open or retained, per 24 h) | 30,000 | ~10 (each execution open less than 1 day plus 1 retention day) |
| Domains (quota, not billed) | 100 per account, deprecated domains included | 1 per apply |

Even beyond the free tier, a workflow-day costs $0.000005, so a forgotten execution costs a fraction of a cent. The real risk is using up domain slots, not money.

- **Open executions outlive `destroy`.** Deprecating a domain does not stop running executions. Every execution here has a 300 s start-to-close timeout, and Cleanup terminates any that are still open.
- **Scripted loops.** Do not script start or poll loops. They could use up the 1,000 starts or 10,000 tasks. Check your usage with `count-closed-workflow-executions` (see Use).
- `retention_days` is limited to 0-7 (default 1) to keep workflow-days low.

AWS's SWF developer guide recommends [Step Functions](https://aws.amazon.com/step-functions/) for most new use cases. This is advice only: SWF is not deprecated and is still open to new customers.

## Requirements

- Terraform >= 1.5.0
- AWS CLI v2 configured with an IAM Identity Center profile
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

Least-privilege policy. Replace `<region>` and `<account>`. Check the action-to-resource mapping against the [SWF IAM docs](https://docs.aws.amazon.com/amazonswf/latest/developerguide/swf-dev-iam.html) and the [Service Authorization Reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonsimpleworkflowservice.html) before you use it.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformDomain",
      "Effect": "Allow",
      "Action": [
        "swf:RegisterDomain",
        "swf:DeprecateDomain",
        "swf:DescribeDomain",
        "swf:ListTagsForResource",
        "swf:TagResource",
        "swf:UntagResource"
      ],
      "Resource": "arn:aws:swf:<region>:<account>:/domain/swf-learning-*"
    },
    {
      "Sid": "ListDomains",
      "Effect": "Allow",
      "Action": "swf:ListDomains",
      "Resource": "*"
    },
    {
      "Sid": "Walkthrough",
      "Effect": "Allow",
      "Action": [
        "swf:RegisterWorkflowType",
        "swf:RegisterActivityType",
        "swf:StartWorkflowExecution",
        "swf:PollForDecisionTask",
        "swf:RespondDecisionTaskCompleted",
        "swf:PollForActivityTask",
        "swf:RespondActivityTaskCompleted",
        "swf:GetWorkflowExecutionHistory",
        "swf:DescribeWorkflowExecution",
        "swf:ListOpenWorkflowExecutions",
        "swf:ListClosedWorkflowExecutions",
        "swf:CountClosedWorkflowExecutions",
        "swf:TerminateWorkflowExecution"
      ],
      "Resource": "arn:aws:swf:<region>:<account>:/domain/swf-learning-*"
    }
  ]
}
```

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
DOMAIN=$(terraform output -raw domain_name)
```

Poll calls are long polls. If no task is waiting, they block for up to 60 s and then return an empty `taskToken`. If that happens, poll again.

a. Register the workflow type:

```sh
aws swf register-workflow-type --domain $DOMAIN --name HelloWorkflow --workflow-version 1 \
  --default-task-list name=decisions --default-execution-start-to-close-timeout 300 \
  --default-task-start-to-close-timeout 60 --default-child-policy TERMINATE
```

b. Register the activity type:

```sh
aws swf register-activity-type --domain $DOMAIN --name SayHello --activity-version 1 \
  --default-task-list name=activities --default-task-start-to-close-timeout 60 \
  --default-task-schedule-to-start-timeout 120 --default-task-schedule-to-close-timeout 180 \
  --default-task-heartbeat-timeout NONE
```

c. Start an execution. It times out after 300 s whatever you do:

```sh
aws swf start-workflow-execution --domain $DOMAIN --workflow-id hello-1 \
  --workflow-type name=HelloWorkflow,version=1 --input '"world"' \
  --execution-start-to-close-timeout 300
```

d. As the decider, poll and schedule the activity:

```sh
TOKEN=$(aws swf poll-for-decision-task --domain $DOMAIN --task-list name=decisions \
  --query taskToken --output text)
aws swf respond-decision-task-completed --task-token "$TOKEN" --decisions '[{
  "decisionType": "ScheduleActivityTask",
  "scheduleActivityTaskDecisionAttributes": {
    "activityType": {"name": "SayHello", "version": "1"},
    "activityId": "say-hello-1",
    "taskList": {"name": "activities"},
    "input": "\"world\""
  }
}]'
```

e. As the worker, poll and complete the activity:

```sh
TOKEN=$(aws swf poll-for-activity-task --domain $DOMAIN --task-list name=activities \
  --query taskToken --output text)
aws swf respond-activity-task-completed --task-token "$TOKEN" --result '"hello world"'
```

f. As the decider again, complete the workflow:

```sh
TOKEN=$(aws swf poll-for-decision-task --domain $DOMAIN --task-list name=decisions \
  --query taskToken --output text)
aws swf respond-decision-task-completed --task-token "$TOKEN" --decisions '[{
  "decisionType": "CompleteWorkflowExecution",
  "completeWorkflowExecutionDecisionAttributes": {"result": "\"hello world\""}
}]'
```

g. Read the event history:

```sh
RUN_ID=$(aws swf list-closed-workflow-executions --domain $DOMAIN \
  --start-time-filter oldestDate=0 --execution-filter workflowId=hello-1 \
  --query 'executionInfos[0].execution.runId' --output text)
aws swf get-workflow-execution-history --domain $DOMAIN \
  --execution workflowId=hello-1,runId=$RUN_ID \
  --query 'events[].[eventId,eventType]' --output table
```

To run it again, use a new `--workflow-id` (for example `hello-2`). Check how much you have used:

```sh
aws swf count-closed-workflow-executions --domain $DOMAIN --start-time-filter oldestDate=0
```

## Cleanup

1. Find any open executions and terminate them:

```sh
aws swf list-open-workflow-executions --domain $DOMAIN --start-time-filter oldestDate=0 \
  --query 'executionInfos[].execution.workflowId' --output text
aws swf terminate-workflow-execution --domain $DOMAIN --workflow-id <id>   # for each id listed
```

2. Destroy:

```sh
terraform plan -destroy
terraform destroy
```

3. Check:

```sh
aws swf describe-domain --name $DOMAIN          # "status": "DEPRECATED" is expected
aws swf list-domains --registration-status REGISTERED   # swf-learning-* no longer listed
terraform state list                            # empty
```

**Destroy only deprecates the domain. It is never deleted.** It stays listed under `aws swf list-domains --registration-status DEPRECATED`, its name can never be reused, and it uses one of the 100 domain slots in the account and region permanently. Once no executions are open and the 1-day retention has passed, it accrues nothing. Check Billing > Free Tier to confirm SWF usage is well under the limits.
