ALTER TABLE shipment_groups
    ADD COLUMN dispatch_radius_m INTEGER NOT NULL DEFAULT 5000
        CHECK (dispatch_radius_m BETWEEN 5000 AND 30000 AND dispatch_radius_m % 5000 = 0),
    ADD COLUMN dispatch_radius_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE shipments
    ADD COLUMN dispatch_radius_m INTEGER NOT NULL DEFAULT 5000
        CHECK (dispatch_radius_m BETWEEN 5000 AND 30000 AND dispatch_radius_m % 5000 = 0),
    ADD COLUMN dispatch_radius_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE FUNCTION shipments_dispatch_radius_reset() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'searching_driver' AND OLD.status <> 'searching_driver' THEN
        NEW.dispatch_radius_m := 5000;
        NEW.dispatch_radius_updated_at := now();
        IF NEW.group_id IS NOT NULL THEN
            UPDATE shipment_groups
            SET dispatch_radius_m = 5000, dispatch_radius_updated_at = now()
            WHERE id = NEW.group_id;
        END IF;
    END IF;
    RETURN NEW;
END$$;

CREATE TRIGGER trg_shipments_dispatch_radius_reset
    BEFORE UPDATE OF status ON shipments
    FOR EACH ROW EXECUTE FUNCTION shipments_dispatch_radius_reset();
