# Multi-Domain Data Sharing Scenario

## Overview

This data generation script creates a realistic enterprise data sharing scenario with:
- **1 Producer Cluster**: Central data warehouse with all organizational data
- **2 Consumer Clusters**: Domain-specific clusters for Sales and Operations

## Data Architecture

### 🌐 Shared Core Data (Both Consumers)
**Schema**: `shared_airline`

Core airline operational data that both Sales and Operations teams need:
- **airports**: Airport information and hub status
- **aircraft**: Fleet information and specifications  
- **flights**: Flight schedules and status
- **routes**: Route network and distances
- **flight_performance** (view): Aggregated flight performance metrics

### 💰 Sales Domain Data (Sales Consumer Only)
**Schema**: `sales_domain`

Customer and revenue focused data for sales and marketing teams:
- **customers**: Customer profiles and loyalty information
- **bookings**: Booking transactions and revenue
- **marketing_campaigns**: Campaign performance and ROI
- **daily_revenue**: Daily revenue aggregations
- **customer_360** (view): Complete customer view

### 🔧 Operations Domain Data (Operations Consumer Only)
**Schema**: `operations_domain`

Operational efficiency and maintenance data:
- **maintenance_logs**: Aircraft maintenance schedules and compliance
- **crew_assignments**: Crew scheduling and hours tracking
- **daily_operations_metrics**: Operational KPIs and performance
- **ground_handling**: Ground operations and turnaround times
- **fleet_status** (view): Fleet maintenance status

## Usage

### 1. Generate Data on Producer Cluster

```bash
python generate-multi-domain-data.py \
    --host <producer-endpoint> \
    --database dev \
    --user admin \
    --password <password>
```

This will:
- Create all schemas (shared_airline, sales_domain, operations_domain)
- Generate realistic data for all tables
- Create aggregated views
- Display data sharing SQL commands

### 2. Set Up Data Shares

The script outputs the exact SQL commands needed. Here's the flow:

#### On Producer Cluster:
```sql
-- Get producer namespace ID
SELECT current_namespace;

-- Create three data shares
CREATE DATASHARE airline_core_share;         -- For both consumers
CREATE DATASHARE sales_data_share;           -- For Sales only
CREATE DATASHARE operations_data_share;      -- For Operations only

-- Add schemas to shares
ALTER DATASHARE airline_core_share ADD SCHEMA shared_airline;
ALTER DATASHARE sales_data_share ADD SCHEMA sales_domain;
ALTER DATASHARE operations_data_share ADD SCHEMA operations_domain;
```

#### Grant Access:
```sql
-- Both consumers get core data
GRANT USAGE ON DATASHARE airline_core_share TO NAMESPACE '<SALES_NAMESPACE_ID>';
GRANT USAGE ON DATASHARE airline_core_share TO NAMESPACE '<OPS_NAMESPACE_ID>';

-- Domain-specific access
GRANT USAGE ON DATASHARE sales_data_share TO NAMESPACE '<SALES_NAMESPACE_ID>';
GRANT USAGE ON DATASHARE operations_data_share TO NAMESPACE '<OPS_NAMESPACE_ID>';
```

### 3. Consumer Setup

#### Sales Consumer:
```sql
-- Create databases from shares
CREATE DATABASE airline_shared FROM DATASHARE airline_core_share 
    OF NAMESPACE '<PRODUCER_NAMESPACE>';
CREATE DATABASE sales_analytics FROM DATASHARE sales_data_share 
    OF NAMESPACE '<PRODUCER_NAMESPACE>';

-- Sales team can now query:
SELECT * FROM airline_shared.shared_airline.flights;        -- ✅ Shared data
SELECT * FROM sales_analytics.sales_domain.customers;       -- ✅ Sales data
-- Cannot access operations_domain                          -- ❌ No access
```

#### Operations Consumer:
```sql
-- Create databases from shares
CREATE DATABASE airline_shared FROM DATASHARE airline_core_share 
    OF NAMESPACE '<PRODUCER_NAMESPACE>';
CREATE DATABASE ops_analytics FROM DATASHARE operations_data_share 
    OF NAMESPACE '<PRODUCER_NAMESPACE>';

-- Operations team can now query:
SELECT * FROM airline_shared.shared_airline.flights;        -- ✅ Shared data
SELECT * FROM ops_analytics.operations_domain.maintenance;  -- ✅ Ops data
-- Cannot access sales_domain                               -- ❌ No access
```

## Data Volumes

Default generation creates:
- 2,000 flights
- 1,000 customers
- 5,000 bookings
- 500 maintenance records
- 2,000 crew assignments
- 90 days of daily metrics

Adjust in the script's `generate_all_data()` method as needed.

## Business Scenario

This simulates a real airline organization where:

1. **Central Data Team** (Producer) maintains the single source of truth
2. **Sales Team** (Consumer 1) focuses on:
   - Customer analytics
   - Revenue optimization
   - Marketing campaign effectiveness
   - Booking patterns

3. **Operations Team** (Consumer 2) focuses on:
   - Fleet maintenance optimization
   - Crew utilization
   - On-time performance
   - Ground operations efficiency

Both teams need access to core flight and aircraft data, but each has their own domain-specific data that shouldn't be shared with the other team.

## Benefits of This Architecture

1. **Data Governance**: Central control with domain-specific access
2. **Cost Optimization**: Each team pays for their own compute
3. **Performance Isolation**: Sales queries don't impact Operations
4. **Security**: Teams only see data relevant to their domain
5. **Scalability**: Can add more consumer clusters as needed

## Testing the Setup

After setup, verify data sharing works:

```sql
-- On Sales Consumer
SELECT 
    COUNT(*) as bookings,
    SUM(total_price) as revenue
FROM sales_analytics.sales_domain.bookings
WHERE booking_date >= CURRENT_DATE - 30;

-- On Operations Consumer  
SELECT 
    aircraft_id,
    COUNT(*) as maintenance_events,
    AVG(cost) as avg_cost
FROM ops_analytics.operations_domain.maintenance_logs
GROUP BY aircraft_id;

-- Both can query shared data
SELECT 
    origin_airport,
    destination_airport,
    COUNT(*) as flight_count
FROM airline_shared.shared_airline.flights
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 10;
```

## Troubleshooting

1. **"Namespace not found"**: Ensure you're using the correct namespace ID from `SELECT current_namespace`
2. **"Datashare not found"**: Check the producer cluster created the shares successfully
3. **"Permission denied"**: Verify GRANT statements were executed on producer
4. **Empty results**: Ensure data was generated on producer before creating shares