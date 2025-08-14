# Redshift NLB Test Instance

This creates a small EC2 instance within the VPC to test NLB connectivity to Redshift consumers.

## Why?

- The NLB is internal-only (for security)
- Testing from outside the VPC isn't possible
- This EC2 instance runs inside the VPC and can access the NLB

## Deployment

```bash
# From this directory
terraform init
terraform apply
```

## Running Tests

### Option 1: Seamless execution from your terminal

```bash
# Set password
export REDSHIFT_PASSWORD='your-password-here'

# Run quick test
./run-remote-test.sh

# Run full bash test
./run-remote-test.sh bash

# Run Python load distribution test
./run-remote-test.sh python
```

### Option 2: SSH into instance and run manually

```bash
# SSH into instance
ssh -i test-instance.pem ec2-user@$(terraform output -raw instance_public_ip)

# Once connected:
cd redshift-tests
export REDSHIFT_PASSWORD='your-password-here'

# Run tests
./test-nlb.sh
python3 test-nlb-connection.py
```

## What the tests do

1. **test-nlb.sh**: Runs SQL queries through the NLB to verify connectivity and data sharing
2. **test-nlb-connection.py**: Tests load distribution across consumer workgroups
3. Both scripts access the `airline_shared` database through the NLB

## Cleanup

```bash
terraform destroy
```

## Security Notes

- EC2 instance only allows SSH from your IP (71.231.5.129/32)
- Instance is in the same VPC as Redshift
- No Redshift passwords are stored in code
- Private key is generated and stored locally only