#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO="${ECR_REPO:-vllm-neuron}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
VLLM_REF="${VLLM_REF:-v0.6.0}"

INSTANCE_TYPE="${INSTANCE_TYPE:-m7i.4xlarge}"
VOLUME_SIZE_GB="${VOLUME_SIZE_GB:-350}"
SUBNET_ID="${SUBNET_ID:-}"
WAIT_TIMEOUT_MIN="${WAIT_TIMEOUT_MIN:-240}"
POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-30}"
KEEP_BUILDER_RESOURCES="${KEEP_BUILDER_RESOURCES:-false}"

for bin in aws base64; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "Missing dependency: ${bin}" >&2
    exit 1
  }
done

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"
SUFFIX="$(date +%s)-$RANDOM"
ROLE_NAME="tmp-neuron-ecr-builder-${SUFFIX}"
PROFILE_NAME="${ROLE_NAME}"
SG_NAME="tmp-neuron-ecr-builder-${SUFFIX}"
TAG_NAME="tmp-neuron-ecr-builder-${SUFFIX}"
INSTANCE_ID=""
SG_ID=""
CREATED_IAM=false

echo "Using:"
echo "  AWS_REGION=${AWS_REGION}"
echo "  ECR_REPO=${ECR_REPO}"
echo "  IMAGE_TAG=${IMAGE_TAG}"
echo "  VLLM_REF=${VLLM_REF}"
echo "  IMAGE_URI=${IMAGE_URI}"
echo "  INSTANCE_TYPE=${INSTANCE_TYPE}"
echo "  VOLUME_SIZE_GB=${VOLUME_SIZE_GB}"

if [[ -z "${SUBNET_ID}" ]]; then
  SUBNET_ID="$(aws ec2 describe-subnets \
    --region "${AWS_REGION}" \
    --filters Name=state,Values=available \
    --query 'Subnets[0].SubnetId' \
    --output text)"
fi

if [[ -z "${SUBNET_ID}" || "${SUBNET_ID}" == "None" ]]; then
  echo "Could not resolve SUBNET_ID. Set SUBNET_ID explicitly." >&2
  exit 1
fi

VPC_ID="$(aws ec2 describe-subnets \
  --region "${AWS_REGION}" \
  --subnet-ids "${SUBNET_ID}" \
  --query 'Subnets[0].VpcId' \
  --output text)"

if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
  echo "Could not resolve VPC_ID for subnet ${SUBNET_ID}." >&2
  exit 1
fi

echo "Resolved:"
echo "  SUBNET_ID=${SUBNET_ID}"
echo "  VPC_ID=${VPC_ID}"

aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null

echo "Creating temporary IAM role/profile..."

TRUST_FILE="$(mktemp)"
POLICY_FILE="$(mktemp)"
USER_DATA_FILE="$(mktemp)"

cleanup_tmp() {
  rm -f "${TRUST_FILE}" "${POLICY_FILE}" "${USER_DATA_FILE}"
}
trap cleanup_tmp EXIT

cleanup_cloud_resources() {
  if [[ "${KEEP_BUILDER_RESOURCES}" == "true" ]]; then
    return
  fi

  if [[ -n "${INSTANCE_ID}" ]]; then
    aws ec2 terminate-instances --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${SG_ID}" ]]; then
    aws ec2 delete-security-group --region "${AWS_REGION}" --group-id "${SG_ID}" >/dev/null 2>&1 || true
  fi

  if [[ "${CREATED_IAM}" == "true" ]]; then
    aws iam remove-role-from-instance-profile --instance-profile-name "${PROFILE_NAME}" --role-name "${ROLE_NAME}" >/dev/null 2>&1 || true
    aws iam delete-instance-profile --instance-profile-name "${PROFILE_NAME}" >/dev/null 2>&1 || true
    aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name EcrBuildAndSelfTerminate >/dev/null 2>&1 || true
    aws iam delete-role --role-name "${ROLE_NAME}" >/dev/null 2>&1 || true
  fi
}

on_error() {
  echo "Script failed. Cleaning temporary cloud resources..." >&2
  cleanup_cloud_resources
}

trap on_error ERR

cat > "${TRUST_FILE}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

cat > "${POLICY_FILE}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        "ecr:CreateRepository"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:TerminateInstances"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-role \
  --role-name "${ROLE_NAME}" \
  --assume-role-policy-document "file://${TRUST_FILE}" >/dev/null

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name EcrBuildAndSelfTerminate \
  --policy-document "file://${POLICY_FILE}" >/dev/null

aws iam create-instance-profile \
  --instance-profile-name "${PROFILE_NAME}" >/dev/null

aws iam add-role-to-instance-profile \
  --instance-profile-name "${PROFILE_NAME}" \
  --role-name "${ROLE_NAME}" >/dev/null
CREATED_IAM=true

sleep 10

echo "Creating temporary security group..."
SG_ID="$(aws ec2 create-security-group \
  --region "${AWS_REGION}" \
  --group-name "${SG_NAME}" \
  --description "Temporary SG for Neuron ECR builder" \
  --vpc-id "${VPC_ID}" \
  --query GroupId \
  --output text)"

aws ec2 create-tags \
  --region "${AWS_REGION}" \
  --resources "${SG_ID}" \
  --tags Key=Name,Value="${SG_NAME}" >/dev/null

AMI_ID="$(aws ssm get-parameter \
  --region "${AWS_REGION}" \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' \
  --output text)"

DOCKERFILE_B64="$(base64 -w0 "${SCRIPT_DIR}/Dockerfile.neuron")"

cat > "${USER_DATA_FILE}" <<EOF
#!/usr/bin/env bash
set -euxo pipefail
exec > >(tee -a /var/log/neuron-ecr-build.log | logger -t neuron-ecr-build -s 2>/dev/console) 2>&1

AWS_REGION="${AWS_REGION}"
ECR_REPO="${ECR_REPO}"
IMAGE_TAG="${IMAGE_TAG}"
VLLM_REF="${VLLM_REF}"
DOCKERFILE_B64="${DOCKERFILE_B64}"
KEEP_BUILDER_RESOURCES="${KEEP_BUILDER_RESOURCES}"

dnf install -y docker awscli git
systemctl enable --now docker

ACCOUNT_ID=\$(aws sts get-caller-identity --query Account --output text --region "\${AWS_REGION}")
IMAGE_URI="\${ACCOUNT_ID}.dkr.ecr.\${AWS_REGION}.amazonaws.com/\${ECR_REPO}:\${IMAGE_TAG}"

aws ecr describe-repositories --repository-names "\${ECR_REPO}" --region "\${AWS_REGION}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "\${ECR_REPO}" --region "\${AWS_REGION}" >/dev/null

aws ecr get-login-password --region "\${AWS_REGION}" | \
  docker login --username AWS --password-stdin "\${ACCOUNT_ID}.dkr.ecr.\${AWS_REGION}.amazonaws.com"

mkdir -p /opt/neuron-build
cd /opt/neuron-build
echo "\${DOCKERFILE_B64}" | base64 -d > Dockerfile.neuron

docker build \
  --build-arg VLLM_REF="\${VLLM_REF}" \
  -f Dockerfile.neuron \
  -t "\${IMAGE_URI}" \
  .

docker push "\${IMAGE_URI}"
docker system prune -af --volumes || true

if [[ "\${KEEP_BUILDER_RESOURCES}" != "true" ]]; then
  TOKEN=\$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  IID=\$(curl -sH "X-aws-ec2-metadata-token: \${TOKEN}" "http://169.254.169.254/latest/meta-data/instance-id")
  aws ec2 terminate-instances --instance-ids "\${IID}" --region "\${AWS_REGION}" >/dev/null
fi
EOF

echo "Launching builder EC2..."
INSTANCE_ID="$(aws ec2 run-instances \
  --region "${AWS_REGION}" \
  --image-id "${AMI_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --iam-instance-profile Name="${PROFILE_NAME}" \
  --subnet-id "${SUBNET_ID}" \
  --security-group-ids "${SG_ID}" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${VOLUME_SIZE_GB},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
  --user-data "file://${USER_DATA_FILE}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TAG_NAME}},{Key=ManagedBy,Value=build-and-push-ecr-ec2.sh}]" \
  --query 'Instances[0].InstanceId' \
  --output text)"

echo "Instance launched: ${INSTANCE_ID}"
echo "Image target: ${IMAGE_URI}"

aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}"

echo "Builder running. Waiting for auto-termination (timeout ${WAIT_TIMEOUT_MIN} min)..."
elapsed=0
max_seconds=$((WAIT_TIMEOUT_MIN * 60))

while true; do
  state="$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || true)"

  echo "  state=${state:-unknown} elapsed=${elapsed}s"

  if [[ "${state}" == "terminated" ]]; then
    echo "Builder instance terminated."
    break
  fi

  if (( elapsed >= max_seconds )); then
    echo "Timeout reached. Terminating instance manually..."
    aws ec2 terminate-instances --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}" >/dev/null || true
    aws ec2 wait instance-terminated --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}" || true
    break
  fi

  sleep "${POLL_INTERVAL_SEC}"
  elapsed=$((elapsed + POLL_INTERVAL_SEC))
done

if [[ "${KEEP_BUILDER_RESOURCES}" != "true" ]]; then
  echo "Cleaning temporary IAM and network resources..."

  aws iam remove-role-from-instance-profile \
    --instance-profile-name "${PROFILE_NAME}" \
    --role-name "${ROLE_NAME}" >/dev/null || true

  aws iam delete-instance-profile \
    --instance-profile-name "${PROFILE_NAME}" >/dev/null || true

  aws iam delete-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name EcrBuildAndSelfTerminate >/dev/null || true

  aws iam delete-role \
    --role-name "${ROLE_NAME}" >/dev/null || true

  aws ec2 delete-security-group \
    --region "${AWS_REGION}" \
    --group-id "${SG_ID}" >/dev/null || true
fi

trap - ERR

echo
echo "Done. Image pushed (validate with):"
echo "  aws ecr list-images --repository-name ${ECR_REPO} --region ${AWS_REGION}"
echo
echo "If image exists, deploy with:"
echo "  kubectl set image deployment/vllm-neuron-llama31-8b vllm-neuron=${IMAGE_URI} -n ai-example"
echo "  kubectl scale deployment/vllm-neuron-llama31-8b --replicas=1 -n ai-example"
