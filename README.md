# ElasticBeanstalk Authentication Automation

This project provides automated authentication integration for ElasticBeanstalk applications using Application Load Balancer (ALB) and Amazon Cognito.

## Overview

The solution eliminates manual configuration steps by:
- Provisioning required AWS services via CloudFormation
- Automating Cognito integration through .ebextensions
- Ensuring consistent deployments across environments

## Project Structure

```
├── cloudformation/
│   ├── cognito-infrastructure.yaml    # Cognito User Pool and App Client
│   ├── alb-cognito-integration.yaml   # ALB with Cognito authentication
│   └── parameters/                    # Environment-specific parameters
├── .ebextensions/
│   ├── 01-cognito-config.config      # Cognito environment variables
│   ├── 02-alb-listener-rules.config  # ALB authentication rules
│   └── 03-security-groups.config     # Security group configurations
├── scripts/
│   ├── deploy.sh                     # Deployment automation script
│   └── validate.sh                   # Configuration validation
└── docs/
    ├── architecture.md               # Solution architecture
    ├── deployment-guide.md           # Step-by-step deployment
    └── troubleshooting.md            # Common issues and solutions
```

## Quick Start

1. Configure AWS credentials and region
2. Update parameters in `cloudformation/parameters/`
3. Run deployment script: `./scripts/deploy.sh`
4. Deploy your application to ElasticBeanstalk

## Features

- Automated Cognito User Pool creation
- ALB authentication rule configuration
- Environment-specific parameter management
- Security group automation
- Comprehensive documentation

## Requirements

- AWS CLI configured
- ElasticBeanstalk CLI (optional)
- Appropriate IAM permissions for CloudFormation and ElasticBeanstalk