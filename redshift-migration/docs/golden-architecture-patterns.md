# Redshift Golden Architecture Patterns

## 1. Data Modeling Best Practices

### Star Schema Design
```sql
-- Fact tables: Large, contains measures
-- Dimension tables: Smaller, contains attributes
-- Our airline model follows this pattern perfectly
```

**Key Principles:**
- **Fact Tables**: Store transactional data (bookings, flights)
- **Dimension Tables**: Store descriptive data (airports, aircraft)
- **Surrogate Keys**: Use IDENTITY columns for better performance
- **Date Dimensions**: Pre-populated for better query performance

### Distribution Strategies

#### DISTKEY Selection
```sql
-- High-cardinality columns that are frequently joined
DISTKEY (customer_key)  -- for fact_bookings
DISTKEY (date_key)      -- for fact_flight_operations
DISTKEY (flight_number) -- for dim_flight
```

**Rules:**
1. Choose columns with high cardinality
2. Frequently used in JOIN conditions
3. Avoid columns that would cause data skew

#### DISTSTYLE Patterns
```sql
-- Small dimension tables (<1M rows)
DISTSTYLE ALL  -- Replicate to all nodes

-- Large fact tables
DISTSTYLE KEY  -- Distribute by high-cardinality column

-- Even distribution needed
DISTSTYLE EVEN -- Round-robin distribution
```

### Sort Key Optimization

#### Compound Sort Keys
```sql
-- For time-series queries
SORTKEY (date_key, scheduled_departure_datetime)

-- For range queries
SORTKEY (origin_airport_code, destination_airport_code)
```

**Best Practices:**
- First column should be most selective
- Matches WHERE clause predicates
- Consider query patterns

## 2. Query Optimization Patterns

### Materialized Views for Common Aggregations
```sql
CREATE MATERIALIZED VIEW mv_daily_route_performance AS
SELECT 
    date_key,
    origin_airport_code,
    destination_airport_code,
    COUNT(*) as flight_count,
    AVG(departure_delay_minutes) as avg_delay,
    SUM(total_passengers) as total_passengers
FROM fact_flight_operations fo
JOIN dim_flight f ON fo.flight_key = f.flight_key
GROUP BY 1, 2, 3;

-- Auto-refresh on data changes
ALTER MATERIALIZED VIEW mv_daily_route_performance 
SET AUTO REFRESH = YES;
```

### Query Tuning Patterns

#### Use Column Pruning
```sql
-- Bad: SELECT * wastes resources
SELECT * FROM fact_bookings;

-- Good: Select only needed columns
SELECT booking_key, customer_key, total_fare_usd 
FROM fact_bookings;
```

#### Optimize JOIN Order
```sql
-- Join smaller tables first
SELECT ...
FROM small_dimension d1
JOIN medium_dimension d2 ON d1.key = d2.key
JOIN large_fact f ON d2.key = f.key;
```

#### Use Appropriate Aggregation
```sql
-- Use approximate functions for large datasets
SELECT 
    APPROXIMATE COUNT(DISTINCT customer_key) as unique_customers,
    APPROXIMATE PERCENTILE_CONT(0.5) 
        WITHIN GROUP (ORDER BY total_fare_usd) as median_fare
FROM fact_bookings;
```

## 3. Data Loading Patterns

### Efficient COPY Operations
```sql
-- Best practices for COPY
COPY table_name
FROM 's3://bucket/path/'
IAM_ROLE 'arn:aws:iam::account:role/role-name'
FORMAT AS PARQUET        -- Compressed format
FILLRECORD              -- Handle missing columns
ACCEPTINVCHARS          -- Handle special characters
DATEFORMAT 'auto'       -- Automatic date parsing
TIMEFORMAT 'auto'       -- Automatic time parsing
COMPUPDATE PRESET       -- Automatic compression
STATUPDATE ON;          -- Update table statistics
```

### Incremental Loading Pattern
```sql
-- Use staging table for incremental loads
BEGIN;

-- Load new data into staging
COPY staging_table FROM 's3://bucket/new-data/';

-- Merge into main table
DELETE FROM main_table
USING staging_table
WHERE main_table.key = staging_table.key;

INSERT INTO main_table
SELECT * FROM staging_table;

COMMIT;
```

## 4. Serverless-Specific Patterns

### Workload Isolation
```sql
-- Create separate namespaces for different workloads
CREATE NAMESPACE analytics_namespace;
CREATE NAMESPACE etl_namespace;
CREATE NAMESPACE reporting_namespace;

-- Assign different RPU configurations
-- Analytics: 32-128 RPUs (auto-scale)
-- ETL: 64-256 RPUs (higher for data loading)
-- Reporting: 32-64 RPUs (consistent performance)
```

### Cost Optimization Strategies

#### Auto-Pause Configuration
```python
# Terraform configuration for auto-pause
resource "aws_redshiftserverless_workgroup" "main" {
  # Auto-pause after 10 minutes of inactivity
  config_parameter {
    parameter_key   = "auto_pause"
    parameter_value = "true"
  }
  
  config_parameter {
    parameter_key   = "auto_pause_minutes"
    parameter_value = "10"
  }
}
```

#### Query Monitoring Rules (QMR)
```sql
-- Prevent runaway queries
CREATE QMR rule 'long_running_query_abort'
WHEN query_execution_time > 300000  -- 5 minutes
THEN abort;

CREATE QMR rule 'high_memory_query_log'
WHEN query_memory_usage_percent > 80
THEN log;
```

## 5. Security Patterns

### Column-Level Encryption
```sql
-- Sensitive data encryption
CREATE TABLE customers (
    customer_id INTEGER,
    name VARCHAR(100) ENCRYPT,
    ssn VARCHAR(11) ENCRYPT USING 'AES256',
    email VARCHAR(255)
);
```

### Row-Level Security
```sql
-- Create policy for data access
CREATE RLS POLICY customer_data_policy
ON fact_bookings
FOR SELECT
TO analysts_role
USING (customer_type != 'vip');
```

### Audit Logging
```sql
-- Enable audit logging
ALTER DATABASE airline_dw 
SET enable_user_activity_logging TO true;

-- Query audit logs
SELECT 
    username,
    query,
    starttime,
    endtime
FROM sys_query_history
WHERE query_type = 'SELECT'
  AND tables_accessed LIKE '%customer%';
```

## 6. Performance Monitoring

### System Tables for Monitoring
```sql
-- Query performance metrics
SELECT 
    query_id,
    query_text,
    execution_time,
    queue_time,
    rows_returned,
    bytes_scanned
FROM sys_query_history
WHERE execution_time > 5000  -- Queries over 5 seconds
ORDER BY execution_time DESC;

-- Table usage patterns
SELECT 
    schema_name,
    table_name,
    query_count,
    user_count,
    last_accessed
FROM sys_table_access_history
ORDER BY query_count DESC;
```

### Workload Management
```sql
-- Create query queues for different workloads
CREATE QUEUE etl_queue 
WITH (
    CONCURRENCY = 5,
    MEMORY_PERCENT = 40
);

CREATE QUEUE analytics_queue 
WITH (
    CONCURRENCY = 15,
    MEMORY_PERCENT = 30
);

CREATE QUEUE reporting_queue 
WITH (
    CONCURRENCY = 25,
    MEMORY_PERCENT = 30
);
```

## 7. Migration-Specific Patterns

### Zero-Downtime Migration
1. **Set up data sharing** between clusters
2. **Sync data** using CDC or scheduled jobs
3. **Validate** data consistency
4. **Gradually migrate** workloads
5. **Monitor** both clusters during transition

### Rollback Strategy
```sql
-- Maintain backup endpoints
-- Keep source cluster running for X days
-- Use CNAME switching for instant rollback
-- Monitor error rates and performance
```

## 8. Modern Data Architecture Integration

### Data Lake Integration
```sql
-- Query S3 data directly with Spectrum
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'airline_data_lake'
IAM_ROLE 'arn:aws:iam::account:role/spectrum-role';

-- Join external and internal data
SELECT 
    r.customer_key,
    r.total_revenue,
    e.external_events
FROM redshift_table r
JOIN spectrum_schema.external_table e
  ON r.customer_id = e.customer_id;
```

### Real-Time Streaming
```sql
-- Ingest from Kinesis
CREATE EXTERNAL SCHEMA kinesis_schema
FROM KINESIS
IAM_ROLE 'arn:aws:iam::account:role/kinesis-role';

-- Materialized view for real-time data
CREATE MATERIALIZED VIEW real_time_bookings AS
SELECT * FROM kinesis_schema.booking_stream;
```

## Key Takeaways

1. **Design for Scale**: Use appropriate distribution and sort keys
2. **Optimize for Cost**: Leverage serverless auto-pause and scaling
3. **Monitor Continuously**: Use system tables and CloudWatch
4. **Automate Everything**: From loading to maintenance
5. **Plan for Growth**: Design with future requirements in mind
6. **Test Thoroughly**: Validate performance at scale
7. **Document Patterns**: Maintain runbooks and best practices