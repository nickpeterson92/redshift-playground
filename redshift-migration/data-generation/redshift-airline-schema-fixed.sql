-- Airline Data Warehouse Schema for Redshift
-- Fixed for Query Editor compatibility

-- Create schemas first
CREATE SCHEMA IF NOT EXISTS airline_dw;
CREATE SCHEMA IF NOT EXISTS staging;

-- ==========================================
-- DIMENSION TABLES
-- ==========================================

-- Date dimension
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
SORTKEY (full_date);

-- Airport dimension
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
SORTKEY (airport_code);

-- Aircraft dimension
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
SORTKEY (aircraft_type, tail_number);

-- Flight dimension
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
SORTKEY (origin_airport_code, destination_airport_code);

-- Customer dimension
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
SORTKEY (loyalty_tier, customer_type);

-- ==========================================
-- FACT TABLES
-- ==========================================

-- Flight operations fact table
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
SORTKEY (date_key, scheduled_departure_datetime);

-- Bookings fact table
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
SORTKEY (travel_date_key, booking_date_key);

-- Revenue fact table
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
SORTKEY (date_key, flight_key);

-- ==========================================
-- STAGING TABLES
-- ==========================================

CREATE TABLE IF NOT EXISTS staging.flight_operations_raw (
    flight_date DATE,
    flight_number VARCHAR(10),
    tail_number VARCHAR(10),
    origin_airport CHAR(3),
    destination_airport CHAR(3),
    scheduled_departure TIMESTAMP,
    actual_departure TIMESTAMP,
    scheduled_arrival TIMESTAMP,
    actual_arrival TIMESTAMP,
    passengers INTEGER,
    fuel_gallons DECIMAL(10,2),
    cargo_lbs DECIMAL(10,2),
    status VARCHAR(20),
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS staging.bookings_raw (
    booking_reference VARCHAR(10),
    booking_date TIMESTAMP,
    flight_date DATE,
    flight_number VARCHAR(10),
    customer_id VARCHAR(20),
    fare_class CHAR(1),
    base_fare DECIMAL(10,2),
    total_fare DECIMAL(10,2),
    booking_channel VARCHAR(20),
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);