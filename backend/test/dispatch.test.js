import assert from 'node:assert/strict';
import test from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DB_HOST ||= 'localhost';
process.env.DB_PORT ||= '5432';
process.env.DB_NAME ||= 'wasls';
process.env.DB_USER ||= 'wasla_app';
process.env.DB_PASSWORD ||= 'test';
process.env.JWT_SECRET ||= 'test-secret-with-more-than-thirty-two-characters';
process.env.NATIONAL_ID_KEY ||= 'test-national-id-key-with-more-than-32-characters';

const { makeOffers } = await import('../src/lib/dispatch.js');

function queryRecorder() {
  const statements = [];
  return {
    statements,
    async query(sql, values) {
      statements.push({ sql, values });
      return { rows: [] };
    },
  };
}

test('normal dispatch retains distance and vehicle-fit filters', async () => {
  const client = queryRecorder();

  await makeOffers(client, null, false);

  assert.equal(client.statements.length, 2);
  const [singleOffer, groupedOffer] = client.statements.map(({ sql }) => sql);
  assert.match(singleOffer, /q\.vehicle_type_id = v\.vehicle_type_id/);
  assert.match(singleOffer, /ST_DWithin\(dp\.current_location, s\.pickup_location, s\.dispatch_radius_m\)/);
  assert.match(singleOffer, /COALESCE\(s\.weight_kg, 0\) <= v\.max_payload_kg/);
  assert.match(singleOffer, /s\.helpers_count <= dp\.max_helpers/);
  assert.match(groupedOffer, /x\.searching = x\.stops AND x\.same_type/);
  assert.match(groupedOffer, /ST_DWithin\(dp\.current_location, g\.pickup_location, g\.dispatch_radius_m\)/);
  assert.match(groupedOffer, /x\.weight <= v\.max_payload_kg/);
  assert.match(groupedOffer, /g\.helpers_count <= dp\.max_helpers/);
});

test('test dispatch bypasses distance and cargo fit but keeps driver availability checks', async () => {
  const client = queryRecorder();

  await makeOffers(client, null, true);

  assert.equal(client.statements.length, 3);
  assert.match(client.statements[0].sql, /set_config\('wasla\.dispatch_test_mode', 'true', true\)/);
  const [singleOffer, groupedOffer] = client.statements.slice(1).map(({ sql }) => sql);
  assert.doesNotMatch(singleOffer, /q\.vehicle_type_id = v\.vehicle_type_id/);
  assert.doesNotMatch(singleOffer, /ST_DWithin\(dp\.current_location, s\.pickup_location/);
  assert.doesNotMatch(singleOffer, /s\.weight_kg.*v\.max_payload_kg/);
  assert.doesNotMatch(singleOffer, /s\.helpers_count <= dp\.max_helpers/);
  assert.match(singleOffer, /dp\.is_online/);
  assert.match(singleOffer, /dp\.location_updated_at/);
  assert.match(singleOffer, /dp\.active_vehicle_id/);
  assert.match(singleOffer, /FROM trips t/);
  assert.doesNotMatch(groupedOffer, /x\.searching = x\.stops AND x\.same_type/);
  assert.doesNotMatch(groupedOffer, /ST_DWithin\(dp\.current_location, g\.pickup_location/);
  assert.doesNotMatch(groupedOffer, /x\.weight <= v\.max_payload_kg/);
  assert.doesNotMatch(groupedOffer, /g\.helpers_count <= dp\.max_helpers/);
  assert.match(groupedOffer, /dp\.is_online/);
  assert.match(groupedOffer, /dp\.location_updated_at/);
  assert.match(groupedOffer, /FROM trips t/);
});
