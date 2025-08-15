# Traditional Redshift Cluster (Optional)

## Purpose

This deployment is **OPTIONAL** and only needed for:

1. **Initial Data Loading**: If you need to create and load sample data from scratch
2. **Snapshot Storage**: Maintaining a traditional cluster with your baseline data
3. **Learning/Testing**: Understanding traditional Redshift before moving to serverless
4. **Cost Comparison**: Running side-by-side cost analysis

## When You DON'T Need This

You can skip this deployment entirely if:
- ✅ You already have a snapshot with your data
- ✅ You're going straight to serverless architecture
- ✅ You want to minimize costs (serverless only)
- ✅ You're restoring from an existing snapshot

## Architecture

This creates a minimal traditional Redshift cluster with:
- Single ra3.xlplus node (cheapest RA3 option)
- VPC with proper networking (3 AZs)
- Security group for access control
- ~$414/month fixed cost (24/7 running)

## Quick Deploy (If Needed)

```bash
# Only if you need to create initial data
cd traditional
terraform init
terraform apply -var="master_password=YourPassword123!"

# Create snapshot after loading data
aws redshift create-cluster-snapshot \
  --cluster-identifier my-redshift-cluster \
  --snapshot-identifier airline-data-snapshot

# Then destroy to save costs
terraform destroy
```

## Snapshot Management

Once you have a snapshot, you can:
1. **Destroy the traditional cluster** to save costs
2. **Keep the snapshot** (minimal storage cost)
3. **Restore to serverless** when needed

```bash
# List snapshots
aws redshift describe-cluster-snapshots \
  --query 'Snapshots[*].[SnapshotIdentifier,Status,ClusterCreateTime]' \
  --output table

# Delete old snapshots to save storage costs
aws redshift delete-cluster-snapshot \
  --snapshot-identifier old-snapshot-name
```

## Migration to Serverless

After creating your snapshot:

1. **Deploy data-sharing** (which creates its own VPC):
```bash
cd ../data-sharing
terraform init
terraform apply
```

2. **Restore snapshot to producer**:
- Use AWS Console → Redshift Serverless
- Select your producer namespace
- Restore from snapshot

## Cost Optimization

**Traditional Cluster**:
- $414/month continuous
- Consider reserved instances for long-term
- Shut down when not needed

**Serverless Alternative**:
- $0 when paused
- Pay only for usage
- Auto-scaling included

## Files

- `redshift.tf` - Complete traditional deployment
- `terraform.tfvars.example` - Example configuration
- `minimal-redshift.tf.example` - Minimal config without VPC (uses default)

## Important Notes

⚠️ **VPC Creation**: This creates its own VPC. If you want to share a VPC with data-sharing:
1. Deploy traditional first (if needed)
2. Set `create_vpc = false` in data-sharing
3. Use the same `vpc_name`

💡 **Recommendation**: Skip this entirely and go straight to data-sharing with serverless!