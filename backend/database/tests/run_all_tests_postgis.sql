\set ON_ERROR_STOP on
\encoding UTF8
\pset pager off
DO $$ BEGIN
 IF current_database() NOT IN ('wasla_unified_test','wasla_unified_test_2') THEN
 RAISE EXCEPTION 'Use a new empty wasla_unified_test database'; END IF;
 IF to_regclass('public.users') IS NOT NULL THEN RAISE EXCEPTION 'Database must be empty; do not rerun here'; END IF;
END$$;

SET client_encoding = 'UTF8';

BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE DOMAIN money_amount AS NUMERIC(12,2) CHECK (VALUE >= 0);
CREATE DOMAIN positive_measure AS NUMERIC(12,3) CHECK (VALUE > 0);
CREATE DOMAIN phone_e164 AS TEXT CHECK (VALUE ~ '^\+[1-9][0-9]{7,14}$');
CREATE DOMAIN email_address AS TEXT
    CHECK (VALUE ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' AND VALUE = lower(VALUE));
CREATE DOMAIN license_category AS TEXT
    CHECK (VALUE IN ('private', 'professional_3', 'professional_2', 'professional_1'));

CREATE TABLE users (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name               TEXT NOT NULL CHECK (btrim(full_name) <> ''),
    phone                   phone_e164,
    email                   email_address,
    email_verified_at       TIMESTAMPTZ,
    password_hash           TEXT CHECK (password_hash IS NULL OR btrim(password_hash) <> ''),
    avatar_storage_key      TEXT,
    preferred_language      TEXT NOT NULL DEFAULT 'ar' CHECK (preferred_language IN ('ar', 'en')),
    default_payment_method  TEXT CHECK (default_payment_method IN ('cash', 'wallet')),
    account_status          TEXT NOT NULL DEFAULT 'active'
                            CHECK (account_status IN ('active', 'suspended', 'deleted')),
    suspended_at            TIMESTAMPTZ,
    suspended_by            BIGINT REFERENCES users(id),
    suspension_reason       TEXT,
    deleted_at              TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_users_suspension CHECK (
        account_status <> 'suspended' OR (suspended_at IS NOT NULL AND suspension_reason IS NOT NULL)
    ),
    CONSTRAINT ck_users_live_credentials CHECK (
        account_status = 'deleted' OR (email IS NOT NULL AND phone IS NOT NULL AND password_hash IS NOT NULL)
    ),
    CONSTRAINT ck_users_email_verified CHECK (email_verified_at IS NULL OR email IS NOT NULL),
    CONSTRAINT ck_users_deleted CHECK (
        (account_status = 'deleted') = (deleted_at IS NOT NULL)
        AND (account_status <> 'deleted' OR (phone IS NULL AND email IS NULL AND password_hash IS NULL))
    )
);
CREATE UNIQUE INDEX uq_users_email_ci ON users (lower(email)) WHERE email IS NOT NULL;

CREATE TABLE roles (
    id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code  TEXT NOT NULL UNIQUE,
    name  TEXT NOT NULL
);

CREATE TABLE user_roles (
    user_id     BIGINT NOT NULL REFERENCES users(id),
    role_id     BIGINT NOT NULL REFERENCES roles(id),
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id)
);
CREATE INDEX ix_user_roles_role ON user_roles (role_id);

CREATE TABLE otp_codes (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email        email_address NOT NULL,
    code_hash    TEXT NOT NULL,
    purpose      TEXT NOT NULL CHECK (purpose IN (
                     'verify_email', 'login', 'reset_password', 'change_email', 'delete_account')),
    attempts     SMALLINT NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
    expires_at   TIMESTAMPTZ NOT NULL,
    consumed_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_otp_codes_email ON otp_codes (email, created_at DESC);

CREATE TABLE auth_sessions (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             BIGINT NOT NULL REFERENCES users(id),
    refresh_token_hash  TEXT NOT NULL UNIQUE,
    user_agent          TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked_at          TIMESTAMPTZ
);
CREATE INDEX ix_auth_sessions_user ON auth_sessions (user_id);

CREATE TABLE user_devices (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id),
    fcm_token     TEXT NOT NULL UNIQUE,
    platform      TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    app           TEXT NOT NULL CHECK (app IN ('customer', 'driver', 'admin')),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_user_devices_user ON user_devices (user_id);

CREATE TABLE notifications (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id),
    type        TEXT NOT NULL,
    title       TEXT NOT NULL,
    body        TEXT NOT NULL,
    data        JSONB NOT NULL DEFAULT '{}',
    read_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_notifications_user ON notifications (user_id, created_at DESC);

CREATE TABLE policy_versions (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_type        TEXT NOT NULL CHECK (doc_type IN ('terms', 'privacy')),
    version_number  INTEGER NOT NULL CHECK (version_number > 0),
    content_ar      TEXT NOT NULL CHECK (btrim(content_ar) <> ''),
    content_en      TEXT NOT NULL CHECK (btrim(content_en) <> ''),
    published_at    TIMESTAMPTZ,
    created_by      BIGINT REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_policy_version UNIQUE (doc_type, version_number)
);

CREATE TABLE policy_acceptances (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id            BIGINT NOT NULL REFERENCES users(id),
    policy_version_id  BIGINT NOT NULL REFERENCES policy_versions(id),
    accepted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_policy_acceptance UNIQUE (user_id, policy_version_id)
);

CREATE TABLE saved_places (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id),
    label       TEXT NOT NULL CHECK (btrim(label) <> ''),
    address     TEXT NOT NULL,
    location    GEOGRAPHY(POINT, 4326) NOT NULL,
    details     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_saved_places_label ON saved_places (user_id, lower(label));

CREATE TABLE platform_settings (
    id                             SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    commission_rate                NUMERIC(5,4) NOT NULL CHECK (commission_rate BETWEEN 0 AND 1),
    default_debt_limit             money_amount NOT NULL,
    driver_offer_timeout_seconds   INTEGER NOT NULL CHECK (driver_offer_timeout_seconds > 0),
    dispatch_radius_m              INTEGER NOT NULL CHECK (dispatch_radius_m > 0),
    cancellation_fee               money_amount NOT NULL,
    group_discount_pct             NUMERIC(5,4) NOT NULL CHECK (group_discount_pct BETWEEN 0 AND 1),
    max_group_stops                SMALLINT NOT NULL CHECK (max_group_stops >= 2),
    min_schedule_lead_minutes      INTEGER NOT NULL CHECK (min_schedule_lead_minutes >= 0),
    driver_search_timeout_minutes  INTEGER NOT NULL CHECK (driver_search_timeout_minutes > 0),
    scheduled_search_lead_minutes  INTEGER NOT NULL CHECK (scheduled_search_lead_minutes > 0),
    company_instapay_handle        TEXT NOT NULL,
    company_bank_name              TEXT,
    company_bank_account           TEXT,
    min_topup_amount               money_amount NOT NULL CHECK (min_topup_amount > 0),
    max_topup_amount               money_amount NOT NULL,
    min_driver_age                 SMALLINT NOT NULL CHECK (min_driver_age BETWEEN 18 AND 70),
    driver_payout_weekday          SMALLINT NOT NULL CHECK (driver_payout_weekday BETWEEN 0 AND 6),
    max_delivery_code_attempts     SMALLINT NOT NULL CHECK (max_delivery_code_attempts > 0),
    location_stale_seconds         INTEGER NOT NULL CHECK (location_stale_seconds > 0),
    auto_offline_after_seconds     INTEGER NOT NULL CHECK (auto_offline_after_seconds > 0),
    max_dynamic_multiplier         NUMERIC(4,2) NOT NULL CHECK (max_dynamic_multiplier >= 1),
    backhaul_discount_amount       money_amount NOT NULL,
    backhaul_min_discount_pct      NUMERIC(5,4) NOT NULL CHECK (backhaul_min_discount_pct BETWEEN 0 AND 1),
    ai_low_confidence_threshold    NUMERIC(4,3) NOT NULL CHECK (ai_low_confidence_threshold BETWEEN 0 AND 1),
    dispute_response_hours         INTEGER NOT NULL CHECK (dispute_response_hours > 0),
    updated_by                     BIGINT REFERENCES users(id),
    updated_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_settings_topup_range CHECK (min_topup_amount <= max_topup_amount),
    CONSTRAINT ck_settings_offline_after_stale CHECK (auto_offline_after_seconds > location_stale_seconds)
);

CREATE TABLE cities (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        TEXT NOT NULL UNIQUE,
    name_ar     TEXT NOT NULL UNIQUE CHECK (btrim(name_ar) <> ''),
    name_en     TEXT NOT NULL UNIQUE CHECK (btrim(name_en) <> ''),
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE service_zones (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_id     BIGINT NOT NULL REFERENCES cities(id),
    code        TEXT NOT NULL UNIQUE,
    name_ar     TEXT NOT NULL CHECK (btrim(name_ar) <> ''),
    name_en     TEXT NOT NULL CHECK (btrim(name_en) <> ''),
    boundary    GEOGRAPHY(POLYGON, 4326) NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_service_zones_boundary ON service_zones USING gist (boundary) WHERE is_active;

CREATE TABLE vehicle_types (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                  TEXT NOT NULL UNIQUE,
    name_ar               TEXT NOT NULL UNIQUE CHECK (btrim(name_ar) <> ''),
    name_en               TEXT NOT NULL UNIQUE CHECK (btrim(name_en) <> ''),
    max_payload_kg        positive_measure NOT NULL,
    cargo_volume_m3       positive_measure NOT NULL,
    bed_length_m          positive_measure NOT NULL,
    bed_width_m           positive_measure NOT NULL,
    bed_height_m          positive_measure NOT NULL,
    suitable_for_ar       TEXT,
    suitable_for_en       TEXT,
    base_fare             money_amount NOT NULL,
    per_km_rate           money_amount NOT NULL,
    helper_fee            money_amount NOT NULL DEFAULT 0,
    min_license_category  license_category NOT NULL DEFAULT 'private',
    is_active             BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE cargo_categories (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        TEXT NOT NULL UNIQUE,
    name_ar     TEXT NOT NULL CHECK (btrim(name_ar) <> ''),
    name_en     TEXT NOT NULL CHECK (btrim(name_en) <> ''),
    is_active   BOOLEAN NOT NULL DEFAULT true,
    sort_order  SMALLINT NOT NULL DEFAULT 0
);

CREATE TABLE cargo_size_options (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cargo_category_id  BIGINT NOT NULL REFERENCES cargo_categories(id),
    code               TEXT NOT NULL,
    name_ar            TEXT NOT NULL CHECK (btrim(name_ar) <> ''),
    name_en            TEXT NOT NULL CHECK (btrim(name_en) <> ''),
    approx_volume_m3   positive_measure,
    is_active          BOOLEAN NOT NULL DEFAULT true,
    sort_order         SMALLINT NOT NULL DEFAULT 0,
    CONSTRAINT uq_size_option_code UNIQUE (cargo_category_id, code),
    CONSTRAINT uq_size_option_category UNIQUE (id, cargo_category_id)
);

CREATE TABLE review_tags (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        TEXT NOT NULL UNIQUE,
    name_ar     TEXT NOT NULL CHECK (btrim(name_ar) <> ''),
    name_en     TEXT NOT NULL CHECK (btrim(name_en) <> ''),
    sentiment   TEXT NOT NULL CHECK (sentiment IN ('positive', 'negative')),
    direction   TEXT NOT NULL CHECK (direction IN ('customer_to_driver', 'driver_to_customer')),
    is_active   BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE driver_profiles (
    user_id              BIGINT PRIMARY KEY REFERENCES users(id),
    verification_status  TEXT NOT NULL DEFAULT 'draft'
                         CHECK (verification_status IN ('draft', 'pending', 'approved', 'rejected')),
    submitted_at         TIMESTAMPTZ,
    rejection_reason     TEXT,
    reviewed_by          BIGINT REFERENCES users(id),
    reviewed_at          TIMESTAMPTZ,
    city_id              BIGINT NOT NULL REFERENCES cities(id),
    date_of_birth        DATE NOT NULL,
    national_id_hash     TEXT UNIQUE CHECK (national_id_hash ~ '^[0-9a-f]{64}$'),
    national_id_last4    CHAR(4) CHECK (national_id_last4 ~ '^[0-9]{4}$'),
    max_helpers          SMALLINT NOT NULL DEFAULT 0 CHECK (max_helpers BETWEEN 0 AND 20),
    is_online            BOOLEAN NOT NULL DEFAULT false,
    current_location     GEOGRAPHY(POINT, 4326),
    location_updated_at  TIMESTAMPTZ,
    active_vehicle_id    BIGINT,
    debt_limit_override  money_amount,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_driver_rejection CHECK (verification_status <> 'rejected' OR rejection_reason IS NOT NULL),
    CONSTRAINT ck_driver_submitted CHECK (verification_status = 'draft' OR submitted_at IS NOT NULL),
    CONSTRAINT ck_driver_national_id CHECK ((national_id_hash IS NULL) = (national_id_last4 IS NULL)),
    CONSTRAINT ck_driver_online_approved CHECK (NOT is_online OR verification_status = 'approved'),
    CONSTRAINT ck_driver_online_ready CHECK (
        NOT is_online OR (current_location IS NOT NULL AND active_vehicle_id IS NOT NULL)
    )
);
CREATE INDEX ix_driver_profiles_online_location
    ON driver_profiles USING gist (current_location) WHERE is_online;

CREATE TABLE vehicles (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    driver_id         BIGINT NOT NULL REFERENCES driver_profiles(user_id),
    vehicle_type_id   BIGINT NOT NULL REFERENCES vehicle_types(id),
    plate_number      TEXT NOT NULL UNIQUE CHECK (btrim(plate_number) <> ''),
    make              TEXT NOT NULL CHECK (btrim(make) <> ''),
    model             TEXT NOT NULL CHECK (btrim(model) <> ''),
    manufacture_year  SMALLINT NOT NULL,
    color             TEXT NOT NULL CHECK (btrim(color) <> ''),
    max_payload_kg    positive_measure NOT NULL,
    cargo_length_m    positive_measure,
    cargo_width_m     positive_measure,
    cargo_height_m    positive_measure,
    status            TEXT NOT NULL DEFAULT 'pending_review'
                      CHECK (status IN ('pending_review', 'active', 'inactive', 'rejected')),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_vehicles_id_driver UNIQUE (id, driver_id)
);
CREATE INDEX ix_vehicles_driver ON vehicles (driver_id);
CREATE INDEX ix_vehicles_type ON vehicles (vehicle_type_id);

ALTER TABLE driver_profiles
    ADD CONSTRAINT fk_driver_active_vehicle
    FOREIGN KEY (active_vehicle_id, user_id) REFERENCES vehicles (id, driver_id);

CREATE TABLE driver_documents (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    driver_id         BIGINT NOT NULL REFERENCES driver_profiles(user_id),
    document_type     TEXT NOT NULL CHECK (document_type IN (
                          'national_id_front', 'national_id_back',
                          'driving_license_front', 'driving_license_back', 'profile_photo')),
    document_number   TEXT,
    license_category  license_category,
    storage_key       TEXT NOT NULL,
    expires_on        DATE,
    review_status     TEXT NOT NULL DEFAULT 'pending'
                      CHECK (review_status IN ('pending', 'approved', 'rejected')),
    reviewed_by       BIGINT REFERENCES users(id),
    reviewed_at       TIMESTAMPTZ,
    checks            JSONB CHECK (checks IS NULL OR jsonb_typeof(checks) = 'object'),
    rejection_code    TEXT CHECK (rejection_code IN (
                          'blurry', 'expiry_unreadable', 'expired', 'name_mismatch', 'wrong_document', 'other')),
    rejection_reason  TEXT,
    uploaded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    superseded_at     TIMESTAMPTZ,
    CONSTRAINT ck_driver_doc_review CHECK (
        (review_status = 'pending' AND reviewed_at IS NULL)
        OR (review_status <> 'pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    ),
    CONSTRAINT ck_driver_doc_rejection CHECK (
        (review_status = 'rejected') = (rejection_code IS NOT NULL AND btrim(COALESCE(rejection_reason, '')) <> '')
        AND (review_status = 'rejected' OR (rejection_code IS NULL AND rejection_reason IS NULL))
    ),
    CONSTRAINT ck_driver_doc_no_national_id CHECK (
        document_type NOT IN ('national_id_front', 'national_id_back') OR document_number IS NULL
    ),
    CONSTRAINT ck_driver_doc_license_category CHECK (
        (document_type = 'driving_license_front') = (license_category IS NOT NULL)
    ),
    CONSTRAINT ck_driver_doc_expiry CHECK (
        review_status <> 'approved'
        OR document_type NOT IN ('national_id_front', 'driving_license_front')
        OR expires_on IS NOT NULL
    )
);
CREATE UNIQUE INDEX uq_driver_documents_approved ON driver_documents (driver_id, document_type)
    WHERE superseded_at IS NULL AND review_status = 'approved';
CREATE UNIQUE INDEX uq_driver_documents_pending ON driver_documents (driver_id, document_type)
    WHERE superseded_at IS NULL AND review_status = 'pending';
CREATE UNIQUE INDEX uq_driver_documents_rejected ON driver_documents (driver_id, document_type)
    WHERE superseded_at IS NULL AND review_status = 'rejected';

CREATE TABLE vehicle_documents (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id        BIGINT NOT NULL REFERENCES vehicles(id),
    document_type     TEXT NOT NULL CHECK (document_type IN (
                          'vehicle_license_front', 'vehicle_license_back',
                          'vehicle_photo_front', 'vehicle_photo_side', 'vehicle_photo_rear', 'vehicle_photo_cargo')),
    document_number   TEXT,
    storage_key       TEXT NOT NULL,
    expires_on        DATE,
    review_status     TEXT NOT NULL DEFAULT 'pending'
                      CHECK (review_status IN ('pending', 'approved', 'rejected')),
    reviewed_by       BIGINT REFERENCES users(id),
    reviewed_at       TIMESTAMPTZ,
    checks            JSONB CHECK (checks IS NULL OR jsonb_typeof(checks) = 'object'),
    rejection_code    TEXT CHECK (rejection_code IN (
                          'blurry', 'expiry_unreadable', 'expired', 'name_mismatch', 'wrong_document', 'other')),
    rejection_reason  TEXT,
    uploaded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    superseded_at     TIMESTAMPTZ,
    CONSTRAINT ck_vehicle_doc_review CHECK (
        (review_status = 'pending' AND reviewed_at IS NULL)
        OR (review_status <> 'pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    ),
    CONSTRAINT ck_vehicle_doc_rejection CHECK (
        (review_status = 'rejected') = (rejection_code IS NOT NULL AND btrim(COALESCE(rejection_reason, '')) <> '')
        AND (review_status = 'rejected' OR (rejection_code IS NULL AND rejection_reason IS NULL))
    ),
    CONSTRAINT ck_vehicle_doc_expiry CHECK (
        review_status <> 'approved' OR document_type <> 'vehicle_license_front' OR expires_on IS NOT NULL
    )
);
CREATE UNIQUE INDEX uq_vehicle_documents_approved ON vehicle_documents (vehicle_id, document_type)
    WHERE superseded_at IS NULL AND review_status = 'approved';
CREATE UNIQUE INDEX uq_vehicle_documents_pending ON vehicle_documents (vehicle_id, document_type)
    WHERE superseded_at IS NULL AND review_status = 'pending';
CREATE UNIQUE INDEX uq_vehicle_documents_rejected ON vehicle_documents (vehicle_id, document_type)
    WHERE superseded_at IS NULL AND review_status = 'rejected';

CREATE TABLE payout_accounts (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id           BIGINT NOT NULL REFERENCES users(id),
    method            TEXT NOT NULL CHECK (method IN ('bank_account', 'wallet')),
    holder_name       TEXT NOT NULL CHECK (btrim(holder_name) <> ''),
    bank_name         TEXT,
    account_number    TEXT NOT NULL CHECK (btrim(account_number) <> ''),
    review_status     TEXT NOT NULL DEFAULT 'pending'
                      CHECK (review_status IN ('pending', 'approved', 'rejected')),
    reviewed_by       BIGINT REFERENCES users(id),
    reviewed_at       TIMESTAMPTZ,
    rejection_code    TEXT CHECK (rejection_code IN ('name_mismatch', 'invalid_account', 'unsupported_bank', 'other')),
    rejection_reason  TEXT,
    superseded_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_payout_account_bank CHECK (method <> 'bank_account' OR btrim(COALESCE(bank_name, '')) <> ''),
    CONSTRAINT ck_payout_account_review CHECK (
        (review_status = 'pending' AND reviewed_at IS NULL)
        OR (review_status <> 'pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    ),
    CONSTRAINT ck_payout_account_rejection CHECK (
        (review_status = 'rejected') = (rejection_code IS NOT NULL AND btrim(COALESCE(rejection_reason, '')) <> '')
        AND (review_status = 'rejected' OR (rejection_code IS NULL AND rejection_reason IS NULL))
    ),
    CONSTRAINT uq_payout_accounts_id_user UNIQUE (id, user_id)
);
CREATE UNIQUE INDEX uq_payout_accounts_current ON payout_accounts (user_id) WHERE superseded_at IS NULL;

CREATE TABLE driver_online_sessions (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    driver_id   BIGINT NOT NULL REFERENCES driver_profiles(user_id),
    vehicle_id  BIGINT,
    started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at    TIMESTAMPTZ,
    CONSTRAINT fk_session_vehicle_of_driver FOREIGN KEY (vehicle_id, driver_id) REFERENCES vehicles (id, driver_id),
    CONSTRAINT ck_session_times CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE UNIQUE INDEX uq_online_session_open ON driver_online_sessions (driver_id) WHERE ended_at IS NULL;
CREATE INDEX ix_online_sessions_driver ON driver_online_sessions (driver_id, started_at DESC);

CREATE TABLE shipment_groups (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id        BIGINT NOT NULL REFERENCES users(id),
    pickup_address     TEXT NOT NULL,
    pickup_location    GEOGRAPHY(POINT, 4326) NOT NULL,
    pickup_notes       TEXT,
    helpers_count      SMALLINT NOT NULL DEFAULT 0 CHECK (helpers_count BETWEEN 0 AND 20),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_shipment_groups_id_customer UNIQUE (id, customer_id)
);

CREATE TABLE shipments (
    id                          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id                 BIGINT NOT NULL REFERENCES users(id),
    group_id                    BIGINT,
    delivery_sequence           SMALLINT CHECK (delivery_sequence > 0),
    cargo_category_id           BIGINT NOT NULL REFERENCES cargo_categories(id),
    size_option_id              BIGINT,
    cargo_description           TEXT NOT NULL CHECK (btrim(cargo_description) <> ''),
    item_count                  SMALLINT NOT NULL CHECK (item_count > 0),
    is_fragile                  BOOLEAN NOT NULL DEFAULT false,
    weight_kg                   positive_measure,
    helpers_count               SMALLINT NOT NULL DEFAULT 0 CHECK (helpers_count BETWEEN 0 AND 20),
    requested_vehicle_type_id   BIGINT REFERENCES vehicle_types(id),
    pickup_address              TEXT NOT NULL,
    pickup_location             GEOGRAPHY(POINT, 4326) NOT NULL,
    pickup_notes                TEXT,
    pickup_zone_id              BIGINT REFERENCES service_zones(id),
    dropoff_address             TEXT NOT NULL,
    dropoff_location            GEOGRAPHY(POINT, 4326) NOT NULL,
    dropoff_notes               TEXT,
    dropoff_zone_id             BIGINT REFERENCES service_zones(id),
    pickup_type                 TEXT NOT NULL CHECK (pickup_type IN ('now', 'scheduled')),
    pickup_window_start         TIMESTAMPTZ NOT NULL,
    pickup_window_end           TIMESTAMPTZ NOT NULL,
    search_started_at           TIMESTAMPTZ,
    route_distance_m            INTEGER CHECK (route_distance_m > 0),
    route_duration_s            INTEGER CHECK (route_duration_s > 0),
    payment_method              TEXT NOT NULL CHECK (payment_method IN ('cash', 'wallet')),
    fare_paid_by                TEXT NOT NULL DEFAULT 'sender' CHECK (fare_paid_by IN ('sender', 'recipient')),
    recipient_name              TEXT CHECK (btrim(recipient_name) <> ''),
    recipient_phone             phone_e164,
    delivery_code               CHAR(4) NOT NULL CHECK (delivery_code ~ '^[0-9]{4}$'),
    status                      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
                                    'draft', 'searching_driver', 'driver_assigned',
                                    'in_progress', 'delivered', 'cancelled')),
    cancelled_at                TIMESTAMPTZ,
    cancelled_by                BIGINT REFERENCES users(id),
    cancellation_reason         TEXT,
    cancellation_party          TEXT CHECK (cancellation_party IN ('customer', 'driver', 'platform')),
    details_version             INTEGER NOT NULL DEFAULT 1 CHECK (details_version > 0),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_shipments_pickup_window CHECK (pickup_window_end >= pickup_window_start),
    CONSTRAINT ck_shipments_cancelled CHECK (
        (status = 'cancelled' AND cancelled_at IS NOT NULL AND cancellation_party IS NOT NULL)
        OR (status <> 'cancelled' AND cancellation_party IS NULL)
    ),
    CONSTRAINT ck_shipments_recipient_pair CHECK ((recipient_name IS NULL) = (recipient_phone IS NULL)),
    CONSTRAINT ck_shipments_recipient_pays CHECK (
        fare_paid_by = 'sender' OR (payment_method = 'cash' AND recipient_phone IS NOT NULL)
    ),
    CONSTRAINT ck_shipments_group_sequence CHECK ((group_id IS NULL) = (delivery_sequence IS NULL)),
    CONSTRAINT fk_shipment_size_of_category
        FOREIGN KEY (size_option_id, cargo_category_id) REFERENCES cargo_size_options (id, cargo_category_id),
    CONSTRAINT fk_shipment_group_same_customer
        FOREIGN KEY (group_id, customer_id) REFERENCES shipment_groups (id, customer_id),
    CONSTRAINT uq_shipments_group_sequence UNIQUE (group_id, delivery_sequence) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT uq_shipments_id_method UNIQUE (id, payment_method),
    CONSTRAINT uq_shipments_id_customer UNIQUE (id, customer_id)
);
CREATE INDEX ix_shipments_customer ON shipments (customer_id, created_at DESC);
CREATE INDEX ix_shipments_status ON shipments (status);
CREATE INDEX ix_shipments_group ON shipments (group_id) WHERE group_id IS NOT NULL;
CREATE INDEX ix_shipments_open_pickup
    ON shipments USING gist (pickup_location) WHERE status = 'searching_driver';
CREATE INDEX ix_shipments_created_at ON shipments (created_at);

CREATE TABLE shipment_items (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id  BIGINT NOT NULL REFERENCES shipments(id),
    description  TEXT NOT NULL,
    quantity     INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    length_m     positive_measure,
    width_m      positive_measure,
    height_m     positive_measure,
    weight_kg    positive_measure,
    source       TEXT NOT NULL DEFAULT 'customer' CHECK (source IN ('customer', 'ai')),
    CONSTRAINT uq_shipment_items_id_shipment UNIQUE (id, shipment_id)
);
CREATE INDEX ix_shipment_items_shipment ON shipment_items (shipment_id);

CREATE TABLE shipment_item_images (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id       BIGINT NOT NULL REFERENCES shipments(id),
    shipment_item_id  BIGINT,
    storage_key       TEXT NOT NULL,
    caption           TEXT,
    uploaded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_image_item_same_shipment
        FOREIGN KEY (shipment_item_id, shipment_id) REFERENCES shipment_items (id, shipment_id)
);
CREATE INDEX ix_shipment_item_images_shipment ON shipment_item_images (shipment_id);

CREATE TABLE cargo_analysis_runs (
    id                           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id                  BIGINT NOT NULL REFERENCES shipments(id),
    status                       TEXT NOT NULL DEFAULT 'queued'
                                 CHECK (status IN ('queued', 'processing', 'succeeded', 'failed')),
    model_version                TEXT NOT NULL,
    input_snapshot               JSONB NOT NULL,
    result                       JSONB,
    estimated_volume_m3          positive_measure,
    estimated_weight_kg          positive_measure,
    recommended_vehicle_type_id  BIGINT REFERENCES vehicle_types(id),
    confidence                   NUMERIC(4,3) CHECK (confidence BETWEEN 0 AND 1),
    failure_reason               TEXT,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at                 TIMESTAMPTZ,
    CONSTRAINT ck_cargo_analysis_failed CHECK (status <> 'failed' OR failure_reason IS NOT NULL)
);
CREATE INDEX ix_cargo_analysis_shipment ON cargo_analysis_runs (shipment_id);

CREATE TABLE coupons (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                   TEXT NOT NULL CHECK (btrim(code) <> ''),
    discount_type          TEXT NOT NULL CHECK (discount_type IN ('percent', 'fixed')),
    discount_value         NUMERIC(12,2) NOT NULL CHECK (discount_value > 0),
    max_discount           money_amount,
    min_order_amount       money_amount NOT NULL DEFAULT 0,
    starts_at              TIMESTAMPTZ NOT NULL,
    ends_at                TIMESTAMPTZ NOT NULL,
    max_total_uses         INTEGER CHECK (max_total_uses > 0),
    max_uses_per_customer  INTEGER NOT NULL DEFAULT 1 CHECK (max_uses_per_customer > 0),
    is_active              BOOLEAN NOT NULL DEFAULT true,
    created_by             BIGINT REFERENCES users(id),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_coupon_dates CHECK (ends_at > starts_at),
    CONSTRAINT ck_coupon_percent CHECK (discount_type <> 'percent' OR discount_value <= 100),
    CONSTRAINT ck_coupon_max_discount CHECK (discount_type = 'percent' OR max_discount IS NULL)
);
CREATE UNIQUE INDEX uq_coupons_code_ci ON coupons (lower(code));

CREATE TABLE price_quotes (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id             BIGINT NOT NULL REFERENCES shipments(id),
    vehicle_type_id         BIGINT NOT NULL REFERENCES vehicle_types(id),
    pricing_details         JSONB NOT NULL,
    pricing_source          TEXT NOT NULL CHECK (pricing_source IN ('ai', 'rules')),
    model_version           TEXT,
    standard_amount         money_amount NOT NULL CHECK (standard_amount > 0),
    transport_amount        money_amount NOT NULL CHECK (transport_amount > 0),
    helpers_count           SMALLINT NOT NULL DEFAULT 0,
    helper_fee              money_amount NOT NULL DEFAULT 0,
    helpers_amount          money_amount NOT NULL DEFAULT 0,
    return_discount_amount  money_amount NOT NULL DEFAULT 0,
    group_discount_amount   money_amount NOT NULL DEFAULT 0,
    amount                  money_amount NOT NULL CHECK (amount > 0),
    coupon_id               BIGINT REFERENCES coupons(id),
    coupon_discount_amount  money_amount NOT NULL DEFAULT 0,
    customer_amount         money_amount NOT NULL CHECK (customer_amount > 0),
    commission_rate         NUMERIC(5,4) NOT NULL CHECK (commission_rate BETWEEN 0 AND 1),
    shipment_version        INTEGER NOT NULL,
    expires_at              TIMESTAMPTZ NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'offered'
                            CHECK (status IN ('offered', 'accepted', 'rejected', 'expired', 'withdrawn')),
    accepted_at             TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_quote_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_quote_accepted CHECK (
        (status <> 'accepted' OR accepted_at IS NOT NULL)
        AND (status IN ('accepted', 'withdrawn') OR accepted_at IS NULL)
        AND (accepted_at IS NULL OR accepted_at <= expires_at)
    ),
    CONSTRAINT ck_quote_helpers CHECK (helpers_amount = helpers_count * helper_fee),
    CONSTRAINT ck_quote_amount CHECK (
        amount = transport_amount + helpers_amount - return_discount_amount - group_discount_amount
    ),
    CONSTRAINT ck_quote_customer_amount CHECK (customer_amount = amount - coupon_discount_amount),
    CONSTRAINT ck_quote_coupon CHECK (coupon_id IS NOT NULL OR coupon_discount_amount = 0),
    CONSTRAINT uq_quote_shipment UNIQUE (id, shipment_id),
    CONSTRAINT uq_quote_customer_amount UNIQUE (id, shipment_id, customer_amount),
    CONSTRAINT uq_quote_agreement UNIQUE (id, shipment_id, amount, commission_rate)
);
CREATE INDEX ix_price_quotes_shipment ON price_quotes (shipment_id);
CREATE UNIQUE INDEX uq_shipment_accepted_quote ON price_quotes (shipment_id) WHERE status = 'accepted';

CREATE TABLE coupon_redemptions (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    coupon_id        BIGINT NOT NULL REFERENCES coupons(id),
    customer_id      BIGINT NOT NULL,
    shipment_id      BIGINT NOT NULL,
    price_quote_id   BIGINT NOT NULL,
    discount_amount  money_amount NOT NULL CHECK (discount_amount > 0),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    cancelled_at     TIMESTAMPTZ,
    CONSTRAINT fk_redemption_shipment_customer FOREIGN KEY (shipment_id, customer_id) REFERENCES shipments (id, customer_id),
    CONSTRAINT fk_redemption_quote_shipment FOREIGN KEY (price_quote_id, shipment_id) REFERENCES price_quotes (id, shipment_id)
);
CREATE UNIQUE INDEX uq_redemption_per_shipment ON coupon_redemptions (shipment_id) WHERE cancelled_at IS NULL;
CREATE INDEX ix_redemptions_coupon ON coupon_redemptions (coupon_id, customer_id);

CREATE TABLE trips (
    id                         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id                BIGINT NOT NULL REFERENCES shipments(id),
    group_id                   BIGINT REFERENCES shipment_groups(id),
    driver_id                  BIGINT NOT NULL REFERENCES driver_profiles(user_id),
    vehicle_id                 BIGINT NOT NULL,
    price_quote_id             BIGINT NOT NULL,
    fare_amount                money_amount NOT NULL,
    commission_rate            NUMERIC(5,4) NOT NULL,
    return_match_proposal_id   BIGINT UNIQUE,
    status                     TEXT NOT NULL DEFAULT 'assigned' CHECK (status IN (
                                   'assigned',
                                   'heading_to_pickup',
                                   'arrived_at_pickup',
                                   'loaded',
                                   'heading_to_dropoff',
                                   'arrived_at_dropoff',
                                   'delivered',
                                   'cancelled')),
    planned_start_at           TIMESTAMPTZ NOT NULL,
    planned_end_at             TIMESTAMPTZ NOT NULL,
    started_at                 TIMESTAMPTZ,
    loaded_at                  TIMESTAMPTZ,
    delivered_at               TIMESTAMPTZ,
    cancelled_at               TIMESTAMPTZ,
    cancelled_by               BIGINT REFERENCES users(id),
    cancellation_reason        TEXT,
    cancellation_party         TEXT CHECK (cancellation_party IN ('customer', 'driver', 'platform')),
    cancellation_ticket_id     BIGINT,
    is_late_cancellation       BOOLEAN NOT NULL DEFAULT false,
    cancellation_fee           money_amount NOT NULL DEFAULT 0,
    vehicle_fit                TEXT CHECK (vehicle_fit IN ('suitable', 'too_small', 'too_large')),
    departure_checked_at       TIMESTAMPTZ,
    delivery_code_attempts     SMALLINT NOT NULL DEFAULT 0 CHECK (delivery_code_attempts >= 0),
    delivery_code_verified_at  TIMESTAMPTZ,
    commission_amount          money_amount,
    driver_earning_amount      money_amount,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_trip_vehicle_of_driver
        FOREIGN KEY (vehicle_id, driver_id) REFERENCES vehicles (id, driver_id),
    CONSTRAINT fk_trip_agreed_quote
        FOREIGN KEY (price_quote_id, shipment_id, fare_amount, commission_rate)
        REFERENCES price_quotes (id, shipment_id, amount, commission_rate),
    CONSTRAINT ck_trip_planned_time CHECK (planned_end_at > planned_start_at),
    CONSTRAINT ck_trip_actual_time CHECK (delivered_at IS NULL OR started_at IS NULL OR delivered_at >= started_at),
    CONSTRAINT ck_trip_delivered CHECK (
        status <> 'delivered'
        OR (delivered_at IS NOT NULL AND commission_amount IS NOT NULL AND driver_earning_amount IS NOT NULL
            AND delivery_code_verified_at IS NOT NULL)
    ),
    CONSTRAINT ck_trip_money_split CHECK (
        commission_amount IS NULL OR (
            commission_amount = round(fare_amount * commission_rate, 2)
            AND driver_earning_amount = fare_amount - commission_amount)
    ),
    CONSTRAINT ck_trip_cancelled CHECK (
        (status = 'cancelled' AND cancelled_at IS NOT NULL AND cancellation_party IS NOT NULL)
        OR (status <> 'cancelled' AND cancellation_party IS NULL)
    ),
    CONSTRAINT ck_trip_late_cancel CHECK (
        NOT is_late_cancellation OR (status = 'cancelled' AND cancellation_party = 'customer')
    ),
    CONSTRAINT ck_trip_cancel_fee CHECK (cancellation_fee = 0 OR is_late_cancellation),
    CONSTRAINT ck_trip_vehicle_fit CHECK ((vehicle_fit IS NULL) = (departure_checked_at IS NULL)),
    CONSTRAINT ex_trips_driver_executing EXCLUDE USING gist (
        driver_id WITH =, (COALESCE(group_id, -id)) WITH <>
    ) WHERE (status IN ('heading_to_pickup', 'arrived_at_pickup', 'loaded', 'heading_to_dropoff', 'arrived_at_dropoff')),
    CONSTRAINT ex_trips_vehicle_executing EXCLUDE USING gist (
        vehicle_id WITH =, (COALESCE(group_id, -id)) WITH <>
    ) WHERE (status IN ('heading_to_pickup', 'arrived_at_pickup', 'loaded', 'heading_to_dropoff', 'arrived_at_dropoff')),
    CONSTRAINT ex_trips_driver_schedule EXCLUDE USING gist (
        driver_id WITH =, tstzrange(planned_start_at, planned_end_at, '[)') WITH &&,
        (COALESCE(group_id, -id)) WITH <>
    ) WHERE (status NOT IN ('delivered', 'cancelled')),
    CONSTRAINT ex_trips_vehicle_schedule EXCLUDE USING gist (
        vehicle_id WITH =, tstzrange(planned_start_at, planned_end_at, '[)') WITH &&,
        (COALESCE(group_id, -id)) WITH <>
    ) WHERE (status NOT IN ('delivered', 'cancelled')),
    CONSTRAINT uq_trips_id_driver UNIQUE (id, driver_id),
    CONSTRAINT uq_trips_id_shipment UNIQUE (id, shipment_id),
    CONSTRAINT uq_trips_id_shipment_driver UNIQUE (id, shipment_id, driver_id),
    CONSTRAINT uq_trips_offer_match UNIQUE (id, shipment_id, driver_id, vehicle_id, price_quote_id)
);
CREATE UNIQUE INDEX uq_shipment_live_trip ON trips (shipment_id) WHERE status <> 'cancelled';
CREATE INDEX ix_trips_driver ON trips (driver_id, created_at DESC);
CREATE INDEX ix_trips_status ON trips (status);
CREATE INDEX ix_trips_group ON trips (group_id) WHERE group_id IS NOT NULL;
CREATE INDEX ix_trips_delivered_at ON trips (delivered_at) WHERE status = 'delivered';

CREATE TABLE dispatch_offers (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id           BIGINT REFERENCES shipments(id),
    price_quote_id        BIGINT,
    group_id              BIGINT REFERENCES shipment_groups(id),
    driver_id             BIGINT NOT NULL REFERENCES driver_profiles(user_id),
    vehicle_id            BIGINT NOT NULL,
    distance_to_pickup_m  INTEGER NOT NULL CHECK (distance_to_pickup_m >= 0),
    response              TEXT NOT NULL DEFAULT 'pending'
                          CHECK (response IN ('pending', 'accepted', 'rejected', 'expired', 'cancelled')),
    sent_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at            TIMESTAMPTZ NOT NULL,
    responded_at          TIMESTAMPTZ,
    trip_id               BIGINT UNIQUE,
    CONSTRAINT fk_offer_vehicle_of_driver
        FOREIGN KEY (vehicle_id, driver_id) REFERENCES vehicles (id, driver_id),
    CONSTRAINT fk_offer_quote_same_shipment
        FOREIGN KEY (price_quote_id, shipment_id) REFERENCES price_quotes (id, shipment_id),
    CONSTRAINT fk_offer_trip_exact_match
        FOREIGN KEY (trip_id, shipment_id, driver_id, vehicle_id, price_quote_id)
        REFERENCES trips (id, shipment_id, driver_id, vehicle_id, price_quote_id),
    CONSTRAINT ck_offer_target CHECK (
        (shipment_id IS NOT NULL AND price_quote_id IS NOT NULL AND group_id IS NULL)
        OR (group_id IS NOT NULL AND shipment_id IS NULL AND price_quote_id IS NULL AND trip_id IS NULL)
    ),
    CONSTRAINT ck_offer_expiry CHECK (expires_at > sent_at),
    CONSTRAINT ck_offer_responded CHECK (response IN ('pending', 'expired', 'cancelled') OR responded_at IS NOT NULL),
    CONSTRAINT ck_offer_accepted_trip CHECK (group_id IS NOT NULL OR (response = 'accepted') = (trip_id IS NOT NULL))
);
CREATE UNIQUE INDEX uq_offer_pending_per_driver
    ON dispatch_offers (shipment_id, driver_id) WHERE response = 'pending' AND shipment_id IS NOT NULL;
CREATE UNIQUE INDEX uq_group_offer_pending_per_driver
    ON dispatch_offers (group_id, driver_id) WHERE response = 'pending' AND group_id IS NOT NULL;
CREATE INDEX ix_dispatch_offers_shipment ON dispatch_offers (shipment_id);
CREATE INDEX ix_dispatch_offers_driver ON dispatch_offers (driver_id, sent_at DESC);

CREATE TABLE trip_photos (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id      BIGINT NOT NULL REFERENCES trips(id),
    stage        TEXT NOT NULL CHECK (stage IN ('pickup', 'delivery')),
    storage_key  TEXT NOT NULL,
    uploaded_by  BIGINT NOT NULL REFERENCES users(id),
    uploaded_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_trip_photos_trip ON trip_photos (trip_id, stage);

CREATE TABLE shipment_status_history (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id         BIGINT NOT NULL REFERENCES shipments(id),
    from_status         TEXT,
    to_status           TEXT NOT NULL,
    changed_by_user_id  BIGINT REFERENCES users(id),
    change_source       TEXT NOT NULL CHECK (change_source IN ('customer', 'driver', 'admin', 'system')),
    reason              TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_shipment_status_history_shipment ON shipment_status_history (shipment_id, created_at);

CREATE TABLE trip_status_history (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id             BIGINT NOT NULL REFERENCES trips(id),
    from_status         TEXT,
    to_status           TEXT NOT NULL,
    changed_by_user_id  BIGINT REFERENCES users(id),
    change_source       TEXT NOT NULL CHECK (change_source IN ('customer', 'driver', 'admin', 'system')),
    reason              TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_trip_status_history_trip ON trip_status_history (trip_id, created_at);

CREATE TABLE trip_location_points (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id      BIGINT NOT NULL REFERENCES trips(id),
    location     GEOGRAPHY(POINT, 4326) NOT NULL,
    recorded_at  TIMESTAMPTZ NOT NULL,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    accuracy_m   NUMERIC(8,2) CHECK (accuracy_m >= 0)
);
CREATE INDEX ix_trip_location_points_trip ON trip_location_points (trip_id, recorded_at DESC);

CREATE TABLE delivery_code_attempts (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id       BIGINT NOT NULL REFERENCES trips(id),
    entered_code  CHAR(4) NOT NULL CHECK (entered_code ~ '^[0-9]{4}$'),
    is_correct    BOOLEAN NOT NULL,
    attempted_by  BIGINT REFERENCES users(id),
    attempted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_delivery_code_attempts_trip ON delivery_code_attempts (trip_id);

CREATE TABLE return_match_proposals (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    outbound_trip_id       BIGINT NOT NULL,
    driver_id              BIGINT NOT NULL,
    shipment_id            BIGINT NOT NULL REFERENCES shipments(id),
    price_quote_id         BIGINT NOT NULL UNIQUE,
    proposed_pickup_at     TIMESTAMPTZ NOT NULL,
    proposed_dropoff_at    TIMESTAMPTZ NOT NULL,
    match_score            NUMERIC(4,3) CHECK (match_score BETWEEN 0 AND 1),
    model_version          TEXT,
    status                 TEXT NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'confirmed', 'rejected', 'expired', 'withdrawn')),
    driver_response        TEXT NOT NULL DEFAULT 'pending'
                           CHECK (driver_response IN ('pending', 'accepted', 'rejected')),
    customer_response      TEXT NOT NULL DEFAULT 'pending'
                           CHECK (customer_response IN ('pending', 'accepted', 'rejected')),
    driver_responded_at    TIMESTAMPTZ,
    customer_responded_at  TIMESTAMPTZ,
    expires_at             TIMESTAMPTZ NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_return_outbound_driver
        FOREIGN KEY (outbound_trip_id, driver_id) REFERENCES trips (id, driver_id),
    CONSTRAINT fk_return_quote_same_shipment
        FOREIGN KEY (price_quote_id, shipment_id) REFERENCES price_quotes (id, shipment_id),
    CONSTRAINT ck_return_times CHECK (proposed_dropoff_at > proposed_pickup_at AND expires_at > created_at),
    CONSTRAINT ck_return_both_accepted CHECK (
        status <> 'confirmed' OR (
            driver_response = 'accepted' AND customer_response = 'accepted'
            AND driver_responded_at IS NOT NULL AND customer_responded_at IS NOT NULL
            AND driver_responded_at <= expires_at AND customer_responded_at <= expires_at)
    ),
    CONSTRAINT ck_return_response_times CHECK (
        (driver_response = 'pending') = (driver_responded_at IS NULL)
        AND (customer_response = 'pending') = (customer_responded_at IS NULL)
    ),
    CONSTRAINT uq_return_proposal_agreement UNIQUE (id, shipment_id, price_quote_id, driver_id)
);
CREATE INDEX ix_return_proposals_outbound ON return_match_proposals (outbound_trip_id);
CREATE INDEX ix_return_proposals_shipment ON return_match_proposals (shipment_id);

ALTER TABLE trips
    ADD CONSTRAINT fk_trip_return_same_agreement
    FOREIGN KEY (return_match_proposal_id, shipment_id, price_quote_id, driver_id)
    REFERENCES return_match_proposals (id, shipment_id, price_quote_id, driver_id);

CREATE TABLE trip_share_links (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id     BIGINT NOT NULL REFERENCES trips(id),
    token_hash  TEXT NOT NULL UNIQUE,
    created_by  BIGINT REFERENCES users(id),
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_share_link_expiry CHECK (expires_at > created_at)
);
CREATE INDEX ix_trip_share_links_trip ON trip_share_links (trip_id);

CREATE TABLE payments (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id             BIGINT NOT NULL,
    price_quote_id          BIGINT NOT NULL,
    method                  TEXT NOT NULL CHECK (method IN ('cash', 'wallet')),
    payer                   TEXT NOT NULL CHECK (payer IN ('sender', 'recipient')),
    amount                  money_amount NOT NULL CHECK (amount > 0),
    status                  TEXT NOT NULL CHECK (status IN ('paid', 'collected', 'charged_to_sender')),
    collected_on_trip_id    BIGINT,
    collected_by_driver_id  BIGINT,
    collected_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_payment_shipment_method
        FOREIGN KEY (shipment_id, method) REFERENCES shipments (id, payment_method),
    CONSTRAINT fk_payment_quote_amount
        FOREIGN KEY (price_quote_id, shipment_id, amount) REFERENCES price_quotes (id, shipment_id, customer_amount),
    CONSTRAINT fk_payment_collector_on_trip
        FOREIGN KEY (collected_on_trip_id, shipment_id, collected_by_driver_id)
        REFERENCES trips (id, shipment_id, driver_id),
    CONSTRAINT ck_payment_wallet CHECK (
        method <> 'wallet' OR (status = 'paid' AND payer = 'sender'
                               AND collected_on_trip_id IS NULL AND collected_by_driver_id IS NULL)
    ),
    CONSTRAINT ck_payment_cash CHECK (
        method <> 'cash' OR (status IN ('collected', 'charged_to_sender')
                             AND collected_on_trip_id IS NOT NULL AND collected_by_driver_id IS NOT NULL
                             AND collected_at IS NOT NULL)
    ),
    CONSTRAINT ck_payment_refused CHECK (status <> 'charged_to_sender' OR payer = 'recipient'),
    CONSTRAINT uq_payments_id_shipment UNIQUE (id, shipment_id)
);
CREATE UNIQUE INDEX uq_payment_wallet_per_shipment ON payments (shipment_id) WHERE method = 'wallet';
CREATE UNIQUE INDEX uq_payment_cash_per_trip ON payments (collected_on_trip_id) WHERE collected_on_trip_id IS NOT NULL;

CREATE TABLE driver_settlements (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    driver_id           BIGINT NOT NULL REFERENCES driver_profiles(user_id),
    amount              money_amount NOT NULL CHECK (amount > 0),
    proof_storage_key   TEXT NOT NULL,
    transfer_reference  TEXT,
    status              TEXT NOT NULL DEFAULT 'awaiting_verification'
                        CHECK (status IN ('awaiting_verification', 'verified', 'rejected')),
    verified_by         BIGINT REFERENCES users(id),
    verified_at         TIMESTAMPTZ,
    rejection_reason    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_settlement_reviewed CHECK (
        status = 'awaiting_verification' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)
    ),
    CONSTRAINT ck_settlement_rejected CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL),
    CONSTRAINT ck_settlement_verified_reference CHECK (status <> 'verified' OR btrim(COALESCE(transfer_reference, '')) <> ''),
    CONSTRAINT uq_settlements_id_driver UNIQUE (id, driver_id)
);
CREATE INDEX ix_driver_settlements_driver ON driver_settlements (driver_id);
CREATE UNIQUE INDEX uq_settlement_verified_reference ON driver_settlements (lower(btrim(transfer_reference))) WHERE status = 'verified';

CREATE TABLE payout_requests (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    driver_id           BIGINT NOT NULL REFERENCES driver_profiles(user_id),
    payout_account_id   BIGINT NOT NULL,
    amount              money_amount NOT NULL CHECK (amount > 0),
    status              TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'paid', 'rejected')),
    created_by          BIGINT REFERENCES users(id),
    processed_by        BIGINT REFERENCES users(id),
    processed_at        TIMESTAMPTZ,
    transfer_reference  TEXT,
    rejection_reason    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_payout_account_of_driver
        FOREIGN KEY (payout_account_id, driver_id) REFERENCES payout_accounts (id, user_id),
    CONSTRAINT ck_payout_processed CHECK (status = 'requested' OR (processed_by IS NOT NULL AND processed_at IS NOT NULL)),
    CONSTRAINT ck_payout_paid CHECK (status <> 'paid' OR transfer_reference IS NOT NULL),
    CONSTRAINT ck_payout_rejected CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL),
    CONSTRAINT uq_payouts_id_driver UNIQUE (id, driver_id)
);
CREATE UNIQUE INDEX uq_payout_open_per_driver ON payout_requests (driver_id) WHERE status = 'requested';

CREATE TABLE disputes (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id               BIGINT NOT NULL,
    shipment_id           BIGINT NOT NULL,
    opened_by             BIGINT NOT NULL REFERENCES users(id),
    reason                TEXT NOT NULL CHECK (reason IN (
                              'damaged_items', 'missing_items', 'late_delivery',
                              'driver_behavior', 'customer_behavior', 'payment_issue', 'other')),
    description           TEXT NOT NULL CHECK (btrim(description) <> ''),
    requested_resolution  TEXT NOT NULL DEFAULT 'review'
                          CHECK (requested_resolution IN ('review', 'full_refund', 'partial_refund')),
    requested_amount      money_amount,
    respondent_statement  TEXT CHECK (btrim(respondent_statement) <> ''),
    responded_at          TIMESTAMPTZ,
    status                TEXT NOT NULL DEFAULT 'open' CHECK (status IN (
                              'open', 'awaiting_response', 'under_review', 'resolved', 'rejected')),
    assigned_to           BIGINT REFERENCES users(id),
    priority              TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high')),
    response_due_at       TIMESTAMPTZ,
    resolution            TEXT CHECK (resolution IN (
                              'release_to_driver', 'refund_customer', 'split', 'no_financial_action')),
    driver_amount         money_amount,
    customer_amount       money_amount,
    refund_borne_by       TEXT CHECK (refund_borne_by IN ('driver', 'platform')),
    admin_notes           TEXT,
    resolved_by           BIGINT REFERENCES users(id),
    resolved_at           TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_dispute_trip_shipment FOREIGN KEY (trip_id, shipment_id) REFERENCES trips (id, shipment_id),
    CONSTRAINT ck_dispute_requested_amount CHECK (
        (requested_resolution = 'partial_refund') = (requested_amount IS NOT NULL)
    ),
    CONSTRAINT ck_dispute_response_pair CHECK ((respondent_statement IS NULL) = (responded_at IS NULL)),
    CONSTRAINT ck_dispute_resolved CHECK (
        (status = 'resolved') = (resolution IS NOT NULL)
        AND (status NOT IN ('resolved', 'rejected') OR (resolved_by IS NOT NULL AND resolved_at IS NOT NULL))
    ),
    CONSTRAINT ck_dispute_customer_refund CHECK (
        (COALESCE(resolution IN ('refund_customer', 'split'), false)
            AND COALESCE(customer_amount, 0) > 0 AND refund_borne_by IS NOT NULL)
        OR (NOT COALESCE(resolution IN ('refund_customer', 'split'), false)
            AND COALESCE(customer_amount, 0) = 0 AND refund_borne_by IS NULL)
    ),
    CONSTRAINT ck_dispute_split CHECK (resolution IS DISTINCT FROM 'split' OR driver_amount IS NOT NULL),
    CONSTRAINT uq_disputes_id_shipment UNIQUE (id, shipment_id)
);
CREATE UNIQUE INDEX uq_dispute_open_per_trip ON disputes (trip_id)
    WHERE status IN ('open', 'awaiting_response', 'under_review');

CREATE TABLE dispute_evidence (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dispute_id   BIGINT NOT NULL REFERENCES disputes(id),
    uploaded_by  BIGINT NOT NULL REFERENCES users(id),
    storage_key  TEXT NOT NULL,
    uploaded_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_dispute_evidence_dispute ON dispute_evidence (dispute_id);

CREATE TABLE dispute_events (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dispute_id  BIGINT NOT NULL REFERENCES disputes(id),
    event_type  TEXT NOT NULL CHECK (event_type IN (
                    'opened', 'status_changed', 'evidence_added', 'response_added',
                    'evidence_requested', 'note_to_parties', 'resolved')),
    from_status TEXT,
    to_status   TEXT,
    actor_id    BIGINT REFERENCES users(id),
    note        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_dispute_events_dispute ON dispute_events (dispute_id, created_at);

CREATE TABLE refunds (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id   BIGINT NOT NULL,
    shipment_id  BIGINT NOT NULL,
    reason_type  TEXT NOT NULL CHECK (reason_type IN ('cancellation', 'dispute')),
    dispute_id   BIGINT,
    amount       money_amount NOT NULL CHECK (amount > 0),
    note         TEXT,
    created_by   BIGINT REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_refund_payment_shipment FOREIGN KEY (payment_id, shipment_id) REFERENCES payments (id, shipment_id),
    CONSTRAINT fk_refund_dispute_shipment FOREIGN KEY (dispute_id, shipment_id) REFERENCES disputes (id, shipment_id),
    CONSTRAINT ck_refund_dispute CHECK ((reason_type = 'dispute') = (dispute_id IS NOT NULL))
);
CREATE INDEX ix_refunds_payment ON refunds (payment_id);
CREATE INDEX ix_refunds_dispute ON refunds (dispute_id) WHERE dispute_id IS NOT NULL;

CREATE TABLE wallet_transactions (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    driver_id          BIGINT NOT NULL REFERENCES driver_profiles(user_id),
    entry_type         TEXT NOT NULL CHECK (entry_type IN (
                           'trip_earning', 'commission_charge', 'coupon_compensation', 'cancellation_compensation',
                           'debt_settlement', 'payout', 'refund_charge', 'collected_cash_charge', 'manual_adjustment')),
    amount             NUMERIC(12,2) NOT NULL CHECK (amount <> 0),
    trip_id            BIGINT,
    settlement_id      BIGINT,
    payout_request_id  BIGINT,
    refund_id          BIGINT REFERENCES refunds(id),
    created_by         BIGINT REFERENCES users(id),
    note               TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_wallet_trip_of_driver FOREIGN KEY (trip_id, driver_id) REFERENCES trips (id, driver_id),
    CONSTRAINT fk_wallet_settlement_of_driver
        FOREIGN KEY (settlement_id, driver_id) REFERENCES driver_settlements (id, driver_id),
    CONSTRAINT fk_wallet_payout_of_driver
        FOREIGN KEY (payout_request_id, driver_id) REFERENCES payout_requests (id, driver_id),
    CONSTRAINT ck_wallet_entry_rules CHECK (
           (entry_type = 'trip_earning'              AND amount > 0 AND trip_id IS NOT NULL)
        OR (entry_type = 'commission_charge'         AND amount < 0 AND trip_id IS NOT NULL)
        OR (entry_type = 'coupon_compensation'       AND amount > 0 AND trip_id IS NOT NULL)
        OR (entry_type = 'cancellation_compensation' AND amount > 0 AND trip_id IS NOT NULL)
        OR (entry_type = 'debt_settlement'           AND amount > 0 AND settlement_id IS NOT NULL)
        OR (entry_type = 'payout'                    AND amount < 0 AND payout_request_id IS NOT NULL)
        OR (entry_type = 'refund_charge'             AND amount < 0 AND refund_id IS NOT NULL AND trip_id IS NOT NULL)
        OR (entry_type = 'collected_cash_charge'     AND amount < 0 AND refund_id IS NOT NULL AND trip_id IS NOT NULL)
        OR (entry_type = 'manual_adjustment'         AND created_by IS NOT NULL AND note IS NOT NULL)
    )
);
CREATE INDEX ix_wallet_transactions_driver ON wallet_transactions (driver_id, created_at DESC);
CREATE UNIQUE INDEX uq_wallet_trip_entry ON wallet_transactions (trip_id, entry_type)
    WHERE entry_type IN ('trip_earning', 'commission_charge', 'coupon_compensation', 'cancellation_compensation');
CREATE UNIQUE INDEX uq_wallet_refund_entry ON wallet_transactions (refund_id) WHERE refund_id IS NOT NULL;
CREATE UNIQUE INDEX uq_wallet_settlement_entry ON wallet_transactions (settlement_id) WHERE settlement_id IS NOT NULL;
CREATE UNIQUE INDEX uq_wallet_payout_entry ON wallet_transactions (payout_request_id) WHERE payout_request_id IS NOT NULL;

CREATE VIEW driver_wallet_balances AS
SELECT
    dp.user_id AS driver_id,
    COALESCE(SUM(wt.amount), 0)                              AS balance,
    COALESCE(dp.debt_limit_override, ps.default_debt_limit)  AS debt_limit,
    COALESCE(SUM(wt.amount), 0)
        < -COALESCE(dp.debt_limit_override, ps.default_debt_limit) AS is_blocked_by_debt
FROM driver_profiles dp
CROSS JOIN platform_settings ps
LEFT JOIN wallet_transactions wt ON wt.driver_id = dp.user_id
GROUP BY dp.user_id, dp.debt_limit_override, ps.default_debt_limit;

CREATE TABLE customer_topups (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id         BIGINT NOT NULL REFERENCES users(id),
    amount              money_amount NOT NULL CHECK (amount > 0),
    proof_storage_key   TEXT NOT NULL,
    transfer_reference  TEXT,
    status              TEXT NOT NULL DEFAULT 'awaiting_verification'
                        CHECK (status IN ('awaiting_verification', 'verified', 'rejected')),
    verified_by         BIGINT REFERENCES users(id),
    verified_at         TIMESTAMPTZ,
    rejection_reason    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_topup_reviewed CHECK (
        status = 'awaiting_verification' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)
    ),
    CONSTRAINT ck_topup_rejected CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL),
    CONSTRAINT ck_topup_verified_reference CHECK (status <> 'verified' OR btrim(COALESCE(transfer_reference, '')) <> ''),
    CONSTRAINT uq_topups_id_customer UNIQUE (id, customer_id)
);
CREATE INDEX ix_customer_topups_awaiting ON customer_topups (created_at) WHERE status = 'awaiting_verification';
CREATE UNIQUE INDEX uq_topup_verified_reference ON customer_topups (lower(btrim(transfer_reference))) WHERE status = 'verified';

CREATE TABLE customer_withdrawals (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id         BIGINT NOT NULL REFERENCES users(id),
    payout_account_id   BIGINT NOT NULL,
    amount              money_amount NOT NULL CHECK (amount > 0),
    status              TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'paid', 'rejected')),
    processed_by        BIGINT REFERENCES users(id),
    processed_at        TIMESTAMPTZ,
    transfer_reference  TEXT,
    rejection_reason    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_withdrawal_account_of_customer
        FOREIGN KEY (payout_account_id, customer_id) REFERENCES payout_accounts (id, user_id),
    CONSTRAINT ck_withdrawal_processed CHECK (status = 'requested' OR (processed_by IS NOT NULL AND processed_at IS NOT NULL)),
    CONSTRAINT ck_withdrawal_paid CHECK (status <> 'paid' OR transfer_reference IS NOT NULL),
    CONSTRAINT ck_withdrawal_rejected CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL),
    CONSTRAINT uq_withdrawals_id_customer UNIQUE (id, customer_id)
);
CREATE UNIQUE INDEX uq_withdrawal_open_per_customer ON customer_withdrawals (customer_id) WHERE status = 'requested';

CREATE TABLE customer_wallet_transactions (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id    BIGINT NOT NULL REFERENCES users(id),
    entry_type     TEXT NOT NULL CHECK (entry_type IN (
                       'top_up', 'trip_payment', 'recipient_refused_charge', 'refund',
                       'cancellation_fee', 'withdrawal', 'manual_adjustment')),
    amount         NUMERIC(12,2) NOT NULL CHECK (amount <> 0),
    topup_id       BIGINT,
    payment_id     BIGINT REFERENCES payments(id),
    refund_id      BIGINT REFERENCES refunds(id),
    trip_id        BIGINT REFERENCES trips(id),
    withdrawal_id  BIGINT,
    created_by     BIGINT REFERENCES users(id),
    note           TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_cwallet_topup_of_customer
        FOREIGN KEY (topup_id, customer_id) REFERENCES customer_topups (id, customer_id),
    CONSTRAINT fk_cwallet_withdrawal_of_customer
        FOREIGN KEY (withdrawal_id, customer_id) REFERENCES customer_withdrawals (id, customer_id),
    CONSTRAINT ck_cwallet_entry_rules CHECK (
           (entry_type = 'top_up'                   AND amount > 0 AND topup_id IS NOT NULL)
        OR (entry_type = 'trip_payment'             AND amount < 0 AND payment_id IS NOT NULL)
        OR (entry_type = 'recipient_refused_charge' AND amount < 0 AND payment_id IS NOT NULL)
        OR (entry_type = 'refund'                   AND amount > 0 AND refund_id IS NOT NULL)
        OR (entry_type = 'cancellation_fee'         AND amount < 0 AND trip_id IS NOT NULL)
        OR (entry_type = 'withdrawal'               AND amount < 0 AND withdrawal_id IS NOT NULL)
        OR (entry_type = 'manual_adjustment'        AND created_by IS NOT NULL AND note IS NOT NULL)
    )
);
CREATE INDEX ix_cwallet_customer ON customer_wallet_transactions (customer_id, created_at DESC);
CREATE UNIQUE INDEX uq_cwallet_topup_entry ON customer_wallet_transactions (topup_id) WHERE topup_id IS NOT NULL;
CREATE UNIQUE INDEX uq_cwallet_payment_entry ON customer_wallet_transactions (payment_id) WHERE payment_id IS NOT NULL;
CREATE UNIQUE INDEX uq_cwallet_refund_entry ON customer_wallet_transactions (refund_id) WHERE refund_id IS NOT NULL;
CREATE UNIQUE INDEX uq_cwallet_fee_entry ON customer_wallet_transactions (trip_id) WHERE entry_type = 'cancellation_fee';
CREATE UNIQUE INDEX uq_cwallet_withdrawal_entry ON customer_wallet_transactions (withdrawal_id) WHERE withdrawal_id IS NOT NULL;

CREATE VIEW customer_wallet_balances AS
SELECT u.id AS customer_id, COALESCE(SUM(t.amount), 0) AS balance
FROM users u
LEFT JOIN customer_wallet_transactions t ON t.customer_id = u.id
GROUP BY u.id;

CREATE TABLE conversations (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id     BIGINT UNIQUE REFERENCES trips(id),
    group_id    BIGINT REFERENCES shipment_groups(id),
    driver_id   BIGINT REFERENCES driver_profiles(user_id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at   TIMESTAMPTZ,
    CONSTRAINT ck_conversation_target CHECK (
        (trip_id IS NOT NULL AND group_id IS NULL AND driver_id IS NULL)
        OR (trip_id IS NULL AND group_id IS NOT NULL AND driver_id IS NOT NULL)
    ),
    CONSTRAINT uq_conversation_group_driver UNIQUE (group_id, driver_id)
);

CREATE TABLE messages (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversation_id         BIGINT NOT NULL REFERENCES conversations(id),
    sender_id               BIGINT NOT NULL REFERENCES users(id),
    message_type            TEXT NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'location')),
    body                    TEXT,
    attachment_storage_key  TEXT,
    location                GEOGRAPHY(POINT, 4326),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at                 TIMESTAMPTZ,
    CONSTRAINT ck_message_content CHECK (
        (message_type = 'text' AND btrim(COALESCE(body, '')) <> '' AND attachment_storage_key IS NULL AND location IS NULL)
        OR (message_type = 'image' AND attachment_storage_key IS NOT NULL AND location IS NULL)
        OR (message_type = 'location' AND location IS NOT NULL AND attachment_storage_key IS NULL)
    )
);
CREATE INDEX ix_messages_conversation ON messages (conversation_id, created_at);

CREATE TABLE reviews (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id         BIGINT NOT NULL REFERENCES trips(id),
    reviewer_id     BIGINT NOT NULL REFERENCES users(id),
    reviewee_id     BIGINT NOT NULL REFERENCES users(id),
    rating          SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    vehicle_rating  SMALLINT CHECK (vehicle_rating BETWEEN 1 AND 5),
    service_rating  SMALLINT CHECK (service_rating BETWEEN 1 AND 5),
    comment         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_review_not_self CHECK (reviewer_id <> reviewee_id),
    CONSTRAINT uq_review_per_author UNIQUE (trip_id, reviewer_id)
);
CREATE INDEX ix_reviews_reviewee ON reviews (reviewee_id);

CREATE TABLE review_tag_selections (
    review_id   BIGINT NOT NULL REFERENCES reviews(id),
    tag_id      BIGINT NOT NULL REFERENCES review_tags(id),
    PRIMARY KEY (review_id, tag_id)
);

CREATE VIEW user_ratings AS
SELECT reviewee_id AS user_id, ROUND(AVG(rating), 2) AS average_rating, COUNT(*) AS reviews_count
FROM reviews
GROUP BY reviewee_id;

CREATE TABLE support_tickets (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users(id),
    user_role    TEXT NOT NULL CHECK (user_role IN ('customer', 'driver')),
    opened_by    BIGINT REFERENCES users(id),
    trip_id      BIGINT REFERENCES trips(id),
    shipment_id  BIGINT REFERENCES shipments(id),
    dispute_id   BIGINT REFERENCES disputes(id),
    category     TEXT NOT NULL CHECK (category IN ('account', 'trip', 'payment', 'safety', 'other')),
    priority     TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high')),
    status       TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'waiting_user', 'resolved', 'closed')),
    subject      TEXT NOT NULL CHECK (btrim(subject) <> ''),
    assigned_to  BIGINT REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at  TIMESTAMPTZ,
    resolution_note  TEXT,
    cargo_outcome    TEXT CHECK (cargo_outcome IN ('returned_to_sender', 'handed_to_recipient', 'other_documented')),
    resolved_by      BIGINT REFERENCES users(id),
    CONSTRAINT ck_ticket_safety_priority CHECK (category <> 'safety' OR priority = 'high'),
    CONSTRAINT ck_ticket_resolved CHECK (status NOT IN ('resolved', 'closed') OR resolved_at IS NOT NULL),
    CONSTRAINT ck_ticket_cargo_resolution CHECK (
        cargo_outcome IS NULL OR (trip_id IS NOT NULL AND status IN ('resolved', 'closed')
                                  AND btrim(COALESCE(resolution_note, '')) <> '' AND resolved_by IS NOT NULL))
);
ALTER TABLE trips
    ADD CONSTRAINT fk_trip_cancellation_ticket FOREIGN KEY (cancellation_ticket_id) REFERENCES support_tickets (id);
CREATE INDEX ix_support_tickets_user ON support_tickets (user_id, created_at DESC);
CREATE INDEX ix_support_tickets_open ON support_tickets (priority, created_at) WHERE status IN ('open', 'waiting_user');

CREATE TABLE support_messages (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id               BIGINT NOT NULL REFERENCES support_tickets(id),
    sender_id               BIGINT NOT NULL REFERENCES users(id),
    body                    TEXT NOT NULL CHECK (btrim(body) <> ''),
    attachment_storage_key  TEXT,
    is_internal             BOOLEAN NOT NULL DEFAULT false,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at                 TIMESTAMPTZ
);
CREATE INDEX ix_support_messages_ticket ON support_messages (ticket_id, created_at);

CREATE TABLE admin_audit_log (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id    BIGINT REFERENCES users(id),
    actor_role  TEXT NOT NULL,
    action      TEXT NOT NULL CHECK (action IN ('insert', 'update', 'delete')),
    table_name  TEXT NOT NULL,
    row_id      TEXT NOT NULL,
    before      JSONB,
    after       JSONB,
    reason      TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_admin_audit_log_row ON admin_audit_log (table_name, row_id, created_at);
CREATE INDEX ix_admin_audit_log_actor ON admin_audit_log (actor_id, created_at);

CREATE TABLE shipment_imports (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uploaded_by        BIGINT NOT NULL REFERENCES users(id),
    storage_key        TEXT NOT NULL,
    original_filename  TEXT,
    status             TEXT NOT NULL DEFAULT 'uploaded' CHECK (status IN (
                           'uploaded', 'validating', 'awaiting_confirmation', 'processing', 'completed', 'failed')),
    total_rows         INTEGER CHECK (total_rows >= 0),
    valid_rows         INTEGER CHECK (valid_rows >= 0),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at       TIMESTAMPTZ,
    completed_at       TIMESTAMPTZ,
    failure_reason     TEXT,
    CONSTRAINT ck_import_counts CHECK (valid_rows IS NULL OR total_rows IS NULL OR valid_rows <= total_rows)
);
CREATE INDEX ix_shipment_imports_uploader ON shipment_imports (uploaded_by, created_at DESC);

CREATE TABLE shipment_import_rows (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    import_id          BIGINT NOT NULL REFERENCES shipment_imports(id),
    row_number         INTEGER NOT NULL CHECK (row_number > 0),
    raw_data           JSONB NOT NULL,
    validated_data     JSONB,
    status             TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'valid', 'invalid', 'imported', 'creation_failed')),
    validation_errors  JSONB,
    shipment_id        BIGINT UNIQUE REFERENCES shipments(id),
    CONSTRAINT uq_import_row_number UNIQUE (import_id, row_number),
    CONSTRAINT ck_import_row_invalid CHECK (status <> 'invalid' OR validation_errors IS NOT NULL),
    CONSTRAINT ck_import_row_imported CHECK (status <> 'imported' OR shipment_id IS NOT NULL)
);

CREATE FUNCTION app_actor_id() RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.actor_id', true), '')::BIGINT
$$;
CREATE FUNCTION app_actor_role() RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT COALESCE(NULLIF(current_setting('app.actor_role', true), ''), 'system')
$$;
CREATE FUNCTION app_change_reason() RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.change_reason', true), '')
$$;

CREATE FUNCTION has_role(p_user BIGINT, p_role TEXT) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
                   WHERE ur.user_id = p_user AND r.code = p_role)
$$;

CREATE FUNCTION license_rank(p license_category) RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p WHEN 'private' THEN 1 WHEN 'professional_3' THEN 2
                  WHEN 'professional_2' THEN 3 WHEN 'professional_1' THEN 4 END
$$;

CREATE FUNCTION driver_balance(p_driver BIGINT) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(amount), 0) FROM wallet_transactions WHERE driver_id = p_driver
$$;
CREATE FUNCTION driver_debt_limit(p_driver BIGINT) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(dp.debt_limit_override, ps.default_debt_limit)
    FROM driver_profiles dp CROSS JOIN platform_settings ps WHERE dp.user_id = p_driver
$$;
CREATE FUNCTION customer_balance(p_customer BIGINT) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(amount), 0) FROM customer_wallet_transactions WHERE customer_id = p_customer
$$;
CREATE FUNCTION customer_available_balance(p_customer BIGINT) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT customer_balance(p_customer)
         - COALESCE((SELECT SUM(amount) FROM customer_withdrawals WHERE customer_id = p_customer AND status = 'requested'), 0)
$$;

CREATE FUNCTION shipment_is_locked(p_shipment BIGINT) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM shipments WHERE id = p_shipment AND status <> 'draft')
        OR EXISTS (SELECT 1 FROM price_quotes WHERE shipment_id = p_shipment AND status = 'accepted')
$$;

CREATE FUNCTION zone_for(p_location GEOGRAPHY(POINT, 4326)) RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT id FROM service_zones
    WHERE is_active AND ST_Covers(boundary, p_location)
    ORDER BY ST_Area(boundary), id
    LIMIT 1
$$;

CREATE FUNCTION latest_policy_version(p_type TEXT) RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT id FROM policy_versions
    WHERE doc_type = p_type AND published_at IS NOT NULL AND published_at <= now()
    ORDER BY version_number DESC
    LIMIT 1
$$;
CREATE FUNCTION accepted_latest_policies(p_user BIGINT) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT bool_and(v.id IS NULL OR EXISTS (
               SELECT 1 FROM policy_acceptances a WHERE a.user_id = p_user AND a.policy_version_id = v.id))
    FROM (SELECT latest_policy_version(t) AS id FROM unnest(ARRAY['terms', 'privacy']) AS t) v
$$;

CREATE FUNCTION coupon_discount(p_coupon BIGINT, p_amount NUMERIC) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT LEAST(
               CASE c.discount_type
                   WHEN 'percent' THEN LEAST(round(p_amount * c.discount_value / 100, 2),
                                             COALESCE(c.max_discount, p_amount))
                   ELSE c.discount_value
               END,
               p_amount - 0.01)
    FROM coupons c WHERE c.id = p_coupon
$$;

CREATE FUNCTION driver_current_license(p_driver BIGINT) RETURNS driver_documents LANGUAGE sql STABLE AS $$
    SELECT * FROM driver_documents
    WHERE driver_id = p_driver AND document_type = 'driving_license_front'
      AND review_status = 'approved' AND superseded_at IS NULL
$$;

CREATE FUNCTION forbid_settings_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'platform_settings must keep its single row: update it instead of deleting';
END$$;
CREATE TRIGGER trg_platform_settings_no_delete BEFORE DELETE ON platform_settings
    FOR EACH ROW EXECUTE FUNCTION forbid_settings_delete();
CREATE TRIGGER trg_platform_settings_no_truncate BEFORE TRUNCATE ON platform_settings
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_settings_delete();

CREATE FUNCTION policy_versions_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM policy_versions WHERE doc_type = NEW.doc_type
                   AND version_number >= NEW.version_number) THEN
            RAISE EXCEPTION 'policy % version % must be newer than existing versions', NEW.doc_type, NEW.version_number;
        END IF;
        RETURN NEW;
    END IF;
    IF OLD.published_at IS NOT NULL AND
       (NEW.doc_type, NEW.version_number, NEW.content_ar, NEW.content_en, NEW.published_at)
       IS DISTINCT FROM (OLD.doc_type, OLD.version_number, OLD.content_ar, OLD.content_en, OLD.published_at) THEN
        RAISE EXCEPTION 'policy version % is published: create a new version instead of editing it', OLD.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_policy_versions_guard BEFORE INSERT OR UPDATE ON policy_versions
    FOR EACH ROW EXECUTE FUNCTION policy_versions_guard();

CREATE FUNCTION policy_acceptances_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM policy_versions WHERE id = NEW.policy_version_id
                   AND published_at IS NOT NULL AND published_at <= now()) THEN
        RAISE EXCEPTION 'policy version % is not published', NEW.policy_version_id;
    END IF;
    NEW.accepted_at := now();
    RETURN NEW;
END$$;
CREATE TRIGGER trg_policy_acceptances_guard BEFORE INSERT ON policy_acceptances
    FOR EACH ROW EXECUTE FUNCTION policy_acceptances_guard();

CREATE FUNCTION user_roles_policies_check() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT code FROM roles WHERE id = NEW.role_id) IN ('customer', 'driver')
       AND NOT accepted_latest_policies(NEW.user_id) THEN
        RAISE EXCEPTION 'user % must accept the latest terms and privacy policy', NEW.user_id;
    END IF;
    RETURN NULL;
END$$;
CREATE CONSTRAINT TRIGGER trg_user_roles_policies AFTER INSERT ON user_roles
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION user_roles_policies_check();

CREATE FUNCTION users_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.account_status = 'deleted' THEN
        IF NEW IS DISTINCT FROM OLD THEN
            RAISE EXCEPTION 'user % is deleted and cannot change', OLD.id;
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.account_status = 'deleted' THEN
        IF EXISTS (SELECT 1 FROM trips WHERE driver_id = OLD.id AND status NOT IN ('delivered', 'cancelled'))
           OR EXISTS (SELECT 1 FROM shipments WHERE customer_id = OLD.id
                      AND status IN ('searching_driver', 'driver_assigned', 'in_progress')) THEN
            RAISE EXCEPTION 'user % has an active trip or shipment: finish or cancel it first', OLD.id;
        END IF;
        IF customer_balance(OLD.id) <> 0 THEN
            RAISE EXCEPTION 'user % customer wallet balance is % (must be exactly 0)', OLD.id, customer_balance(OLD.id);
        END IF;
        IF EXISTS (SELECT 1 FROM driver_profiles WHERE user_id = OLD.id) AND driver_balance(OLD.id) <> 0 THEN
            RAISE EXCEPTION 'user % driver wallet balance is % (must be exactly 0)', OLD.id, driver_balance(OLD.id);
        END IF;
        IF EXISTS (SELECT 1 FROM disputes d JOIN trips t ON t.id = d.trip_id JOIN shipments s ON s.id = d.shipment_id
                   WHERE d.status IN ('open', 'awaiting_response', 'under_review')
                     AND (d.opened_by = OLD.id OR t.driver_id = OLD.id OR s.customer_id = OLD.id)) THEN
            RAISE EXCEPTION 'user % has an open dispute', OLD.id;
        END IF;
        NEW.full_name          := 'Deleted user';
        NEW.phone              := NULL;
        NEW.email              := NULL;
        NEW.email_verified_at  := NULL;
        NEW.password_hash      := NULL;
        NEW.avatar_storage_key := NULL;
        NEW.default_payment_method := NULL;
        NEW.deleted_at         := now();
        RETURN NEW;
    END IF;

    IF NEW.email IS DISTINCT FROM OLD.email AND NEW.email_verified_at IS NOT DISTINCT FROM OLD.email_verified_at THEN
        NEW.email_verified_at := NULL;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_users_guard BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION users_guard();

CREATE FUNCTION cancel_unstarted_trips(p_driver BIGINT, p_vehicle BIGINT, p_reason TEXT)
RETURNS void LANGUAGE sql AS $$
    UPDATE trips t SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = p_reason
    WHERE t.status = 'assigned'
      AND (t.driver_id = p_driver OR t.vehicle_id = p_vehicle)
      AND (t.group_id IS NULL OR NOT EXISTS (
               SELECT 1 FROM trips g WHERE g.group_id = t.group_id
               AND g.status NOT IN ('assigned', 'delivered', 'cancelled')));
$$;

CREATE FUNCTION users_after_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.account_status <> 'active' AND OLD.account_status = 'active' THEN
        UPDATE driver_profiles SET is_online = false WHERE user_id = NEW.id AND is_online;
        PERFORM cancel_unstarted_trips(NEW.id, NULL, 'driver account ' || NEW.account_status);
    END IF;
    IF NEW.account_status = 'deleted' AND OLD.account_status <> 'deleted' THEN
        UPDATE auth_sessions SET revoked_at = now() WHERE user_id = NEW.id AND revoked_at IS NULL;
        DELETE FROM user_devices WHERE user_id = NEW.id;
        DELETE FROM saved_places WHERE user_id = NEW.id;
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_users_after_change AFTER UPDATE OF account_status ON users
    FOR EACH ROW EXECUTE FUNCTION users_after_change();

CREATE FUNCTION driver_submission_missing(p_driver BIGINT) RETURNS TEXT[] LANGUAGE plpgsql STABLE AS $$
DECLARE
    dp       driver_profiles%ROWTYPE;
    missing  TEXT[] := '{}';
    t        TEXT;
BEGIN
    SELECT * INTO dp FROM driver_profiles WHERE user_id = p_driver;
    FOREACH t IN ARRAY ARRAY['profile_photo', 'national_id_front', 'national_id_back',
                             'driving_license_front', 'driving_license_back'] LOOP
        IF NOT EXISTS (SELECT 1 FROM driver_documents WHERE driver_id = p_driver AND document_type = t
                       AND superseded_at IS NULL AND review_status IN ('pending', 'approved')) THEN
            missing := missing || t;
        END IF;
    END LOOP;
    IF NOT EXISTS (
        SELECT 1 FROM vehicles v WHERE v.driver_id = p_driver AND (
            SELECT count(DISTINCT vd.document_type) FROM vehicle_documents vd
            WHERE vd.vehicle_id = v.id AND vd.superseded_at IS NULL AND vd.review_status IN ('pending', 'approved')
        ) = 6) THEN
        missing := missing || 'vehicle_documents'::TEXT;
    END IF;
    IF dp.date_of_birth > current_date - make_interval(years => (SELECT min_driver_age FROM platform_settings)) THEN
        missing := missing || 'min_age'::TEXT;
    END IF;
    IF NOT (SELECT is_active FROM cities WHERE id = dp.city_id) THEN
        missing := missing || 'active_city'::TEXT;
    END IF;
    IF dp.national_id_hash IS NULL THEN
        missing := missing || 'national_id'::TEXT;
    END IF;
    IF NOT accepted_latest_policies(p_driver) THEN
        missing := missing || 'accepted_terms'::TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM payout_accounts WHERE user_id = p_driver
                   AND superseded_at IS NULL AND review_status <> 'rejected') THEN
        missing := missing || 'payout_account'::TEXT;
    END IF;
    RETURN missing;
END$$;

CREATE FUNCTION driver_approval_missing(p_driver BIGINT) RETURNS TEXT[] LANGUAGE plpgsql STABLE AS $$
DECLARE
    missing  TEXT[] := '{}';
    t        TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['profile_photo', 'national_id_front', 'national_id_back',
                             'driving_license_front', 'driving_license_back'] LOOP
        IF NOT EXISTS (SELECT 1 FROM driver_documents WHERE driver_id = p_driver AND document_type = t
                       AND superseded_at IS NULL AND review_status = 'approved') THEN
            missing := missing || t;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM driver_documents WHERE driver_id = p_driver
                   AND document_type = 'driving_license_front' AND superseded_at IS NULL
                   AND review_status = 'approved' AND expires_on > current_date) THEN
        missing := missing || 'driving_license_valid'::TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM driver_documents WHERE driver_id = p_driver
                   AND document_type = 'national_id_front' AND superseded_at IS NULL
                   AND review_status = 'approved' AND expires_on > current_date) THEN
        missing := missing || 'national_id_valid'::TEXT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM vehicles v WHERE v.driver_id = p_driver
          AND (SELECT count(DISTINCT vd.document_type) FROM vehicle_documents vd
               WHERE vd.vehicle_id = v.id AND vd.superseded_at IS NULL AND vd.review_status = 'approved') = 6
          AND EXISTS (SELECT 1 FROM vehicle_documents vd WHERE vd.vehicle_id = v.id
                      AND vd.document_type = 'vehicle_license_front' AND vd.superseded_at IS NULL
                      AND vd.review_status = 'approved' AND vd.expires_on > current_date)) THEN
        missing := missing || 'vehicle_documents_approved'::TEXT;
    END IF;
    RETURN missing;
END$$;

CREATE FUNCTION license_fits_vehicle(p_driver BIGINT, p_vehicle BIGINT) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT COALESCE(license_rank((driver_current_license(p_driver)).license_category)
                    >= (SELECT license_rank(vt.min_license_category)
                        FROM vehicles v JOIN vehicle_types vt ON vt.id = v.vehicle_type_id WHERE v.id = p_vehicle),
                    false)
$$;

CREATE FUNCTION driver_profiles_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    missing TEXT[];
BEGIN
    IF (TG_OP = 'INSERT' OR NEW.city_id IS DISTINCT FROM OLD.city_id)
       AND NOT (SELECT is_active FROM cities WHERE id = NEW.city_id) THEN
        RAISE EXCEPTION 'city % is not active', NEW.city_id;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.verification_status <> 'draft' OR NEW.submitted_at IS NOT NULL THEN
            RAISE EXCEPTION 'a new driver profile must start as draft';
        END IF;
    ELSIF NEW.verification_status IS DISTINCT FROM OLD.verification_status THEN
        IF NOT (OLD.verification_status || '>' || NEW.verification_status = ANY (ARRAY[
                'draft>pending', 'pending>approved', 'pending>rejected'])) THEN
            RAISE EXCEPTION 'driver % cannot go from % to %', OLD.user_id, OLD.verification_status, NEW.verification_status;
        END IF;
        IF NEW.verification_status = 'pending' THEN
            missing := driver_submission_missing(OLD.user_id);
            IF cardinality(missing) > 0 THEN
                RAISE EXCEPTION 'driver % cannot submit yet, missing: %', OLD.user_id, array_to_string(missing, ', ');
            END IF;
            NEW.submitted_at := now();
        ELSE
            IF NEW.verification_status = 'approved' THEN
                missing := driver_approval_missing(OLD.user_id);
                IF cardinality(missing) > 0 THEN
                    RAISE EXCEPTION 'driver % cannot be approved yet, missing: %', OLD.user_id, array_to_string(missing, ', ');
                END IF;
            END IF;
            NEW.reviewed_at := now();
            NEW.reviewed_by := COALESCE(NEW.reviewed_by, app_actor_id());
        END IF;
    ELSE
        NEW.submitted_at := OLD.submitted_at;
    END IF;

    IF NEW.is_online AND (TG_OP = 'INSERT' OR NOT OLD.is_online)
       AND (SELECT account_status FROM users WHERE id = NEW.user_id) <> 'active' THEN
        RAISE EXCEPTION 'driver % account is not active: cannot go online', NEW.user_id;
    END IF;
    IF NEW.is_online AND (TG_OP = 'INSERT' OR NOT OLD.is_online) AND NOT accepted_latest_policies(NEW.user_id) THEN
        RAISE EXCEPTION 'driver % must accept the latest terms and privacy policy before going online', NEW.user_id;
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.active_vehicle_id IS DISTINCT FROM OLD.active_vehicle_id AND EXISTS (
           SELECT 1 FROM trips WHERE driver_id = OLD.user_id AND status IN (
               'heading_to_pickup', 'arrived_at_pickup', 'loaded', 'heading_to_dropoff', 'arrived_at_dropoff')) THEN
        RAISE EXCEPTION 'driver % is in the middle of a trip: cannot switch vehicle', OLD.user_id;
    END IF;

    IF NEW.active_vehicle_id IS NOT NULL AND NEW.verification_status = 'approved'
       AND (TG_OP = 'INSERT' OR NEW.active_vehicle_id IS DISTINCT FROM OLD.active_vehicle_id
            OR (NEW.is_online AND NOT OLD.is_online))
       AND NOT license_fits_vehicle(NEW.user_id, NEW.active_vehicle_id) THEN
        RAISE EXCEPTION 'driver % license category is too low for vehicle %', NEW.user_id, NEW.active_vehicle_id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_driver_profiles_guard BEFORE INSERT OR UPDATE ON driver_profiles
    FOR EACH ROW EXECUTE FUNCTION driver_profiles_guard();

CREATE FUNCTION driver_online_sessions_track() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.is_online AND (TG_OP = 'INSERT' OR NOT OLD.is_online) THEN
        INSERT INTO driver_online_sessions (driver_id, vehicle_id) VALUES (NEW.user_id, NEW.active_vehicle_id);
    ELSIF TG_OP = 'UPDATE' AND OLD.is_online AND NOT NEW.is_online THEN
        UPDATE driver_online_sessions SET ended_at = now() WHERE driver_id = NEW.user_id AND ended_at IS NULL;
    ELSIF TG_OP = 'UPDATE' AND OLD.is_online AND NEW.is_online
          AND NEW.active_vehicle_id IS DISTINCT FROM OLD.active_vehicle_id THEN
        UPDATE driver_online_sessions SET ended_at = now() WHERE driver_id = NEW.user_id AND ended_at IS NULL;
        INSERT INTO driver_online_sessions (driver_id, vehicle_id) VALUES (NEW.user_id, NEW.active_vehicle_id);
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_driver_online_sessions AFTER INSERT OR UPDATE OF is_online, active_vehicle_id ON driver_profiles
    FOR EACH ROW EXECUTE FUNCTION driver_online_sessions_track();

CREATE FUNCTION driver_online_sessions_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'online sessions are written automatically from driver_profiles.is_online';
    END IF;
    IF TG_OP = 'UPDATE' AND (OLD.ended_at IS NOT NULL OR
       (NEW.driver_id, NEW.vehicle_id, NEW.started_at) IS DISTINCT FROM (OLD.driver_id, OLD.vehicle_id, OLD.started_at)) THEN
        RAISE EXCEPTION 'online session % can only be closed once', OLD.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_driver_online_sessions_guard BEFORE INSERT OR UPDATE ON driver_online_sessions
    FOR EACH ROW EXECUTE FUNCTION driver_online_sessions_guard();

CREATE FUNCTION vehicles_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.max_payload_kg IS NULL THEN
        SELECT max_payload_kg INTO NEW.max_payload_kg FROM vehicle_types WHERE id = NEW.vehicle_type_id;
    END IF;
    IF NEW.manufacture_year NOT BETWEEN 1980 AND EXTRACT(YEAR FROM now())::INT + 1 THEN
        RAISE EXCEPTION 'manufacture year % must be between 1980 and next year', NEW.manufacture_year;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_vehicles_guard BEFORE INSERT OR UPDATE ON vehicles
    FOR EACH ROW EXECUTE FUNCTION vehicles_guard();

CREATE FUNCTION vehicles_after_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE driver_profiles SET is_online = false WHERE active_vehicle_id = NEW.id AND is_online;
    PERFORM cancel_unstarted_trips(NULL, NEW.id, 'vehicle ' || NEW.status);
    RETURN NULL;
END$$;
CREATE TRIGGER trg_vehicles_after_change AFTER UPDATE OF status ON vehicles
    FOR EACH ROW WHEN (OLD.status = 'active' AND NEW.status <> 'active')
    EXECUTE FUNCTION vehicles_after_change();

CREATE FUNCTION documents_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    owner_col  TEXT := TG_ARGV[0];
    owner_id   BIGINT;
BEGIN
    owner_id := (to_jsonb(NEW) ->> owner_col)::BIGINT;

    IF TG_OP = 'INSERT' THEN
        IF NEW.review_status <> 'pending' OR NEW.superseded_at IS NOT NULL THEN
            RAISE EXCEPTION 'a new document must start as pending and current';
        END IF;
        EXECUTE format('UPDATE %I SET superseded_at = now() WHERE %I = $1 AND document_type = $2
                        AND superseded_at IS NULL AND review_status IN (''pending'', ''rejected'')',
                       TG_TABLE_NAME, owner_col)
            USING owner_id, NEW.document_type;
        RETURN NEW;
    END IF;

    IF (to_jsonb(NEW) ->> owner_col, NEW.document_type, NEW.storage_key, NEW.uploaded_at)
       IS DISTINCT FROM (to_jsonb(OLD) ->> owner_col, OLD.document_type, OLD.storage_key, OLD.uploaded_at) THEN
        RAISE EXCEPTION 'document % owner/type/file cannot change: upload a new one', OLD.id;
    END IF;
    IF NEW.superseded_at IS DISTINCT FROM OLD.superseded_at THEN
        IF OLD.superseded_at IS NOT NULL OR pg_trigger_depth() < 2 THEN
            RAISE EXCEPTION 'document % superseded_at is set automatically by the database', OLD.id;
        END IF;
    END IF;
    IF OLD.superseded_at IS NOT NULL OR OLD.review_status <> 'pending' THEN
        IF (to_jsonb(NEW) - 'superseded_at') IS DISTINCT FROM (to_jsonb(OLD) - 'superseded_at') THEN
            RAISE EXCEPTION 'document % is % and final', OLD.id,
                CASE WHEN OLD.superseded_at IS NOT NULL THEN 'superseded' ELSE OLD.review_status END;
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.review_status <> 'pending' THEN
        NEW.reviewed_at := now();
        NEW.reviewed_by := COALESCE(NEW.reviewed_by, app_actor_id());
        IF NEW.review_status = 'approved' AND NEW.expires_on IS NOT NULL AND NEW.expires_on <= current_date THEN
            RAISE EXCEPTION 'document % expired on %: it cannot be approved', OLD.id, NEW.expires_on;
        END IF;
        IF NEW.review_status = 'approved' THEN
            EXECUTE format('UPDATE %I SET superseded_at = now() WHERE %I = $1 AND document_type = $2
                            AND superseded_at IS NULL AND review_status = ''approved'' AND id <> $3',
                           TG_TABLE_NAME, owner_col)
                USING owner_id, NEW.document_type, NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_driver_documents_guard BEFORE INSERT OR UPDATE ON driver_documents
    FOR EACH ROW EXECUTE FUNCTION documents_guard('driver_id');
CREATE TRIGGER trg_vehicle_documents_guard BEFORE INSERT OR UPDATE ON vehicle_documents
    FOR EACH ROW EXECUTE FUNCTION documents_guard('vehicle_id');

CREATE FUNCTION payout_accounts_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.review_status <> 'pending' OR NEW.superseded_at IS NOT NULL THEN
            RAISE EXCEPTION 'a new payout account must start as pending and current';
        END IF;
        UPDATE payout_accounts SET superseded_at = now() WHERE user_id = NEW.user_id AND superseded_at IS NULL;
        RETURN NEW;
    END IF;
    IF (NEW.user_id, NEW.method, NEW.holder_name, NEW.bank_name, NEW.account_number, NEW.created_at)
       IS DISTINCT FROM (OLD.user_id, OLD.method, OLD.holder_name, OLD.bank_name, OLD.account_number, OLD.created_at) THEN
        RAISE EXCEPTION 'payout account % details cannot change: add a new account', OLD.id;
    END IF;
    IF NEW.superseded_at IS DISTINCT FROM OLD.superseded_at
       AND (OLD.superseded_at IS NOT NULL OR pg_trigger_depth() < 2) THEN
        RAISE EXCEPTION 'payout account % superseded_at is set automatically', OLD.id;
    END IF;
    IF OLD.review_status <> 'pending' OR OLD.superseded_at IS NOT NULL THEN
        IF (to_jsonb(NEW) - 'superseded_at') IS DISTINCT FROM (to_jsonb(OLD) - 'superseded_at') THEN
            RAISE EXCEPTION 'payout account % review is final', OLD.id;
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.review_status <> 'pending' THEN
        NEW.reviewed_at := now();
        NEW.reviewed_by := COALESCE(NEW.reviewed_by, app_actor_id());
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_payout_accounts_guard BEFORE INSERT OR UPDATE ON payout_accounts
    FOR EACH ROW EXECUTE FUNCTION payout_accounts_guard();

CREATE FUNCTION shipment_groups_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.customer_id, NEW.pickup_address, NEW.pickup_location::text, NEW.pickup_notes, NEW.helpers_count)
       IS DISTINCT FROM (OLD.customer_id, OLD.pickup_address, OLD.pickup_location::text, OLD.pickup_notes, OLD.helpers_count)
       AND EXISTS (SELECT 1 FROM shipments s WHERE s.group_id = OLD.id AND shipment_is_locked(s.id)) THEN
        RAISE EXCEPTION 'group % details are fixed after a price was accepted', OLD.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_shipment_groups_guard BEFORE UPDATE ON shipment_groups
    FOR EACH ROW EXECUTE FUNCTION shipment_groups_guard();

CREATE FUNCTION shipment_groups_sync() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE shipments SET pickup_address = NEW.pickup_address, pickup_location = NEW.pickup_location,
                         pickup_notes = NEW.pickup_notes, helpers_count = NEW.helpers_count
    WHERE group_id = NEW.id AND status = 'draft';
    RETURN NULL;
END$$;
CREATE TRIGGER trg_shipment_groups_sync AFTER UPDATE ON shipment_groups
    FOR EACH ROW EXECUTE FUNCTION shipment_groups_sync();

CREATE FUNCTION shipments_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    from_trip  BOOLEAN := pg_trigger_depth() > 1;
    g          shipment_groups%ROWTYPE;
    q          price_quotes%ROWTYPE;
    bal        NUMERIC;
BEGIN
    IF NEW.group_id IS NOT NULL THEN
        SELECT * INTO g FROM shipment_groups WHERE id = NEW.group_id FOR UPDATE;
        NEW.pickup_address  := g.pickup_address;
        NEW.pickup_location := g.pickup_location;
        NEW.pickup_notes    := g.pickup_notes;
        NEW.helpers_count   := g.helpers_count;
        IF (TG_OP = 'INSERT' OR NEW.group_id IS DISTINCT FROM OLD.group_id)
           AND (SELECT count(*) FROM shipments WHERE group_id = NEW.group_id AND status <> 'cancelled')
               >= (SELECT max_group_stops FROM platform_settings) THEN
            RAISE EXCEPTION 'group % already has the maximum number of drop-offs', NEW.group_id;
        END IF;
        IF (TG_OP = 'INSERT' OR NEW.group_id IS DISTINCT FROM OLD.group_id)
           AND EXISTS (SELECT 1 FROM shipments s WHERE s.group_id = NEW.group_id AND s.status <> 'cancelled'
                       AND (s.status <> 'draft' OR EXISTS (
                            SELECT 1 FROM price_quotes pq WHERE pq.shipment_id = s.id AND pq.status = 'accepted'))) THEN
            RAISE EXCEPTION 'group % already has an agreed price: no new drop-off can join it', NEW.group_id;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'draft' THEN
            RAISE EXCEPTION 'a new shipment must start as draft';
        END IF;
        NEW.search_started_at := NULL;
        NEW.details_version   := 1;
        NEW.pickup_zone_id  := zone_for(NEW.pickup_location);
        NEW.dropoff_zone_id := zone_for(NEW.dropoff_location);
        RETURN NEW;
    END IF;

    IF NEW.pickup_location::text IS DISTINCT FROM OLD.pickup_location::text THEN
        NEW.pickup_zone_id := zone_for(NEW.pickup_location);
    ELSE
        NEW.pickup_zone_id := OLD.pickup_zone_id;
    END IF;
    IF NEW.dropoff_location::text IS DISTINCT FROM OLD.dropoff_location::text THEN
        NEW.dropoff_zone_id := zone_for(NEW.dropoff_location);
    ELSE
        NEW.dropoff_zone_id := OLD.dropoff_zone_id;
    END IF;

    IF (OLD.status <> 'draft'
        OR EXISTS (SELECT 1 FROM price_quotes WHERE shipment_id = OLD.id AND status = 'accepted')) AND
       (NEW.customer_id, NEW.group_id, NEW.cargo_category_id, NEW.size_option_id, NEW.cargo_description,
        NEW.item_count, NEW.is_fragile, NEW.weight_kg, NEW.helpers_count, NEW.requested_vehicle_type_id,
        NEW.pickup_address, NEW.pickup_location::text, NEW.pickup_notes,
        NEW.dropoff_address, NEW.dropoff_location::text, NEW.dropoff_notes,
        NEW.pickup_type, NEW.pickup_window_start, NEW.pickup_window_end, NEW.route_distance_m, NEW.route_duration_s,
        NEW.payment_method, NEW.fare_paid_by, NEW.recipient_name, NEW.recipient_phone)
       IS DISTINCT FROM
       (OLD.customer_id, OLD.group_id, OLD.cargo_category_id, OLD.size_option_id, OLD.cargo_description,
        OLD.item_count, OLD.is_fragile, OLD.weight_kg, OLD.helpers_count, OLD.requested_vehicle_type_id,
        OLD.pickup_address, OLD.pickup_location::text, OLD.pickup_notes,
        OLD.dropoff_address, OLD.dropoff_location::text, OLD.dropoff_notes,
        OLD.pickup_type, OLD.pickup_window_start, OLD.pickup_window_end, OLD.route_distance_m, OLD.route_duration_s,
        OLD.payment_method, OLD.fare_paid_by, OLD.recipient_name, OLD.recipient_phone) THEN
        RAISE EXCEPTION 'shipment % details are fixed after the price was accepted', OLD.id;
    END IF;

    IF NEW.delivery_code IS DISTINCT FROM OLD.delivery_code AND shipment_is_locked(OLD.id) THEN
        IF app_actor_role() <> 'admin' OR NOT EXISTS (
               SELECT 1 FROM trips t WHERE t.shipment_id = OLD.id AND t.status = 'arrived_at_dropoff'
                 AND t.delivery_code_verified_at IS NULL
                 AND t.delivery_code_attempts >= (SELECT max_delivery_code_attempts FROM platform_settings)) THEN
            RAISE EXCEPTION 'shipment % delivery code is fixed: an admin issues a new one only after the attempts run out', OLD.id;
        END IF;
    END IF;

    IF pg_trigger_depth() = 1 THEN
        NEW.search_started_at := OLD.search_started_at;
    END IF;

    IF NEW.delivery_sequence IS DISTINCT FROM OLD.delivery_sequence AND OLD.status IN ('delivered', 'cancelled') THEN
        RAISE EXCEPTION 'shipment % is % and its delivery order cannot change', OLD.id, OLD.status;
    END IF;

    IF pg_trigger_depth() = 1 THEN
        NEW.details_version := OLD.details_version;
    END IF;
    IF (NEW.cargo_category_id, NEW.size_option_id, NEW.cargo_description, NEW.item_count, NEW.is_fragile,
        NEW.weight_kg, NEW.helpers_count, NEW.requested_vehicle_type_id,
        NEW.pickup_address, NEW.pickup_location::text, NEW.dropoff_address, NEW.dropoff_location::text,
        NEW.pickup_type, NEW.pickup_window_start, NEW.pickup_window_end, NEW.route_distance_m, NEW.route_duration_s)
       IS DISTINCT FROM
       (OLD.cargo_category_id, OLD.size_option_id, OLD.cargo_description, OLD.item_count, OLD.is_fragile,
        OLD.weight_kg, OLD.helpers_count, OLD.requested_vehicle_type_id,
        OLD.pickup_address, OLD.pickup_location::text, OLD.dropoff_address, OLD.dropoff_location::text,
        OLD.pickup_type, OLD.pickup_window_start, OLD.pickup_window_end, OLD.route_distance_m, OLD.route_duration_s) THEN
        NEW.details_version := OLD.details_version + 1;
    END IF;

    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF NOT (OLD.status || '>' || NEW.status = ANY (ARRAY[
        'draft>searching_driver', 'draft>cancelled',
        'searching_driver>driver_assigned', 'searching_driver>cancelled',
        'driver_assigned>in_progress', 'driver_assigned>searching_driver', 'driver_assigned>cancelled',
        'in_progress>delivered', 'in_progress>searching_driver', 'in_progress>cancelled'])) THEN
        RAISE EXCEPTION 'shipment % cannot go from % to %', OLD.id, OLD.status, NEW.status;
    END IF;

    IF NOT from_trip AND (NEW.status IN ('driver_assigned', 'in_progress', 'delivered')
                          OR OLD.status IN ('driver_assigned', 'in_progress')) THEN
        RAISE EXCEPTION 'shipment % follows its trip: change the trip status instead', OLD.id;
    END IF;

    IF NEW.status = 'searching_driver' THEN
        NEW.search_started_at := NULL;
    END IF;

    IF OLD.status = 'draft' AND NEW.status = 'searching_driver' THEN
        SELECT * INTO q FROM price_quotes WHERE shipment_id = NEW.id AND status = 'accepted';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'shipment % has no accepted quote', NEW.id;
        END IF;
        IF NOT accepted_latest_policies(NEW.customer_id) THEN
            RAISE EXCEPTION 'customer % must accept the latest terms and privacy policy before a new request', NEW.customer_id;
        END IF;
        PERFORM 1 FROM users WHERE id = NEW.customer_id FOR UPDATE;
        bal := customer_balance(NEW.customer_id);
        IF bal < 0 THEN
            RAISE EXCEPTION 'customer % wallet is negative (%): top up before a new request', NEW.customer_id, bal;
        END IF;
        IF NEW.payment_method = 'wallet' AND customer_available_balance(NEW.customer_id) < q.customer_amount THEN
            RAISE EXCEPTION 'insufficient wallet balance: % available, % needed',
                customer_available_balance(NEW.customer_id), q.customer_amount;
        END IF;
    END IF;

    IF NEW.status = 'cancelled' THEN
        NEW.cancelled_at := COALESCE(NEW.cancelled_at, now());
        NEW.cancelled_by := COALESCE(NEW.cancelled_by, app_actor_id());
        NEW.cancellation_party := COALESCE(NEW.cancellation_party,
            CASE WHEN NEW.cancelled_by = OLD.customer_id THEN 'customer'
                 WHEN NEW.cancelled_by IS NULL AND app_actor_role() = 'system' THEN 'platform' END);
        IF NEW.cancellation_party IS NULL THEN
            RAISE EXCEPTION 'shipment % cancellation needs cancellation_party (customer, driver or platform)', OLD.id;
        END IF;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_shipments_guard BEFORE INSERT OR UPDATE ON shipments
    FOR EACH ROW EXECUTE FUNCTION shipments_guard();

CREATE FUNCTION shipment_cargo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    sid BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN sid := OLD.shipment_id; ELSE sid := NEW.shipment_id; END IF;
    IF shipment_is_locked(sid)
       OR (TG_OP = 'UPDATE' AND NEW.shipment_id <> OLD.shipment_id AND shipment_is_locked(OLD.shipment_id)) THEN
        RAISE EXCEPTION 'shipment % cargo is fixed after the price was accepted', sid;
    END IF;
    UPDATE shipments SET details_version = details_version + 1 WHERE id = sid;
    IF TG_OP = 'UPDATE' AND NEW.shipment_id <> OLD.shipment_id THEN
        UPDATE shipments SET details_version = details_version + 1 WHERE id = OLD.shipment_id;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_shipment_items_guard BEFORE INSERT OR UPDATE OR DELETE ON shipment_items
    FOR EACH ROW EXECUTE FUNCTION shipment_cargo_guard();
CREATE TRIGGER trg_shipment_item_images_guard BEFORE INSERT OR UPDATE OR DELETE ON shipment_item_images
    FOR EACH ROW EXECUTE FUNCTION shipment_cargo_guard();

CREATE FUNCTION shipments_log_status() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO shipment_status_history (shipment_id, from_status, to_status, changed_by_user_id, change_source, reason)
        VALUES (NEW.id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END, NEW.status,
                app_actor_id(), app_actor_role(), COALESCE(app_change_reason(), NEW.cancellation_reason));
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_shipments_log_status AFTER INSERT OR UPDATE OF status ON shipments
    FOR EACH ROW EXECUTE FUNCTION shipments_log_status();

CREATE FUNCTION shipments_after_change() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    q     price_quotes%ROWTYPE;
    p     payments%ROWTYPE;
    left_ NUMERIC;
BEGIN
    IF OLD.status = 'draft' AND NEW.status = 'searching_driver' AND NEW.payment_method = 'wallet' THEN
        SELECT * INTO q FROM price_quotes WHERE shipment_id = NEW.id AND status = 'accepted';
        INSERT INTO payments (shipment_id, price_quote_id, method, payer, amount, status)
        VALUES (NEW.id, q.id, 'wallet', 'sender', q.customer_amount, 'paid');
    END IF;

    IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
        SELECT * INTO p FROM payments WHERE shipment_id = NEW.id AND method = 'wallet';
        IF FOUND THEN
            left_ := p.amount - COALESCE((SELECT SUM(amount) FROM refunds WHERE payment_id = p.id), 0);
            IF left_ > 0 THEN
                INSERT INTO refunds (payment_id, shipment_id, reason_type, amount, note)
                VALUES (p.id, NEW.id, 'cancellation', left_, 'shipment cancelled');
            END IF;
        END IF;
        UPDATE coupon_redemptions SET cancelled_at = now() WHERE shipment_id = NEW.id AND cancelled_at IS NULL;
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_shipments_after_change AFTER UPDATE OF status ON shipments
    FOR EACH ROW EXECUTE FUNCTION shipments_after_change();

CREATE FUNCTION shipments_code_reissued() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE trips SET delivery_code_attempts = 0
    WHERE shipment_id = NEW.id AND status = 'arrived_at_dropoff' AND delivery_code_verified_at IS NULL;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_shipments_code_reissued AFTER UPDATE OF delivery_code ON shipments
    FOR EACH ROW WHEN (NEW.delivery_code IS DISTINCT FROM OLD.delivery_code)
    EXECUTE FUNCTION shipments_code_reissued();

CREATE FUNCTION shipment_group_request_check() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    n_types     INTEGER;
BEGIN
    IF NEW.group_id IS NULL THEN
        RETURN NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM shipments WHERE group_id = NEW.group_id AND status = 'draft') THEN
        RAISE EXCEPTION 'group % must be requested all at once (a drop-off is still draft)', NEW.group_id;
    END IF;
    SELECT count(DISTINCT q.vehicle_type_id) INTO n_types
    FROM price_quotes q JOIN shipments s ON s.id = q.shipment_id
    WHERE s.group_id = NEW.group_id AND s.status <> 'cancelled' AND q.status = 'accepted';
    IF n_types > 1 THEN
        RAISE EXCEPTION 'group % drop-offs must be priced for one vehicle type', NEW.group_id;
    END IF;
    RETURN NULL;
END$$;
CREATE CONSTRAINT TRIGGER trg_shipment_group_request AFTER UPDATE OF status ON shipments
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW WHEN (OLD.status = 'draft' AND NEW.status = 'searching_driver')
    EXECUTE FUNCTION shipment_group_request_check();

CREATE FUNCTION price_quotes_insert_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    sh  shipments%ROWTYPE;
    st  platform_settings%ROWTYPE;
BEGIN
    IF NEW.status <> 'offered' THEN
        RAISE EXCEPTION 'a quote is created as offered and accepted later (so its version is checked)';
    END IF;
    SELECT * INTO sh FROM shipments WHERE id = NEW.shipment_id;
    SELECT * INTO st FROM platform_settings;
    IF NEW.shipment_version IS DISTINCT FROM sh.details_version THEN
        RAISE EXCEPTION 'quote was priced on version % of shipment %, but the details are now version %: price again',
            NEW.shipment_version, sh.id, sh.details_version;
    END IF;
    NEW.commission_rate  := st.commission_rate;
    NEW.helpers_count    := sh.helpers_count;
    SELECT helper_fee INTO NEW.helper_fee FROM vehicle_types WHERE id = NEW.vehicle_type_id;

    IF NEW.helpers_amount <> NEW.helpers_count * NEW.helper_fee THEN
        RAISE EXCEPTION 'helpers amount must be % (% helpers x %)',
            NEW.helpers_count * NEW.helper_fee, NEW.helpers_count, NEW.helper_fee;
    END IF;
    IF sh.group_id IS NULL AND NEW.group_discount_amount > 0 THEN
        RAISE EXCEPTION 'group discount applies to group shipments only';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shipment_item_images WHERE shipment_id = NEW.shipment_id) THEN
        RAISE EXCEPTION 'shipment % has no cargo photo: at least one photo is required before pricing', NEW.shipment_id;
    END IF;
    IF sh.pickup_type = 'scheduled'
       AND sh.pickup_window_start < now() + make_interval(mins => st.min_schedule_lead_minutes) THEN
        RAISE EXCEPTION 'scheduled pickup must start at least % minutes from now', st.min_schedule_lead_minutes;
    END IF;
    IF NEW.pricing_source = 'ai'
       AND NEW.transport_amount > round(NEW.standard_amount * st.max_dynamic_multiplier, 2) THEN
        RAISE EXCEPTION 'AI price % is above the cap % (standard % x %)', NEW.transport_amount,
            round(NEW.standard_amount * st.max_dynamic_multiplier, 2), NEW.standard_amount, st.max_dynamic_multiplier;
    END IF;
    IF NEW.coupon_id IS NOT NULL AND NEW.coupon_discount_amount <> coupon_discount(NEW.coupon_id, NEW.amount) THEN
        RAISE EXCEPTION 'coupon discount must be %', coupon_discount(NEW.coupon_id, NEW.amount);
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_price_quotes_insert_guard BEFORE INSERT ON price_quotes
    FOR EACH ROW EXECUTE FUNCTION price_quotes_insert_guard();

CREATE FUNCTION price_quotes_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'accepted' AND OLD.status <> 'accepted' THEN
        PERFORM 1 FROM shipment_groups g JOIN shipments s ON s.group_id = g.id
        WHERE s.id = OLD.shipment_id FOR UPDATE OF g;
    END IF;
    IF NEW.status = 'accepted' AND OLD.status <> 'accepted'
       AND OLD.shipment_version <> (SELECT details_version FROM shipments WHERE id = OLD.shipment_id) THEN
        RAISE EXCEPTION 'quote % was priced on an older version of shipment % (details changed): request a new quote',
            OLD.id, OLD.shipment_id;
    END IF;
    IF NEW.status = 'accepted' AND OLD.status <> 'accepted' THEN
        NEW.accepted_at := now();
        IF now() > OLD.expires_at THEN
            RAISE EXCEPTION 'quote % expired at %: request a new quote', OLD.id, OLD.expires_at;
        END IF;
    END IF;
    IF OLD.status = 'accepted' AND NEW.status = 'withdrawn'
       AND (SELECT status FROM shipments WHERE id = OLD.shipment_id) = 'draft' THEN
        NULL;
    ELSIF OLD.status <> 'offered' THEN
        RAISE EXCEPTION 'quote % is already %: create a new quote instead of editing it', OLD.id, OLD.status;
    END IF;
    IF (to_jsonb(NEW) - ARRAY['status', 'accepted_at']) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status', 'accepted_at'])
       OR (OLD.accepted_at IS NOT NULL AND NEW.accepted_at IS DISTINCT FROM OLD.accepted_at) THEN
        RAISE EXCEPTION 'quote % details are fixed: only its status can change', OLD.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_price_quotes_guard BEFORE UPDATE ON price_quotes
    FOR EACH ROW EXECUTE FUNCTION price_quotes_guard();

CREATE FUNCTION price_quotes_after_change() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    c    coupons%ROWTYPE;
    cid  BIGINT;
BEGIN
    IF NEW.status = 'accepted' AND OLD.status <> 'accepted' AND NEW.coupon_id IS NOT NULL THEN
        SELECT * INTO c FROM coupons WHERE id = NEW.coupon_id FOR UPDATE;
        SELECT customer_id INTO cid FROM shipments WHERE id = NEW.shipment_id;
        IF NOT c.is_active OR now() NOT BETWEEN c.starts_at AND c.ends_at THEN
            RAISE EXCEPTION 'coupon % is not active now', c.code;
        END IF;
        IF NEW.amount < c.min_order_amount THEN
            RAISE EXCEPTION 'coupon % needs an order of at least %', c.code, c.min_order_amount;
        END IF;
        IF c.max_total_uses IS NOT NULL AND (SELECT count(*) FROM coupon_redemptions
               WHERE coupon_id = c.id AND cancelled_at IS NULL) >= c.max_total_uses THEN
            RAISE EXCEPTION 'coupon % has no uses left', c.code;
        END IF;
        IF (SELECT count(*) FROM coupon_redemptions WHERE coupon_id = c.id AND customer_id = cid
               AND cancelled_at IS NULL) >= c.max_uses_per_customer THEN
            RAISE EXCEPTION 'coupon % was already used by this customer', c.code;
        END IF;
        INSERT INTO coupon_redemptions (coupon_id, customer_id, shipment_id, price_quote_id, discount_amount)
        VALUES (c.id, cid, NEW.shipment_id, NEW.id, NEW.coupon_discount_amount);
    ELSIF OLD.status = 'accepted' AND NEW.status = 'withdrawn' THEN
        UPDATE coupon_redemptions SET cancelled_at = now() WHERE price_quote_id = NEW.id AND cancelled_at IS NULL;
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_price_quotes_after_change AFTER UPDATE OF status ON price_quotes
    FOR EACH ROW EXECUTE FUNCTION price_quotes_after_change();

CREATE FUNCTION coupon_redemptions_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'coupon redemptions are written automatically when a quote is accepted';
    END IF;
    IF TG_OP = 'UPDATE' AND (OLD.cancelled_at IS NOT NULL
       OR (to_jsonb(NEW) - 'cancelled_at') IS DISTINCT FROM (to_jsonb(OLD) - 'cancelled_at')) THEN
        RAISE EXCEPTION 'coupon redemption % can only be cancelled once', OLD.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_coupon_redemptions_guard BEFORE INSERT OR UPDATE ON coupon_redemptions
    FOR EACH ROW EXECUTE FUNCTION coupon_redemptions_guard();

CREATE FUNCTION trips_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    sh   shipments%ROWTYPE;
    q    price_quotes%ROWTYPE;
    dp   driver_profiles%ROWTYPE;
    lic  driver_documents%ROWTYPE;
    ob   trips%ROWTYPE;
BEGIN
    SELECT * INTO sh FROM shipments WHERE id = NEW.shipment_id;

    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'assigned' THEN
            RAISE EXCEPTION 'a new trip must start as assigned';
        END IF;
        IF sh.status <> 'searching_driver' THEN
            RAISE EXCEPTION 'shipment % is % (not searching for a driver)', sh.id, sh.status;
        END IF;
        SELECT * INTO q FROM price_quotes WHERE id = NEW.price_quote_id;
        IF q.status IS DISTINCT FROM 'accepted' THEN
            RAISE EXCEPTION 'trip must use the accepted quote (quote % is %)', NEW.price_quote_id, q.status;
        END IF;
        NEW.fare_amount     := q.amount;
        NEW.commission_rate := q.commission_rate;
        NEW.group_id        := sh.group_id;
        IF NEW.started_at IS NOT NULL OR NEW.loaded_at IS NOT NULL OR NEW.delivered_at IS NOT NULL
           OR NEW.cancelled_at IS NOT NULL OR NEW.cancelled_by IS NOT NULL OR NEW.cancellation_reason IS NOT NULL
           OR NEW.cancellation_party IS NOT NULL OR NEW.is_late_cancellation OR NEW.cancellation_fee <> 0
           OR NEW.vehicle_fit IS NOT NULL OR NEW.departure_checked_at IS NOT NULL
           OR NEW.delivery_code_attempts <> 0 OR NEW.delivery_code_verified_at IS NOT NULL
           OR NEW.commission_amount IS NOT NULL OR NEW.driver_earning_amount IS NOT NULL
           OR NEW.cancellation_ticket_id IS NOT NULL THEN
            RAISE EXCEPTION 'a new trip starts empty: progress, delivery code, vehicle fit, money and cancellation are filled in later';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM vehicles WHERE id = NEW.vehicle_id AND vehicle_type_id = q.vehicle_type_id) THEN
            RAISE EXCEPTION 'vehicle % is not the vehicle type the price was quoted for', NEW.vehicle_id;
        END IF;
        IF (SELECT COALESCE(sum(s.weight_kg), 0) FROM shipments s
            WHERE (s.id = sh.id OR (sh.group_id IS NOT NULL AND s.group_id = sh.group_id)) AND s.status <> 'cancelled')
           > (SELECT max_payload_kg FROM vehicles WHERE id = NEW.vehicle_id) THEN
            RAISE EXCEPTION 'cargo weight is more than the payload of vehicle %', NEW.vehicle_id;
        END IF;
        IF NEW.return_match_proposal_id IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM return_match_proposals WHERE id = NEW.return_match_proposal_id AND status = 'confirmed') THEN
            RAISE EXCEPTION 'return proposal % is not confirmed', NEW.return_match_proposal_id;
        END IF;
        SELECT * INTO dp FROM driver_profiles WHERE user_id = NEW.driver_id;
        IF dp.verification_status <> 'approved' THEN
            RAISE EXCEPTION 'driver % is not approved', NEW.driver_id;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM vehicles WHERE id = NEW.vehicle_id AND status = 'active') THEN
            RAISE EXCEPTION 'vehicle % is not active', NEW.vehicle_id;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.driver_id AND account_status = 'active') THEN
            RAISE EXCEPTION 'driver % account is not active', NEW.driver_id;
        END IF;
        IF NOT accepted_latest_policies(NEW.driver_id) THEN
            RAISE EXCEPTION 'driver % must accept the latest terms and privacy policy', NEW.driver_id;
        END IF;
        IF driver_balance(NEW.driver_id) < -driver_debt_limit(NEW.driver_id) THEN
            RAISE EXCEPTION 'driver % is blocked: debt is over the limit', NEW.driver_id;
        END IF;
        IF dp.max_helpers < sh.helpers_count THEN
            RAISE EXCEPTION 'driver % can provide % helpers, shipment needs %', NEW.driver_id, dp.max_helpers, sh.helpers_count;
        END IF;
        lic := driver_current_license(NEW.driver_id);
        IF lic.id IS NULL OR lic.expires_on <= current_date THEN
            RAISE EXCEPTION 'driver % driving license is missing or expired', NEW.driver_id;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM vehicle_documents WHERE vehicle_id = NEW.vehicle_id
                       AND document_type = 'vehicle_license_front' AND review_status = 'approved'
                       AND superseded_at IS NULL AND expires_on > current_date) THEN
            RAISE EXCEPTION 'vehicle % license is missing or expired', NEW.vehicle_id;
        END IF;
        IF NOT license_fits_vehicle(NEW.driver_id, NEW.vehicle_id) THEN
            RAISE EXCEPTION 'driver % license category is too low for vehicle %', NEW.driver_id, NEW.vehicle_id;
        END IF;
        IF NEW.group_id IS NOT NULL AND EXISTS (
               SELECT 1 FROM trips WHERE group_id = NEW.group_id AND driver_id <> NEW.driver_id
               AND status NOT IN ('delivered', 'cancelled')) THEN
            RAISE EXCEPTION 'group % already has another driver', NEW.group_id;
        END IF;
        IF NEW.group_id IS NOT NULL AND EXISTS (
               SELECT 1 FROM trips WHERE group_id = NEW.group_id AND vehicle_id <> NEW.vehicle_id
               AND status NOT IN ('delivered', 'cancelled')) THEN
            RAISE EXCEPTION 'group % is loaded on one vehicle: all its trips use the same vehicle', NEW.group_id;
        END IF;
        IF dp.active_vehicle_id IS DISTINCT FROM NEW.vehicle_id THEN
            RAISE EXCEPTION 'vehicle % is not the active vehicle of driver %', NEW.vehicle_id, NEW.driver_id;
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status IN ('delivered', 'cancelled') THEN
        RAISE EXCEPTION 'trip % is % and final: correct it with a wallet adjustment instead', OLD.id, OLD.status;
    END IF;

    IF (NEW.shipment_id, NEW.group_id, NEW.driver_id, NEW.vehicle_id, NEW.price_quote_id, NEW.fare_amount,
        NEW.commission_rate, NEW.return_match_proposal_id)
       IS DISTINCT FROM
       (OLD.shipment_id, OLD.group_id, OLD.driver_id, OLD.vehicle_id, OLD.price_quote_id, OLD.fare_amount,
        OLD.commission_rate, OLD.return_match_proposal_id) THEN
        RAISE EXCEPTION 'trip % agreement (shipment, driver, vehicle, quote) cannot change', OLD.id;
    END IF;

    IF (NEW.delivery_code_attempts, NEW.delivery_code_verified_at)
       IS DISTINCT FROM (OLD.delivery_code_attempts, OLD.delivery_code_verified_at)
       AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'delivery code attempts are recorded by verify_delivery_code() only (an admin issues a new code to reset them)';
    END IF;

    IF (NEW.started_at, NEW.loaded_at, NEW.delivered_at, NEW.cancelled_at, NEW.commission_amount,
        NEW.driver_earning_amount, NEW.is_late_cancellation, NEW.cancellation_fee)
       IS DISTINCT FROM
       (OLD.started_at, OLD.loaded_at, OLD.delivered_at, OLD.cancelled_at, OLD.commission_amount,
        OLD.driver_earning_amount, OLD.is_late_cancellation, OLD.cancellation_fee) THEN
        RAISE EXCEPTION 'trip % times, money and cancellation fee are set by the database', OLD.id;
    END IF;
    IF NEW.status <> 'cancelled' AND (NEW.cancelled_by, NEW.cancellation_reason, NEW.cancellation_party, NEW.cancellation_ticket_id)
       IS DISTINCT FROM (OLD.cancelled_by, OLD.cancellation_reason, OLD.cancellation_party, OLD.cancellation_ticket_id) THEN
        RAISE EXCEPTION 'trip % cancellation details are written only when it is cancelled', OLD.id;
    END IF;

    IF (NEW.vehicle_fit, NEW.departure_checked_at) IS DISTINCT FROM (OLD.vehicle_fit, OLD.departure_checked_at) THEN
        IF OLD.vehicle_fit IS NOT NULL OR OLD.status <> 'loaded' THEN
            RAISE EXCEPTION 'vehicle fit is confirmed once, after loading';
        END IF;
        NEW.departure_checked_at := now();
    END IF;

    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF NEW.status <> 'cancelled'
       AND (NEW.cancellation_fee <> OLD.cancellation_fee OR NEW.is_late_cancellation <> OLD.is_late_cancellation) THEN
        RAISE EXCEPTION 'cancellation fee is set by the database at cancellation time';
    END IF;

    IF NOT (
         OLD.status || '>' || NEW.status = ANY (ARRAY[
            'assigned>heading_to_pickup', 'heading_to_pickup>arrived_at_pickup',
            'arrived_at_pickup>loaded', 'loaded>heading_to_dropoff',
            'heading_to_dropoff>arrived_at_dropoff', 'arrived_at_dropoff>delivered'])
         OR NEW.status = 'cancelled') THEN
        RAISE EXCEPTION 'trip % cannot go from % to %', OLD.id, OLD.status, NEW.status;
    END IF;

    IF NEW.status = 'heading_to_pickup' THEN
        IF NOT EXISTS (SELECT 1 FROM users WHERE id = OLD.driver_id AND account_status = 'active')
           OR NOT EXISTS (SELECT 1 FROM driver_profiles WHERE user_id = OLD.driver_id AND verification_status = 'approved') THEN
            RAISE EXCEPTION 'driver % is not active: trip % cannot start', OLD.driver_id, OLD.id;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM vehicles WHERE id = OLD.vehicle_id AND status = 'active') THEN
            RAISE EXCEPTION 'vehicle % is not active: trip % cannot start', OLD.vehicle_id, OLD.id;
        END IF;
        lic := driver_current_license(OLD.driver_id);
        IF lic.id IS NULL OR lic.expires_on <= current_date OR NOT license_fits_vehicle(OLD.driver_id, OLD.vehicle_id) THEN
            RAISE EXCEPTION 'driver % driving license is missing, expired or too low: trip % cannot start', OLD.driver_id, OLD.id;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM vehicle_documents WHERE vehicle_id = OLD.vehicle_id
                       AND document_type = 'vehicle_license_front' AND review_status = 'approved'
                       AND superseded_at IS NULL AND expires_on > current_date) THEN
            RAISE EXCEPTION 'vehicle % license is missing or expired: trip % cannot start', OLD.vehicle_id, OLD.id;
        END IF;
        IF (SELECT active_vehicle_id FROM driver_profiles WHERE user_id = OLD.driver_id) IS DISTINCT FROM OLD.vehicle_id THEN
            RAISE EXCEPTION 'vehicle % is not the active vehicle of driver %: trip % cannot start', OLD.vehicle_id, OLD.driver_id, OLD.id;
        END IF;
        PERFORM unified_start_eligibility(OLD.driver_id, OLD.vehicle_id, OLD.shipment_id, OLD.price_quote_id);
        NEW.started_at := now();
        IF NEW.return_match_proposal_id IS NOT NULL THEN
            SELECT t.* INTO ob FROM trips t JOIN return_match_proposals r ON r.outbound_trip_id = t.id
            WHERE r.id = NEW.return_match_proposal_id;
            IF EXISTS (SELECT 1 FROM trips t
                       WHERE (t.id = ob.id OR (ob.group_id IS NOT NULL AND t.group_id = ob.group_id))
                         AND t.status NOT IN ('delivered', 'cancelled')) THEN
                RAISE EXCEPTION 'return trip % cannot start before the outbound delivery is finished', OLD.id;
            END IF;
        END IF;
    END IF;

    IF NEW.status = 'loaded' THEN
        IF NOT EXISTS (SELECT 1 FROM trip_photos WHERE trip_id = OLD.id AND stage = 'pickup') THEN
            RAISE EXCEPTION 'trip % needs at least one pickup photo before loading', OLD.id;
        END IF;
        IF sh.payment_method = 'cash' AND sh.fare_paid_by = 'sender' AND NOT EXISTS (
               SELECT 1 FROM payments WHERE collected_on_trip_id = OLD.id AND status = 'collected') THEN
            RAISE EXCEPTION 'trip % cannot be loaded: the sender''s cash was not collected', OLD.id;
        END IF;
        NEW.loaded_at := now();
    END IF;

    IF NEW.status = 'heading_to_dropoff' AND NEW.vehicle_fit IS NULL THEN
        RAISE EXCEPTION 'trip % needs the vehicle fit confirmation before leaving', OLD.id;
    END IF;

    IF NEW.status = 'delivered' THEN
        IF NOT EXISTS (SELECT 1 FROM trip_photos WHERE trip_id = OLD.id AND stage = 'delivery') THEN
            RAISE EXCEPTION 'trip % needs at least one delivery photo', OLD.id;
        END IF;
        IF NEW.delivery_code_verified_at IS NULL THEN
            RAISE EXCEPTION 'trip % delivery code was not verified', OLD.id;
        END IF;
        IF sh.payment_method = 'wallet' AND NOT EXISTS (
               SELECT 1 FROM payments WHERE shipment_id = sh.id AND status = 'paid') THEN
            RAISE EXCEPTION 'trip % cannot be delivered: wallet payment missing', OLD.id;
        END IF;
        IF sh.payment_method = 'cash' AND NOT EXISTS (
               SELECT 1 FROM payments WHERE collected_on_trip_id = OLD.id
               AND status IN ('collected', 'charged_to_sender')) THEN
            RAISE EXCEPTION 'trip % cannot be delivered: cash was not collected (or recipient refusal recorded)', OLD.id;
        END IF;
        NEW.delivered_at          := now();
        NEW.commission_amount     := round(NEW.fare_amount * NEW.commission_rate, 2);
        NEW.driver_earning_amount := NEW.fare_amount - NEW.commission_amount;
    END IF;

    IF NEW.status = 'cancelled' THEN
        NEW.cancelled_at := now();
        NEW.cancelled_by := COALESCE(NEW.cancelled_by, app_actor_id());
        NEW.cancellation_party := COALESCE(NEW.cancellation_party,
            CASE WHEN NEW.cancelled_by = sh.customer_id THEN 'customer'
                 WHEN NEW.cancelled_by = OLD.driver_id THEN 'driver'
                 WHEN NEW.cancelled_by IS NULL AND app_actor_role() = 'system' THEN 'platform' END);
        IF NEW.cancellation_party IS NULL THEN
            RAISE EXCEPTION 'trip % cancellation needs cancellation_party (customer, driver or platform)', OLD.id;
        END IF;
        IF OLD.status IN ('loaded', 'heading_to_dropoff', 'arrived_at_dropoff') AND app_actor_role() <> 'admin' THEN
            RAISE EXCEPTION 'after loading only an admin can cancel trip %', OLD.id;
        END IF;
        IF OLD.loaded_at IS NOT NULL OR (OLD.group_id IS NOT NULL AND EXISTS (
             SELECT 1 FROM trips WHERE group_id = OLD.group_id AND loaded_at IS NOT NULL)) THEN
            IF app_actor_role() IS DISTINCT FROM 'admin' OR NOT has_role(app_actor_id(), 'admin') THEN
                RAISE EXCEPTION 'U_CARGO_ADMIN: only a verified admin can cancel a group with loaded cargo';
            END IF;
            IF btrim(COALESCE(NEW.cancellation_reason, '')) = '' OR NOT EXISTS (
                   SELECT 1 FROM support_tickets tk JOIN trips tt ON tt.id = tk.trip_id
                   WHERE tk.id = NEW.cancellation_ticket_id
                     AND (tt.id = OLD.id OR (OLD.group_id IS NOT NULL AND tt.group_id = OLD.group_id))
                     AND tk.status IN ('resolved', 'closed') AND tk.cargo_outcome IS NOT NULL
                     AND btrim(COALESCE(tk.resolution_note, '')) <> ''
                     AND tk.resolved_by IS NOT NULL) THEN
                RAISE EXCEPTION 'trip % was loaded: cancelling needs a reason and a resolved support ticket saying where the cargo went', OLD.id;
            END IF;
        ELSIF NEW.cancellation_ticket_id IS NOT NULL THEN
            RAISE EXCEPTION 'trip % was not loaded: no cargo ticket needed', OLD.id;
        END IF;
        IF NEW.cancellation_party = 'customer' AND OLD.status <> 'assigned' THEN
            NEW.is_late_cancellation := true;
            NEW.cancellation_fee := (SELECT cancellation_fee FROM platform_settings);
        ELSE
            NEW.is_late_cancellation := false;
            NEW.cancellation_fee := 0;
        END IF;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_trips_guard BEFORE INSERT OR UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION trips_guard();

CREATE FUNCTION trips_after_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    sh  shipments%ROWTYPE;
    p   payments%ROWTYPE;
    q   price_quotes%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.status = OLD.status THEN
        RETURN NULL;
    END IF;

    INSERT INTO trip_status_history (trip_id, from_status, to_status, changed_by_user_id, change_source, reason)
    VALUES (NEW.id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END, NEW.status,
            app_actor_id(), app_actor_role(), COALESCE(app_change_reason(), NEW.cancellation_reason));

    SELECT * INTO sh FROM shipments WHERE id = NEW.shipment_id;

    IF TG_OP = 'INSERT' THEN
        UPDATE shipments SET status = 'driver_assigned' WHERE id = NEW.shipment_id;
    ELSIF NEW.status = 'heading_to_pickup' THEN
        UPDATE shipments SET status = 'in_progress' WHERE id = NEW.shipment_id;
    ELSIF NEW.status = 'delivered' THEN
        UPDATE shipments SET status = 'delivered' WHERE id = NEW.shipment_id;
    ELSIF NEW.status = 'cancelled' THEN
        IF NEW.cancellation_party = 'customer' OR NEW.loaded_at IS NOT NULL
           OR (NEW.group_id IS NOT NULL AND EXISTS (
                   SELECT 1 FROM trips WHERE group_id = NEW.group_id AND loaded_at IS NOT NULL)) THEN
            UPDATE shipments SET status = 'cancelled', cancelled_by = NEW.cancelled_by,
                                 cancellation_reason = NEW.cancellation_reason,
                                 cancellation_party = NEW.cancellation_party
            WHERE id = NEW.shipment_id;
            IF NEW.cancellation_party <> 'customer' AND NEW.group_id IS NOT NULL AND pg_trigger_depth() = 1 THEN
                UPDATE trips SET status = 'cancelled', cancellation_party = NEW.cancellation_party,
                                 cancelled_by = NEW.cancelled_by, cancellation_reason = NEW.cancellation_reason,
                                 cancellation_ticket_id = NEW.cancellation_ticket_id
                WHERE group_id = NEW.group_id AND id <> NEW.id AND status NOT IN ('delivered', 'cancelled');
            END IF;
        ELSE
            UPDATE shipments SET status = 'searching_driver' WHERE id = NEW.shipment_id;
            IF NEW.group_id IS NOT NULL AND pg_trigger_depth() = 1 THEN
                UPDATE trips SET status = 'cancelled', cancellation_party = NEW.cancellation_party,
                                 cancelled_by = NEW.cancelled_by, cancellation_reason = NEW.cancellation_reason,
                                 cancellation_ticket_id = NEW.cancellation_ticket_id
                WHERE group_id = NEW.group_id AND id <> NEW.id AND status NOT IN ('delivered', 'cancelled');
            END IF;
        END IF;
    END IF;

    IF NEW.status = 'delivered' THEN
        SELECT * INTO p FROM payments
        WHERE shipment_id = NEW.shipment_id AND (method = 'wallet' OR collected_on_trip_id = NEW.id);
        IF p.method = 'wallet' OR p.status = 'charged_to_sender' THEN
            IF NEW.driver_earning_amount > 0 THEN
                INSERT INTO wallet_transactions (driver_id, entry_type, amount, trip_id)
                VALUES (NEW.driver_id, 'trip_earning', NEW.driver_earning_amount, NEW.id);
            END IF;
        ELSE
            IF NEW.commission_amount > 0 THEN
                INSERT INTO wallet_transactions (driver_id, entry_type, amount, trip_id)
                VALUES (NEW.driver_id, 'commission_charge', -NEW.commission_amount, NEW.id);
            END IF;
            SELECT * INTO q FROM price_quotes WHERE id = NEW.price_quote_id;
            IF q.coupon_discount_amount > 0 THEN
                INSERT INTO wallet_transactions (driver_id, entry_type, amount, trip_id)
                VALUES (NEW.driver_id, 'coupon_compensation', q.coupon_discount_amount, NEW.id);
            END IF;
        END IF;
    ELSIF NEW.status = 'cancelled' THEN
        FOR p IN SELECT * FROM payments WHERE collected_on_trip_id = NEW.id LOOP
            INSERT INTO refunds (payment_id, shipment_id, reason_type, amount, note)
            VALUES (p.id, p.shipment_id, 'cancellation', p.amount, 'trip cancelled after the cash was collected');
        END LOOP;
        IF NEW.cancellation_fee > 0 THEN
            INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, trip_id)
            VALUES (sh.customer_id, 'cancellation_fee', -NEW.cancellation_fee, NEW.id);
            INSERT INTO wallet_transactions (driver_id, entry_type, amount, trip_id)
            VALUES (NEW.driver_id, 'cancellation_compensation', NEW.cancellation_fee, NEW.id);
        END IF;
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_trips_after_change AFTER INSERT OR UPDATE OF status ON trips
    FOR EACH ROW EXECUTE FUNCTION trips_after_change();

CREATE FUNCTION group_trips_check() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM shipments WHERE group_id = NEW.group_id AND status = 'searching_driver') THEN
        RAISE EXCEPTION 'group % must be assigned to one driver all at once', NEW.group_id;
    END IF;
    RETURN NULL;
END$$;
CREATE CONSTRAINT TRIGGER trg_group_trips_check AFTER INSERT ON trips
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW WHEN (NEW.group_id IS NOT NULL)
    EXECUTE FUNCTION group_trips_check();

CREATE FUNCTION delivery_code_attempts_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    t  trips%ROWTYPE;
BEGIN
    SELECT * INTO t FROM trips WHERE id = NEW.trip_id FOR UPDATE;
    IF t.status <> 'arrived_at_dropoff' THEN
        RAISE EXCEPTION 'trip % is % (the code is entered at the drop-off)', t.id, t.status;
    END IF;
    IF t.delivery_code_verified_at IS NOT NULL THEN
        RAISE EXCEPTION 'trip % delivery code is already verified', t.id;
    END IF;
    IF t.delivery_code_attempts >= (SELECT max_delivery_code_attempts FROM platform_settings) THEN
        RAISE EXCEPTION 'trip % delivery code is locked after too many attempts: contact support', t.id;
    END IF;
    NEW.is_correct   := NEW.entered_code = (SELECT delivery_code FROM shipments WHERE id = t.shipment_id);
    NEW.attempted_by := COALESCE(NEW.attempted_by, app_actor_id());
    NEW.attempted_at := now();
    RETURN NEW;
END$$;
CREATE TRIGGER trg_delivery_code_attempts_guard BEFORE INSERT ON delivery_code_attempts
    FOR EACH ROW EXECUTE FUNCTION delivery_code_attempts_guard();

CREATE FUNCTION delivery_code_attempts_after() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.is_correct THEN
        UPDATE trips SET delivery_code_verified_at = now() WHERE id = NEW.trip_id;
    ELSE
        UPDATE trips SET delivery_code_attempts = delivery_code_attempts + 1 WHERE id = NEW.trip_id;
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_delivery_code_attempts_after AFTER INSERT ON delivery_code_attempts
    FOR EACH ROW EXECUTE FUNCTION delivery_code_attempts_after();

CREATE FUNCTION verify_delivery_code(p_trip BIGINT, p_code TEXT) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
    ok BOOLEAN;
BEGIN
    INSERT INTO delivery_code_attempts (trip_id, entered_code) VALUES (p_trip, p_code) RETURNING is_correct INTO ok;
    RETURN ok;
END$$;

CREATE FUNCTION return_proposals_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status <> 'pending' OR NEW.driver_response <> 'pending' OR NEW.customer_response <> 'pending'
       OR NEW.driver_responded_at IS NOT NULL OR NEW.customer_responded_at IS NOT NULL THEN
        RAISE EXCEPTION 'a return proposal starts as pending for both the driver and the customer';
    END IF;
    IF (SELECT group_id FROM shipments WHERE id = NEW.shipment_id) IS NOT NULL THEN
        RAISE EXCEPTION 'a return trip shipment cannot be part of a group';
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_return_proposals_guard BEFORE INSERT ON return_match_proposals
    FOR EACH ROW EXECUTE FUNCTION return_proposals_guard();

CREATE FUNCTION return_proposals_update_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    answer CONSTANT TEXT[] := ARRAY['status', 'driver_response', 'customer_response',
                                    'driver_responded_at', 'customer_responded_at'];
BEGIN
    IF OLD.status <> 'pending' THEN
        RAISE EXCEPTION 'return proposal % is % and final', OLD.id, OLD.status;
    END IF;
    IF (to_jsonb(NEW) - answer) IS DISTINCT FROM (to_jsonb(OLD) - answer) THEN
        RAISE EXCEPTION 'return proposal % details cannot change: only the answers', OLD.id;
    END IF;
    IF OLD.driver_response <> 'pending' AND NEW.driver_response IS DISTINCT FROM OLD.driver_response THEN
        RAISE EXCEPTION 'the driver already answered return proposal %', OLD.id;
    END IF;
    IF OLD.customer_response <> 'pending' AND NEW.customer_response IS DISTINCT FROM OLD.customer_response THEN
        RAISE EXCEPTION 'the customer already answered return proposal %', OLD.id;
    END IF;
    NEW.driver_responded_at   := CASE WHEN NEW.driver_response = 'pending' THEN NULL
                                      WHEN OLD.driver_response = 'pending' THEN now() ELSE OLD.driver_responded_at END;
    NEW.customer_responded_at := CASE WHEN NEW.customer_response = 'pending' THEN NULL
                                      WHEN OLD.customer_response = 'pending' THEN now() ELSE OLD.customer_responded_at END;
    IF NEW.status = 'confirmed' AND now() > OLD.expires_at THEN
        RAISE EXCEPTION 'return proposal % expired at %: it cannot be confirmed', OLD.id, OLD.expires_at;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_return_proposals_update_guard BEFORE UPDATE ON return_match_proposals
    FOR EACH ROW EXECUTE FUNCTION return_proposals_update_guard();

CREATE FUNCTION dispatch_offers_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    lead INTEGER := (SELECT scheduled_search_lead_minutes FROM platform_settings);
BEGIN
    IF NEW.response <> 'pending' OR NEW.responded_at IS NOT NULL OR NEW.trip_id IS NOT NULL THEN
        RAISE EXCEPTION 'an offer starts as pending, without a response or a trip';
    END IF;
    IF EXISTS (SELECT 1 FROM price_quotes q JOIN shipments s ON s.id = q.shipment_id
               WHERE q.status = 'accepted' AND (s.id = NEW.shipment_id OR s.group_id = NEW.group_id)
                 AND q.vehicle_type_id <> (SELECT vehicle_type_id FROM vehicles WHERE id = NEW.vehicle_id)) THEN
        RAISE EXCEPTION 'vehicle % is not the vehicle type the price was quoted for', NEW.vehicle_id;
    END IF;
    IF (SELECT COALESCE(sum(weight_kg), 0) FROM shipments
        WHERE (id = NEW.shipment_id OR group_id = NEW.group_id) AND status <> 'cancelled')
       > (SELECT max_payload_kg FROM vehicles WHERE id = NEW.vehicle_id) THEN
        RAISE EXCEPTION 'cargo weight is more than the payload of vehicle %', NEW.vehicle_id;
    END IF;
    IF EXISTS (SELECT 1 FROM shipments s
               WHERE (s.id = NEW.shipment_id OR s.group_id = NEW.group_id) AND s.status <> 'searching_driver') THEN
        RAISE EXCEPTION 'offer target is not searching for a driver';
    END IF;
    IF EXISTS (SELECT 1 FROM shipments s
               WHERE (s.id = NEW.shipment_id OR s.group_id = NEW.group_id) AND s.pickup_type = 'scheduled'
                 AND s.pickup_window_start - make_interval(mins => lead) > now()) THEN
        RAISE EXCEPTION 'scheduled pickup: offers start % minutes before the pickup time', lead;
    END IF;
    UPDATE shipments SET search_started_at = now()
    WHERE (id = NEW.shipment_id OR group_id = NEW.group_id) AND search_started_at IS NULL;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_dispatch_offers_guard BEFORE INSERT ON dispatch_offers
    FOR EACH ROW EXECUTE FUNCTION dispatch_offers_guard();

CREATE FUNCTION trip_share_links_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT status FROM trips WHERE id = NEW.trip_id) IN ('delivered', 'cancelled') THEN
        RAISE EXCEPTION 'trip % is finished: no new share link', NEW.trip_id;
    END IF;
    IF NEW.created_by IS NOT NULL AND trip_party(NEW.trip_id, NEW.created_by) IS DISTINCT FROM 'customer' THEN
        RAISE EXCEPTION 'only the customer of trip % (or the system) can create a share link', NEW.trip_id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_trip_share_links_guard BEFORE INSERT ON trip_share_links
    FOR EACH ROW EXECUTE FUNCTION trip_share_links_guard();

CREATE FUNCTION payments_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    sh  shipments%ROWTYPE;
    t   trips%ROWTYPE;
BEGIN
    SELECT * INTO sh FROM shipments WHERE id = NEW.shipment_id;
    IF NOT EXISTS (SELECT 1 FROM price_quotes WHERE id = NEW.price_quote_id AND status = 'accepted') THEN
        RAISE EXCEPTION 'payment must be for the accepted quote of the shipment';
    END IF;
    IF sh.status IN ('draft', 'cancelled', 'delivered') THEN
        RAISE EXCEPTION 'shipment % is %: no payment now', sh.id, sh.status;
    END IF;
    IF NEW.payer <> sh.fare_paid_by THEN
        RAISE EXCEPTION 'shipment % fare is paid by %, not %', sh.id, sh.fare_paid_by, NEW.payer;
    END IF;
    IF NEW.method = 'wallet' THEN
        IF pg_trigger_depth() < 2 THEN
            RAISE EXCEPTION 'wallet payments are taken automatically when the shipment is requested';
        END IF;
        RETURN NEW;
    END IF;
    SELECT * INTO t FROM trips WHERE id = NEW.collected_on_trip_id;
    IF t.status = 'cancelled' THEN
        RAISE EXCEPTION 'trip % is cancelled', t.id;
    END IF;
    IF NEW.payer = 'sender' AND t.status <> 'arrived_at_pickup' THEN
        RAISE EXCEPTION 'the sender pays at pickup (trip % is %)', t.id, t.status;
    END IF;
    IF NEW.payer = 'recipient' AND t.status <> 'arrived_at_dropoff' THEN
        RAISE EXCEPTION 'the recipient pays at drop-off (trip % is %)', t.id, t.status;
    END IF;
    NEW.collected_at := now();
    RETURN NEW;
END$$;
CREATE TRIGGER trg_payments_guard BEFORE INSERT ON payments
    FOR EACH ROW EXECUTE FUNCTION payments_guard();

CREATE FUNCTION payments_after_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    cid BIGINT;
BEGIN
    SELECT customer_id INTO cid FROM shipments WHERE id = NEW.shipment_id;
    IF NEW.status = 'paid' THEN
        INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, payment_id)
        VALUES (cid, 'trip_payment', -NEW.amount, NEW.id);
    ELSIF NEW.status = 'charged_to_sender' THEN
        INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, payment_id)
        VALUES (cid, 'recipient_refused_charge', -NEW.amount, NEW.id);
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_payments_after_insert AFTER INSERT ON payments
    FOR EACH ROW EXECUTE FUNCTION payments_after_insert();

CREATE FUNCTION refunds_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    p  payments%ROWTYPE;
    d  disputes%ROWTYPE;
BEGIN
    SELECT * INTO p FROM payments WHERE id = NEW.payment_id FOR UPDATE;
    IF COALESCE((SELECT SUM(amount) FROM refunds WHERE payment_id = p.id), 0) + NEW.amount > p.amount THEN
        RAISE EXCEPTION 'refunds would exceed the payment of %', p.amount;
    END IF;
    IF NEW.reason_type = 'cancellation' THEN
        IF pg_trigger_depth() < 2 THEN
            RAISE EXCEPTION 'cancellation refunds are made automatically when the shipment is cancelled';
        END IF;
    ELSE
        SELECT * INTO d FROM disputes WHERE id = NEW.dispute_id;
        IF d.status IS DISTINCT FROM 'resolved' OR d.resolution NOT IN ('refund_customer', 'split')
           OR COALESCE(d.customer_amount, 0) <= 0 THEN
            RAISE EXCEPTION 'dispute % is not resolved with a refund amount', d.id;
        END IF;
        IF COALESCE((SELECT SUM(amount) FROM refunds WHERE dispute_id = d.id), 0) + NEW.amount > d.customer_amount THEN
            RAISE EXCEPTION 'refunds would exceed the dispute decision of %', d.customer_amount;
        END IF;
    END IF;
    NEW.created_by := COALESCE(NEW.created_by, app_actor_id());
    NEW.created_at := now();
    RETURN NEW;
END$$;
CREATE TRIGGER trg_refunds_guard BEFORE INSERT ON refunds
    FOR EACH ROW EXECUTE FUNCTION refunds_guard();

CREATE FUNCTION refunds_after_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    d  disputes%ROWTYPE;
    p  payments%ROWTYPE;
BEGIN
    INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, refund_id)
    VALUES ((SELECT customer_id FROM shipments WHERE id = NEW.shipment_id), 'refund', NEW.amount, NEW.id);
    IF NEW.reason_type = 'cancellation' THEN
        SELECT * INTO p FROM payments WHERE id = NEW.payment_id;
        IF p.method = 'cash' AND p.status = 'collected' THEN
            INSERT INTO wallet_transactions (driver_id, entry_type, amount, refund_id, trip_id)
            VALUES (p.collected_by_driver_id, 'collected_cash_charge', -NEW.amount, NEW.id, p.collected_on_trip_id);
        END IF;
    END IF;
    IF NEW.dispute_id IS NOT NULL THEN
        SELECT * INTO d FROM disputes WHERE id = NEW.dispute_id;
        IF d.refund_borne_by = 'driver' THEN
            INSERT INTO wallet_transactions (driver_id, entry_type, amount, refund_id, trip_id, created_by)
            VALUES ((SELECT driver_id FROM trips WHERE id = d.trip_id), 'refund_charge', -NEW.amount,
                    NEW.id, d.trip_id, NEW.created_by);
        END IF;
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_refunds_after_insert AFTER INSERT ON refunds
    FOR EACH ROW EXECUTE FUNCTION refunds_after_insert();

CREATE FUNCTION wallet_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    r  refunds%ROWTYPE;
BEGIN
    PERFORM 1 FROM driver_profiles WHERE user_id = NEW.driver_id FOR UPDATE;
    IF NEW.entry_type <> 'manual_adjustment' AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION '% entries are written automatically by the database', NEW.entry_type;
    END IF;
    IF NEW.entry_type = 'refund_charge' THEN
        SELECT * INTO r FROM refunds WHERE id = NEW.refund_id;
        IF NOT EXISTS (SELECT 1 FROM disputes d WHERE d.id = r.dispute_id AND d.trip_id = NEW.trip_id
                       AND d.refund_borne_by = 'driver') THEN
            RAISE EXCEPTION 'refund % is not a dispute refund borne by the driver of trip %', r.id, NEW.trip_id;
        END IF;
    END IF;
    IF NEW.entry_type = 'collected_cash_charge' AND NOT EXISTS (
           SELECT 1 FROM refunds rf JOIN payments py ON py.id = rf.payment_id
           WHERE rf.id = NEW.refund_id AND rf.reason_type = 'cancellation' AND py.method = 'cash'
             AND py.collected_by_driver_id = NEW.driver_id AND py.collected_on_trip_id = NEW.trip_id) THEN
        RAISE EXCEPTION 'refund % is not a cash refund collected by driver % on trip %', NEW.refund_id, NEW.driver_id, NEW.trip_id;
    END IF;
    IF NEW.entry_type = 'payout' AND driver_balance(NEW.driver_id) + NEW.amount < 0 THEN
        RAISE EXCEPTION 'insufficient balance: % available, payout %', driver_balance(NEW.driver_id), -NEW.amount;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_wallet_guard BEFORE INSERT ON wallet_transactions
    FOR EACH ROW EXECUTE FUNCTION wallet_guard();

CREATE FUNCTION customer_wallet_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    owner BIGINT;
BEGIN
    PERFORM 1 FROM users WHERE id = NEW.customer_id FOR UPDATE;
    IF NEW.entry_type <> 'manual_adjustment' AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION '% entries are written automatically by the database', NEW.entry_type;
    END IF;
    owner := CASE
        WHEN NEW.payment_id IS NOT NULL THEN
            (SELECT s.customer_id FROM payments p JOIN shipments s ON s.id = p.shipment_id WHERE p.id = NEW.payment_id)
        WHEN NEW.refund_id IS NOT NULL THEN
            (SELECT s.customer_id FROM refunds r JOIN shipments s ON s.id = r.shipment_id WHERE r.id = NEW.refund_id)
        WHEN NEW.trip_id IS NOT NULL THEN
            (SELECT s.customer_id FROM trips t JOIN shipments s ON s.id = t.shipment_id WHERE t.id = NEW.trip_id)
        ELSE NEW.customer_id END;
    IF owner IS DISTINCT FROM NEW.customer_id THEN
        RAISE EXCEPTION 'wallet entry belongs to customer %, not %', owner, NEW.customer_id;
    END IF;
    IF NEW.entry_type = 'trip_payment' AND customer_available_balance(NEW.customer_id) + NEW.amount < 0 THEN
        RAISE EXCEPTION 'insufficient wallet balance: % available, % needed',
            customer_available_balance(NEW.customer_id), -NEW.amount;
    END IF;
    IF NEW.entry_type = 'withdrawal' AND customer_balance(NEW.customer_id) + NEW.amount < 0 THEN
        RAISE EXCEPTION 'insufficient wallet balance: % available, % needed',
            customer_balance(NEW.customer_id), -NEW.amount;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_customer_wallet_guard BEFORE INSERT ON customer_wallet_transactions
    FOR EACH ROW EXECUTE FUNCTION customer_wallet_guard();

CREATE FUNCTION assert_transfer_unused(p_reference TEXT, p_table TEXT) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM incoming_transfer_claims
               WHERE transfer_reference = lower(btrim(p_reference))) THEN
        RAISE EXCEPTION 'transfer % was already confirmed for another payment', p_reference;
    END IF;
END$$;

CREATE FUNCTION settlements_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'awaiting_verification' OR NEW.verified_by IS NOT NULL OR NEW.verified_at IS NOT NULL THEN
            RAISE EXCEPTION 'a settlement starts as awaiting_verification';
        END IF;
        RETURN NEW;
    END IF;
    IF OLD.status <> 'awaiting_verification' THEN
        RAISE EXCEPTION 'settlement % is already %', OLD.id, OLD.status;
    END IF;
    IF (NEW.driver_id, NEW.amount, NEW.proof_storage_key, NEW.created_at)
       IS DISTINCT FROM (OLD.driver_id, OLD.amount, OLD.proof_storage_key, OLD.created_at) THEN
        RAISE EXCEPTION 'settlement % details cannot change', OLD.id;
    END IF;
    IF NEW.status = 'verified' THEN
        PERFORM assert_transfer_unused(NEW.transfer_reference, 'driver_settlements');
    END IF;
    IF NEW.status <> 'awaiting_verification' THEN
        NEW.verified_at := now();
        NEW.verified_by := COALESCE(NEW.verified_by, app_actor_id());
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_settlements_guard BEFORE INSERT OR UPDATE ON driver_settlements
    FOR EACH ROW EXECUTE FUNCTION settlements_guard();

CREATE FUNCTION settlements_after_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'verified' AND (TG_OP = 'INSERT' OR OLD.status <> 'verified') THEN
        INSERT INTO wallet_transactions (driver_id, entry_type, amount, settlement_id, created_by)
        VALUES (NEW.driver_id, 'debt_settlement', NEW.amount, NEW.id, NEW.verified_by);
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_settlements_after_change AFTER INSERT OR UPDATE OF status ON driver_settlements
    FOR EACH ROW EXECUTE FUNCTION settlements_after_change();

CREATE FUNCTION payouts_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'requested' THEN
            RAISE EXCEPTION 'a payout starts as requested';
        END IF;
        IF NEW.created_by IS NOT NULL OR app_actor_role() <> 'system' THEN
            RAISE EXCEPTION 'driver payouts are created by the weekly system job only';
        END IF;
        PERFORM 1 FROM driver_profiles WHERE user_id = NEW.driver_id FOR UPDATE;
        IF NEW.amount > driver_balance(NEW.driver_id) THEN
            RAISE EXCEPTION 'insufficient balance: % available, requested %', driver_balance(NEW.driver_id), NEW.amount;
        END IF;
        RETURN NEW;
    END IF;
    IF OLD.status <> 'requested' THEN
        RAISE EXCEPTION 'payout % is already %', OLD.id, OLD.status;
    END IF;
    IF (NEW.driver_id, NEW.payout_account_id, NEW.amount, NEW.created_by)
       IS DISTINCT FROM (OLD.driver_id, OLD.payout_account_id, OLD.amount, OLD.created_by) THEN
        RAISE EXCEPTION 'payout % details cannot change', OLD.id;
    END IF;
    IF NEW.status = 'paid' AND NOT EXISTS (SELECT 1 FROM payout_accounts WHERE id = NEW.payout_account_id
                                           AND review_status = 'approved' AND superseded_at IS NULL) THEN
        RAISE EXCEPTION 'payout account % is not the current approved account', NEW.payout_account_id;
    END IF;
    IF NEW.status <> 'requested' THEN
        NEW.processed_at := now();
        NEW.processed_by := COALESCE(NEW.processed_by, app_actor_id());
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_payouts_guard BEFORE INSERT OR UPDATE ON payout_requests
    FOR EACH ROW EXECUTE FUNCTION payouts_guard();

CREATE FUNCTION payouts_after_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'paid' AND OLD.status <> 'paid' THEN
        INSERT INTO wallet_transactions (driver_id, entry_type, amount, payout_request_id, created_by)
        VALUES (NEW.driver_id, 'payout', -NEW.amount, NEW.id, NEW.processed_by);
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_payouts_after_change AFTER UPDATE OF status ON payout_requests
    FOR EACH ROW EXECUTE FUNCTION payouts_after_change();

CREATE FUNCTION topups_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    st platform_settings%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO st FROM platform_settings;
        IF NEW.status <> 'awaiting_verification' OR NEW.verified_by IS NOT NULL OR NEW.verified_at IS NOT NULL THEN
            RAISE EXCEPTION 'a top-up starts as awaiting_verification';
        END IF;
        IF NEW.amount NOT BETWEEN st.min_topup_amount AND st.max_topup_amount THEN
            RAISE EXCEPTION 'top-up must be between % and %', st.min_topup_amount, st.max_topup_amount;
        END IF;
        RETURN NEW;
    END IF;
    IF OLD.status <> 'awaiting_verification' THEN
        RAISE EXCEPTION 'top-up % is already %', OLD.id, OLD.status;
    END IF;
    IF (NEW.customer_id, NEW.amount, NEW.proof_storage_key) IS DISTINCT FROM (OLD.customer_id, OLD.amount, OLD.proof_storage_key) THEN
        RAISE EXCEPTION 'top-up % details cannot change', OLD.id;
    END IF;
    IF NEW.status = 'verified' THEN
        PERFORM assert_transfer_unused(NEW.transfer_reference, 'customer_topups');
    END IF;
    IF NEW.status <> 'awaiting_verification' THEN
        NEW.verified_at := now();
        NEW.verified_by := COALESCE(NEW.verified_by, app_actor_id());
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_topups_guard BEFORE INSERT OR UPDATE ON customer_topups
    FOR EACH ROW EXECUTE FUNCTION topups_guard();

CREATE FUNCTION topups_after_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'verified' AND OLD.status <> 'verified' THEN
        INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, topup_id, created_by)
        VALUES (NEW.customer_id, 'top_up', NEW.amount, NEW.id, NEW.verified_by);
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_topups_after_change AFTER UPDATE OF status ON customer_topups
    FOR EACH ROW EXECUTE FUNCTION topups_after_change();

CREATE FUNCTION withdrawals_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'requested' THEN
            RAISE EXCEPTION 'a withdrawal starts as requested';
        END IF;
        PERFORM 1 FROM users WHERE id = NEW.customer_id FOR UPDATE;
        IF NEW.amount > customer_available_balance(NEW.customer_id) THEN
            RAISE EXCEPTION 'insufficient wallet balance: % available, requested %',
                customer_available_balance(NEW.customer_id), NEW.amount;
        END IF;
        RETURN NEW;
    END IF;
    IF OLD.status <> 'requested' THEN
        RAISE EXCEPTION 'withdrawal % is already %', OLD.id, OLD.status;
    END IF;
    IF (NEW.customer_id, NEW.payout_account_id, NEW.amount) IS DISTINCT FROM (OLD.customer_id, OLD.payout_account_id, OLD.amount) THEN
        RAISE EXCEPTION 'withdrawal % details cannot change', OLD.id;
    END IF;
    IF NEW.status = 'paid' AND NOT EXISTS (SELECT 1 FROM payout_accounts WHERE id = NEW.payout_account_id
                                           AND review_status = 'approved' AND superseded_at IS NULL) THEN
        RAISE EXCEPTION 'payout account % is not the current approved account', NEW.payout_account_id;
    END IF;
    IF NEW.status <> 'requested' THEN
        NEW.processed_at := now();
        NEW.processed_by := COALESCE(NEW.processed_by, app_actor_id());
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_withdrawals_guard BEFORE INSERT OR UPDATE ON customer_withdrawals
    FOR EACH ROW EXECUTE FUNCTION withdrawals_guard();

CREATE FUNCTION withdrawals_after_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'paid' AND OLD.status <> 'paid' THEN
        INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, withdrawal_id, created_by)
        VALUES (NEW.customer_id, 'withdrawal', -NEW.amount, NEW.id, NEW.processed_by);
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_withdrawals_after_change AFTER UPDATE OF status ON customer_withdrawals
    FOR EACH ROW EXECUTE FUNCTION withdrawals_after_change();

CREATE FUNCTION trip_party(p_trip BIGINT, p_user BIGINT) RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN s.customer_id = p_user THEN 'customer' WHEN t.driver_id = p_user THEN 'driver' END
    FROM trips t JOIN shipments s ON s.id = t.shipment_id WHERE t.id = p_trip
$$;

CREATE FUNCTION disputes_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    paid       NUMERIC;
    opener     TEXT;
BEGIN
    opener := trip_party(NEW.trip_id, NEW.opened_by);
    paid := COALESCE((SELECT amount FROM payments WHERE shipment_id = NEW.shipment_id
                      AND (method = 'wallet' OR collected_on_trip_id = NEW.trip_id)), 0);

    IF NEW.assigned_to IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.assigned_to IS DISTINCT FROM OLD.assigned_to)
       AND NOT has_role(NEW.assigned_to, 'admin') THEN
        RAISE EXCEPTION 'dispute owner % must be an admin', NEW.assigned_to;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF opener IS NULL THEN
            RAISE EXCEPTION 'user % is not a party of trip %', NEW.opened_by, NEW.trip_id;
        END IF;
        IF NEW.status <> 'open' OR NEW.resolution IS NOT NULL OR NEW.respondent_statement IS NOT NULL THEN
            RAISE EXCEPTION 'a new dispute starts as open, without a response or resolution';
        END IF;
        IF NEW.requested_amount > paid THEN
            RAISE EXCEPTION 'requested amount % is more than the paid %', NEW.requested_amount, paid;
        END IF;
        NEW.response_due_at := now() + make_interval(hours => (SELECT dispute_response_hours FROM platform_settings));
        NEW.created_at := now();
        RETURN NEW;
    END IF;

    IF OLD.status IN ('resolved', 'rejected') THEN
        RAISE EXCEPTION 'dispute % is % and final', OLD.id, OLD.status;
    END IF;
    IF (NEW.trip_id, NEW.shipment_id, NEW.opened_by, NEW.reason, NEW.description, NEW.requested_resolution,
        NEW.requested_amount, NEW.response_due_at, NEW.created_at)
       IS DISTINCT FROM
       (OLD.trip_id, OLD.shipment_id, OLD.opened_by, OLD.reason, OLD.description, OLD.requested_resolution,
        OLD.requested_amount, OLD.response_due_at, OLD.created_at) THEN
        RAISE EXCEPTION 'dispute % complaint details cannot change', OLD.id;
    END IF;

    IF NEW.respondent_statement IS DISTINCT FROM OLD.respondent_statement THEN
        IF OLD.respondent_statement IS NOT NULL THEN
            RAISE EXCEPTION 'dispute % already has a response', OLD.id;
        END IF;
        IF trip_party(OLD.trip_id, app_actor_id()) IS NULL OR trip_party(OLD.trip_id, app_actor_id()) = opener THEN
            RAISE EXCEPTION 'only the other party of the trip can respond to dispute %', OLD.id;
        END IF;
        NEW.responded_at := now();
    ELSIF NEW.responded_at IS DISTINCT FROM OLD.responded_at THEN
        RAISE EXCEPTION 'responded_at is set with the response';
    END IF;

    IF NEW.status <> OLD.status THEN
        IF NOT (OLD.status || '>' || NEW.status = ANY (ARRAY[
                'open>awaiting_response', 'open>under_review', 'open>resolved', 'open>rejected',
                'awaiting_response>under_review', 'awaiting_response>resolved', 'awaiting_response>rejected',
                'under_review>awaiting_response', 'under_review>resolved', 'under_review>rejected'])) THEN
            RAISE EXCEPTION 'dispute % cannot go from % to %', OLD.id, OLD.status, NEW.status;
        END IF;
        IF NEW.status IN ('resolved', 'rejected') THEN
            NEW.resolved_at := now();
            NEW.resolved_by := COALESCE(NEW.resolved_by, app_actor_id());
        END IF;
    END IF;

    IF NEW.status = 'resolved' THEN
        IF opener = 'driver' AND NEW.resolution <> 'no_financial_action' THEN
            RAISE EXCEPTION 'a driver''s dispute is resolved without money (no_financial_action)';
        END IF;
        IF COALESCE(NEW.customer_amount, 0) > paid THEN
            RAISE EXCEPTION 'customer amount % is more than the paid %', NEW.customer_amount, paid;
        END IF;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_disputes_guard BEFORE INSERT OR UPDATE ON disputes
    FOR EACH ROW EXECUTE FUNCTION disputes_guard();

CREATE FUNCTION disputes_log_events() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO dispute_events (dispute_id, event_type, to_status, actor_id)
        VALUES (NEW.id, 'opened', NEW.status, NEW.opened_by);
        RETURN NULL;
    END IF;
    IF NEW.respondent_statement IS NOT NULL AND OLD.respondent_statement IS NULL THEN
        INSERT INTO dispute_events (dispute_id, event_type, actor_id) VALUES (NEW.id, 'response_added', app_actor_id());
    END IF;
    IF NEW.status <> OLD.status THEN
        INSERT INTO dispute_events (dispute_id, event_type, from_status, to_status, actor_id, note)
        VALUES (NEW.id, CASE WHEN NEW.status IN ('resolved', 'rejected') THEN 'resolved' ELSE 'status_changed' END,
                OLD.status, NEW.status, app_actor_id(), NEW.resolution);
    END IF;
    RETURN NULL;
END$$;
CREATE TRIGGER trg_disputes_log_events AFTER INSERT OR UPDATE ON disputes
    FOR EACH ROW EXECUTE FUNCTION disputes_log_events();

CREATE FUNCTION dispute_events_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.event_type NOT IN ('evidence_requested', 'note_to_parties') AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION '% events are recorded automatically', NEW.event_type;
    END IF;
    NEW.actor_id := COALESCE(NEW.actor_id, app_actor_id());
    RETURN NEW;
END$$;
CREATE TRIGGER trg_dispute_events_guard BEFORE INSERT ON dispute_events
    FOR EACH ROW EXECUTE FUNCTION dispute_events_guard();

CREATE FUNCTION dispute_evidence_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    d disputes%ROWTYPE;
BEGIN
    SELECT * INTO d FROM disputes WHERE id = NEW.dispute_id;
    IF d.status IN ('resolved', 'rejected') THEN
        RAISE EXCEPTION 'dispute % is closed', d.id;
    END IF;
    IF trip_party(d.trip_id, NEW.uploaded_by) IS NULL AND NOT has_role(NEW.uploaded_by, 'admin') THEN
        RAISE EXCEPTION 'user % is not a party of dispute %', NEW.uploaded_by, d.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_dispute_evidence_guard BEFORE INSERT ON dispute_evidence
    FOR EACH ROW EXECUTE FUNCTION dispute_evidence_guard();

CREATE FUNCTION dispute_evidence_log() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dispute_events (dispute_id, event_type, actor_id) VALUES (NEW.dispute_id, 'evidence_added', NEW.uploaded_by);
    RETURN NULL;
END$$;
CREATE TRIGGER trg_dispute_evidence_log AFTER INSERT ON dispute_evidence
    FOR EACH ROW EXECUTE FUNCTION dispute_evidence_log();

CREATE FUNCTION conversations_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.group_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM trips WHERE group_id = NEW.group_id AND driver_id = NEW.driver_id) THEN
        RAISE EXCEPTION 'driver % has no trip in group %', NEW.driver_id, NEW.group_id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_conversations_guard BEFORE INSERT ON conversations
    FOR EACH ROW EXECUTE FUNCTION conversations_guard();

CREATE FUNCTION messages_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    c        conversations%ROWTYPE;
    allowed  BOOLEAN;
BEGIN
    SELECT * INTO c FROM conversations WHERE id = NEW.conversation_id;
    IF c.closed_at IS NOT NULL THEN
        RAISE EXCEPTION 'conversation % is closed', c.id;
    END IF;
    IF c.trip_id IS NOT NULL THEN
        allowed := trip_party(c.trip_id, NEW.sender_id) IS NOT NULL;
    ELSE
        allowed := NEW.sender_id = c.driver_id
                   OR NEW.sender_id = (SELECT customer_id FROM shipment_groups WHERE id = c.group_id);
    END IF;
    IF NOT allowed THEN
        RAISE EXCEPTION 'user % is not part of conversation %', NEW.sender_id, c.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_messages_guard BEFORE INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION messages_guard();

CREATE FUNCTION messages_update_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (to_jsonb(NEW) - 'read_at') IS DISTINCT FROM (to_jsonb(OLD) - 'read_at')
       OR (OLD.read_at IS NOT NULL AND NEW.read_at IS DISTINCT FROM OLD.read_at) THEN
        RAISE EXCEPTION 'message % cannot be edited (only marked as read once)', OLD.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_messages_update_guard BEFORE UPDATE ON messages
    FOR EACH ROW EXECUTE FUNCTION messages_update_guard();

CREATE FUNCTION reviews_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    rv  TEXT := trip_party(NEW.trip_id, NEW.reviewer_id);
    re  TEXT := trip_party(NEW.trip_id, NEW.reviewee_id);
BEGIN
    IF (SELECT status FROM trips WHERE id = NEW.trip_id) <> 'delivered' THEN
        RAISE EXCEPTION 'trip % is not delivered yet', NEW.trip_id;
    END IF;
    IF NOT COALESCE((rv = 'customer' AND re = 'driver') OR (rv = 'driver' AND re = 'customer'), false) THEN
        RAISE EXCEPTION 'a review is between the customer and the driver of trip %', NEW.trip_id;
    END IF;
    IF rv = 'driver' AND (NEW.vehicle_rating IS NOT NULL OR NEW.service_rating IS NOT NULL) THEN
        RAISE EXCEPTION 'vehicle and service ratings are given by the customer only';
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_reviews_guard BEFORE INSERT ON reviews
    FOR EACH ROW EXECUTE FUNCTION reviews_guard();

CREATE FUNCTION review_tags_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    r    reviews%ROWTYPE;
    dir  TEXT;
BEGIN
    SELECT * INTO r FROM reviews WHERE id = NEW.review_id;
    dir := CASE trip_party(r.trip_id, r.reviewer_id) WHEN 'customer' THEN 'customer_to_driver' ELSE 'driver_to_customer' END;
    IF NOT EXISTS (SELECT 1 FROM review_tags WHERE id = NEW.tag_id AND direction = dir AND is_active) THEN
        RAISE EXCEPTION 'tag % is not an active % tag', NEW.tag_id, dir;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_review_tags_guard BEFORE INSERT ON review_tag_selections
    FOR EACH ROW EXECUTE FUNCTION review_tags_guard();

CREATE FUNCTION support_tickets_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.assigned_to IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.assigned_to IS DISTINCT FROM OLD.assigned_to)
       AND NOT has_role(NEW.assigned_to, 'admin') THEN
        RAISE EXCEPTION 'ticket owner % must be an admin', NEW.assigned_to;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NOT has_role(NEW.user_id, NEW.user_role) THEN
            RAISE EXCEPTION 'user % is not a %', NEW.user_id, NEW.user_role;
        END IF;
        IF NEW.opened_by IS NULL THEN
            IF app_actor_role() <> 'system' THEN
                RAISE EXCEPTION 'opened_by is required (empty means the system)';
            END IF;
        ELSIF NEW.opened_by <> NEW.user_id AND NOT has_role(NEW.opened_by, 'admin') THEN
            RAISE EXCEPTION 'a ticket is opened by its owner, an admin or the system';
        END IF;
        IF NEW.trip_id IS NOT NULL AND trip_party(NEW.trip_id, NEW.user_id) IS NULL THEN
            RAISE EXCEPTION 'user % is not a party of trip %', NEW.user_id, NEW.trip_id;
        END IF;
        IF NEW.shipment_id IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM shipments s WHERE s.id = NEW.shipment_id AND (s.customer_id = NEW.user_id
                   OR EXISTS (SELECT 1 FROM trips t WHERE t.shipment_id = s.id AND t.driver_id = NEW.user_id))) THEN
            RAISE EXCEPTION 'user % is not a party of shipment %', NEW.user_id, NEW.shipment_id;
        END IF;
        IF NEW.dispute_id IS NOT NULL AND trip_party((SELECT trip_id FROM disputes WHERE id = NEW.dispute_id), NEW.user_id) IS NULL THEN
            RAISE EXCEPTION 'user % is not a party of dispute %', NEW.user_id, NEW.dispute_id;
        END IF;
        IF NEW.status <> 'open' THEN
            RAISE EXCEPTION 'a new ticket starts as open';
        END IF;
        NEW.resolved_by := NULL;
        RETURN NEW;
    END IF;
    IF OLD.status = 'closed' THEN
        RAISE EXCEPTION 'ticket % is closed', OLD.id;
    END IF;
    IF (NEW.user_id, NEW.user_role, NEW.opened_by, NEW.created_at) IS DISTINCT FROM
       (OLD.user_id, OLD.user_role, OLD.opened_by, OLD.created_at) THEN
        RAISE EXCEPTION 'ticket % owner cannot change', OLD.id;
    END IF;
    IF NEW.status IN ('resolved', 'closed') AND OLD.status NOT IN ('resolved', 'closed') THEN
        NEW.resolved_at := now();
    END IF;
    IF (NEW.cargo_outcome, NEW.resolution_note) IS DISTINCT FROM (OLD.cargo_outcome, OLD.resolution_note)
       OR NEW.resolved_by IS DISTINCT FROM OLD.resolved_by THEN
        IF NEW.cargo_outcome IS NOT NULL OR OLD.cargo_outcome IS NOT NULL THEN
            IF app_actor_role() <> 'admin' OR NOT has_role(app_actor_id(), 'admin') THEN
                RAISE EXCEPTION 'only an admin records where the cargo went (ticket %)', OLD.id;
            END IF;
        END IF;
        NEW.resolved_by := CASE WHEN app_actor_role() = 'admin' THEN app_actor_id() ELSE OLD.resolved_by END;
    END IF;
    IF EXISTS (SELECT 1 FROM trips WHERE cancellation_ticket_id = OLD.id) AND (
           (NEW.trip_id, NEW.shipment_id, NEW.cargo_outcome, NEW.resolution_note, NEW.resolved_by)
           IS DISTINCT FROM (OLD.trip_id, OLD.shipment_id, OLD.cargo_outcome, OLD.resolution_note, OLD.resolved_by)
           OR NEW.status NOT IN ('resolved', 'closed')) THEN
        RAISE EXCEPTION 'ticket % is the evidence of a cancelled loaded trip: it cannot change', OLD.id;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_support_tickets_guard BEFORE INSERT OR UPDATE ON support_tickets
    FOR EACH ROW EXECUTE FUNCTION support_tickets_guard();

CREATE FUNCTION support_messages_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    tk support_tickets%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (to_jsonb(NEW) - 'read_at') IS DISTINCT FROM (to_jsonb(OLD) - 'read_at') THEN
            RAISE EXCEPTION 'support message % cannot be edited', OLD.id;
        END IF;
        RETURN NEW;
    END IF;
    SELECT * INTO tk FROM support_tickets WHERE id = NEW.ticket_id;
    IF tk.status = 'closed' THEN
        RAISE EXCEPTION 'ticket % is closed', tk.id;
    END IF;
    IF NEW.sender_id <> tk.user_id AND NOT has_role(NEW.sender_id, 'admin') THEN
        RAISE EXCEPTION 'user % cannot write in ticket %', NEW.sender_id, tk.id;
    END IF;
    IF NEW.is_internal AND NOT has_role(NEW.sender_id, 'admin') THEN
        RAISE EXCEPTION 'internal notes are for admins only';
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_support_messages_guard BEFORE INSERT OR UPDATE ON support_messages
    FOR EACH ROW EXECUTE FUNCTION support_messages_guard();

CREATE FUNCTION audit_row_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    old_j    JSONB := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
    new_j    JSONB := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
    ignored  TEXT[] := TG_ARGV[1:];
    b        JSONB := '{}';
    a        JSONB := '{}';
    k        TEXT;
BEGIN
    IF TG_ARGV[0] = 'admin_only' AND app_actor_role() <> 'admin' THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        FOR k IN SELECT jsonb_object_keys(new_j) LOOP
            IF k <> ALL (ignored) AND (new_j -> k) IS DISTINCT FROM (old_j -> k) THEN
                b := b || jsonb_build_object(k, old_j -> k);
                a := a || jsonb_build_object(k, new_j -> k);
            END IF;
        END LOOP;
        IF a = '{}' THEN
            RETURN NULL;
        END IF;
    ELSE
        b := old_j;
        a := new_j;
    END IF;
    INSERT INTO admin_audit_log (actor_id, actor_role, action, table_name, row_id, before, after, reason)
    VALUES (app_actor_id(), app_actor_role(), lower(TG_OP), TG_TABLE_NAME,
            COALESCE(COALESCE(new_j, old_j) ->> 'id', COALESCE(new_j, old_j) ->> 'user_id'),
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE b END,
            CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE a END,
            app_change_reason());
    RETURN NULL;
END$$;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['platform_settings', 'vehicle_types', 'cities', 'service_zones', 'coupons',
                             'policy_versions', 'cargo_categories', 'cargo_size_options', 'review_tags']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%s_audit AFTER INSERT OR UPDATE ON %I
                        FOR EACH ROW EXECUTE FUNCTION audit_row_change(''all'')', t, t);
    END LOOP;
END$$;
CREATE TRIGGER trg_users_audit AFTER UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('admin_only', 'password_hash');
CREATE TRIGGER trg_driver_profiles_audit AFTER UPDATE ON driver_profiles
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('admin_only', 'current_location', 'location_updated_at', 'is_online');
CREATE TRIGGER trg_payout_accounts_audit AFTER UPDATE ON payout_accounts
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('admin_only');

CREATE FUNCTION trip_photos_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    tr trips%ROWTYPE;
BEGIN
    SELECT * INTO tr FROM trips WHERE id = NEW.trip_id;
    IF (NEW.stage = 'pickup' AND tr.status <> 'arrived_at_pickup')
       OR (NEW.stage = 'delivery' AND tr.status <> 'arrived_at_dropoff') THEN
        RAISE EXCEPTION 'trip % is %: % photos are taken at the % point', tr.id, tr.status, NEW.stage, NEW.stage;
    END IF;
    IF NEW.uploaded_by IS DISTINCT FROM tr.driver_id THEN
        RAISE EXCEPTION 'only the driver of trip % uploads its photos', tr.id;
    END IF;
    NEW.uploaded_at := now();
    RETURN NEW;
END$$;
CREATE TRIGGER trg_trip_photos_guard BEFORE INSERT ON trip_photos
    FOR EACH ROW EXECUTE FUNCTION trip_photos_guard();

CREATE FUNCTION trip_location_points_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM trips WHERE id = NEW.trip_id AND status IN (
                       'heading_to_pickup', 'arrived_at_pickup', 'loaded', 'heading_to_dropoff', 'arrived_at_dropoff')) THEN
        RAISE EXCEPTION 'trip % is not moving: no tracking points', NEW.trip_id;
    END IF;
    NEW.received_at := now();
    RETURN NEW;
END$$;
CREATE TRIGGER trg_trip_location_points_guard BEFORE INSERT ON trip_location_points
    FOR EACH ROW EXECUTE FUNCTION trip_location_points_guard();

CREATE FUNCTION written_by_database_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION '% is written automatically by the database', TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_shipment_status_history_auto BEFORE INSERT ON shipment_status_history
    FOR EACH ROW EXECUTE FUNCTION written_by_database_only();
CREATE TRIGGER trg_trip_status_history_auto BEFORE INSERT ON trip_status_history
    FOR EACH ROW EXECUTE FUNCTION written_by_database_only();
CREATE TRIGGER trg_admin_audit_log_auto BEFORE INSERT ON admin_audit_log
    FOR EACH ROW EXECUTE FUNCTION written_by_database_only();

CREATE FUNCTION forbid_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        RAISE EXCEPTION 'TRUNCATE is not allowed on %: it would wipe records of every user at once', TG_TABLE_NAME;
    END IF;
    RAISE EXCEPTION '% is a permanent record: DELETE is not allowed (change its status instead)', TG_TABLE_NAME;
END$$;

CREATE FUNCTION forbid_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only: add a correcting record instead of editing', TG_TABLE_NAME;
END$$;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'users', 'roles', 'policy_versions', 'policy_acceptances',
        'cities', 'service_zones', 'vehicle_types', 'cargo_categories', 'cargo_size_options', 'review_tags',
        'driver_profiles', 'vehicles', 'driver_documents', 'vehicle_documents', 'payout_accounts', 'driver_online_sessions',
        'shipment_groups', 'shipments', 'cargo_analysis_runs', 'coupons', 'price_quotes', 'coupon_redemptions',
        'trips', 'dispatch_offers', 'trip_photos', 'shipment_status_history', 'trip_status_history',
        'trip_location_points', 'delivery_code_attempts', 'return_match_proposals', 'trip_share_links',
        'payments', 'driver_settlements', 'payout_requests', 'disputes', 'dispute_evidence', 'dispute_events',
        'refunds', 'wallet_transactions', 'customer_topups', 'customer_withdrawals', 'customer_wallet_transactions',
        'conversations', 'messages', 'reviews', 'review_tag_selections', 'support_tickets', 'support_messages',
        'admin_audit_log', 'shipment_imports', 'shipment_import_rows']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%s_no_delete BEFORE DELETE ON %I
                        FOR EACH ROW EXECUTE FUNCTION forbid_delete()', t, t);
        EXECUTE format('CREATE TRIGGER trg_%s_no_truncate BEFORE TRUNCATE ON %I
                        FOR EACH STATEMENT EXECUTE FUNCTION forbid_delete()', t, t);
    END LOOP;

    FOREACH t IN ARRAY ARRAY['shipment_items', 'shipment_item_images', 'user_roles', 'saved_places']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%s_no_truncate BEFORE TRUNCATE ON %I
                        FOR EACH STATEMENT EXECUTE FUNCTION forbid_delete()', t, t);
    END LOOP;

    FOREACH t IN ARRAY ARRAY[
        'wallet_transactions', 'customer_wallet_transactions', 'payments', 'refunds',
        'policy_acceptances', 'admin_audit_log', 'dispute_events', 'dispute_evidence',
        'delivery_code_attempts', 'shipment_status_history', 'trip_status_history', 'review_tag_selections',
        'reviews', 'trip_photos', 'trip_location_points']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%s_append_only BEFORE UPDATE ON %I
                        FOR EACH ROW EXECUTE FUNCTION forbid_update()', t, t);
    END LOOP;
END$$;

CREATE TABLE incoming_transfer_claims (
    transfer_reference TEXT PRIMARY KEY CHECK (transfer_reference = lower(btrim(transfer_reference)) AND transfer_reference <> ''),
    topup_id BIGINT UNIQUE REFERENCES customer_topups(id),
    settlement_id BIGINT UNIQUE REFERENCES driver_settlements(id),
    claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_transfer_claim_target CHECK (num_nonnulls(topup_id, settlement_id) = 1)
);
CREATE TRIGGER trg_claim_internal BEFORE INSERT ON incoming_transfer_claims FOR EACH ROW EXECUTE FUNCTION written_by_database_only();
CREATE TRIGGER trg_claim_fixed BEFORE UPDATE ON incoming_transfer_claims FOR EACH ROW EXECUTE FUNCTION forbid_update();
CREATE TRIGGER trg_claim_no_delete BEFORE DELETE ON incoming_transfer_claims FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_claim_no_truncate BEFORE TRUNCATE ON incoming_transfer_claims FOR EACH STATEMENT EXECUTE FUNCTION forbid_delete();

CREATE FUNCTION unified_claim_transfer() RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF NEW.status = 'verified' AND OLD.status <> 'verified' THEN
        IF TG_TABLE_NAME = 'customer_topups' THEN
            INSERT INTO incoming_transfer_claims (transfer_reference, topup_id)
            VALUES (lower(btrim(NEW.transfer_reference)), NEW.id);
        ELSE
            INSERT INTO incoming_transfer_claims (transfer_reference, settlement_id)
            VALUES (lower(btrim(NEW.transfer_reference)), NEW.id);
        END IF;
    END IF;
    RETURN NULL;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'transfer % was already confirmed for another payment', NEW.transfer_reference;
END$$;
CREATE TRIGGER trg_00_claim_transfer AFTER UPDATE OF status ON customer_topups FOR EACH ROW EXECUTE FUNCTION unified_claim_transfer();
CREATE TRIGGER trg_00_claim_transfer AFTER UPDATE OF status ON driver_settlements FOR EACH ROW EXECUTE FUNCTION unified_claim_transfer();

CREATE FUNCTION unified_start_eligibility(p_driver BIGINT, p_vehicle BIGINT, p_shipment BIGINT, p_quote BIGINT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    dp driver_profiles%ROWTYPE;
    v vehicles%ROWTYPE;
    sh shipments%ROWTYPE;
    lic driver_documents%ROWTYPE;
    known_weight NUMERIC;
BEGIN
    SELECT * INTO dp FROM driver_profiles WHERE user_id = p_driver FOR UPDATE;
    SELECT * INTO v FROM vehicles WHERE id = p_vehicle FOR SHARE;
    SELECT * INTO sh FROM shipments WHERE id = p_shipment;
    IF dp.verification_status IS DISTINCT FROM 'approved'
       OR NOT EXISTS (SELECT 1 FROM users WHERE id = p_driver AND account_status = 'active') THEN
        RAISE EXCEPTION 'U_DRIVER_INELIGIBLE: driver must be approved and active';
    END IF;
    IF v.status IS DISTINCT FROM 'active' OR v.driver_id IS DISTINCT FROM p_driver THEN
        RAISE EXCEPTION 'U_VEHICLE_INACTIVE: vehicle must be active and owned by the driver';
    END IF;
    IF dp.active_vehicle_id IS DISTINCT FROM p_vehicle THEN
        RAISE EXCEPTION 'U_ACTIVE_VEHICLE: trip must use the selected active vehicle';
    END IF;
    IF v.vehicle_type_id IS DISTINCT FROM (SELECT vehicle_type_id FROM price_quotes WHERE id = p_quote) THEN
        RAISE EXCEPTION 'U_VEHICLE_TYPE: vehicle must match the accepted quote';
    END IF;
    IF NOT accepted_latest_policies(p_driver) THEN
        RAISE EXCEPTION 'U_POLICIES: driver must accept latest terms';
    END IF;
    lic := driver_current_license(p_driver);
    IF lic.id IS NULL OR lic.expires_on <= current_date OR NOT license_fits_vehicle(p_driver,p_vehicle) THEN
        RAISE EXCEPTION 'U_LICENSE: driving license is missing, expired or unsuitable';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM vehicle_documents WHERE vehicle_id = p_vehicle
        AND document_type = 'vehicle_license_front' AND review_status = 'approved'
        AND superseded_at IS NULL AND expires_on > current_date) THEN
        RAISE EXCEPTION 'U_VEHICLE_LICENSE: current valid vehicle license required';
    END IF;
    IF dp.max_helpers < sh.helpers_count THEN RAISE EXCEPTION 'U_HELPERS: insufficient helpers'; END IF;
    IF driver_balance(p_driver) < -driver_debt_limit(p_driver) THEN
        RAISE EXCEPTION 'U_DEBT: driver debt exceeds the limit';
    END IF;
    IF sh.group_id IS NULL THEN
        known_weight := sh.weight_kg;
    ELSE
        SELECT sum(weight_kg) INTO known_weight FROM shipments
        WHERE group_id = sh.group_id AND status NOT IN ('delivered','cancelled');
    END IF;
    IF known_weight > v.max_payload_kg THEN
        RAISE EXCEPTION 'U_PAYLOAD: known cargo weight exceeds vehicle payload';
    END IF;
END$$;

CREATE FUNCTION unified_group_trip_lock() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.group_id IS NOT NULL THEN
        PERFORM 1 FROM shipment_groups WHERE id=NEW.group_id FOR UPDATE;
    END IF;
    RETURN NEW;
END$$;
CREATE TRIGGER trg_00_unified_group_trip_lock BEFORE UPDATE OF status ON trips
FOR EACH ROW EXECUTE FUNCTION unified_group_trip_lock();

INSERT INTO roles (code, name) VALUES
    ('customer', 'عميل'),
    ('driver',   'سائق'),
    ('admin',    'مسؤول النظام');

INSERT INTO platform_settings (
    commission_rate, default_debt_limit, driver_offer_timeout_seconds, dispatch_radius_m, cancellation_fee,
    group_discount_pct, max_group_stops, min_schedule_lead_minutes, driver_search_timeout_minutes, scheduled_search_lead_minutes,
    company_instapay_handle, company_bank_name, company_bank_account, min_topup_amount, max_topup_amount,
    min_driver_age, driver_payout_weekday, max_delivery_code_attempts,
    location_stale_seconds, auto_offline_after_seconds, max_dynamic_multiplier,
    backhaul_discount_amount, backhaul_min_discount_pct, ai_low_confidence_threshold, dispute_response_hours)
VALUES (
    0.1500, 1000.00, 30, 10000, 50.00,
    0.0500, 5, 30, 30, 60,
    'wasla@instapay', NULL, NULL, 50.00, 10000.00,
    21, 0, 5,
    120, 900, 1.25,
    120.00, 0.1000, 0.600, 24);

INSERT INTO cities (code, name_ar, name_en) VALUES ('cairo', 'القاهرة', 'Cairo');

INSERT INTO vehicle_types (code, name_ar, name_en, max_payload_kg, cargo_volume_m3,
                           bed_length_m, bed_width_m, bed_height_m, suitable_for_ar, suitable_for_en,
                           base_fare, per_km_rate, helper_fee, min_license_category) VALUES
    ('small_pickup',  'بيك أب صغير', 'Small Pickup',  1000,  4,  1.8, 1.4, 1.2, 'أجهزة وكراتين', 'Appliances and boxes',     180.00, 12.00, 120.00, 'private'),
    ('quarter_truck', 'ربع نقل',     'Quarter Truck', 1500,  6,  2.5, 1.6, 1.5, 'أوضة أو شقة صغيرة', 'A room or a small flat', 300.00, 15.00, 150.00, 'professional_3'),
    ('jumbo',         'جامبو',       'Jumbo',         4000,  18, 4.2, 2.0, 2.0, 'شقة كاملة', 'A full apartment',                500.00, 25.00, 220.00, 'professional_2'),
    ('heavy_truck',   'نقل تقيل',    'Heavy Truck',   10000, 40, 6.5, 2.4, 2.4, 'بضاعة ومعدات', 'Goods and equipment',         900.00, 50.00, 300.00, 'professional_1');

INSERT INTO cargo_categories (code, name_ar, name_en, sort_order) VALUES
    ('furniture',  'أثاث',          'Furniture',  1),
    ('appliances', 'أجهزة',         'Appliances', 2),
    ('goods',      'بضاعة',         'Goods',      3),
    ('machinery',  'مكن ومعدات',    'Machinery',  4),
    ('other',      'أخرى',          'Other',      9);

INSERT INTO cargo_size_options (cargo_category_id, code, name_ar, name_en, approx_volume_m3, sort_order)
SELECT c.id, v.code, v.name_ar, v.name_en, v.vol, v.ord
FROM cargo_categories c
JOIN (VALUES
    ('furniture', 'few_items',  'قطع قليلة',     'A few items',      2,  1),
    ('furniture', 'one_room',   'أوضة',          'One room',         6,  2),
    ('furniture', 'small_flat', 'شقة صغيرة',     'Small apartment',  15, 3),
    ('furniture', 'full_flat',  'شقة كاملة',     'Full apartment',   30, 4),
    ('goods',     'boxes',      'كام كرتونة',    'A few boxes',      1,  1),
    ('goods',     'pallet',     'بالتة',         'One pallet',       2,  2),
    ('goods',     'pallets',    'كذا بالتة',     'Several pallets',  8,  3),
    ('goods',     'full_truck', 'عربية كاملة',   'Full truck',       30, 4)
) AS v(cat, code, name_ar, name_en, vol, ord) ON v.cat = c.code;

INSERT INTO review_tags (code, name_ar, name_en, sentiment, direction) VALUES
    ('professional', 'محترف',              'Professional',       'positive', 'customer_to_driver'),
    ('on_time',      'في الميعاد',         'On time',            'positive', 'customer_to_driver'),
    ('careful',      'حريص على الحاجة',    'Careful with items', 'positive', 'customer_to_driver'),
    ('late',         'اتأخر',              'Late',               'negative', 'customer_to_driver'),
    ('paid_on_time', 'دفع في الميعاد',     'Paid on time',       'positive', 'driver_to_customer'),
    ('ready_cargo',  'الحمولة كانت جاهزة', 'Cargo was ready',    'positive', 'driver_to_customer'),
    ('late_loading', 'اتأخر في التحميل',   'Late loading',       'negative', 'driver_to_customer');

COMMIT;

\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='wasla_runtime') THEN
   CREATE ROLE wasla_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
 ELSIF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='wasla_runtime'
             AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls OR rolcanlogin)) THEN
   RAISE EXCEPTION 'Existing wasla_runtime is not the expected restricted NOLOGIN role';
 END IF;
END$$;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO wasla_runtime;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM wasla_runtime;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO wasla_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO wasla_runtime;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO wasla_runtime;
REVOKE INSERT, UPDATE ON incoming_transfer_claims, shipment_status_history,
 trip_status_history, admin_audit_log FROM wasla_runtime;
REVOKE UPDATE ON wallet_transactions, customer_wallet_transactions, payments, refunds,
 policy_acceptances, dispute_events, dispute_evidence, delivery_code_attempts,
 review_tag_selections, trip_photos, trip_location_points, reviews FROM wasla_runtime;
GRANT DELETE ON shipment_items, shipment_item_images, user_roles, saved_places,
 otp_codes, auth_sessions, user_devices, notifications TO wasla_runtime;
COMMIT;

CREATE SCHEMA IF NOT EXISTS t;
CREATE FUNCTION t.loc(lon float8, lat float8) RETURNS geography LANGUAGE sql IMMUTABLE AS
$$ SELECT ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography$$;
CREATE FUNCTION t.box_poly(lon1 float8, lat1 float8, lon2 float8, lat2 float8) RETURNS geography LANGUAGE sql IMMUTABLE AS
$$ SELECT ST_MakeEnvelope(lon1, lat1, lon2, lat2, 4326)::geography$$;

SET client_min_messages = warning;

CREATE TABLE t.results (
    n       SERIAL PRIMARY KEY,
    section TEXT,
    name    TEXT NOT NULL,
    ok      BOOLEAN NOT NULL,
    detail  TEXT
);
CREATE TABLE t.ctx (k TEXT PRIMARY KEY, v BIGINT);
CREATE TABLE t.cur (section TEXT);
INSERT INTO t.cur VALUES ('setup');

CREATE FUNCTION t.section(p TEXT) RETURNS void LANGUAGE sql AS $$ UPDATE t.cur SET section = p$$;
CREATE FUNCTION t.set(k TEXT, v BIGINT) RETURNS BIGINT LANGUAGE sql AS $$
    INSERT INTO t.ctx VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v RETURNING v$$;
CREATE FUNCTION t.get(p TEXT) RETURNS BIGINT LANGUAGE sql STABLE AS $$ SELECT v FROM t.ctx WHERE k = p$$;

CREATE FUNCTION t.ok(p_name TEXT, p_sql TEXT) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
        INSERT INTO t.results (section, name, ok) SELECT section, p_name, true FROM t.cur;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO t.results (section, name, ok, detail) SELECT section, p_name, false, SQLERRM FROM t.cur;
    END;
END$$;

CREATE FUNCTION t.err(p_name TEXT, p_sql TEXT, p_pattern TEXT) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
        RAISE EXCEPTION 'T_NO_ERROR';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'T_NO_ERROR' THEN
            INSERT INTO t.results (section, name, ok, detail) SELECT section, p_name, false, 'expected an error, none raised' FROM t.cur;
        ELSIF SQLERRM ~* p_pattern THEN
            INSERT INTO t.results (section, name, ok) SELECT section, p_name, true FROM t.cur;
        ELSE
            INSERT INTO t.results (section, name, ok, detail) SELECT section, p_name, false, 'wrong error: ' || SQLERRM FROM t.cur;
        END IF;
    END;
END$$;

CREATE FUNCTION t.eq(p_name TEXT, p_actual TEXT, p_expected TEXT) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO t.results (section, name, ok, detail)
    SELECT section, p_name, p_actual IS NOT DISTINCT FROM p_expected,
           CASE WHEN p_actual IS DISTINCT FROM p_expected THEN format('got %s, expected %s', p_actual, p_expected) END
    FROM t.cur;
END$$;

CREATE FUNCTION t.act(p_id BIGINT, p_role TEXT) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('app.actor_id', COALESCE(p_id::text, ''), false);
    PERFORM set_config('app.actor_role', COALESCE(p_role, ''), false);
END$$;
CREATE FUNCTION t.sys() RETURNS void LANGUAGE sql AS $$ SELECT t.act(NULL, NULL)$$;

CREATE FUNCTION t.publish_policies() RETURNS void LANGUAGE sql AS $$
    INSERT INTO policy_versions (doc_type, version_number, content_ar, content_en, published_at)
    VALUES ('terms', 1, 'الشروط', 'Terms', now() - interval '1 hour'),
           ('privacy', 1, 'الخصوصية', 'Privacy', now() - interval '1 hour');
$$;

CREATE FUNCTION t.mk_user(p_name TEXT, p_phone TEXT, p_roles TEXT[]) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    uid BIGINT;
    r   TEXT;
BEGIN
    INSERT INTO users (full_name, phone, email, password_hash)
    VALUES (p_name, p_phone, 'u' || ltrim(p_phone, '+') || '@test.wasla', 'bcrypt$hash') RETURNING id INTO uid;
    INSERT INTO policy_acceptances (user_id, policy_version_id)
    SELECT uid, v FROM (SELECT latest_policy_version('terms') v UNION SELECT latest_policy_version('privacy')) x
    WHERE v IS NOT NULL;
    FOREACH r IN ARRAY p_roles LOOP
        INSERT INTO user_roles (user_id, role_id) SELECT uid, id FROM roles WHERE code = r;
    END LOOP;
    RETURN uid;
END$$;

CREATE FUNCTION t.mk_driver(p_name TEXT, p_phone TEXT, p_vtype TEXT DEFAULT 'quarter_truck',
                            p_license license_category DEFAULT 'professional_2', p_helpers INT DEFAULT 2)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    uid  BIGINT;
    vid  BIGINT;
    dt   TEXT;
BEGIN
    uid := t.mk_user(p_name, p_phone, ARRAY['driver']);
    INSERT INTO driver_profiles (user_id, city_id, date_of_birth, national_id_hash, national_id_last4, max_helpers)
    VALUES (uid, (SELECT id FROM cities WHERE code = 'cairo'), DATE '1990-01-01',
            md5(p_phone) || md5(p_name), '1234', p_helpers);
    FOREACH dt IN ARRAY ARRAY['profile_photo', 'national_id_front', 'national_id_back',
                              'driving_license_front', 'driving_license_back'] LOOP
        INSERT INTO driver_documents (driver_id, document_type, storage_key, license_category)
        VALUES (uid, dt, 'doc/' || uid || '/' || dt, CASE WHEN dt = 'driving_license_front' THEN p_license END);
    END LOOP;
    INSERT INTO vehicles (driver_id, vehicle_type_id, plate_number, make, model, manufacture_year, color)
    VALUES (uid, (SELECT id FROM vehicle_types WHERE code = p_vtype), 'P-' || uid, 'Chevrolet', 'N300', 2019, 'White')
    RETURNING id INTO vid;
    FOREACH dt IN ARRAY ARRAY['vehicle_license_front', 'vehicle_license_back', 'vehicle_photo_front',
                              'vehicle_photo_side', 'vehicle_photo_rear', 'vehicle_photo_cargo'] LOOP
        INSERT INTO vehicle_documents (vehicle_id, document_type, storage_key) VALUES (vid, dt, 'veh/' || vid || '/' || dt);
    END LOOP;
    INSERT INTO payout_accounts (user_id, method, holder_name, account_number) VALUES (uid, 'wallet', p_name, '01000000000');
    RETURN uid;
END$$;

CREATE FUNCTION t.vehicle_of(p_driver BIGINT) RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT min(id) FROM vehicles WHERE driver_id = p_driver$$;

CREATE FUNCTION t.approve_driver(p_driver BIGINT, p_admin BIGINT) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    vid BIGINT := t.vehicle_of(p_driver);
BEGIN
    PERFORM t.act(p_driver, 'driver');
    UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = p_driver;
    PERFORM t.act(p_admin, 'admin');
    UPDATE driver_documents SET review_status = 'approved',
           expires_on = CASE WHEN document_type IN ('national_id_front', 'driving_license_front') THEN current_date + 365 END
    WHERE driver_id = p_driver AND superseded_at IS NULL AND review_status = 'pending';
    UPDATE vehicle_documents SET review_status = 'approved',
           expires_on = CASE WHEN document_type = 'vehicle_license_front' THEN current_date + 365 END
    WHERE vehicle_id = vid AND superseded_at IS NULL AND review_status = 'pending';
    UPDATE payout_accounts SET review_status = 'approved' WHERE user_id = p_driver AND superseded_at IS NULL;
    UPDATE driver_profiles SET verification_status = 'approved' WHERE user_id = p_driver;
    UPDATE vehicles SET status = 'active' WHERE id = vid;
    PERFORM t.act(p_driver, 'driver');
    UPDATE driver_profiles SET active_vehicle_id = vid, current_location = t.loc(31.24, 30.05),
           location_updated_at = now(), is_online = true WHERE user_id = p_driver;
    PERFORM t.sys();
END$$;

CREATE FUNCTION t.fund(p_customer BIGINT, p_amount NUMERIC, p_admin BIGINT) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    tid BIGINT;
BEGIN
    INSERT INTO customer_topups (customer_id, amount, proof_storage_key) VALUES (p_customer, p_amount, 'receipt')
    RETURNING id INTO tid;
    PERFORM t.act(p_admin, 'admin');
    UPDATE customer_topups SET status = 'verified', transfer_reference = 'IP-' || tid WHERE id = tid;
    PERFORM t.sys();
END$$;

CREATE FUNCTION t.mk_shipment(p_customer BIGINT, p_method TEXT DEFAULT 'wallet', p_helpers INT DEFAULT 0,
                              p_group BIGINT DEFAULT NULL, p_seq INT DEFAULT NULL, p_payer TEXT DEFAULT 'sender')
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    sid BIGINT;
BEGIN
    INSERT INTO shipments (customer_id, group_id, delivery_sequence, cargo_category_id, cargo_description, item_count,
                           helpers_count, pickup_address, pickup_location, dropoff_address, dropoff_location,
                           pickup_type, pickup_window_start, pickup_window_end, payment_method, fare_paid_by,
                           recipient_name, recipient_phone, delivery_code)
    VALUES (p_customer, p_group, p_seq, (SELECT id FROM cargo_categories WHERE code = 'furniture'), 'Sofa and boxes', 3,
            p_helpers, 'Nasr City', t.loc(31.33, 30.06), 'Maadi', t.loc(31.25, 29.96),
            'now', now(), now() + interval '1 hour', p_method, p_payer,
            CASE WHEN p_payer = 'recipient' THEN 'Recipient' END,
            CASE WHEN p_payer = 'recipient' THEN '+201099999999' END, '1234')
    RETURNING id INTO sid;
    INSERT INTO shipment_item_images (shipment_id, storage_key) VALUES (sid, 'img/' || sid);
    RETURN sid;
END$$;

CREATE FUNCTION t.mk_quote(p_shipment BIGINT, p_transport NUMERIC DEFAULT 500, p_coupon BIGINT DEFAULT NULL,
                           p_source TEXT DEFAULT 'rules', p_standard NUMERIC DEFAULT NULL,
                           p_return_discount NUMERIC DEFAULT 0, p_group_discount NUMERIC DEFAULT 0,
                           p_helpers_amount NUMERIC DEFAULT NULL, p_vtype TEXT DEFAULT 'quarter_truck')
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    sh   shipments%ROWTYPE;
    vt   vehicle_types%ROWTYPE;
    h    NUMERIC;
    amt  NUMERIC;
    disc NUMERIC := 0;
    qid  BIGINT;
BEGIN
    SELECT * INTO sh FROM shipments WHERE id = p_shipment;
    SELECT * INTO vt FROM vehicle_types WHERE code = p_vtype;
    h := COALESCE(p_helpers_amount, sh.helpers_count * vt.helper_fee);
    amt := p_transport + h - p_return_discount - p_group_discount;
    IF p_coupon IS NOT NULL THEN disc := coupon_discount(p_coupon, amt); END IF;
    INSERT INTO price_quotes (shipment_id, vehicle_type_id, pricing_details, pricing_source, standard_amount,
                              transport_amount, helpers_amount, return_discount_amount, group_discount_amount, amount,
                              coupon_id, coupon_discount_amount, customer_amount, commission_rate, shipment_version, expires_at)
    VALUES (p_shipment, vt.id, '{}', p_source, COALESCE(p_standard, p_transport), p_transport, h,
            p_return_discount, p_group_discount, amt, p_coupon, disc, amt - disc, 0, sh.details_version, now() + interval '1 hour')
    RETURNING id INTO qid;
    RETURN qid;
END$$;

CREATE FUNCTION t.accept(p_quote BIGINT) RETURNS void LANGUAGE sql AS $$
    UPDATE price_quotes SET status = 'accepted', accepted_at = now() WHERE id = p_quote$$;

CREATE FUNCTION t.request(p_shipment BIGINT) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM t.act((SELECT customer_id FROM shipments WHERE id = p_shipment), 'customer');
    UPDATE shipments SET status = 'searching_driver' WHERE id = p_shipment;
    PERFORM t.sys();
END$$;

CREATE FUNCTION t.ready_shipment(p_customer BIGINT, p_method TEXT DEFAULT 'wallet', p_transport NUMERIC DEFAULT 500,
                                 p_helpers INT DEFAULT 0, p_payer TEXT DEFAULT 'sender', p_coupon BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    sid BIGINT;
BEGIN
    sid := t.mk_shipment(p_customer, p_method, p_helpers, NULL, NULL, p_payer);
    PERFORM t.accept(t.mk_quote(sid, p_transport, p_coupon));
    PERFORM t.request(sid);
    RETURN sid;
END$$;

CREATE FUNCTION t.assign(p_shipment BIGINT, p_driver BIGINT) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    tid BIGINT;
BEGIN
    INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount, commission_rate,
                       planned_start_at, planned_end_at)
    VALUES (p_shipment, p_driver, t.vehicle_of(p_driver),
            (SELECT id FROM price_quotes WHERE shipment_id = p_shipment AND status = 'accepted'), 0, 0,
            now(), now() + interval '2 hours')
    RETURNING id INTO tid;
    RETURN tid;
END$$;

CREATE FUNCTION t.move(p_trip BIGINT, p_status TEXT) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM t.act((SELECT driver_id FROM trips WHERE id = p_trip), 'driver');
    UPDATE trips SET status = p_status WHERE id = p_trip;
    PERFORM t.sys();
END$$;

CREATE FUNCTION t.photo(p_trip BIGINT, p_stage TEXT) RETURNS void LANGUAGE sql AS $$
    INSERT INTO trip_photos (trip_id, stage, storage_key, uploaded_by)
    SELECT p_trip, p_stage, 'ph/' || p_trip || '/' || p_stage, driver_id FROM trips WHERE id = p_trip$$;

CREATE FUNCTION t.collect(p_trip BIGINT, p_status TEXT DEFAULT 'collected') RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    tr trips%ROWTYPE;
    sh shipments%ROWTYPE;
BEGIN
    SELECT * INTO tr FROM trips WHERE id = p_trip;
    SELECT * INTO sh FROM shipments WHERE id = tr.shipment_id;
    INSERT INTO payments (shipment_id, price_quote_id, method, payer, amount, status,
                          collected_on_trip_id, collected_by_driver_id, collected_at)
    SELECT sh.id, q.id, 'cash', sh.fare_paid_by, q.customer_amount, p_status, tr.id, tr.driver_id, now()
    FROM price_quotes q WHERE q.id = tr.price_quote_id;
END$$;

CREATE FUNCTION t.to_dropoff(p_trip BIGINT) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    sh shipments%ROWTYPE;
BEGIN
    SELECT s.* INTO sh FROM shipments s JOIN trips tr ON tr.shipment_id = s.id WHERE tr.id = p_trip;
    PERFORM t.move(p_trip, 'heading_to_pickup');
    PERFORM t.move(p_trip, 'arrived_at_pickup');
    PERFORM t.photo(p_trip, 'pickup');
    IF sh.payment_method = 'cash' AND sh.fare_paid_by = 'sender' THEN PERFORM t.collect(p_trip); END IF;
    PERFORM t.move(p_trip, 'loaded');
    UPDATE trips SET vehicle_fit = 'suitable' WHERE id = p_trip;
    PERFORM t.move(p_trip, 'heading_to_dropoff');
    PERFORM t.move(p_trip, 'arrived_at_dropoff');
END$$;

CREATE FUNCTION t.deliver(p_trip BIGINT) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    sh shipments%ROWTYPE;
BEGIN
    SELECT s.* INTO sh FROM shipments s JOIN trips tr ON tr.shipment_id = s.id WHERE tr.id = p_trip;
    PERFORM t.to_dropoff(p_trip);
    PERFORM t.photo(p_trip, 'delivery');
    IF sh.payment_method = 'cash' AND sh.fare_paid_by = 'recipient' THEN PERFORM t.collect(p_trip); END IF;
    PERFORM verify_delivery_code(p_trip, '1234');
    PERFORM t.move(p_trip, 'delivered');
END$$;

CREATE FUNCTION t.cbal(p BIGINT) RETURNS TEXT LANGUAGE sql STABLE AS $$ SELECT customer_balance(p)::numeric(12,2)::text$$;
CREATE FUNCTION t.dbal(p BIGINT) RETURNS TEXT LANGUAGE sql STABLE AS $$ SELECT driver_balance(p)::numeric(12,2)::text$$;

CREATE FUNCTION t.mk_group(p_customer BIGINT, p_helpers INT DEFAULT 0) RETURNS BIGINT LANGUAGE sql AS $$
    INSERT INTO shipment_groups (customer_id, pickup_address, pickup_location, helpers_count)
    VALUES (p_customer, 'Warehouse, Nasr City', t.loc(31.33, 30.06), p_helpers) RETURNING id$$;

CREATE FUNCTION t.resolve_cargo(p_trip BIGINT, p_admin BIGINT) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE tk BIGINT; cid BIGINT;
BEGIN
    SELECT s.customer_id INTO cid FROM shipments s JOIN trips tr ON tr.shipment_id = s.id WHERE tr.id = p_trip;
    PERFORM t.act(p_admin, 'admin');
    INSERT INTO support_tickets (user_id, user_role, opened_by, trip_id, category, subject)
    VALUES (cid, 'customer', p_admin, p_trip, 'trip', 'Cargo incident') RETURNING id INTO tk;
    UPDATE support_tickets SET status = 'resolved', cargo_outcome = 'returned_to_sender',
           resolution_note = 'Cargo returned to sender; receipt checked by admin.' WHERE id = tk;
    PERFORM t.sys();
    RETURN tk;
END$$;

SELECT t.publish_policies();
SELECT t.set('admin',  t.mk_user('Admin One', '+201000000001', ARRAY['admin']));
SELECT t.set('admin2', t.mk_user('Admin Two', '+201000000002', ARRAY['admin']));
SELECT t.set('cust',   t.mk_user('Mariam Adel', '+201111111111', ARRAY['customer']));
SELECT t.set('cust2',  t.mk_user('Laila Nabil', '+201111111112', ARRAY['customer']));
SELECT t.set('drv',    t.mk_driver('Ahmed Hassan', '+201222222221'));
SELECT t.approve_driver(t.get('drv'), t.get('admin'));
SELECT t.set('drv2',   t.mk_driver('Karim Nabil', '+201222222222'));
SELECT t.approve_driver(t.get('drv2'), t.get('admin'));
SELECT t.fund(t.get('cust'), 5000, t.get('admin'));

SELECT t.section('users & phones');
SELECT t.ok('foreign E.164 phone accepted', $q$ INSERT INTO users (full_name, phone, email, password_hash) VALUES ('Sam', '+447911123456', 'sam@test.wasla', 'h')$q$);
SELECT t.err('local format phone rejected', $q$ INSERT INTO users (full_name, phone, email, password_hash) VALUES ('X', '01012345678', 'x1@test.wasla', 'h')$q$, 'phone_e164');
SELECT t.err('too short phone rejected', $q$ INSERT INTO users (full_name, phone, email, password_hash) VALUES ('X', '+2012', 'x2@test.wasla', 'h')$q$, 'phone_e164');
SELECT t.err('duplicate email rejected', $q$ INSERT INTO users (full_name, phone, email, password_hash) VALUES ('X', '+201111111199', 'sam@test.wasla', 'h')$q$, 'uq_users_email_ci');
SELECT t.err('OTP email must be a valid email', $q$ INSERT INTO otp_codes (email, code_hash, purpose, expires_at) VALUES ('not-an-email', 'h', 'login', now())$q$, 'email_address');
SELECT t.ok('OTP purpose delete_account exists', $q$ INSERT INTO otp_codes (email, code_hash, purpose, expires_at) VALUES ('sam@test.wasla', 'h', 'delete_account', now() + interval '5 min')$q$);
SELECT t.eq('preferred language defaults to ar', (SELECT preferred_language FROM users WHERE id = t.get('cust')), 'ar');
SELECT t.err('preferred language only ar/en', $q$ UPDATE users SET preferred_language = 'fr' WHERE id = 1$q$, 'preferred_language');
SELECT t.err('default payment only cash/wallet', $q$ UPDATE users SET default_payment_method = 'card' WHERE id = 1$q$, 'default_payment_method');
SELECT t.err('live user needs a password', $q$ UPDATE users SET password_hash = NULL WHERE id = 1$q$, 'ck_users_live_credentials');

SELECT t.section('terms & privacy');
SELECT t.err('customer role without accepting terms is rejected (deferred)', $q$
    WITH u AS (INSERT INTO users (full_name, phone, email, password_hash) VALUES ('NoTerms', '+201555000001', 'noterms@test.wasla', 'h') RETURNING id)
    INSERT INTO user_roles (user_id, role_id) SELECT u.id, r.id FROM u, roles r WHERE r.code = 'customer'$q$, 'must accept the latest terms');
SELECT t.ok('admin role without accepting terms is allowed', $q$
    WITH u AS (INSERT INTO users (full_name, phone, email, password_hash) VALUES ('Admin3', '+201555000002', 'admin3@test.wasla', 'h') RETURNING id)
    INSERT INTO user_roles (user_id, role_id) SELECT u.id, r.id FROM u, roles r WHERE r.code = 'admin'$q$);
SELECT t.err('published policy text cannot change', $q$ UPDATE policy_versions SET content_en = 'changed' WHERE doc_type = 'terms'$q$, 'is published');
SELECT t.ok('draft policy text can change', $q$
    INSERT INTO policy_versions (doc_type, version_number, content_ar, content_en) VALUES ('terms', 2, 'مسودة', 'Draft');
    UPDATE policy_versions SET content_en = 'Draft 2' WHERE doc_type = 'terms' AND version_number = 2$q$);
SELECT t.err('new version number must be higher', $q$ INSERT INTO policy_versions (doc_type, version_number, content_ar, content_en) VALUES ('terms', 1, 'a', 'b')$q$, 'must be newer');
SELECT t.err('cannot accept an unpublished version', $q$
    INSERT INTO policy_acceptances (user_id, policy_version_id)
    SELECT 1, id FROM policy_versions WHERE doc_type = 'terms' AND version_number = 2$q$, 'not published');
SELECT t.err('policy acceptances are append-only', $q$ UPDATE policy_acceptances SET accepted_at = now()$q$, 'append-only');
SELECT t.err('policy acceptances cannot be deleted', $q$ DELETE FROM policy_acceptances$q$, 'permanent record');
SELECT t.err('policy text needs both languages', $q$ INSERT INTO policy_versions (doc_type, version_number, content_ar, content_en) VALUES ('privacy', 5, 'نص', ' ')$q$, 'content_en');

SELECT t.section('catalog');
SELECT t.err('vehicle type names are unique (ar)', $q$
    INSERT INTO vehicle_types (code, name_ar, name_en, max_payload_kg, cargo_volume_m3, bed_length_m, bed_width_m, bed_height_m, base_fare, per_km_rate)
    VALUES ('x', 'ربع نقل', 'X', 1, 1, 1, 1, 1, 1, 1)$q$, 'unique');
SELECT t.err('bed dimensions must be positive', $q$
    INSERT INTO vehicle_types (code, name_ar, name_en, max_payload_kg, cargo_volume_m3, bed_length_m, bed_width_m, bed_height_m, base_fare, per_km_rate)
    VALUES ('y', 'ي', 'Y', 1, 1, 0, 1, 1, 1, 1)$q$, 'positive_measure');
SELECT t.set('s_cat', t.mk_shipment(t.get('cust')));
SELECT t.err('size option must belong to the cargo category', $q$
    UPDATE shipments SET size_option_id = (SELECT id FROM cargo_size_options WHERE code = 'pallet'),
                         cargo_category_id = (SELECT id FROM cargo_categories WHERE code = 'furniture')
    WHERE id = t.get('s_cat')$q$, 'fk_shipment_size_of_category');
SELECT t.ok('size option of the same category is accepted', $q$
    UPDATE shipments SET size_option_id = (SELECT id FROM cargo_size_options WHERE code = 'one_room')
    WHERE id = t.get('s_cat')$q$);
SELECT t.eq('size option saved', (SELECT (size_option_id IS NOT NULL)::text FROM shipments WHERE id = t.get('s_cat')), 'true');
SELECT t.err('review tag direction must be valid', $q$ INSERT INTO review_tags (code, name_ar, name_en, sentiment, direction) VALUES ('z', 'ز', 'Z', 'positive', 'both')$q$, 'direction');
SELECT t.err('catalog rows cannot be deleted (deactivate instead)', $q$ DELETE FROM cargo_categories WHERE code = 'other'$q$, 'permanent record');

SELECT t.section('driver onboarding');
SELECT t.set('d3', t.mk_driver('Omar Samir', '+201222222223', 'quarter_truck', 'professional_3', 0));
SELECT t.err('inactive city rejected', $q$
    INSERT INTO cities (code, name_ar, name_en, is_active) VALUES ('alex', 'الإسكندرية', 'Alexandria', false);
    UPDATE driver_profiles SET city_id = (SELECT id FROM cities WHERE code = 'alex') WHERE user_id = t.get('d3')$q$, 'not active');
SELECT t.err('new driver profile must start as draft', $q$
    INSERT INTO driver_profiles (user_id, city_id, date_of_birth, verification_status)
    VALUES (t.get('cust2'), (SELECT id FROM cities WHERE code = 'cairo'), '1990-01-01', 'pending')$q$, 'start as draft');
SELECT t.err('national id hash must be 64 hex chars', $q$ UPDATE driver_profiles SET national_id_hash = '29001011234567' WHERE user_id = t.get('d3')$q$, 'national_id_hash');
SELECT t.err('national id hash is unique (same person twice)', $q$
    UPDATE driver_profiles SET national_id_hash = (SELECT national_id_hash FROM driver_profiles WHERE user_id = t.get('drv'))
    WHERE user_id = t.get('d3')$q$, 'unique');
SELECT t.err('hash and last4 go together', $q$ UPDATE driver_profiles SET national_id_last4 = NULL WHERE user_id = t.get('d3')$q$, 'ck_driver_national_id');
SELECT t.err('national id number cannot be stored on ID documents', $q$
    UPDATE driver_documents SET document_number = '29001011234567' WHERE driver_id = t.get('d3') AND document_type = 'national_id_front'$q$, 'ck_driver_doc_no_national_id');
SELECT t.err('license front needs a category', $q$
    INSERT INTO driver_documents (driver_id, document_type, storage_key) VALUES (t.get('d3'), 'driving_license_front', 'x')$q$, 'ck_driver_doc_license_category');
SELECT t.err('license back has no category', $q$
    INSERT INTO driver_documents (driver_id, document_type, storage_key, license_category) VALUES (t.get('d3'), 'driving_license_back', 'x', 'private')$q$, 'ck_driver_doc_license_category');
SELECT t.err('old document type driving_license is gone', $q$
    INSERT INTO driver_documents (driver_id, document_type, storage_key) VALUES (t.get('d3'), 'driving_license', 'x')$q$, 'document_type');
SELECT t.err('old vehicle_photo type is gone (4 angles now)', $q$
    INSERT INTO vehicle_documents (vehicle_id, document_type, storage_key) VALUES (t.vehicle_of(t.get('d3')), 'vehicle_photo', 'x')$q$, 'document_type');
SELECT t.eq('vehicle max payload copied from its type', (SELECT max_payload_kg::int::text FROM vehicles WHERE id = t.vehicle_of(t.get('d3'))), '1500');
SELECT t.err('manufacture year too old', $q$ UPDATE vehicles SET manufacture_year = 1975 WHERE id = t.vehicle_of(t.get('d3'))$q$, 'between 1980');
SELECT t.err('manufacture year in the far future', $q$ UPDATE vehicles SET manufacture_year = EXTRACT(YEAR FROM now())::int + 2 WHERE id = t.vehicle_of(t.get('d3'))$q$, 'between 1980');
SELECT t.err('vehicle color is required', $q$ UPDATE vehicles SET color = ' ' WHERE id = t.vehicle_of(t.get('d3'))$q$, 'color');

SELECT t.err('submit blocked: under minimum age', $q$
    UPDATE driver_profiles SET date_of_birth = current_date - interval '19 years' WHERE user_id = t.get('d3');
    UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = t.get('d3')$q$, 'min_age');
SELECT t.err('submit blocked: missing profile photo', $q$
    INSERT INTO driver_documents (driver_id, document_type, storage_key) VALUES (t.get('d3'), 'profile_photo', 'p2');
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE driver_documents SET review_status = 'rejected', rejection_code = 'blurry', rejection_reason = 'Retake'
    WHERE driver_id = t.get('d3') AND document_type = 'profile_photo' AND superseded_at IS NULL;
    SELECT t.sys();
    UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = t.get('d3')$q$, 'profile_photo');
SELECT t.err('superseded_at cannot be set by hand', $q$
    UPDATE vehicle_documents SET superseded_at = now() WHERE vehicle_id = t.vehicle_of(t.get('d3')) AND document_type = 'vehicle_photo_rear'$q$, 'set automatically');
SELECT t.err('submit blocked: no payout account', $q$
    INSERT INTO payout_accounts (user_id, method, holder_name, account_number) VALUES (t.get('d3'), 'wallet', 'Omar', '0100');
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE payout_accounts SET review_status = 'rejected', rejection_code = 'invalid_account', rejection_reason = 'Wrong'
    WHERE user_id = t.get('d3') AND superseded_at IS NULL;
    SELECT t.sys();
    UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = t.get('d3')$q$, 'payout_account');
SELECT t.ok('submit succeeds with everything in place', $q$ UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = t.get('d3')$q$);
SELECT t.eq('submitted_at is set by the database', (SELECT (submitted_at IS NOT NULL)::text FROM driver_profiles WHERE user_id = t.get('d3')), 'true');
SELECT t.ok('editing submitted_at by hand is ignored', $q$ UPDATE driver_profiles SET submitted_at = now() - interval '9 days' WHERE user_id = t.get('d3')$q$);
SELECT t.eq('submitted_at unchanged', (SELECT (submitted_at > now() - interval '1 day')::text FROM driver_profiles WHERE user_id = t.get('d3')), 'true');
SELECT t.err('cannot go back to draft', $q$ UPDATE driver_profiles SET verification_status = 'draft' WHERE user_id = t.get('d3')$q$, 'cannot go from');

SELECT t.act(t.get('admin'), 'admin');
SELECT t.err('approve blocked while documents pending', $q$ UPDATE driver_profiles SET verification_status = 'approved' WHERE user_id = t.get('d3')$q$, 'cannot be approved yet');
SELECT t.err('rejecting a document needs code and message', $q$
    UPDATE driver_documents SET review_status = 'rejected', rejection_reason = 'blurry'
    WHERE driver_id = t.get('d3') AND document_type = 'national_id_back' AND superseded_at IS NULL$q$, 'ck_driver_doc_rejection');
SELECT t.err('invalid rejection code', $q$
    UPDATE driver_documents SET review_status = 'rejected', rejection_code = 'ugly', rejection_reason = 'x'
    WHERE driver_id = t.get('d3') AND document_type = 'national_id_back' AND superseded_at IS NULL$q$, 'rejection_code');
SELECT t.err('approving license front without expiry is rejected', $q$
    UPDATE driver_documents SET review_status = 'approved'
    WHERE driver_id = t.get('d3') AND document_type = 'driving_license_front' AND superseded_at IS NULL$q$, 'ck_driver_doc_expiry');
SELECT t.err('approving vehicle license without expiry is rejected', $q$
    UPDATE vehicle_documents SET review_status = 'approved'
    WHERE vehicle_id = t.vehicle_of(t.get('d3')) AND document_type = 'vehicle_license_front' AND superseded_at IS NULL$q$, 'ck_vehicle_doc_expiry');
SELECT t.err('checks must be a JSON object', $q$
    UPDATE driver_documents SET checks = '["ok"]' WHERE driver_id = t.get('d3') AND document_type = 'profile_photo' AND superseded_at IS NULL$q$, 'checks');
SELECT t.ok('admin records checks, expiry and fixes license category while reviewing', $q$
    UPDATE driver_documents SET checks = '{"photo_quality": "ok", "name_match": "ok"}', expires_on = current_date + 400,
           license_category = 'professional_2'
    WHERE driver_id = t.get('d3') AND document_type = 'driving_license_front' AND superseded_at IS NULL$q$);
SELECT t.ok('rejecting one document keeps the application pending', $q$
    UPDATE driver_documents SET review_status = 'rejected', rejection_code = 'blurry', rejection_reason = 'Please retake in daylight'
    WHERE driver_id = t.get('d3') AND document_type = 'national_id_back' AND superseded_at IS NULL$q$);
SELECT t.eq('application still pending', (SELECT verification_status FROM driver_profiles WHERE user_id = t.get('d3')), 'pending');
SELECT t.eq('reviewer taken from the actor', (SELECT (reviewed_by = t.get('admin'))::text FROM driver_documents WHERE driver_id = t.get('d3') AND document_type = 'national_id_back' AND review_status = 'rejected'), 'true');
SELECT t.err('a reviewed document is final', $q$
    UPDATE driver_documents SET review_status = 'approved', rejection_code = NULL, rejection_reason = NULL
    WHERE driver_id = t.get('d3') AND document_type = 'national_id_back' AND review_status = 'rejected'$q$, 'final');
SELECT t.sys();
SELECT t.ok('re-upload after rejection', $q$ INSERT INTO driver_documents (driver_id, document_type, storage_key) VALUES (t.get('d3'), 'national_id_back', 'id-back-2')$q$);
SELECT t.eq('the rejected copy is superseded on re-upload',
    (SELECT count(*)::text FROM driver_documents WHERE driver_id = t.get('d3') AND document_type = 'national_id_back' AND superseded_at IS NULL), '1');
SELECT t.err('a document file cannot be swapped', $q$
    UPDATE driver_documents SET storage_key = 'other' WHERE driver_id = t.get('d3') AND document_type = 'national_id_back' AND superseded_at IS NULL$q$, 'cannot change');
SELECT t.act(t.get('admin'), 'admin');
SELECT t.ok('approve all documents', $q$
    UPDATE driver_documents SET review_status = 'approved',
           expires_on = CASE WHEN document_type IN ('national_id_front', 'driving_license_front') THEN current_date + 365 END
    WHERE driver_id = t.get('d3') AND superseded_at IS NULL AND review_status = 'pending';
    UPDATE vehicle_documents SET review_status = 'approved',
           expires_on = CASE WHEN document_type = 'vehicle_license_front' THEN current_date + 365 END
    WHERE vehicle_id = t.vehicle_of(t.get('d3')) AND superseded_at IS NULL AND review_status = 'pending'$q$);
SELECT t.ok('approve driver (payout account not required)', $q$ UPDATE driver_profiles SET verification_status = 'approved' WHERE user_id = t.get('d3')$q$);
SELECT t.err('rejecting an approved driver is not a valid transition', $q$
    UPDATE driver_profiles SET verification_status = 'rejected', rejection_reason = 'x' WHERE user_id = t.get('d3')$q$, 'cannot go from');
SELECT t.sys();

SELECT t.ok('renewal upload keeps the approved license active', $q$
    INSERT INTO driver_documents (driver_id, document_type, storage_key, license_category)
    VALUES (t.get('d3'), 'driving_license_front', 'lic-2', 'professional_2')$q$);
SELECT t.eq('approved + pending copies both current', (SELECT string_agg(review_status, ',' ORDER BY review_status) FROM driver_documents
    WHERE driver_id = t.get('d3') AND document_type = 'driving_license_front' AND superseded_at IS NULL), 'approved,pending');
SELECT t.act(t.get('admin'), 'admin');
SELECT t.ok('approving the renewal supersedes the old approved copy', $q$
    UPDATE driver_documents SET review_status = 'approved', expires_on = current_date + 700
    WHERE driver_id = t.get('d3') AND document_type = 'driving_license_front' AND review_status = 'pending' AND superseded_at IS NULL$q$);
SELECT t.sys();
SELECT t.eq('only one current approved license', (SELECT count(*)::text FROM driver_documents
    WHERE driver_id = t.get('d3') AND document_type = 'driving_license_front' AND superseded_at IS NULL), '1');
SELECT t.err('two pending copies of the same type are impossible', $q$
    INSERT INTO driver_documents (driver_id, document_type, storage_key) VALUES (t.get('d3'), 'profile_photo', 'a');
    INSERT INTO driver_documents (driver_id, document_type, storage_key, review_status) VALUES (t.get('d3'), 'profile_photo', 'b', 'approved')$q$, 'start as pending');

SELECT t.ok('vehicle activated', $q$ UPDATE vehicles SET status = 'active' WHERE id = t.vehicle_of(t.get('d3'))$q$);
SELECT t.ok('driver goes online', $q$ UPDATE driver_profiles SET active_vehicle_id = t.vehicle_of(t.get('d3')), current_location = t.loc(31.2, 30.0),
    location_updated_at = now(), is_online = true WHERE user_id = t.get('d3')$q$);
SELECT t.eq('online session opened', (SELECT count(*)::text FROM driver_online_sessions WHERE driver_id = t.get('d3') AND ended_at IS NULL), '1');
SELECT t.ok('driver goes offline', $q$ UPDATE driver_profiles SET is_online = false WHERE user_id = t.get('d3')$q$);
SELECT t.eq('online session closed', (SELECT count(*)::text FROM driver_online_sessions WHERE driver_id = t.get('d3') AND ended_at IS NOT NULL), '1');
SELECT t.err('sessions cannot be written by hand', $q$ INSERT INTO driver_online_sessions (driver_id) VALUES (t.get('d3'))$q$, 'written automatically');
SELECT t.err('license category too low for a heavy truck', $q$
    INSERT INTO vehicles (driver_id, vehicle_type_id, plate_number, make, model, manufacture_year, color, status)
    VALUES (t.get('d3'), (SELECT id FROM vehicle_types WHERE code = 'heavy_truck'), 'HV-1', 'Mercedes', 'Actros', 2015, 'Red', 'active');
    UPDATE driver_profiles SET active_vehicle_id = (SELECT id FROM vehicles WHERE plate_number = 'HV-1') WHERE user_id = t.get('d3')$q$, 'license category is too low');
SELECT t.set('d4', t.mk_driver('Draft Driver', '+201222222224'));
SELECT t.err('draft driver cannot go online', $q$
    UPDATE driver_profiles SET is_online = true, active_vehicle_id = t.vehicle_of(user_id), current_location = t.loc(1, 1)
    WHERE user_id = t.get('d4')$q$, 'ck_driver_online_approved');

SELECT t.act(t.get('admin'), 'admin');
SELECT t.ok('suspending an online driver', $q$
    UPDATE driver_profiles SET is_online = true WHERE user_id = t.get('d3');
    UPDATE users SET account_status = 'suspended', suspended_at = now(), suspended_by = t.get('admin'), suspension_reason = 'Safety review'
    WHERE id = t.get('d3')$q$);
SELECT t.eq('suspended driver is offline automatically', (SELECT is_online::text FROM driver_profiles WHERE user_id = t.get('d3')), 'false');
SELECT t.err('suspended driver cannot go online', $q$ UPDATE driver_profiles SET is_online = true WHERE user_id = t.get('d3')$q$, 'not active');
SELECT t.err('suspension needs a reason', $q$ UPDATE users SET account_status = 'suspended', suspended_at = now(), suspension_reason = NULL WHERE id = t.get('cust2')$q$, 'ck_users_suspension');
SELECT t.ok('reactivate driver', $q$ UPDATE users SET account_status = 'active' WHERE id = t.get('d3')$q$);
SELECT t.sys();

SELECT t.err('bank account needs a bank name', $q$ INSERT INTO payout_accounts (user_id, method, holder_name, account_number) VALUES (t.get('cust'), 'bank_account', 'M', '123')$q$, 'ck_payout_account_bank');
SELECT t.ok('customer adds a payout account', $q$ INSERT INTO payout_accounts (user_id, method, holder_name, bank_name, account_number) VALUES (t.get('cust'), 'bank_account', 'Mariam', 'CIB', '123456')$q$);
SELECT t.ok('changing the account adds a new row and supersedes the old', $q$ INSERT INTO payout_accounts (user_id, method, holder_name, account_number) VALUES (t.get('cust'), 'wallet', 'Mariam', '01111111111')$q$);
SELECT t.eq('one current account per user', (SELECT count(*)::text FROM payout_accounts WHERE user_id = t.get('cust') AND superseded_at IS NULL), '1');
SELECT t.eq('old account kept in history', (SELECT count(*)::text FROM payout_accounts WHERE user_id = t.get('cust')), '2');
SELECT t.err('account details cannot be edited', $q$ UPDATE payout_accounts SET account_number = '999' WHERE user_id = t.get('cust') AND superseded_at IS NULL$q$, 'cannot change');
SELECT t.act(t.get('admin'), 'admin');
SELECT t.ok('admin approves the customer account', $q$ UPDATE payout_accounts SET review_status = 'approved' WHERE user_id = t.get('cust') AND superseded_at IS NULL$q$);
SELECT t.sys();

SELECT t.section('zones');
SELECT t.ok('create zones (big and small overlapping)', $q$
    INSERT INTO service_zones (city_id, code, name_ar, name_en, boundary) VALUES
      ((SELECT id FROM cities WHERE code = 'cairo'), 'east_cairo', 'شرق القاهرة', 'East Cairo', t.box_poly(31.28, 30.00, 31.45, 30.15)),
      ((SELECT id FROM cities WHERE code = 'cairo'), 'nasr_city',  'مدينة نصر',  'Nasr City',  t.box_poly(31.30, 30.03, 31.36, 30.09)),
      ((SELECT id FROM cities WHERE code = 'cairo'), 'maadi',      'المعادي',    'Maadi',      t.box_poly(31.22, 29.93, 31.28, 29.99))$q$);
SELECT t.set('s_zone', t.mk_shipment(t.get('cust')));
SELECT t.eq('pickup zone = the smallest covering zone', (SELECT z.code FROM shipments s JOIN service_zones z ON z.id = s.pickup_zone_id WHERE s.id = t.get('s_zone')), 'nasr_city');
SELECT t.eq('dropoff zone set automatically', (SELECT z.code FROM shipments s JOIN service_zones z ON z.id = s.dropoff_zone_id WHERE s.id = t.get('s_zone')), 'maadi');
SELECT t.ok('backend cannot set a zone by hand (ignored)', $q$ UPDATE shipments SET pickup_zone_id = (SELECT id FROM service_zones WHERE code = 'maadi') WHERE id = t.get('s_zone')$q$);
SELECT t.eq('zone unchanged', (SELECT z.code FROM shipments s JOIN service_zones z ON z.id = s.pickup_zone_id WHERE s.id = t.get('s_zone')), 'nasr_city');
SELECT t.ok('moving the pickup recomputes the zone', $q$ UPDATE shipments SET pickup_location = t.loc(31.40, 30.12) WHERE id = t.get('s_zone')$q$);
SELECT t.eq('new zone', (SELECT z.code FROM shipments s JOIN service_zones z ON z.id = s.pickup_zone_id WHERE s.id = t.get('s_zone')), 'east_cairo');
SELECT t.ok('outside every zone is allowed', $q$ UPDATE shipments SET dropoff_location = t.loc(29.9, 31.2) WHERE id = t.get('s_zone')$q$);
SELECT t.eq('outside = empty zone ("Other")', (SELECT (dropoff_zone_id IS NULL)::text FROM shipments WHERE id = t.get('s_zone')), 'true');

SELECT t.section('shipment details');
SELECT t.err('cargo category is required', $q$
    INSERT INTO shipments (customer_id, cargo_description, item_count, pickup_address, pickup_location, dropoff_address, dropoff_location,
      pickup_type, pickup_window_start, pickup_window_end, payment_method, delivery_code)
    VALUES (t.get('cust'), 'x', 1, 'a', t.loc(1,1), 'b', t.loc(2,2), 'now', now(), now(), 'cash', '1111')$q$, 'cargo_category_id');
SELECT t.err('bank transfer is no longer a payment method', $q$ UPDATE shipments SET payment_method = 'bank_transfer' WHERE id = t.get('s_zone')$q$, 'payment_method');
SELECT t.err('item count must be positive', $q$ UPDATE shipments SET item_count = 0 WHERE id = t.get('s_zone')$q$, 'item_count');
SELECT t.err('recipient name and phone go together', $q$ UPDATE shipments SET recipient_name = 'Ali' WHERE id = t.get('s_zone')$q$, 'ck_shipments_recipient_pair');
SELECT t.err('recipient phone is E.164', $q$ UPDATE shipments SET recipient_name = 'Ali', recipient_phone = '0100' WHERE id = t.get('s_zone')$q$, 'phone_e164');
SELECT t.err('recipient pays only in cash', $q$
    UPDATE shipments SET fare_paid_by = 'recipient', recipient_name = 'Ali', recipient_phone = '+201000000777', payment_method = 'wallet'
    WHERE id = t.get('s_zone')$q$, 'ck_shipments_recipient_pays');
SELECT t.err('recipient pays needs a known recipient', $q$
    UPDATE shipments SET fare_paid_by = 'recipient', payment_method = 'cash' WHERE id = t.get('s_zone')$q$, 'ck_shipments_recipient_pays');
SELECT t.err('pickup type is now/scheduled', $q$ UPDATE shipments SET pickup_type = 'asap' WHERE id = t.get('s_zone')$q$, 'pickup_type');
SELECT t.err('cancelled shipment needs a cancellation party', $q$ UPDATE shipments SET status = 'cancelled' WHERE id = t.get('s_zone') AND false; SELECT t.act(t.get('admin'), 'admin'); UPDATE shipments SET status = 'cancelled' WHERE id = t.get('s_zone')$q$, 'needs cancellation_party');
SELECT t.sys();

SELECT t.section('quotes');
SELECT t.set('s_q', t.mk_shipment(t.get('cust'), 'wallet', 2));
SELECT t.err('no quote without a cargo photo', $q$
    DELETE FROM shipment_item_images WHERE shipment_id = t.get('s_q');
    SELECT t.mk_quote(t.get('s_q'))$q$, 'no cargo photo');
SELECT t.err('helpers amount must equal count x fee', $q$
    INSERT INTO price_quotes (shipment_id, vehicle_type_id, pricing_details, pricing_source, standard_amount, transport_amount,
      helpers_amount, amount, customer_amount, commission_rate, shipment_version, expires_at)
    VALUES (t.get('s_q'), (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), '{}', 'rules', 500, 500, 100, 600, 600, 0, (SELECT details_version FROM shipments WHERE id = t.get('s_q')), now() + interval '1 hour')$q$, 'helpers amount must be');
SELECT t.err('amount must equal transport + helpers - discounts', $q$
    INSERT INTO price_quotes (shipment_id, vehicle_type_id, pricing_details, pricing_source, standard_amount, transport_amount,
      helpers_amount, amount, customer_amount, commission_rate, shipment_version, expires_at)
    VALUES (t.get('s_q'), (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), '{}', 'rules', 500, 500, 300, 700, 700, 0, (SELECT details_version FROM shipments WHERE id = t.get('s_q')), now() + interval '1 hour')$q$, 'ck_quote_amount');
SELECT t.set('q1', t.mk_quote(t.get('s_q'), 500));
SELECT t.eq('helpers copied from shipment and fee from vehicle type', (SELECT helpers_count || 'x' || helper_fee FROM price_quotes WHERE id = t.get('q1')), '2x150.00');
SELECT t.eq('commission rate set by the database', (SELECT commission_rate::text FROM price_quotes WHERE id = t.get('q1')), '0.1500');
SELECT t.eq('quote amount = 500 + 2x150', (SELECT amount::text FROM price_quotes WHERE id = t.get('q1')), '800.00');
SELECT t.err('AI price above the cap is rejected', $q$ SELECT t.mk_quote(t.get('s_q'), 700, NULL, 'ai', 500)$q$, 'above the cap');
SELECT t.ok('AI price at the cap is accepted', $q$ SELECT t.mk_quote(t.get('s_q'), 625, NULL, 'ai', 500)$q$);
SELECT t.ok('rules price is not capped', $q$ SELECT t.mk_quote(t.get('s_q'), 900, NULL, 'rules', 500)$q$);
SELECT t.err('group discount only for group shipments', $q$ SELECT t.mk_quote(t.get('s_q'), 500, NULL, 'rules', NULL, 0, 50)$q$, 'group shipments only');
SELECT t.err('quote details are fixed after creation', $q$ UPDATE price_quotes SET transport_amount = 1 WHERE id = t.get('q1')$q$, 'fixed');
SELECT t.ok('changing the shipment invalidates older quotes (version)', $q$ UPDATE shipments SET cargo_description = 'Sofa, boxes and a fridge' WHERE id = t.get('s_q')$q$);
SELECT t.err('old-version quote cannot be accepted', $q$ SELECT t.accept(t.get('q1'))$q$, 'older version');
SELECT t.set('q2', t.mk_quote(t.get('s_q'), 500));
SELECT t.ok('fresh quote accepted', $q$ SELECT t.accept(t.get('q2'))$q$);
SELECT t.err('details locked after acceptance (notes too)', $q$ UPDATE shipments SET dropoff_notes = 'Floor 5' WHERE id = t.get('s_q')$q$, 'fixed after the price');
SELECT t.err('helpers locked after acceptance', $q$ UPDATE shipments SET helpers_count = 3 WHERE id = t.get('s_q')$q$, 'fixed after the price');
SELECT t.err('fragile flag locked after acceptance', $q$ UPDATE shipments SET is_fragile = true WHERE id = t.get('s_q')$q$, 'fixed after the price');
SELECT t.err('cargo photos locked after acceptance', $q$ INSERT INTO shipment_item_images (shipment_id, storage_key) VALUES (t.get('s_q'), 'late')$q$, 'fixed after the price');
SELECT t.ok('withdraw acceptance while draft', $q$ UPDATE price_quotes SET status = 'withdrawn' WHERE id = t.get('q2')$q$);
SELECT t.ok('details editable again after withdrawing', $q$ UPDATE shipments SET dropoff_notes = 'Floor 5, no elevator' WHERE id = t.get('s_q')$q$);
SELECT t.err('scheduled pickup too soon', $q$
    UPDATE shipments SET pickup_type = 'scheduled', pickup_window_start = now() + interval '10 min', pickup_window_end = now() + interval '1 hour'
    WHERE id = t.get('s_q');
    SELECT t.mk_quote(t.get('s_q'))$q$, 'at least 30 minutes');
SELECT t.ok('scheduled pickup with enough lead time', $q$
    UPDATE shipments SET pickup_type = 'scheduled', pickup_window_start = now() + interval '2 hours', pickup_window_end = now() + interval '3 hours'
    WHERE id = t.get('s_q');
    SELECT t.mk_quote(t.get('s_q'))$q$);

SELECT t.section('coupons');
SELECT t.ok('create coupons', $q$
    INSERT INTO coupons (code, discount_type, discount_value, max_discount, min_order_amount, starts_at, ends_at, max_total_uses, max_uses_per_customer)
    VALUES ('SAVE10', 'percent', 10, 50, 100, now() - interval '1 day', now() + interval '30 days', 1, 1),
           ('FLAT80', 'fixed', 80, NULL, 0, now() - interval '1 day', now() + interval '30 days', NULL, 5),
           ('OLD', 'fixed', 20, NULL, 0, now() - interval '30 days', now() - interval '1 day', NULL, 1)$q$);
SELECT t.err('coupon code unique ignoring case', $q$
    INSERT INTO coupons (code, discount_type, discount_value, starts_at, ends_at) VALUES ('save10', 'fixed', 5, now(), now() + interval '1 day')$q$, 'unique');
SELECT t.err('percent coupon above 100 rejected', $q$
    INSERT INTO coupons (code, discount_type, discount_value, starts_at, ends_at) VALUES ('BIG', 'percent', 150, now(), now() + interval '1 day')$q$, 'ck_coupon_percent');
SELECT t.eq('percent discount capped by max_discount', (SELECT coupon_discount(id, 800)::text FROM coupons WHERE code = 'SAVE10'), '50.00');
SELECT t.set('s_c', t.mk_shipment(t.get('cust')));
SELECT t.err('wrong coupon discount rejected', $q$
    INSERT INTO price_quotes (shipment_id, vehicle_type_id, pricing_details, pricing_source, standard_amount, transport_amount,
      amount, coupon_id, coupon_discount_amount, customer_amount, commission_rate, shipment_version, expires_at)
    VALUES (t.get('s_c'), (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), '{}', 'rules', 500, 500, 500,
            (SELECT id FROM coupons WHERE code = 'SAVE10'), 10, 490, 0, (SELECT details_version FROM shipments WHERE id = t.get('s_c')), now() + interval '1 hour')$q$, 'coupon discount must be');
SELECT t.set('q_c', t.mk_quote(t.get('s_c'), 500, (SELECT id FROM coupons WHERE code = 'SAVE10')));
SELECT t.eq('customer pays amount minus coupon', (SELECT amount || '/' || customer_amount FROM price_quotes WHERE id = t.get('q_c')), '500.00/450.00');
SELECT t.ok('accepting redeems the coupon', $q$ SELECT t.accept(t.get('q_c'))$q$);
SELECT t.eq('redemption recorded', (SELECT count(*)::text FROM coupon_redemptions WHERE shipment_id = t.get('s_c') AND cancelled_at IS NULL), '1');
SELECT t.set('s_c2', t.mk_shipment(t.get('cust2')));
SELECT t.set('q_c2', t.mk_quote(t.get('s_c2'), 500, (SELECT id FROM coupons WHERE code = 'SAVE10')));
SELECT t.err('coupon with no uses left is rejected', $q$ SELECT t.accept(t.get('q_c2'))$q$, 'no uses left');
SELECT t.ok('withdrawing gives the coupon back', $q$ UPDATE price_quotes SET status = 'withdrawn' WHERE id = t.get('q_c')$q$);
SELECT t.ok('now the other customer can use it', $q$ SELECT t.accept(t.get('q_c2'))$q$);
SELECT t.set('s_c3', t.mk_shipment(t.get('cust')));
SELECT t.err('expired coupon rejected', $q$ SELECT t.accept(t.mk_quote(t.get('s_c3'), 500, (SELECT id FROM coupons WHERE code = 'OLD')))$q$, 'not active');
SELECT t.err('below minimum order rejected', $q$ SELECT t.accept(t.mk_quote(t.get('s_c3'), 90, (SELECT id FROM coupons WHERE code = 'SAVE10')))$q$, 'needs an order|no uses left');
SELECT t.err('redemptions cannot be written by hand', $q$
    INSERT INTO coupon_redemptions (coupon_id, customer_id, shipment_id, price_quote_id, discount_amount)
    SELECT coupon_id, t.get('cust2'), t.get('s_c2'), t.get('q_c2'), 1 FROM price_quotes WHERE id = t.get('q_c2')$q$, 'written automatically');

SELECT t.section('customer wallet');
SELECT t.eq('top-up credited after admin verification', t.cbal(t.get('cust')), '5000.00');
SELECT t.err('top-up below minimum', $q$ INSERT INTO customer_topups (customer_id, amount, proof_storage_key) VALUES (t.get('cust'), 10, 'r')$q$, 'between');
SELECT t.err('top-up above maximum', $q$ INSERT INTO customer_topups (customer_id, amount, proof_storage_key) VALUES (t.get('cust'), 20000, 'r')$q$, 'between');
SELECT t.ok('rejected top-up does not credit', $q$
    INSERT INTO customer_topups (customer_id, amount, proof_storage_key) VALUES (t.get('cust2'), 100, 'r');
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE customer_topups SET status = 'rejected', rejection_reason = 'Fake receipt' WHERE customer_id = t.get('cust2') AND status = 'awaiting_verification';
    SELECT t.sys()$q$);
SELECT t.eq('cust2 balance still 0', t.cbal(t.get('cust2')), '0.00');
SELECT t.err('a decided top-up is final', $q$ UPDATE customer_topups SET status = 'verified' WHERE customer_id = t.get('cust2')$q$, 'already');
SELECT t.err('wallet entries are automatic (no hand-written top_up)', $q$
    INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, topup_id) SELECT t.get('cust'), 'top_up', 100, min(id) FROM customer_topups$q$, 'written automatically');
SELECT t.err('customer wallet is append-only', $q$ UPDATE customer_wallet_transactions SET amount = 1$q$, 'append-only');
SELECT t.ok('manual adjustment by admin with a note', $q$
    INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, created_by, note) VALUES (t.get('cust2'), 'manual_adjustment', 30, t.get('admin'), 'Goodwill')$q$);
SELECT t.eq('balance after adjustment', t.cbal(t.get('cust2')), '30.00');

SELECT t.set('s_w', t.mk_shipment(t.get('cust2'), 'wallet'));
SELECT t.ok('quote accepted', $q$ SELECT t.accept(t.mk_quote(t.get('s_w'), 500))$q$);
SELECT t.err('wallet request blocked when balance is too low', $q$ SELECT t.request(t.get('s_w'))$q$, 'insufficient wallet balance');
SELECT t.set('s_w2', t.ready_shipment(t.get('cust'), 'wallet', 500));
SELECT t.eq('wallet charged at request time', t.cbal(t.get('cust')), '4500.00');
SELECT t.eq('payment row paid', (SELECT status || '/' || amount FROM payments WHERE shipment_id = t.get('s_w2')), 'paid/500.00');
SELECT t.err('wallet payments are automatic', $q$
    INSERT INTO payments (shipment_id, price_quote_id, method, payer, amount, status)
    SELECT t.get('s_w'), id, 'wallet', 'sender', customer_amount, 'paid' FROM price_quotes WHERE shipment_id = t.get('s_w') AND status = 'accepted'$q$, 'taken automatically|is draft');
SELECT t.err('payments are append-only', $q$ UPDATE payments SET amount = 1 WHERE shipment_id = t.get('s_w2')$q$, 'append-only');
SELECT t.ok('customer cancels before a driver: full refund', $q$
    SELECT t.act(t.get('cust'), 'customer');
    UPDATE shipments SET status = 'cancelled', cancellation_reason = 'Changed my mind' WHERE id = t.get('s_w2');
    SELECT t.sys()$q$);
SELECT t.eq('refund back to wallet', t.cbal(t.get('cust')), '5000.00');
SELECT t.eq('cancellation party inferred = customer', (SELECT cancellation_party FROM shipments WHERE id = t.get('s_w2')), 'customer');
SELECT t.err('cancellation refunds are automatic', $q$
    INSERT INTO refunds (payment_id, shipment_id, reason_type, amount) SELECT id, shipment_id, 'cancellation', 1 FROM payments WHERE shipment_id = t.get('s_w2')$q$, 'automatically|exceed');

SELECT t.err('withdrawal above balance rejected', $q$
    INSERT INTO customer_withdrawals (customer_id, payout_account_id, amount)
    SELECT t.get('cust'), id, 999999 FROM payout_accounts WHERE user_id = t.get('cust') AND superseded_at IS NULL$q$, 'insufficient');
SELECT t.err('withdrawal to someone else''s account rejected', $q$
    INSERT INTO customer_withdrawals (customer_id, payout_account_id, amount)
    SELECT t.get('cust'), id, 10 FROM payout_accounts WHERE user_id = t.get('drv')$q$, 'fk_withdrawal_account_of_customer');
SELECT t.ok('withdrawal requested and paid', $q$
    INSERT INTO customer_withdrawals (customer_id, payout_account_id, amount)
    SELECT t.get('cust'), id, 1000 FROM payout_accounts WHERE user_id = t.get('cust') AND superseded_at IS NULL;
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE customer_withdrawals SET status = 'paid', transfer_reference = 'TX-1' WHERE customer_id = t.get('cust') AND status = 'requested';
    SELECT t.sys()$q$);
SELECT t.eq('balance after withdrawal', t.cbal(t.get('cust')), '4000.00');
SELECT t.err('withdrawal to an unapproved account cannot be paid', $q$
    INSERT INTO payout_accounts (user_id, method, holder_name, account_number) VALUES (t.get('cust2'), 'wallet', 'Laila', '0122');
    INSERT INTO customer_withdrawals (customer_id, payout_account_id, amount)
    SELECT t.get('cust2'), id, 10 FROM payout_accounts WHERE user_id = t.get('cust2') AND superseded_at IS NULL;
    UPDATE customer_withdrawals SET status = 'paid', transfer_reference = 'TX-2', processed_by = t.get('admin') WHERE customer_id = t.get('cust2')$q$, 'not the current approved');

SELECT t.section('group orders');
SELECT t.set('g1', t.mk_group(t.get('cust'), 1));
SELECT t.set('g1a', t.mk_shipment(t.get('cust'), 'wallet', 0, t.get('g1'), 1));
SELECT t.set('g1b', t.mk_shipment(t.get('cust'), 'wallet', 0, t.get('g1'), 2));
SELECT t.eq('group pickup copied into each shipment', (SELECT pickup_address || '|' || helpers_count FROM shipments WHERE id = t.get('g1b')), 'Warehouse, Nasr City|1');
SELECT t.err('group shipment must belong to the same customer', $q$ SELECT t.mk_shipment(t.get('cust2'), 'wallet', 0, t.get('g1'), 3)$q$, 'fk_shipment_group_same_customer');
SELECT t.err('group needs a delivery sequence', $q$ SELECT t.mk_shipment(t.get('cust'), 'wallet', 0, t.get('g1'), NULL)$q$, 'ck_shipments_group_sequence');
SELECT t.err('duplicate delivery sequence rejected (deferred)', $q$ SELECT t.mk_shipment(t.get('cust'), 'wallet', 0, t.get('g1'), 2)$q$, 'uq_shipments_group_sequence');
SELECT t.ok('swap delivery order in one transaction', $q$
    UPDATE shipments SET delivery_sequence = 2 WHERE id = t.get('g1a');
    UPDATE shipments SET delivery_sequence = 1 WHERE id = t.get('g1b')$q$);
SELECT t.err('max drop-offs per group', $q$
    UPDATE platform_settings SET max_group_stops = 2;
    SELECT t.mk_shipment(t.get('cust'), 'wallet', 0, t.get('g1'), 3)$q$, 'maximum number of drop-offs');
SELECT t.err('group helpers split across drop-offs are rejected: each drop-off pays its own', $q$
    SELECT t.mk_quote(t.get('g1a'), 400, NULL, 'rules', NULL, 0, 20, 75)$q$, 'helpers amount must be');
SELECT t.err('group priced for two vehicle types is rejected (one truck)', $q$
    SELECT t.accept(t.mk_quote(t.get('g1a'), 400, NULL, 'rules', NULL, 0, 20));
    SELECT t.accept(t.mk_quote(t.get('g1b'), 400, NULL, 'rules', NULL, 0, 20, NULL, 'jumbo'));
    SELECT t.request(t.get('g1a')); SELECT t.request(t.get('g1b'))$q$, 'one vehicle type');
SELECT t.ok('quotes with group discount (helpers per drop-off: 1 x 150 on each)', $q$
    SELECT t.accept(t.mk_quote(t.get('g1a'), 400, NULL, 'rules', NULL, 0, 20));
    SELECT t.accept(t.mk_quote(t.get('g1b'), 400, NULL, 'rules', NULL, 0, 20))$q$);
SELECT t.eq('each drop-off carries its own helpers fee', (SELECT string_agg(helpers_amount::text, ',') FROM price_quotes q JOIN shipments s ON s.id = q.shipment_id WHERE s.group_id = t.get('g1') AND q.status = 'accepted'), '150.00,150.00');
SELECT t.err('requesting only part of a group is rejected (all at once)', $q$ SELECT t.request(t.get('g1a'))$q$, 'all at once');
SELECT t.ok('requesting the whole group together', $q$ SELECT t.request(t.get('g1a')); SELECT t.request(t.get('g1b'))$q$);
SELECT t.err('group pickup locked after acceptance', $q$ UPDATE shipment_groups SET pickup_address = 'Other' WHERE id = t.get('g1')$q$, 'fixed after');
SELECT t.err('return-trip shipment cannot be a group shipment', $q$
    INSERT INTO return_match_proposals (outbound_trip_id, driver_id, shipment_id, price_quote_id, proposed_pickup_at, proposed_dropoff_at, expires_at)
    SELECT 1, 1, t.get('g1a'), id, now(), now() + interval '1 hour', now() + interval '1 hour' FROM price_quotes WHERE shipment_id = t.get('g1a') AND status = 'accepted'$q$, 'cannot be part of a group');

SELECT t.section('trip assignment');
SELECT t.set('s_h', t.ready_shipment(t.get('cust'), 'wallet', 500, 3));
SELECT t.err('driver who cannot bring 3 helpers is rejected', $q$ SELECT t.assign(t.get('s_h'), t.get('drv'))$q$, 'can provide 2 helpers');
SELECT t.ok('cancel that shipment (customer, before driver)', $q$
    SELECT t.act(t.get('cust'), 'customer'); UPDATE shipments SET status = 'cancelled' WHERE id = t.get('s_h'); SELECT t.sys()$q$);
SELECT t.set('s_x', t.ready_shipment(t.get('cust'), 'wallet', 500));
SELECT t.err('expired driving license blocks the trip', $q$
    UPDATE driver_documents SET superseded_at = NULL WHERE false;
    ALTER TABLE driver_documents DISABLE TRIGGER trg_driver_documents_guard;
    UPDATE driver_documents SET expires_on = current_date - 1 WHERE driver_id = t.get('drv') AND document_type = 'driving_license_front' AND superseded_at IS NULL;
    ALTER TABLE driver_documents ENABLE TRIGGER trg_driver_documents_guard;
    SELECT t.assign(t.get('s_x'), t.get('drv'))$q$, 'missing or expired');
SELECT t.err('expired vehicle license blocks the trip', $q$
    ALTER TABLE vehicle_documents DISABLE TRIGGER trg_vehicle_documents_guard;
    UPDATE vehicle_documents SET expires_on = current_date WHERE vehicle_id = t.vehicle_of(t.get('drv')) AND document_type = 'vehicle_license_front' AND superseded_at IS NULL;
    ALTER TABLE vehicle_documents ENABLE TRIGGER trg_vehicle_documents_guard;
    SELECT t.assign(t.get('s_x'), t.get('drv'))$q$, 'missing or expired');
SELECT t.err('license category too low for the vehicle', $q$
    UPDATE vehicle_types SET min_license_category = 'professional_1' WHERE code = 'quarter_truck';
    SELECT t.assign(t.get('s_x'), t.get('drv'))$q$, 'too low');
SELECT t.err('suspended driver cannot get a trip', $q$
    UPDATE users SET account_status = 'suspended', suspended_at = now(), suspension_reason = 'x' WHERE id = t.get('drv');
    SELECT t.assign(t.get('s_x'), t.get('drv'))$q$, 'not active');
SELECT t.err('trip must use the accepted quote', $q$
    INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount, commission_rate, planned_start_at, planned_end_at)
    SELECT t.get('s_x'), t.get('drv'), t.vehicle_of(t.get('drv')), t.mk_quote(t.get('s_x')), 0, 0, now(), now() + interval '1 hour'$q$, 'accepted quote');
SELECT t.set('tr1', t.assign(t.get('s_x'), t.get('drv')));
SELECT t.eq('fare = quote amount (copied by DB)', (SELECT fare_amount::text FROM trips WHERE id = t.get('tr1')), '500.00');
SELECT t.eq('shipment follows: driver_assigned', (SELECT status FROM shipments WHERE id = t.get('s_x')), 'driver_assigned');
SELECT t.err('second live trip for the same shipment rejected', $q$ SELECT t.assign(t.get('s_x'), t.get('drv2'))$q$, 'not searching|uq_shipment_live_trip');

SELECT t.section('trip flow');
SELECT t.err('cannot skip states', $q$ SELECT t.move(t.get('tr1'), 'loaded')$q$, 'cannot go from');
SELECT t.ok('heading and arriving at pickup', $q$ SELECT t.move(t.get('tr1'), 'heading_to_pickup'); SELECT t.move(t.get('tr1'), 'arrived_at_pickup')$q$);
SELECT t.eq('shipment in_progress', (SELECT status FROM shipments WHERE id = t.get('s_x')), 'in_progress');
SELECT t.err('loaded needs a pickup photo', $q$ SELECT t.move(t.get('tr1'), 'loaded')$q$, 'pickup photo');
SELECT t.err('vehicle fit cannot be set before loading', $q$ UPDATE trips SET vehicle_fit = 'suitable' WHERE id = t.get('tr1')$q$, 'after loading');
SELECT t.ok('photo then loaded', $q$ SELECT t.photo(t.get('tr1'), 'pickup'); SELECT t.move(t.get('tr1'), 'loaded')$q$);
SELECT t.err('leaving needs the vehicle fit answer', $q$ SELECT t.move(t.get('tr1'), 'heading_to_dropoff')$q$, 'vehicle fit');
SELECT t.err('vehicle fit values are fixed', $q$ UPDATE trips SET vehicle_fit = 'ok' WHERE id = t.get('tr1')$q$, 'vehicle_fit');
SELECT t.ok('driver says the truck was too small', $q$ UPDATE trips SET vehicle_fit = 'too_small' WHERE id = t.get('tr1')$q$);
SELECT t.eq('departure_checked_at set by DB', (SELECT (departure_checked_at IS NOT NULL)::text FROM trips WHERE id = t.get('tr1')), 'true');
SELECT t.err('vehicle fit is answered once', $q$ UPDATE trips SET vehicle_fit = 'suitable' WHERE id = t.get('tr1')$q$, 'once');
SELECT t.ok('heading to dropoff', $q$ SELECT t.move(t.get('tr1'), 'heading_to_dropoff')$q$);
SELECT t.err('no delivered straight from on-the-way: needs "arrived"', $q$ SELECT t.move(t.get('tr1'), 'delivered')$q$, 'cannot go from');
SELECT t.err('code cannot be entered before arriving', $q$ SELECT verify_delivery_code(t.get('tr1'), '1234')$q$, 'entered at the drop-off');
SELECT t.ok('arrived at dropoff', $q$ SELECT t.move(t.get('tr1'), 'arrived_at_dropoff')$q$);
SELECT t.eq('wrong code returns false', (SELECT verify_delivery_code(t.get('tr1'), '0000')::text), 'false');
SELECT t.eq('attempt counted', (SELECT delivery_code_attempts::text FROM trips WHERE id = t.get('tr1')), '1');
SELECT t.err('backend cannot edit the counter', $q$ UPDATE trips SET delivery_code_attempts = 0 WHERE id = t.get('tr1')$q$, 'verify_delivery_code');
SELECT t.err('backend cannot mark the code verified', $q$ UPDATE trips SET delivery_code_verified_at = now() WHERE id = t.get('tr1')$q$, 'verify_delivery_code');
SELECT t.err('attempts log is append-only', $q$ UPDATE delivery_code_attempts SET is_correct = true$q$, 'append-only');
SELECT t.err('delivered needs a delivery photo', $q$ SELECT t.move(t.get('tr1'), 'delivered')$q$, 'delivery photo');
SELECT t.err('delivered needs the verified code', $q$ SELECT t.photo(t.get('tr1'), 'delivery'); SELECT t.move(t.get('tr1'), 'delivered')$q$, 'not verified');
SELECT t.eq('right code returns true', (SELECT verify_delivery_code(t.get('tr1'), '1234')::text), 'true');
SELECT t.err('code cannot be re-entered after verification', $q$ SELECT verify_delivery_code(t.get('tr1'), '1234')$q$, 'already verified');
SELECT t.ok('delivered', $q$ SELECT t.photo(t.get('tr1'), 'delivery'); SELECT t.move(t.get('tr1'), 'delivered')$q$);
SELECT t.eq('commission and driver share computed', (SELECT commission_amount || '/' || driver_earning_amount FROM trips WHERE id = t.get('tr1')), '75.00/425.00');
SELECT t.eq('wallet trip: driver earns his share', t.dbal(t.get('drv')), '425.00');
SELECT t.eq('shipment delivered', (SELECT status FROM shipments WHERE id = t.get('s_x')), 'delivered');
SELECT t.err('delivered trip is final', $q$ UPDATE trips SET cancellation_reason = 'x' WHERE id = t.get('tr1')$q$, 'final');
SELECT t.eq('history recorded every state', (SELECT count(*)::text FROM trip_status_history WHERE trip_id = t.get('tr1')), '7');

SELECT t.set('s_lock', t.ready_shipment(t.get('cust'), 'wallet', 300));
SELECT t.set('tr_lock', t.assign(t.get('s_lock'), t.get('drv')));
SELECT t.to_dropoff(t.get('tr_lock'));
SELECT verify_delivery_code(t.get('tr_lock'), '0000') FROM generate_series(1, 5);
SELECT t.err('6th attempt locked', $q$ SELECT verify_delivery_code(t.get('tr_lock'), '1234')$q$, 'locked after too many attempts');
SELECT t.err('a driver cannot reset the counter', $q$ SELECT t.act(t.get('drv'), 'driver'); UPDATE trips SET delivery_code_attempts = 0 WHERE id = t.get('tr_lock')$q$, 'verify_delivery_code');
SELECT t.sys();
SELECT t.err('even an admin cannot reset the counter by hand (only a new code)', $q$
    SELECT t.act(t.get('admin'), 'admin'); UPDATE trips SET delivery_code_attempts = 0 WHERE id = t.get('tr_lock')$q$, 'verify_delivery_code');
SELECT t.sys();
SELECT t.err('a driver cannot issue a new code', $q$
    SELECT t.act(t.get('drv'), 'driver'); UPDATE shipments SET delivery_code = '5678' WHERE id = t.get('s_lock')$q$, 'new one only after');
SELECT t.sys();
SELECT t.ok('admin issues a new code after the attempts ran out', $q$
    SELECT t.act(t.get('admin'), 'admin'); UPDATE shipments SET delivery_code = '5678' WHERE id = t.get('s_lock'); SELECT t.sys()$q$);
SELECT t.eq('the counter went back to 0 with the new code', (SELECT delivery_code_attempts::text FROM trips WHERE id = t.get('tr_lock')), '0');
SELECT t.eq('the old code no longer works', (SELECT verify_delivery_code(t.get('tr_lock'), '1234')::text), 'false');
SELECT t.ok('the new code works and the trip is delivered', $q$
    SELECT verify_delivery_code(t.get('tr_lock'), '5678'); SELECT t.photo(t.get('tr_lock'), 'delivery'); SELECT t.move(t.get('tr_lock'), 'delivered')$q$);

SELECT t.section('cash, coupons and recipient payments');
SELECT t.set('s_cash', t.ready_shipment(t.get('cust2'), 'cash', 500, 0, 'sender', (SELECT id FROM coupons WHERE code = 'FLAT80')));
SELECT t.eq('cash request does not touch the wallet', t.cbal(t.get('cust2')), '30.00');
SELECT t.set('tr_cash', t.assign(t.get('s_cash'), t.get('drv2')));
SELECT t.ok('to pickup', $q$ SELECT t.move(t.get('tr_cash'), 'heading_to_pickup'); SELECT t.move(t.get('tr_cash'), 'arrived_at_pickup'); SELECT t.photo(t.get('tr_cash'), 'pickup')$q$);
SELECT t.err('sender cash must be collected before loading', $q$ SELECT t.move(t.get('tr_cash'), 'loaded')$q$, 'not collected');
SELECT t.err('cash amount must match what the customer pays', $q$
    INSERT INTO payments (shipment_id, price_quote_id, method, payer, amount, status, collected_on_trip_id, collected_by_driver_id, collected_at)
    SELECT t.get('s_cash'), price_quote_id, 'cash', 'sender', 500, 'collected', id, driver_id, now() FROM trips WHERE id = t.get('tr_cash')$q$, 'fk_payment_quote_amount');
SELECT t.err('the payer must match the shipment', $q$
    INSERT INTO payments (shipment_id, price_quote_id, method, payer, amount, status, collected_on_trip_id, collected_by_driver_id, collected_at)
    SELECT t.get('s_cash'), q.id, 'cash', 'recipient', q.customer_amount, 'collected', tr.id, tr.driver_id, now()
    FROM trips tr JOIN price_quotes q ON q.id = tr.price_quote_id WHERE tr.id = t.get('tr_cash')$q$, 'fare is paid by');
SELECT t.ok('collect cash (420 after coupon) and deliver', $q$
    SELECT t.collect(t.get('tr_cash')); SELECT t.move(t.get('tr_cash'), 'loaded');
    UPDATE trips SET vehicle_fit = 'suitable' WHERE id = t.get('tr_cash');
    SELECT t.move(t.get('tr_cash'), 'heading_to_dropoff'); SELECT t.move(t.get('tr_cash'), 'arrived_at_dropoff');
    SELECT t.photo(t.get('tr_cash'), 'delivery'); SELECT verify_delivery_code(t.get('tr_cash'), '1234');
    SELECT t.move(t.get('tr_cash'), 'delivered')$q$);
SELECT t.eq('cash payment amount = after coupon', (SELECT amount::text FROM payments WHERE shipment_id = t.get('s_cash')), '420.00');
SELECT t.eq('cash + coupon: driver owes 75 commission, gets 80 coupon back', t.dbal(t.get('drv2')), '5.00');
SELECT t.eq('wallet entries for the cash trip', (SELECT string_agg(entry_type || ':' || amount, ',' ORDER BY entry_type) FROM wallet_transactions WHERE trip_id = t.get('tr_cash')),
    'commission_charge:-75.00,coupon_compensation:80.00');

SELECT t.set('s_rcp', t.ready_shipment(t.get('cust'), 'cash', 400, 0, 'recipient'));
SELECT t.set('tr_rcp', t.assign(t.get('s_rcp'), t.get('drv2')));
SELECT t.ok('recipient-paid trip loads without collecting', $q$ SELECT t.to_dropoff(t.get('tr_rcp'))$q$);
SELECT t.err('delivered blocked until the recipient pays or refuses', $q$
    SELECT t.photo(t.get('tr_rcp'), 'delivery'); SELECT verify_delivery_code(t.get('tr_rcp'), '1234'); SELECT t.move(t.get('tr_rcp'), 'delivered')$q$, 'cash was not collected');
SELECT t.set('bal_before', (SELECT customer_balance(t.get('cust'))::bigint));
SELECT t.ok('recipient refuses: fare charged to the sender', $q$ SELECT t.collect(t.get('tr_rcp'), 'charged_to_sender')$q$);
SELECT t.eq('sender wallet charged 400', (customer_balance(t.get('cust')) - t.get('bal_before'))::numeric(12,2)::text, '-400.00');
SELECT t.ok('delivery completes', $q$
    SELECT t.photo(t.get('tr_rcp'), 'delivery'); SELECT verify_delivery_code(t.get('tr_rcp'), '1234'); SELECT t.move(t.get('tr_rcp'), 'delivered')$q$);
SELECT t.eq('driver gets his share in the wallet (340)', (SELECT amount::text FROM wallet_transactions WHERE trip_id = t.get('tr_rcp')), '340.00');

SELECT t.section('cancellations');
SELECT t.set('s_lc', t.ready_shipment(t.get('cust'), 'wallet', 600));
SELECT t.set('tr_lc', t.assign(t.get('s_lc'), t.get('drv')));
SELECT t.set('cb', (SELECT customer_balance(t.get('cust'))::bigint));
SELECT t.set('db', (SELECT driver_balance(t.get('drv'))::bigint));
SELECT t.ok('driver on the way, customer cancels (late)', $q$
    SELECT t.move(t.get('tr_lc'), 'heading_to_pickup');
    SELECT t.act(t.get('cust'), 'customer'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('tr_lc'); SELECT t.sys()$q$);
SELECT t.eq('late cancellation: party customer, fee 50', (SELECT cancellation_party || '/' || is_late_cancellation || '/' || cancellation_fee FROM trips WHERE id = t.get('tr_lc')), 'customer/true/50.00');
SELECT t.eq('shipment cancelled too', (SELECT status || '/' || cancellation_party FROM shipments WHERE id = t.get('s_lc')), 'cancelled/customer');
SELECT t.eq('customer: +600 refund -50 fee', (customer_balance(t.get('cust')) - t.get('cb'))::numeric(12,2)::text, '550.00');
SELECT t.eq('driver compensated 50', (driver_balance(t.get('drv')) - t.get('db'))::numeric(12,2)::text, '50.00');

SELECT t.set('s_dc', t.ready_shipment(t.get('cust'), 'wallet', 600));
SELECT t.set('tr_dc', t.assign(t.get('s_dc'), t.get('drv')));
SELECT t.ok('driver cancels', $q$
    SELECT t.move(t.get('tr_dc'), 'heading_to_pickup');
    SELECT t.act(t.get('drv'), 'driver'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('tr_dc'); SELECT t.sys()$q$);
SELECT t.eq('driver cancellation: no fee, shipment back to searching', (SELECT tr.cancellation_party || '/' || tr.cancellation_fee || '/' || s.status
    FROM trips tr JOIN shipments s ON s.id = tr.shipment_id WHERE tr.id = t.get('tr_dc')), 'driver/0.00/searching_driver');
SELECT t.set('tr_dc2', t.assign(t.get('s_dc'), t.get('drv2')));
SELECT t.err('admin must choose who the cancellation is on', $q$
    SELECT t.move(t.get('tr_dc2'), 'heading_to_pickup');
    SELECT t.act(t.get('admin'), 'admin'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('tr_dc2')$q$, 'needs cancellation_party');
SELECT t.sys();
SELECT t.set('cb', (SELECT customer_balance(t.get('cust'))::bigint));
SELECT t.ok('admin cancels on behalf of the customer (late)', $q$
    SELECT t.move(t.get('tr_dc2'), 'heading_to_pickup');
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'customer', cancellation_reason = 'Customer called support' WHERE id = t.get('tr_dc2');
    SELECT t.sys()$q$);
SELECT t.eq('fee still charged when admin cancels for the customer', (SELECT cancellation_fee::text FROM trips WHERE id = t.get('tr_dc2')), '50.00');
SELECT t.eq('customer: +600 -50', (customer_balance(t.get('cust')) - t.get('cb'))::numeric(12,2)::text, '550.00');
SELECT t.set('s_nd', t.ready_shipment(t.get('cust'), 'wallet', 300));
SELECT t.set('cb', (SELECT customer_balance(t.get('cust'))::bigint));
SELECT t.ok('system cancels: no driver found', $q$ UPDATE shipments SET status = 'cancelled', cancellation_reason = 'no_driver_found' WHERE id = t.get('s_nd')$q$);
SELECT t.eq('system cancellation = platform, full refund', (SELECT cancellation_party FROM shipments WHERE id = t.get('s_nd')) || '/' || (customer_balance(t.get('cust')) - t.get('cb'))::numeric(12,2), 'platform/300.00');
SELECT t.err('customer cannot cancel after loading', $q$
    SELECT t.set('tmp', t.assign(t.ready_shipment(t.get('cust'), 'wallet', 300), t.get('drv')));
    SELECT t.move(t.get('tmp'), 'heading_to_pickup'); SELECT t.move(t.get('tmp'), 'arrived_at_pickup');
    SELECT t.photo(t.get('tmp'), 'pickup'); SELECT t.move(t.get('tmp'), 'loaded');
    SELECT t.act(t.get('cust'), 'customer'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('tmp')$q$, 'only an admin');
SELECT t.sys();

SELECT t.set('cust3', t.mk_user('Nour', '+201111111113', ARRAY['customer']));
SELECT t.ok('cash customer cancels late -> negative wallet', $q$
    SELECT t.set('s_neg', t.ready_shipment(t.get('cust3'), 'cash', 300));
    SELECT t.set('tr_neg', t.assign(t.get('s_neg'), t.get('drv')));
    SELECT t.move(t.get('tr_neg'), 'heading_to_pickup');
    SELECT t.act(t.get('cust3'), 'customer'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('tr_neg'); SELECT t.sys()$q$);
SELECT t.eq('negative balance after cash late cancellation', t.cbal(t.get('cust3')), '-50.00');
SELECT t.err('negative balance blocks any new request, even cash', $q$ SELECT t.ready_shipment(t.get('cust3'), 'cash', 300)$q$, 'wallet is negative');
SELECT t.ok('top-up settles the debt', $q$ SELECT t.fund(t.get('cust3'), 100, t.get('admin'))$q$);
SELECT t.ok('then requests work again', $q$ SELECT t.ready_shipment(t.get('cust3'), 'cash', 300)$q$);

SELECT t.section('group trips');
SELECT t.err('another driver for the same group is rejected', $q$
    SELECT t.assign(t.get('g1a'), t.get('drv')); SELECT t.assign(t.get('g1b'), t.get('drv2'))$q$, 'another driver');
SELECT t.err('assigning only part of the group is rejected (deferred)', $q$ SELECT t.assign(t.get('g1a'), t.get('drv'))$q$, 'all at once');
SELECT t.err('group trips on two different vehicles are rejected (loaded once)', $q$
    INSERT INTO vehicles (driver_id, vehicle_type_id, plate_number, make, model, manufacture_year, color)
    VALUES (t.get('drv'), (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), 'P-2ND', 'Isuzu', 'NKR', 2020, 'Blue');
    INSERT INTO vehicle_documents (vehicle_id, document_type, storage_key)
    SELECT (SELECT id FROM vehicles WHERE plate_number = 'P-2ND'), dt, 'v2/' || dt
    FROM unnest(ARRAY['vehicle_license_front', 'vehicle_license_back', 'vehicle_photo_front',
                      'vehicle_photo_side', 'vehicle_photo_rear', 'vehicle_photo_cargo']) AS dt;
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE vehicle_documents SET review_status = 'approved',
           expires_on = CASE WHEN document_type = 'vehicle_license_front' THEN current_date + 365 END
    WHERE vehicle_id = (SELECT id FROM vehicles WHERE plate_number = 'P-2ND');
    UPDATE vehicles SET status = 'active' WHERE plate_number = 'P-2ND';
    SELECT t.sys();
    SELECT t.assign(t.get('g1a'), t.get('drv'));
    INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount, commission_rate, planned_start_at, planned_end_at)
    VALUES (t.get('g1b'), t.get('drv'), (SELECT id FROM vehicles WHERE plate_number = 'P-2ND'),
            (SELECT id FROM price_quotes WHERE shipment_id = t.get('g1b') AND status = 'accepted'), 0, 0, now(), now() + interval '2 hours')$q$,
    'same vehicle');
SELECT t.set('tg_a', t.assign(t.get('g1a'), t.get('drv'))), t.set('tg_b', t.assign(t.get('g1b'), t.get('drv')));
SELECT t.eq('group trips carry the group id', (SELECT count(*)::text FROM trips WHERE group_id = t.get('g1') AND status = 'assigned'), '2');
SELECT t.ok('both group trips execute together (same driver)', $q$
    SELECT t.move(t.get('tg_a'), 'heading_to_pickup'); SELECT t.move(t.get('tg_b'), 'heading_to_pickup')$q$);
SELECT t.err('a normal trip cannot run with them', $q$
    SELECT t.move(t.assign(t.ready_shipment(t.get('cust'), 'wallet', 300), t.get('drv')), 'heading_to_pickup')$q$, 'ex_trips_driver|conflicting');
SELECT t.ok('driver cancels one group trip -> the whole group goes back', $q$
    SELECT t.act(t.get('drv'), 'driver'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('tg_a'); SELECT t.sys()$q$);
SELECT t.eq('both group trips cancelled', (SELECT string_agg(status || ':' || cancellation_party, ',') FROM trips WHERE group_id = t.get('g1')), 'cancelled:driver,cancelled:driver');
SELECT t.eq('both shipments searching again', (SELECT string_agg(DISTINCT status, ',') FROM shipments WHERE group_id = t.get('g1')), 'searching_driver');
SELECT t.err('re-assigning only part of the group is rejected (deferred)', $q$ SELECT t.assign(t.get('g1a'), t.get('drv2'))$q$, 'all at once');
SELECT t.ok('group assigned to the new driver together', $q$
    SELECT t.set('tg2_a', t.assign(t.get('g1a'), t.get('drv2'))), t.set('tg2_b', t.assign(t.get('g1b'), t.get('drv2')))$q$);
SELECT t.ok('group conversation for the group driver', $q$ INSERT INTO conversations (group_id, driver_id) VALUES (t.get('g1'), t.get('drv2'))$q$);
SELECT t.err('group conversation with a driver outside the group', $q$ INSERT INTO conversations (group_id, driver_id) VALUES (t.get('g1'), t.get('d3'))$q$, 'no trip in group');
SELECT t.ok('group customer and driver can chat', $q$
    INSERT INTO messages (conversation_id, sender_id, body) SELECT id, t.get('cust'), 'Gate 3' FROM conversations WHERE group_id = t.get('g1');
    INSERT INTO messages (conversation_id, sender_id, message_type, location) SELECT id, t.get('drv2'), 'location', t.loc(31.3, 30.0) FROM conversations WHERE group_id = t.get('g1')$q$);
SELECT t.err('outsider cannot write in the group chat', $q$
    INSERT INTO messages (conversation_id, sender_id, body) SELECT id, t.get('cust2'), 'hi' FROM conversations WHERE group_id = t.get('g1')$q$, 'not part of conversation');
SELECT t.err('image message needs an attachment', $q$
    INSERT INTO messages (conversation_id, sender_id, message_type) SELECT id, t.get('cust'), 'image' FROM conversations WHERE group_id = t.get('g1')$q$, 'ck_message_content');

SELECT t.section('payouts & settlements');
SELECT t.err('a driver cannot request a payout himself', $q$
    SELECT t.act(t.get('drv'), 'driver');
    INSERT INTO payout_requests (driver_id, payout_account_id, amount)
    SELECT t.get('drv'), id, 100 FROM payout_accounts WHERE user_id = t.get('drv') AND superseded_at IS NULL$q$, 'weekly system job');
SELECT t.sys();
SELECT t.err('payout above the balance rejected', $q$
    INSERT INTO payout_requests (driver_id, payout_account_id, amount)
    SELECT t.get('drv'), id, 999999 FROM payout_accounts WHERE user_id = t.get('drv') AND superseded_at IS NULL$q$, 'insufficient');
SELECT t.set('pay_amt', (SELECT driver_balance(t.get('drv'))::bigint));
SELECT t.ok('weekly job creates the payout (system)', $q$
    INSERT INTO payout_requests (driver_id, payout_account_id, amount)
    SELECT t.get('drv'), id, driver_balance(t.get('drv')) FROM payout_accounts WHERE user_id = t.get('drv') AND superseded_at IS NULL$q$);
SELECT t.err('one open payout per driver', $q$
    INSERT INTO payout_requests (driver_id, payout_account_id, amount)
    SELECT t.get('drv'), id, 1 FROM payout_accounts WHERE user_id = t.get('drv') AND superseded_at IS NULL$q$, 'uq_payout_open_per_driver');
SELECT t.err('cannot pay to a superseded account', $q$
    INSERT INTO payout_accounts (user_id, method, holder_name, account_number) VALUES (t.get('drv'), 'wallet', 'Ahmed', '0155');
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE payout_requests SET status = 'paid', transfer_reference = 'W-1' WHERE driver_id = t.get('drv') AND status = 'requested'$q$, 'not the current approved');
SELECT t.act(t.get('admin'), 'admin');
SELECT t.ok('admin pays the weekly payout', $q$ UPDATE payout_requests SET status = 'paid', transfer_reference = 'W-1' WHERE driver_id = t.get('drv') AND status = 'requested'$q$);
SELECT t.sys();
SELECT t.eq('driver balance zero after payout', t.dbal(t.get('drv')), '0.00');
SELECT t.err('driver wallet entries are automatic', $q$
    INSERT INTO wallet_transactions (driver_id, entry_type, amount, trip_id) VALUES (t.get('drv'), 'trip_earning', 10, t.get('tr1'))$q$, 'written automatically');
SELECT t.err('driver wallet is append-only', $q$ DELETE FROM wallet_transactions$q$, 'permanent record');
SELECT t.ok('debt settlement verified by admin', $q$
    INSERT INTO driver_settlements (driver_id, amount, proof_storage_key) VALUES (t.get('drv2'), 100, 'rcpt');
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE driver_settlements SET status = 'verified', transfer_reference = 'IP-S1' WHERE driver_id = t.get('drv2');
    SELECT t.sys()$q$);
SELECT t.eq('settlement credited with verifier', (SELECT entry_type || ':' || amount || ':' || (created_by = t.get('admin')) FROM wallet_transactions WHERE driver_id = t.get('drv2') AND entry_type = 'debt_settlement'), 'debt_settlement:100.00:true');

SELECT t.section('disputes & refunds');
SELECT t.err('only a trip party can open a dispute', $q$
    INSERT INTO disputes (trip_id, shipment_id, opened_by, reason, description)
    SELECT id, shipment_id, t.get('cust2'), 'damaged_items', 'x' FROM trips WHERE id = t.get('tr1')$q$, 'not a party');
SELECT t.err('requested amount cannot exceed the payment', $q$
    INSERT INTO disputes (trip_id, shipment_id, opened_by, reason, description, requested_resolution, requested_amount)
    SELECT id, shipment_id, t.get('cust'), 'damaged_items', 'x', 'partial_refund', 9999 FROM trips WHERE id = t.get('tr1')$q$, 'more than the paid');
SELECT t.err('partial refund needs an amount', $q$
    INSERT INTO disputes (trip_id, shipment_id, opened_by, reason, description, requested_resolution)
    SELECT id, shipment_id, t.get('cust'), 'damaged_items', 'x', 'partial_refund' FROM trips WHERE id = t.get('tr1')$q$, 'ck_dispute_requested_amount');
SELECT t.ok('customer opens a dispute', $q$
    INSERT INTO disputes (trip_id, shipment_id, opened_by, reason, description, requested_resolution, requested_amount)
    SELECT id, shipment_id, t.get('cust'), 'damaged_items', 'Scratched washing machine', 'partial_refund', 150 FROM trips WHERE id = t.get('tr1')$q$);
SELECT t.set('dsp', (SELECT max(id) FROM disputes));
SELECT t.eq('response deadline = 24h', (SELECT (response_due_at BETWEEN now() + interval '23 hours' AND now() + interval '25 hours')::text FROM disputes WHERE id = t.get('dsp')), 'true');
SELECT t.err('one open dispute per trip', $q$
    INSERT INTO disputes (trip_id, shipment_id, opened_by, reason, description)
    SELECT id, shipment_id, t.get('cust'), 'late_delivery', 'late' FROM trips WHERE id = t.get('tr1')$q$, 'uq_dispute_open_per_trip');
SELECT t.ok('evidence from the customer', $q$ INSERT INTO dispute_evidence (dispute_id, uploaded_by, storage_key) VALUES (t.get('dsp'), t.get('cust'), 'ev1')$q$);
SELECT t.err('evidence from an outsider', $q$ INSERT INTO dispute_evidence (dispute_id, uploaded_by, storage_key) VALUES (t.get('dsp'), t.get('cust2'), 'ev2')$q$, 'not a party');
SELECT t.act(t.get('admin'), 'admin');
SELECT t.err('dispute owner must be an admin', $q$ UPDATE disputes SET assigned_to = t.get('cust2') WHERE id = t.get('dsp')$q$, 'must be an admin');
SELECT t.ok('admin asks the driver to respond', $q$
    UPDATE disputes SET status = 'awaiting_response', assigned_to = t.get('admin'), priority = 'high' WHERE id = t.get('dsp');
    INSERT INTO dispute_events (dispute_id, event_type, note) VALUES (t.get('dsp'), 'evidence_requested', 'Please share pickup photos')$q$);
SELECT t.err('automatic event types cannot be written by hand', $q$ INSERT INTO dispute_events (dispute_id, event_type) VALUES (t.get('dsp'), 'resolved')$q$, 'recorded automatically');
SELECT t.err('the customer cannot answer her own dispute', $q$
    SELECT t.act(t.get('cust'), 'customer'); UPDATE disputes SET respondent_statement = 'me' WHERE id = t.get('dsp')$q$, 'only the other party');
SELECT t.act(t.get('drv'), 'driver');
SELECT t.ok('the driver responds', $q$ UPDATE disputes SET respondent_statement = 'It was wrapped at pickup' WHERE id = t.get('dsp')$q$);
SELECT t.err('respond only once', $q$ UPDATE disputes SET respondent_statement = 'again' WHERE id = t.get('dsp')$q$, 'already has a response');
SELECT t.act(t.get('admin'), 'admin');
SELECT t.err('complaint text cannot change', $q$ UPDATE disputes SET description = 'edited' WHERE id = t.get('dsp')$q$, 'cannot change');
SELECT t.err('refund needs who bears it', $q$
    UPDATE disputes SET status = 'resolved', resolution = 'split', customer_amount = 150, driver_amount = 350 WHERE id = t.get('dsp')$q$, 'ck_dispute_customer_refund');
SELECT t.err('customer amount cannot exceed the payment', $q$
    UPDATE disputes SET status = 'resolved', resolution = 'refund_customer', customer_amount = 900, refund_borne_by = 'driver' WHERE id = t.get('dsp')$q$, 'more than the paid');
SELECT t.ok('resolved: split, refund borne by the driver', $q$
    UPDATE disputes SET status = 'resolved', resolution = 'split', customer_amount = 150, driver_amount = 350, refund_borne_by = 'driver'
    WHERE id = t.get('dsp')$q$);
SELECT t.eq('resolver from the actor', (SELECT (resolved_by = t.get('admin'))::text FROM disputes WHERE id = t.get('dsp')), 'true');
SELECT t.err('resolved dispute is final', $q$ UPDATE disputes SET admin_notes = 'x' WHERE id = t.get('dsp')$q$, 'final');
SELECT t.err('no evidence after closing', $q$ INSERT INTO dispute_evidence (dispute_id, uploaded_by, storage_key) VALUES (t.get('dsp'), t.get('cust'), 'late')$q$, 'closed');
SELECT t.eq('timeline recorded', (SELECT string_agg(event_type, ',' ORDER BY id) FROM dispute_events WHERE dispute_id = t.get('dsp')),
    'opened,evidence_added,status_changed,evidence_requested,response_added,resolved');
SELECT t.set('cb', (SELECT customer_balance(t.get('cust'))::bigint));
SELECT t.set('db', (SELECT driver_balance(t.get('drv'))::bigint));
SELECT t.err('refund above the decision rejected', $q$
    INSERT INTO refunds (payment_id, shipment_id, reason_type, dispute_id, amount)
    SELECT p.id, p.shipment_id, 'dispute', t.get('dsp'), 200 FROM payments p JOIN trips tr ON tr.shipment_id = p.shipment_id WHERE tr.id = t.get('tr1')$q$, 'exceed the dispute decision');
SELECT t.ok('refund 150 by the admin', $q$
    INSERT INTO refunds (payment_id, shipment_id, reason_type, dispute_id, amount)
    SELECT p.id, p.shipment_id, 'dispute', t.get('dsp'), 150 FROM payments p JOIN trips tr ON tr.shipment_id = p.shipment_id WHERE tr.id = t.get('tr1')$q$);
SELECT t.eq('refund lands in the customer wallet', (customer_balance(t.get('cust')) - t.get('cb'))::numeric(12,2)::text, '150.00');
SELECT t.eq('and is charged to the driver', (driver_balance(t.get('drv')) - t.get('db'))::numeric(12,2)::text, '-150.00');
SELECT t.err('refunds are append-only', $q$ UPDATE refunds SET amount = 1$q$, 'append-only');
SELECT t.sys();

SELECT t.ok('platform-borne refund does not touch the driver', $q$
    INSERT INTO disputes (trip_id, shipment_id, opened_by, reason, description)
    SELECT id, shipment_id, t.get('cust'), 'late_delivery', 'Late' FROM trips WHERE id = t.get('tr_lock');
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE disputes SET status = 'resolved', resolution = 'refund_customer', customer_amount = 100, refund_borne_by = 'platform'
    WHERE trip_id = t.get('tr_lock');
    SELECT t.set('db', (SELECT driver_balance(t.get('drv'))::bigint));
    INSERT INTO refunds (payment_id, shipment_id, reason_type, dispute_id, amount)
    SELECT p.id, p.shipment_id, 'dispute', d.id, 100 FROM disputes d JOIN payments p ON p.shipment_id = d.shipment_id WHERE d.trip_id = t.get('tr_lock');
    SELECT t.sys()$q$);
SELECT t.eq('driver balance unchanged', (driver_balance(t.get('drv')) - t.get('db'))::numeric(12,2)::text, '0.00');

SELECT t.ok('driver opens a complaint about the customer', $q$
    INSERT INTO disputes (trip_id, shipment_id, opened_by, reason, description)
    SELECT id, shipment_id, t.get('drv2'), 'customer_behavior', 'Kept me waiting 2 hours' FROM trips WHERE id = t.get('tr_cash')$q$);
SELECT t.act(t.get('admin'), 'admin');
SELECT t.err('driver complaints cannot refund money', $q$
    UPDATE disputes SET status = 'resolved', resolution = 'release_to_driver' WHERE trip_id = t.get('tr_cash')$q$, 'without money');
SELECT t.ok('resolved with no financial action', $q$
    UPDATE disputes SET status = 'resolved', resolution = 'no_financial_action' WHERE trip_id = t.get('tr_cash')$q$);
SELECT t.sys();

SELECT t.section('reviews');
SELECT t.err('no review before delivery', $q$
    INSERT INTO reviews (trip_id, reviewer_id, reviewee_id, rating) SELECT id, t.get('cust'), t.get('drv2'), 5 FROM trips WHERE id = t.get('tg2_a')$q$, 'not delivered');
SELECT t.ok('customer rates driver with 3 ratings', $q$
    INSERT INTO reviews (trip_id, reviewer_id, reviewee_id, rating, vehicle_rating, service_rating) VALUES (t.get('tr1'), t.get('cust'), t.get('drv'), 5, 4, 5)$q$);
SELECT t.err('driver cannot give vehicle/service ratings', $q$
    INSERT INTO reviews (trip_id, reviewer_id, reviewee_id, rating, vehicle_rating) VALUES (t.get('tr1'), t.get('drv'), t.get('cust'), 4, 4)$q$, 'customer only');
SELECT t.ok('driver rates the customer', $q$ INSERT INTO reviews (trip_id, reviewer_id, reviewee_id, rating) VALUES (t.get('tr1'), t.get('drv'), t.get('cust'), 4)$q$);
SELECT t.err('outsider cannot review', $q$ INSERT INTO reviews (trip_id, reviewer_id, reviewee_id, rating) VALUES (t.get('tr1'), t.get('cust2'), t.get('drv'), 1)$q$, 'between the customer and the driver');
SELECT t.ok('customer picks a customer->driver tag', $q$
    INSERT INTO review_tag_selections (review_id, tag_id)
    SELECT r.id, g.id FROM reviews r, review_tags g WHERE r.trip_id = t.get('tr1') AND r.reviewer_id = t.get('cust') AND g.code = 'professional'$q$);
SELECT t.err('customer cannot pick a driver->customer tag', $q$
    INSERT INTO review_tag_selections (review_id, tag_id)
    SELECT r.id, g.id FROM reviews r, review_tags g WHERE r.trip_id = t.get('tr1') AND r.reviewer_id = t.get('cust') AND g.code = 'paid_on_time'$q$, 'not an active');
SELECT t.eq('average rating view', (SELECT average_rating::text FROM user_ratings WHERE user_id = t.get('drv')), '5.00');

SELECT t.section('support tickets');
SELECT t.err('safety tickets are always high priority', $q$
    INSERT INTO support_tickets (user_id, user_role, opened_by, category, priority, subject) VALUES (t.get('cust'), 'customer', t.get('cust'), 'safety', 'normal', 'Unsafe driving')$q$, 'ck_ticket_safety_priority');
SELECT t.err('ticket owner must be an admin', $q$
    INSERT INTO support_tickets (user_id, user_role, opened_by, category, subject, assigned_to) VALUES (t.get('cust'), 'customer', t.get('cust'), 'other', 'x', t.get('cust2'))$q$, 'must be an admin');
SELECT t.ok('customer opens a ticket linked to her trip', $q$
    INSERT INTO support_tickets (user_id, user_role, opened_by, trip_id, category, subject) VALUES (t.get('cust'), 'customer', t.get('cust'), t.get('tr1'), 'trip', 'Question')$q$);
SELECT t.err('ticket on someone else''s trip', $q$
    INSERT INTO support_tickets (user_id, user_role, opened_by, trip_id, category, subject) VALUES (t.get('cust2'), 'customer', t.get('cust2'), t.get('tr1'), 'trip', 'x')$q$, 'not a party');
SELECT t.err('user role must be real', $q$
    INSERT INTO support_tickets (user_id, user_role, opened_by, category, subject) VALUES (t.get('cust'), 'driver', t.get('cust'), 'other', 'x')$q$, 'is not a driver');
SELECT t.ok('admin opens a ticket with a driver ("Contact driver")', $q$
    INSERT INTO support_tickets (user_id, user_role, opened_by, trip_id, category, subject) VALUES (t.get('drv'), 'driver', t.get('admin'), t.get('tr1'), 'trip', 'Truck stopped?')$q$);
SELECT t.err('another customer cannot open a ticket for someone else', $q$
    INSERT INTO support_tickets (user_id, user_role, opened_by, category, subject) VALUES (t.get('cust'), 'customer', t.get('cust2'), 'other', 'x')$q$, 'owner, an admin or the system');
SELECT t.ok('system opens a ticket (code locked)', $q$
    INSERT INTO support_tickets (user_id, user_role, trip_id, category, priority, subject) VALUES (t.get('drv'), 'driver', t.get('tr_lock'), 'trip', 'high', 'Delivery code locked')$q$);
SELECT t.err('a user cannot leave opened_by empty', $q$
    SELECT t.act(t.get('cust'), 'customer');
    INSERT INTO support_tickets (user_id, user_role, category, subject) VALUES (t.get('cust'), 'customer', 'other', 'x')$q$, 'opened_by is required');
SELECT t.sys();
SELECT t.set('tk', (SELECT max(id) FROM support_tickets WHERE user_id = t.get('drv') AND opened_by = t.get('admin')));
SELECT t.ok('driver replies, admin adds an internal note', $q$
    INSERT INTO support_messages (ticket_id, sender_id, body) VALUES (t.get('tk'), t.get('drv'), 'Flat tyre, 20 min');
    INSERT INTO support_messages (ticket_id, sender_id, body, is_internal) VALUES (t.get('tk'), t.get('admin'), 'Watch this driver', true)$q$);
SELECT t.err('only admins write internal notes', $q$ INSERT INTO support_messages (ticket_id, sender_id, body, is_internal) VALUES (t.get('tk'), t.get('drv'), 'x', true)$q$, 'admins only');
SELECT t.err('outsider cannot write in the ticket', $q$ INSERT INTO support_messages (ticket_id, sender_id, body) VALUES (t.get('tk'), t.get('cust2'), 'x')$q$, 'cannot write');
SELECT t.err('messages cannot be edited', $q$ UPDATE support_messages SET body = 'edited' WHERE ticket_id = t.get('tk')$q$, 'cannot be edited');
SELECT t.ok('marking a message read is allowed', $q$ UPDATE support_messages SET read_at = now() WHERE ticket_id = t.get('tk')$q$);
SELECT t.ok('close the ticket', $q$ UPDATE support_tickets SET status = 'closed' WHERE id = t.get('tk')$q$);
SELECT t.err('no messages on a closed ticket', $q$ INSERT INTO support_messages (ticket_id, sender_id, body) VALUES (t.get('tk'), t.get('drv'), 'x')$q$, 'closed');

SELECT t.section('share links');
SELECT t.ok('share link for a live trip', $q$
    INSERT INTO trip_share_links (trip_id, token_hash, created_by, expires_at) VALUES (t.get('tg2_a'), 'hash-1', t.get('cust'), now() + interval '1 day')$q$);
SELECT t.err('no link for a finished trip', $q$
    INSERT INTO trip_share_links (trip_id, token_hash, expires_at) VALUES (t.get('tr1'), 'hash-2', now() + interval '1 day')$q$, 'finished');
SELECT t.err('a driver cannot create a share link (customer or system only)', $q$
    INSERT INTO trip_share_links (trip_id, token_hash, created_by, expires_at) VALUES (t.get('tg2_a'), 'hash-3', t.get('drv2'), now() + interval '1 day')$q$, 'only the customer');
SELECT t.ok('the system creates the recipient link', $q$
    INSERT INTO trip_share_links (trip_id, token_hash, expires_at) VALUES (t.get('tg2_a'), 'hash-4', now() + interval '1 day')$q$);
SELECT t.err('token hash is unique', $q$
    INSERT INTO trip_share_links (trip_id, token_hash, expires_at) VALUES (t.get('tg2_a'), 'hash-1', now() + interval '1 day')$q$, 'unique');

SELECT t.section('return trip after a group');
SELECT t.ok('deliver the group (drv2)', $q$ SELECT t.to_dropoff(t.get('tg2_a'))$q$);
SELECT t.ok('return proposal on the last group trip', $q$
    SELECT t.set('s_ret', t.mk_shipment(t.get('cust2'), 'cash'));
    SELECT t.set('q_ret', t.mk_quote(t.get('s_ret'), 500, NULL, 'rules', NULL, 120, 0));
    INSERT INTO return_match_proposals (outbound_trip_id, driver_id, shipment_id, price_quote_id, proposed_pickup_at, proposed_dropoff_at, expires_at)
    VALUES (t.get('tg2_b'), t.get('drv2'), t.get('s_ret'), t.get('q_ret'), now() + interval '3 hours', now() + interval '4 hours',
        now() + interval '1 hour');
    UPDATE return_match_proposals SET driver_response = 'accepted', driver_responded_at = now(),
        customer_response = 'accepted', customer_responded_at = now(), status = 'confirmed' WHERE shipment_id = t.get('s_ret');
    SELECT t.accept(t.get('q_ret')); SELECT t.request(t.get('s_ret'));
    INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount, commission_rate, planned_start_at, planned_end_at, return_match_proposal_id)
    VALUES (t.get('s_ret'), t.get('drv2'), t.vehicle_of(t.get('drv2')), t.get('q_ret'), 0, 0, now() + interval '3 hours', now() + interval '4 hours',
            (SELECT id FROM return_match_proposals WHERE shipment_id = t.get('s_ret')))$q$);
SELECT t.err('return trip cannot start before the whole group is delivered', $q$
    SELECT t.move((SELECT id FROM trips WHERE shipment_id = t.get('s_ret')), 'heading_to_pickup')$q$, 'outbound delivery is finished|conflicting');
SELECT t.ok('finish both group deliveries', $q$
    SELECT t.photo(t.get('tg2_a'), 'delivery'); SELECT verify_delivery_code(t.get('tg2_a'), '1234'); SELECT t.move(t.get('tg2_a'), 'delivered');
    SELECT t.to_dropoff(t.get('tg2_b'))$q$);
SELECT t.err('still blocked while one group stop is open', $q$
    SELECT t.move((SELECT id FROM trips WHERE shipment_id = t.get('s_ret')), 'heading_to_pickup')$q$, 'outbound delivery is finished');
SELECT t.ok('last stop delivered', $q$
    SELECT t.photo(t.get('tg2_b'), 'delivery'); SELECT verify_delivery_code(t.get('tg2_b'), '1234'); SELECT t.move(t.get('tg2_b'), 'delivered')$q$);
SELECT t.ok('now the return trip starts', $q$ SELECT t.move((SELECT id FROM trips WHERE shipment_id = t.get('s_ret')), 'heading_to_pickup')$q$);

SELECT t.section('audit log');
SELECT t.act(t.get('admin'), 'admin');
SELECT t.ok('admin changes the commission', $q$ UPDATE platform_settings SET commission_rate = 0.12$q$);
SELECT t.eq('change logged with before/after', (SELECT before ->> 'commission_rate' || '>' || (after ->> 'commission_rate') || ':' || (actor_id = t.get('admin'))
    FROM admin_audit_log WHERE table_name = 'platform_settings' AND action = 'update' ORDER BY id DESC LIMIT 1), '0.1500>0.1200:true');
SELECT t.ok('restore commission', $q$ UPDATE platform_settings SET commission_rate = 0.15$q$);
SELECT t.sys();
SELECT t.eq('driver approval by admin was logged', (SELECT count(*)::text FROM admin_audit_log WHERE table_name = 'driver_profiles' AND after ->> 'verification_status' = 'approved' AND row_id = t.get('d3')::text), '1');
SELECT t.eq('suspension by admin was logged', (SELECT count(*)::text FROM admin_audit_log WHERE table_name = 'users' AND after ->> 'account_status' = 'suspended' AND row_id = t.get('d3')::text), '1');
SELECT t.ok('driver location updates are not logged', $q$
    SELECT t.act(t.get('admin'), 'admin'); UPDATE driver_profiles SET current_location = t.loc(31.0, 30.0), location_updated_at = now() WHERE user_id = t.get('drv'); SELECT t.sys()$q$);
SELECT t.eq('no log row for a location-only change', (SELECT count(*)::text FROM admin_audit_log WHERE table_name = 'driver_profiles' AND row_id = t.get('drv')::text AND before ? 'current_location'), '0');
SELECT t.ok('a customer editing her own name is not an admin change', $q$
    SELECT t.act(t.get('cust'), 'customer'); UPDATE users SET full_name = 'Mariam A.' WHERE id = t.get('cust'); SELECT t.sys()$q$);
SELECT t.eq('not logged', (SELECT count(*)::text FROM admin_audit_log WHERE table_name = 'users' AND row_id = t.get('cust')::text), '0');
SELECT t.err('audit log is append-only', $q$ UPDATE admin_audit_log SET actor_role = 'x'$q$, 'append-only');
SELECT t.err('audit log cannot be deleted', $q$ DELETE FROM admin_audit_log$q$, 'permanent record');

SELECT t.section('account deletion');
SELECT t.set('cust5', t.mk_user('Rich User', '+201111111115', ARRAY['customer']));
SELECT t.fund(t.get('cust5'), 200, t.get('admin'));
SELECT t.err('deletion blocked with money in the wallet', $q$ UPDATE users SET account_status = 'deleted' WHERE id = t.get('cust5')$q$, 'balance is 200');
SELECT t.err('deletion blocked for a driver with an open dispute or trip', $q$ UPDATE users SET account_status = 'deleted' WHERE id = t.get('drv2')$q$, 'active trip|balance|dispute');
SELECT t.set('cust4', t.mk_user('Temp User', '+201111111114', ARRAY['customer']));
SELECT t.ok('saved place and device before deleting', $q$
    INSERT INTO saved_places (user_id, label, address, location) VALUES (t.get('cust4'), 'Home', 'Dokki', t.loc(31.2, 30.03));
    INSERT INTO user_devices (user_id, fcm_token, platform, app) VALUES (t.get('cust4'), 'tok-4', 'android', 'customer')$q$);
SELECT t.err('saved place label unique ignoring case', $q$
    INSERT INTO saved_places (user_id, label, address, location) VALUES (t.get('cust4'), 'HOME', 'x', t.loc(1, 1))$q$, 'uq_saved_places_label');
SELECT t.ok('delete the account', $q$ UPDATE users SET account_status = 'deleted' WHERE id = t.get('cust4')$q$);
SELECT t.eq('personal data scrubbed', (SELECT full_name || '|' || COALESCE(phone, '-') || '|' || COALESCE(password_hash, '-') FROM users WHERE id = t.get('cust4')), 'Deleted user|-|-');
SELECT t.eq('saved places and devices removed', (SELECT (SELECT count(*) FROM saved_places WHERE user_id = t.get('cust4')) + (SELECT count(*) FROM user_devices WHERE user_id = t.get('cust4')))::text, '0');
SELECT t.ok('the phone number can register again', $q$ SELECT t.mk_user('New Person', '+201111111114', ARRAY['customer'])$q$);
SELECT t.err('a deleted account cannot come back', $q$ UPDATE users SET account_status = 'active' WHERE id = t.get('cust4')$q$, 'deleted and cannot change');

SELECT t.section('permanent records');
SELECT t.err('shipments cannot be deleted', $q$ DELETE FROM shipments WHERE id = t.get('s_x')$q$, 'permanent record');
SELECT t.err('trips cannot be truncated', $q$ TRUNCATE trips CASCADE$q$, 'TRUNCATE is not allowed');
SELECT t.err('coupons cannot be deleted', $q$ DELETE FROM coupons$q$, 'permanent record');
SELECT t.err('support messages cannot be deleted', $q$ DELETE FROM support_messages$q$, 'permanent record');
SELECT t.err('status history is append-only', $q$ UPDATE trip_status_history SET reason = 'x'$q$, 'append-only');
SELECT t.err('settings cannot be deleted', $q$ DELETE FROM platform_settings$q$, 'single row');
SELECT t.ok('cargo items of a draft can be deleted', $q$
    INSERT INTO shipment_items (shipment_id, description) VALUES (t.get('s_cat'), 'Chair');
    DELETE FROM shipment_items WHERE shipment_id = t.get('s_cat')$q$);

SELECT t.section('report indexes');
SELECT t.eq('index on delivered trips exists', (SELECT count(*)::text FROM pg_indexes WHERE indexname = 'ix_trips_delivered_at'), '1');
SELECT t.eq('index on shipment creation exists', (SELECT count(*)::text FROM pg_indexes WHERE indexname = 'ix_shipments_created_at'), '1');
ANALYZE trips; ANALYZE shipments;
SET enable_seqscan = off;
CREATE FUNCTION t.plan(q TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE r TEXT; o TEXT := '';
BEGIN FOR r IN EXECUTE 'EXPLAIN ' || q LOOP o := o || r || E'\n'; END LOOP; RETURN o; END$$;
SELECT t.eq('"delivered today" uses the partial index',
    (SELECT (t.plan($q$ SELECT count(*) FROM trips WHERE status = 'delivered' AND delivered_at >= now() - interval '1 day'$q$) LIKE '%ix_trips_delivered_at%')::text), 'true');
SELECT t.eq('"shipments today" uses the created_at index',
    (SELECT (t.plan($q$ SELECT count(*) FROM shipments WHERE created_at >= now() - interval '1 day'$q$) LIKE '%ix_shipments_created_at%')::text), 'true');
RESET enable_seqscan;

SELECT t.section('extra checks');
SELECT t.set('s_cp', t.ready_shipment(t.get('cust'), 'wallet', 500, 0, 'sender', (SELECT id FROM coupons WHERE code = 'FLAT80')));
SELECT t.ok('cancel a shipment that used a coupon', $q$
    SELECT t.act(t.get('cust'), 'customer'); UPDATE shipments SET status = 'cancelled' WHERE id = t.get('s_cp'); SELECT t.sys()$q$);
SELECT t.eq('coupon returned on cancellation', (SELECT (cancelled_at IS NOT NULL)::text FROM coupon_redemptions WHERE shipment_id = t.get('s_cp')), 'true');
SELECT t.err('a new driver in an inactive city is rejected', $q$
    INSERT INTO cities (code, name_ar, name_en, is_active) VALUES ('alex', 'الإسكندرية', 'Alexandria', false);
    INSERT INTO driver_profiles (user_id, city_id, date_of_birth) VALUES (t.get('cust2'), (SELECT id FROM cities WHERE code = 'alex'), '1990-01-01')$q$, 'not active');
SELECT t.ok('publish a new privacy version', $q$
    INSERT INTO policy_versions (doc_type, version_number, content_ar, content_en, published_at) VALUES ('privacy', 2, 'خصوصية ٢', 'Privacy 2', now() - interval '1 minute')$q$);
SELECT t.err('driver who did not accept the new version cannot submit', $q$
    UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = t.get('d4')$q$, 'accepted_terms');
SELECT t.ok('after accepting the new version the driver can submit', $q$
    INSERT INTO policy_acceptances (user_id, policy_version_id) VALUES (t.get('d4'), latest_policy_version('privacy'));
    UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = t.get('d4')$q$);
SELECT t.err('auto-offline must come after "No signal"', $q$ UPDATE platform_settings SET auto_offline_after_seconds = 60$q$, 'ck_settings_offline_after_stale');
SELECT t.err('AI confidence threshold is between 0 and 1', $q$ UPDATE platform_settings SET ai_low_confidence_threshold = 1.5$q$, 'ai_low_confidence_threshold');
SELECT t.err('AI price cap is at least 1x', $q$ UPDATE platform_settings SET max_dynamic_multiplier = 0.9$q$, 'max_dynamic_multiplier');
SELECT t.err('dispute response hours must be positive', $q$ UPDATE platform_settings SET dispute_response_hours = 0$q$, 'dispute_response_hours');

SELECT t.section('coverage: every table is usable');
SELECT t.set('cov_c', t.mk_user('Coverage Customer', '+201555000001', ARRAY['customer']));
SELECT t.set('cov_d', t.mk_driver('Coverage Driver', '+201555000011'));
SELECT t.approve_driver(t.get('cov_d'), t.get('admin'));

SELECT t.set('cov_s', t.ready_shipment(t.get('cov_c'), 'cash', 300));
SELECT t.ok('offer a shipment to a driver', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
    SELECT t.get('cov_s'), id, t.get('cov_d'), t.vehicle_of(t.get('cov_d')), 1200, now() + interval '30 seconds'
    FROM price_quotes WHERE shipment_id = t.get('cov_s') AND status = 'accepted'$q$);
SELECT t.err('two pending offers of the same shipment to one driver', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
    SELECT t.get('cov_s'), id, t.get('cov_d'), t.vehicle_of(t.get('cov_d')), 1200, now() + interval '30 seconds'
    FROM price_quotes WHERE shipment_id = t.get('cov_s') AND status = 'accepted'$q$, 'uq_offer_pending_per_driver');
SELECT t.err('accepted offer must point to its trip', $q$
    UPDATE dispatch_offers SET response = 'accepted', responded_at = now() WHERE shipment_id = t.get('cov_s')$q$, 'ck_offer_accepted_trip');
SELECT t.ok('driver accepts: trip + offer linked in one step', $q$
    SELECT t.set('cov_t', t.assign(t.get('cov_s'), t.get('cov_d')));
    UPDATE dispatch_offers SET response = 'accepted', responded_at = now(), trip_id = t.get('cov_t') WHERE shipment_id = t.get('cov_s')$q$);
SELECT t.err('a trip is linked to one offer only (not another drivers offer)', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at, response, responded_at, trip_id)
    SELECT t.get('cov_s'), price_quote_id, t.get('drv2'), t.vehicle_of(t.get('drv2')), 900, now() + interval '30 seconds', 'accepted', now(), id
    FROM trips WHERE id = t.get('cov_t')$q$, 'fk_offer_trip_exact_match|dispatch_offers_trip_id_key|not searching|starts as pending');

SELECT t.set('cov_g', t.mk_group(t.get('cov_c'), 0));
SELECT t.set('cov_ga', t.mk_shipment(t.get('cov_c'), 'cash', 0, t.get('cov_g'), 1));
SELECT t.set('cov_gb', t.mk_shipment(t.get('cov_c'), 'cash', 0, t.get('cov_g'), 2));
SELECT t.ok('group draft: editing the group pickup updates its drop-offs', $q$
    UPDATE shipment_groups SET pickup_address = 'Warehouse 2, Nasr City' WHERE id = t.get('cov_g')$q$);
SELECT t.eq('drop-offs follow the group pickup', (SELECT string_agg(DISTINCT pickup_address, ',') FROM shipments WHERE group_id = t.get('cov_g')), 'Warehouse 2, Nasr City');
SELECT t.ok('request the group', $q$
    SELECT t.accept(t.mk_quote(t.get('cov_ga'), 300)); SELECT t.accept(t.mk_quote(t.get('cov_gb'), 300));
    SELECT t.request(t.get('cov_ga')); SELECT t.request(t.get('cov_gb'))$q$);
SELECT t.ok('one offer card for the whole group', $q$
    INSERT INTO dispatch_offers (group_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
    VALUES (t.get('cov_g'), t.get('drv2'), t.vehicle_of(t.get('drv2')), 800, now() + interval '30 seconds')$q$);
SELECT t.err('an offer is for a shipment or a group, not both', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, group_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
    SELECT t.get('cov_ga'), id, t.get('cov_g'), t.get('drv2'), t.vehicle_of(t.get('drv2')), 800, now() + interval '30 seconds'
    FROM price_quotes WHERE shipment_id = t.get('cov_ga') AND status = 'accepted'$q$, 'ck_offer_target');
SELECT t.ok('group offer expires', $q$
    UPDATE dispatch_offers SET response = 'expired' WHERE group_id = t.get('cov_g')$q$);

SELECT t.ok('AI analysis run with a recommendation', $q$
    INSERT INTO cargo_analysis_runs (shipment_id, status, model_version, input_snapshot, recommended_vehicle_type_id, confidence, completed_at)
    VALUES (t.get('cov_s'), 'succeeded', 'cargo-v1', '{"images": 1}', (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), 0.82, now())$q$);
SELECT t.err('failed AI run needs a reason', $q$
    INSERT INTO cargo_analysis_runs (shipment_id, status, model_version, input_snapshot) VALUES (t.get('cov_s'), 'failed', 'cargo-v1', '{}')$q$, 'ck_cargo_analysis_failed');
SELECT t.ok('live tracking point', $q$
    SELECT t.move(t.get('cov_t'), 'heading_to_pickup');
    INSERT INTO trip_location_points (trip_id, location, recorded_at, accuracy_m) VALUES (t.get('cov_t'), t.loc(31.30, 30.05), now(), 8)$q$);
SELECT t.err('tracking points are permanent', $q$ DELETE FROM trip_location_points WHERE trip_id = t.get('cov_t')$q$, 'permanent record');
SELECT t.ok('Excel import with a row that becomes a shipment', $q$
    INSERT INTO shipment_imports (uploaded_by, storage_key, original_filename, total_rows, valid_rows)
    VALUES (t.get('cov_c'), 'xl/1', 'orders.xlsx', 1, 1);
    INSERT INTO shipment_import_rows (import_id, row_number, raw_data, status, shipment_id)
    VALUES ((SELECT max(id) FROM shipment_imports), 1, '{"to": "Maadi"}', 'imported', t.mk_shipment(t.get('cov_c'), 'cash'))$q$);
SELECT t.err('an imported row must point to its shipment', $q$
    INSERT INTO shipment_import_rows (import_id, row_number, raw_data, status) VALUES ((SELECT max(id) FROM shipment_imports), 2, '{}', 'imported')$q$, 'ck_import_row_imported');
SELECT t.ok('login session and notification', $q$
    INSERT INTO auth_sessions (user_id, refresh_token_hash, expires_at) VALUES (t.get('cov_c'), 'rt-hash-1', now() + interval '30 days');
    INSERT INTO notifications (user_id, type, title, body) VALUES (t.get('cov_c'), 'trip', 'Driver on the way', 'Your driver is heading to pickup')$q$);

SELECT t.act(t.get('admin'), 'admin');
SELECT t.ok('admin deactivates a zone and a coupon', $q$
    UPDATE service_zones SET is_active = false WHERE code = 'nasr_city';
    UPDATE coupons SET is_active = false WHERE code = 'FLAT80'$q$);
SELECT t.sys();
SELECT t.eq('deactivation is in the audit log', (SELECT count(*)::text FROM admin_audit_log WHERE table_name IN ('service_zones', 'coupons') AND action = 'update' AND after ? 'is_active'), '2');
SELECT t.set('cov_z', t.mk_shipment(t.get('cov_c'), 'cash'));
SELECT t.eq('new shipments skip the inactive zone (next smallest)', (SELECT z.code FROM shipments s JOIN service_zones z ON z.id = s.pickup_zone_id WHERE s.id = t.get('cov_z')), 'east_cairo');
SELECT t.eq('old shipments keep their zone', (SELECT z.code FROM shipments s JOIN service_zones z ON z.id = s.pickup_zone_id WHERE s.id = t.get('cov_ga')), 'nasr_city');
SELECT t.err('inactive coupon cannot be used', $q$ SELECT t.accept(t.mk_quote(t.mk_shipment(t.get('cov_c'), 'cash'), 500, (SELECT id FROM coupons WHERE code = 'FLAT80')))$q$, 'not active');

SELECT t.section('group fees, new delivery code and cash after cancellation');
SELECT t.set('r4c', t.mk_user('R4 Customer', '+201600000001', ARRAY['customer']));
SELECT t.fund(t.get('r4c'), 5000, t.get('admin'));
SELECT t.set('r4d1', t.mk_driver('R4 Driver 1', '+201600000011')); SELECT t.approve_driver(t.get('r4d1'), t.get('admin'));
SELECT t.set('r4d2', t.mk_driver('R4 Driver 2', '+201600000012')); SELECT t.approve_driver(t.get('r4d2'), t.get('admin'));
SELECT t.set('r4d3', t.mk_driver('R4 Driver 3', '+201600000013')); SELECT t.approve_driver(t.get('r4d3'), t.get('admin'));
SELECT t.set('r4d4', t.mk_driver('R4 Driver 4', '+201600000014')); SELECT t.approve_driver(t.get('r4d4'), t.get('admin'));

SELECT t.set('r4g', t.mk_group(t.get('r4c'), 0));
SELECT t.set('r4ga', t.mk_shipment(t.get('r4c'), 'wallet', 0, t.get('r4g'), 1));
SELECT t.set('r4gb', t.mk_shipment(t.get('r4c'), 'wallet', 0, t.get('r4g'), 2));
SELECT t.accept(t.mk_quote(t.get('r4ga'), 300)); SELECT t.accept(t.mk_quote(t.get('r4gb'), 300));
SELECT t.request(t.get('r4ga')), t.request(t.get('r4gb'));
SELECT t.set('r4ta', t.assign(t.get('r4ga'), t.get('r4d1'))), t.set('r4tb', t.assign(t.get('r4gb'), t.get('r4d1')));
SELECT t.move(t.get('r4ta'), 'heading_to_pickup'); SELECT t.move(t.get('r4tb'), 'heading_to_pickup');
SELECT t.ok('customer cancels both drop-offs late', $q$
    SELECT t.act(t.get('r4c'), 'customer');
    UPDATE trips SET status = 'cancelled' WHERE id = t.get('r4ta');
    UPDATE trips SET status = 'cancelled' WHERE id = t.get('r4tb'); SELECT t.sys()$q$);
SELECT t.eq('late fee on each drop-off: 50 + 50', (SELECT sum(cancellation_fee)::text FROM trips WHERE group_id = t.get('r4g')), '100.00');

SELECT t.set('r4c2', t.mk_user('R4 Cash Customer', '+201600000002', ARRAY['customer']));
SELECT t.set('r4s1', t.ready_shipment(t.get('r4c2'), 'cash', 200));
SELECT t.set('r4t1', t.assign(t.get('r4s1'), t.get('r4d2')));
SELECT t.move(t.get('r4t1'), 'heading_to_pickup'); SELECT t.move(t.get('r4t1'), 'arrived_at_pickup'); SELECT t.collect(t.get('r4t1'));
SELECT t.ok('customer cancels after paying 200 cash at pickup', $q$
    SELECT t.act(t.get('r4c2'), 'customer'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('r4t1'); SELECT t.sys()$q$);
SELECT t.eq('the 200 cash comes back as a refund', (SELECT sum(amount)::text FROM refunds WHERE shipment_id = t.get('r4s1')), '200.00');
SELECT t.eq('customer wallet = +200 refund - 50 late fee', customer_balance(t.get('r4c2'))::numeric(12,2)::text, '150.00');
SELECT t.eq('driver wallet = -200 cash he holds + 50 compensation', driver_balance(t.get('r4d2'))::numeric(12,2)::text, '-150.00');
SELECT t.eq('driver entries', (SELECT string_agg(entry_type || ':' || amount, ',' ORDER BY id) FROM wallet_transactions WHERE driver_id = t.get('r4d2')), 'collected_cash_charge:-200.00,cancellation_compensation:50.00');

SELECT t.set('r4c3', t.mk_user('R4 Cash Customer 2', '+201600000003', ARRAY['customer']));
SELECT t.set('r4s2', t.ready_shipment(t.get('r4c3'), 'cash', 200));
SELECT t.set('r4t2', t.assign(t.get('r4s2'), t.get('r4d3')));
SELECT t.move(t.get('r4t2'), 'heading_to_pickup'); SELECT t.move(t.get('r4t2'), 'arrived_at_pickup'); SELECT t.collect(t.get('r4t2'));
SELECT t.ok('driver cancels after collecting the cash', $q$
    SELECT t.act(t.get('r4d3'), 'driver'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('r4t2'); SELECT t.sys()$q$);
SELECT t.eq('shipment searches again, cash refunded, driver charged', (SELECT status FROM shipments WHERE id = t.get('r4s2')) || '/' || customer_balance(t.get('r4c3'))::numeric(12,2) || '/' || driver_balance(t.get('r4d3'))::numeric(12,2), 'searching_driver/200.00/-200.00');
SELECT t.ok('a new driver collects again, loads and delivers', $q$
    SELECT t.set('r4t2b', t.assign(t.get('r4s2'), t.get('r4d4')));
    SELECT t.deliver(t.get('r4t2b'))$q$);
SELECT t.eq('the delivered trip uses its own cash payment', (SELECT count(*)::text FROM payments WHERE shipment_id = t.get('r4s2')), '2');

SELECT t.set('r4c4', t.mk_user('R4 Wallet Customer', '+201600000004', ARRAY['customer']));
SELECT t.fund(t.get('r4c4'), 5000, t.get('admin'));
INSERT INTO payout_accounts (user_id, method, holder_name, account_number) VALUES (t.get('r4c4'), 'wallet', 'R4 Wallet Customer', '01011111111');
SELECT t.act(t.get('admin'), 'admin'); UPDATE payout_accounts SET review_status = 'approved' WHERE user_id = t.get('r4c4'); SELECT t.sys();
INSERT INTO customer_withdrawals (customer_id, payout_account_id, amount) SELECT t.get('r4c4'), id, 4900 FROM payout_accounts WHERE user_id = t.get('r4c4');
SELECT t.err('a 200 trip is rejected while 4900 is reserved for a withdrawal', $q$ SELECT t.ready_shipment(t.get('r4c4'), 'wallet', 200)$q$, 'insufficient wallet balance: 100');
SELECT t.ok('a 100 trip fits the available 100', $q$ SELECT t.ready_shipment(t.get('r4c4'), 'wallet', 100)$q$);
SELECT t.ok('the withdrawal is still payable', $q$
    SELECT t.act(t.get('admin'), 'admin'); UPDATE customer_withdrawals SET status = 'paid', transfer_reference = 'WD-1' WHERE customer_id = t.get('r4c4'); SELECT t.sys()$q$);

SELECT t.err('verifying a top-up needs the transfer reference', $q$
    INSERT INTO customer_topups (customer_id, amount, proof_storage_key) VALUES (t.get('r4c'), 500, 'r');
    SELECT t.act(t.get('admin'), 'admin'); UPDATE customer_topups SET status = 'verified' WHERE customer_id = t.get('r4c') AND status = 'awaiting_verification'$q$, 'ck_topup_verified_reference');
SELECT t.sys();
SELECT t.err('the same transfer reference cannot be verified twice', $q$
    INSERT INTO customer_topups (customer_id, amount, proof_storage_key, transfer_reference) VALUES (t.get('r4c'), 500, 'r1', 'IP-777'), (t.get('r4c'), 500, 'r1', ' ip-777 ');
    SELECT t.act(t.get('admin'), 'admin'); UPDATE customer_topups SET status = 'verified' WHERE customer_id = t.get('r4c') AND status = 'awaiting_verification'$q$, 'uq_topup_verified_reference');
SELECT t.sys();
SELECT t.err('the same debt settlement reference cannot be verified twice', $q$
    INSERT INTO driver_settlements (driver_id, amount, proof_storage_key, transfer_reference) VALUES (t.get('r4d2'), 50, 'p', 'IP-S9'), (t.get('r4d2'), 50, 'p', 'IP-S9');
    SELECT t.act(t.get('admin'), 'admin'); UPDATE driver_settlements SET status = 'verified' WHERE driver_id = t.get('r4d2')$q$, 'uq_settlement_verified_reference');
SELECT t.sys();

SELECT t.set('r4s6', t.ready_shipment(t.get('r4c'), 'wallet', 400));
SELECT t.set('r4t6', t.assign(t.get('r4s6'), t.get('r4d1')));
SELECT t.deliver(t.get('r4t6'));
INSERT INTO disputes (trip_id, shipment_id, opened_by, reason, description) VALUES (t.get('r4t6'), t.get('r4s6'), t.get('r4c'), 'damaged_items', 'broken');
SELECT t.err('full refund without an amount is rejected (NULL no longer slips through)', $q$
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE disputes SET status = 'resolved', resolution = 'refund_customer', refund_borne_by = 'driver' WHERE trip_id = t.get('r4t6')$q$, 'ck_dispute_customer_refund');
SELECT t.sys();

SELECT t.set('r4d8', t.mk_driver('R4 Expired', '+201600000018'));
SELECT t.act(t.get('r4d8'), 'driver'); UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = t.get('r4d8'); SELECT t.sys();
SELECT t.err('an ID that expired yesterday cannot be approved', $q$
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE driver_documents SET review_status = 'approved', expires_on = current_date - 1 WHERE driver_id = t.get('r4d8') AND document_type = 'national_id_front'$q$, 'expired on');
SELECT t.err('approval lists a missing valid ID', $q$
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE driver_documents SET review_status = 'approved', expires_on = CASE WHEN document_type = 'driving_license_front' THEN current_date + 365 END
    WHERE driver_id = t.get('r4d8') AND document_type <> 'national_id_front';
    UPDATE vehicle_documents SET review_status = 'approved', expires_on = CASE WHEN document_type = 'vehicle_license_front' THEN current_date + 365 END
    WHERE vehicle_id = t.vehicle_of(t.get('r4d8'));
    UPDATE driver_profiles SET verification_status = 'approved' WHERE user_id = t.get('r4d8')$q$, 'national_id_front');
SELECT t.sys();

SELECT t.set('r4s9', t.ready_shipment(t.get('r4c'), 'wallet', 300));
SELECT t.eq('no offer yet = search not started', (SELECT (search_started_at IS NULL)::text FROM shipments WHERE id = t.get('r4s9')), 'true');
SELECT t.ok('backend cannot set the search start by hand (ignored)', $q$ UPDATE shipments SET search_started_at = now() - interval '1 day' WHERE id = t.get('r4s9')$q$);
SELECT t.eq('still empty', (SELECT (search_started_at IS NULL)::text FROM shipments WHERE id = t.get('r4s9')), 'true');
SELECT t.ok('first offer starts the search', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
    SELECT t.get('r4s9'), id, t.get('r4d2'), t.vehicle_of(t.get('r4d2')), 900, now() + interval '30 seconds'
    FROM price_quotes WHERE shipment_id = t.get('r4s9') AND status = 'accepted'$q$);
SELECT t.eq('search_started_at set by the database', (SELECT (search_started_at IS NOT NULL)::text FROM shipments WHERE id = t.get('r4s9')), 'true');
SELECT t.set('r4s9b', t.mk_shipment(t.get('r4c')));
UPDATE shipments SET pickup_type = 'scheduled', pickup_window_start = now() + interval '1 day', pickup_window_end = now() + interval '1 day 1 hour' WHERE id = t.get('r4s9b');
SELECT t.accept(t.mk_quote(t.get('r4s9b'), 300)); SELECT t.request(t.get('r4s9b'));
SELECT t.err('a pickup tomorrow is not offered to drivers now', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
    SELECT t.get('r4s9b'), id, t.get('r4d2'), t.vehicle_of(t.get('r4d2')), 900, now() + interval '30 seconds'
    FROM price_quotes WHERE shipment_id = t.get('r4s9b') AND status = 'accepted'$q$, 'offers start 60 minutes');

SELECT t.set('r4s10', t.mk_shipment(t.get('r4c')));
INSERT INTO price_quotes (shipment_id, vehicle_type_id, pricing_details, pricing_source, standard_amount, transport_amount, amount, customer_amount, commission_rate, shipment_version, expires_at, created_at)
SELECT t.get('r4s10'), (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), '{}', 'rules', 300, 300, 300, 300, 0, details_version, now() - interval '1 hour', now() - interval '2 hours'
FROM shipments WHERE id = t.get('r4s10');
SELECT t.err('an expired quote cannot be accepted, even with an old accepted_at', $q$
    UPDATE price_quotes SET status = 'accepted', accepted_at = now() - interval '90 minutes' WHERE shipment_id = t.get('r4s10')$q$, 'expired at');

SELECT t.err('a customer who did not accept the new version cannot request', $q$ SELECT t.ready_shipment(t.get('cust'), 'wallet', 300)$q$, 'latest terms');
SELECT t.err('a driver who did not accept the new version cannot go online', $q$
    SELECT t.act(t.get('drv2'), 'driver');
    UPDATE driver_profiles SET is_online = false WHERE user_id = t.get('drv2');
    UPDATE driver_profiles SET is_online = true WHERE user_id = t.get('drv2')$q$, 'latest terms');
SELECT t.sys();

SELECT t.act(t.get('admin'), 'admin');
INSERT INTO vehicles (driver_id, vehicle_type_id, plate_number, make, model, manufacture_year, color, status)
VALUES (t.get('r4d2'), (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), 'P-R4-2', 'Isuzu', 'NKR', 2020, 'Blue', 'active');
SELECT t.sys();
SELECT t.ok('driver switches vehicle while online', $q$
    SELECT t.act(t.get('r4d2'), 'driver');
    UPDATE driver_profiles SET active_vehicle_id = (SELECT id FROM vehicles WHERE plate_number = 'P-R4-2') WHERE user_id = t.get('r4d2'); SELECT t.sys()$q$);
SELECT t.eq('old session closed, new one on the new vehicle', (SELECT count(*) FILTER (WHERE ended_at IS NOT NULL) || '/' || bool_and(ended_at IS NOT NULL OR vehicle_id = (SELECT id FROM vehicles WHERE plate_number = 'P-R4-2')) FROM driver_online_sessions WHERE driver_id = t.get('r4d2')), '1/true');

SELECT t.set('r4s14', t.ready_shipment(t.get('r4c'), 'wallet', 300));
SELECT t.set('r4t14', t.assign(t.get('r4s14'), t.get('r4d4')));
SELECT t.move(t.get('r4t14'), 'heading_to_pickup'); SELECT t.move(t.get('r4t14'), 'arrived_at_pickup'); SELECT t.photo(t.get('r4t14'), 'pickup'); SELECT t.move(t.get('r4t14'), 'loaded');
SELECT t.err('the driver cannot cancel with the cargo loaded', $q$
    SELECT t.act(t.get('r4d4'), 'driver'); UPDATE trips SET status = 'cancelled' WHERE id = t.get('r4t14')$q$, 'only an admin');
SELECT t.sys();
SELECT t.ok('an admin can (choosing the party, after documenting the cargo)', $q$
    SELECT t.set('r4_resolution', t.resolve_cargo(t.get('r4t14'), t.get('admin')));
    SELECT t.act(t.get('admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = 'Cargo returned; admin resolution recorded',
           cancellation_ticket_id = t.get('r4_resolution') WHERE id = t.get('r4t14');
    SELECT t.sys()$q$);

SELECT t.set('r4s15', t.mk_shipment(t.get('r4c')));
SELECT t.set('r4v15', (SELECT details_version FROM shipments WHERE id = t.get('r4s15')));
UPDATE shipments SET item_count = 30 WHERE id = t.get('r4s15');
SELECT t.err('an AI quote priced on the old version is rejected', $q$
    INSERT INTO price_quotes (shipment_id, vehicle_type_id, pricing_details, pricing_source, standard_amount, transport_amount, amount, customer_amount, commission_rate, shipment_version, expires_at)
    VALUES (t.get('r4s15'), (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), '{}', 'ai', 300, 300, 300, 300, 0, t.get('r4v15'), now() + interval '1 hour')$q$, 'priced on version');

SELECT t.set('r4s88', t.ready_shipment(t.get('r4c'), 'wallet', 300));
SELECT t.set('r4t88', t.assign(t.get('r4s88'), t.get('r4d1')));
SELECT t.to_dropoff(t.get('r4t88'));
SELECT t.err('an admin cannot change the code before the attempts run out', $q$
    SELECT t.act(t.get('admin'), 'admin'); UPDATE shipments SET delivery_code = '4321' WHERE id = t.get('r4s88')$q$, 'new one only after');
SELECT t.sys();

SELECT t.section('email identity and email OTP');

SELECT t.err('live user needs an email', $q$
    INSERT INTO users (full_name, phone, password_hash) VALUES ('No Mail', '+201700000001', 'h')$q$, 'ck_users_live_credentials');
SELECT t.err('email without @ rejected', $q$
    INSERT INTO users (full_name, phone, email, password_hash) VALUES ('Bad', '+201700000002', 'bad.mail.com', 'h')$q$, 'email_address');
SELECT t.err('email with spaces rejected', $q$
    INSERT INTO users (full_name, phone, email, password_hash) VALUES ('Bad', '+201700000003', 'a b@mail.com', 'h')$q$, 'email_address');
SELECT t.err('email must be stored lowercase (backend lowercases it)', $q$
    INSERT INTO users (full_name, phone, email, password_hash) VALUES ('Upper', '+201700000004', 'Mona@Mail.com', 'h')$q$, 'email_address');
SELECT t.set('d90a', t.mk_user('D90 A', '+201700000010', ARRAY['customer']));
SELECT t.err('same email twice rejected', $q$
    INSERT INTO users (full_name, phone, email, password_hash) VALUES ('Copy', '+201700000011', 'u201700000010@test.wasla', 'h')$q$, 'uq_users_email_ci');

SELECT t.ok('two accounts can share a phone (contact only)', $q$
    INSERT INTO users (full_name, phone, email, password_hash) VALUES ('Same Phone', '+201700000010', 'samephone@test.wasla', 'h')$q$);
SELECT t.err('live user still needs a phone (for calls)', $q$
    INSERT INTO users (full_name, email, password_hash) VALUES ('No Phone', 'nophone@test.wasla', 'h')$q$, 'ck_users_live_credentials');
SELECT t.eq('phone_verified_at column is gone', (SELECT count(*)::text FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'phone_verified_at'), '0');

SELECT t.ok('email verified', $q$ UPDATE users SET email_verified_at = now() WHERE id = t.get('d90a')$q$);
SELECT t.ok('email changed without a new verification', $q$
    UPDATE users SET email = 'd90a.new@test.wasla' WHERE id = t.get('d90a')$q$);
SELECT t.eq('changing the email clears the old verification', (SELECT (email_verified_at IS NULL)::text FROM users WHERE id = t.get('d90a')), 'true');
SELECT t.ok('email changed and verified in one statement (code sent to the new email)', $q$
    UPDATE users SET email = 'd90a.final@test.wasla', email_verified_at = now() WHERE id = t.get('d90a')$q$);
SELECT t.eq('verification kept when it is set with the change', (SELECT (email_verified_at IS NOT NULL)::text FROM users WHERE id = t.get('d90a')), 'true');
SELECT t.ok('other edits keep the verification', $q$ UPDATE users SET full_name = 'D90 Renamed' WHERE id = t.get('d90a')$q$);
SELECT t.eq('verification still there', (SELECT (email_verified_at IS NOT NULL)::text FROM users WHERE id = t.get('d90a')), 'true');

SELECT t.ok('delete account', $q$ UPDATE users SET account_status = 'deleted' WHERE id = t.get('d90a')$q$);
SELECT t.eq('deleted user: no email, no verification', (SELECT (email IS NULL AND email_verified_at IS NULL)::text FROM users WHERE id = t.get('d90a')), 'true');
SELECT t.ok('the deleted email can register again', $q$
    INSERT INTO users (full_name, phone, email, password_hash) VALUES ('Back', '+201700000012', 'd90a.final@test.wasla', 'h')$q$);

SELECT t.ok('OTP verify_email', $q$ INSERT INTO otp_codes (email, code_hash, purpose, expires_at)
    VALUES ('back@test.wasla', 'h', 'verify_email', now() + interval '10 min')$q$);
SELECT t.ok('OTP change_email', $q$ INSERT INTO otp_codes (email, code_hash, purpose, expires_at)
    VALUES ('back2@test.wasla', 'h', 'change_email', now() + interval '10 min')$q$);
SELECT t.err('old SMS purpose verify_phone is gone', $q$ INSERT INTO otp_codes (email, code_hash, purpose, expires_at)
    VALUES ('back@test.wasla', 'h', 'verify_phone', now() + interval '10 min')$q$, 'otp_codes_purpose_check');
SELECT t.err('OTP email stored lowercase', $q$ INSERT INTO otp_codes (email, code_hash, purpose, expires_at)
    VALUES ('Back@Test.Wasla', 'h', 'login', now() + interval '10 min')$q$, 'email_address');
SELECT t.eq('otp_codes has no phone column', (SELECT count(*)::text FROM information_schema.columns
    WHERE table_name = 'otp_codes' AND column_name = 'phone'), '0');

SELECT t.section('hardening R01-R09');
SELECT t.set('h_admin', t.mk_user('H Admin', '+201800000001', ARRAY['admin']));
SELECT t.set('h_c', t.mk_user('H Customer', '+201800000002', ARRAY['customer']));
SELECT t.fund(t.get('h_c'), 5000, t.get('h_admin'));
SELECT t.set('h_d1', t.mk_driver('H Driver 1', '+201800000011')); SELECT t.approve_driver(t.get('h_d1'), t.get('h_admin'));
SELECT t.set('h_d2', t.mk_driver('H Driver 2', '+201800000012', 'small_pickup')); SELECT t.approve_driver(t.get('h_d2'), t.get('h_admin'));
SELECT t.set('h_d3', t.mk_driver('H Driver 3', '+201800000013')); SELECT t.approve_driver(t.get('h_d3'), t.get('h_admin'));
SELECT t.set('h_d4', t.mk_driver('H Driver 4', '+201800000014')); SELECT t.approve_driver(t.get('h_d4'), t.get('h_admin'));
SELECT t.set('h_d5', t.mk_driver('H Driver 5', '+201800000015')); SELECT t.approve_driver(t.get('h_d5'), t.get('h_admin'));
SELECT t.set('h_d6', t.mk_driver('H Driver 6', '+201800000016')); SELECT t.approve_driver(t.get('h_d6'), t.get('h_admin'));
SELECT t.set('h_d7', t.mk_driver('H Driver 7', '+201800000017')); SELECT t.approve_driver(t.get('h_d7'), t.get('h_admin'));
SELECT t.set('h_d8', t.mk_driver('H Driver 8', '+201800000018')); SELECT t.approve_driver(t.get('h_d8'), t.get('h_admin'));

SELECT t.err('R01 a customer top-up transfer cannot also confirm a driver settlement', $q$
    INSERT INTO driver_settlements (driver_id, amount, proof_storage_key, transfer_reference)
    SELECT t.get('h_d1'), 100, 'review/same', transfer_reference FROM customer_topups
    WHERE customer_id = t.get('h_c') AND status = 'verified';
    SELECT t.act(t.get('h_admin'), 'admin');
    UPDATE driver_settlements SET status = 'verified' WHERE driver_id = t.get('h_d1') AND status = 'awaiting_verification'$q$,
    'already confirmed for another payment');
SELECT t.sys();
SELECT t.ok('a settlement with its own transfer is confirmed', $q$
    INSERT INTO driver_settlements (driver_id, amount, proof_storage_key, transfer_reference) VALUES (t.get('h_d1'), 100, 'r1', 'H-REF-1');
    SELECT t.act(t.get('h_admin'), 'admin');
    UPDATE driver_settlements SET status = 'verified' WHERE driver_id = t.get('h_d1') AND status = 'awaiting_verification';
    SELECT t.sys()$q$);
SELECT t.err('R01 the other way: a top-up cannot reuse a settlement transfer (spaces and case ignored)', $q$
    INSERT INTO customer_topups (customer_id, amount, proof_storage_key) VALUES (t.get('h_c'), 100, 'r2');
    SELECT t.act(t.get('h_admin'), 'admin');
    UPDATE customer_topups SET status = 'verified', transfer_reference = ' h-ref-1 '
    WHERE customer_id = t.get('h_c') AND status = 'awaiting_verification'$q$, 'already confirmed for another payment');
SELECT t.sys();

SELECT t.err('R08a a settlement cannot be inserted as verified', $q$
    INSERT INTO driver_settlements (driver_id, amount, proof_storage_key, transfer_reference, status, verified_by, verified_at)
    VALUES (t.get('h_d1'), 100, 'r3', 'H-DIRECT', 'verified', t.get('h_admin'), now())$q$, 'starts as awaiting_verification');
SELECT t.err('a top-up cannot be inserted with a reviewer', $q$
    INSERT INTO customer_topups (customer_id, amount, proof_storage_key, verified_by) VALUES (t.get('h_c'), 100, 'r4', t.get('h_admin'))$q$,
    'starts as awaiting_verification');
SELECT t.ok('pending settlement', $q$
    INSERT INTO driver_settlements (driver_id, amount, proof_storage_key) VALUES (t.get('h_d1'), 100, 'review/original-receipt')$q$);
SELECT t.err('R08b a pending settlement amount cannot change', $q$
    UPDATE driver_settlements SET amount = 900 WHERE proof_storage_key = 'review/original-receipt'$q$, 'details cannot change');

SELECT t.set('h_s2', t.ready_shipment(t.get('h_c'), 'wallet', 300));
SELECT t.err('R02 a trip cannot be inserted with the delivery code already verified', $q$
    INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount, commission_rate,
                       planned_start_at, planned_end_at, delivery_code_verified_at)
    SELECT sh.id, t.get('h_d8'), t.vehicle_of(t.get('h_d8')), q.id, 0, 0, now(), now() + interval '2 hours', now()
    FROM shipments sh JOIN price_quotes q ON q.shipment_id = sh.id AND q.status = 'accepted' WHERE sh.id = t.get('h_s2')$q$, 'starts empty');
SELECT t.err('a trip cannot be inserted with its money already split', $q$
    INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount, commission_rate,
                       planned_start_at, planned_end_at, commission_amount, driver_earning_amount)
    SELECT sh.id, t.get('h_d8'), t.vehicle_of(t.get('h_d8')), q.id, 0, 0, now(), now() + interval '2 hours', 1, 1
    FROM shipments sh JOIN price_quotes q ON q.shipment_id = sh.id AND q.status = 'accepted' WHERE sh.id = t.get('h_s2')$q$, 'starts empty');
SELECT t.set('h_t2', t.assign(t.get('h_s2'), t.get('h_d8')));
SELECT t.err('a trip delivery time cannot be written by hand', $q$
    UPDATE trips SET delivered_at = now() WHERE id = t.get('h_t2')$q$, 'set by the database');
SELECT t.err('cancellation details are written only when cancelling', $q$
    UPDATE trips SET cancellation_reason = 'later' WHERE id = t.get('h_t2')$q$, 'only when it is cancelled');

SELECT t.ok('deliver the trip', $q$ SELECT t.deliver(t.get('h_t2'))$q$);
SELECT t.err('R07c a delivery photo cannot be replaced after the trip', $q$
    UPDATE trip_photos SET storage_key = 'review/replaced' WHERE trip_id = t.get('h_t2') AND stage = 'delivery'$q$, 'append-only');
SELECT t.err('no new delivery photo after the trip is delivered', $q$ SELECT t.photo(t.get('h_t2'), 'delivery')$q$, 'photos are taken at');
SELECT t.ok('review', $q$
    INSERT INTO reviews (trip_id, reviewer_id, reviewee_id, rating) VALUES (t.get('h_t2'), t.get('h_c'), t.get('h_d8'), 5)$q$);
SELECT t.err('R07a a review cannot be edited (author or rating)', $q$
    UPDATE reviews SET reviewer_id = t.get('h_admin') WHERE trip_id = t.get('h_t2')$q$, 'append-only');
SELECT t.ok('conversation and message', $q$
    WITH c AS (INSERT INTO conversations (trip_id) VALUES (t.get('h_t2')) RETURNING id) SELECT t.set('h_conv', id) FROM c;
    INSERT INTO messages (conversation_id, sender_id, body) VALUES (t.get('h_conv'), t.get('h_c'), 'Original')$q$);
SELECT t.err('R07b a message sender cannot change', $q$
    UPDATE messages SET sender_id = t.get('h_admin') WHERE conversation_id = t.get('h_conv')$q$, 'cannot be edited');
SELECT t.err('a message text cannot change', $q$
    UPDATE messages SET body = 'Edited' WHERE conversation_id = t.get('h_conv')$q$, 'cannot be edited');
SELECT t.ok('a message is marked as read', $q$ UPDATE messages SET read_at = now() WHERE conversation_id = t.get('h_conv')$q$);
SELECT t.err('read time is set once', $q$
    UPDATE messages SET read_at = now() + interval '1 hour' WHERE conversation_id = t.get('h_conv')$q$, 'cannot be edited');

SELECT t.err('R09a no forged shipment history', $q$
    INSERT INTO shipment_status_history (shipment_id, from_status, to_status, change_source, reason)
    VALUES (t.get('h_s2'), 'in_progress', 'delivered', 'admin', 'forged')$q$, 'written automatically');
SELECT t.err('no forged trip history', $q$
    INSERT INTO trip_status_history (trip_id, from_status, to_status, change_source) VALUES (t.get('h_t2'), 'loaded', 'delivered', 'admin')$q$,
    'written automatically');
SELECT t.err('R09b no invented audit entry', $q$
    INSERT INTO admin_audit_log (actor_id, actor_role, action, table_name, row_id, after)
    VALUES (t.get('h_admin'), 'admin', 'update', 'users', t.get('h_c')::text, '{"full_name": "never"}')$q$, 'written automatically');
SELECT t.ok('real changes still write history and audit', $q$
    SELECT t.act(t.get('h_admin'), 'admin'); UPDATE platform_settings SET cancellation_fee = cancellation_fee; SELECT t.sys()$q$);

SELECT t.set('h_g', t.mk_group(t.get('h_c')));
SELECT t.set('h_g1', t.mk_shipment(t.get('h_c'), 'wallet', 0, t.get('h_g'), 1));
SELECT t.set('h_g2', t.mk_shipment(t.get('h_c'), 'wallet', 0, t.get('h_g'), 2));
SELECT t.accept(t.mk_quote(t.get('h_g1'), 300)); SELECT t.accept(t.mk_quote(t.get('h_g2'), 300));
SELECT t.request(t.get('h_g1')), t.request(t.get('h_g2'));
SELECT t.err('R04 a new drop-off cannot join a requested group', $q$
    SELECT t.mk_shipment(t.get('h_c'), 'wallet', 0, t.get('h_g'), 3)$q$, 'already has an agreed price');

SELECT t.set('h_s5', t.ready_shipment(t.get('h_c'), 'wallet', 300));
SELECT t.err('R05a a small pickup cannot take a quarter-truck price', $q$ SELECT t.assign(t.get('h_s5'), t.get('h_d2'))$q$,
    'vehicle type the price was quoted for');
SELECT t.err('R05a no offer to the wrong vehicle type either', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
    SELECT t.get('h_s5'), id, t.get('h_d2'), t.vehicle_of(t.get('h_d2')), 500, now() + interval '30 seconds'
    FROM price_quotes WHERE shipment_id = t.get('h_s5') AND status = 'accepted'$q$, 'vehicle type the price was quoted for');
SELECT t.set('h_s5b', t.mk_shipment(t.get('h_c')));
UPDATE shipments SET weight_kg = 5000 WHERE id = t.get('h_s5b');
SELECT t.accept(t.mk_quote(t.get('h_s5b'), 300)); SELECT t.request(t.get('h_s5b'));
SELECT t.err('R05b cargo heavier than the vehicle payload', $q$ SELECT t.assign(t.get('h_s5b'), t.get('h_d1'))$q$, 'more than the payload');
SELECT t.err('no offer for cargo heavier than the vehicle', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
    SELECT t.get('h_s5b'), id, t.get('h_d1'), t.vehicle_of(t.get('h_d1')), 500, now() + interval '30 seconds'
    FROM price_quotes WHERE shipment_id = t.get('h_s5b') AND status = 'accepted'$q$, 'more than the payload');
SELECT t.err('an offer cannot be inserted as accepted', $q$
    INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at, response, responded_at)
    SELECT t.get('h_s5'), id, t.get('h_d1'), t.vehicle_of(t.get('h_d1')), 500, now() + interval '30 seconds', 'rejected', now()
    FROM price_quotes WHERE shipment_id = t.get('h_s5') AND status = 'accepted'$q$, 'starts as pending');

SELECT t.set('h_t6a', t.assign(t.get('h_s5'), t.get('h_d3')));
SELECT t.set('h_s6', t.ready_shipment(t.get('h_c'), 'wallet', 300));
SELECT t.set('h_t6b', t.assign(t.get('h_s6'), t.get('h_d4')));
SELECT t.move(t.get('h_t6b'), 'heading_to_pickup');
SELECT t.ok('suspend two drivers', $q$
    SELECT t.act(t.get('h_admin'), 'admin');
    UPDATE users SET account_status = 'suspended', suspended_at = now(), suspension_reason = 'review'
    WHERE id IN (t.get('h_d3'), t.get('h_d4'));
    SELECT t.sys()$q$);
SELECT t.eq('R06a trip not started yet: cancelled on the platform', (SELECT status || '/' || cancellation_party FROM trips WHERE id = t.get('h_t6a')), 'cancelled/platform');
SELECT t.eq('its shipment searches for another driver', (SELECT status FROM shipments WHERE id = t.get('h_s5')), 'searching_driver');
SELECT t.eq('a started trip continues (cargo safety)', (SELECT status FROM trips WHERE id = t.get('h_t6b')), 'heading_to_pickup');

SELECT t.set('h_s6v', t.ready_shipment(t.get('h_c'), 'wallet', 300));
SELECT t.set('h_t6v', t.assign(t.get('h_s6v'), t.get('h_d6')));
SELECT t.ok('vehicle deactivated', $q$
    SELECT t.act(t.get('h_admin'), 'admin'); UPDATE vehicles SET status = 'inactive' WHERE id = t.vehicle_of(t.get('h_d6')); SELECT t.sys()$q$);
SELECT t.eq('R06b its trip not started yet is cancelled', (SELECT status FROM trips WHERE id = t.get('h_t6v')), 'cancelled');
SELECT t.eq('its shipment searches again', (SELECT status FROM shipments WHERE id = t.get('h_s6v')), 'searching_driver');
SELECT t.eq('the driver is offline', (SELECT is_online::text FROM driver_profiles WHERE user_id = t.get('h_d6')), 'false');

SELECT t.set('h_gb', t.mk_group(t.get('h_c')));
SELECT t.set('h_gb1', t.mk_shipment(t.get('h_c'), 'wallet', 0, t.get('h_gb'), 1));
SELECT t.set('h_gb2', t.mk_shipment(t.get('h_c'), 'wallet', 0, t.get('h_gb'), 2));
SELECT t.accept(t.mk_quote(t.get('h_gb1'), 300)); SELECT t.accept(t.mk_quote(t.get('h_gb2'), 300));
SELECT t.request(t.get('h_gb1')), t.request(t.get('h_gb2'));
SELECT t.set('h_tb1', t.assign(t.get('h_gb1'), t.get('h_d5'))), t.set('h_tb2', t.assign(t.get('h_gb2'), t.get('h_d5')));
SELECT t.move(t.get('h_tb1'), 'heading_to_pickup');
SELECT t.ok('suspend the group driver', $q$
    SELECT t.act(t.get('h_admin'), 'admin');
    UPDATE users SET account_status = 'suspended', suspended_at = now(), suspension_reason = 'review' WHERE id = t.get('h_d5');
    SELECT t.sys()$q$);
SELECT t.eq('a group that already started is left to the admin', (SELECT status FROM trips WHERE id = t.get('h_tb2')), 'assigned');
SELECT t.err('R06 a suspended driver cannot start an assigned trip', $q$ SELECT t.move(t.get('h_tb2'), 'heading_to_pickup')$q$, 'is not active');

SELECT t.set('h_s3', t.ready_shipment(t.get('h_c'), 'wallet', 300));
SELECT t.set('h_bal3', (SELECT customer_balance(t.get('h_c')))::bigint);
SELECT t.set('h_t3', t.assign(t.get('h_s3'), t.get('h_d7')));
SELECT t.to_dropoff(t.get('h_t3'));
SELECT t.ok('admin cancels after loading (vehicle broke down, cargo documented)', $q$
    SELECT t.set('h_tk3', t.resolve_cargo(t.get('h_t3'), t.get('h_admin')));
    SELECT t.act(t.get('h_admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = 'vehicle broke down',
           cancellation_ticket_id = t.get('h_tk3')
    WHERE id = t.get('h_t3');
    SELECT t.sys()$q$);
SELECT t.eq('R03 the shipment is cancelled, not searching again', (SELECT status || '/' || cancellation_party FROM shipments WHERE id = t.get('h_s3')), 'cancelled/platform');
SELECT t.eq('the wallet payment came back to the customer',
    (SELECT (customer_balance(t.get('h_c')) - t.get('h_bal3'))::text), (SELECT amount::text FROM payments WHERE shipment_id = t.get('h_s3')));

SELECT t.err('a return proposal cannot be inserted as confirmed', $q$
    INSERT INTO return_match_proposals (outbound_trip_id, driver_id, shipment_id, price_quote_id, proposed_pickup_at, proposed_dropoff_at,
        status, driver_response, customer_response, driver_responded_at, customer_responded_at, expires_at)
    SELECT t.get('h_t2'), t.get('h_d8'), t.get('h_s6'), id, now() + interval '3 hours', now() + interval '4 hours',
        'confirmed', 'accepted', 'accepted', now(), now(), now() + interval '1 hour'
    FROM price_quotes WHERE shipment_id = t.get('h_s6') AND status = 'accepted'$q$, 'starts as pending');
SELECT t.err('no tracking point on a trip that did not move', $q$
    INSERT INTO trip_location_points (trip_id, location, recorded_at) VALUES (t.get('h_tb2'), t.loc(31.3, 30.0), now())$q$, 'not moving');
SELECT t.ok('tracking point on a moving trip', $q$
    INSERT INTO trip_location_points (trip_id, location, recorded_at) VALUES (t.get('h_tb1'), t.loc(31.3, 30.0), now())$q$);
SELECT t.err('tracking points cannot be edited', $q$
    UPDATE trip_location_points SET recorded_at = now() - interval '1 day' WHERE trip_id = t.get('h_tb1')$q$, 'append-only');
SELECT t.err('only the trip driver uploads its photos', $q$
    SELECT t.move(t.get('h_tb1'), 'arrived_at_pickup');
    INSERT INTO trip_photos (trip_id, stage, storage_key, uploaded_by) VALUES (t.get('h_tb1'), 'pickup', 'x', t.get('h_c'))$q$, 'only the driver');
SELECT t.ok('backdated policy acceptance', $q$
    SELECT t.set('h_c9', t.mk_user('H Late', '+201800000099', ARRAY['customer']));
    INSERT INTO policy_versions (doc_type, version_number, content_ar, content_en, published_at)
    SELECT 'terms', max(version_number) + 1, 'شروط', 'Terms', now() - interval '1 minute' FROM policy_versions WHERE doc_type = 'terms';
    INSERT INTO policy_acceptances (user_id, policy_version_id, accepted_at)
    VALUES (t.get('h_c9'), latest_policy_version('terms'), DATE '2020-01-01')$q$);
SELECT t.eq('the acceptance gets the real time, not the one sent',
    (SELECT (accepted_at::date = current_date)::text FROM policy_acceptances WHERE user_id = t.get('h_c9') ORDER BY id DESC LIMIT 1), 'true');

SELECT t.section('vehicle lock, license recheck, group lock and return agreement');
SELECT t.set('i_admin', t.mk_user('I Admin', '+201900000001', ARRAY['admin']));
SELECT t.set('i_c', t.mk_user('I Customer', '+201900000002', ARRAY['customer']));
SELECT t.fund(t.get('i_c'), 5000, t.get('i_admin'));
SELECT t.set('i_d1', t.mk_driver('I Driver 1', '+201900000011')); SELECT t.approve_driver(t.get('i_d1'), t.get('i_admin'));
SELECT t.set('i_d2', t.mk_driver('I Driver 2', '+201900000012')); SELECT t.approve_driver(t.get('i_d2'), t.get('i_admin'));
SELECT t.set('i_d3', t.mk_driver('I Driver 3', '+201900000013')); SELECT t.approve_driver(t.get('i_d3'), t.get('i_admin'));
SELECT t.set('i_d4', t.mk_driver('I Driver 4', '+201900000014')); SELECT t.approve_driver(t.get('i_d4'), t.get('i_admin'));
SELECT t.act(t.get('i_admin'), 'admin');
INSERT INTO vehicles (driver_id, vehicle_type_id, plate_number, make, model, manufacture_year, color, status)
VALUES (t.get('i_d1'), (SELECT id FROM vehicle_types WHERE code = 'quarter_truck'), 'I-2ND', 'Isuzu', 'NKR', 2021, 'Grey', 'active');
INSERT INTO vehicle_documents (vehicle_id, document_type, storage_key)
SELECT (SELECT id FROM vehicles WHERE plate_number = 'I-2ND'), dt, 'i2/' || dt
FROM unnest(ARRAY['vehicle_license_front', 'vehicle_license_back', 'vehicle_photo_front',
                  'vehicle_photo_side', 'vehicle_photo_rear', 'vehicle_photo_cargo']) AS dt;
UPDATE vehicle_documents SET review_status = 'approved',
       expires_on = CASE WHEN document_type = 'vehicle_license_front' THEN current_date + 365 END
WHERE vehicle_id = (SELECT id FROM vehicles WHERE plate_number = 'I-2ND');
SELECT t.sys();
SELECT t.set('i_v2', (SELECT id FROM vehicles WHERE plate_number = 'I-2ND'));

SELECT t.set('i_s0', t.ready_shipment(t.get('i_c'), 'wallet', 300));
SELECT t.err('a trip on a vehicle that is not the active one is rejected', $q$
    INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount, commission_rate, planned_start_at, planned_end_at)
    SELECT t.get('i_s0'), t.get('i_d1'), t.get('i_v2'), id, 0, 0, now(), now() + interval '2 hours'
    FROM price_quotes WHERE shipment_id = t.get('i_s0') AND status = 'accepted'$q$, 'not the active vehicle');

SELECT t.set('i_t1', t.assign(t.ready_shipment(t.get('i_c'), 'wallet', 300), t.get('i_d1')));
SELECT t.ok('switching vehicle while only assigned is allowed', $q$
    SELECT t.act(t.get('i_d1'), 'driver');
    UPDATE driver_profiles SET active_vehicle_id = t.get('i_v2') WHERE user_id = t.get('i_d1'); SELECT t.sys()$q$);
SELECT t.err('but the trip cannot start on a vehicle the driver is not using', $q$
    SELECT t.move(t.get('i_t1'), 'heading_to_pickup')$q$, 'not the active vehicle');
SELECT t.ok('back on the trip vehicle, the trip starts', $q$
    SELECT t.act(t.get('i_d1'), 'driver');
    UPDATE driver_profiles SET active_vehicle_id = t.vehicle_of(t.get('i_d1')) WHERE user_id = t.get('i_d1');
    SELECT t.move(t.get('i_t1'), 'heading_to_pickup')$q$);

SELECT t.err('R10 no vehicle switch in the middle of a trip', $q$
    SELECT t.act(t.get('i_d1'), 'driver');
    UPDATE driver_profiles SET active_vehicle_id = t.get('i_v2') WHERE user_id = t.get('i_d1')$q$, 'middle of a trip');
SELECT t.sys();
SELECT t.ok('finish the trip', $q$
    SELECT t.move(t.get('i_t1'), 'arrived_at_pickup'); SELECT t.photo(t.get('i_t1'), 'pickup'); SELECT t.move(t.get('i_t1'), 'loaded');
    UPDATE trips SET vehicle_fit = 'suitable' WHERE id = t.get('i_t1');
    SELECT t.move(t.get('i_t1'), 'heading_to_dropoff'); SELECT t.move(t.get('i_t1'), 'arrived_at_dropoff');
    SELECT t.photo(t.get('i_t1'), 'delivery'); SELECT verify_delivery_code(t.get('i_t1'), '1234'); SELECT t.move(t.get('i_t1'), 'delivered')$q$);
SELECT t.ok('after the trip the driver can switch', $q$
    SELECT t.act(t.get('i_d1'), 'driver');
    UPDATE driver_profiles SET active_vehicle_id = t.get('i_v2') WHERE user_id = t.get('i_d1');
    UPDATE driver_profiles SET active_vehicle_id = t.vehicle_of(t.get('i_d1')) WHERE user_id = t.get('i_d1'); SELECT t.sys()$q$);

SELECT t.set('i_t2', t.assign(t.ready_shipment(t.get('i_c'), 'wallet', 300), t.get('i_d2')));
SELECT t.err('a license that expired after the assignment blocks the start', $q$
    ALTER TABLE driver_documents DISABLE TRIGGER trg_driver_documents_guard;
    UPDATE driver_documents SET expires_on = current_date WHERE driver_id = t.get('i_d2') AND document_type = 'driving_license_front' AND superseded_at IS NULL;
    ALTER TABLE driver_documents ENABLE TRIGGER trg_driver_documents_guard;
    SELECT t.move(t.get('i_t2'), 'heading_to_pickup')$q$, 'license is missing, expired or too low');
SELECT t.err('a vehicle license that expired after the assignment blocks the start', $q$
    ALTER TABLE vehicle_documents DISABLE TRIGGER trg_vehicle_documents_guard;
    UPDATE vehicle_documents SET expires_on = current_date WHERE vehicle_id = t.vehicle_of(t.get('i_d2')) AND document_type = 'vehicle_license_front' AND superseded_at IS NULL;
    ALTER TABLE vehicle_documents ENABLE TRIGGER trg_vehicle_documents_guard;
    SELECT t.move(t.get('i_t2'), 'heading_to_pickup')$q$, 'vehicle % license|license is missing or expired');
SELECT t.ok('valid licenses: the trip starts', $q$ SELECT t.move(t.get('i_t2'), 'heading_to_pickup')$q$);

SELECT t.set('i_g', t.mk_group(t.get('i_c'), 0));
SELECT t.set('i_ga', t.mk_shipment(t.get('i_c'), 'wallet', 0, t.get('i_g'), 1));
SELECT t.set('i_gb', t.mk_shipment(t.get('i_c'), 'wallet', 0, t.get('i_g'), 2));
SELECT t.set('i_gqa', t.mk_quote(t.get('i_ga'), 300));
SELECT t.accept(t.get('i_gqa'));
SELECT t.err('no new drop-off once one drop-off accepted its price', $q$
    SELECT t.mk_shipment(t.get('i_c'), 'wallet', 0, t.get('i_g'), 3)$q$, 'already has an agreed price');
SELECT t.set('i_loose', t.mk_shipment(t.get('i_c'), 'wallet'));
SELECT t.err('an existing draft cannot move into that group either', $q$
    UPDATE shipments SET group_id = t.get('i_g'), delivery_sequence = 3 WHERE id = t.get('i_loose')$q$, 'already has an agreed price');
SELECT t.ok('withdrawing the price (still draft) opens the group again', $q$
    UPDATE price_quotes SET status = 'withdrawn' WHERE id = t.get('i_gqa');
    SELECT t.mk_shipment(t.get('i_c'), 'wallet', 0, t.get('i_g'), 3)$q$);

SELECT t.set('i_t4', t.assign(t.ready_shipment(t.get('i_c'), 'wallet', 300), t.get('i_d4')));
SELECT t.set('i_rs', t.mk_shipment(t.get('i_c'), 'cash'));
SELECT t.set('i_rq', t.mk_quote(t.get('i_rs'), 400, NULL, 'rules', NULL, 100, 0));
INSERT INTO return_match_proposals (outbound_trip_id, driver_id, shipment_id, price_quote_id, proposed_pickup_at, proposed_dropoff_at, expires_at)
VALUES (t.get('i_t4'), t.get('i_d4'), t.get('i_rs'), t.get('i_rq'), now() + interval '3 hours', now() + interval '4 hours', now() + interval '1 hour');
SELECT t.set('i_rp', (SELECT id FROM return_match_proposals WHERE shipment_id = t.get('i_rs')));
SELECT t.ok('driver accepts (sends an old answer time)', $q$
    UPDATE return_match_proposals SET driver_response = 'accepted', driver_responded_at = now() - interval '3 days' WHERE id = t.get('i_rp')$q$);
SELECT t.eq('the answer time is the real time', (SELECT (driver_responded_at > now() - interval '1 minute')::text FROM return_match_proposals WHERE id = t.get('i_rp')), 'true');
SELECT t.err('the driver cannot change his answer', $q$
    UPDATE return_match_proposals SET driver_response = 'rejected' WHERE id = t.get('i_rp')$q$, 'already answered');
SELECT t.err('the proposal times cannot change', $q$
    UPDATE return_match_proposals SET proposed_dropoff_at = proposed_dropoff_at + interval '1 hour' WHERE id = t.get('i_rp')$q$, 'details cannot change');
SELECT t.ok('customer accepts and the proposal is confirmed', $q$
    UPDATE return_match_proposals SET customer_response = 'accepted', status = 'confirmed' WHERE id = t.get('i_rp')$q$);
SELECT t.err('R12 a confirmed agreement is final', $q$
    UPDATE return_match_proposals SET proposed_dropoff_at = proposed_dropoff_at + interval '1 hour' WHERE id = t.get('i_rp')$q$, 'is confirmed and final');
SELECT t.err('a confirmed proposal cannot be withdrawn by editing', $q$
    UPDATE return_match_proposals SET status = 'withdrawn' WHERE id = t.get('i_rp')$q$, 'final');
SELECT t.set('i_rs2', t.mk_shipment(t.get('i_c'), 'cash'));
SELECT t.set('i_rq2', t.mk_quote(t.get('i_rs2'), 400, NULL, 'rules', NULL, 100, 0));
INSERT INTO return_match_proposals (outbound_trip_id, driver_id, shipment_id, price_quote_id, proposed_pickup_at, proposed_dropoff_at, expires_at, created_at)
VALUES (t.get('i_t4'), t.get('i_d4'), t.get('i_rs2'), t.get('i_rq2'), now() + interval '3 hours', now() + interval '4 hours', now() - interval '1 minute', now() - interval '10 minutes');
SELECT t.err('an expired proposal cannot be confirmed', $q$
    UPDATE return_match_proposals SET driver_response = 'accepted', customer_response = 'accepted', status = 'confirmed'
    WHERE shipment_id = t.get('i_rs2')$q$, 'expired at|ck_return_both_accepted');
SELECT t.ok('it is marked expired', $q$ UPDATE return_match_proposals SET status = 'expired' WHERE shipment_id = t.get('i_rs2')$q$);
SELECT t.err('an expired proposal is final', $q$
    UPDATE return_match_proposals SET status = 'pending' WHERE shipment_id = t.get('i_rs2')$q$, 'is expired and final');

SELECT t.set('i_s5', t.ready_shipment(t.get('i_c'), 'wallet', 300));
SELECT t.set('i_bal5', (SELECT customer_balance(t.get('i_c')))::bigint);
SELECT t.set('i_t5', t.assign(t.get('i_s5'), t.get('i_d3')));
SELECT t.to_dropoff(t.get('i_t5'));
SELECT t.err('after loading: no cancellation without a cargo ticket', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = 'truck broke down' WHERE id = t.get('i_t5')$q$,
    'resolved support ticket');
SELECT t.sys();
INSERT INTO support_tickets (user_id, user_role, opened_by, trip_id, category, subject)
VALUES (t.get('i_c'), 'customer', t.get('i_admin'), t.get('i_t5'), 'trip', 'Truck broke down with the cargo');
SELECT t.set('i_tk', (SELECT max(id) FROM support_tickets WHERE trip_id = t.get('i_t5')));
SELECT t.sys();
SELECT t.err('an open ticket is not enough', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = 'truck broke down',
           cancellation_ticket_id = t.get('i_tk') WHERE id = t.get('i_t5')$q$, 'resolved support ticket');
SELECT t.sys();
SELECT t.err('where the cargo went needs a note', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE support_tickets SET status = 'resolved', cargo_outcome = 'returned_to_sender' WHERE id = t.get('i_tk')$q$, 'ck_ticket_cargo_resolution');
SELECT t.sys();
SELECT t.err('only an admin records where the cargo went', $q$
    SELECT t.act(t.get('i_c'), 'customer');
    UPDATE support_tickets SET status = 'resolved', cargo_outcome = 'returned_to_sender', resolution_note = 'I got it back' WHERE id = t.get('i_tk')$q$, 'only an admin');
SELECT t.sys();
SELECT t.ok('admin resolves the ticket: cargo returned to the sender', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE support_tickets SET status = 'resolved', cargo_outcome = 'returned_to_sender',
           resolution_note = 'Second truck took the cargo back to the sender' WHERE id = t.get('i_tk');
    SELECT t.sys()$q$);
SELECT t.eq('the admin who documented it is recorded', (SELECT (resolved_by = t.get('i_admin'))::text FROM support_tickets WHERE id = t.get('i_tk')), 'true');
SELECT t.err('a reason is still needed', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_ticket_id = t.get('i_tk') WHERE id = t.get('i_t5')$q$, 'needs a reason');
SELECT t.sys();
SELECT t.set('i_tk_other', t.resolve_cargo(t.get('i_t1'), t.get('i_admin')));
SELECT t.err('a ticket of another trip does not count', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = 'x',
           cancellation_ticket_id = t.get('i_tk_other') WHERE id = t.get('i_t5')$q$, 'resolved support ticket');
SELECT t.sys();
SELECT t.ok('admin cancels with the documented ticket', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = 'truck broke down',
           cancellation_ticket_id = t.get('i_tk') WHERE id = t.get('i_t5');
    SELECT t.sys()$q$);
SELECT t.eq('shipment cancelled and the wallet payment refunded',
    (SELECT status FROM shipments WHERE id = t.get('i_s5')) || '/' || (customer_balance(t.get('i_c')) - t.get('i_bal5'))::numeric(12,2), 'cancelled/300.00');
SELECT t.err('the ticket is now evidence: where the cargo went cannot change', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE support_tickets SET cargo_outcome = 'handed_to_recipient' WHERE id = t.get('i_tk')$q$, 'evidence of a cancelled loaded trip');
SELECT t.sys();
SELECT t.err('and it cannot be opened again', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE support_tickets SET status = 'open' WHERE id = t.get('i_tk')$q$, 'evidence of a cancelled loaded trip');
SELECT t.sys();
SELECT t.ok('closing it is fine', $q$
    SELECT t.act(t.get('i_admin'), 'admin'); UPDATE support_tickets SET status = 'closed' WHERE id = t.get('i_tk'); SELECT t.sys()$q$);
SELECT t.err('a trip that was not loaded does not take a cargo ticket', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = 'x',
           cancellation_ticket_id = t.get('i_tk_other') WHERE id = t.get('i_t2')$q$, 'no cargo ticket needed');
SELECT t.sys();
SELECT t.err('the ticket cannot be attached to a trip that is not cancelling', $q$
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE trips SET cancellation_ticket_id = t.get('i_tk') WHERE id = t.get('i_t2')$q$, 'written only when it is cancelled');
SELECT t.sys();

SELECT t.set('i_g2', t.mk_group(t.get('i_c'), 0));
SELECT t.set('i_g2a', t.mk_shipment(t.get('i_c'), 'wallet', 0, t.get('i_g2'), 1));
SELECT t.set('i_g2b', t.mk_shipment(t.get('i_c'), 'wallet', 0, t.get('i_g2'), 2));
SELECT t.accept(t.mk_quote(t.get('i_g2a'), 300)); SELECT t.accept(t.mk_quote(t.get('i_g2b'), 300));
SELECT t.request(t.get('i_g2a')), t.request(t.get('i_g2b'));
SELECT t.set('i_d5', t.mk_driver('I Driver 5', '+201900000015')); SELECT t.approve_driver(t.get('i_d5'), t.get('i_admin'));
SELECT t.set('i_g2ta', t.assign(t.get('i_g2a'), t.get('i_d5'))), t.set('i_g2tb', t.assign(t.get('i_g2b'), t.get('i_d5')));
SELECT t.to_dropoff(t.get('i_g2ta')); SELECT t.move(t.get('i_g2tb'), 'heading_to_pickup');
SELECT t.ok('admin cancels the loaded group with one documented ticket', $q$
    SELECT t.set('i_tk2', t.resolve_cargo(t.get('i_g2ta'), t.get('i_admin')));
    SELECT t.act(t.get('i_admin'), 'admin');
    UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = 'accident',
           cancellation_ticket_id = t.get('i_tk2') WHERE id = t.get('i_g2ta');
    SELECT t.sys()$q$);
SELECT t.eq('both group trips and shipments cancelled',
    (SELECT string_agg(DISTINCT status, ',') FROM trips WHERE group_id = t.get('i_g2')) || '/' ||
    (SELECT string_agg(DISTINCT status, ',') FROM shipments WHERE group_id = t.get('i_g2')), 'cancelled/cancelled');

SELECT count(*) FILTER(WHERE ok) AS passed,count(*) FILTER(WHERE NOT ok) AS failed,count(*) AS total FROM t.results;
SELECT n,name,detail FROM t.results WHERE NOT ok ORDER BY n;
DO $$ BEGIN IF (SELECT count(*) FROM t.results)<>575 OR EXISTS(SELECT 1 FROM t.results WHERE NOT ok)
 THEN RAISE EXCEPTION 'BASELINE_FAILED: expected 575 passed and 0 failed'; END IF; END$$;
\set ON_ERROR_STOP on
\encoding UTF8
\pset pager off
\pset null '(null)'
\echo WASLA REVIEW CHECKS - starting

BEGIN;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = public, pg_temp;

DO $$
BEGIN
    IF current_database() NOT IN ('wasla_unified_test','wasla_unified_test_2') THEN
        RAISE EXCEPTION 'Use a separate test database (e.g. wasla_test), not wasls';
    END IF;
    IF to_regclass('t.results') IS NULL OR to_regprocedure('t.mk_group(bigint,integer)') IS NULL THEN
        RAISE EXCEPTION 'Original test helpers are missing. Run the original test suite first.';
    END IF;
    IF (SELECT count(*) FROM t.results) <> 575 OR EXISTS (SELECT 1 FROM t.results WHERE NOT ok) THEN
        RAISE EXCEPTION 'Expected the baseline: 575 passed and 0 failed.';
    END IF;
END$$;

SELECT current_database() AS database_name, version() AS server_version,
       (SELECT extversion FROM pg_extension WHERE extname = 'postgis') AS postgis_version;
SELECT count(*) AS original_tests, count(*) FILTER (WHERE NOT ok) AS original_failed FROM t.results;

CREATE TEMP TABLE review_results (
    id text PRIMARY KEY,
    finding text NOT NULL,
    outcome text NOT NULL,
    stage text NOT NULL,
    error_state text,
    detail text NOT NULL
) ON COMMIT DROP;
CREATE TEMP SEQUENCE review_fixture_seq START 8800000000;

CREATE FUNCTION pg_temp.review_fixture() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    a bigint;
    c bigint;
    d bigint;
BEGIN
    PERFORM t.sys();
    a := t.mk_user('Review admin', '+20' || nextval('pg_temp.review_fixture_seq'), ARRAY['admin']);
    c := t.mk_user('Review customer', '+20' || nextval('pg_temp.review_fixture_seq'), ARRAY['customer']);
    d := t.mk_driver('Review driver', '+20' || nextval('pg_temp.review_fixture_seq'));
    PERFORM t.set('rv_admin', a);
    PERFORM t.set('rv_customer', c);
    PERFORM t.set('rv_driver', d);
    PERFORM t.approve_driver(d, a);
    PERFORM t.fund(c, 3000, a);
END$$;

CREATE FUNCTION pg_temp.review_probe(
    p_id text, p_finding text, p_setup text, p_action text, p_evidence text,
    p_control boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    phase text := 'setup';
    outcome_ text;
    detail_ text;
    state_ text;
    evidence_ boolean;
BEGIN
    BEGIN
        PERFORM pg_temp.review_fixture();
        EXECUTE p_setup;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
        phase := 'action';
        EXECUTE p_action;
        SET CONSTRAINTS ALL IMMEDIATE;
        SET CONSTRAINTS ALL DEFERRED;
        phase := 'evidence';
        EXECUTE p_evidence INTO STRICT evidence_;
        IF p_control THEN
            outcome_ := CASE WHEN evidence_ IS TRUE THEN 'PASS' ELSE 'FAIL' END;
        ELSE
            outcome_ := CASE WHEN evidence_ IS TRUE THEN 'FAIL' ELSE 'CHECK_ERROR' END;
        END IF;
        IF NOT p_control AND evidence_ IS TRUE THEN outcome_ := 'FAIL'; END IF;
        detail_ := CASE WHEN evidence_ IS TRUE THEN 'Expected positive control state observed.'
                        WHEN evidence_ IS FALSE THEN 'Evidence predicate returned false.'
                        ELSE 'Evidence predicate returned NULL; inspect the probe.' END;
        IF evidence_ IS NULL THEN outcome_ := 'CHECK_ERROR'; END IF;
        RAISE EXCEPTION USING ERRCODE = 'ZV001', MESSAGE = 'review_case_rollback';
    EXCEPTION
        WHEN SQLSTATE 'ZV001' THEN NULL;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS detail_ = MESSAGE_TEXT, state_ = RETURNED_SQLSTATE;
            outcome_ := CASE WHEN phase = 'setup' THEN 'SETUP_ERROR'
                             WHEN phase = 'evidence' THEN 'CHECK_ERROR'
                             WHEN NOT p_control AND position((CASE p_id WHEN 'R01' THEN 'already confirmed for another payment' WHEN 'R02' THEN 'a new trip starts empty' WHEN 'R03' THEN 'where the cargo went' WHEN 'R04' THEN 'already has an agreed price' WHEN 'R05a' THEN 'not the vehicle type' WHEN 'R05b' THEN 'more than the payload' WHEN 'R06a' THEN 'cancelled and final' WHEN 'R06b' THEN 'cancelled and final' WHEN 'R07a' THEN 'append-only' WHEN 'R07b' THEN 'cannot be edited' WHEN 'R07c' THEN 'append-only' WHEN 'R08a' THEN 'starts as awaiting_verification' WHEN 'R08b' THEN 'details cannot change' WHEN 'R09a' THEN 'written automatically by the database' WHEN 'R09b' THEN 'written automatically by the database' WHEN 'R10' THEN 'middle of a trip' WHEN 'R11' THEN 'more than the payload' WHEN 'R12' THEN 'confirmed and final' WHEN 'R13' THEN 'append-only' ELSE '__no_expected_error__' END) in detail_) > 0
                                  AND state_ = 'P0001'
                                  THEN 'PASS'
                             ELSE 'FAIL' END;
    END;
    INSERT INTO pg_temp.review_results VALUES (p_id, p_finding, outcome_, phase, state_, detail_);
END$$;

SELECT pg_temp.review_probe('C01', 'Positive control: ordinary wallet delivery',
$s$
SELECT t.set('rv_trip', t.assign(t.ready_shipment(t.get('rv_customer'), 'wallet', 300), t.get('rv_driver')));
$s$,
$a$ SELECT t.deliver(t.get('rv_trip'));$a$,
$e$
SELECT tr.status = 'delivered' AND sh.status = 'delivered'
   AND tr.delivery_code_verified_at IS NOT NULL
   AND EXISTS (SELECT 1 FROM delivery_code_attempts WHERE trip_id = tr.id AND is_correct)
   AND customer_balance(sh.customer_id) = 2700
   AND driver_balance(tr.driver_id) = tr.driver_earning_amount
FROM trips tr JOIN shipments sh ON sh.id = tr.shipment_id WHERE tr.id = t.get('rv_trip');
$e$, true);

SELECT pg_temp.review_probe('R01', 'Same incoming transfer credited to two financial flows',
$s$
SELECT t.set('rv_topup', id) FROM customer_topups WHERE customer_id = t.get('rv_customer') AND status = 'verified';
INSERT INTO driver_settlements (driver_id, amount, proof_storage_key, transfer_reference)
SELECT t.get('rv_driver'), amount, 'review/same-transfer', transfer_reference
FROM customer_topups WHERE id = t.get('rv_topup');
SELECT t.set('rv_settlement', id) FROM driver_settlements WHERE driver_id = t.get('rv_driver');
$s$,
$a$
SELECT t.act(t.get('rv_admin'), 'admin');
UPDATE driver_settlements SET status = 'verified' WHERE id = t.get('rv_settlement');
$a$,
$e$
SELECT ct.status = 'verified' AND ds.status = 'verified'
   AND lower(btrim(ct.transfer_reference)) = lower(btrim(ds.transfer_reference))
   AND customer_balance(ct.customer_id) = 3000 AND driver_balance(ds.driver_id) = 3000
FROM customer_topups ct CROSS JOIN driver_settlements ds
WHERE ct.id = t.get('rv_topup') AND ds.id = t.get('rv_settlement');
$e$);

SELECT pg_temp.review_probe('R02', 'Delivery completed using verification supplied on trip INSERT',
$s$ SELECT t.set('rv_shipment', t.ready_shipment(t.get('rv_customer'), 'wallet', 300));$s$,
$a$
WITH inserted AS (
 INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount,
 commission_rate, planned_start_at, planned_end_at, delivery_code_verified_at)
 SELECT sh.id, t.get('rv_driver'), t.vehicle_of(t.get('rv_driver')), q.id,
 0, 0, now(), now() + interval '2 hours', now()
 FROM shipments sh JOIN price_quotes q ON q.shipment_id = sh.id AND q.status = 'accepted'
 WHERE sh.id = t.get('rv_shipment') RETURNING id
) SELECT t.set('rv_trip', id) FROM inserted;
SELECT t.to_dropoff(t.get('rv_trip'));
SELECT t.photo(t.get('rv_trip'), 'delivery');
SELECT t.move(t.get('rv_trip'), 'delivered');
$a$,
$e$
SELECT status = 'delivered' AND delivery_code_verified_at IS NOT NULL
 AND NOT EXISTS (SELECT 1 FROM delivery_code_attempts WHERE trip_id = tr.id)
FROM trips tr WHERE id = t.get('rv_trip');
$e$);

SELECT pg_temp.review_probe('R03', 'Admin cancellation after loading restarts driver search',
$s$
SELECT t.set('rv_trip', t.assign(t.ready_shipment(t.get('rv_customer'), 'wallet', 300), t.get('rv_driver')));
SELECT t.to_dropoff(t.get('rv_trip'));
$s$,
$a$
SELECT t.act(t.get('rv_admin'), 'admin');
UPDATE trips SET status = 'cancelled', cancellation_party = 'platform',
 cancellation_reason = 'Review: vehicle broke down with cargo loaded' WHERE id = t.get('rv_trip');
$a$,
$e$
SELECT tr.status = 'cancelled' AND tr.loaded_at IS NOT NULL AND sh.status = 'searching_driver'
 AND sh.pickup_address = 'Nasr City'
FROM trips tr JOIN shipments sh ON sh.id = tr.shipment_id WHERE tr.id = t.get('rv_trip');
$e$);

SELECT pg_temp.review_probe('R04', 'A new draft stop can join an already assigned group',
$s$
SELECT t.set('rv_group', t.mk_group(t.get('rv_customer')));
SELECT t.set('rv_s1', t.mk_shipment(t.get('rv_customer'), 'wallet', 0, t.get('rv_group'), 1));
SELECT t.set('rv_s2', t.mk_shipment(t.get('rv_customer'), 'wallet', 0, t.get('rv_group'), 2));
SELECT t.accept(t.mk_quote(t.get('rv_s1'), 300));
SELECT t.accept(t.mk_quote(t.get('rv_s2'), 300));
SELECT t.request(t.get('rv_s1'));
SELECT t.request(t.get('rv_s2'));
SELECT t.assign(t.get('rv_s1'), t.get('rv_driver'));
SELECT t.assign(t.get('rv_s2'), t.get('rv_driver'));
$s$,
$a$ SELECT t.set('rv_s3', t.mk_shipment(t.get('rv_customer'), 'wallet', 0, t.get('rv_group'), 3));$a$,
$e$
SELECT count(*) = 3 AND count(*) FILTER (WHERE status = 'draft') = 1
 AND count(*) FILTER (WHERE status = 'driver_assigned') = 2
FROM shipments WHERE group_id = t.get('rv_group');
$e$);

SELECT pg_temp.review_probe('R05a', 'Trip vehicle type differs from the accepted quote',
$s$
UPDATE vehicles SET vehicle_type_id = (SELECT id FROM vehicle_types WHERE code = 'small_pickup')
WHERE id = t.vehicle_of(t.get('rv_driver'));
SELECT t.set('rv_shipment', t.ready_shipment(t.get('rv_customer'), 'wallet', 300));
$s$,
$a$ SELECT t.set('rv_trip', t.assign(t.get('rv_shipment'), t.get('rv_driver')));$a$,
$e$
SELECT v.vehicle_type_id <> q.vehicle_type_id
FROM trips tr JOIN vehicles v ON v.id = tr.vehicle_id JOIN price_quotes q ON q.id = tr.price_quote_id
WHERE tr.id = t.get('rv_trip');
$e$);

SELECT pg_temp.review_probe('R05b', 'Known cargo weight exceeds assigned vehicle payload',
$s$
SELECT t.set('rv_shipment', t.mk_shipment(t.get('rv_customer')));
UPDATE shipments SET weight_kg = (SELECT max_payload_kg + 100 FROM vehicles WHERE id = t.vehicle_of(t.get('rv_driver')))
WHERE id = t.get('rv_shipment');
SELECT t.accept(t.mk_quote(t.get('rv_shipment'), 300));
SELECT t.request(t.get('rv_shipment'));
$s$,
$a$ SELECT t.set('rv_trip', t.assign(t.get('rv_shipment'), t.get('rv_driver')));$a$,
$e$
SELECT sh.weight_kg > v.max_payload_kg FROM trips tr
JOIN shipments sh ON sh.id = tr.shipment_id JOIN vehicles v ON v.id = tr.vehicle_id
WHERE tr.id = t.get('rv_trip');
$e$);

SELECT pg_temp.review_probe('R06a', 'Previously assigned trip starts after driver suspension',
$s$
SELECT t.set('rv_trip', t.assign(t.ready_shipment(t.get('rv_customer'), 'wallet', 300), t.get('rv_driver')));
SELECT t.act(t.get('rv_admin'), 'admin');
UPDATE users SET account_status = 'suspended', suspended_at = now(),
 suspended_by = t.get('rv_admin'), suspension_reason = 'Review suspension'
WHERE id = t.get('rv_driver');
$s$,
$a$ SELECT t.move(t.get('rv_trip'), 'heading_to_pickup');$a$,
$e$
SELECT tr.status = 'heading_to_pickup' AND u.account_status = 'suspended'
FROM trips tr JOIN users u ON u.id = tr.driver_id WHERE tr.id = t.get('rv_trip');
$e$);

SELECT pg_temp.review_probe('R06b', 'Previously assigned trip starts after vehicle deactivation',
$s$
SELECT t.set('rv_trip', t.assign(t.ready_shipment(t.get('rv_customer'), 'wallet', 300), t.get('rv_driver')));
UPDATE vehicles SET status = 'inactive' WHERE id = t.vehicle_of(t.get('rv_driver'));
$s$,
$a$ SELECT t.move(t.get('rv_trip'), 'heading_to_pickup');$a$,
$e$
SELECT tr.status = 'heading_to_pickup' AND v.status = 'inactive'
FROM trips tr JOIN vehicles v ON v.id = tr.vehicle_id WHERE tr.id = t.get('rv_trip');
$e$);

SELECT pg_temp.review_probe('R07a', 'Review author changed to a person outside the trip',
$s$
SELECT t.set('rv_trip', t.assign(t.ready_shipment(t.get('rv_customer'), 'wallet', 300), t.get('rv_driver')));
SELECT t.deliver(t.get('rv_trip'));
INSERT INTO reviews (trip_id, reviewer_id, reviewee_id, rating)
VALUES (t.get('rv_trip'), t.get('rv_customer'), t.get('rv_driver'), 5);
$s$,
$a$ UPDATE reviews SET reviewer_id = t.get('rv_admin') WHERE trip_id = t.get('rv_trip');$a$,
$e$
SELECT reviewer_id = t.get('rv_admin') AND trip_party(trip_id, reviewer_id) IS NULL
FROM reviews WHERE trip_id = t.get('rv_trip');
$e$);

SELECT pg_temp.review_probe('R07b', 'Message sender changed to a person outside the conversation',
$s$
SELECT t.set('rv_trip', t.assign(t.ready_shipment(t.get('rv_customer'), 'wallet', 300), t.get('rv_driver')));
WITH x AS (INSERT INTO conversations (trip_id) VALUES (t.get('rv_trip')) RETURNING id)
SELECT t.set('rv_conversation', id) FROM x;
INSERT INTO messages (conversation_id, sender_id, body)
VALUES (t.get('rv_conversation'), t.get('rv_customer'), 'Original message');
$s$,
$a$ UPDATE messages SET sender_id = t.get('rv_admin') WHERE conversation_id = t.get('rv_conversation');$a$,
$e$
SELECT m.sender_id = t.get('rv_admin') AND trip_party(c.trip_id, m.sender_id) IS NULL
FROM messages m JOIN conversations c ON c.id = m.conversation_id
WHERE c.id = t.get('rv_conversation');
$e$);

SELECT pg_temp.review_probe('R07c', 'Delivery evidence image replaced after trip completion',
$s$
SELECT t.set('rv_trip', t.assign(t.ready_shipment(t.get('rv_customer'), 'wallet', 300), t.get('rv_driver')));
SELECT t.deliver(t.get('rv_trip'));
$s$,
$a$
UPDATE trip_photos SET storage_key = 'review/replaced-evidence'
WHERE trip_id = t.get('rv_trip') AND stage = 'delivery';
$a$,
$e$
SELECT p.storage_key = 'review/replaced-evidence' AND tr.status = 'delivered'
FROM trip_photos p JOIN trips tr ON tr.id = p.trip_id
WHERE tr.id = t.get('rv_trip') AND p.stage = 'delivery';
$e$);

SELECT pg_temp.review_probe('R08a', 'Debt settlement inserted as verified without pending stage',
$s$ SELECT t.act(t.get('rv_admin'), 'admin');$s$,
$a$
INSERT INTO driver_settlements (driver_id, amount, proof_storage_key, transfer_reference, status, verified_by, verified_at)
VALUES (t.get('rv_driver'), 100, 'review/receipt', 'REVIEW-DIRECT-' || t.get('rv_driver'),
 'verified', t.get('rv_admin'), now());
$a$,
$e$
SELECT count(*) = 1 AND driver_balance(t.get('rv_driver')) = 100
FROM driver_settlements WHERE driver_id = t.get('rv_driver') AND status = 'verified';
$e$);

SELECT pg_temp.review_probe('R08b', 'Pending settlement amount changed while retaining the same receipt',
$s$
INSERT INTO driver_settlements (driver_id, amount, proof_storage_key)
VALUES (t.get('rv_driver'), 100, 'review/original-receipt');
$s$,
$a$ UPDATE driver_settlements SET amount = 900 WHERE driver_id = t.get('rv_driver');$a$,
$e$
SELECT amount = 900 AND proof_storage_key = 'review/original-receipt' AND status = 'awaiting_verification'
FROM driver_settlements WHERE driver_id = t.get('rv_driver');
$e$);

SELECT pg_temp.review_probe('R09a', 'Direct insertion of a false shipment state-history entry',
$s$ SELECT t.set('rv_shipment', t.mk_shipment(t.get('rv_customer')));$s$,
$a$
INSERT INTO shipment_status_history (shipment_id, from_status, to_status, changed_by_user_id, change_source, reason)
VALUES (t.get('rv_shipment'), 'in_progress', 'delivered', t.get('rv_admin'), 'admin', 'Review forged history');
$a$,
$e$
SELECT sh.status = 'draft' AND EXISTS (
 SELECT 1 FROM shipment_status_history h WHERE h.shipment_id = sh.id
 AND h.to_status = 'delivered' AND h.reason = 'Review forged history')
FROM shipments sh WHERE sh.id = t.get('rv_shipment');
$e$);

SELECT pg_temp.review_probe('R09b', 'Direct insertion of an audit entry without its alleged update',
$s$ SELECT t.sys();$s$,
$a$
INSERT INTO admin_audit_log (actor_id, actor_role, action, table_name, row_id, before, after, reason)
VALUES (t.get('rv_admin'), 'admin', 'update', 'users', t.get('rv_customer')::text,
 '{"full_name":"Review customer"}', '{"full_name":"Never actually set"}', 'Review invented audit');
$a$,
$e$
SELECT u.full_name = 'Review customer' AND EXISTS (
 SELECT 1 FROM admin_audit_log a WHERE a.row_id = u.id::text AND a.table_name = 'users'
 AND a.reason = 'Review invented audit' AND a.after->>'full_name' = 'Never actually set')
FROM users u WHERE u.id = t.get('rv_customer');
$e$);

SELECT pg_temp.review_probe('C02','Documented post-load cancellation ends shipment and refunds wallet',
$s$
SELECT t.set('rv_trip',t.assign(t.ready_shipment(t.get('rv_customer'),'wallet',300),t.get('rv_driver')));
SELECT t.to_dropoff(t.get('rv_trip'));
SELECT t.set('rv_ticket',t.resolve_cargo(t.get('rv_trip'),t.get('rv_admin')));
$s$,
$a$
SELECT t.act(t.get('rv_admin'),'admin');
UPDATE trips SET status='cancelled', cancellation_party='platform', cancellation_reason='Cargo returned',
 cancellation_ticket_id=t.get('rv_ticket') WHERE id=t.get('rv_trip');
$a$,
$e$
SELECT tr.status='cancelled' AND sh.status='cancelled' AND customer_balance(sh.customer_id)=3000
 AND tr.cancellation_ticket_id=t.get('rv_ticket') AND sh.cancellation_party='platform'
FROM trips tr JOIN shipments sh ON sh.id=tr.shipment_id WHERE tr.id=t.get('rv_trip');
$e$, true);

SELECT pg_temp.review_probe('C03','Message read receipt remains editable',
$s$
SELECT t.set('rv_trip',t.assign(t.ready_shipment(t.get('rv_customer'),'wallet',300),t.get('rv_driver')));
WITH x AS (INSERT INTO conversations(trip_id) VALUES(t.get('rv_trip')) RETURNING id) SELECT t.set('rv_chat',id) FROM x;
INSERT INTO messages(conversation_id,sender_id,body) VALUES(t.get('rv_chat'),t.get('rv_customer'),'Hello');
$s$,
$a$ UPDATE messages SET read_at=now() WHERE conversation_id=t.get('rv_chat');$a$,
$e$ SELECT read_at IS NOT NULL AND body='Hello' FROM messages WHERE conversation_id=t.get('rv_chat');$e$, true);

SELECT pg_temp.review_probe('R13','A posted review cannot be edited',
$s$
SELECT t.set('rv_trip',t.assign(t.ready_shipment(t.get('rv_customer'),'wallet',300),t.get('rv_driver')));
SELECT t.deliver(t.get('rv_trip'));
INSERT INTO reviews(trip_id,reviewer_id,reviewee_id,rating) VALUES(t.get('rv_trip'),t.get('rv_customer'),t.get('rv_driver'),5);
$s$,
$a$ UPDATE reviews SET rating=4,comment='Updated comment' WHERE trip_id=t.get('rv_trip');$a$,
$e$ SELECT rating=4 FROM reviews WHERE trip_id=t.get('rv_trip');$e$);

SELECT pg_temp.review_probe('R10','Cannot switch active vehicle while executing',
$s$
SELECT t.set('rv_trip',t.assign(t.ready_shipment(t.get('rv_customer'),'wallet',300),t.get('rv_driver')));
SELECT t.move(t.get('rv_trip'),'heading_to_pickup');
WITH x AS (INSERT INTO vehicles(driver_id,vehicle_type_id,plate_number,make,model,manufacture_year,color,status)
SELECT t.get('rv_driver'),vehicle_type_id,'V8-'||id,'Test','Test',2020,'Blue','active' FROM vehicles WHERE id=t.vehicle_of(t.get('rv_driver')) RETURNING id)
SELECT t.set('rv_vehicle2',id) FROM x;
$s$,
$a$ UPDATE driver_profiles SET active_vehicle_id=t.get('rv_vehicle2') WHERE user_id=t.get('rv_driver');$a$,
$e$ SELECT active_vehicle_id=t.get('rv_vehicle2') FROM driver_profiles WHERE user_id=t.get('rv_driver');$e$);

SELECT pg_temp.review_probe('R11','Group aggregate known weight exceeds payload',
$s$
SELECT t.set('rv_group',t.mk_group(t.get('rv_customer')));
SELECT t.set('rv_s1',t.mk_shipment(t.get('rv_customer'),'wallet',0,t.get('rv_group'),1));
SELECT t.set('rv_s2',t.mk_shipment(t.get('rv_customer'),'wallet',0,t.get('rv_group'),2));
UPDATE shipments SET weight_kg=(SELECT max_payload_kg * 0.75 FROM vehicles WHERE id=t.vehicle_of(t.get('rv_driver'))) WHERE group_id=t.get('rv_group');
SELECT t.accept(t.mk_quote(t.get('rv_s1'),300)); SELECT t.accept(t.mk_quote(t.get('rv_s2'),300));
SELECT t.request(t.get('rv_s1')); SELECT t.request(t.get('rv_s2'));
$s$,
$a$ SELECT t.assign(t.get('rv_s1'),t.get('rv_driver')); SELECT t.assign(t.get('rv_s2'),t.get('rv_driver'));$a$,
$e$ SELECT count(*)=2 FROM trips WHERE group_id=t.get('rv_group');$e$);

SELECT pg_temp.review_probe('R12','Confirmed return agreement is immutable',
$s$
SELECT t.set('rv_trip',t.assign(t.ready_shipment(t.get('rv_customer'),'wallet',300),t.get('rv_driver')));
SELECT t.set('rv_ret',t.mk_shipment(t.get('rv_customer'),'cash'));
SELECT t.set('rv_quote',t.mk_quote(t.get('rv_ret'),300));
INSERT INTO return_match_proposals(outbound_trip_id,driver_id,shipment_id,price_quote_id,proposed_pickup_at,proposed_dropoff_at,expires_at)
VALUES(t.get('rv_trip'),t.get('rv_driver'),t.get('rv_ret'),t.get('rv_quote'),now()+interval '3 hours',now()+interval '4 hours',now()+interval '1 hour');
UPDATE return_match_proposals SET driver_response='accepted' WHERE shipment_id=t.get('rv_ret');
UPDATE return_match_proposals SET customer_response='accepted', status='confirmed' WHERE shipment_id=t.get('rv_ret');
$s$,
$a$ UPDATE return_match_proposals SET proposed_dropoff_at=proposed_dropoff_at+interval '1 hour' WHERE shipment_id=t.get('rv_ret');$a$,
$e$ SELECT true FROM return_match_proposals WHERE shipment_id=t.get('rv_ret');$e$);

\echo REVIEW CHECKS RESULTS
SELECT * FROM pg_temp.review_results ORDER BY id;
SELECT count(*) FILTER(WHERE outcome='PASS') AS passed,
       count(*) FILTER(WHERE outcome<>'PASS') AS failed, count(*) AS total FROM pg_temp.review_results;
SELECT count(*)=22 AND bool_and(outcome='PASS') AS regression_ok FROM pg_temp.review_results \gset
ROLLBACK;
\if :regression_ok
\echo REVIEW_CHECKS_PASS - 22/22, test changes rolled back.
\else
DO $$ BEGIN RAISE EXCEPTION 'REVIEW_CHECKS_FAILED: inspect the printed case results'; END$$;
\endif

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SELECT t.section('eligibility, cargo evidence and restricted runtime');
SELECT t.sys();
SELECT t.set('u_admin',t.mk_user('Unified Admin','+202000000001',ARRAY['admin']));
SELECT t.set('u_c',t.mk_user('Unified Customer','+202000000002',ARRAY['customer']));
SELECT t.fund(t.get('u_c'),5000,t.get('u_admin'));
SELECT t.set('u_d',t.mk_driver('Unified Driver','+202000000003'));
SELECT t.approve_driver(t.get('u_d'),t.get('u_admin'));
SELECT t.set('u_s',t.mk_shipment(t.get('u_c'),'wallet',1));
UPDATE shipments SET weight_kg=100 WHERE id=t.get('u_s');
SELECT t.accept(t.mk_quote(t.get('u_s'),300));
SELECT t.request(t.get('u_s'));
SELECT t.set('u_t',t.assign(t.get('u_s'),t.get('u_d')));

SELECT t.err('U01 new policies after assignment block departure', $q$
 SELECT t.act(t.get('u_admin'),'admin');
 INSERT INTO policy_versions(doc_type,version_number,content_ar,content_en,published_at)
 SELECT 'terms',max(version_number)+1,'شروط جديدة','New terms',now()-interval '1 minute'
 FROM policy_versions WHERE doc_type='terms';
 SELECT t.move(t.get('u_t'),'heading_to_pickup');$q$, 'U_POLICIES');
SELECT t.err('U02 debt acquired after assignment blocks departure', $q$
 SELECT t.act(t.get('u_admin'),'admin');
 INSERT INTO wallet_transactions(driver_id,entry_type,amount,created_by,note)
 VALUES(t.get('u_d'),'manual_adjustment',-driver_debt_limit(t.get('u_d'))-1,t.get('u_admin'),'Test debt');
 SELECT t.move(t.get('u_t'),'heading_to_pickup');$q$, 'U_DEBT');
SELECT t.err('U03 fewer helpers after assignment blocks departure', $q$
 UPDATE driver_profiles SET max_helpers=0 WHERE user_id=t.get('u_d');
 SELECT t.move(t.get('u_t'),'heading_to_pickup');$q$, 'U_HELPERS');
SELECT t.err('U04 reduced vehicle payload blocks departure', $q$
 UPDATE vehicles SET max_payload_kg=50 WHERE id=t.vehicle_of(t.get('u_d'));
 SELECT t.move(t.get('u_t'),'heading_to_pickup');$q$, 'U_PAYLOAD');
SELECT t.err('U05 changed vehicle type blocks departure', $q$
 UPDATE vehicles SET vehicle_type_id=(SELECT id FROM vehicle_types WHERE code='small_pickup')
 WHERE id=t.vehicle_of(t.get('u_d'));
 SELECT t.move(t.get('u_t'),'heading_to_pickup');$q$, 'U_VEHICLE_TYPE');

GRANT USAGE ON SCHEMA t TO wasla_runtime;
GRANT SELECT ON t.ctx TO wasla_runtime;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA t TO wasla_runtime;
SELECT t.ok('U06 restricted runtime can complete a valid wallet trip', $q$
 SET LOCAL ROLE wasla_runtime;
 SELECT t.deliver(t.get('u_t'));
 RESET ROLE;$q$);
SELECT t.eq('U07 runtime delivery really reached delivered', (SELECT status FROM trips WHERE id=t.get('u_t')), 'delivered');
SELECT t.err('U08 runtime cannot forge shipment history', $q$
 SET LOCAL ROLE wasla_runtime;
 INSERT INTO shipment_status_history(shipment_id,to_status,change_source)
 VALUES(t.get('u_s'),'delivered','system');$q$, 'permission denied for table shipment_status_history');
SELECT t.err('U09 runtime cannot write transfer registry', $q$
 SET LOCAL ROLE wasla_runtime;
 INSERT INTO incoming_transfer_claims(transfer_reference,topup_id)
 SELECT 'forged',id FROM customer_topups WHERE customer_id=t.get('u_c');$q$, 'permission denied for table incoming_transfer_claims');
SELECT t.err('U10 runtime cannot alter schema', $q$
 SET LOCAL ROLE wasla_runtime;
 ALTER TABLE trips ADD COLUMN forbidden_column integer;$q$, 'must be owner');
SELECT t.err('U11 owner cannot directly forge registry rows either', $q$
 INSERT INTO incoming_transfer_claims(transfer_reference,topup_id)
 SELECT 'forged',id FROM customer_topups WHERE customer_id=t.get('u_c');$q$, 'written automatically');
SELECT t.eq('U12 verified topup has exactly one central claim',
 (SELECT count(*)::text FROM incoming_transfer_claims c JOIN customer_topups t ON c.topup_id=t.id
 WHERE t.customer_id=t.get('u_c')), '1');

SELECT t.set('u_gd',t.mk_driver('Unified Group Driver','+202000000004'));
SELECT t.approve_driver(t.get('u_gd'),t.get('u_admin'));
SELECT t.set('u_g',t.mk_group(t.get('u_c')));
SELECT t.set('u_a',t.mk_shipment(t.get('u_c'),'wallet',0,t.get('u_g'),1));
SELECT t.set('u_b',t.mk_shipment(t.get('u_c'),'wallet',0,t.get('u_g'),2));
SELECT t.accept(t.mk_quote(t.get('u_a'),300)); SELECT t.accept(t.mk_quote(t.get('u_b'),300));
SELECT t.request(t.get('u_a')); SELECT t.request(t.get('u_b'));
SELECT t.set('u_ta',t.assign(t.get('u_a'),t.get('u_gd')));
SELECT t.set('u_tb',t.assign(t.get('u_b'),t.get('u_gd')));
SELECT t.to_dropoff(t.get('u_ta'));
SELECT t.err('U13 unloaded stop cannot bypass cargo documentation for loaded group', $q$
 SELECT t.act(t.get('u_admin'),'admin');
 UPDATE trips SET status='cancelled',cancellation_party='platform',cancellation_reason='Accident'
 WHERE id=t.get('u_tb');$q$, 'resolved support ticket');
SELECT t.err('U14 customer cannot cancel unloaded stop in loaded group', $q$
 SELECT t.act(t.get('u_c'),'customer');
 UPDATE trips SET status='cancelled',cancellation_party='customer',cancellation_reason='Cancel'
 WHERE id=t.get('u_tb');$q$, 'U_CARGO_ADMIN');
SELECT t.err('U15 claimed admin role without admin membership is rejected', $q$
 SELECT t.act(t.get('u_c'),'admin');
 UPDATE trips SET status='cancelled',cancellation_party='platform',cancellation_reason='Cancel'
 WHERE id=t.get('u_tb');$q$, 'U_CARGO_ADMIN');
SELECT t.set('u_wrong',t.resolve_cargo(t.get('u_t'),t.get('u_admin')));
SELECT t.err('U16 a different group cannot supply the cargo ticket', $q$
 SELECT t.act(t.get('u_admin'),'admin');
 UPDATE trips SET status='cancelled',cancellation_party='platform',cancellation_reason='Accident',
 cancellation_ticket_id=t.get('u_wrong') WHERE id=t.get('u_tb');$q$, 'resolved support ticket');
SELECT t.set('u_ticket',t.resolve_cargo(t.get('u_ta'),t.get('u_admin')));
SELECT t.set('u_balance_before',customer_balance(t.get('u_c'))::bigint);
SELECT t.ok('U17 documented cancellation from unloaded stop cancels the whole group', $q$
 SELECT t.act(t.get('u_admin'),'admin');
 UPDATE trips SET status='cancelled',cancellation_party='platform',cancellation_reason='Accident',
 cancellation_ticket_id=t.get('u_ticket') WHERE id=t.get('u_tb');
 SELECT t.sys();$q$);
SELECT t.eq('U18 every cancelled trip links the same evidence',
 (SELECT count(*)::text FROM trips WHERE group_id=t.get('u_g') AND status='cancelled'
 AND cancellation_ticket_id=t.get('u_ticket')), '2');
SELECT t.eq('U19 neither shipment searches again',
 (SELECT count(*)::text FROM shipments WHERE group_id=t.get('u_g') AND status='cancelled'), '2');
SELECT t.eq('U20 both wallet payments refunded exactly once',
 (customer_balance(t.get('u_c'))-t.get('u_balance_before'))::numeric(12,2)::text,'600.00');
SELECT t.err('U21 evidence cannot be reopened after propagation', $q$
 SELECT t.act(t.get('u_admin'),'admin');
 UPDATE support_tickets SET status='open' WHERE id=t.get('u_ticket');$q$, 'evidence of a cancelled loaded trip');
SELECT t.err('U22 repeated cancellation cannot refund twice', $q$
 SELECT t.act(t.get('u_admin'),'admin');
 UPDATE trips SET status='cancelled' WHERE id=t.get('u_tb');$q$, 'cancelled and final');
SELECT t.eq('U23 existing loaded-first group cascade also carries evidence',
 (SELECT count(*)::text FROM trips WHERE group_id=t.get('i_g2') AND status='cancelled'
 AND cancellation_ticket_id=t.get('i_tk2')), '2');
SELECT t.eq('U24 no table or schema creation privileges for runtime',
 (has_schema_privilege('wasla_runtime','public','CREATE') OR
 has_table_privilege('wasla_runtime','admin_audit_log','INSERT'))::text,'false');

SELECT n,name,ok,detail FROM t.results WHERE section='eligibility, cargo evidence and restricted runtime' ORDER BY n;
SELECT count(*) FILTER(WHERE ok) AS passed,count(*) FILTER(WHERE NOT ok) AS failed,count(*) AS total
FROM t.results WHERE section='eligibility, cargo evidence and restricted runtime';
SELECT count(*)=24 AND bool_and(ok) AS unified_ok FROM t.results
WHERE section='eligibility, cargo evidence and restricted runtime' \gset
ROLLBACK;
\if :unified_ok
\echo UNIFIED_CHECKS_PASS - 24/24; temporary grants and fixtures rolled back.
\else
DO $$ BEGIN RAISE EXCEPTION 'UNIFIED_CHECKS_FAILED: inspect the case results above'; END$$;
\endif

CREATE TABLE t.unified_validation (version text PRIMARY KEY, checked_at timestamptz NOT NULL DEFAULT now());
INSERT INTO t.unified_validation(version) VALUES ('1.0');
\echo UNIFIED_FUNCTIONAL_COMPLETE - baseline 575 + review 22 + unified 24. Concurrency separate.
