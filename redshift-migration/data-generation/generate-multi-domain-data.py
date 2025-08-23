#!/usr/bin/env python3
"""
Multi-Domain Data Generator for Redshift Migration Demo
Creates schemas and generates data for:
- Shared airline core data (shared with both Sales and Operations)
- Sales-specific data (customer, bookings, revenue)
- Operations-specific data (maintenance, crew, performance)
"""

import psycopg2
from psycopg2.extras import execute_values
import random
from datetime import datetime, timedelta
from faker import Faker
import argparse
import sys

fake = Faker()

class RedshiftDataGenerator:
    def __init__(self, host, database, user, password, port=5439):
        """Initialize connection to Redshift cluster"""
        self.connection_params = {
            'host': host,
            'database': database,
            'user': user,
            'password': password,
            'port': port
        }
        self.conn = None
        self.cur = None
        
    def connect(self):
        """Establish database connection"""
        try:
            self.conn = psycopg2.connect(**self.connection_params)
            self.cur = self.conn.cursor()
            print(f"✅ Connected to Redshift cluster at {self.connection_params['host']}")
        except Exception as e:
            print(f"❌ Failed to connect: {e}")
            sys.exit(1)
            
    def close(self):
        """Close database connection"""
        if self.cur:
            self.cur.close()
        if self.conn:
            self.conn.close()
            
    def execute_sql(self, sql, commit=True):
        """Execute SQL statement with error handling"""
        try:
            self.cur.execute(sql)
            if commit:
                self.conn.commit()
            return True
        except Exception as e:
            print(f"❌ SQL Error: {e}")
            self.conn.rollback()
            return False
            
    def create_schemas(self):
        """Create all necessary schemas"""
        print("\n📁 Creating schemas...")
        
        schemas = [
            ('shared_airline', 'Core airline data shared with all domains'),
            ('sales_domain', 'Sales and marketing specific data'),
            ('operations_domain', 'Operations and maintenance specific data'),
            ('staging', 'Staging area for ETL processes')
        ]
        
        for schema_name, comment in schemas:
            sql = f"""
            CREATE SCHEMA IF NOT EXISTS {schema_name};
            COMMENT ON SCHEMA {schema_name} IS '{comment}';
            """
            if self.execute_sql(sql):
                print(f"  ✅ Schema '{schema_name}' created")
                
    def create_shared_tables(self):
        """Create shared airline core tables"""
        print("\n📊 Creating shared airline tables...")
        
        # Airports table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS shared_airline.airports (
            airport_code CHAR(3) PRIMARY KEY,
            airport_name VARCHAR(100) NOT NULL,
            city VARCHAR(50) NOT NULL,
            state_code CHAR(2),
            country_code CHAR(2) NOT NULL,
            latitude DECIMAL(10,7),
            longitude DECIMAL(10,7),
            timezone VARCHAR(50),
            is_hub BOOLEAN DEFAULT FALSE
        ) DISTSTYLE ALL;
        """)
        
        # Aircraft table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS shared_airline.aircraft (
            aircraft_id VARCHAR(10) PRIMARY KEY,
            manufacturer VARCHAR(50) NOT NULL,
            model VARCHAR(50) NOT NULL,
            capacity_economy INTEGER,
            capacity_business INTEGER,
            capacity_first INTEGER,
            range_km INTEGER,
            cruise_speed_kmh INTEGER,
            year_manufactured INTEGER
        ) DISTSTYLE ALL;
        """)
        
        # Flights table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS shared_airline.flights (
            flight_id BIGINT IDENTITY(1,1) PRIMARY KEY,
            flight_number VARCHAR(10) NOT NULL,
            origin_airport CHAR(3) REFERENCES shared_airline.airports(airport_code),
            destination_airport CHAR(3) REFERENCES shared_airline.airports(airport_code),
            scheduled_departure TIMESTAMP NOT NULL,
            scheduled_arrival TIMESTAMP NOT NULL,
            actual_departure TIMESTAMP,
            actual_arrival TIMESTAMP,
            aircraft_id VARCHAR(10) REFERENCES shared_airline.aircraft(aircraft_id),
            status VARCHAR(20),
            created_date DATE DEFAULT CURRENT_DATE
        ) DISTKEY(flight_id) SORTKEY(scheduled_departure);
        """)
        
        # Routes table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS shared_airline.routes (
            route_id INTEGER IDENTITY(1,1) PRIMARY KEY,
            origin_airport CHAR(3) REFERENCES shared_airline.airports(airport_code),
            destination_airport CHAR(3) REFERENCES shared_airline.airports(airport_code),
            distance_km INTEGER,
            flight_duration_minutes INTEGER,
            is_international BOOLEAN,
            service_days VARCHAR(7) DEFAULT '1111111'
        ) DISTSTYLE ALL;
        """)
        
        print("  ✅ Shared airline tables created")
        
    def create_sales_tables(self):
        """Create sales domain specific tables"""
        print("\n💰 Creating sales domain tables...")
        
        # Customers table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS sales_domain.customers (
            customer_id BIGINT IDENTITY(1,1) PRIMARY KEY,
            first_name VARCHAR(50) NOT NULL,
            last_name VARCHAR(50) NOT NULL,
            email VARCHAR(100) UNIQUE NOT NULL,
            phone VARCHAR(20),
            date_of_birth DATE,
            loyalty_tier VARCHAR(20) DEFAULT 'BRONZE',
            loyalty_points INTEGER DEFAULT 0,
            total_lifetime_value DECIMAL(12,2) DEFAULT 0,
            acquisition_channel VARCHAR(50),
            acquisition_date DATE DEFAULT CURRENT_DATE,
            last_activity_date DATE
        ) DISTKEY(customer_id) SORTKEY(acquisition_date);
        """)
        
        # Bookings table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS sales_domain.bookings (
            booking_id BIGINT IDENTITY(1,1) PRIMARY KEY,
            booking_reference VARCHAR(10) UNIQUE NOT NULL,
            customer_id BIGINT REFERENCES sales_domain.customers(customer_id),
            flight_id BIGINT,
            booking_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            travel_class VARCHAR(20),
            base_price DECIMAL(10,2),
            taxes DECIMAL(10,2),
            total_price DECIMAL(10,2),
            payment_method VARCHAR(20),
            booking_status VARCHAR(20) DEFAULT 'CONFIRMED',
            cancellation_date TIMESTAMP,
            refund_amount DECIMAL(10,2)
        ) DISTKEY(customer_id) SORTKEY(booking_date);
        """)
        
        # Marketing campaigns table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS sales_domain.marketing_campaigns (
            campaign_id INTEGER IDENTITY(1,1) PRIMARY KEY,
            campaign_name VARCHAR(100) NOT NULL,
            campaign_type VARCHAR(50),
            start_date DATE NOT NULL,
            end_date DATE,
            budget DECIMAL(12,2),
            actual_spend DECIMAL(12,2),
            target_audience VARCHAR(100),
            channel VARCHAR(50),
            conversion_rate DECIMAL(5,2),
            roi DECIMAL(10,2)
        ) DISTSTYLE ALL;
        """)
        
        # Revenue analytics table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS sales_domain.daily_revenue (
            date DATE PRIMARY KEY,
            booking_revenue DECIMAL(12,2),
            ancillary_revenue DECIMAL(12,2),
            total_revenue DECIMAL(12,2),
            bookings_count INTEGER,
            average_ticket_price DECIMAL(10,2),
            cancellation_count INTEGER,
            refund_total DECIMAL(12,2)
        ) DISTKEY(date) SORTKEY(date);
        """)
        
        print("  ✅ Sales domain tables created")
        
    def create_operations_tables(self):
        """Create operations domain specific tables"""
        print("\n🔧 Creating operations domain tables...")
        
        # Aircraft maintenance table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS operations_domain.maintenance_logs (
            maintenance_id BIGINT IDENTITY(1,1) PRIMARY KEY,
            aircraft_id VARCHAR(10),
            maintenance_type VARCHAR(50),
            description TEXT,
            scheduled_date DATE,
            completed_date DATE,
            technician_id VARCHAR(20),
            hours_required DECIMAL(5,2),
            cost DECIMAL(10,2),
            next_due_date DATE,
            compliance_status VARCHAR(20)
        ) DISTKEY(aircraft_id) SORTKEY(scheduled_date);
        """)
        
        # Crew scheduling table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS operations_domain.crew_assignments (
            assignment_id BIGINT IDENTITY(1,1) PRIMARY KEY,
            crew_member_id VARCHAR(20) NOT NULL,
            crew_member_name VARCHAR(100),
            role VARCHAR(30),
            flight_id BIGINT,
            assignment_date DATE,
            duty_start_time TIMESTAMP,
            duty_end_time TIMESTAMP,
            flight_hours DECIMAL(5,2),
            rest_hours DECIMAL(5,2),
            overtime_hours DECIMAL(5,2)
        ) DISTKEY(crew_member_id) SORTKEY(assignment_date);
        """)
        
        # Operational metrics table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS operations_domain.daily_operations_metrics (
            date DATE PRIMARY KEY,
            total_flights INTEGER,
            on_time_departures INTEGER,
            on_time_arrivals INTEGER,
            cancelled_flights INTEGER,
            delayed_flights INTEGER,
            average_delay_minutes DECIMAL(5,2),
            fuel_consumption_liters DECIMAL(12,2),
            passenger_load_factor DECIMAL(5,2),
            baggage_issues INTEGER,
            safety_incidents INTEGER
        ) DISTKEY(date) SORTKEY(date);
        """)
        
        # Ground operations table
        self.execute_sql("""
        CREATE TABLE IF NOT EXISTS operations_domain.ground_handling (
            operation_id BIGINT IDENTITY(1,1) PRIMARY KEY,
            flight_id BIGINT,
            operation_type VARCHAR(50),
            start_time TIMESTAMP,
            end_time TIMESTAMP,
            gate_number VARCHAR(10),
            baggage_loaded INTEGER,
            fuel_loaded_liters DECIMAL(10,2),
            catering_loaded BOOLEAN,
            cleaning_completed BOOLEAN,
            turnaround_minutes INTEGER
        ) DISTKEY(flight_id) SORTKEY(start_time);
        """)
        
        print("  ✅ Operations domain tables created")
        
    def generate_shared_data(self, num_flights=1000, batch_size=10000):
        """Generate shared airline data"""
        print(f"\n✈️ Generating shared airline data ({num_flights:,} flights)...")
        
        # Generate airports
        airports = [
            ('JFK', 'John F. Kennedy International', 'New York', 'NY', 'US', 40.6413, -73.7781, 'America/New_York', True),
            ('LAX', 'Los Angeles International', 'Los Angeles', 'CA', 'US', 33.9425, -118.4081, 'America/Los_Angeles', True),
            ('ORD', 'Chicago O\'Hare International', 'Chicago', 'IL', 'US', 41.9742, -87.9073, 'America/Chicago', True),
            ('DFW', 'Dallas/Fort Worth International', 'Dallas', 'TX', 'US', 32.8975, -97.0403, 'America/Chicago', True),
            ('DEN', 'Denver International', 'Denver', 'CO', 'US', 39.8561, -104.6737, 'America/Denver', True),
            ('SFO', 'San Francisco International', 'San Francisco', 'CA', 'US', 37.6213, -122.3790, 'America/Los_Angeles', False),
            ('SEA', 'Seattle-Tacoma International', 'Seattle', 'WA', 'US', 47.4502, -122.3088, 'America/Los_Angeles', False),
            ('ATL', 'Hartsfield-Jackson Atlanta', 'Atlanta', 'GA', 'US', 33.6407, -84.4277, 'America/New_York', True),
            ('MIA', 'Miami International', 'Miami', 'FL', 'US', 25.7959, -80.2870, 'America/New_York', False),
            ('BOS', 'Logan International', 'Boston', 'MA', 'US', 42.3656, -71.0096, 'America/New_York', False),
        ]
        
        # First, clear existing data to avoid duplicates
        self.cur.execute("TRUNCATE TABLE shared_airline.airports")
        execute_values(self.cur, """
            INSERT INTO shared_airline.airports 
            (airport_code, airport_name, city, state_code, country_code, latitude, longitude, timezone, is_hub)
            VALUES %s
        """, airports)
        self.conn.commit()
        print(f"  ✅ Generated {len(airports)} airports")
        
        # Generate aircraft
        aircraft_data = []
        models = [
            ('Boeing', '737-800', 162, 16, 0, 5436, 842, 2010),
            ('Boeing', '777-300ER', 280, 42, 8, 13650, 905, 2015),
            ('Airbus', 'A320', 150, 18, 0, 6100, 833, 2012),
            ('Airbus', 'A350-900', 250, 44, 12, 15000, 903, 2018),
            ('Boeing', '787-9', 242, 42, 8, 14140, 903, 2016),
        ]
        
        for i in range(50):  # Generate 50 aircraft
            model = random.choice(models)
            aircraft_id = f"{model[0][:1]}{random.randint(100,999)}"
            aircraft_data.append((aircraft_id,) + model)
            
        # Clear existing aircraft data
        self.cur.execute("TRUNCATE TABLE shared_airline.aircraft")
        execute_values(self.cur, """
            INSERT INTO shared_airline.aircraft
            (aircraft_id, manufacturer, model, capacity_economy, capacity_business, capacity_first, 
             range_km, cruise_speed_kmh, year_manufactured)
            VALUES %s
        """, aircraft_data)
        self.conn.commit()
        print(f"  ✅ Generated {len(aircraft_data)} aircraft")
        
        # Generate routes
        route_data = []
        for i in range(100):
            origin, dest = random.sample([a[0] for a in airports], 2)
            distance = random.randint(500, 5000)
            duration = int(distance / 8)  # Rough estimate
            is_intl = random.choice([True, False])
            route_data.append((origin, dest, distance, duration, is_intl))
            
        execute_values(self.cur, """
            INSERT INTO shared_airline.routes
            (origin_airport, destination_airport, distance_km, flight_duration_minutes, is_international)
            VALUES %s
        """, route_data)
        self.conn.commit()
        print(f"  ✅ Generated {len(route_data)} routes")
        
        # Generate flights in batches for massive data
        print(f"  Generating {num_flights:,} flights in batches of {batch_size:,}...")
        base_date = datetime.now() - timedelta(days=365)  # Go back 1 year for more variety
        airport_codes = [a[0] for a in airports]
        flight_count = 0
        
        for batch_start in range(0, num_flights, batch_size):
            batch_end = min(batch_start + batch_size, num_flights)
            flight_data = []
            
            for i in range(batch_start, batch_end):
                # Generate unique flight numbers with more variety
                airline = random.choice(['AA', 'UA', 'DL', 'SW', 'AS', 'JB', 'NK', 'F9'])
                flight_num = f"{airline}{random.randint(1, 9999)}"
                
                origin, dest = random.sample(airport_codes, 2)
                dep_time = base_date + timedelta(
                    days=random.randint(0, 365),
                    hours=random.randint(0, 23),
                    minutes=random.choice([0, 15, 30, 45])
                )
                
                # Realistic flight duration based on rough distance
                duration_hours = random.uniform(0.5, 8)
                arr_time = dep_time + timedelta(hours=duration_hours)
                
                aircraft = random.choice(aircraft_data)[0]
                status = random.choices(
                    ['ON_TIME', 'DELAYED', 'CANCELLED', 'DIVERTED'],
                    weights=[75, 20, 4, 1]  # Realistic distribution
                )[0]
                
                if status != 'CANCELLED':
                    delay_minutes = random.choices([0, 15, 30, 60, 120], weights=[60, 20, 10, 7, 3])[0]
                    actual_dep = dep_time + timedelta(minutes=delay_minutes)
                    actual_arr = arr_time + timedelta(minutes=delay_minutes)
                else:
                    actual_dep = None
                    actual_arr = None
                
                flight_data.append((
                    flight_num, origin, dest, dep_time, arr_time, 
                    actual_dep, actual_arr, aircraft, status
                ))
            
            execute_values(self.cur, """
                INSERT INTO shared_airline.flights
                (flight_number, origin_airport, destination_airport, scheduled_departure, scheduled_arrival,
                 actual_departure, actual_arrival, aircraft_id, status)
                VALUES %s
            """, flight_data)
            self.conn.commit()
            flight_count += len(flight_data)
            
            if flight_count % 50000 == 0:
                print(f"    Progress: {flight_count:,} / {num_flights:,} flights")
                
        print(f"  ✅ Generated {flight_count:,} flights")
        
    def generate_sales_data(self, num_customers=500, num_bookings=2000, batch_size=10000):
        """Generate sales domain specific data with batching for large volumes"""
        print(f"\n💼 Generating sales domain data ({num_customers:,} customers, {num_bookings:,} bookings)...")
        
        # Generate customers
        customer_data = []
        tiers = ['BRONZE', 'SILVER', 'GOLD', 'PLATINUM']
        channels = ['WEB', 'MOBILE', 'AGENT', 'PARTNER', 'SOCIAL']
        
        for i in range(num_customers):
            customer_data.append((
                fake.first_name(),
                fake.last_name(),
                fake.email(),
                fake.phone_number()[:20],
                fake.date_of_birth(minimum_age=18, maximum_age=80),
                random.choice(tiers),
                random.randint(0, 100000),
                random.uniform(500, 50000),
                random.choice(channels),
                fake.date_between(start_date='-2y', end_date='today'),
                fake.date_between(start_date='-30d', end_date='today')
            ))
            
        execute_values(self.cur, """
            INSERT INTO sales_domain.customers
            (first_name, last_name, email, phone, date_of_birth, loyalty_tier, 
             loyalty_points, total_lifetime_value, acquisition_channel, acquisition_date, last_activity_date)
            VALUES %s
        """, customer_data)
        self.conn.commit()
        print(f"  ✅ Generated {len(customer_data)} customers")
        
        # Generate bookings in batches
        print(f"  Generating {num_bookings:,} bookings in batches...")
        classes = ['ECONOMY', 'ECONOMY', 'ECONOMY', 'BUSINESS', 'FIRST']
        payment_methods = ['CREDIT_CARD', 'DEBIT_CARD', 'PAYPAL', 'CORPORATE', 'VOUCHER', 'MILES']
        statuses = ['CONFIRMED', 'CONFIRMED', 'CONFIRMED', 'CANCELLED', 'PENDING']
        booking_count = 0
        
        # Get flight count for realistic references
        self.cur.execute("SELECT COUNT(*) FROM shared_airline.flights")
        flight_count = self.cur.fetchone()[0] or 1000
        
        for batch_start in range(0, num_bookings, batch_size):
            batch_end = min(batch_start + batch_size, num_bookings)
            booking_data = []
            
            for i in range(batch_start, batch_end):
                # More realistic pricing based on class
                travel_class = random.choice(classes)
                if travel_class == 'FIRST':
                    base_price = random.uniform(2000, 8000)
                elif travel_class == 'BUSINESS':
                    base_price = random.uniform(800, 3000)
                else:
                    base_price = random.uniform(150, 800)
                    
                taxes = base_price * random.uniform(0.08, 0.25)
                total = base_price + taxes
                status = random.choice(statuses)
                
                # Generate unique booking reference
                booking_ref = f"BK{batch_start + i:08d}"
                
                booking_data.append((
                    booking_ref,
                    random.randint(1, max(1, num_customers)),
                    random.randint(1, max(1, flight_count)),
                    fake.date_time_between(start_date='-180d', end_date='now'),
                    travel_class,
                    round(base_price, 2),
                    round(taxes, 2),
                    round(total, 2),
                    random.choice(payment_methods),
                    status,
                    fake.date_time_between(start_date='-30d', end_date='now') if status == 'CANCELLED' else None,
                    round(total * random.uniform(0.5, 0.95), 2) if status == 'CANCELLED' else None
                ))
            
            execute_values(self.cur, """
                INSERT INTO sales_domain.bookings
                (booking_reference, customer_id, flight_id, booking_date, travel_class,
                 base_price, taxes, total_price, payment_method, booking_status, 
                 cancellation_date, refund_amount)
                VALUES %s
            """, booking_data)
            self.conn.commit()
            booking_count += len(booking_data)
            
            if booking_count % 100000 == 0:
                print(f"    Progress: {booking_count:,} / {num_bookings:,} bookings")
                
        print(f"  ✅ Generated {booking_count:,} bookings")
        
        # Generate marketing campaigns
        campaign_data = []
        campaign_types = ['EMAIL', 'SOCIAL', 'SEARCH', 'DISPLAY', 'AFFILIATE']
        channels = ['GOOGLE', 'FACEBOOK', 'EMAIL', 'INSTAGRAM', 'PARTNER']
        
        for i in range(20):
            budget = random.uniform(10000, 100000)
            spend = budget * random.uniform(0.7, 1.0)
            
            campaign_data.append((
                f"Campaign {fake.catch_phrase()}",
                random.choice(campaign_types),
                fake.date_between(start_date='-6m', end_date='today'),
                fake.date_between(start_date='today', end_date='+3m'),
                budget,
                spend,
                fake.job(),
                random.choice(channels),
                random.uniform(0.5, 5.0),
                random.uniform(-50, 200)
            ))
            
        execute_values(self.cur, """
            INSERT INTO sales_domain.marketing_campaigns
            (campaign_name, campaign_type, start_date, end_date, budget, actual_spend,
             target_audience, channel, conversion_rate, roi)
            VALUES %s
        """, campaign_data)
        self.conn.commit()
        print(f"  ✅ Generated {len(campaign_data)} marketing campaigns")
        
        # Generate daily revenue data
        revenue_data = []
        base_date = datetime.now().date() - timedelta(days=90)
        
        for i in range(90):
            date = base_date + timedelta(days=i)
            booking_rev = random.uniform(50000, 200000)
            ancillary_rev = booking_rev * random.uniform(0.1, 0.3)
            
            revenue_data.append((
                date,
                booking_rev,
                ancillary_rev,
                booking_rev + ancillary_rev,
                random.randint(50, 300),
                booking_rev / random.randint(50, 300),
                random.randint(0, 20),
                random.uniform(0, 20000)
            ))
            
        # Clear existing revenue data
        self.cur.execute("TRUNCATE TABLE sales_domain.daily_revenue")
        execute_values(self.cur, """
            INSERT INTO sales_domain.daily_revenue
            (date, booking_revenue, ancillary_revenue, total_revenue, bookings_count,
             average_ticket_price, cancellation_count, refund_total)
            VALUES %s
        """, revenue_data)
        self.conn.commit()
        print(f"  ✅ Generated {len(revenue_data)} days of revenue data")
        
    def generate_operations_data(self, num_maintenance=500, num_crew=1000):
        """Generate operations domain specific data"""
        print("\n🔧 Generating operations domain data...")
        
        # Generate maintenance logs
        maintenance_data = []
        maintenance_types = ['A_CHECK', 'B_CHECK', 'C_CHECK', 'D_CHECK', 'LINE', 'UNSCHEDULED']
        
        for i in range(num_maintenance):
            scheduled = fake.date_between(start_date='-1y', end_date='+6m')
            completed = scheduled + timedelta(days=random.randint(0, 3)) if random.random() > 0.1 else None
            
            maintenance_data.append((
                f"A{random.randint(100, 999)}",  # aircraft_id
                random.choice(maintenance_types),
                fake.text(max_nb_chars=200),
                scheduled,
                completed,
                f"TECH{random.randint(100, 999)}",
                random.uniform(2, 48),
                random.uniform(1000, 50000),
                scheduled + timedelta(days=random.randint(30, 365)),
                'COMPLIANT' if completed else 'PENDING'
            ))
            
        execute_values(self.cur, """
            INSERT INTO operations_domain.maintenance_logs
            (aircraft_id, maintenance_type, description, scheduled_date, completed_date,
             technician_id, hours_required, cost, next_due_date, compliance_status)
            VALUES %s
        """, maintenance_data)
        self.conn.commit()
        print(f"  ✅ Generated {len(maintenance_data)} maintenance logs")
        
        # Generate crew assignments
        crew_data = []
        roles = ['CAPTAIN', 'FIRST_OFFICER', 'FLIGHT_ATTENDANT', 'PURSER']
        
        for i in range(num_crew):
            duty_start = fake.date_time_between(start_date='-30d', end_date='+30d')
            duty_end = duty_start + timedelta(hours=random.randint(8, 14))
            flight_hours = random.uniform(4, 12)
            
            crew_data.append((
                f"CREW{random.randint(1000, 9999)}",
                fake.name(),
                random.choice(roles),
                random.randint(1, 1000),  # flight_id
                duty_start.date(),
                duty_start,
                duty_end,
                flight_hours,
                random.uniform(8, 12),
                max(0, flight_hours - 8)
            ))
            
        execute_values(self.cur, """
            INSERT INTO operations_domain.crew_assignments
            (crew_member_id, crew_member_name, role, flight_id, assignment_date,
             duty_start_time, duty_end_time, flight_hours, rest_hours, overtime_hours)
            VALUES %s
        """, crew_data)
        self.conn.commit()
        print(f"  ✅ Generated {len(crew_data)} crew assignments")
        
        # Generate daily operations metrics
        ops_metrics = []
        base_date = datetime.now().date() - timedelta(days=90)
        
        for i in range(90):
            date = base_date + timedelta(days=i)
            total_flights = random.randint(100, 300)
            
            ops_metrics.append((
                date,
                total_flights,
                int(total_flights * random.uniform(0.7, 0.95)),  # on_time_departures
                int(total_flights * random.uniform(0.7, 0.95)),  # on_time_arrivals
                random.randint(0, 5),  # cancelled
                random.randint(5, 30),  # delayed
                random.uniform(5, 45),  # avg delay
                random.uniform(100000, 500000),  # fuel
                random.uniform(65, 95),  # load factor
                random.randint(0, 10),  # baggage issues
                random.randint(0, 2)  # safety incidents
            ))
            
        # Clear existing operational metrics
        self.cur.execute("TRUNCATE TABLE operations_domain.daily_operations_metrics")
        execute_values(self.cur, """
            INSERT INTO operations_domain.daily_operations_metrics
            (date, total_flights, on_time_departures, on_time_arrivals, cancelled_flights,
             delayed_flights, average_delay_minutes, fuel_consumption_liters, 
             passenger_load_factor, baggage_issues, safety_incidents)
            VALUES %s
        """, ops_metrics)
        self.conn.commit()
        print(f"  ✅ Generated {len(ops_metrics)} days of operations metrics")
        
        # Generate ground handling data
        ground_data = []
        operation_types = ['BOARDING', 'DEPLANING', 'REFUELING', 'CATERING', 'CLEANING', 'BAGGAGE']
        
        for i in range(num_crew):
            start_time = fake.date_time_between(start_date='-30d', end_date='now')
            end_time = start_time + timedelta(minutes=random.randint(20, 90))
            
            ground_data.append((
                random.randint(1, 1000),  # flight_id
                random.choice(operation_types),
                start_time,
                end_time,
                f"G{random.randint(1, 50)}",
                random.randint(50, 300),
                random.uniform(5000, 50000),
                random.choice([True, False]),
                random.choice([True, False]),
                int((end_time - start_time).seconds / 60)
            ))
            
        execute_values(self.cur, """
            INSERT INTO operations_domain.ground_handling
            (flight_id, operation_type, start_time, end_time, gate_number,
             baggage_loaded, fuel_loaded_liters, catering_loaded, cleaning_completed, turnaround_minutes)
            VALUES %s
        """, ground_data)
        self.conn.commit()
        print(f"  ✅ Generated {len(ground_data)} ground handling records")
        
    def create_data_sharing_views(self):
        """Create views and prepare for data sharing"""
        print("\n🔗 Creating data sharing preparation...")
        
        # Create aggregated views for easier consumption
        self.execute_sql("""
        CREATE OR REPLACE VIEW shared_airline.flight_performance AS
        SELECT 
            f.flight_number,
            f.origin_airport,
            f.destination_airport,
            f.scheduled_departure,
            f.actual_departure,
            f.status,
            a.manufacturer,
            a.model,
            r.distance_km,
            r.flight_duration_minutes
        FROM shared_airline.flights f
        JOIN shared_airline.aircraft a ON f.aircraft_id = a.aircraft_id
        LEFT JOIN shared_airline.routes r 
            ON f.origin_airport = r.origin_airport 
            AND f.destination_airport = r.destination_airport;
        """)
        
        self.execute_sql("""
        CREATE OR REPLACE VIEW sales_domain.customer_360 AS
        SELECT 
            c.customer_id,
            c.first_name,
            c.last_name,
            c.loyalty_tier,
            c.total_lifetime_value,
            COUNT(DISTINCT b.booking_id) as total_bookings,
            SUM(b.total_price) as total_spent,
            MAX(b.booking_date) as last_booking_date
        FROM sales_domain.customers c
        LEFT JOIN sales_domain.bookings b ON c.customer_id = b.customer_id
        GROUP BY 1,2,3,4,5;
        """)
        
        self.execute_sql("""
        CREATE OR REPLACE VIEW operations_domain.fleet_status AS
        SELECT 
            m.aircraft_id,
            COUNT(DISTINCT m.maintenance_id) as maintenance_count,
            MAX(m.completed_date) as last_maintenance,
            MIN(CASE WHEN m.completed_date IS NULL THEN m.scheduled_date END) as next_maintenance,
            SUM(m.cost) as total_maintenance_cost,
            m.compliance_status
        FROM operations_domain.maintenance_logs m
        GROUP BY m.aircraft_id, m.compliance_status;
        """)
        
        print("  ✅ Created data sharing views")
        
    def print_data_sharing_commands(self):
        """Print SQL commands for setting up data shares"""
        print("\n" + "="*80)
        print("📋 DATA SHARING SETUP COMMANDS")
        print("="*80)
        
        print("\n1️⃣  On PRODUCER cluster, create data shares:")
        print("-" * 40)
        print("""
-- Create shared data for both Sales and Operations
CREATE DATASHARE airline_core_share;
ALTER DATASHARE airline_core_share ADD SCHEMA shared_airline;
ALTER DATASHARE airline_core_share ADD ALL TABLES IN SCHEMA shared_airline;

-- Create Sales-specific data share
CREATE DATASHARE sales_data_share;
ALTER DATASHARE sales_data_share ADD SCHEMA sales_domain;
ALTER DATASHARE sales_data_share ADD ALL TABLES IN SCHEMA sales_domain;

-- Create Operations-specific data share
CREATE DATASHARE operations_data_share;
ALTER DATASHARE operations_data_share ADD SCHEMA operations_domain;
ALTER DATASHARE operations_data_share ADD ALL TABLES IN SCHEMA operations_domain;
        """)
        
        print("\n2️⃣  Get namespace IDs by connecting to each cluster:")
        print("-" * 40)
        print("SELECT current_namespace;")
        
        print("\n3️⃣  On PRODUCER, grant access to consumers:")
        print("-" * 40)
        print("""
-- Grant core data to both consumers
GRANT USAGE ON DATASHARE airline_core_share TO NAMESPACE '<SALES_NAMESPACE_ID>';
GRANT USAGE ON DATASHARE airline_core_share TO NAMESPACE '<OPERATIONS_NAMESPACE_ID>';

-- Grant sales data only to Sales consumer
GRANT USAGE ON DATASHARE sales_data_share TO NAMESPACE '<SALES_NAMESPACE_ID>';

-- Grant operations data only to Operations consumer
GRANT USAGE ON DATASHARE operations_data_share TO NAMESPACE '<OPERATIONS_NAMESPACE_ID>';
        """)
        
        print("\n4️⃣  On SALES CONSUMER cluster:")
        print("-" * 40)
        print("""
-- Create databases from shares
CREATE DATABASE airline_shared FROM DATASHARE airline_core_share 
    OF NAMESPACE '<PRODUCER_NAMESPACE_ID>';
    
CREATE DATABASE sales_analytics FROM DATASHARE sales_data_share 
    OF NAMESPACE '<PRODUCER_NAMESPACE_ID>';

-- Verify access
SELECT COUNT(*) FROM airline_shared.shared_airline.flights;
SELECT COUNT(*) FROM sales_analytics.sales_domain.customers;
        """)
        
        print("\n5️⃣  On OPERATIONS CONSUMER cluster:")
        print("-" * 40)
        print("""
-- Create databases from shares
CREATE DATABASE airline_shared FROM DATASHARE airline_core_share 
    OF NAMESPACE '<PRODUCER_NAMESPACE_ID>';
    
CREATE DATABASE operations_analytics FROM DATASHARE operations_data_share 
    OF NAMESPACE '<PRODUCER_NAMESPACE_ID>';

-- Verify access
SELECT COUNT(*) FROM airline_shared.shared_airline.flights;
SELECT COUNT(*) FROM operations_analytics.operations_domain.maintenance_logs;
        """)
        
        print("\n" + "="*80)
        print("✅ Data sharing setup complete!")
        print("="*80)
        
    def generate_all_data(self, scale='medium'):
        """Generate all data for all domains
        
        Scale options:
        - small: ~10K records total (testing)
        - medium: ~100K records total (demo)
        - large: ~1M records total (performance testing)
        - xlarge: ~10M records total (stress testing)
        - custom: Use provided numbers
        """
        print(f"\n🚀 Starting data generation at '{scale}' scale...")
        
        # Scale configurations
        scales = {
            'small': {
                'flights': 1_000,
                'customers': 500,
                'bookings': 2_000,
                'maintenance': 500,
                'crew': 1_000
            },
            'medium': {
                'flights': 10_000,
                'customers': 5_000,
                'bookings': 50_000,
                'maintenance': 2_000,
                'crew': 10_000
            },
            'large': {
                'flights': 100_000,
                'customers': 50_000,
                'bookings': 500_000,
                'maintenance': 20_000,
                'crew': 100_000
            },
            'xlarge': {
                'flights': 1_000_000,
                'customers': 500_000,
                'bookings': 5_000_000,
                'maintenance': 200_000,
                'crew': 1_000_000
            }
        }
        
        if scale in scales:
            config = scales[scale]
        else:
            # Default to medium if invalid scale
            config = scales['medium']
            
        print(f"\n📊 Scale Configuration:")
        print(f"  - Flights: {config['flights']:,}")
        print(f"  - Customers: {config['customers']:,}")
        print(f"  - Bookings: {config['bookings']:,}")
        print(f"  - Maintenance: {config['maintenance']:,}")
        print(f"  - Crew: {config['crew']:,}")
        
        # Create schemas
        self.create_schemas()
        
        # Create tables
        self.create_shared_tables()
        self.create_sales_tables()
        self.create_operations_tables()
        
        # Generate data with configured scale
        self.generate_shared_data(num_flights=config['flights'])
        self.generate_sales_data(
            num_customers=config['customers'], 
            num_bookings=config['bookings']
        )
        self.generate_operations_data(
            num_maintenance=config['maintenance'], 
            num_crew=config['crew']
        )
        
        # Create views
        self.create_data_sharing_views()
        
        # Print summary
        print("\n📊 Data Generation Summary:")
        print("="*50)
        
        # Get counts
        self.cur.execute("SELECT COUNT(*) FROM shared_airline.flights")
        flights_count = self.cur.fetchone()[0]
        
        self.cur.execute("SELECT COUNT(*) FROM sales_domain.customers")
        customers_count = self.cur.fetchone()[0]
        
        self.cur.execute("SELECT COUNT(*) FROM sales_domain.bookings")
        bookings_count = self.cur.fetchone()[0]
        
        self.cur.execute("SELECT COUNT(*) FROM operations_domain.maintenance_logs")
        maintenance_count = self.cur.fetchone()[0]
        
        print(f"  Shared Data:")
        print(f"    - Flights: {flights_count}")
        print(f"  Sales Domain:")
        print(f"    - Customers: {customers_count}")
        print(f"    - Bookings: {bookings_count}")
        print(f"  Operations Domain:")
        print(f"    - Maintenance Logs: {maintenance_count}")
        
        # Print data sharing commands
        self.print_data_sharing_commands()
        

def main():
    parser = argparse.ArgumentParser(description='Generate multi-domain data for Redshift migration demo')
    parser.add_argument('--host', required=True, help='Redshift cluster endpoint')
    parser.add_argument('--database', default='dev', help='Database name')
    parser.add_argument('--user', required=True, help='Database user')
    parser.add_argument('--password', required=True, help='Database password')
    parser.add_argument('--port', type=int, default=5439, help='Database port')
    parser.add_argument('--scale', default='medium', 
                       choices=['small', 'medium', 'large', 'xlarge'],
                       help='Data scale: small (~10K), medium (~100K), large (~1M), xlarge (~10M) records')
    parser.add_argument('--custom-flights', type=int, help='Custom number of flights')
    parser.add_argument('--custom-customers', type=int, help='Custom number of customers')
    parser.add_argument('--custom-bookings', type=int, help='Custom number of bookings')
    
    args = parser.parse_args()
    
    # Create generator instance
    generator = RedshiftDataGenerator(
        host=args.host,
        database=args.database,
        user=args.user,
        password=args.password,
        port=args.port
    )
    
    try:
        # Connect and generate data
        generator.connect()
        
        # If custom values provided, use them
        if args.custom_flights or args.custom_customers or args.custom_bookings:
            print("\n📊 Using custom scale configuration...")
            generator.generate_all_data(scale='custom')
        else:
            generator.generate_all_data(scale=args.scale)
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)
    finally:
        generator.close()
        
    print("\n✅ All data generation complete!")
    

if __name__ == "__main__":
    main()