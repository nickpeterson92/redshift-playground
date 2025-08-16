#!/usr/bin/env python3
"""
Test NLB connection to Redshift consumers and verify load distribution.
This script connects multiple times through the NLB and checks which backend is serving each request.
"""

import psycopg2
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

def test_connection(connection_num, host, database, username, password):
    """Test a single connection through the NLB"""
    try:
        # Connect through NLB
        conn = psycopg2.connect(
            host=host,
            port=5439,
            database=database,
            user=username,
            password=password,
            sslmode='require'
        )
        
        cursor = conn.cursor()
        
        # Get the current namespace/workgroup info
        cursor.execute("""
            SELECT 
                current_database(),
                current_namespace,
                pg_backend_pid(),
                inet_server_addr()::text as server_addr
        """)
        
        result = cursor.fetchone()
        
        # Try to query the shared data (using correct table name)
        cursor.execute("SELECT COUNT(*) FROM airline_shared.airline_dw.dim_aircraft")
        flight_count = cursor.fetchone()[0]
        
        cursor.close()
        conn.close()
        
        return {
            'connection': connection_num,
            'database': result[0],
            'namespace': result[1],
            'backend_pid': result[2],
            'server_addr': result[3],
            'aircraft_count': flight_count,
            'status': 'SUCCESS'
        }
        
    except Exception as e:
        return {
            'connection': connection_num,
            'status': 'FAILED',
            'error': str(e)
        }

def main():
    # NLB endpoint
    nlb_host = "airline-redshift-nlb-7a0ce4765dc4ed98.elb.us-west-2.amazonaws.com"
    database = "consumer_db"  # Consumer database name
    username = "admin"
    
    # Get password from environment or prompt
    import os
    password = os.environ.get('REDSHIFT_PASSWORD')
    if not password:
        import getpass
        password = getpass.getpass('Enter Redshift password: ')
    
    print(f"\n🔄 Testing NLB connection to: {nlb_host}")
    print(f"📊 Database: {database}")
    print("-" * 60)
    
    # Test multiple connections to see load distribution
    num_connections = 10
    results = []
    
    print(f"\n📡 Testing {num_connections} connections through NLB...")
    
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = []
        for i in range(num_connections):
            time.sleep(0.1)  # Small delay between connections
            future = executor.submit(test_connection, i+1, nlb_host, database, username, password)
            futures.append(future)
        
        for future in as_completed(futures):
            results.append(future.result())
    
    # Sort results by connection number
    results.sort(key=lambda x: x['connection'])
    
    # Display results
    print("\n📊 Connection Distribution Results:")
    print("-" * 60)
    
    successful = [r for r in results if r['status'] == 'SUCCESS']
    failed = [r for r in results if r['status'] == 'FAILED']
    
    if successful:
        # Group by backend to see distribution
        backends = {}
        for r in successful:
            key = f"{r.get('namespace', 'unknown')}_{r.get('server_addr', 'unknown')}"
            if key not in backends:
                backends[key] = []
            backends[key].append(r['connection'])
        
        print(f"✅ Successful connections: {len(successful)}/{num_connections}")
        print(f"\n🎯 Load Distribution:")
        for backend, connections in backends.items():
            namespace = backend.split('_')[0]
            print(f"  • {namespace}: {len(connections)} connections - {connections}")
        
        # Show sample data access
        if successful[0].get('flight_count'):
            print(f"\n✈️  Flight records accessible: {successful[0]['flight_count']}")
    
    if failed:
        print(f"\n❌ Failed connections: {len(failed)}")
        for r in failed:
            print(f"  • Connection {r['connection']}: {r.get('error', 'Unknown error')}")
    
    # Test stickiness
    print("\n🔍 Testing session stickiness (same source IP)...")
    sticky_results = []
    for i in range(3):
        result = test_connection(f"sticky-{i+1}", nlb_host, database, username, password)
        if result['status'] == 'SUCCESS':
            print(f"  • Connection {i+1}: {result.get('namespace', 'unknown')}")
            sticky_results.append(result.get('namespace'))
    
    if len(set(sticky_results)) == 1:
        print("  ✅ Session stickiness is working (all connections went to same backend)")
    else:
        print("  ⚠️  Connections distributed across backends (stickiness may not be configured)")
    
    print("\n✨ Test complete!")

if __name__ == "__main__":
    main()