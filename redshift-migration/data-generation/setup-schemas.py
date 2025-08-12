#!/usr/bin/env python3
"""
Quick script to create schemas in Redshift before running data generation
"""

import psycopg2

# Connection parameters
conn_params = {
    'host': 'my-redshift-cluster.cjsvyvjxsdqo.us-west-2.redshift.amazonaws.com',
    'port': 5439,
    'database': 'mydb',
    'user': 'admin',
    'password': 'P4ssw0rd123!'
}

try:
    # Connect to Redshift
    conn = psycopg2.connect(**conn_params)
    cur = conn.cursor()
    
    print("Creating schemas...")
    
    # Create schemas
    cur.execute("CREATE SCHEMA IF NOT EXISTS airline_dw")
    cur.execute("CREATE SCHEMA IF NOT EXISTS staging")
    
    conn.commit()
    print("Schemas created successfully!")
    
    # Verify schemas
    cur.execute("""
        SELECT schema_name 
        FROM information_schema.schemata 
        WHERE schema_name IN ('airline_dw', 'staging')
    """)
    
    schemas = cur.fetchall()
    print("\nCreated schemas:")
    for schema in schemas:
        print(f"  - {schema[0]}")
    
    cur.close()
    conn.close()
    
except Exception as e:
    print(f"Error: {e}")