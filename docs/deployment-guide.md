# Deployment Guide

This guide walks you through deploying the ElasticBeanstalk authentication automation solution step by step.

## Prerequisites

Before starting, ensure you have:

- AWS CLI installed and configured with appropriate permissions
- ElasticBeanstalk CLI (optional, for easier EB management)
- jq installed for JSON processing
- A domain name for your application (optional for testing)

### Required AWS Permissions

Your AWS user/role needs the following permissions:
- CloudFormation: Full access
- Cognito: Full access
- ElasticLoadBalancing: Full access
- EC2: VPC and Security Group management
- ElasticBeanstalk: Full access
- Certificate Manager: Certificate management

## Step 1: Configure Parameters

### 1.1 Update Project Configuration

Edit the parameter files in `cloudformation/parameters/` to match your requirements:

**For Development (`dev-parameters.json`):**
```json
[
  {
    "ParameterKey": "ProjectName",
    "ParameterValue": "your-project-name"
  },
  {
    "ParameterKey": "Environment",
    "ParameterValue": "dev"
  },
  {
    "ParameterKey": "CallbackURLs",
    "ParameterValue": "https://your-domain.com/callback,http://localhost:3000/callback"
  },
  {
    "ParameterKey": "LogoutURLs",
    "ParameterValue": "https://your-domain.com/logout,http://localhost:3000/logout"
  }
]
```

### 1.2 Update .ebextensions Configuration

Modify `.ebextensions/01-cognito-config.config` to use your project name:

```yaml
option_settings:
  aws:elasticbeanstalk:application:environment:
    COGNITO_USER_POOL_ID: '`{"Fn::ImportValue": "your-project-name-dev-UserPoolId"}`'
    COGNITO_CLIENT_ID: '`{"Fn::ImportValue": "your-project-name-dev-UserPoolClientId"}`'
    COGNITO_DOMAIN: '`{"Fn::ImportValue": "your-project-name-dev-UserPoolDomain"}`'
```

## Step 2: Deploy Infrastructure

### 2.1 Validate Configuration

Run the validation script to check your configuration:

```bash
./scripts/validate.sh
```

### 2.2 Deploy CloudFormation Stacks

Run the deployment script:

```bash
./scripts/deploy.sh
```

This script will:
1. Validate CloudFormation templates
2. Deploy Cognito infrastructure
3. Deploy ALB infrastructure
4. Display deployment information

### 2.3 Manual Deployment (Alternative)

If you prefer manual deployment:

```bash
# Deploy Cognito stack
aws cloudformation deploy \
  --template-file cloudformation/cognito-infrastructure.yaml \
  --stack-name your-project-cognito \
  --parameter-overrides file://cloudformation/parameters/dev-parameters.json \
  --capabilities CAPABILITY_IAM \
  --region us-east-1

# Deploy ALB stack (after updating VPC parameters)
aws cloudformation deploy \
  --template-file cloudformation/alb-cognito-integration.yaml \
  --stack-name your-project-alb \
  --parameter-overrides file://cloudformation/parameters/alb-parameters.json \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

## Step 3: Create ElasticBeanstalk Application

### 3.1 Create Application

```bash
# Using EB CLI
eb init your-app-name --region us-east-1

# Or using AWS CLI
aws elasticbeanstalk create-application \
  --application-name your-app-name \
  --description "Application with Cognito authentication"
```

### 3.2 Create Environment

```bash
# Using EB CLI
eb create your-env-name --elb-type application

# Or using AWS CLI
aws elasticbeanstalk create-environment \
  --application-name your-app-name \
  --environment-name your-env-name \
  --solution-stack-name "64bit Amazon Linux 2 v3.4.0 running Python 3.8"
```

## Step 4: Deploy Application with Authentication

### 4.1 Prepare Application Bundle

Create your application with the `.ebextensions` folder:

```
your-app/
├── .ebextensions/
│   ├── 01-cognito-config.config
│   └── 02-alb-listener-rules.config
├── application.py  # Your application code
├── requirements.txt
└── other-files...
```

### 4.2 Deploy Application

```bash
# Using EB CLI
eb deploy

# Or create ZIP and deploy via console
zip -r app.zip . -x "*.git*" "docs/*" "scripts/*" "cloudformation/*"
```

## Step 5: Configure Domain and SSL

### 5.1 Request SSL Certificate

```bash
aws acm request-certificate \
  --domain-name your-domain.com \
  --validation-method DNS \
  --region us-east-1
```

### 5.2 Update ALB Configuration

After certificate is validated, update the ALB stack with the certificate ARN.

### 5.3 Configure DNS

Point your domain to the ALB DNS name:

```
your-domain.com CNAME alb-dns-name.region.elb.amazonaws.com
```

## Step 6: Test Authentication

### 6.1 Access Application

1. Navigate to `https://your-domain.com`
2. You should be redirected to Cognito login page
3. Create a test user account
4. After login, you should be redirected back to your application

### 6.2 Create Test User

```bash
aws cognito-idp admin-create-user \
  --user-pool-id your-user-pool-id \
  --username testuser \
  --user-attributes Name=email,Value=test@example.com \
  --temporary-password TempPass123! \
  --message-action SUPPRESS
```

## Step 7: Monitor and Maintain

### 7.1 CloudWatch Monitoring

Set up CloudWatch alarms for:
- ALB response times
- Error rates
- Cognito authentication failures

### 7.2 Log Analysis

Monitor logs in:
- CloudWatch Logs (ElasticBeanstalk logs)
- ALB access logs
- Cognito authentication logs

## Troubleshooting

### Common Issues

1. **Certificate validation fails**
   - Ensure DNS records are properly configured
   - Wait for DNS propagation (up to 48 hours)

2. **Authentication loop**
   - Check callback URLs in Cognito configuration
   - Verify ALB listener rules are correctly configured

3. **502 Bad Gateway**
   - Check ElasticBeanstalk application health
   - Verify security group configurations

4. **Stack deployment fails**
   - Check CloudFormation events for detailed error messages
   - Ensure IAM permissions are sufficient

### Getting Help

1. Check CloudFormation stack events
2. Review ElasticBeanstalk logs
3. Validate configuration with `./scripts/validate.sh`
4. Check AWS service health dashboard

## Environment-Specific Configurations

### Development Environment
- Use HTTP for local testing
- Enable debug logging
- Relaxed security settings

### Staging Environment
- Production-like configuration
- Performance testing setup
- Limited access controls

### Production Environment
- HTTPS only
- Strict security settings
- Comprehensive monitoring
- Backup and disaster recovery

## Security Best Practices

1. **Use HTTPS everywhere**
2. **Implement proper session management**
3. **Regular security audits**
4. **Monitor authentication logs**
5. **Keep dependencies updated**
6. **Use least privilege IAM policies**

## Cost Optimization

1. **Right-size EC2 instances**
2. **Use reserved instances for production**
3. **Monitor ALB LCU usage**
4. **Optimize Cognito MAU usage**
5. **Set up billing alerts**