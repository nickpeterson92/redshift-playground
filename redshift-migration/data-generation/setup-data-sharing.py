#!/usr/bin/env python3
"""
Setup data sharing between producer and consumer clusters in traditional Redshift deployment
"""

import psycopg2
import argparse
import sys
from typing import Dict, List, Tuple

class DataSharingSetup:
    def __init__(self, producer_config: Dict, consumer_configs: List[Dict]):
        self.producer_config = producer_config
        self.consumer_configs = consumer_configs
        
    def get_namespace_id(self, config: Dict) -> str:
        """Get the namespace ID for a cluster"""
        try:
            conn = psycopg2.connect(
                host=config['host'],
                database=config['database'],
                user=config['user'],
                password=config['password'],
                port=config.get('port', 5439)
            )
            cursor = conn.cursor()
            cursor.execute("SELECT current_namespace")
            namespace_id = cursor.fetchone()[0]
            cursor.close()
            conn.close()
            return namespace_id
        except Exception as e:
            print(f"❌ Error getting namespace ID for {config['host']}: {e}")
            return None
    
    def create_datashares_on_producer(self) -> bool:
        """Create datashares on the producer cluster"""
        try:
            # Create connection with autocommit for DDL operations
            conn = psycopg2.connect(
                host=self.producer_config['host'],
                database=self.producer_config['database'],
                user=self.producer_config['user'],
                password=self.producer_config['password'],
                port=self.producer_config.get('port', 5439)
            )
            conn.autocommit = True  # Set autocommit at connection level
            cursor = conn.cursor()
            
            print("\n🧹 Cleaning up existing datashares...")
            
            # First, let's see what datashares exist
            cursor.execute("SELECT share_name, share_owner FROM svv_datashares")
            all_shares = cursor.fetchall()
            print(f"  Found {len(all_shares)} total datashares in cluster")
            
            # Get current namespace
            cursor.execute("SELECT current_namespace")
            current_ns = cursor.fetchone()[0]
            print(f"  Current namespace: {current_ns}")
            
            # Drop datashares we're going to recreate (by name, regardless of owner)
            datashares_to_drop = ['shared_airline_data', 'sales_domain_data', 'operations_domain_data']
            for share_name in datashares_to_drop:
                try:
                    cursor.execute(f"DROP DATASHARE {share_name}")
                    print(f"  ✅ Dropped datashare: {share_name}")
                except Exception as e:
                    if "does not exist" in str(e).lower():
                        print(f"  ℹ️  Datashare {share_name} doesn't exist, skipping")
                    else:
                        print(f"  ⚠️  Could not drop datashare {share_name}: {e}")
            
            print("\n📊 Creating datashares on producer cluster...")
            
            # Define datashares and their contents
            datashares = [
                {
                    'name': 'shared_airline_data',
                    'description': 'Core airline operational data shared with all consumers',
                    'schemas': ['shared_airline'],
                    'share_with': 'all'  # Share with all consumers
                },
                {
                    'name': 'sales_domain_data',
                    'description': 'Sales and marketing domain data',
                    'schemas': ['sales_domain'],
                    'share_with': 'sales'  # Share only with sales consumer
                },
                {
                    'name': 'operations_domain_data',
                    'description': 'Operations and maintenance domain data',
                    'schemas': ['operations_domain'],
                    'share_with': 'operations'  # Share only with operations consumer
                }
            ]
            
            for datashare in datashares:
                print(f"\n  Creating datashare: {datashare['name']}")
                
                # Create the datashare with public access enabled
                cursor.execute(f"CREATE DATASHARE {datashare['name']} SET PUBLICACCESSIBLE TRUE")
                print(f"    ✅ Created datashare {datashare['name']} (publicly accessible)")
                
                # Add schemas and their tables to the datashare
                for schema in datashare['schemas']:
                    try:
                        # Add schema
                        cursor.execute(f"ALTER DATASHARE {datashare['name']} ADD SCHEMA {schema}")
                        print(f"    ✅ Added schema {schema}")
                        
                        # Add all tables in the schema
                        cursor.execute(f"ALTER DATASHARE {datashare['name']} ADD ALL TABLES IN SCHEMA {schema}")
                        print(f"    ✅ Added all tables from {schema}")
                        
                    except Exception as e:
                        print(f"    ❌ Error adding schema {schema}: {e}")
                
                # Grant access to appropriate consumers
                for consumer in self.consumer_configs:
                    should_share = (
                        datashare['share_with'] == 'all' or
                        (datashare['share_with'] == 'sales' and 'sales' in consumer['name'].lower()) or
                        (datashare['share_with'] == 'operations' and ('operations' in consumer['name'].lower() or 'ops' in consumer['name'].lower()))
                    )
                    
                    if should_share:
                        namespace_id = consumer.get('namespace_id')
                        if namespace_id:
                            try:
                                cursor.execute(f"GRANT USAGE ON DATASHARE {datashare['name']} TO NAMESPACE '{namespace_id}'")
                                print(f"    ✅ Granted access to {consumer['name']} (namespace: {namespace_id})")
                            except Exception as e:
                                print(f"    ❌ Error granting to {consumer['name']}: {e}")
            
            # Show datashare status
            print("\n📊 Datashare Status:")
            cursor.execute("""
                SELECT 
                    share_name,
                    share_owner,
                    is_publicaccessible,
                    share_type
                FROM svv_datashares
                WHERE share_owner = current_namespace
                ORDER BY share_name
            """)
            
            shares = cursor.fetchall()
            for share in shares:
                print(f"  - {share[0]}: Type={share[3]}, Public={share[2]}")
            
            # Show consumer grants
            print("\n📊 Datashare Consumers:")
            cursor.execute("""
                SELECT 
                    share_name,
                    consumer_namespace
                FROM svv_datashare_consumers
                ORDER BY share_name, consumer_namespace
            """)
            
            consumers = cursor.fetchall()
            for consumer in consumers:
                print(f"  - {consumer[0]} → Consumer: {consumer[1]}")
            
            cursor.close()
            conn.close()
            return True
            
        except Exception as e:
            print(f"❌ Error creating datashares: {e}")
            return False
    
    def create_databases_on_consumers(self) -> bool:
        """Create databases from datashares on consumer clusters"""
        
        # Get producer namespace ID
        producer_namespace = self.get_namespace_id(self.producer_config)
        if not producer_namespace:
            print("❌ Could not get producer namespace ID")
            return False
        
        print(f"\n✅ Producer namespace ID: {producer_namespace}")
        
        for consumer in self.consumer_configs:
            print(f"\n📊 Setting up consumer: {consumer['name']}")
            
            try:
                conn = psycopg2.connect(
                    host=consumer['host'],
                    database=consumer['database'],
                    user=consumer['user'],
                    password=consumer['password'],
                    port=consumer.get('port', 5439)
                )
                conn.autocommit = True  # Need autocommit for CREATE DATABASE
                cursor = conn.cursor()
                
                # Determine which databases to create based on consumer type
                databases_to_create = []
                
                # All consumers get shared airline data
                databases_to_create.append({
                    'datashare': 'shared_airline_data',
                    'database': 'shared_airline_db',
                    'description': 'Core airline operational data'
                })
                
                # Sales consumer gets sales domain data
                if 'sales' in consumer['name'].lower():
                    databases_to_create.append({
                        'datashare': 'sales_domain_data',
                        'database': 'sales_domain_db',
                        'description': 'Sales and marketing data'
                    })
                
                # Operations consumer gets operations domain data
                if 'operations' in consumer['name'].lower() or 'ops' in consumer['name'].lower():
                    databases_to_create.append({
                        'datashare': 'operations_domain_data',
                        'database': 'operations_domain_db',
                        'description': 'Operations and maintenance data'
                    })
                
                # Create databases from datashares
                for db_config in databases_to_create:
                    try:
                        # Drop existing database (no IF EXISTS in Redshift)
                        cursor.execute(f"DROP DATABASE {db_config['database']}")
                        print(f"  ✅ Dropped existing database {db_config['database']}")
                    except Exception as e:
                        if "does not exist" not in str(e).lower():
                            print(f"  ℹ️  Could not drop {db_config['database']}: {e}")
                    
                    try:
                        # Create database from datashare
                        create_sql = f"""
                            CREATE DATABASE {db_config['database']} 
                            FROM DATASHARE {db_config['datashare']} 
                            OF NAMESPACE '{producer_namespace}'
                        """
                        cursor.execute(create_sql)
                        print(f"  ✅ Created database {db_config['database']} - {db_config['description']}")
                        
                    except Exception as e:
                        print(f"  ❌ Error creating database {db_config['database']}: {e}")
                
                # Verify access by querying shared data
                print(f"\n  🔍 Verifying data access on {consumer['name']}:")
                
                # Test shared airline data (all consumers should have this)
                try:
                    # First check if we can see the database
                    cursor.execute("SELECT database_name FROM svv_redshift_databases WHERE database_name = 'shared_airline_db'")
                    if cursor.fetchone():
                        print(f"    ✅ Database shared_airline_db is accessible")
                        
                        # Try a simpler query first
                        cursor.execute("SELECT current_database()")
                        current_db = cursor.fetchone()[0]
                        print(f"    ℹ️  Current database: {current_db}")
                        
                        # List available schemas in the shared database
                        cursor.execute("""
                            SELECT schema_name 
                            FROM svv_all_schemas 
                            WHERE database_name = 'shared_airline_db'
                        """)
                        schemas = cursor.fetchall()
                        if schemas:
                            print(f"    ✅ Available schemas in shared_airline_db: {[s[0] for s in schemas]}")
                        
                        # List available tables in the schema
                        cursor.execute("""
                            SELECT table_name 
                            FROM svv_all_tables 
                            WHERE database_name = 'shared_airline_db' 
                            AND schema_name = 'shared_airline'
                            ORDER BY table_name
                        """)
                        tables = cursor.fetchall()
                        if tables:
                            print(f"    ✅ Available tables: {[t[0] for t in tables]}")
                            
                            # Try accessing flights table
                            cursor.execute("SELECT COUNT(*) FROM shared_airline_db.shared_airline.flights")
                            count = cursor.fetchone()[0]
                            print(f"    ✅ Can query shared_airline.flights: {count:,} flights")
                        else:
                            # If no tables found in svv_all_tables, try the query anyway
                            cursor.execute("SELECT COUNT(*) FROM shared_airline_db.shared_airline.flights")
                            count = cursor.fetchone()[0]
                            print(f"    ✅ Can query shared_airline data: {count:,} flights")
                    else:
                        print(f"    ⚠️  Database shared_airline_db not found in available databases")
                except Exception as e:
                    if "publicly accessible" in str(e).lower():
                        print(f"    ⚠️  Public access limitation: Datashare is accessible but requires specific permissions")
                        print(f"       Note: You can query the data but may need to grant additional permissions")
                    else:
                        print(f"    ❌ Error accessing shared_airline data: {e}")
                
                # Test sales data (only sales consumer)
                if 'sales' in consumer['name'].lower():
                    try:
                        cursor.execute("SELECT database_name FROM svv_redshift_databases WHERE database_name = 'sales_domain_db'")
                        if cursor.fetchone():
                            print(f"    ✅ Database sales_domain_db is accessible")
                            cursor.execute("SELECT COUNT(*) FROM sales_domain_db.sales_domain.bookings")
                            count = cursor.fetchone()[0]
                            print(f"    ✅ Can query sales_domain data: {count:,} bookings")
                    except Exception as e:
                        if "publicly accessible" in str(e).lower():
                            print(f"    ⚠️  Public access limitation for sales_domain_db")
                        else:
                            print(f"    ❌ Error accessing sales_domain data: {e}")
                
                # Test operations data (only operations consumer)
                if 'operations' in consumer['name'].lower() or 'ops' in consumer['name'].lower():
                    try:
                        cursor.execute("SELECT database_name FROM svv_redshift_databases WHERE database_name = 'operations_domain_db'")
                        if cursor.fetchone():
                            print(f"    ✅ Database operations_domain_db is accessible")
                            cursor.execute("SELECT COUNT(*) FROM operations_domain_db.operations_domain.maintenance_logs")
                            count = cursor.fetchone()[0]
                            print(f"    ✅ Can query operations_domain data: {count:,} maintenance logs")
                    except Exception as e:
                        if "publicly accessible" in str(e).lower():
                            print(f"    ⚠️  Public access limitation for operations_domain_db")
                        else:
                            print(f"    ❌ Error accessing operations_domain data: {e}")
                
                cursor.close()
                conn.close()
                
            except Exception as e:
                print(f"  ❌ Error setting up consumer {consumer['name']}: {e}")
                return False
        
        return True
    
    def generate_sample_queries(self):
        """Generate sample queries for testing data sharing"""
        print("\n" + "="*60)
        print("📝 SAMPLE QUERIES FOR TESTING DATA SHARING")
        print("="*60)
        
        print("\n-- On Sales Consumer Cluster:")
        print("""
-- Test basic connectivity
SELECT COUNT(*) FROM sales_domain_db.sales_domain.customers;
SELECT COUNT(*) FROM shared_airline_db.shared_airline.flights;

-- Query shared airline data (flights)
SELECT 
    f.flight_number,
    f.origin_airport,
    f.destination_airport,
    f.scheduled_departure,
    f.actual_departure,
    f.status
FROM shared_airline_db.shared_airline.flights f
LIMIT 10;

-- Query sales-specific data
SELECT 
    c.first_name,
    c.last_name,
    c.loyalty_tier,
    COUNT(b.booking_id) as total_bookings,
    SUM(b.total_price) as total_spent
FROM sales_domain_db.sales_domain.customers c
LEFT JOIN sales_domain_db.sales_domain.bookings b ON c.customer_id = b.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.loyalty_tier
ORDER BY total_spent DESC
LIMIT 10;

-- Cross-domain query (sales with flight data)
SELECT 
    DATE_TRUNC('month', b.booking_date) as booking_month,
    f.origin_airport,
    f.destination_airport,
    COUNT(DISTINCT b.booking_id) as bookings,
    SUM(b.total_price) as revenue
FROM sales_domain_db.sales_domain.bookings b
JOIN shared_airline_db.shared_airline.flights f ON b.flight_id = f.flight_id
GROUP BY 1, 2, 3
ORDER BY revenue DESC
LIMIT 10;
        """)
        
        print("\n-- On Operations Consumer Cluster:")
        print("""
-- Test basic connectivity
SELECT COUNT(*) FROM operations_domain_db.operations_domain.maintenance_logs;
SELECT COUNT(*) FROM shared_airline_db.shared_airline.aircraft;

-- Query shared airline data (aircraft with flights)
SELECT 
    a.aircraft_id,
    a.manufacturer,
    a.model,
    COUNT(DISTINCT f.flight_id) as total_flights
FROM shared_airline_db.shared_airline.aircraft a
JOIN shared_airline_db.shared_airline.flights f ON a.aircraft_id = f.aircraft_id
GROUP BY a.aircraft_id, a.manufacturer, a.model
ORDER BY total_flights DESC
LIMIT 10;

-- Query operations-specific data (maintenance logs)
SELECT 
    m.aircraft_id,
    a.model,
    m.maintenance_type,
    COUNT(*) as maintenance_count,
    AVG(m.hours_required) as avg_hours,
    SUM(m.cost) as total_cost
FROM operations_domain_db.operations_domain.maintenance_logs m
JOIN shared_airline_db.shared_airline.aircraft a ON m.aircraft_id = a.aircraft_id
GROUP BY m.aircraft_id, a.model, m.maintenance_type
ORDER BY maintenance_count DESC
LIMIT 10;

-- Cross-domain query (crew assignments with flight data)
SELECT 
    DATE_TRUNC('week', ca.assignment_date) as week,
    ca.role,
    COUNT(DISTINCT ca.crew_member_id) as unique_crew,
    COUNT(DISTINCT ca.flight_id) as flights_covered,
    SUM(ca.flight_hours) as total_flight_hours
FROM operations_domain_db.operations_domain.crew_assignments ca
GROUP BY 1, 2
ORDER BY week DESC, unique_crew DESC
LIMIT 10;
        """)

def main():
    parser = argparse.ArgumentParser(description='Setup data sharing between Redshift clusters')
    
    # Producer arguments
    parser.add_argument('--producer-host', required=True, help='Producer cluster endpoint')
    parser.add_argument('--producer-db', required=True, help='Producer database name')
    parser.add_argument('--producer-user', required=True, help='Producer username')
    parser.add_argument('--producer-password', required=True, help='Producer password')
    
    # Consumer 1 (Sales) arguments
    parser.add_argument('--consumer1-host', required=True, help='Consumer 1 (Sales) cluster endpoint')
    parser.add_argument('--consumer1-db', required=True, help='Consumer 1 database name')
    parser.add_argument('--consumer1-user', required=True, help='Consumer 1 username')
    parser.add_argument('--consumer1-password', required=True, help='Consumer 1 password')
    
    # Consumer 2 (Operations) arguments
    parser.add_argument('--consumer2-host', required=True, help='Consumer 2 (Operations) cluster endpoint')
    parser.add_argument('--consumer2-db', required=True, help='Consumer 2 database name')
    parser.add_argument('--consumer2-user', required=True, help='Consumer 2 username')
    parser.add_argument('--consumer2-password', required=True, help='Consumer 2 password')
    
    # Optional port
    parser.add_argument('--port', default=5439, type=int, help='Port number for all clusters (default: 5439)')
    
    args = parser.parse_args()
    
    # Setup configurations
    producer_config = {
        'host': args.producer_host,
        'database': args.producer_db,
        'user': args.producer_user,
        'password': args.producer_password,
        'port': args.port
    }
    
    consumer_configs = [
        {
            'name': 'Sales Consumer',
            'host': args.consumer1_host,
            'database': args.consumer1_db,
            'user': args.consumer1_user,
            'password': args.consumer1_password,
            'port': args.port
        },
        {
            'name': 'Operations Consumer',
            'host': args.consumer2_host,
            'database': args.consumer2_db,
            'user': args.consumer2_user,
            'password': args.consumer2_password,
            'port': args.port
        }
    ]
    
    print("🚀 Starting data sharing setup...")
    print(f"  Producer: {producer_config['host']}")
    print(f"  Consumer 1 (Sales): {consumer_configs[0]['host']}")
    print(f"  Consumer 2 (Operations): {consumer_configs[1]['host']}")
    
    # Get namespace IDs for all clusters
    setup = DataSharingSetup(producer_config, consumer_configs)
    
    print("\n📊 Getting namespace IDs...")
    for consumer in consumer_configs:
        namespace_id = setup.get_namespace_id(consumer)
        if namespace_id:
            consumer['namespace_id'] = namespace_id
            print(f"  ✅ {consumer['name']}: {namespace_id}")
        else:
            print(f"  ❌ Could not get namespace ID for {consumer['name']}")
            sys.exit(1)
    
    # Create datashares on producer
    if not setup.create_datashares_on_producer():
        print("\n❌ Failed to create datashares on producer")
        sys.exit(1)
    
    # Create databases on consumers
    if not setup.create_databases_on_consumers():
        print("\n❌ Failed to create databases on consumers")
        sys.exit(1)
    
    # Generate sample queries
    setup.generate_sample_queries()
    
    print("\n✅ Data sharing setup completed successfully!")
    print("\n⚠️  Important Note about Public Access:")
    print("If your consumer clusters are publicly accessible, you may encounter access restrictions.")
    print("To resolve this, connect to each consumer cluster and run:")
    print("")
    print("-- On each consumer cluster:")
    print("GRANT USAGE ON DATABASE shared_airline_db TO PUBLIC;")
    print("GRANT USAGE ON DATABASE sales_domain_db TO PUBLIC;  -- Sales consumer only")
    print("GRANT USAGE ON DATABASE operations_domain_db TO PUBLIC;  -- Operations consumer only")
    print("")
    print("\nNext steps:")
    print("1. Grant usage permissions if needed (see above)")
    print("2. Test the sample queries on each consumer cluster")
    print("3. Monitor query performance and data freshness")
    print("4. Set up any additional views or aggregations as needed")

if __name__ == "__main__":
    main()