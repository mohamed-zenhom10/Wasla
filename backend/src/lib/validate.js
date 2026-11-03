import { AppError } from '../errors.js';

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PHONE_PATTERN = /^\+[1-9][0-9]{7,14}$/;
const CODE_PATTERN = /^[0-9]{6}$/;

<<<<<<< HEAD
function invalid(field, message) {
=======
export function invalid(field, message) {
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
  return new AppError(400, 'INVALID_INPUT', message, { field });
}

export function cleanEmail(value) {
  const email = typeof value === 'string' ? value.trim().toLowerCase() : '';
  if (!EMAIL_PATTERN.test(email) || email.length > 254) {
    throw invalid('email', 'Email is not valid');
  }
  return email;
}

export function cleanPassword(value, field = 'password') {
  if (typeof value !== 'string' || value.length < 8) {
    throw invalid(field, 'Password must be at least 8 characters');
  }
  if (Buffer.byteLength(value) > 72) {
    throw invalid(field, 'Password is too long');
  }
  return value;
}

export function cleanName(value) {
  const name = typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
  if (name.length < 2 || name.length > 100) {
    throw invalid('fullName', 'Name must be 2 to 100 characters');
  }
  return name;
}

export function cleanPhone(value) {
  const phone = typeof value === 'string' ? value.replace(/[\s-]/g, '') : '';
  if (!PHONE_PATTERN.test(phone)) {
    throw invalid('phone', 'Phone must be in international format, like +201001234567');
  }
  return phone;
}

export function cleanCode(value) {
  const code = typeof value === 'string' ? value.trim() : '';
  if (!CODE_PATTERN.test(code)) {
    throw invalid('code', 'Code must be 6 digits');
  }
  return code;
}

export function cleanToken(value) {
  if (typeof value !== 'string' || value.length < 20 || value.length > 200) {
    throw invalid('refreshToken', 'Refresh token is missing');
  }
  return value;
}
<<<<<<< HEAD
=======

const SLUG_PATTERN = /^[a-z][a-z0-9_]{1,39}$/;
const DECIMAL_PATTERN = /^[0-9]+(\.[0-9]+)?$/;
const ID_PATTERN = /^[1-9][0-9]{0,17}$/;

export function cleanId(value) {
  if (!ID_PATTERN.test(String(value))) {
    throw new AppError(404, 'NOT_FOUND', 'Record not found');
  }
  return String(value);
}

export function cleanRef(value, field) {
  if (!ID_PATTERN.test(String(value))) {
    throw invalid(field, `${field} is not a valid id`);
  }
  return String(value);
}

export function cleanSlug(value, field) {
  if (typeof value !== 'string' || !SLUG_PATTERN.test(value)) {
    throw invalid(field, 'Use 2 to 40 small English letters, numbers or _ and start with a letter');
  }
  return value;
}

export function cleanText(value, field, max = 200) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text) {
    throw invalid(field, `${field} is required`);
  }
  if (text.length > max) {
    throw invalid(field, `${field} must be at most ${max} characters`);
  }
  return text;
}

export function cleanOptionalText(value, field, max = 200) {
  if (value === null || (typeof value === 'string' && !value.trim())) {
    return null;
  }
  return cleanText(value, field, max);
}

export function cleanInteger(value, field, min, max) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw invalid(field, `${field} must be a whole number from ${min} to ${max}`);
  }
  return value;
}

export function cleanDecimal(value, field, { min = 0, max, places, above = false }) {
  const text = typeof value === 'number' && Number.isFinite(value) ? String(value) : value;
  if (typeof text !== 'string' || !DECIMAL_PATTERN.test(text.trim())) {
    throw invalid(field, `${field} must be a number`);
  }
  const [, fraction = ''] = text.trim().split('.');
  const number = Number(text);
  if (fraction.length > places) {
    throw invalid(field, `${field} can have at most ${places} digits after the point`);
  }
  if (number < min || (above && number === min) || number > max) {
    throw invalid(field, `${field} must be ${above ? 'more than' : 'at least'} ${min} and at most ${max}`);
  }
  return text.trim();
}

export function cleanMoney(value, field, above = false) {
  return cleanDecimal(value, field, { max: 1000000000, places: 2, above });
}

export function cleanMeasure(value, field) {
  return cleanDecimal(value, field, { max: 1000000, places: 3, above: true });
}

export function cleanBoolean(value, field) {
  if (typeof value !== 'boolean') {
    throw invalid(field, `${field} must be true or false`);
  }
  return value;
}

export function cleanChoice(value, field, choices) {
  if (!choices.includes(value)) {
    throw invalid(field, `${field} must be one of: ${choices.join(', ')}`);
  }
  return value;
}

export function cleanCoordinate(value, field, limit) {
  const number = typeof value === 'string' && value.trim() ? Number(value) : value;
  if (typeof number !== 'number' || !Number.isFinite(number) || Math.abs(number) > limit) {
    throw invalid(field, `${field} must be a number from -${limit} to ${limit}`);
  }
  return number;
}

export function cleanBoundary(value, field = 'boundary') {
  const ring = value && value.type === 'Polygon' && Array.isArray(value.coordinates) ? value.coordinates : null;
  if (!ring || ring.length !== 1 || !Array.isArray(ring[0])) {
    throw invalid(field, 'boundary must be a GeoJSON Polygon with one ring');
  }
  const points = ring[0];
  if (points.length < 4 || points.length > 1000) {
    throw invalid(field, 'boundary must have 4 to 1000 points, and the last point must repeat the first');
  }
  for (const point of points) {
    if (!Array.isArray(point) || point.length !== 2
        || typeof point[0] !== 'number' || Math.abs(point[0]) > 180
        || typeof point[1] !== 'number' || Math.abs(point[1]) > 90) {
      throw invalid(field, 'each point must be [longitude, latitude]');
    }
  }
  const [first, last] = [points[0], points[points.length - 1]];
  if (first[0] !== last[0] || first[1] !== last[1]) {
    throw invalid(field, 'the last point must be the same as the first point');
  }
  return JSON.stringify({ type: 'Polygon', coordinates: [points] });
}
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
