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

## Catalog

### GET /catalog

No login needed. Returns the lists the apps show, only the active items:

```json
{
  "cargoCategories": [
    {
      "id": "1", "code": "furniture", "nameAr": "أثاث", "nameEn": "Furniture", "sortOrder": 1, "isActive": true,
      "sizes": [ { "id": "4", "categoryId": "1", "code": "few_items", "nameAr": "قطع قليلة", "nameEn": "A few items", "approxVolumeM3": 2, "sortOrder": 1, "isActive": true } ]
    }
  ],
  "vehicleTypes": [
    {
      "id": "2", "code": "quarter_truck", "nameAr": "ربع نقل", "nameEn": "Quarter Truck",
      "maxPayloadKg": 1500, "cargoVolumeM3": 6, "bedLengthM": 2.5, "bedWidthM": 1.6, "bedHeightM": 1.5,
      "suitableForAr": "...", "suitableForEn": "A room or a small flat",
      "baseFare": "300.00", "perKmRate": "15.00", "helperFee": "150.00",
      "minLicenseCategory": "professional_3", "isActive": true
    }
  ],
  "cities": [ { "id": "1", "code": "cairo", "nameAr": "القاهرة", "nameEn": "Cairo", "isActive": true, "zones": [] } ],
  "reviewTags": [ { "id": "1", "code": "professional", "nameAr": "محترف", "nameEn": "Professional", "sentiment": "positive", "direction": "customer_to_driver", "isActive": true } ],
  "settings": {
    "commissionRate": 0.15, "cancellationFee": "50.00", "groupDiscountPct": 0.05, "maxGroupStops": 5,
    "minScheduleLeadMinutes": 30, "companyInstapayHandle": "wasla@instapay", "companyBankName": null, "companyBankAccount": null,
    "minTopupAmount": "50.00", "maxTopupAmount": "10000.00", "minDriverAge": 21, "driverPayoutWeekday": 0
  }
}
```

- Show `nameAr` or `nameEn` depending on the app language.
- Prices are text with 2 decimals (`"300.00"`), like the ids. Sizes and rates are numbers.
- A category can have no sizes. Size is optional when making a shipment.
- `sentiment` is `positive` or `negative`. `direction` is `customer_to_driver` (customer rates the driver) or `driver_to_customer`.
- `driverPayoutWeekday`: 0 is Sunday.
- Load it when the app opens. The list can change from the admin panel, so do not hard code it.

### GET /catalog/zone?lat=30.05&lng=31.33

No login needed. Returns the service zone of a point on the map, or `null` if we do not cover it yet:

```json
{ "zone": { "id": "3", "cityId": "1", "code": "nasr_city", "nameAr": "مدينة نصر", "nameEn": "Nasr City", "isActive": true } }
```

If the point is inside two zones, the smaller one is returned.

Errors: `INVALID_INPUT` (`lat` from -90 to 90, `lng` from -180 to 180)

## Admin

Everything under `/admin` needs an admin account. Others get `403` with `ROLE_REQUIRED`.

Nothing in the catalog can be deleted, because old shipments and trips point to it. Hide it instead with `"isActive": false`. Hidden items disappear from `GET /catalog` but stay in the admin lists.

Every change can have an optional `reason`, saved in the admin log with who made the change:

```json
{ "nameEn": "Furniture", "reason": "fix the spelling" }
```

`PATCH` requests only need the fields that change. `code` (and a few others, see below) cannot be changed after the item is created.

Errors for all admin requests: `INVALID_INPUT` (with `field`), `NOTHING_TO_UPDATE`, `NOT_FOUND`, `ALREADY_EXISTS` (with `field`, for example the same `code` twice)

### GET /admin/catalog

Same as `GET /catalog` but with hidden items too, all the settings, and the zone boundaries.

### Cargo categories and sizes

- `POST /admin/cargo-categories`: `code`, `nameAr`, `nameEn`, optional `sortOrder` (0 to 1000) and `isActive`
- `PATCH /admin/cargo-categories/:id`
- `POST /admin/cargo-categories/:id/sizes`: `code`, `nameAr`, `nameEn`, optional `approxVolumeM3`, `sortOrder`, `isActive`
- `PATCH /admin/cargo-sizes/:id`

`code` is 2 to 40 small English letters, numbers or `_`, for example `office_furniture`.

### Vehicle types

- `POST /admin/vehicle-types`: `code`, `nameAr`, `nameEn`, `maxPayloadKg`, `cargoVolumeM3`, `bedLengthM`, `bedWidthM`, `bedHeightM`, `baseFare`, `perKmRate`, optional `helperFee`, `suitableForAr`, `suitableForEn`, `minLicenseCategory`, `isActive`
- `PATCH /admin/vehicle-types/:id`

`minLicenseCategory` is `private`, `professional_3`, `professional_2` or `professional_1`. Prices can be numbers or text, with at most 2 decimals.

### Cities and zones

- `POST /admin/cities`: `code`, `nameAr`, `nameEn`, optional `isActive`
- `PATCH /admin/cities/:id`
- `GET /admin/zones` and `GET /admin/zones/:id`
- `POST /admin/zones`: `cityId`, `code`, `nameAr`, `nameEn`, `boundary`, optional `isActive`
- `PATCH /admin/zones/:id` (`cityId` and `code` cannot change)

`boundary` is a GeoJSON Polygon. Each point is `[longitude, latitude]` (longitude first), and the last point is the same as the first:

```json
{
  "type": "Polygon",
  "coordinates": [[[31.30, 30.03], [31.38, 30.03], [31.38, 30.09], [31.30, 30.09], [31.30, 30.03]]]
}
```

Map libraries give this format directly. Lines that cross each other are refused.

### Review tags

- `POST /admin/review-tags`: `code`, `nameAr`, `nameEn`, `sentiment`, `direction`, optional `isActive`
- `PATCH /admin/review-tags/:id` (`sentiment` and `direction` cannot change)

### Settings

- `GET /admin/settings`
- `PATCH /admin/settings`: any of the settings

```json
{
  "commissionRate": 0.15, "defaultDebtLimit": "1000.00", "driverOfferTimeoutSeconds": 30, "dispatchRadiusM": 10000,
  "cancellationFee": "50.00", "groupDiscountPct": 0.05, "maxGroupStops": 5, "minScheduleLeadMinutes": 30,
  "driverSearchTimeoutMinutes": 30, "scheduledSearchLeadMinutes": 60, "companyInstapayHandle": "wasla@instapay",
  "companyBankName": null, "companyBankAccount": null, "minTopupAmount": "50.00", "maxTopupAmount": "10000.00",
  "minDriverAge": 21, "driverPayoutWeekday": 0, "maxDeliveryCodeAttempts": 5, "locationStaleSeconds": 120,
  "autoOfflineAfterSeconds": 900, "maxDynamicMultiplier": 1.25, "backhaulDiscountAmount": "120.00",
  "backhaulMinDiscountPct": 0.1, "aiLowConfidenceThreshold": 0.6, "disputeResponseHours": 24,
  "updatedBy": "1", "updatedAt": "..."
}
```

Rates are from 0 to 1 (`0.15` is 15%). `minTopupAmount` cannot be more than `maxTopupAmount`, and `autoOfflineAfterSeconds` must be more than `locationStaleSeconds`.

### Terms and privacy

- `GET /admin/policies`: all versions, newest first
- `POST /admin/policies`: `type` (`terms` or `privacy`), `contentAr`, `contentEn`. Makes a draft with the next version number.
- `PATCH /admin/policies/:id`: change the text of a draft
- `POST /admin/policies/:id/publish`: publish the draft

A draft is not shown to anyone. After publishing, the text cannot change (make a new version), and every customer and driver gets `needsPolicyAcceptance: true` until they accept it.

Errors: `DRAFT_EXISTS` (only one draft per type, the error has its `id`), `ALREADY_PUBLISHED`

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
