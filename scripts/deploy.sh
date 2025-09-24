#!/bin/bash

# ElasticBeanstalk Authentication Automation Deployment Script
# This script deploys the complete authentication solution

set -e

# Configuration
PROJECT_NAME="eb-auth-demos22d"
ENVIRONMENT="dev"
REGION="us-east-1"
STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"
USE_PRIVATE_CERT=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Installing via package manager..."
        if command -v brew &> /dev/null; then
            brew install jq
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        else
            error "Could not install jq. Please install it manually."
        fi
    fi
    
    log "Prerequisites check completed ✓"
}

# Validate CloudFormation templates
validate_templates() {
    log "Validating CloudFormation templates..."
    
    aws cloudformation validate-template \
        --template-body file://cloudformation/cognito-infrastructure.yaml \
        --region $REGION > /dev/null
    
    aws cloudformation validate-template \
        --template-body file://cloudformation/alb-cognito-integration.yaml \
        --region $REGION > /dev/null
    
    log "Template validation completed ✓"
}

# Deploy Cognito infrastructure
deploy_cognito() {
    log "Deploying Cognito infrastructure..."
    
    STACK_NAME="${STACK_PREFIX}-cognito"
    
    aws cloudformation deploy \
        --template-file cloudformation/cognito-infrastructure.yaml \
        --stack-name $STACK_NAME \
        --parameter-overrides file://cloudformation/parameters/dev-parameters.json \
        --capabilities CAPABILITY_IAM \
        --region $REGION \
        --no-fail-on-empty-changeset
    
    if [ $? -eq 0 ]; then
        log "Cognito infrastructure deployed successfully ✓"
    else
        error "Failed to deploy Cognito infrastructure"
    fi
}

# Get VPC and subnet information
get_vpc_info() {
    log "Getting VPC and subnet information..."
    
    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" \
        --output text \
        --region $REGION)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        error "No default VPC found. Please specify VPC ID manually."
    fi
    
    # Get subnets in different AZs
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "Subnets[0:2].SubnetId" \
        --output text \
        --region $REGION | tr '\t' ',')
    
    if [ -z "$SUBNET_IDS" ]; then
        error "No subnets found in VPC $VPC_ID"
    fi
    
    log "Using VPC: $VPC_ID"
    log "Using Subnets: $SUBNET_IDS"
}

# Deploy ALB infrastructure
deploy_alb() {
    log "Deploying ALB infrastructure..."
    
    STACK_NAME="${STACK_PREFIX}-alb"
    local param_file="/tmp/alb-parameters.json"
    
    if [ "$USE_PRIVATE_CERT" = true ]; then
        log "Using private certificate configuration..."
        
        # Use the private certificate parameter file as base
        local cert_param_file="cloudformation/parameters/${ENVIRONMENT}-private-cert-parameters.json"
        
        # Add VPC information to the private cert parameters
        jq --arg vpc_id "$VPC_ID" --arg subnet_ids "$SUBNET_IDS" '
        . + [
          {
            "ParameterKey": "VpcId",
            "ParameterValue": $vpc_id
          },
          {
            "ParameterKey": "SubnetIds", 
            "ParameterValue": $subnet_ids
          }
        ]' "$cert_param_file" > "$param_file"
        
    else
        log "Using ACM certificate configuration..."
        
        # Create standard parameter file for ACM certificate
        cat > "$param_file" << EOF
[
  {
    "ParameterKey": "ProjectName",
    "ParameterValue": "$PROJECT_NAME"
  },
  {
    "ParameterKey": "Environment",
    "ParameterValue": "$ENVIRONMENT"
  },
  {
    "ParameterKey": "VpcId",
    "ParameterValue": "$VPC_ID"
  },
  {
    "ParameterKey": "SubnetIds",
    "ParameterValue": "$SUBNET_IDS"
  },
  {
    "ParameterKey": "ElasticBeanstalkEnvironmentName",
    "ParameterValue": "${PROJECT_NAME}-${ENVIRONMENT}-env"
  },
  {
    "ParameterKey": "CertificateArn",
    "ParameterValue": ""
  },
  {
    "ParameterKey": "UsePrivateCertificate",
    "ParameterValue": "false"
  }
]
EOF
    fi
    
    aws cloudformation deploy \
        --template-file cloudformation/alb-cognito-integration.yaml \
        --stack-name $STACK_NAME \
        --parameter-overrides file://$param_file \
        --capabilities CAPABILITY_IAM \
        --region $REGION \
        --no-fail-on-empty-changeset
    
    if [ $? -eq 0 ]; then
        log "ALB infrastructure deployed successfully ✓"
    else
        error "Failed to deploy ALB infrastructure"
    fi
    
    # Clean up temporary file
    rm -f "$param_file"
}

# Display deployment information
show_deployment_info() {
    log "Deployment completed successfully! 🎉"
    echo
    echo "=== Deployment Information ==="
    
    # Get Cognito information
    USER_POOL_ID=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-cognito" \
        --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
        --output text \
        --region $REGION)
    
    USER_POOL_DOMAIN=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-cognito" \
        --query "Stacks[0].Outputs[?OutputKey=='UserPoolDomain'].OutputValue" \
        --output text \
        --region $REGION)
    
    # Get ALB information
    ALB_DNS=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-alb" \
        --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDNSName'].OutputValue" \
        --output text \
        --region $REGION)
    
    echo "Cognito User Pool ID: $USER_POOL_ID"
    echo "Cognito Domain: $USER_POOL_DOMAIN"
    echo "ALB DNS Name: $ALB_DNS"
    echo
    echo "Next steps:"
    echo "1. Create an ElasticBeanstalk application and environment"
    echo "2. Deploy your application with the .ebextensions configurations"
    echo "3. Update your application's callback URLs in Cognito"
    echo "4. Test the authentication flow"
    echo
    echo "For detailed instructions, see docs/deployment-guide.md"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --use-private-cert)
                USE_PRIVATE_CERT=true
                shift
                ;;
            -p|--project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -e|--env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Update stack prefix after parsing args
    STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p, --project PROJECT   Project name (default: $PROJECT_NAME)"
    echo "  -e, --env ENVIRONMENT   Environment name (default: $ENVIRONMENT)"
    echo "  -r, --region REGION     AWS region (default: $REGION)"
    echo "  --use-private-cert      Use private certificate instead of ACM"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with default settings"
    echo "  $0 --use-private-cert                # Deploy with private certificate"
    echo "  $0 -p myapp -e prod --use-private-cert  # Deploy production with private cert"
}

# Check private certificate prerequisites
check_private_cert() {
    if [ "$USE_PRIVATE_CERT" = true ]; then
        log "Checking private certificate configuration..."
        
        local cert_param_file="cloudformation/parameters/${ENVIRONMENT}-private-cert-parameters.json"
        
        if [ ! -f "$cert_param_file" ]; then
            error "Private certificate parameter file not found: $cert_param_file"
            echo "Please run: ./scripts/generate-private-cert.sh --generate-self-signed -e $ENVIRONMENT"
            exit 1
        fi
        
        # Validate parameter file
        if ! jq empty "$cert_param_file" 2>/dev/null; then
            error "Invalid JSON in private certificate parameter file: $cert_param_file"
        fi
        
        # Check if required parameters are present
        local required_params=("CertificateArn" "UsePrivateCertificate")
        for param in "${required_params[@]}"; do
            if ! jq -e ".[] | select(.ParameterKey == \"$param\")" "$cert_param_file" > /dev/null; then
                error "Missing required parameter '$param' in $cert_param_file"
            fi
        done
        
        log "Private certificate configuration validated ✓"
    fi
}
# Main deployment function
main() {
    log "Starting ElasticBeanstalk Authentication Automation deployment..."
    
    parse_args "$@"
    check_prerequisites
    check_private_cert
    validate_templates
    deploy_cognito
    get_vpc_info
    deploy_alb
    show_deployment_info
}

# Run main function
main "$@"