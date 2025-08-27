#!/usr/bin/env python3
"""
Comprehensive Load Testing Script for Redshift Consumer Clusters
Generates intense workload with various query patterns to create robust audit logs
"""

import psycopg2
from psycopg2.pool import ThreadedConnectionPool
import random
import time
import threading
import argparse
import sys
import json
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed
import signal
import os

# Global flag for graceful shutdown
shutdown_flag = threading.Event()

class RedshiftLoadTester:
    def __init__(self, consumer_sales_config, consumer_ops_config, 
                 duration_hours=2, max_threads=20):
        """Initialize load tester with consumer cluster configurations"""
        
        self.consumer_sales_config = consumer_sales_config
        self.consumer_ops_config = consumer_ops_config
        self.duration_hours = duration_hours
        self.max_threads = max_threads
        self.start_time = datetime.now()
        self.end_time = self.start_time + timedelta(hours=duration_hours)
        
        # Statistics tracking
        self.stats = {
            'sales': {
                'queries_executed': 0,
                'errors': 0,
                'query_types': {},
                'total_duration_ms': 0
            },
            'ops': {
                'queries_executed': 0,
                'errors': 0,
                'query_types': {},
                'total_duration_ms': 0
            }
        }
        self.stats_lock = threading.Lock()
        
        # Connection pools for both consumers
        try:
            self.sales_pool = ThreadedConnectionPool(
                5, max_threads,
                host=consumer_sales_config['host'],
                database=consumer_sales_config['database'],
                user=consumer_sales_config['user'],
                password=consumer_sales_config['password'],
                port=consumer_sales_config['port']
            )
            
            self.ops_pool = ThreadedConnectionPool(
                5, max_threads,
                host=consumer_ops_config['host'],
                database=consumer_ops_config['database'],
                user=consumer_ops_config['user'],
                password=consumer_ops_config['password'],
                port=consumer_ops_config['port']
            )
            
            print(f"✅ Connected to both consumer clusters")
            print(f"  - Sales Consumer: {consumer_sales_config['host']}")
            print(f"  - Ops Consumer: {consumer_ops_config['host']}")
            
        except Exception as e:
            print(f"❌ Failed to connect to clusters: {e}")
            sys.exit(1)
    
    def get_sales_queries(self):
        """Return a collection of sales-focused queries"""
        queries = [
            # Simple queries
            ("simple_customer_count", 
             "SELECT COUNT(*) FROM sales_domain_db.sales_domain.customers"),
            
            ("simple_booking_recent",
             "SELECT * FROM sales_domain_db.sales_domain.bookings WHERE booking_date > CURRENT_DATE - INTERVAL '7 days' LIMIT 100"),
            
            ("simple_revenue_today",
             "SELECT total_revenue FROM sales_domain_db.sales_domain.daily_revenue WHERE date = CURRENT_DATE"),
            
            # Medium complexity queries
            ("medium_loyalty_distribution",
             """SELECT loyalty_tier, COUNT(*) as customer_count, 
                AVG(total_lifetime_value) as avg_ltv
                FROM sales_domain_db.sales_domain.customers 
                GROUP BY loyalty_tier 
                ORDER BY avg_ltv DESC"""),
            
            ("medium_booking_by_class",
             """SELECT travel_class, 
                COUNT(*) as bookings, 
                AVG(total_price) as avg_price,
                SUM(total_price) as total_revenue
                FROM sales_domain_db.sales_domain.bookings 
                WHERE booking_status = 'CONFIRMED'
                GROUP BY travel_class"""),
            
            ("medium_campaign_performance",
             """SELECT campaign_type, channel,
                AVG(conversion_rate) as avg_conversion,
                AVG(roi) as avg_roi
                FROM sales_domain_db.sales_domain.marketing_campaigns
                GROUP BY campaign_type, channel
                HAVING AVG(roi) > 0"""),
            
            # Complex analytical queries
            ("complex_customer_360",
             """WITH customer_metrics AS (
                    SELECT c.customer_id,
                           c.loyalty_tier,
                           COUNT(b.booking_id) as booking_count,
                           SUM(b.total_price) as total_spent,
                           AVG(b.total_price) as avg_ticket_price,
                           MAX(b.booking_date) as last_booking
                    FROM sales_domain_db.sales_domain.customers c
                    LEFT JOIN sales_domain_db.sales_domain.bookings b ON c.customer_id = b.customer_id
                    WHERE b.booking_status = 'CONFIRMED'
                    GROUP BY c.customer_id, c.loyalty_tier
                )
                SELECT loyalty_tier,
                       AVG(booking_count) as avg_bookings,
                       AVG(total_spent) as avg_spent,
                       COUNT(*) as customer_count
                FROM customer_metrics
                GROUP BY loyalty_tier
                ORDER BY avg_spent DESC"""),
            
            ("complex_revenue_trend",
             """WITH daily_metrics AS (
                    SELECT date,
                           total_revenue,
                           bookings_count,
                           LAG(total_revenue, 1) OVER (ORDER BY date) as prev_revenue,
                           LAG(total_revenue, 7) OVER (ORDER BY date) as week_ago_revenue
                    FROM sales_domain_db.sales_domain.daily_revenue
                )
                SELECT date,
                       total_revenue,
                       ROUND((total_revenue - prev_revenue) / NULLIF(prev_revenue, 0) * 100, 2) as daily_growth,
                       ROUND((total_revenue - week_ago_revenue) / NULLIF(week_ago_revenue, 0) * 100, 2) as weekly_growth
                FROM daily_metrics
                WHERE date >= CURRENT_DATE - 30
                ORDER BY date DESC"""),
            
            ("complex_cohort_analysis",
             """WITH cohort_data AS (
                    SELECT c.acquisition_date,
                           DATE_TRUNC('month', c.acquisition_date) as cohort_month,
                           c.customer_id,
                           c.acquisition_channel,
                           COUNT(b.booking_id) as bookings,
                           SUM(b.total_price) as revenue
                    FROM sales_domain_db.sales_domain.customers c
                    LEFT JOIN sales_domain_db.sales_domain.bookings b ON c.customer_id = b.customer_id
                    GROUP BY 1, 2, 3, 4
                )
                SELECT cohort_month,
                       acquisition_channel,
                       COUNT(DISTINCT customer_id) as customers,
                       AVG(bookings) as avg_bookings_per_customer,
                       SUM(revenue) as total_revenue
                FROM cohort_data
                GROUP BY cohort_month, acquisition_channel
                ORDER BY cohort_month DESC, total_revenue DESC"""),
            
            # Window functions and advanced analytics
            ("window_customer_ranking",
             """SELECT customer_id,
                       first_name,
                       last_name,
                       total_lifetime_value,
                       RANK() OVER (ORDER BY total_lifetime_value DESC) as value_rank,
                       NTILE(10) OVER (ORDER BY total_lifetime_value DESC) as value_decile,
                       PERCENT_RANK() OVER (ORDER BY total_lifetime_value DESC) as value_percentile
                FROM sales_domain_db.sales_domain.customers
                WHERE total_lifetime_value > 0
                LIMIT 1000"""),
            
            ("window_booking_patterns",
             """WITH booking_gaps AS (
                    SELECT customer_id,
                           booking_date,
                           LAG(booking_date) OVER (PARTITION BY customer_id ORDER BY booking_date) as prev_booking,
                           booking_date - LAG(booking_date) OVER (PARTITION BY customer_id ORDER BY booking_date) as days_between
                    FROM sales_domain_db.sales_domain.bookings
                    WHERE booking_status = 'CONFIRMED'
                )
                SELECT customer_id,
                       AVG(days_between) as avg_days_between_bookings,
                       MIN(days_between) as min_gap,
                       MAX(days_between) as max_gap,
                       COUNT(*) as booking_count
                FROM booking_gaps
                WHERE days_between IS NOT NULL
                GROUP BY customer_id
                HAVING COUNT(*) > 3
                ORDER BY avg_days_between_bookings
                LIMIT 500"""),
            
            # Cross-schema joins (if data sharing is set up)
            ("join_flight_bookings",
             """SELECT f.flight_number,
                       f.origin_airport,
                       f.destination_airport,
                       COUNT(b.booking_id) as bookings,
                       SUM(b.total_price) as revenue
                FROM shared_airline_db.shared_airline.flights f
                JOIN sales_domain_db.sales_domain.bookings b ON f.flight_id = b.flight_id
                WHERE f.scheduled_departure > CURRENT_DATE - INTERVAL '30 days'
                GROUP BY f.flight_number, f.origin_airport, f.destination_airport
                ORDER BY revenue DESC
                LIMIT 100"""),
            
            # Aggregation heavy queries
            ("agg_monthly_summary",
             """SELECT DATE_TRUNC('month', booking_date) as month,
                       travel_class,
                       payment_method,
                       COUNT(*) as bookings,
                       SUM(total_price) as revenue,
                       AVG(total_price) as avg_price,
                       STDDEV(total_price) as price_stddev,
                       MIN(total_price) as min_price,
                       MAX(total_price) as max_price
                FROM sales_domain_db.sales_domain.bookings
                GROUP BY CUBE(DATE_TRUNC('month', booking_date), travel_class, payment_method)
                HAVING COUNT(*) > 10
                ORDER BY month DESC, revenue DESC
                LIMIT 1000"""),
        ]
        return queries
    
    def get_operations_queries(self):
        """Return a collection of operations-focused queries"""
        queries = [
            # Simple queries
            ("simple_maintenance_count",
             "SELECT COUNT(*) FROM operations_domain_db.operations_domain.maintenance_logs"),
            
            ("simple_crew_today",
             "SELECT * FROM operations_domain_db.operations_domain.crew_assignments WHERE assignment_date = CURRENT_DATE LIMIT 100"),
            
            ("simple_metrics_recent",
             "SELECT * FROM operations_domain_db.operations_domain.daily_operations_metrics WHERE date > CURRENT_DATE - INTERVAL '7 days'"),
            
            # Medium complexity queries
            ("medium_maintenance_by_type",
             """SELECT maintenance_type,
                       COUNT(*) as count,
                       AVG(hours_required) as avg_hours,
                       SUM(cost) as total_cost
                FROM operations_domain_db.operations_domain.maintenance_logs
                GROUP BY maintenance_type
                ORDER BY total_cost DESC"""),
            
            ("medium_crew_utilization",
             """SELECT role,
                       COUNT(DISTINCT crew_member_id) as crew_count,
                       AVG(flight_hours) as avg_flight_hours,
                       AVG(overtime_hours) as avg_overtime
                FROM operations_domain_db.operations_domain.crew_assignments
                WHERE assignment_date >= CURRENT_DATE - INTERVAL '30 days'
                GROUP BY role"""),
            
            ("medium_operational_efficiency",
             """SELECT date,
                       ROUND(CAST(on_time_departures AS FLOAT) / NULLIF(total_flights, 0) * 100, 2) as otd_percentage,
                       average_delay_minutes,
                       passenger_load_factor
                FROM operations_domain_db.operations_domain.daily_operations_metrics
                WHERE date >= CURRENT_DATE - INTERVAL '90 days'
                ORDER BY date DESC"""),
            
            # Complex analytical queries
            ("complex_fleet_maintenance",
             """WITH maintenance_summary AS (
                    SELECT aircraft_id,
                           maintenance_type,
                           COUNT(*) as maintenance_count,
                           SUM(cost) as total_cost,
                           AVG(hours_required) as avg_hours,
                           MAX(completed_date) as last_maintenance
                    FROM operations_domain_db.operations_domain.maintenance_logs
                    WHERE completed_date IS NOT NULL
                    GROUP BY aircraft_id, maintenance_type
                ),
                aircraft_metrics AS (
                    SELECT aircraft_id,
                           SUM(maintenance_count) as total_maintenances,
                           SUM(total_cost) as total_maintenance_cost,
                           AVG(avg_hours) as avg_maintenance_hours
                    FROM maintenance_summary
                    GROUP BY aircraft_id
                )
                SELECT a.aircraft_id,
                       a.manufacturer,
                       a.model,
                       am.total_maintenances,
                       am.total_maintenance_cost,
                       ROUND(am.avg_maintenance_hours, 2) as avg_hours
                FROM shared_airline_db.shared_airline.aircraft a
                LEFT JOIN aircraft_metrics am ON a.aircraft_id = am.aircraft_id
                ORDER BY total_maintenance_cost DESC NULLS LAST"""),
            
            ("complex_crew_performance",
             """WITH crew_metrics AS (
                    SELECT crew_member_id,
                           crew_member_name,
                           role,
                           COUNT(*) as assignments,
                           SUM(flight_hours) as total_flight_hours,
                           SUM(overtime_hours) as total_overtime,
                           AVG(rest_hours) as avg_rest
                    FROM operations_domain_db.operations_domain.crew_assignments
                    WHERE assignment_date >= CURRENT_DATE - INTERVAL '90 days'
                    GROUP BY crew_member_id, crew_member_name, role
                )
                SELECT role,
                       COUNT(crew_member_id) as crew_count,
                       AVG(assignments) as avg_assignments,
                       AVG(total_flight_hours) as avg_total_hours,
                       MAX(total_overtime) as max_overtime
                FROM crew_metrics
                GROUP BY role
                ORDER BY avg_total_hours DESC"""),
            
            ("complex_turnaround_analysis",
             """WITH turnaround_stats AS (
                    SELECT operation_type,
                           gate_number,
                           AVG(turnaround_minutes) as avg_turnaround,
                           MIN(turnaround_minutes) as min_turnaround,
                           MAX(turnaround_minutes) as max_turnaround,
                           STDDEV(turnaround_minutes) as turnaround_stddev,
                           COUNT(*) as operation_count
                    FROM operations_domain_db.operations_domain.ground_handling
                    WHERE turnaround_minutes IS NOT NULL
                    GROUP BY operation_type, gate_number
                )
                SELECT operation_type,
                       AVG(avg_turnaround) as overall_avg_turnaround,
                       MIN(min_turnaround) as best_turnaround,
                       MAX(max_turnaround) as worst_turnaround,
                       COUNT(DISTINCT gate_number) as gates_used
                FROM turnaround_stats
                GROUP BY operation_type
                HAVING COUNT(*) > 10
                ORDER BY overall_avg_turnaround"""),
            
            # Window functions
            ("window_maintenance_schedule",
             """SELECT aircraft_id,
                       scheduled_date,
                       maintenance_type,
                       next_due_date,
                       LAG(scheduled_date) OVER (PARTITION BY aircraft_id ORDER BY scheduled_date) as prev_maintenance,
                       scheduled_date - LAG(scheduled_date) OVER (PARTITION BY aircraft_id ORDER BY scheduled_date) as days_between,
                       LEAD(scheduled_date) OVER (PARTITION BY aircraft_id ORDER BY scheduled_date) as next_maintenance
                FROM operations_domain_db.operations_domain.maintenance_logs
                WHERE scheduled_date >= CURRENT_DATE - INTERVAL '180 days'
                ORDER BY aircraft_id, scheduled_date"""),
            
            ("window_crew_rankings",
             """WITH crew_totals AS (
                    SELECT crew_member_id,
                           crew_member_name,
                           role,
                           SUM(flight_hours) as total_hours,
                           COUNT(*) as total_flights
                    FROM operations_domain_db.operations_domain.crew_assignments
                    GROUP BY crew_member_id, crew_member_name, role
                )
                SELECT crew_member_id,
                       crew_member_name,
                       role,
                       total_hours,
                       RANK() OVER (PARTITION BY role ORDER BY total_hours DESC) as hours_rank,
                       DENSE_RANK() OVER (PARTITION BY role ORDER BY total_flights DESC) as flights_rank,
                       NTILE(4) OVER (PARTITION BY role ORDER BY total_hours DESC) as quartile
                FROM crew_totals
                WHERE total_hours > 0
                LIMIT 500"""),
            
            # Cross-schema joins
            ("join_fleet_operations",
             """SELECT a.manufacturer,
                       a.model,
                       COUNT(DISTINCT f.flight_id) as flights,
                       COUNT(DISTINCT m.maintenance_id) as maintenances,
                       SUM(m.cost) as maintenance_cost
                FROM shared_airline_db.shared_airline.aircraft a
                LEFT JOIN shared_airline_db.shared_airline.flights f ON a.aircraft_id = f.aircraft_id
                LEFT JOIN operations_domain_db.operations_domain.maintenance_logs m ON a.aircraft_id = m.aircraft_id
                GROUP BY a.manufacturer, a.model
                ORDER BY flights DESC"""),
            
            # Heavy aggregations
            ("agg_daily_performance",
             """SELECT date,
                       SUM(total_flights) as flights,
                       SUM(on_time_departures) as otd,
                       SUM(delayed_flights) as delayed,
                       SUM(cancelled_flights) as cancelled,
                       AVG(average_delay_minutes) as avg_delay,
                       AVG(passenger_load_factor) as avg_load_factor,
                       SUM(fuel_consumption_liters) as total_fuel,
                       SUM(baggage_issues) as total_baggage_issues,
                       SUM(safety_incidents) as total_incidents
                FROM operations_domain_db.operations_domain.daily_operations_metrics
                GROUP BY ROLLUP(date)
                ORDER BY date DESC NULLS FIRST
                LIMIT 500"""),
        ]
        return queries
    
    def execute_query(self, pool, query_name, query_sql, cluster_type):
        """Execute a single query and track statistics"""
        conn = None
        cursor = None
        try:
            # Get connection from pool
            conn = pool.getconn()
            cursor = conn.cursor()
            
            # Track execution time
            start_time = time.time()
            cursor.execute(query_sql)
            
            # Fetch results to ensure query completes
            if query_sql.strip().upper().startswith('SELECT'):
                results = cursor.fetchall()
            
            execution_time = (time.time() - start_time) * 1000  # Convert to ms
            
            # Update statistics
            with self.stats_lock:
                self.stats[cluster_type]['queries_executed'] += 1
                self.stats[cluster_type]['total_duration_ms'] += execution_time
                
                if query_name not in self.stats[cluster_type]['query_types']:
                    self.stats[cluster_type]['query_types'][query_name] = 0
                self.stats[cluster_type]['query_types'][query_name] += 1
            
            return True
            
        except Exception as e:
            with self.stats_lock:
                self.stats[cluster_type]['errors'] += 1
            print(f"❌ Error executing {query_name} on {cluster_type}: {str(e)[:100]}")
            return False
            
        finally:
            if cursor:
                cursor.close()
            if conn:
                pool.putconn(conn)
    
    def worker_thread(self, cluster_type):
        """Worker thread that continuously executes queries"""
        if cluster_type == 'sales':
            pool = self.sales_pool
            queries = self.get_sales_queries()
        else:
            pool = self.ops_pool
            queries = self.get_operations_queries()
        
        while not shutdown_flag.is_set() and datetime.now() < self.end_time:
            # Select a random query with weighted probability
            # Favor simple queries more often for volume
            weights = [3, 3, 3, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1] + [1] * (len(queries) - 13)
            query = random.choices(queries, weights=weights[:len(queries)])[0]
            
            query_name, query_sql = query
            self.execute_query(pool, query_name, query_sql, cluster_type)
            
            # Random short delay between queries (0-2 seconds)
            time.sleep(random.uniform(0, 2))
    
    def print_stats(self):
        """Print current statistics"""
        elapsed = (datetime.now() - self.start_time).total_seconds() / 60
        
        print(f"\n{'='*60}")
        print(f"Load Test Statistics - {elapsed:.1f} minutes elapsed")
        print(f"{'='*60}")
        
        for cluster in ['sales', 'ops']:
            stats = self.stats[cluster]
            cluster_name = "Sales Consumer" if cluster == 'sales' else "Ops Consumer"
            
            print(f"\n{cluster_name}:")
            print(f"  Total Queries: {stats['queries_executed']:,}")
            print(f"  Total Errors: {stats['errors']:,}")
            
            if stats['queries_executed'] > 0:
                avg_duration = stats['total_duration_ms'] / stats['queries_executed']
                qps = stats['queries_executed'] / (elapsed * 60) if elapsed > 0 else 0
                print(f"  Avg Duration: {avg_duration:.1f}ms")
                print(f"  Queries/Second: {qps:.2f}")
                
                # Show top 5 query types
                print(f"  Top Query Types:")
                sorted_types = sorted(stats['query_types'].items(), 
                                    key=lambda x: x[1], reverse=True)[:5]
                for query_type, count in sorted_types:
                    print(f"    - {query_type}: {count:,}")
    
    def run_load_test(self):
        """Main load test execution"""
        print(f"\n🚀 Starting Load Test")
        print(f"  Duration: {self.duration_hours} hours")
        print(f"  Max Threads: {self.max_threads}")
        print(f"  Start Time: {self.start_time}")
        print(f"  End Time: {self.end_time}")
        print(f"\nPress Ctrl+C to stop early...\n")
        
        # Create worker threads
        with ThreadPoolExecutor(max_workers=self.max_threads) as executor:
            futures = []
            
            # Split threads between sales and ops clusters
            sales_threads = self.max_threads // 2
            ops_threads = self.max_threads - sales_threads
            
            # Start sales worker threads
            for i in range(sales_threads):
                futures.append(executor.submit(self.worker_thread, 'sales'))
            
            # Start ops worker threads
            for i in range(ops_threads):
                futures.append(executor.submit(self.worker_thread, 'ops'))
            
            # Print statistics periodically
            stats_interval = 60  # Print stats every minute
            last_stats_time = time.time()
            
            try:
                while datetime.now() < self.end_time and not shutdown_flag.is_set():
                    time.sleep(1)
                    
                    # Print stats periodically
                    if time.time() - last_stats_time > stats_interval:
                        self.print_stats()
                        last_stats_time = time.time()
                
                # Set shutdown flag to stop all workers
                shutdown_flag.set()
                
                # Wait for all threads to complete
                print("\n⏳ Waiting for all threads to complete...")
                for future in as_completed(futures):
                    try:
                        future.result()
                    except Exception as e:
                        print(f"Worker thread error: {e}")
                        
            except KeyboardInterrupt:
                print("\n⚠️  Interrupted by user, shutting down gracefully...")
                shutdown_flag.set()
        
        # Final statistics
        print("\n" + "="*60)
        print("FINAL LOAD TEST RESULTS")
        self.print_stats()
        
        # Save results to file
        self.save_results()
    
    def save_results(self):
        """Save test results to a JSON file"""
        results = {
            'start_time': self.start_time.isoformat(),
            'end_time': datetime.now().isoformat(),
            'duration_hours': self.duration_hours,
            'max_threads': self.max_threads,
            'clusters': {
                'sales': self.consumer_sales_config['host'],
                'ops': self.consumer_ops_config['host']
            },
            'statistics': self.stats
        }
        
        filename = f"load_test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(filename, 'w') as f:
            json.dump(results, f, indent=2)
        
        print(f"\n📊 Results saved to: {filename}")
    
    def cleanup(self):
        """Clean up connections"""
        if hasattr(self, 'sales_pool'):
            self.sales_pool.closeall()
        if hasattr(self, 'ops_pool'):
            self.ops_pool.closeall()


def signal_handler(signum, frame):
    """Handle interrupt signals gracefully"""
    print("\n⚠️  Received interrupt signal, shutting down...")
    shutdown_flag.set()


def main():
    parser = argparse.ArgumentParser(description='Load test Redshift consumer clusters')
    
    # Sales consumer arguments
    parser.add_argument('--sales-host', required=True, 
                       help='Sales consumer cluster endpoint')
    parser.add_argument('--sales-database', default='dev',
                       help='Sales consumer database name')
    parser.add_argument('--sales-user', required=True,
                       help='Sales consumer username')
    parser.add_argument('--sales-password', required=True,
                       help='Sales consumer password')
    parser.add_argument('--sales-port', type=int, default=5439,
                       help='Sales consumer port')
    
    # Ops consumer arguments
    parser.add_argument('--ops-host', required=True,
                       help='Ops consumer cluster endpoint')
    parser.add_argument('--ops-database', default='dev',
                       help='Ops consumer database name')
    parser.add_argument('--ops-user', required=True,
                       help='Ops consumer username')
    parser.add_argument('--ops-password', required=True,
                       help='Ops consumer password')
    parser.add_argument('--ops-port', type=int, default=5439,
                       help='Ops consumer port')
    
    # Test configuration
    parser.add_argument('--duration', type=float, default=2.0,
                       help='Test duration in hours (default: 2)')
    parser.add_argument('--threads', type=int, default=20,
                       help='Maximum number of concurrent threads (default: 20)')
    
    args = parser.parse_args()
    
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Configure consumer connections
    sales_config = {
        'host': args.sales_host,
        'database': args.sales_database,
        'user': args.sales_user,
        'password': args.sales_password,
        'port': args.sales_port
    }
    
    ops_config = {
        'host': args.ops_host,
        'database': args.ops_database,
        'user': args.ops_user,
        'password': args.ops_password,
        'port': args.ops_port
    }
    
    # Create and run load tester
    tester = RedshiftLoadTester(
        consumer_sales_config=sales_config,
        consumer_ops_config=ops_config,
        duration_hours=args.duration,
        max_threads=args.threads
    )
    
    try:
        tester.run_load_test()
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)
    finally:
        tester.cleanup()
        print("\n✅ Load test complete!")


if __name__ == "__main__":
    main()