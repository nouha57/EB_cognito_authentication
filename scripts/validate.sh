#!/bin/bash

# Configuration Validation Script
# This script validates the authentication configuration and deployment

set -e

# Configuration
PROJECT_NAME="eb-auth-demo"
ENVIRONMENT="dev"
REGION="us-east-1"
STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

fail() {
    echo -e "${RED}✗ $1${NC}"
}

# Check if AWS CLI is configured
check_aws_config() {
    info "Checking AWS configuration..."
    
    if aws sts get-caller-identity &> /dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        success "AWS CLI configured (Account: $ACCOUNT_ID)"
        return 0
    else
        fail "AWS CLI not configured or credentials invalid"
        return 1
    fi
}

# Validate CloudFormation templates
validate_templates() {
    info "Validating CloudFormation templates..."
    
    local templates=(
        "cloudformation/cognito-infrastructure.yaml"
        "cloudformation/alb-cognito-integration.yaml"
    )
    
    for template in "${templates[@]}"; do
        if [ -f "$template" ]; then
            if aws cloudformation validate-template --template-body file://$template --region $REGION &> /dev/null; then
                success "Template valid: $template"
            else
                fail "Template invalid: $template"
                return 1
            fi
        else
            fail "Template not found: $template"
            return 1
        fi
    done
    
    return 0
}

# Check parameter files
check_parameters() {
    info "Checking parameter files..."
    
    local param_files=(
        "cloudformation/parameters/dev-parameters.json"
        "cloudformation/parameters/staging-parameters.json"
    )
    
    for param_file in "${param_files[@]}"; do
        if [ -f "$param_file" ]; then
            if jq empty "$param_file" 2>/dev/null; then
                success "Parameter file valid: $param_file"
            else
                fail "Parameter file invalid JSON: $param_file"
                return 1
            fi
        else
            fail "Parameter file not found: $param_file"
            return 1
        fi
    done
    
    return 0
}

# Check .ebextensions files
check_ebextensions() {
    info "Checking .ebextensions configuration..."
    
    local eb_files=(
        ".ebextensions/01-cognito-config.config"
        ".ebextensions/02-alb-listener-rules.config"
    )
    
    for eb_file in "${eb_files[@]}"; do
        if [ -f "$eb_file" ]; then
            success "Configuration file found: $eb_file"
        else
            fail "Configuration file not found: $eb_file"
            return 1
        fi
    done
    
    return 0
}

# Check if stacks exist and are in good state
check_stacks() {
    info "Checking CloudFormation stacks..."
    
    local stacks=(
        "${STACK_PREFIX}-cognito"
        "${STACK_PREFIX}-alb"
    )
    
    for stack in "${stacks[@]}"; do
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack" \
            --query "Stacks[0].StackStatus" \
            --output text \
            --region $REGION 2>/dev/null || echo "NOT_FOUND")
        
        case $status in
            "CREATE_COMPLETE"|"UPDATE_COMPLETE")
                success "Stack healthy: $stack ($status)"
                ;;
            "NOT_FOUND")
                warn "Stack not found: $stack (not deployed yet)"
                ;;
            *)
                fail "Stack in bad state: $stack ($status)"
                return 1
                ;;
        esac
    done
    
    return 0
}

# Test Cognito configuration
test_cognito() {
    info "Testing Cognito configuration..."
    
    local stack_name="${STACK_PREFIX}-cognito"
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &> /dev/null; then
        # Get User Pool ID
        local user_pool_id=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
            --output text \
            --region $REGION)
        
        if [ "$user_pool_id" != "None" ] && [ -n "$user_pool_id" ]; then
            success "Cognito User Pool accessible: $user_pool_id"
            
            # Test User Pool details
            if aws cognito-idp describe-user-pool --user-pool-id "$user_pool_id" --region $REGION &> /dev/null; then
                success "User Pool details accessible"
            else
                fail "Cannot access User Pool details"
                return 1
            fi
        else
            fail "Cannot retrieve User Pool ID from stack outputs"
            return 1
        fi
    else
        warn "Cognito stack not deployed yet"
    fi
    
    return 0
}

# Test ALB configuration
test_alb() {
    info "Testing ALB configuration..."
    
    local stack_name="${STACK_PREFIX}-alb"
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &> /dev/null; then
        # Get ALB ARN
        local alb_arn=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerArn'].OutputValue" \
            --output text \
            --region $REGION)
        
        if [ "$alb_arn" != "None" ] && [ -n "$alb_arn" ]; then
            success "ALB accessible: $alb_arn"
            
            # Test ALB details
            if aws elbv2 describe-load-balancers --load-balancer-arns "$alb_arn" --region $REGION &> /dev/null; then
                success "ALB details accessible"
                
                # Get ALB DNS name
                local alb_dns=$(aws elbv2 describe-load-balancers \
                    --load-balancer-arns "$alb_arn" \
                    --query "LoadBalancers[0].DNSName" \
                    --output text \
                    --region $REGION)
                
                info "ALB DNS Name: $alb_dns"
            else
                fail "Cannot access ALB details"
                return 1
            fi
        else
            fail "Cannot retrieve ALB ARN from stack outputs"
            return 1
        fi
    else
        warn "ALB stack not deployed yet"
    fi
    
    return 0
}

# Generate validation report
generate_report() {
    info "Generating validation report..."
    
    local report_file="validation-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
ElasticBeanstalk Authentication Validation Report
Generated: $(date)
Project: $PROJECT_NAME
Environment: $ENVIRONMENT
Region: $REGION

=== Configuration Files ===
EOF
    
    # Check each file and add to report
    local files=(
        "README.md"
        "cloudformation/cognito-infrastructure.yaml"
        "cloudformation/alb-cognito-integration.yaml"
        "cloudformation/parameters/dev-parameters.json"
        "cloudformation/parameters/staging-parameters.json"
        ".ebextensions/01-cognito-config.config"
        ".ebextensions/02-alb-listener-rules.config"
        "scripts/deploy.sh"
        "scripts/validate.sh"
        "docs/architecture.md"
    )
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo "✓ $file" >> "$report_file"
        else
            echo "✗ $file (missing)" >> "$report_file"
        fi
    done
    
    echo "" >> "$report_file"
    echo "=== AWS Resources ===" >> "$report_file"
    
    # Check stacks
    local stacks=(
        "${STACK_PREFIX}-cognito"
        "${STACK_PREFIX}-alb"
    )
    
    for stack in "${stacks[@]}"; do
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack" \
            --query "Stacks[0].StackStatus" \
            --output text \
            --region $REGION 2>/dev/null || echo "NOT_FOUND")
        
        echo "$stack: $status" >> "$report_file"
    done
    
    success "Validation report generated: $report_file"
}

# Main validation function
main() {
    log "Starting configuration validation..."
    echo
    
    local exit_code=0
    
    # Run all validation checks
    check_aws_config || exit_code=1
    echo
    
    validate_templates || exit_code=1
    echo
    
    check_parameters || exit_code=1
    echo
    
    check_ebextensions || exit_code=1
    echo
    
    check_stacks || exit_code=1
    echo
    
    test_cognito || exit_code=1
    echo
    
    test_alb || exit_code=1
    echo
    
    generate_report
    echo
    
    if [ $exit_code -eq 0 ]; then
        log "All validation checks passed! ✅"
    else
        error "Some validation checks failed. Please review the issues above."
    fi
    
    exit $exit_code
}

# Run main function
main "$@"