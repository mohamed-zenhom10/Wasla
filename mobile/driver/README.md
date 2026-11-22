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

## TomTom maps and navigation

The Driver app uses TomTom raster map tiles, live traffic-flow tiles, and
traffic-aware routing, plus OCR.space for national-ID OCR. Put both keys in the
untracked `tomtom-key.json` in this directory:

```json
{
  "TOMTOM_API_KEY": "your-key",
  "NATIONAL_ID_OCR_API_KEY": "your-key"
}
```

Use that file for both development and APK builds:

```powershell
flutter run -d edge --web-port 5173 --dart-define-from-file=tomtom-key.json
flutter build apk --release --dart-define-from-file=tomtom-key.json
```

The keys are injected at build time and are not committed in the app source.
They are still included in a client app/APK and can be extracted, so restrict
them by API and platform in each provider's developer portal. The app does not
contain a mock-map fallback: missing keys and routing/network errors are shown
in the map UI.

Active trips request the fastest traffic-aware route once when navigation
starts. GPS updates locally estimate remaining route time and detect deviations;
no automatic route or traffic refresh requests run in the background. If GPS
stays over 75 m (adjusted for reported accuracy) from the route for two minutes,
the driver can choose whether to request a new route. TomTom map tiles are
loaded as the interactive map is viewed, and a new destination uses place
search.
GPS is streamed on-device; the existing Driver API location updates continue
every 10 seconds during a trip. The existing PostgreSQL/PostGIS tracking
endpoint stores those points and exposes the driver's current position and
pickup/drop-off stage to the owning customer.

From the driver home screen, choose **خطط مشوارك** to search for a destination
(for example, عين شمس). The planner uses the device's current GPS position as
the route origin and displays the route, live traffic ETA, and spoken guidance.
Pickup and delivery trips continue to use the same navigation map component.

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
