# Wasla API

Base URL (local): `http://localhost:3000/api`

All requests and responses are JSON. Send `Content-Type: application/json`.

## Errors

Every error has the same shape:

```json
{ "error": { "code": "EMAIL_TAKEN", "message": "This email is already registered" } }
```

Use `code` to decide what to show the user. `message` is only for developers.
Input errors also have `field`, for example `{ "code": "INVALID_INPUT", "field": "phone", ... }`.

## Logged in requests

Send the access token in the header:

```
Authorization: Bearer <accessToken>
```

The access token lasts 15 minutes. When a request returns `401` with `TOKEN_EXPIRED`, call `/auth/refresh` with the refresh token, save the new tokens, and send the request again.
If refresh returns `SESSION_ENDED`, go to the login screen.

## Sign up

### POST /auth/register

```json
{
  "fullName": "Mona Adel",
  "email": "mona@example.com",
  "phone": "+201001234567",
  "password": "secret123",
  "role": "customer",
  "language": "ar",
  "acceptPolicies": true
}
```

- `role` is `customer` or `driver`.
- `phone` must start with the country code (`+20...`).
- `password` is at least 8 characters.
- `language` is `ar` or `en` (default `ar`). Emails are sent in this language.

Returns `201` with `user`. A 6 digit code is sent to the email. Go to the code screen.

Errors: `INVALID_INPUT`, `POLICIES_NOT_ACCEPTED`, `EMAIL_TAKEN`, `EMAIL_FAILED`, `TOO_MANY_REQUESTS`

### POST /auth/verify-email

```json
{ "email": "mona@example.com", "code": "123456" }
```

Returns the same response as login (the user is logged in).

Errors: `WRONG_CODE`, `CODE_EXPIRED`, `TOO_MANY_ATTEMPTS`

The code lasts 10 minutes. After 5 wrong tries the user must ask for a new code.

### POST /auth/resend-code

```json
{ "email": "mona@example.com" }
```

Errors: `CODE_RECENTLY_SENT` (has `retryAfter` in seconds), `ALREADY_VERIFIED`, `ACCOUNT_NOT_FOUND`, `EMAIL_FAILED`, `TOO_MANY_REQUESTS`

## Login

### POST /auth/login

```json
{ "email": "mona@example.com", "password": "secret123" }
```

Returns:

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "expiresIn": 900,
  "user": {
    "id": "12",
    "fullName": "Mona Adel",
    "email": "mona@example.com",
    "phone": "+201001234567",
    "language": "ar",
    "emailVerified": true,
    "roles": ["customer"],
    "needsPolicyAcceptance": false
  }
}
```

Save both tokens on the device. `id` is a string.

Errors: `WRONG_EMAIL_OR_PASSWORD`, `EMAIL_NOT_VERIFIED` (call `/auth/resend-code` and go to the code screen), `ACCOUNT_SUSPENDED`, `TOO_MANY_REQUESTS`

Each app should check `roles`: the driver app needs `driver`, the admin panel needs `admin`.

### POST /auth/refresh

```json
{ "refreshToken": "..." }
```

Returns new `accessToken`, `refreshToken` and `expiresIn`. The old refresh token stops working, so save the new one.

Errors: `SESSION_ENDED`

### POST /auth/logout

```json
{ "refreshToken": "..." }
```

Returns `204`. Delete the tokens from the device.

## Forgot password

### POST /auth/forgot-password

```json
{ "email": "mona@example.com" }
```

Always returns `200`, even if the email is not registered. If it is, a code is sent.

Errors: `CODE_RECENTLY_SENT`, `EMAIL_FAILED`, `TOO_MANY_REQUESTS`

### POST /auth/reset-password

```json
{ "email": "mona@example.com", "code": "123456", "newPassword": "newsecret1" }
```

Returns `200`. The user is logged out from all devices and must log in with the new password.

Errors: `WRONG_CODE`, `CODE_EXPIRED`, `TOO_MANY_ATTEMPTS`, `INVALID_INPUT`

## Current user

### GET /me (logged in)

Returns `{ "user": { ... } }`, same as login.

If `needsPolicyAcceptance` is `true`, show the terms screen and call `/me/accept-policies`.

### POST /me/accept-policies (logged in)

Returns `{ "user": { ... } }`.

### GET /policies

Returns the latest terms and privacy policy:

```json
{ "policies": [ { "type": "terms", "version": 1, "contentAr": "...", "contentEn": "...", "publishedAt": "..." } ] }
```

## Too many tries

Some endpoints have a limit. When it is reached they return `429` with `TOO_MANY_REQUESTS` and `retryAfter` in seconds.

- `/auth/login`: 10 tries in 15 minutes for the same email from the same device
- `/auth/register`: 50 in an hour from the same device
- `/auth/resend-code` and `/auth/forgot-password`: 20 together in 15 minutes from the same device

## Login errors for all logged in requests

- `NOT_LOGGED_IN`: no token sent
- `TOKEN_EXPIRED`: refresh the token
- `INVALID_TOKEN`, `SESSION_ENDED`: go to login
- `ACCOUNT_SUSPENDED`: show a message
