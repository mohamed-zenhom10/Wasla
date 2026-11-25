BEGIN;

CREATE OR REPLACE FUNCTION trips_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    sh   shipments%ROWTYPE;
    q    price_quotes%ROWTYPE;
    dp   driver_profiles%ROWTYPE;
    lic  driver_documents%ROWTYPE;
    ob   trips%ROWTYPE;
    test_mode BOOLEAN := COALESCE(current_setting('wasla.dispatch_test_mode', true) = 'true', false);
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
        IF NOT test_mode AND NOT EXISTS (
            SELECT 1 FROM vehicles WHERE id = NEW.vehicle_id AND vehicle_type_id = q.vehicle_type_id
        ) THEN
            RAISE EXCEPTION 'vehicle % is not the vehicle type the price was quoted for', NEW.vehicle_id;
        END IF;
        IF NOT test_mode AND
           (SELECT COALESCE(sum(s.weight_kg), 0) FROM shipments s
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
        IF NOT test_mode AND dp.max_helpers < sh.helpers_count THEN
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

CREATE OR REPLACE FUNCTION unified_start_eligibility(p_driver BIGINT, p_vehicle BIGINT, p_shipment BIGINT, p_quote BIGINT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    dp driver_profiles%ROWTYPE;
    v vehicles%ROWTYPE;
    sh shipments%ROWTYPE;
    lic driver_documents%ROWTYPE;
    known_weight NUMERIC;
    test_mode BOOLEAN := COALESCE(current_setting('wasla.dispatch_test_mode', true) = 'true', false);
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
    IF NOT test_mode
       AND v.vehicle_type_id IS DISTINCT FROM (SELECT vehicle_type_id FROM price_quotes WHERE id = p_quote) THEN
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
    IF NOT test_mode AND dp.max_helpers < sh.helpers_count THEN
        RAISE EXCEPTION 'U_HELPERS: insufficient helpers';
    END IF;
    IF driver_balance(p_driver) < -driver_debt_limit(p_driver) THEN
        RAISE EXCEPTION 'U_DEBT: driver debt exceeds the limit';
    END IF;
    IF sh.group_id IS NULL THEN
        known_weight := sh.weight_kg;
    ELSE
        SELECT sum(weight_kg) INTO known_weight FROM shipments
        WHERE group_id = sh.group_id AND status NOT IN ('delivered','cancelled');
    END IF;
    IF NOT test_mode AND known_weight > v.max_payload_kg THEN
        RAISE EXCEPTION 'U_PAYLOAD: known cargo weight exceeds vehicle payload';
    END IF;
END$$;

CREATE OR REPLACE FUNCTION dispatch_offers_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    lead INTEGER := (SELECT scheduled_search_lead_minutes FROM platform_settings);
    test_mode BOOLEAN := COALESCE(current_setting('wasla.dispatch_test_mode', true) = 'true', false);
BEGIN
    IF NEW.response <> 'pending' OR NEW.responded_at IS NOT NULL OR NEW.trip_id IS NOT NULL THEN
        RAISE EXCEPTION 'an offer starts as pending, without a response or a trip';
    END IF;
    IF NOT test_mode AND EXISTS (SELECT 1 FROM price_quotes q JOIN shipments s ON s.id = q.shipment_id
               WHERE q.status = 'accepted' AND (s.id = NEW.shipment_id OR s.group_id = NEW.group_id)
                 AND q.vehicle_type_id <> (SELECT vehicle_type_id FROM vehicles WHERE id = NEW.vehicle_id)) THEN
        RAISE EXCEPTION 'vehicle % is not the vehicle type the price was quoted for', NEW.vehicle_id;
    END IF;
    IF NOT test_mode AND (SELECT COALESCE(sum(weight_kg), 0) FROM shipments
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

COMMIT;
