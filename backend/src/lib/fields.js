import { AppError } from '../errors.js';
import { invalid, cleanOptionalText } from './validate.js';

export function bodyOf(req) {
  const body = req.body === undefined ? {} : req.body;
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, 'INVALID_INPUT', 'Request body must be a JSON object');
  }
  return body;
}

export function readReason(body) {
  return body.reason === undefined ? null : cleanOptionalText(body.reason, 'reason', 500);
}

export function readFields(body, fields, mode) {
  for (const key of Object.keys(body)) {
    const field = fields[key];
    if (key === 'reason') {
      continue;
    }
    if (!field) {
      throw invalid(key, `${key} is not a known field`);
    }
    if (mode === 'update' && field.fixed) {
      throw invalid(key, `${key} cannot be changed after it is created`);
    }
  }

  const values = {};
  for (const [key, field] of Object.entries(fields)) {
    if (body[key] === undefined) {
      if (mode === 'create' && field.required) {
        throw invalid(key, `${key} is required`);
      }
      continue;
    }
    values[field.column] = field.clean(body[key], key);
  }

  if (Object.keys(values).length === 0) {
    throw new AppError(400, 'NOTHING_TO_UPDATE', 'Send at least one field to change');
  }
  return values;
}

function placeholder(fields, column, index) {
  const field = Object.values(fields).find((item) => item.column === column);
  return field && field.sql ? field.sql(`$${index}`) : `$${index}`;
}

export async function insertRow(client, table, fields, values, returning) {
  const columns = Object.keys(values);
  const { rows: [row] } = await client.query(
    `INSERT INTO ${table} (${columns.join(', ')})
     VALUES (${columns.map((column, i) => placeholder(fields, column, i + 1)).join(', ')})
     RETURNING ${returning}`,
    Object.values(values),
  );
  return row;
}

export async function updateRow(client, table, fields, id, values, returning) {
  const columns = Object.keys(values);
  const { rows: [row] } = await client.query(
    `UPDATE ${table}
     SET ${columns.map((column, i) => `${column} = ${placeholder(fields, column, i + 2)}`).join(', ')}
     WHERE id = $1
     RETURNING ${returning}`,
    [id, ...Object.values(values)],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Record not found');
  }
  return row;
}
