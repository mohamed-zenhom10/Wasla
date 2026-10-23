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
