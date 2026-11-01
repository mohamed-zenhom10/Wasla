export class AppError extends Error {
  constructor(status, code, message, extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

const CONSTRAINT_ERRORS = {
  uq_users_email_ci: [409, 'EMAIL_TAKEN', 'This email is already registered'],
  ck_settings_topup_range: [400, 'INVALID_INPUT', 'minTopupAmount must not be more than maxTopupAmount',
    { field: 'minTopupAmount' }],
  ck_settings_offline_after_stale: [400, 'INVALID_INPUT',
    'autoOfflineAfterSeconds must be more than locationStaleSeconds', { field: 'autoOfflineAfterSeconds' }],
};

function duplicateField(detail) {
  const match = /^Key \(([^)]+)\)=/.exec(detail || '');
  if (!match) {
    return undefined;
  }
  const column = match[1].split(',').pop().trim();
  return { field: column.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase()) };
}

const DB_ERRORS = {
  23505: [409, 'ALREADY_EXISTS', 'This record already exists'],
  23503: [409, 'RELATED_RECORD', 'A related record is missing or still in use'],
  23502: [400, 'MISSING_FIELD', 'A required field is missing'],
  23514: [400, 'INVALID_VALUE', 'One of the values is not allowed'],
  '23P01': [409, 'TIME_CONFLICT', 'This overlaps with another record'],
  '22P02': [400, 'INVALID_FORMAT', 'One of the values has the wrong format'],
  22001: [400, 'VALUE_TOO_LONG', 'One of the values is too long'],
  22003: [400, 'VALUE_OUT_OF_RANGE', 'One of the values is out of range'],
  P0001: [409, 'NOT_ALLOWED', 'This action is not allowed right now'],
  40001: [503, 'TRY_AGAIN', 'Please try again'],
  '40P01': [503, 'TRY_AGAIN', 'Please try again'],
};

export function toAppError(err) {
  if (err instanceof AppError) {
    return err;
  }
  if (err.type === 'entity.parse.failed') {
    return new AppError(400, 'INVALID_JSON', 'Request body is not valid JSON');
  }
  if (err.type === 'entity.too.large') {
    return new AppError(413, 'TOO_LARGE', 'Request body is too large');
  }

  const byConstraint = CONSTRAINT_ERRORS[err.constraint];
  const known = byConstraint || DB_ERRORS[err.code];
  if (known) {
    const appError = new AppError(...known);
    if (!byConstraint && err.code === '23505') {
      appError.extra = duplicateField(err.detail);
    }
    appError.detail = err.message;
    return appError;
  }
  return new AppError(500, 'SERVER_ERROR', 'Something went wrong');
}
