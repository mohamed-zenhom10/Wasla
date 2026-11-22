# Wasla Project Analysis

## 1. Executive Summary

Wasla is a delivery platform with a Node.js/PostgreSQL backend, a React admin frontend, a Flutter Customer App, and a Flutter Driver App. The customer shipment lifecycle is implemented across both mobile apps using the same backend API. Customer and Driver apps both pass their available Flutter tests and static analysis. The main remaining gaps are undocumented backend capabilities, mock/static screens in the Customer App, incomplete wallet/payment UI, and screens that are not yet connected to backend APIs.

## 2. Project Structure

- `backend/`: Express API, PostgreSQL access, authentication, shipment, driver, wallet, catalog, and admin endpoints. API contract is documented in `backend/API.md`.
- `frontend/`: React/Vite admin dashboard.
- `mobile/customer/`: Flutter Customer App.
- `mobile/driver/`: Flutter Driver App.
- `mobile/customer/lib/`: Customer screens, pages, services, models, components, theme, routing.
- `mobile/driver/lib/`: Driver screens, data services, maps/routing helpers, components.
- `mobile/customer/test/` and `mobile/driver/test/`: automated widget/service tests.

Important Customer modules:
- `lib/services/auth_service.dart`: authentication, token refresh, logout, secure storage.
- `lib/services/shipment_service.dart`: shipment draft, photos, quotes, acceptance, cancellation, tracking, pagination.
- `lib/services/wallet_service.dart`: wallet, transactions, top-ups, withdrawals, payment method.
- `lib/services/cargo_order_service.dart`: local draft state and compatibility fields.
- `lib/models/shipment.dart`: shipment, quote, photo, tracking, trip, and catalog models.
- `lib/models/wallet.dart`: wallet and transaction models.
- `lib/screens/home_screen.dart`: home, location selection, active draft handling.
- `lib/pages/`: booking, tracking, wallet, profile, and supporting screens.

Important Driver modules:
- `lib/data/driver_api.dart`: authenticated API client and token refresh.
- `lib/screens/driver_home_screen.dart`: availability, requests, active trip.
- `lib/screens/incoming_request_screen.dart`: request acceptance.
- `lib/screens/arriving_screen.dart`, `cargo_loaded_screen.dart`, `proof_of_delivery_screen.dart`: delivery lifecycle.
- `lib/data/driver_trip_location_reporter.dart`, `route_deviation_tracker.dart`, `tomtom_routing_service.dart`: live tracking and routing.

## 3. Completed Features

### Customer App
- Authentication: login, registration, email verification, password reset, logout, token persistence, token refresh, session-expired handling.
- Persistent authentication through secure storage.
- Home screen with pickup/drop-off selection and active draft resume.
- Location picker using geolocation, Photon/Nominatim, and OpenStreetMap tiles.
- Cargo category, details, helpers, size, payment method, scheduling, recipient phone.
- International phone number input and E.164 conversion.
- Cargo photo capture, upload, removal, and draft reuse.
- Shipment draft creation and update through documented endpoints.
- Quote loading, expiry, acceptance, and withdrawal.
- Shipment request to drivers.
- Shipment cancellation, including cancellation-fee handling.
- Driver matching polling and No Driver Found handling.
- Tracking screen with real tracking endpoint polling.
- Trips/activity pagination and status filtering.
- Wallet balance, available balance, negative balance, payment method selection.
- Wallet transactions with pagination and category tabs.
- Add money with catalog InstaPay handle, amount limits, receipt image upload, and top-up submission.
- Withdrawal request, withdrawal history, and cancellation.
- Profile and profile subpages.

### Driver App
- Driver authentication and session recovery.
- Driver availability and online/offline handling.
- Available request list and request details.
- Accept/decline shipment requests.
- Active trip management and status updates.
- Proof of delivery and delivery completion.
- Driver wallet and transaction display.
- Driver location reporting and route deviation tracking.

### Backend
- Customer authentication and token refresh.
- Shipment draft, update, photos, quotes, acceptance, withdrawal, request, cancellation, tracking, and listing.
- Driver availability, requests, acceptance, trip lifecycle, cancellation, delivery, proof, ratings.
- Wallet balance, payment method, transactions, top-ups, withdrawals.
- Catalog endpoints.
- Admin endpoints.

## 4. Incomplete Features

### Customer App
- Add Payment Method screen exists in Figma but is not safely implementable with documented backend APIs. The documented wallet API supports only `wallet`, `cash`, and `null`.
- Payment confirmed and receipt screens are not implemented. Backend payment-confirmation data is not available.
- Grouped shipment receipts and grouped payment collection are not implemented because grouped shipment APIs are not used by the Customer App.
- Payout account management is not implemented because its complete API specification is missing.
- Several screens remain static or mock-backed: `wallet_page.dart` before wallet integration, `available_drivers_page.dart`, `driver_profile_page.dart`, `chat_page.dart`, `booking_review_page.dart`, `price_estimate_page.dart`, `smart_backhaul_page.dart`, `vehicle_jumbo_page.dart`, `multi_stop_route_page.dart`.
- Multi-stop route UI exists, but shipment creation does not accept stops; creation is blocked when stops are present.
- Home active draft is cleared only after successful submission in the current flow; stale resume behavior may still need device testing.
- Tracking map uses coordinate text and a basic route line rather than a full map visualization.
- Wallet transactions filtering is client-side after loading pages.

### Driver App
- Driver application/onboarding flow may be partially implemented; verify against backend driver requirements.
- Live tracking and route deviation depend on external routing/geolocation services and require device testing.
- Driver wallet and payout flows depend on backend documentation and device permissions.

## 5. Missing Features

- Customer card payment registration and card management backend APIs.
- Customer grouped shipment receipt API integration.
- Customer payout-account creation/update/approval APIs.
- Customer payment confirmation screen backed by documented payment status.
- Driver-to-customer chat backend integration.
- Customer-side review/rating submission flow, if required by backend.
- Device-tested push notifications, if any are expected.

## 6. Bugs and Errors

### Customer App
- `lib/pages/location_picker_page.dart`: previously had a private-type public API lint; fixed by renaming `_Suggestion` to `Suggestion`.
- `lib/pages/cargo_details_page.dart`: previously referenced a removed notes controller; fixed.
- `lib/pages/driver_matching_page.dart`: previously had unused fields/imports; fixed.
- `lib/services/auth_service.dart`: previously lacked token refresh and persistent session handling; fixed.
- `lib/pages/shipment_details_page.dart`: previously lacked read-only mode and confirm-shipment flow; fixed.
- `lib/pages/wallet_page.dart`: previously displayed unavailable wallet data; fixed with real API integration.
- `lib/pages/profile_subpages.dart`: previously showed empty payment methods; fixed with documented payment methods.
- `lib/pages/add_money_page.dart`: previously lacked catalog-driven validation; fixed.
- `lib/pages/payment_methods_page.dart`: previously lacked Material ancestor for standalone use; fixed.
- `lib/pages/add_money_page.dart` and `lib/pages/withdraw_balance_page.dart`: previously lacked Scaffold/Material ancestors; fixed.

### Driver App
- No compilation errors found during static analysis.
- Driver location reporting and route deviation require runtime/device verification.

### Backend
- No automated test script is defined in `package.json`.
- Backend requires PostgreSQL and environment configuration.
- Some features depend on admin approval workflows not fully exposed to customers.

## 7. UI/UX Issues

### Customer App
- Some screens still use static or mock data.
- Typography was inconsistent in selectable elements; partially corrected.
- Wallet and payment screens now follow documented API data.
- Onboarding animation was moved to Splash Screen.
- Driver matching map uses a real route fallback but not a full interactive map.
- Location picker uses external geocoding services, so offline behavior depends on network availability.

### Driver App
- Driver screens use a separate design system and should be compared against available Driver design references.
- Live tracking UI requires device testing.

## 8. Backend and API Integration

### Customer App
- Authentication uses secure storage and documented `/auth/*` endpoints.
- Shipment services use `/shipments/*` and `/catalog`.
- Wallet services use `/me/wallet/*`.
- Top-ups use raw image bodies and query parameters as documented.
- Errors are parsed from documented error codes.
- Token refresh prevents simultaneous refresh requests and handles `SESSION_ENDED`.
- Some API failures are surfaced as generic messages unless documented codes are returned.

### Driver App
- Driver API client implements authentication and token refresh.
- Driver request, trip, delivery, wallet, and location endpoints are integrated.
- Driver-specific APIs are separate from Customer APIs.

### Backend
- Backend exposes customer, driver, wallet, catalog, and admin endpoints.
- API documentation is extensive and is the source of truth.
- Backend uses PostgreSQL and environment-based configuration.

## 9. Customer-Driver Integration

The intended flow is supported at the API level:
1. Customer creates a shipment draft.
2. Customer enters cargo, locations, photos, and payment details.
3. Customer requests quotes and accepts a quote.
4. Customer confirms/submits the shipment.
5. Shipment becomes available to drivers.
6. Driver accepts the shipment.
7. Backend assigns the driver.
8. Customer tracks the shipment.
9. Driver completes delivery.

Verification status:
- Customer and Driver apps both call the same backend.
- Driver acceptance is reflected through shipment status and trip data.
- Tracking endpoint provides driver location and status.
- Real-time behavior, notifications, and map rendering require device testing.
- No evidence of customer-side driver browsing or selection exists, preserving the business rule.

## 10. Testing Results

### Customer App
- `flutter analyze`: No issues found.
- `flutter test`: 40 tests passed.
- `git diff --check`: only CRLF line-ending warnings.

### Driver App
- `flutter analyze`: No issues found.
- `flutter test`: 30 tests passed.

### Backend
- No npm test script is defined.
- Backend syntax and runtime behavior were not executed in this analysis.

## 11. Critical Issues and Priorities

1. Critical: Card payment registration is not supported by documented backend APIs.
2. Critical: Payment confirmation and receipt screens depend on undocumented backend data.
3. High: Several Customer screens remain static or mock-backed.
4. High: Payout-account management is undocumented.
5. High: Grouped shipment features are not integrated in the Customer App.
6. Medium: Tracking UI uses coordinate text rather than a full map.
7. Medium: Wallet transaction filtering is client-side after pagination.
8. Medium: Device-level runtime behavior requires manual testing.
9. Low: CRLF line-ending warnings in working tree.

## 12. Recommended Next Development Steps

1. Document and implement card payment and payout-account APIs if required by product scope.
2. Replace static/mock Customer screens with documented API integrations.
3. Add backend integration tests for critical shipment and wallet flows.
4. Implement receipt and payment-confirmation screens only after backend response contracts are available.
5. Perform manual device testing for maps, location, camera, notifications, and real-time tracking.
6. Standardize line endings to remove CRLF warnings.
7. Add automated tests for cancellation fees, negative balances, and driver acceptance flow.
