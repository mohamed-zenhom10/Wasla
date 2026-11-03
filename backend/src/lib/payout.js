export function toPayoutAccount(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    method: row.method,
    holderName: row.holder_name,
    bankName: row.bank_name,
    accountLast4: row.account_number.slice(-4),
    status: row.review_status,
    rejectionCode: row.rejection_code,
    rejectionReason: row.rejection_reason,
    createdAt: row.created_at,
  };
}
