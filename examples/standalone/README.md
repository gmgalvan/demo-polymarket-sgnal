# standalone OpenClaw on EC2

This example now installs both OpenClaw and a local `vLLM` server on the same GPU EC2 instance, with OpenClaw configured to use that local model by default.

What Terraform does:

- launches one GPU EC2 instance
- uses an AWS Deep Learning AMI with NVIDIA drivers already included
- installs `vLLM` in its own Python virtualenv under `/opt/vllm/.venv`
- starts `vLLM` as a `systemd` service on `127.0.0.1:8000`
- installs OpenClaw with the official installer
- runs non-interactive onboarding as `ec2-user`
- writes OpenClaw model config so the default model is the local `vLLM` model
- installs the gateway as a background service
- keeps the gateway on loopback by default for safer remote access through SSM

The default instance type is `g5.xlarge`, which gives you one NVIDIA A10G GPU. The default local model is `Qwen/Qwen2.5-14B-Instruct-AWQ`, served by `vLLM` as `qwen2.5-14b-instruct-awq-local` with `awq_marlin`.

## Terraform

```bash
cd examples/standalone/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

`terraform.tfvars` can stay minimal for the default public model:

```hcl
hf_token = ""
```

If you switch to a gated Hugging Face model later, set `hf_token`.
If you leave `gateway_token` blank, the instance bootstrap generates one and stores it on the box.

## Access the dashboard

The default bind is loopback on port `18789`, so the recommended access pattern is SSM port forwarding.

```bash
aws ssm start-session \
  --region us-east-1 \
  --target "$(terraform output -raw instance_id)" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'
```

Then open:

```bash
http://127.0.0.1:18789/
```

On first open, the dashboard will ask for the gateway token. You can read it from the instance:

```bash
aws ssm start-session --region us-east-1 --target "$(terraform output -raw instance_id)"
sudo bash -lc 'source /home/ec2-user/.openclaw-bootstrap/openclaw.env && printf "%s\n" "$OPENCLAW_GATEWAY_TOKEN"'
```

Paste that value into `Gateway Token`, leave `Password` empty, and click `Connect`.

If the browser asks for device pairing approval, approve the request from the instance with the same token:

```bash
TOKEN=$(sudo bash -lc 'source /home/ec2-user/.openclaw-bootstrap/openclaw.env && printf "%s" "$OPENCLAW_GATEWAY_TOKEN"')
sudo -u ec2-user -i openclaw devices list --token "$TOKEN"
sudo -u ec2-user -i openclaw devices approve <REQUEST_ID> --token "$TOKEN"
```

After pairing, click `Connect` again. A new browser profile or incognito window may generate a new pairing request.

## Quick validation

After `terraform apply`, these checks should pass from inside the instance:

```bash
curl -H "Authorization: Bearer vllm-local" http://127.0.0.1:8000/v1/models
sudo -u ec2-user -i openclaw models list --provider vllm
curl -i http://127.0.0.1:18789/
```

Once the UI is open, create a `New session` and send a short prompt like:

```text
Respond with exactly: hola
```

## Inspect the instance

```bash
aws ssm start-session --region us-east-1 --target "$(terraform output -raw instance_id)"
```

Useful checks inside the instance:

```bash
cat /home/ec2-user/.openclaw/openclaw.json
cat /home/ec2-user/.openclaw-bootstrap/openclaw.env
cat /var/log/openclaw-install.log
cat /var/log/openclaw-onboard.log
cat /var/log/vllm.log
sudo systemctl status vllm
curl -H "Authorization: Bearer vllm-local" http://127.0.0.1:8000/v1/models
su - ec2-user -c 'openclaw gateway status'
su - ec2-user -c 'openclaw models list --provider vllm'
```

## Optional public exposure

If you intentionally want to open the gateway port, set:

```hcl
gateway_bind        = "lan"
allowed_cidr_blocks = ["203.0.113.10/32"]
```

Keep token auth enabled if you do this.

To destroy it:

```bash
terraform destroy
```
