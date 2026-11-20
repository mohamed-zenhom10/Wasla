CREATE OR REPLACE FUNCTION shipment_groups_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.customer_id, NEW.pickup_address, NEW.pickup_location::text, NEW.pickup_notes, NEW.helpers_count)
       IS DISTINCT FROM (OLD.customer_id, OLD.pickup_address, OLD.pickup_location::text, OLD.pickup_notes, OLD.helpers_count)
       AND EXISTS (SELECT 1 FROM shipments s
                   WHERE s.group_id = OLD.id AND s.status <> 'cancelled' AND shipment_is_locked(s.id)) THEN
        RAISE EXCEPTION 'group % details are fixed after a price was accepted', OLD.id;
    END IF;
    RETURN NEW;
END$$;
