# How to Connect to Your Redshift Cluster

## Connection Options

### 1. AWS Query Editor V2 (Easiest - No Setup Required)
- Go to AWS Console → Amazon Redshift → Query Editor V2
- Click "Database" → Add connection
- Select your cluster and enter credentials
- Start querying immediately in the browser

### 2. SQL Workbench/J (Free Desktop Client)
1. Download from: http://www.sql-workbench.eu/
2. Download Redshift JDBC driver: https://docs.aws.amazon.com/redshift/latest/mgmt/configure-jdbc-connection.html
3. Configure connection with the endpoint from Terraform output

### 3. DBeaver (Free, Multi-Database Client)
1. Download from: https://dbeaver.io/
2. Create new connection → Select Amazon Redshift
3. Use the endpoint and credentials from Terraform

### 4. psql Command Line
```bash
# Install psql if needed
brew install postgresql  # macOS
sudo apt-get install postgresql-client  # Ubuntu

# Connect using the command from Terraform output
psql -h <endpoint> -p 5439 -U admin -d mydb
```

### 5. Python (boto3/psycopg2)
```python
import psycopg2

conn = psycopg2.connect(
    host='<your-cluster-endpoint>',
    port=5439,
    database='mydb',
    user='admin',
    password='your-password'
)
```

### 6. TablePlus/DataGrip (Paid Options)
- Professional database clients with Redshift support
- Better UI/UX but require licenses

## NO EC2 REQUIRED!
- The cluster is set to `publicly_accessible = true`
- You can connect directly from your local machine
- The security group is open to 0.0.0.0/0 (restrict this for production!)

## Getting Connection Details
After running `terraform apply`, you'll see outputs like:
```
cluster_endpoint = "my-redshift-cluster.xxx.us-east-1.redshift.amazonaws.com:5439"
jdbc_connection_string = "jdbc:redshift://..."
psql_connection_command = "psql -h ... -p 5439 -U admin -d mydb"
```

## First Steps After Connecting
```sql
-- Create a schema
CREATE SCHEMA IF NOT EXISTS myschema;

-- Create a sample table
CREATE TABLE myschema.users (
    user_id INTEGER NOT NULL,
    username VARCHAR(50),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO myschema.users (user_id, username) 
VALUES (1, 'testuser');

-- Query data
SELECT * FROM myschema.users;
```

## Security Configuration
- The cluster is now restricted to your IP address only (71.231.5.129)
- If your IP changes, update the `allowed_ip` variable in terraform.tfvars
- To check your current IP: `curl https://checkip.amazonaws.com`

## Updating Your IP Address
If you get connection errors, your IP may have changed:
```bash
# Check your current IP
curl https://checkip.amazonaws.com

# Update terraform.tfvars with new IP
# Then apply changes
terraform apply
```