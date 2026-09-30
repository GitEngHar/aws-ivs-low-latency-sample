# infrastructure

Terraform for AWS resources that support this project. Currently manages an
EventBridge rule that captures AWS IVS "Stream State Change" events (stream
start/end) for every channel in the account and writes them to CloudWatch
Logs (`eventbridge.tf`).

## Prerequisites

- Terraform >= 1.5 (`terraform version`)
- AWS credentials for the target account, either via environment variables
  (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`) or a
  named profile in `~/.aws/config` / `~/.aws/credentials`

## Usage

```bash
cd infrastructure

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set aws_region / aws_profile as needed

# build the Go lambda binary (required before plan/apply)
(cd lambda && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -o build/bootstrap .)

terraform init
terraform plan
```

When IVS writes `.../events/recording-ended.json` to the recording bucket,
an S3 event notification invokes the `resolution-tag-add` lambda
(`BATCH_NAME=resolution_tag_add`) — see `s3.tf` / `lambda.tf`.

State is local (`terraform.tfstate` in this directory, gitignored) — there is
no remote backend configured, so `plan`/`apply` work standalone on a laptop.

To apply against a non-default profile without editing `terraform.tfvars`:

```bash
terraform plan -var="aws_profile=your-profile-name"
```
