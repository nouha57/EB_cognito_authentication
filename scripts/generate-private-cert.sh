#!/bin/bash

# Private Certificate Generation Script
# This script helps generate self-signed certificates or prepare private certificates for deployment

set -e

# Configuration
PROJECT_NAME="eb-auth-demo"
ENVIRONMENT="dev"
DOMAIN_NAME="******"
CERT_DIR="certificates"

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
    exit 1
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN     Domain name for the certificate (default: $DOMAIN_NAME)"
    echo "  -p, --project PROJECT   Project name (default: $PROJECT_NAME)"
    echo "  -e, --env ENVIRONMENT   Environment name (default: $ENVIRONMENT)"
    echo "  -o, --output DIR        Output directory for certificates (default: $CERT_DIR)"
    echo "  --import-existing       Import existing certificate files"
    echo "  --generate-self-signed  Generate new self-signed certificate"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --generate-self-signed -d myapp.com"
    echo "  $0 --import-existing -d myapp.com"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -e|--env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -o|--output)
                CERT_DIR="$2"
                shift 2
                ;;
            --import-existing)
                ACTION="import"
                shift
                ;;
            --generate-self-signed)
                ACTION="generate"
                shift
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
    
    if [ -z "$ACTION" ]; then
        error "Please specify either --generate-self-signed or --import-existing"
    fi
}

# Create certificate directory
create_cert_directory() {
    log "Creating certificate directory: $CERT_DIR"
    mkdir -p "$CERT_DIR"
}

# Generate self-signed certificate
generate_self_signed() {
    log "Generating self-signed certificate for domain: $DOMAIN_NAME"
    
    # Create OpenSSL configuration file
    cat > "$CERT_DIR/openssl.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Organization
OU = Organizational Unit
CN = $DOMAIN_NAME

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN_NAME
DNS.2 = *.$DOMAIN_NAME
EOF

    # Generate private key
    info "Generating private key..."
    openssl genrsa -out "$CERT_DIR/private-key.pem" 2048
    
    # Generate certificate signing request
    info "Generating certificate signing request..."
    openssl req -new -key "$CERT_DIR/private-key.pem" -out "$CERT_DIR/cert.csr" -config "$CERT_DIR/openssl.conf"
    
    # Generate self-signed certificate
    info "Generating self-signed certificate..."
    openssl x509 -req -in "$CERT_DIR/cert.csr" -signkey "$CERT_DIR/private-key.pem" -out "$CERT_DIR/certificate.pem" -days 365 -extensions v3_req -extfile "$CERT_DIR/openssl.conf"
    
    # Create certificate chain (for self-signed, it's just the certificate)
    cp "$CERT_DIR/certificate.pem" "$CERT_DIR/certificate-chain.pem"
    
    # Set appropriate permissions
    chmod 600 "$CERT_DIR/private-key.pem"
    chmod 644 "$CERT_DIR/certificate.pem"
    chmod 644 "$CERT_DIR/certificate-chain.pem"
    
    log "Self-signed certificate generated successfully!"
    info "Certificate files created:"
    info "  - Private Key: $CERT_DIR/private-key.pem"
    info "  - Certificate: $CERT_DIR/certificate.pem"
    info "  - Certificate Chain: $CERT_DIR/certificate-chain.pem"
}

# Import existing certificate
import_existing() {
    log "Importing existing certificate files..."
    
    # Check for required files
    local required_files=("certificate.pem" "private-key.pem")
    local optional_files=("certificate-chain.pem")
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$CERT_DIR/$file" ]; then
            error "Required certificate file not found: $CERT_DIR/$file"
        fi
    done
    
    # Validate certificate files
    info "Validating certificate files..."
    
    # Check private key
    if ! openssl rsa -in "$CERT_DIR/private-key.pem" -check -noout &> /dev/null; then
        error "Invalid private key file: $CERT_DIR/private-key.pem"
    fi
    
    # Check certificate
    if ! openssl x509 -in "$CERT_DIR/certificate.pem" -text -noout &> /dev/null; then
        error "Invalid certificate file: $CERT_DIR/certificate.pem"
    fi
    
    # Check certificate chain if it exists
    if [ -f "$CERT_DIR/certificate-chain.pem" ]; then
        if ! openssl x509 -in "$CERT_DIR/certificate-chain.pem" -text -noout &> /dev/null; then
            warn "Invalid certificate chain file: $CERT_DIR/certificate-chain.pem"
        fi
    else
        warn "Certificate chain file not found. Creating empty chain file."
        touch "$CERT_DIR/certificate-chain.pem"
    fi
    
    # Verify certificate and private key match
    cert_modulus=$(openssl x509 -noout -modulus -in "$CERT_DIR/certificate.pem" | openssl md5)
    key_modulus=$(openssl rsa -noout -modulus -in "$CERT_DIR/private-key.pem" | openssl md5)
    
    if [ "$cert_modulus" != "$key_modulus" ]; then
        error "Certificate and private key do not match!"
    fi
    
    log "Certificate files imported and validated successfully!"
}

# Import certificate to ACM and create parameter file
import_to_acm_and_create_params() {
    log "Importing certificate to AWS Certificate Manager..."
    
    # Import certificate to ACM
    local import_cmd="aws acm import-certificate"
    import_cmd="$import_cmd --certificate fileb://$CERT_DIR/certificate.pem"
    import_cmd="$import_cmd --private-key fileb://$CERT_DIR/private-key.pem"
    
    if [ -f "$CERT_DIR/certificate-chain.pem" ] && [ -s "$CERT_DIR/certificate-chain.pem" ]; then
        import_cmd="$import_cmd --certificate-chain fileb://$CERT_DIR/certificate-chain.pem"
    fi
    
    # Execute import and capture certificate ARN
    local cert_arn
    if cert_arn=$(eval $import_cmd --query 'CertificateArn' --output text 2>/dev/null); then
        log "Certificate imported successfully to ACM"
        info "Certificate ARN: $cert_arn"
    else
        error "Failed to import certificate to ACM. Please check your AWS credentials and certificate files."
    fi
    
    # Create parameter file with certificate ARN
    local param_file="cloudformation/parameters/${ENVIRONMENT}-private-cert-parameters.json"
    
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
    "ParameterKey": "ElasticBeanstalkEnvironmentName",
    "ParameterValue": "${PROJECT_NAME}-${ENVIRONMENT}-env"
  },
  {
    "ParameterKey": "CertificateArn",
    "ParameterValue": "$cert_arn"
  },
  {
    "ParameterKey": "UsePrivateCertificate",
    "ParameterValue": "true"
  }
]
EOF
    
    log "Parameter file created: $param_file"
    
    # Store certificate ARN for reference
    echo "$cert_arn" > "$CERT_DIR/certificate-arn.txt"
    log "Certificate ARN saved to: $CERT_DIR/certificate-arn.txt"
}

# Display certificate information
show_certificate_info() {
    log "Certificate Information:"
    echo ""
    
    if [ -f "$CERT_DIR/certificate.pem" ]; then
        echo "=== Certificate Details ==="
        openssl x509 -in "$CERT_DIR/certificate.pem" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:|DNS:)"
        echo ""
    fi
    
    echo "=== Files Created ==="
    ls -la "$CERT_DIR/"
    echo ""
    
    echo "=== Next Steps ==="
    echo "1. Review the generated parameter file: cloudformation/parameters/${ENVIRONMENT}-private-cert-parameters.json"
    echo "2. Update your deployment script to use the new parameter file"
    echo "3. Deploy the ALB stack with: ./scripts/deploy.sh --use-private-cert"
    echo "4. Ensure your DNS points to the ALB after deployment"
    echo ""
    
    if [ "$ACTION" = "generate" ]; then
        warn "This is a self-signed certificate. Browsers will show security warnings."
        warn "For production use, obtain a certificate from a trusted CA."
    fi
}

# Main function
main() {
    log "Starting private certificate management..."
    
    parse_args "$@"
    create_cert_directory
    
    case $ACTION in
        generate)
            generate_self_signed
            ;;
        import)
            import_existing
            ;;
    esac
    
    import_to_acm_and_create_params
    show_certificate_info
    
    log "Certificate management completed successfully! 🎉"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it first."
    fi
}

# Run main function
check_prerequisites
main "$@"
