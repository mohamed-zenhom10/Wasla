import { AppError } from '../errors.js';

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PHONE_PATTERN = /^\+[1-9][0-9]{7,14}$/;
const CODE_PATTERN = /^[0-9]{6}$/;

function invalid(field, message) {
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
