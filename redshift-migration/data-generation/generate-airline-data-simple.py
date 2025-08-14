#!/usr/bin/env python3
"""
Simplified Redshift-compatible airline data generator
"""

import psycopg2
import random
from datetime import datetime, date, timedelta
import time

# Connection parameters
conn_params = {
    'host': 'my-redshift-cluster.cjsvyvjxsdqo.us-west-2.redshift.amazonaws.com',
    'port': 5439,
    'database': 'mydb',
    'user': 'admin',
    'password': 'Password123'
}

# Airport data
AIRPORTS = ['ORD', 'DFW', 'DEN', 'ATL', 'CLT', 'IAH', 'PHX', 'LAX', 'SFO', 'EWR', 
            'BOS', 'SEA', 'MSP', 'DTW', 'LAS', 'MCO', 'MIA', 'JFK', 'PHL', 'DCA']

def main():
    print("Connecting to Redshift...")
    conn = psycopg2.connect(**conn_params)
    cur = conn.cursor()
    
    try:
        # 1. Create tables if they don't exist
        print("Creating tables...")
        
        # Create dim_date
        cur.execute("""
            CREATE TABLE IF NOT EXISTS airline_dw.dim_date (
                date_key INTEGER NOT NULL PRIMARY KEY,
                full_date DATE NOT NULL,
                year SMALLINT NOT NULL,
                quarter SMALLINT NOT NULL,
                month SMALLINT NOT NULL,
                month_name VARCHAR(10) NOT NULL,
                week_of_year SMALLINT NOT NULL,
                day_of_month SMALLINT NOT NULL,
                day_of_week SMALLINT NOT NULL,
                day_name VARCHAR(10) NOT NULL,
                is_weekend BOOLEAN NOT NULL,
                is_holiday BOOLEAN DEFAULT FALSE,
                fiscal_year SMALLINT,
                fiscal_quarter SMALLINT
            )
            DISTSTYLE ALL
            SORTKEY (full_date)
        """)
        
        # Create other tables
        cur.execute("""
            CREATE TABLE IF NOT EXISTS airline_dw.dim_airport (
                airport_key INTEGER NOT NULL PRIMARY KEY,
                airport_code CHAR(3) NOT NULL,
                airport_name VARCHAR(100) NOT NULL,
                city VARCHAR(50) NOT NULL,
                state_code CHAR(2),
                country_code CHAR(2) NOT NULL,
                latitude DECIMAL(10,7),
                longitude DECIMAL(10,7),
                timezone VARCHAR(50),
                is_hub BOOLEAN DEFAULT FALSE,
                hub_type VARCHAR(20),
                valid_from DATE DEFAULT CURRENT_DATE,
                valid_to DATE DEFAULT '9999-12-31',
                is_current BOOLEAN DEFAULT TRUE
            )
            DISTSTYLE ALL
            SORTKEY (airport_code)
        """)
        
        cur.execute("""
            CREATE TABLE IF NOT EXISTS airline_dw.dim_aircraft (
                aircraft_key INTEGER NOT NULL PRIMARY KEY,
                tail_number VARCHAR(10) NOT NULL,
                aircraft_type VARCHAR(20) NOT NULL,
                manufacturer VARCHAR(50) NOT NULL,
                model VARCHAR(50) NOT NULL,
                seat_capacity_first INTEGER DEFAULT 0,
                seat_capacity_business INTEGER DEFAULT 0,
                seat_capacity_economy_plus INTEGER DEFAULT 0,
                seat_capacity_economy INTEGER NOT NULL,
                total_seat_capacity INTEGER NOT NULL,
                range_miles INTEGER,
                year_manufactured SMALLINT,
                acquisition_date DATE,
                retirement_date DATE,
                is_active BOOLEAN DEFAULT TRUE
            )
            DISTSTYLE ALL
            SORTKEY (aircraft_type, tail_number)
        """)
        
        cur.execute("""
            CREATE TABLE IF NOT EXISTS airline_dw.dim_flight (
                flight_key INTEGER NOT NULL PRIMARY KEY,
                flight_number VARCHAR(10) NOT NULL,
                origin_airport_code CHAR(3) NOT NULL,
                destination_airport_code CHAR(3) NOT NULL,
                scheduled_departure_time TIME NOT NULL,
                scheduled_arrival_time TIME NOT NULL,
                scheduled_duration_minutes INTEGER NOT NULL,
                distance_miles INTEGER,
                route_type VARCHAR(20),
                service_class VARCHAR(20),
                valid_from DATE DEFAULT CURRENT_DATE,
                valid_to DATE DEFAULT '9999-12-31',
                is_current BOOLEAN DEFAULT TRUE
            )
            DISTKEY (flight_number)
            SORTKEY (origin_airport_code, destination_airport_code)
        """)
        
        cur.execute("""
            CREATE TABLE IF NOT EXISTS airline_dw.dim_customer (
                customer_key BIGINT NOT NULL PRIMARY KEY,
                customer_id VARCHAR(20) NOT NULL,
                loyalty_number VARCHAR(20),
                loyalty_tier VARCHAR(20),
                customer_type VARCHAR(20),
                home_airport_code CHAR(3),
                country_code CHAR(2),
                registration_date DATE,
                total_lifetime_miles BIGINT DEFAULT 0,
                total_lifetime_segments INTEGER DEFAULT 0,
                is_active BOOLEAN DEFAULT TRUE
            )
            DISTKEY (customer_key)
            SORTKEY (loyalty_tier, customer_type)
        """)
        
        cur.execute("""
            CREATE TABLE IF NOT EXISTS airline_dw.fact_flight_operations (
                flight_operation_key BIGINT NOT NULL PRIMARY KEY,
                date_key INTEGER NOT NULL,
                flight_key INTEGER NOT NULL,
                aircraft_key INTEGER NOT NULL,
                scheduled_departure_datetime TIMESTAMP NOT NULL,
                actual_departure_datetime TIMESTAMP,
                departure_gate VARCHAR(10),
                departure_delay_minutes INTEGER DEFAULT 0,
                scheduled_arrival_datetime TIMESTAMP NOT NULL,
                actual_arrival_datetime TIMESTAMP,
                arrival_gate VARCHAR(10),
                arrival_delay_minutes INTEGER DEFAULT 0,
                actual_duration_minutes INTEGER,
                fuel_consumption_gallons DECIMAL(10,2),
                distance_flown_miles DECIMAL(10,2),
                passengers_first INTEGER DEFAULT 0,
                passengers_business INTEGER DEFAULT 0,
                passengers_economy_plus INTEGER DEFAULT 0,
                passengers_economy INTEGER DEFAULT 0,
                total_passengers INTEGER NOT NULL,
                cargo_weight_lbs DECIMAL(10,2) DEFAULT 0,
                mail_weight_lbs DECIMAL(10,2) DEFAULT 0,
                flight_status VARCHAR(20),
                cancellation_code VARCHAR(10),
                cancellation_reason VARCHAR(100),
                diversion_airport_code CHAR(3),
                is_on_time BOOLEAN,
                is_delayed BOOLEAN,
                is_cancelled BOOLEAN DEFAULT FALSE
            )
            DISTKEY (date_key)
            SORTKEY (date_key, scheduled_departure_datetime)
        """)
        
        cur.execute("""
            CREATE TABLE IF NOT EXISTS airline_dw.fact_bookings (
                booking_key BIGINT NOT NULL PRIMARY KEY,
                booking_date_key INTEGER NOT NULL,
                travel_date_key INTEGER NOT NULL,
                customer_key BIGINT NOT NULL,
                flight_key INTEGER NOT NULL,
                booking_reference VARCHAR(10) NOT NULL,
                booking_channel VARCHAR(20),
                booking_class CHAR(1),
                cabin_class VARCHAR(20),
                base_fare_usd DECIMAL(10,2) NOT NULL,
                taxes_fees_usd DECIMAL(10,2) NOT NULL,
                total_fare_usd DECIMAL(10,2) NOT NULL,
                bags_checked INTEGER DEFAULT 0,
                bag_fees_usd DECIMAL(10,2) DEFAULT 0,
                seat_selection_fees_usd DECIMAL(10,2) DEFAULT 0,
                other_ancillary_fees_usd DECIMAL(10,2) DEFAULT 0,
                miles_earned INTEGER DEFAULT 0,
                miles_redeemed INTEGER DEFAULT 0,
                is_award_ticket BOOLEAN DEFAULT FALSE,
                booking_status VARCHAR(20),
                is_refunded BOOLEAN DEFAULT FALSE,
                refund_amount_usd DECIMAL(10,2) DEFAULT 0
            )
            DISTKEY (customer_key)
            SORTKEY (travel_date_key, booking_date_key)
        """)
        
        cur.execute("""
            CREATE TABLE IF NOT EXISTS airline_dw.fact_daily_revenue (
                date_key INTEGER NOT NULL,
                flight_key INTEGER NOT NULL,
                ticket_revenue_usd DECIMAL(12,2),
                baggage_revenue_usd DECIMAL(12,2),
                seat_selection_revenue_usd DECIMAL(12,2),
                other_ancillary_revenue_usd DECIMAL(12,2),
                cargo_revenue_usd DECIMAL(12,2),
                mail_revenue_usd DECIMAL(12,2),
                total_revenue_usd DECIMAL(12,2),
                passenger_count INTEGER,
                average_fare_usd DECIMAL(10,2),
                load_factor DECIMAL(5,2),
                PRIMARY KEY (date_key, flight_key)
            )
            DISTKEY (date_key)
            SORTKEY (date_key, flight_key)
        """)
        
        conn.commit()
        print("Tables created successfully!")
        
        # Clear any existing data
        print("Clearing existing data...")
        tables = ['fact_daily_revenue', 'fact_bookings', 'fact_flight_operations', 
                  'dim_customer', 'dim_flight', 'dim_aircraft', 'dim_airport', 'dim_date']
        
        for table in tables:
            try:
                cur.execute(f"DELETE FROM airline_dw.{table}")
            except:
                pass
        conn.commit()
        
        # 2. Generate date dimension (2 years)
        print("Generating date dimension...")
        start_date = date(2023, 1, 1)
        end_date = date(2024, 12, 31)
        current = start_date
        
        while current <= end_date:
            date_key = int(current.strftime('%Y%m%d'))
            quarter = (current.month - 1) // 3 + 1
            is_weekend = current.weekday() >= 5
            
            cur.execute("""
                INSERT INTO airline_dw.dim_date 
                (date_key, full_date, year, quarter, month, month_name, week_of_year,
                 day_of_month, day_of_week, day_name, is_weekend, is_holiday, fiscal_year, fiscal_quarter)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                date_key, current, current.year, quarter, current.month,
                current.strftime('%B'), current.isocalendar()[1], current.day,
                current.weekday() + 1, current.strftime('%A'), is_weekend, False,
                current.year, quarter
            ))
            current += timedelta(days=1)
        
        conn.commit()
        print(f"  Generated {(end_date - start_date).days + 1} dates")
        
        # 3. Generate airports
        print("Generating airports...")
        for i, code in enumerate(AIRPORTS):
            is_hub = i < 5  # First 5 are hubs
            hub_type = 'primary' if i < 3 else 'secondary' if i < 5 else None
            
            cur.execute("""
                INSERT INTO airline_dw.dim_airport
                (airport_key, airport_code, airport_name, city, state_code, country_code, 
                 latitude, longitude, timezone, is_hub, hub_type)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                i + 1, code, f"{code} International", f"City_{code}", 'XX', 'US',
                40.0 + random.uniform(-10, 10), -100.0 + random.uniform(-20, 20),
                'America/Chicago', is_hub, hub_type
            ))
        
        conn.commit()
        print(f"  Generated {len(AIRPORTS)} airports")
        
        # 4. Generate aircraft (50 for demo)
        print("Generating aircraft...")
        aircraft_types = ['B737', 'B777', 'A320', 'A330']
        
        for i in range(50):
            aircraft_type = random.choice(aircraft_types)
            tail_number = f"N{random.randint(100, 999)}AA"
            
            cur.execute("""
                INSERT INTO airline_dw.dim_aircraft
                (aircraft_key, tail_number, aircraft_type, manufacturer, model,
                 seat_capacity_first, seat_capacity_business, seat_capacity_economy_plus,
                 seat_capacity_economy, total_seat_capacity, range_miles,
                 year_manufactured, acquisition_date, is_active)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                i + 1, tail_number, aircraft_type, 
                'Boeing' if aircraft_type.startswith('B') else 'Airbus',
                aircraft_type, 16, 0, 42, 120, 178, 3000,
                2015 + random.randint(0, 8), date(2020, 1, 1), True
            ))
        
        conn.commit()
        print("  Generated 50 aircraft")
        
        # 5. Generate flight routes
        print("Generating flight routes...")
        flight_key = 1
        flight_number = 1
        
        # Generate hub-to-hub flights
        hubs = AIRPORTS[:5]
        for origin in hubs:
            for dest in hubs:
                if origin != dest:
                    for freq in range(3):  # 3 flights per day
                        hour = 6 + freq * 6
                        
                        cur.execute("""
                            INSERT INTO airline_dw.dim_flight
                            (flight_key, flight_number, origin_airport_code, destination_airport_code,
                             scheduled_departure_time, scheduled_arrival_time,
                             scheduled_duration_minutes, distance_miles, route_type, service_class)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        """, (
                            flight_key, str(flight_number), origin, dest,
                            f"{hour:02d}:00:00", f"{(hour + 2) % 24:02d}:30:00",
                            150, 800, 'domestic', 'mainline'
                        ))
                        flight_key += 1
                        flight_number += 1
        
        conn.commit()
        print(f"  Generated {flight_number - 1} flight routes")
        
        # 6. Generate customers (1000 for demo)
        print("Generating customers...")
        tiers = ['basic', 'silver', 'gold', 'platinum']
        
        for i in range(1000):
            cur.execute("""
                INSERT INTO airline_dw.dim_customer
                (customer_key, customer_id, loyalty_number, loyalty_tier, customer_type,
                 home_airport_code, country_code, registration_date,
                 total_lifetime_miles, total_lifetime_segments, is_active)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                i + 1, f"C{i:06d}", f"FF{random.randint(100000, 999999)}",
                random.choice(tiers), 'leisure',
                random.choice(AIRPORTS), 'US', date(2020, 1, 1),
                random.randint(1000, 50000), random.randint(10, 100), True
            ))
        
        conn.commit()
        print("  Generated 1000 customers")
        
        # 7. Generate flight operations (last 30 days)
        print("Generating flight operations...")
        cur.execute("SELECT flight_key, flight_number FROM airline_dw.dim_flight")
        flights = cur.fetchall()
        
        cur.execute("SELECT aircraft_key FROM airline_dw.dim_aircraft WHERE is_active = TRUE")
        aircraft = [a[0] for a in cur.fetchall()]
        
        operations = 0
        flight_operation_key = 1
        current_date = date.today() - timedelta(days=30)
        
        while current_date <= date.today():
            date_key = int(current_date.strftime('%Y%m%d'))
            
            # Run 80% of flights each day
            daily_flights = random.sample(flights, k=int(len(flights) * 0.8))
            
            for flight_key, flight_number in daily_flights:
                departure_delay = 0 if random.random() > 0.2 else random.randint(5, 60)
                passengers = random.randint(100, 170)
                
                cur.execute("""
                    INSERT INTO airline_dw.fact_flight_operations
                    (flight_operation_key, date_key, flight_key, aircraft_key,
                     scheduled_departure_datetime, actual_departure_datetime,
                     departure_delay_minutes, scheduled_arrival_datetime, actual_arrival_datetime,
                     arrival_delay_minutes, total_passengers, passengers_first,
                     passengers_business, passengers_economy_plus, passengers_economy,
                     flight_status, is_on_time, is_delayed, is_cancelled)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    flight_operation_key, date_key, flight_key, random.choice(aircraft),
                    datetime.combine(current_date, datetime.min.time()),
                    datetime.combine(current_date, datetime.min.time()) + timedelta(minutes=departure_delay),
                    departure_delay,
                    datetime.combine(current_date, datetime.min.time()) + timedelta(hours=2),
                    datetime.combine(current_date, datetime.min.time()) + timedelta(hours=2, minutes=departure_delay),
                    departure_delay, passengers,
                    int(passengers * 0.05), int(passengers * 0.10),
                    int(passengers * 0.20), int(passengers * 0.65),
                    'completed', departure_delay <= 15, departure_delay > 15, False
                ))
                flight_operation_key += 1
                operations += 1
            
            current_date += timedelta(days=1)
            
            if operations % 1000 == 0:
                conn.commit()
                print(f"  Generated {operations} operations...")
        
        conn.commit()
        print(f"  Generated {operations} flight operations")
        
        # 8. Generate bookings
        print("Generating bookings...")
        cur.execute("SELECT customer_key FROM airline_dw.dim_customer")
        customers = [c[0] for c in cur.fetchall()]
        
        booking_key = 1
        for _ in range(5000):  # 5000 bookings for demo
            customer = random.choice(customers)
            flight = random.choice(flights)
            booking_date = date.today() - timedelta(days=random.randint(1, 60))
            travel_date = booking_date + timedelta(days=random.randint(1, 90))
            
            base_fare = random.uniform(100, 500)
            taxes = base_fare * 0.15
            
            cur.execute("""
                INSERT INTO airline_dw.fact_bookings
                (booking_key, booking_date_key, travel_date_key, customer_key, flight_key,
                 booking_reference, booking_channel, booking_class, cabin_class,
                 base_fare_usd, taxes_fees_usd, total_fare_usd,
                 bags_checked, bag_fees_usd, miles_earned, booking_status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                booking_key,
                int(booking_date.strftime('%Y%m%d')),
                int(travel_date.strftime('%Y%m%d')),
                customer, flight[0],
                f"B{random.randint(100000, 999999)}", 'website', 'Y', 'economy',
                base_fare, taxes, base_fare + taxes,
                random.randint(0, 2), random.randint(0, 2) * 35,
                int(base_fare * 5), 'confirmed'
            ))
            booking_key += 1
        
        conn.commit()
        print("  Generated 5000 bookings")
        
        print("\nData generation complete!")
        
        # Show summary
        cur.execute("""
            SELECT 
                'dim_date' as table_name, COUNT(*) as row_count FROM airline_dw.dim_date
            UNION ALL
            SELECT 'dim_airport', COUNT(*) FROM airline_dw.dim_airport
            UNION ALL
            SELECT 'dim_aircraft', COUNT(*) FROM airline_dw.dim_aircraft
            UNION ALL
            SELECT 'dim_flight', COUNT(*) FROM airline_dw.dim_flight
            UNION ALL
            SELECT 'dim_customer', COUNT(*) FROM airline_dw.dim_customer
            UNION ALL
            SELECT 'fact_flight_operations', COUNT(*) FROM airline_dw.fact_flight_operations
            UNION ALL
            SELECT 'fact_bookings', COUNT(*) FROM airline_dw.fact_bookings
        """)
        
        print("\nTable row counts:")
        for table, count in cur.fetchall():
            print(f"  {table}: {count:,}")
        
    except Exception as e:
        print(f"Error: {e}")
        conn.rollback()
    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    main()