# Wasla Driver app

The driver app uses the API contract in [`backend/API.md`](../../backend/API.md).
Authentication, driver applications, live availability, offers, and trip
updates are sent to the backend. Offer polling is every 5 seconds; driver
location is sent every 30 seconds online and every 10 seconds during a trip.

## Run the app

From `mobile/driver`:

```powershell
flutter pub get
flutter run
```

By default the app uses the hosted API:
`https://wasla-api-464a.onrender.com/api`. Its free host can take a while to
wake up; requests use a 90-second timeout.

To use a local backend, set the API URL when running:

```powershell
# Android emulator
flutter run --dart-define=WASLA_API_URL=http://10.0.2.2:3000/api

# iOS simulator
flutter run --dart-define=WASLA_API_URL=http://localhost:3000/api

# Physical phone: replace the address with your development computer's LAN IP
flutter run --dart-define=WASLA_API_URL=http://192.168.1.10:3000/api
```

Start and configure the backend first by following [`backend/README.md`](../../backend/README.md).
The phone/emulator and backend must be able to reach each other. Do not use
`localhost` for an Android emulator or a physical phone.

## Driver account and location

Sign in with an account whose API role includes `driver`, or register a driver
account and verify its email. The onboarding flow needs the catalog and policies
configured on the backend. A driver must be approved and have an active vehicle
before going online.

Allow location access when prompted. Location is required to go online and start
a trip. Keep location services enabled while working. Trip pickup and delivery
photos are uploaded directly to the API and must each be no larger than 5 MB.

## Validate

```powershell
flutter analyze
flutter test
```
