# model-deploy-manually

The idea here is just two steps:

1. show how to load the model and send a message locally
2. show what the same pattern looks like when it runs on a server

## 1. Local example

[`app/01-load-model.py`](app/01-load-model.py) is almost the same as the book example.

```bash
cd model-deploy-manually/app
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python 01-load-model.py
```

## 2. Server example

[`app/server.py`](app/server.py) is the minimal FastAPI version.

```bash
cd model-deploy-manually/app
source .venv/bin/activate
uvicorn server:app --host 0.0.0.0 --port 8000
```

Test:

```bash
curl http://127.0.0.1:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{"text":"Explain in one sentence why model serving needs a runtime."}'
```

## 3. Terraform

The [`terraform/`](terraform/main.tf) folder only does this:

- creates one GPU EC2 instance
- copies `01-load-model.py`
- copies `server.py`
- installs dependencies
- starts `uvicorn`

### From scratch

```bash
cd model-deploy-manually/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

After `apply`, Terraform returns:

- `instance_id`
- `public_ip`
- `service_url`

### Test the script on the instance

Connect with SSM:

```bash
aws ssm start-session --region us-east-1 --target "$(terraform output -raw instance_id)"
```

Then inside the instance:

```bash
/opt/model-deploy-manually/run-load-model.sh
```

Or run the script directly with the Deep Learning AMI Python:

```bash
/opt/pytorch/bin/python /opt/model-deploy-manually/01-load-model.py
```

That runs:

- [`01-load-model.py`](app/01-load-model.py)
- with the same `MODEL_ID` configured in Terraform
- directly on the EC2 GPU instance

### Test the HTTP server

From your laptop:

```bash
terraform output -raw service_url
```

Then test the endpoint with `curl`.

Example:

```bash
curl "$(terraform output -raw service_url)" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Explain in one sentence why model serving needs a runtime."}'
```

### Useful checks

Inside the instance:

```bash
cat /opt/model-deploy-manually/.env
cat /var/log/model-server.log
ps aux | grep uvicorn
ss -ltnp | grep 8000
nvidia-smi
```

To destroy it:

```bash
terraform destroy
```

## Note

The default model is already a non-gated one:

```text
TinyLlama/TinyLlama-1.1B-Chat-v1.0
```

That means you do not need `HF_TOKEN` unless you switch to a gated model later.
