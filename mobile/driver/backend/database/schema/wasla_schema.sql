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
