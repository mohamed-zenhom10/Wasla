import { query } from '../db.js';
import {
  cleanSlug, cleanText, cleanOptionalText, cleanInteger, cleanBoolean, cleanChoice,
  cleanMoney, cleanMeasure, cleanDecimal,
} from './validate.js';

const LICENSES = ['private', 'professional_3', 'professional_2', 'professional_1'];

const code = { column: 'code', clean: cleanSlug, required: true, fixed: true };
const nameAr = { column: 'name_ar', clean: (v, f) => cleanText(v, f, 100), required: true };
const nameEn = { column: 'name_en', clean: (v, f) => cleanText(v, f, 100), required: true };
const isActive = { column: 'is_active', clean: cleanBoolean };
const sortOrder = { column: 'sort_order', clean: (v, f) => cleanInteger(v, f, 0, 1000) };

export const categoryFields = { code, nameAr, nameEn, sortOrder, isActive };

export const sizeFields = {
  code,
  nameAr,
  nameEn,
  approxVolumeM3: { column: 'approx_volume_m3', clean: (v, f) => (v === null ? null : cleanMeasure(v, f)) },
  sortOrder,
  isActive,
};

const measure = (column) => ({ column, clean: cleanMeasure, required: true });
const money = (column, required = true) => ({ column, clean: (v, f) => cleanMoney(v, f), required });

export const vehicleTypeFields = {
  code,
  nameAr,
  nameEn,
  maxPayloadKg: measure('max_payload_kg'),
  cargoVolumeM3: measure('cargo_volume_m3'),
  bedLengthM: measure('bed_length_m'),
  bedWidthM: measure('bed_width_m'),
  bedHeightM: measure('bed_height_m'),
  suitableForAr: { column: 'suitable_for_ar', clean: (v, f) => cleanOptionalText(v, f, 200) },
  suitableForEn: { column: 'suitable_for_en', clean: (v, f) => cleanOptionalText(v, f, 200) },
  baseFare: money('base_fare'),
  perKmRate: money('per_km_rate'),
  helperFee: money('helper_fee', false),
  minLicenseCategory: { column: 'min_license_category', clean: (v, f) => cleanChoice(v, f, LICENSES) },
  isActive,
};

export const cityFields = { code, nameAr, nameEn, isActive };

export const reviewTagFields = {
  code,
  nameAr,
  nameEn,
  sentiment: {
    column: 'sentiment', clean: (v, f) => cleanChoice(v, f, ['positive', 'negative']), required: true, fixed: true,
  },
  direction: {
    column: 'direction',
    clean: (v, f) => cleanChoice(v, f, ['customer_to_driver', 'driver_to_customer']),
    required: true,
    fixed: true,
  },
  isActive,
};

const int = (column, min, max) => ({ column, clean: (v, f) => cleanInteger(v, f, min, max), kind: 'number' });
const decimal = (column, limits) => ({ column, clean: (v, f) => cleanDecimal(v, f, limits), kind: 'number' });
const rate = (column) => decimal(column, { max: 1, places: 4 });
const amount = (column, above = false) => ({ column, clean: (v, f) => cleanMoney(v, f, above) });
const label = (column) => ({ column, clean: (v, f) => cleanText(v, f, 100) });
const optionalLabel = (column) => ({ column, clean: (v, f) => cleanOptionalText(v, f, 100) });
const shown = (field) => ({ ...field, public: true });

export const settingFields = {
  commissionRate: shown(rate('commission_rate')),
  defaultDebtLimit: amount('default_debt_limit'),
  driverOfferTimeoutSeconds: int('driver_offer_timeout_seconds', 1, 3600),
  dispatchRadiusM: int('dispatch_radius_m', 1, 500000),
  cancellationFee: shown(amount('cancellation_fee')),
  groupDiscountPct: shown(rate('group_discount_pct')),
  maxGroupStops: shown(int('max_group_stops', 2, 50)),
  minScheduleLeadMinutes: shown(int('min_schedule_lead_minutes', 0, 10080)),
  driverSearchTimeoutMinutes: int('driver_search_timeout_minutes', 1, 1440),
  scheduledSearchLeadMinutes: int('scheduled_search_lead_minutes', 1, 1440),
  companyInstapayHandle: shown(label('company_instapay_handle')),
  companyBankName: shown(optionalLabel('company_bank_name')),
  companyBankAccount: shown(optionalLabel('company_bank_account')),
  minTopupAmount: shown(amount('min_topup_amount', true)),
  maxTopupAmount: shown(amount('max_topup_amount')),
  minDriverAge: shown(int('min_driver_age', 18, 70)),
  driverPayoutWeekday: shown(int('driver_payout_weekday', 0, 6)),
  maxDeliveryCodeAttempts: int('max_delivery_code_attempts', 1, 20),
  locationStaleSeconds: int('location_stale_seconds', 1, 86400),
  autoOfflineAfterSeconds: int('auto_offline_after_seconds', 1, 86400),
  maxDynamicMultiplier: decimal('max_dynamic_multiplier', { min: 1, max: 10, places: 2 }),
  backhaulDiscountAmount: amount('backhaul_discount_amount'),
  backhaulMinDiscountPct: rate('backhaul_min_discount_pct'),
  aiLowConfidenceThreshold: decimal('ai_low_confidence_threshold', { max: 1, places: 3 }),
  disputeResponseHours: int('dispute_response_hours', 1, 720),
};

const num = (value) => (value === null ? null : Number(value));

export function toCategory(row, sizes) {
  const category = {
    id: row.id,
    code: row.code,
    nameAr: row.name_ar,
    nameEn: row.name_en,
    sortOrder: row.sort_order,
    isActive: row.is_active,
  };
  if (sizes) {
    category.sizes = sizes;
  }
  return category;
}

export function toSize(row) {
  return {
    id: row.id,
    categoryId: row.cargo_category_id,
    code: row.code,
    nameAr: row.name_ar,
    nameEn: row.name_en,
    approxVolumeM3: num(row.approx_volume_m3),
    sortOrder: row.sort_order,
    isActive: row.is_active,
  };
}

export function toVehicleType(row) {
  return {
    id: row.id,
    code: row.code,
    nameAr: row.name_ar,
    nameEn: row.name_en,
    maxPayloadKg: num(row.max_payload_kg),
    cargoVolumeM3: num(row.cargo_volume_m3),
    bedLengthM: num(row.bed_length_m),
    bedWidthM: num(row.bed_width_m),
    bedHeightM: num(row.bed_height_m),
    suitableForAr: row.suitable_for_ar,
    suitableForEn: row.suitable_for_en,
    baseFare: row.base_fare,
    perKmRate: row.per_km_rate,
    helperFee: row.helper_fee,
    minLicenseCategory: row.min_license_category,
    isActive: row.is_active,
  };
}

export function toCity(row, zones) {
  const city = {
    id: row.id,
    code: row.code,
    nameAr: row.name_ar,
    nameEn: row.name_en,
    isActive: row.is_active,
  };
  if (zones) {
    city.zones = zones;
  }
  return city;
}

export function toZone(row) {
  const zone = {
    id: row.id,
    cityId: row.city_id,
    code: row.code,
    nameAr: row.name_ar,
    nameEn: row.name_en,
    isActive: row.is_active,
  };
  if (row.boundary !== undefined) {
    zone.boundary = row.boundary;
  }
  return zone;
}

export function toReviewTag(row) {
  return {
    id: row.id,
    code: row.code,
    nameAr: row.name_ar,
    nameEn: row.name_en,
    sentiment: row.sentiment,
    direction: row.direction,
    isActive: row.is_active,
  };
}

export function toSettings(row, all) {
  const settings = {};
  for (const [key, field] of Object.entries(settingFields)) {
    if (all || field.public) {
      settings[key] = field.kind === 'number' ? num(row[field.column]) : row[field.column];
    }
  }
  if (all) {
    settings.updatedBy = row.updated_by;
    settings.updatedAt = row.updated_at;
  }
  return settings;
}

const ZONE_BASE = 'id, city_id, code, name_ar, name_en, is_active';
export const ZONE_COLUMNS = `${ZONE_BASE}, ST_AsGeoJSON(boundary)::json AS boundary`;

export async function loadCatalog(all) {
  const [categories, sizes, vehicleTypes, cities, zones, reviewTags, settings] = await Promise.all([
    query('SELECT * FROM cargo_categories WHERE $1 OR is_active ORDER BY sort_order, id', [all]),
    query('SELECT * FROM cargo_size_options WHERE $1 OR is_active ORDER BY sort_order, id', [all]),
    query('SELECT * FROM vehicle_types WHERE $1 OR is_active ORDER BY max_payload_kg, id', [all]),
    query('SELECT * FROM cities WHERE $1 OR is_active ORDER BY name_en', [all]),
    query(
      all
        ? `SELECT ${ZONE_COLUMNS} FROM service_zones ORDER BY name_en`
        : `SELECT ${ZONE_BASE} FROM service_zones WHERE is_active ORDER BY name_en`,
    ),
    query('SELECT * FROM review_tags WHERE $1 OR is_active ORDER BY direction, sentiment DESC, id', [all]),
    query('SELECT * FROM platform_settings WHERE id = 1'),
  ]);

  return {
    cargoCategories: categories.rows.map((row) => toCategory(
      row,
      sizes.rows.filter((size) => size.cargo_category_id === row.id).map(toSize),
    )),
    vehicleTypes: vehicleTypes.rows.map(toVehicleType),
    cities: cities.rows.map((row) => toCity(
      row,
      zones.rows.filter((zone) => zone.city_id === row.id).map(toZone),
    )),
    reviewTags: reviewTags.rows.map(toReviewTag),
    settings: toSettings(settings.rows[0], all),
  };
}
