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

## Driver application

Everything under `/driver` needs a driver account (`role: "driver"` at sign up). Others get `403` with `ROLE_REQUIRED`.

The steps: personal information, 5 photos, a vehicle with 6 photos, a payout account, then send for review. They can be done in any order after the personal information.

Every request below returns the whole application, so the app can redraw the screens from one shape:

```json
{
  "application": {
    "status": "draft",
    "submittedAt": null, "reviewedAt": null, "rejectionReason": null,
    "profile": { "cityId": "1", "dateOfBirth": "1995-05-14", "nationalIdLast4": "1234", "maxHelpers": 2, "activeVehicleId": null },
    "documents": [
      { "id": "7", "type": "driving_license_front", "status": "pending", "licenseCategory": "professional_3",
        "expiresOn": null, "rejectionCode": null, "rejectionReason": null, "uploadedAt": "...", "reviewedAt": null,
        "url": "https://..." }
    ],
    "vehicles": [
      { "id": "3", "vehicleTypeId": "2", "plateNumber": "ABC 123", "make": "Suzuki", "model": "Carry",
        "manufactureYear": 2018, "color": "White", "maxPayloadKg": 1500, "status": "pending_review", "documents": [ ] }
    ],
    "payoutAccount": { "id": "4", "method": "wallet", "holderName": "...", "bankName": "Vodafone Cash", "accountLast4": "4567", "status": "pending", "rejectionCode": null, "rejectionReason": null, "createdAt": "..." },
    "missing": ["vehicle_documents", "payout_account"]
  }
}
```

- `status`: `not_started` (no personal information yet), `draft`, `pending` (sent, waiting for the admin), `approved`, `rejected` (final, the driver cannot apply again).
- A document `status` is `pending`, `approved` or `rejected`. A rejected document has `rejectionCode` (`blurry`, `expiry_unreadable`, `expired`, `name_mismatch`, `wrong_document`, `other`) and `rejectionReason`. The driver uploads a new photo of the same type, the application stays `pending`.
- `url` opens the photo for 1 hour. Load the application again to get new links.
- `missing` (only in `draft`) is what is left before sending: the document types, `profile`, `vehicle_documents` (a vehicle with its 6 photos), `payout_account`, `accepted_terms`, `min_age`, `active_city`, `national_id`, `license_too_low` (the license category is lower than the vehicle type needs).
- `expiresOn` is written by the admin from the photo, the driver does not send it.

### GET /driver/application

### PUT /driver/profile

```json
{ "cityId": "1", "dateOfBirth": "1995-05-14", "nationalId": "29505140101234", "maxHelpers": 2 }
```

- The first time all fields are needed except `maxHelpers` (0 to 20, how many workers the driver can bring). After that send only what changes.
- `nationalId` is the 14 digits of the Egyptian national ID. Arabic digits are fine. `dateOfBirth` must match it, so send the two together.
- The driver must be at least `minDriverAge` (from `GET /catalog`).
- The national ID is never returned, only `nationalIdLast4`.

Errors: `INVALID_INPUT`, `NATIONAL_ID_TAKEN`, `APPLICATION_LOCKED` (only a `draft` can change)

### PUT /driver/documents/:type

`type` is `profile_photo`, `national_id_front`, `national_id_back`, `driving_license_front` or `driving_license_back`.

The body is the photo itself (not JSON), with `Content-Type: image/jpeg`, `image/png` or `image/webp`, at most 5 MB. For the license front add the category: `PUT /driver/documents/driving_license_front?licenseCategory=professional_3` (`private`, `professional_3`, `professional_2`, `professional_1`).

In Flutter: `http.put(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'image/jpeg'}, body: await file.readAsBytes())`. Use `imageQuality` in `image_picker` to keep the photo small.

A new photo of the same type replaces the old one. Returns `201`.

Errors: `PROFILE_REQUIRED` (save the personal information first), `INVALID_IMAGE`, `UNSUPPORTED_IMAGE`, `TOO_LARGE`, `STORAGE_FAILED` (try again), `APPLICATION_LOCKED` (rejected application)

### POST /driver/vehicles

```json
{ "vehicleTypeId": "2", "plateNumber": "ABC 123", "make": "Suzuki", "model": "Carry", "manufactureYear": 2018, "color": "White" }
```

`vehicleTypeId` comes from `GET /catalog`. The max payload is taken from the vehicle type. Returns `201`.

Errors: `INVALID_INPUT`, `PLATE_TAKEN`, `PROFILE_REQUIRED`, `APPLICATION_LOCKED` (while `pending`)

### PATCH /driver/vehicles/:id

Same fields, only what changes. Only before the application is sent.

Errors: `VEHICLE_LOCKED`, `APPLICATION_LOCKED`, `NOT_FOUND`

### PUT /driver/vehicles/:id/documents/:type

Same as the driver photos. `type` is `vehicle_license_front`, `vehicle_license_back`, `vehicle_photo_front`, `vehicle_photo_side`, `vehicle_photo_rear` or `vehicle_photo_cargo`.

### POST /driver/application/submit

```json
{ "confirm": true }
```

`confirm` is the "these documents are mine" checkbox. Returns the application with `status: "pending"`.

Errors: `APPLICATION_INCOMPLETE` (has `missing`, same list as above), `INVALID_INPUT` (`confirm`), `APPLICATION_LOCKED`

## Driver status

For an approved driver: going online and sending the location. Everything here returns `{ "status": { ... } }`:

```json
{
  "status": {
    "online": true, "onlineSince": "...", "canGoOnline": true, "blockers": [],
    "vehicle": { "id": "4", "vehicleTypeId": "2", "plateNumber": "ABC 123", "make": "Suzuki", "model": "Carry", "color": "White" },
    "location": { "lat": 30.0561, "lng": 31.3301, "updatedAt": "..." },
    "balance": "0.00", "debtLimit": "1000.00"
  }
}
```

- `blockers` is why the driver cannot go online: `not_approved`, `no_active_vehicle`, `vehicle_not_active`, `policies_not_accepted`, `license_expired`, `license_too_low`, `vehicle_license_expired`, `debt_over_limit`. Empty means `canGoOnline` is true.
- `vehicle` is the vehicle the driver works with now. `location` is the last one sent, or null.
- `balance` is the driver wallet. It is negative when the driver owes the platform, and `debt_over_limit` means it passed `debtLimit`.

### GET /driver/status

Call it when the home screen opens.

### POST /driver/online

```json
{ "lat": 30.0561, "lng": 31.3301 }
```

The location is needed. Errors (`409`): the first blocker in capital letters, for example `NOT_APPROVED` or `POLICIES_NOT_ACCEPTED`. `DEBT_OVER_LIMIT` has `balance` and `debtLimit`. Also `INVALID_INPUT`.

### POST /driver/offline

No body.

### POST /driver/location

```json
{ "lat": 30.0561, "lng": 31.3301, "accuracyM": 12.5 }
```

Send it every 30 seconds while the driver is online, and every 10 seconds during a trip (from `start` until `deliver`). During a trip every location is saved for the customer's tracking. `accuracyM` is the GPS accuracy in meters, optional. A driver who sends nothing for `autoOfflineAfterSeconds` (15 minutes) is set offline by the server.

Errors: `NOT_ONLINE` (the driver is offline now, show the home screen as offline), `INVALID_INPUT`

## Driver requests

A request is a shipment offered to the driver. The app asks for the list every few seconds while the driver is online, there is no push yet.

### GET /driver/offers

Call it every 5 seconds on the requests screen. Returns `{ "offers": [ ... ] }`, nearest pickup first:

```json
{
  "id": "41", "sentAt": "...", "expiresAt": "...", "secondsLeft": 24, "distanceToPickupM": 3120,
  "shipmentId": "12", "cargoCategoryId": "1", "sizeOptionId": "3", "cargoDescription": "A sofa and 2 chairs",
  "itemCount": 3, "isFragile": false, "weightKg": 120, "helpersCount": 1,
  "pickup": { "address": "...", "lat": 30.0444, "lng": 31.2357, "notes": "3rd floor" },
  "dropoff": { "address": "...", "lat": 30.0131, "lng": 31.2089, "notes": null },
  "pickupType": "now", "pickupWindowStart": "...", "pickupWindowEnd": "...",
  "routeDistanceM": 12012, "routeDurationS": 1730,
  "paymentMethod": "cash", "farePaidBy": "sender",
  "fareAmount": "630.18", "commissionAmount": "94.53", "driverEarning": "535.65", "cashToCollect": "630.18"
}
```

- A driver gets a request when he is online, within `dispatchRadiusM` of the pickup, his vehicle is the type the customer chose, it can carry the weight, and he can bring the helpers.
- `secondsLeft` is for the countdown. When it ends the request is closed, and while the shipment still needs a driver it comes back in the list with a new `id`. A declined request does not come back.
- `driverEarning` is what the driver keeps. `cashToCollect` is the cash he takes from the customer, `0.00` when the customer pays by wallet.
- The list is empty when the driver is offline or cannot work now (see `blockers` in `GET /driver/status`).
- The customer's name and phone come after accepting, in the trip.

### POST /driver/offers/:id/accept

No body. Returns `201` with `{ "trip": { ... } }`, see Driver trips.

Errors: `OFFER_EXPIRED` (the time is over), `OFFER_GONE` (another driver took it, or the customer cancelled), `SCHEDULE_CONFLICT` (the driver has another trip at that time), `NOT_ONLINE`, and the blockers of `POST /driver/online` like `POLICIES_NOT_ACCEPTED`

### POST /driver/offers/:id/decline

No body. Returns the offers that are left, `{ "offers": [ ... ] }`.

Errors: `OFFER_EXPIRED`, `OFFER_GONE`

## Driver trips

A trip is a shipment the driver accepted. A trip has everything a request has, plus:

```json
{
  "trip": {
    "id": "7", "status": "assigned",
    "customer": { "name": "Mariam Adel", "phone": "+201012345678" },
    "recipient": { "name": "Mona", "phone": "+201098765432" },
    "vehicleFit": null, "cashStatus": null, "deliveryCodeVerified": false, "deliveryCodeAttemptsLeft": 5,
    "plannedStartAt": "...", "plannedEndAt": "...", "startedAt": null, "loadedAt": null, "deliveredAt": null,
    "cancelledAt": null, "cancellationParty": null, "cancellationReason": null, "createdAt": "...",
    "photos": { "pickup": [ { "id": "3", "url": "https://...", "uploadedAt": "..." } ], "delivery": [] }
  }
}
```

- `status` is `assigned`, `heading_to_pickup`, `arrived_at_pickup`, `loaded`, `heading_to_dropoff`, `arrived_at_dropoff`, `delivered` or `cancelled`.
- The phones are there only while the trip is running. After `delivered` or `cancelled` they are null.
- `recipient` is null when the customer did not add one.
- `cashStatus` is null until the driver takes the cash, then `collected`, or `charged_to_sender` when the recipient refused to pay.
- `photos` comes with one trip (`GET /driver/trips/:id`, `current` and every step below), not in the list.

### GET /driver/trips/current

The trip the driver is working on now, or the next one he accepted. `{ "trip": null }` when there is none. Call it when the app opens.

### GET /driver/trips?status=active&page=1

`status` is `active` (default) or `finished`. 20 per page. Returns `trips`, `page` and `hasMore`.

### GET /driver/trips/:id

### The steps of a trip

```
assigned -> heading_to_pickup -> arrived_at_pickup -> loaded -> heading_to_dropoff -> arrived_at_dropoff -> delivered
```

Every step returns `{ "trip": { ... } }`. A step in the wrong order returns `409` with `WRONG_STEP` and the trip `status` now.

| Screen | Request | Body |
|---|---|---|
| Navigate to pickup | `POST /driver/trips/:id/start` | `{ "lat": 30.05, "lng": 31.33 }` (needed), `accuracyM` (optional) |
| I've arrived (pickup) | `POST /driver/trips/:id/arrive-pickup` | `{ "lat", "lng", "accuracyM" }` (optional) |
| Cargo photos | `PUT /driver/trips/:id/photos/pickup` | the photo itself |
| Cargo loaded | `POST /driver/trips/:id/loaded` | `{ "cashCollected": true }` when `cashToCollect` is taken at pickup |
| Start trip | `POST /driver/trips/:id/depart` | `{ "vehicleFit": "suitable" }` |
| I've arrived (drop-off) | `POST /driver/trips/:id/arrive-dropoff` | `{ "lat", "lng", "accuracyM" }` (optional) |
| Delivery code | `POST /driver/trips/:id/verify-code` | `{ "code": "4821" }` |
| Delivery photos | `PUT /driver/trips/:id/photos/delivery` | the photo itself |
| Complete delivery | `POST /driver/trips/:id/deliver` | `{ "payment": "collected" }` when the recipient pays |

#### POST /driver/trips/:id/start

The driver goes online with this location. The server checks the driver again, because a scheduled trip may be accepted days before.

Errors: `ANOTHER_TRIP_RUNNING` (with `tripId`), `VEHICLE_CHANGED`, the blockers of `POST /driver/online` like `LICENSE_EXPIRED` or `DEBT_OVER_LIMIT`, `INVALID_INPUT`

While a trip is running (`heading_to_pickup` to `arrived_at_dropoff`) the driver cannot go offline: `POST /driver/offline` returns `TRIP_RUNNING` with `tripId`.

#### PUT /driver/trips/:id/photos/pickup and /photos/delivery

Same as the other photos: the body is the photo (`image/jpeg`, `png` or `webp`, up to 5 MB). Pickup photos only at `arrived_at_pickup`, delivery photos only at `arrived_at_dropoff`. At most 6 of each. Returns `201`.

Errors: `WRONG_STEP`, `TOO_MANY_PHOTOS`, `UNSUPPORTED_IMAGE`, `INVALID_IMAGE`, `STORAGE_FAILED`

#### POST /driver/trips/:id/loaded

Needs at least one pickup photo. When the shipment is cash and `farePaidBy` is `sender`, the driver takes `cashToCollect` from the customer now and sends `"cashCollected": true`.

Errors: `PHOTO_REQUIRED`, `CASH_NOT_COLLECTED` (with `amount`), `WRONG_STEP`

After this the driver cannot cancel the trip, only support can.

#### POST /driver/trips/:id/depart

`vehicleFit` is how the vehicle fitted the cargo: `suitable`, `too_small` or `too_large`. Needed.

#### POST /driver/trips/:id/verify-code

The recipient tells the driver the 4 digit code (the customer has it in `GET /shipments/:id`).

Errors: `WRONG_CODE` (with `attemptsLeft`), `CODE_LOCKED` (5 wrong codes, support gives a new code), `INVALID_INPUT`

#### POST /driver/trips/:id/deliver

Needs the right code and at least one delivery photo. When the shipment is cash and `farePaidBy` is `recipient`, send `"payment": "collected"`, or `"payment": "refused"` when the recipient did not pay (the amount goes on the customer's wallet).

Errors: `CODE_NOT_VERIFIED`, `PHOTO_REQUIRED`, `CASH_NOT_COLLECTED` (with `amount`), `WRONG_STEP`

When the trip is delivered with cash, the platform commission is taken from the driver wallet (`balance` in `GET /driver/status`).

### POST /driver/trips/:id/cancel

```json
{ "reason": "Flat tyre" }
```

The driver can cancel until the cargo is loaded. The shipment goes back to searching for another driver, and the customer does not lose the request.

Errors: `CARGO_LOADED`, `TRIP_FINISHED`, `INVALID_INPUT`

## Payout account

For any logged in user. Drivers get their earnings here every week, customers will use it to take money out of their wallet.

### GET /me/payout-account

Returns `{ "payoutAccount": { ... } }` or `{ "payoutAccount": null }`. Only the last 4 digits of the account are returned.

### PUT /me/payout-account

```json
{ "method": "bank_account", "holderName": "Ahmed Hassan", "bankName": "National Bank of Egypt", "accountNumber": "EG380019000500000000263180002" }
```

- `method` is `bank_account` or `wallet`. `bankName` is needed for a bank, and for a wallet it can be the provider (`Vodafone Cash`).
- A new account replaces the old one and waits for the admin again. Returns `201`.

## Shipments

Everything under `/shipments` needs a customer account. Others get `403` with `ROLE_REQUIRED`.

The steps: make the shipment, add photos of the cargo, ask for prices, accept one, then send the request. Until it is sent the shipment is a `draft` and can change.

Every request below returns `{ "shipment": { ... } }`:

```json
{
  "shipment": {
    "id": "12", "status": "draft",
    "cargoCategoryId": "1", "sizeOptionId": "3", "cargoDescription": "A sofa and 2 chairs", "itemCount": 3,
    "isFragile": false, "weightKg": 120, "helpersCount": 1, "requestedVehicleTypeId": null,
    "pickup": { "address": "...", "lat": 30.0444, "lng": 31.2357, "notes": "3rd floor", "zoneId": null },
    "dropoff": { "address": "...", "lat": 30.0131, "lng": 31.2089, "notes": null, "zoneId": null },
    "pickupType": "now", "pickupWindowStart": "...", "pickupWindowEnd": "...",
    "routeDistanceM": 12012, "routeDurationS": 1730,
    "paymentMethod": "cash", "farePaidBy": "sender", "recipient": { "name": "Mona", "phone": "+201012345678" },
    "deliveryCode": "4821",
    "createdAt": "...", "cancelledAt": null, "cancellationParty": null, "cancellationReason": null,
    "photos": [ { "id": "5", "url": "https://...", "uploadedAt": "..." } ],
    "quotes": [
      { "id": "30", "vehicleTypeId": "2", "status": "offered", "recommended": true,
        "transportAmount": "580.18", "helpersCount": 1, "helperFee": "50.00", "helpersAmount": "50.00",
        "returnDiscountAmount": "0.00", "groupDiscountAmount": "0.00", "couponDiscountAmount": "0.00",
        "amount": "630.18", "customerAmount": "630.18", "pricingSource": "rules", "pricingDetails": { },
        "expiresAt": "...", "acceptedAt": null }
    ],
    "acceptedQuote": null,
    "trip": null,
    "timeline": [ { "from": null, "to": "draft", "by": "customer", "reason": null, "at": "..." } ]
  }
}
```

- `routeDistanceM` and `routeDurationS` are worked out by the server from the two points. Do not send them.
- `deliveryCode` is shown to the customer only. The recipient tells it to the driver at the drop-off.
- `quotes` has only the prices that can still be accepted. `customerAmount` is what the customer pays.
- `url` opens the photo for 1 hour.
- `trip` is null until a driver accepts. After that:

```json
"trip": {
  "id": "7", "status": "assigned",
  "driver": { "id": "15", "name": "Ahmed Ali", "phone": "+201055512345" },
  "vehicle": { "vehicleTypeId": "2", "plateNumber": "ABC 123", "make": "Suzuki", "model": "Carry", "color": "White" },
  "plannedStartAt": "...", "startedAt": null, "loadedAt": null, "deliveredAt": null
}
```

- The driver's phone is null after the delivery. If the driver cancels, `trip` is null again and the shipment is back to `searching_driver`.
- A shipment that finds no driver in `driverSearchTimeoutMinutes` (30 minutes) is cancelled by the server, with `cancellationParty` `platform` and `cancellationReason` `no_driver_found`.
- A scheduled shipment is offered to drivers `scheduledSearchLeadMinutes` (60 minutes) before the pickup time, not before.

### GET /shipments?status=active&page=1

20 per page, newest first. `status` is `active` (searching, assigned or on the way), `draft`, `searching_driver`, `driver_assigned`, `in_progress`, `delivered` or `cancelled`. Returns `shipments` (short: id, status, addresses, `pickupWindowStart`, `vehicleTypeId` and `customerAmount` of the accepted price), `page` and `hasMore`.

### POST /shipments

```json
{
  "cargoCategoryId": "1", "sizeOptionId": "3", "cargoDescription": "A sofa and 2 chairs", "itemCount": 3,
  "isFragile": false, "weightKg": 120, "helpersCount": 1,
  "pickup": { "address": "...", "lat": 30.0444, "lng": 31.2357, "notes": "3rd floor" },
  "dropoff": { "address": "...", "lat": 30.0131, "lng": 31.2089 },
  "pickupType": "scheduled", "pickupAt": "2026-11-20T09:30:00+02:00",
  "paymentMethod": "cash", "farePaidBy": "recipient",
  "recipientName": "Mona", "recipientPhone": "+201012345678"
}
```

- Needed: `cargoCategoryId`, `cargoDescription`, `itemCount`, `pickup`, `dropoff`, `pickupType`, `paymentMethod`.
- `sizeOptionId` must be one of the sizes of the category (from `GET /catalog`). `weightKg` and the size are used to choose the vehicles that fit.
- `helpersCount` is 0 to 20. `requestedVehicleTypeId` is optional.
- `pickupType` is `now` or `scheduled`. A scheduled pickup needs `pickupAt`, at least `minScheduleLeadMinutes` from now and at most 30 days. The driver comes within 1 hour from that time.
- `paymentMethod` is `cash` or `wallet`. `farePaidBy` is `sender` (default) or `recipient`. The recipient can only pay cash, and then `recipientName` and `recipientPhone` are needed.
- Pickup and drop-off must be at least 200 m apart.

Returns `201`. Errors: `INVALID_INPUT`, `SAME_PLACE`

### GET /shipments/:id

### GET /shipments/:id/tracking

For the trip screen. Call it every 10 seconds while the trip is running. It is small, so the app does not need to load the whole shipment each time.

```json
{
  "tracking": {
    "shipmentStatus": "in_progress", "tripId": "7", "tripStatus": "heading_to_dropoff",
    "signal": "live", "nextStop": "dropoff",
    "driverLocation": { "lat": 30.0213, "lng": 31.2219, "accuracyM": 12.5, "recordedAt": "..." },
    "distanceToNextStopM": 4120
  }
}
```

- `driverLocation` is there only while the trip is running (`heading_to_pickup` to `arrived_at_dropoff`). Before the driver starts and after the delivery it is null.
- `signal` is `live`, or `lost` when the driver sent nothing for `locationStaleSeconds` (2 minutes). Show the last location with a "no signal" note. It is null when the trip is not running.
- `nextStop` is `pickup` or `dropoff`. `distanceToNextStopM` is a straight line, not the road.
- `tripId` and `tripStatus` are null before a driver accepts.

Errors: `NOT_FOUND`

### PATCH /shipments/:id

Same fields, only what changes. Only a `draft`, and not after a price is accepted. A change makes the old prices useless, ask for new ones.

Errors: `INVALID_INPUT`, `WRONG_STATUS`, `PRICE_ACCEPTED` (withdraw the price first), `NOT_FOUND`

### PUT /shipments/:id/photos

The body is the photo itself, the same as the driver photos (`image/jpeg`, `image/png` or `image/webp`, at most 5 MB). At most 10 photos. Returns `201`.

`DELETE /shipments/:id/photos/:photoId` removes one.

Errors: `TOO_MANY_PHOTOS`, `INVALID_IMAGE`, `UNSUPPORTED_IMAGE`, `TOO_LARGE`, `STORAGE_FAILED`, `PRICE_ACCEPTED`, `WRONG_STATUS`

### POST /shipments/:id/quotes

No body. Makes one price for every vehicle type that can carry the cargo. The smallest one has `recommended: true`. A price is valid for 15 minutes, and asking again replaces the old prices. Returns `201`.

For a `now` pickup the pickup time starts again from now.

Errors: `PHOTO_REQUIRED` (add a photo first), `NO_VEHICLE_FITS`, `SCHEDULE_TOO_SOON` (the scheduled time is too close now, change `pickupAt`), `PRICE_ACCEPTED`

### POST /shipments/:id/quotes/:quoteId/accept

No body. The other prices become `rejected`, and the shipment cannot change until the price is withdrawn.

Errors: `QUOTE_EXPIRED`, `QUOTE_OUTDATED` (the shipment changed after this price), `QUOTE_NOT_AVAILABLE`, `PRICE_ACCEPTED`, `NOT_FOUND`

### POST /shipments/:id/withdraw-price

No body. Cancels the accepted price, so the shipment can change again. Ask for new prices after that.

Errors: `PRICE_NOT_ACCEPTED`

### POST /shipments/:id/request

No body. Sends the shipment to the drivers, the status becomes `searching_driver`.

Errors: `PRICE_NOT_ACCEPTED`, `PRICE_TOO_OLD` (the pickup time passed, withdraw and ask again), `POLICIES_NOT_ACCEPTED`, `WALLET_NEGATIVE` (has `balance`), `WALLET_TOO_LOW` (has `available` and `needed`, top up or pay cash)

### POST /shipments/:id/cancel

```json
{ "reason": "Changed my mind" }
```

`reason` is optional.

- `draft` or `searching_driver`: cancelled for free.
- A driver accepted but did not start yet (`trip.status` is `assigned`): cancelled for free.
- The driver is on the way (`heading_to_pickup` or `arrived_at_pickup`): there is a fee (`cancellationFee` in settings, 50 EGP). The first call returns `CANCEL_FEE` with `fee`. Show it to the customer, and if they agree send again with `"acceptFee": true`. The fee is taken from the customer wallet and goes to the driver. A wallet below zero blocks new requests until it is paid.
- After loading the customer cannot cancel.

Errors: `CANCEL_FEE` (with `fee`), `CARGO_LOADED`, `WRONG_STATUS`

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

### Driver applications

- `GET /admin/drivers?status=pending&search=ahmed&page=1`: 20 per page, oldest first. `status` is `draft`, `pending`, `needs_fix` (pending with a rejected photo), `approved` or `rejected`. `search` looks in the name, email and phone. Returns `drivers` (each with `needsFix` and `pendingDocuments`), `page`, `pageSize` and `total`.
- `GET /admin/drivers/:id`: returns `driver` (name, email, phone, language, accountStatus) and `application`, the same as the driver sees plus `reviewedBy` on each photo, the full `payoutAccount.accountNumber`, the vehicle `cargoLengthM`, `cargoWidthM`, `cargoHeightM`, and `approvalMissing` (what stops the approval).

Every request below returns the same `{ driver, application }`.

### Reviewing a photo

- `POST /admin/driver-documents/:id/review`
- `POST /admin/vehicle-documents/:id/review`

```json
{ "decision": "approve", "expiresOn": "2030-06-30" }
{ "decision": "reject", "rejectionCode": "blurry", "rejectionReason": "The numbers cannot be read." }
```

- `expiresOn` is needed when approving `national_id_front`, `driving_license_front` and `vehicle_license_front` (read it from the photo), and not allowed for the others. It must be after today, an expired document is rejected with `expired`.
- When approving `driving_license_front` you can also send `licenseCategory` to correct what the driver chose.
- `rejectionCode`: `blurry`, `expiry_unreadable`, `expired`, `name_mismatch`, `wrong_document`, `other`.
- A rejected photo does not reject the application. The driver gets an email and uploads a new one.

Errors: `ALREADY_REVIEWED`, `DOCUMENT_REPLACED` (the driver uploaded a newer photo, review that one), `WRONG_STATUS` (the application was not sent yet or is rejected)

### Approving or rejecting the driver

- `POST /admin/drivers/:id/approve` (optional `reason`): only when every photo is approved and the licenses are not expired. It also activates the vehicle and makes it the driver's current vehicle. The driver gets an email.
- `POST /admin/drivers/:id/reject` with `{ "reason": "..." }`: final, the driver cannot apply again. The driver gets an email with the reason.

Errors: `APPROVAL_INCOMPLETE` (has `missing`), `WRONG_STATUS` (only a `pending` application)

### Vehicles

- `PATCH /admin/vehicles/:id`: `maxPayloadKg`, `cargoLengthM`, `cargoWidthM`, `cargoHeightM`, if the vehicle license says something different.
- `POST /admin/vehicles/:id/activate`: for another vehicle of an approved driver, after its 6 photos are approved.
- `POST /admin/vehicles/:id/reject` with `{ "reason": "..." }`.

### Payout accounts

- `GET /admin/payout-accounts?status=pending`: current accounts with the full account number, of drivers and customers.
- `POST /admin/payout-accounts/:id/review`: `{ "decision": "approve" }` or `{ "decision": "reject", "rejectionCode": "name_mismatch", "rejectionReason": "..." }`. Codes: `name_mismatch`, `invalid_account`, `unsupported_bank`, `other`. The user gets an email when it is rejected.

### Shipments

- `GET /admin/shipments?status=active&search=mona&page=1`: 20 per page, newest first. Same `status` as the customer list. `search` is the shipment id or the customer name, email or phone. Returns `shipments` (each with `customerId`), `page`, `pageSize` and `total`.
- `GET /admin/shipments/:id`: returns `customer` (id, fullName, email, phone) and `shipment`, the same shape the customer sees.

### Terms and privacy

- `GET /admin/policies`: all versions, newest first
- `POST /admin/policies`: `type` (`terms` or `privacy`), `contentAr`, `contentEn`. Makes a draft with the next version number.
- `PATCH /admin/policies/:id`: change the text of a draft
- `POST /admin/policies/:id/publish`: publish the draft

A draft is not shown to anyone. After publishing, the text cannot change (make a new version), and every customer and driver gets `needsPolicyAcceptance: true` until they accept it.

Errors: `DRAFT_EXISTS` (only one draft per type, the error has its `id`), `ALREADY_PUBLISHED`

### Trips

#### GET /admin/trips?status=active&search=&page=1

`status` is `active` (default), `finished` or `all`. `search` matches the trip number, the shipment number, or the driver's or customer's name or phone. 20 per page. Returns `trips`, `page`, `pageSize`, `total`:

```json
{ "id": "7", "status": "heading_to_pickup", "shipmentId": "12", "fareAmount": "630.18",
  "driver": { "id": "15", "name": "Ahmed Ali" }, "customer": { "id": "9", "name": "Mariam Adel" },
  "plannedStartAt": "...", "startedAt": "...", "deliveredAt": null, "cancelledAt": null,
  "cancellationParty": null, "createdAt": "..." }
```

#### GET /admin/trips/:id

The trip as the driver sees it (see Driver trips), plus:

- `driver` (id, name, phone) and `vehicle`. The phones are always there for the admin.
- `isLateCancellation`, `cancellationFee`, `finalCommission`, `finalDriverEarning` (the last two after delivery).
- `timeline`: every status change with `by` (`customer`, `driver`, `admin` or `system`) and `reason`.
- `path`: every location the driver sent during the trip, oldest first, for drawing the route.
- `tracking`: the same as `GET /shipments/:id/tracking`.

#### POST /admin/trips/:id/cancel

```json
{ "reason": "Driver not answering" }
```

`reason` is needed. Only before loading. The shipment goes back to searching for another driver, not the same one. After loading it needs a support ticket (comes with support).

Errors: `CARGO_LOADED`, `TRIP_FINISHED`, `INVALID_INPUT`

#### POST /admin/trips/:id/new-code

No body. When the driver entered 5 wrong codes, this makes a new code for the shipment and gives the driver 5 tries again. The customer sees the new code in `GET /shipments/:id`; tell them to share it with the recipient.

Errors: `CODE_NOT_LOCKED` (the trip is not at the drop-off, or it still has tries)

### Live map

#### GET /admin/map

The drivers to show on the live map: everyone online, and everyone in a running trip even if offline.

```json
{ "drivers": [ {
  "id": "15", "name": "Ahmed Ali", "phone": "+201055512345", "online": true, "signal": "live",
  "location": { "lat": 30.0561, "lng": 31.3301, "updatedAt": "..." },
  "vehicle": { "vehicleTypeId": "2", "plateNumber": "ABC 123" },
  "trip": { "id": "7", "status": "heading_to_pickup", "shipmentId": "12" }
} ] }
```

`signal` is `lost` when the driver sent nothing for `locationStaleSeconds`. `trip` is null when the driver is waiting for requests. Call it every 15 seconds.

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
