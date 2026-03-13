#!/bin/bash

# Terraform Backend Management Script
# Creates/Destroys S3 bucket and DynamoDB table for Terraform remote state

set -e  # Exit on any error

# Configuration variables
BUCKET_NAME="352-demo-dev-s3b-tfstate-backend"
DYNAMODB_TABLE="352-demo-dev-ddb-tfstate-lock"
AWS_REGION="us-east-1"
ENVIRONMENT="dev"
PROJECT="352-demo"
STACK_LEVEL="level-0-networking"
OWNER="devops-team"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_action() {
    echo -e "${CYAN}[ACTION]${NC} $1"
}

# Function to show usage
show_usage() {
    cat <<EOF
Usage: $0 [COMMAND]

Commands:
    create      Create Terraform backend infrastructure (S3 + DynamoDB)
    destroy     Destroy Terraform backend infrastructure
    validate    Validate existing backend infrastructure
    status      Show status of backend infrastructure
    help        Show this help message

Examples:
    $0 create           # Create backend infrastructure
    $0 destroy          # Destroy backend infrastructure
    $0 validate         # Check if backend exists and is accessible
    $0 status           # Show current status

Configuration:
    Bucket Name:     $BUCKET_NAME
    DynamoDB Table:  $DYNAMODB_TABLE
    AWS Region:      $AWS_REGION
    Environment:     $ENVIRONMENT
    Project:         $PROJECT

EOF
}

# Function to check if AWS CLI is installed and configured
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    local aws_account=$(aws sts get-caller-identity --query 'Account' --output text)
    local aws_user=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    print_success "AWS CLI configured for account: $aws_account"
    print_status "Running as: $aws_user"
}

# Function to check if resources exist
check_resources_exist() {
    local s3_exists=false
    local dynamodb_exists=false
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
        s3_exists=true
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &>/dev/null; then
        dynamodb_exists=true
    fi
    
    echo "$s3_exists,$dynamodb_exists"
}

# Function to create S3 bucket
create_s3_bucket() {
    print_status "Creating S3 bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
        print_warning "S3 bucket $BUCKET_NAME already exists"
        return 0
    fi
    
    local max_attempts=8
    local attempt=1
    local delay_seconds=3
    local output=""

    while [ $attempt -le $max_attempts ]; do
        # Create bucket with region constraint if not us-east-1
        if [ "$AWS_REGION" = "us-east-1" ]; then
            output=$(aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>&1) && rc=0 || rc=$?
        else
            output=$(aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION" 2>&1) && rc=0 || rc=$?
        fi

        if [ $rc -eq 0 ]; then
            print_success "S3 bucket created successfully"
            return 0
        fi

        # Handle transient/conflict conditions gracefully.
        if echo "$output" | grep -Eq "OperationAborted|conflicting conditional operation|BucketAlreadyOwnedByYou"; then
            if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
                print_warning "S3 bucket $BUCKET_NAME already exists (or became available during retries)"
                return 0
            fi

            if [ $attempt -lt $max_attempts ]; then
                print_warning "S3 create attempt $attempt/$max_attempts hit transient conflict. Retrying in ${delay_seconds}s..."
                sleep "$delay_seconds"
                attempt=$((attempt + 1))
                delay_seconds=$((delay_seconds + 2))
                continue
            fi
        fi

        print_error "Failed to create S3 bucket: $output"
        return 1
    done

    print_error "Failed to create S3 bucket after $max_attempts attempts"
    return 1
}

# Function to configure S3 bucket settings
configure_s3_bucket() {
    print_status "Configuring S3 bucket settings..."

    # Bucket creation may be eventually consistent. Wait until S3 confirms access.
    local max_wait_attempts=10
    local wait_attempt=1
    while ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; do
        if [ $wait_attempt -ge $max_wait_attempts ]; then
            print_error "S3 bucket $BUCKET_NAME is not accessible after waiting."
            return 1
        fi
        print_warning "Waiting for S3 bucket availability ($wait_attempt/$max_wait_attempts)..."
        sleep 3
        wait_attempt=$((wait_attempt + 1))
    done
    
    # Enable versioning
    print_status "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    print_status "Enabling server-side encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    # Block all public access
    print_status "Blocking public access..."
    aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --region "$AWS_REGION" \
    --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'
    
    # Add bucket policy for additional security
    print_status "Setting bucket policy..."
    BUCKET_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}/*",
                "arn:aws:s3:::${BUCKET_NAME}"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
)
    
    echo "$BUCKET_POLICY" | aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --policy file:///dev/stdin
    
    # Add tags
    print_status "Adding tags..."
    aws s3api put-bucket-tagging \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --tagging 'TagSet=[
            {Key=Environment,Value='$ENVIRONMENT'},
            {Key=Project,Value='$PROJECT'},
            {Key=Purpose,Value=TerraformBackend},
            {Key=ManagedBy,Value=terraform},
            {Key=StackLevel,Value='$STACK_LEVEL'},
            {Key=Owner,Value='$OWNER'}
        ]'
    
    print_success "S3 bucket configured successfully"
}

# Function to create DynamoDB table for state locking
create_dynamodb_table() {
    print_status "Creating DynamoDB table: $DYNAMODB_TABLE"
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &>/dev/null; then
        print_warning "DynamoDB table $DYNAMODB_TABLE already exists"
        return 0
    fi
    
    # Create DynamoDB table
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --tags Key=Environment,Value="$ENVIRONMENT" \
               Key=Project,Value="$PROJECT" \
               Key=Purpose,Value="TerraformStateLock" \
               Key=ManagedBy,Value="terraform" \
               Key=StackLevel,Value="$STACK_LEVEL" \
               Key=Owner,Value="$OWNER"
    
    # Wait for table to be active
    print_status "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION"
    
    print_success "DynamoDB table created successfully"
}

# Function to destroy S3 bucket
destroy_s3_bucket() {
    print_status "Destroying S3 bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
        print_warning "S3 bucket $BUCKET_NAME does not exist"
        return 0
    fi
    
    # Check if bucket has objects (including versions)
    local object_count=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query 'length(Versions[])' --output text 2>/dev/null || echo "0")
    local delete_marker_count=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query 'length(DeleteMarkers[])' --output text 2>/dev/null || echo "0")
    
    if [ "$object_count" != "0" ] || [ "$delete_marker_count" != "0" ]; then
        print_warning "Bucket contains objects or versions. Emptying bucket first..."
        
        # Delete all object versions
        aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | \
        while read key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --region "$AWS_REGION" --key "$key" --version-id "$version_id" >/dev/null
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | \
        while read key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --region "$AWS_REGION" --key "$key" --version-id "$version_id" >/dev/null
            fi
        done
        
        print_status "Bucket emptied successfully"
    fi
    
    # Delete bucket
    aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
    print_success "S3 bucket deleted successfully"
}

# Function to destroy DynamoDB table
destroy_dynamodb_table() {
    print_status "Destroying DynamoDB table: $DYNAMODB_TABLE"
    
    # Check if table exists
    if ! aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &>/dev/null; then
        print_warning "DynamoDB table $DYNAMODB_TABLE does not exist"
        return 0
    fi
    
    # Delete table
    aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" >/dev/null
    
    # Wait for table to be deleted
    print_status "Waiting for DynamoDB table to be deleted..."
    aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION"
    
    print_success "DynamoDB table deleted successfully"
}

# Function to display backend configuration
display_backend_config() {
    print_success "Backend infrastructure ready!"
    echo
    print_status "Use this backend configuration in your Terraform files:"
    echo
    cat <<EOF
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "path/to/your/terraform.tfstate"
    region         = "$AWS_REGION"
    use_lockfile   = true
    encrypt        = true
  }
}
EOF
    echo
    print_status "Example for your current lv-0 networking VPC configuration:"
    echo
    cat <<EOF
terraform {
  required_version = "~> 1.13.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.12.0"
    }
  }

  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "dev/lv-0-networking/vpc/terraform.tfstate"
    region         = "$AWS_REGION"
    use_lockfile   = true
    encrypt        = true
  }
}
EOF
}

# Function to validate backend setup
validate_backend() {
    print_status "Validating backend setup..."
    
    local validation_passed=true
    
    # Test S3 bucket access
    if aws s3 ls "s3://$BUCKET_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_success "✓ S3 bucket is accessible"
    else
        print_error "✗ S3 bucket is not accessible"
        validation_passed=false
    fi
    
    # Test DynamoDB table access
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &>/dev/null; then
        print_success "✓ DynamoDB table is accessible"
    else
        print_error "✗ DynamoDB table is not accessible"
        validation_passed=false
    fi
    
    if [ "$validation_passed" = true ]; then
        print_success "Backend validation completed successfully"
        return 0
    else
        print_error "Backend validation failed"
        return 1
    fi
}

# Function to show status
show_status() {
    print_status "Checking backend infrastructure status..."
    echo
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
        print_success "✓ S3 Bucket: $BUCKET_NAME (exists)"
        
        # Get bucket details
        local versioning=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query 'Status' --output text 2>/dev/null || echo "None")
        local encryption=$(aws s3api get-bucket-encryption --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null || echo "None")
        
        echo "    - Versioning: $versioning"
        echo "    - Encryption: $encryption"
    else
        print_error "✗ S3 Bucket: $BUCKET_NAME (not found)"
    fi
    
    echo
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &>/dev/null; then
        print_success "✓ DynamoDB Table: $DYNAMODB_TABLE (exists)"
        
        # Get table details
        local table_status=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" --query 'Table.TableStatus' --output text)
        local read_capacity=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" --query 'Table.ProvisionedThroughput.ReadCapacityUnits' --output text)
        local write_capacity=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" --query 'Table.ProvisionedThroughput.WriteCapacityUnits' --output text)
        
        echo "    - Status: $table_status"
        echo "    - Read Capacity: $read_capacity"
        echo "    - Write Capacity: $write_capacity"
    else
        print_error "✗ DynamoDB Table: $DYNAMODB_TABLE (not found)"
    fi
    
    echo
}

# Function to create backend infrastructure
create_backend() {
    echo "========================================"
    echo "   Creating Terraform Backend          "
    echo "========================================"
    echo
    
    check_prerequisites
    echo
    
    create_s3_bucket
    echo
    
    configure_s3_bucket
    echo
    
    create_dynamodb_table
    echo
    
    validate_backend
    echo
    
    display_backend_config
    
    echo
    print_success "Backend creation completed successfully! 🚀"
    print_status "You can now run 'terraform init' in your Terraform project."
}

# Function to destroy backend infrastructure
destroy_backend() {
    echo "========================================"
    echo "   Destroying Terraform Backend        "
    echo "========================================"
    echo
    
    # Safety check
    read -p "⚠️  Are you sure you want to destroy the Terraform backend? This action cannot be undone! (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Operation cancelled by user."
        exit 0
    fi
    
    check_prerequisites
    echo
    
    # Check what exists
    IFS=',' read -r s3_exists dynamodb_exists <<< "$(check_resources_exist)"
    
    if [ "$s3_exists" = "false" ] && [ "$dynamodb_exists" = "false" ]; then
        print_warning "No backend infrastructure found to destroy."
        exit 0
    fi
    
    print_warning "⚠️  DANGER: This will permanently delete your Terraform state storage!"
    print_warning "⚠️  Make sure you have backed up any important state files!"
    echo
    
    read -p "Type 'DESTROY' to confirm: " -r
    echo
    
    if [[ $REPLY != "DESTROY" ]]; then
        print_status "Operation cancelled. You must type 'DESTROY' to confirm."
        exit 0
    fi
    
    if [ "$dynamodb_exists" = "true" ]; then
        destroy_dynamodb_table
        echo
    fi
    
    if [ "$s3_exists" = "true" ]; then
        destroy_s3_bucket
        echo
    fi
    
    print_success "Backend infrastructure destroyed successfully! 💥"
    print_warning "Remember to update your Terraform configurations to remove the backend block."
}

# Main function
main() {
    local command="${1:-help}"
    
    case "$command" in
        "create")
            create_backend
            ;;
        "destroy")
            destroy_backend
            ;;
        "validate")
            echo "========================================"
            echo "   Validating Terraform Backend        "
            echo "========================================"
            echo
            check_prerequisites
            echo
            validate_backend
            ;;
        "status")
            echo "========================================"
            echo "   Terraform Backend Status            "
            echo "========================================"
            echo
            check_prerequisites
            echo
            show_status
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
