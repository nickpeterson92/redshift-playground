# Resource Filtering Logic for deploy-monitor-curses.py

## Current Filtering Approach

### VPC Detection (Lines 265-268)
- Checks for VPCs with:
  1. Tag `Project` = `airline`
  2. Tag `Name` containing `airline`
  3. Tag `Name` = `redshift-vpc-dev` (bootstrap convention)

### Subnet Detection (Lines 279-280)
- Gets ALL subnets from the detected VPC
- No additional filtering needed (VPC already filtered)

### NAT Gateway Detection (Lines 290-293)
- Filters by VPC ID and State='available'
- Optional check - doesn't fail if missing

### Workgroup Detection (Lines 304-338)
- Lists ALL workgroups, then filters by:
  - Workgroup name contains `project_name` (airline)
  - Separates producer vs consumer based on name

### Endpoint Detection (Lines 399-432)
- Lists ALL endpoints, then filters by:
  - Endpoint name contains `project_name` (airline)

### NLB Detection (Lines 442-447)
- First tries exact match: `{project_name}-redshift-nlb`
- Falls back to contains: any NLB with `project_name` in name

### Target Group Detection (Lines 468-477)
- First tries exact match: `{project_name}-consumers`
- Falls back to contains: any TG with `project_name` in name

## Environment Variables Used
- `PROJECT_NAME` (default: 'airline')
- `ENVIRONMENT` (default: 'dev')
- `AWS_REGION` (default: 'us-west-2')

## Naming Conventions Expected
- VPC: `redshift-vpc-{environment}` OR contains project name
- Workgroups: `{project_name}-producer-workgroup`, `{project_name}-consumer-wg-{n}`
- Endpoints: `{project_name}-consumer-wg-{n}-endpoint`
- NLB: `{project_name}-redshift-nlb`
- Target Group: `{project_name}-consumers`

## Tags Expected
- All resources should have `Project` tag = project_name
- VPC should have `Name` tag
- Resources should have `Environment` tag = environment