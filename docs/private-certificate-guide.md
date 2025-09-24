# Private Certificate Guide

This guide explains how to use private certificates (self-signed or from a private CA) instead of Amazon-issued certificates with the ElasticBeanstalk authentication solution.

## Overview

By default, the solution uses AWS Certificate Manager (ACM) to request and validate public certificates. However, you may want to use private certificates for:

- Development and testing environments
- Internal applications not accessible from the internet
- Organizations with their own Certificate Authority (CA)
- Air-gapped environments

## Private Certificate Options

### 1. Self-Signed Certificates
- Quick to generate
- No external dependencies
- Browsers will show security warnings
- Suitable for development/testing

### 2. Private CA Certificates
- Issued by your organization's CA
- Can be trusted by configuring client browsers/systems
- More secure than self-signed
- Suitable for internal production use

## Quick Start with Private Certificates

### Step 1: Generate or Prepare Certificate

**Option A: Generate Self-Signed Certificate**
```bash
./scripts/generate-private-cert.sh --generate-self-signed -d myapp.example.com -e dev
```

**Option B: Import Existing Certificate**
```bash
# Place your certificate files in the certificates/ directory:
# - certificate.pem (your certificate)
# - private-key.pem (private key)
# - certificate-chain.pem (certificate chain, optional)

./scripts/generate-private-cert.sh --import-existing -d myapp.example.com -e dev
```

### Step 2: Deploy with Private Certificate
```bash
./scripts/deploy.sh --use-private-cert -e dev
```

## Detailed Certificate Management

### Certificate File Requirements

Your certificate files must be in PEM format:

**certificate.pem** - The server certificate:
```
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAKoK/heBjcOuMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNV...
-----END CERTIFICATE-----
```

**private-key.pem** - The private key:
```
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7VJTUt9Us8cKB...
-----END PRIVATE KEY-----
```

**certificate-chain.pem** - The certificate chain (optional):
```
-----BEGIN CERTIFICATE-----
[Intermediate CA Certificate]
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
[Root CA Certificate]
-----END CERTIFICATE-----
```

### Certificate Generation Script Options

```bash
./scripts/generate-private-cert.sh [OPTIONS]

Options:
  -d, --domain DOMAIN     Domain name for the certificate
  -p, --project PROJECT   Project name (default: eb-auth-demo)
  -e, --env ENVIRONMENT   Environment name (default: dev)
  -o, --output DIR        Output directory for certificates (default: certificates)
  --import-existing       Import existing certificate files
  --generate-self-signed  Generate new self-signed certificate
  --help                  Show help message
```

### Examples

**Generate certificate for custom domain:**
```bash
./scripts/generate-private-cert.sh --generate-self-signed \
  -d api.mycompany.internal \
  -p myapp \
  -e production
```

**Import existing certificate:**
```bash
# First, copy your certificate files to certificates/
cp /path/to/your/cert.pem certificates/certificate.pem
cp /path/to/your/key.pem certificates/private-key.pem
cp /path/to/your/chain.pem certificates/certificate-chain.pem

# Then import
./scripts/generate-private-cert.sh --import-existing \
  -d api.mycompany.internal \
  -e production
```

## Deployment Process

### 1. Certificate Import to ACM

The script automatically imports your private certificate to AWS Certificate Manager:

```bash
aws acm import-certificate \
  --certificate fileb://certificates/certificate.pem \
  --private-key fileb://certificates/private-key.pem \
  --certificate-chain fileb://certificates/certificate-chain.pem
```

### 2. Parameter File Creation

A parameter file is created with the certificate ARN:

```json
[
  {
    "ParameterKey": "CertificateArn",
    "ParameterValue": "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  },
  {
    "ParameterKey": "UsePrivateCertificate",
    "ParameterValue": "true"
  }
]
```

### 3. CloudFormation Deployment

The ALB stack uses the imported certificate ARN instead of creating a new ACM certificate.

## Security Considerations

### Certificate Storage
- Private keys are stored securely in ACM
- Local certificate files should be deleted after import
- Use appropriate file permissions (600 for private keys)

### Certificate Validation
- Self-signed certificates will trigger browser warnings
- Configure client systems to trust your CA for private CA certificates
- Consider using certificate pinning for additional security

### Certificate Rotation
- Monitor certificate expiration dates
- Plan for certificate renewal and rotation
- Update ACM with new certificates before expiration

## Troubleshooting

### Common Issues

**1. Certificate Import Fails**
```
Error: Failed to import certificate to ACM
```
- Check certificate file format (must be PEM)
- Verify private key matches certificate
- Ensure AWS credentials have ACM permissions

**2. Browser Security Warnings**
```
"Your connection is not private" or "Certificate not trusted"
```
- Expected behavior for self-signed certificates
- Add certificate to browser's trusted store for testing
- Use private CA certificates for production

**3. ALB Health Check Failures**
```
Target group shows unhealthy targets
```
- Verify certificate domain matches ALB DNS name
- Check security group configurations
- Ensure application responds to health checks

### Validation Commands

**Check certificate details:**
```bash
openssl x509 -in certificates/certificate.pem -text -noout
```

**Verify private key:**
```bash
openssl rsa -in certificates/private-key.pem -check -noout
```

**Test certificate and key match:**
```bash
cert_md5=$(openssl x509 -noout -modulus -in certificates/certificate.pem | openssl md5)
key_md5=$(openssl rsa -noout -modulus -in certificates/private-key.pem | openssl md5)
echo "Certificate: $cert_md5"
echo "Private Key: $key_md5"
```

**Check ACM certificate:**
```bash
aws acm list-certificates --region us-east-1
aws acm describe-certificate --certificate-arn "your-cert-arn" --region us-east-1
```

## Best Practices

### Development Environment
- Use self-signed certificates for quick setup
- Include localhost and development domains in SAN
- Document certificate trust procedures for team members

### Staging Environment
- Use certificates that match production setup
- Test certificate renewal procedures
- Validate monitoring and alerting

### Production Environment
- Use certificates from trusted CA (internal or external)
- Implement certificate monitoring and alerting
- Plan for certificate rotation and emergency procedures
- Use certificate transparency monitoring

### Certificate Management
- Store certificates securely (encrypted storage, access controls)
- Maintain certificate inventory and expiration tracking
- Implement automated certificate renewal where possible
- Regular security audits of certificate usage

## Integration with CI/CD

### Automated Certificate Deployment

```bash
# Example CI/CD pipeline step
- name: Deploy with Private Certificate
  run: |
    # Import certificate (if not already in ACM)
    ./scripts/generate-private-cert.sh --import-existing -e $ENVIRONMENT
    
    # Deploy infrastructure
    ./scripts/deploy.sh --use-private-cert -e $ENVIRONMENT
```

### Environment-Specific Certificates

```bash
# Development
./scripts/deploy.sh --use-private-cert -e dev

# Staging  
./scripts/deploy.sh --use-private-cert -e staging

# Production
./scripts/deploy.sh --use-private-cert -e prod
```

## Cost Considerations

- ACM imported certificates are free
- No additional charges for private certificates in ACM
- Standard ALB and ElasticBeanstalk charges apply
- Consider certificate management overhead

## Compliance and Governance

- Document certificate sources and validation procedures
- Implement certificate lifecycle management
- Regular security assessments
- Compliance with organizational PKI policies