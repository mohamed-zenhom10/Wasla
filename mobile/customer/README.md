# Wasla Customer app

The customer app uses the Wasla PostgreSQL-backed API for shipments, driver
offers, and live trip locations. Apply pending SQL updates from
[`backend/database/updates/`](../../backend/database/updates/) before deploying
backend changes.

## Run with TomTom maps

The customer tracking map requests TomTom map tiles, traffic tiles, and a
traffic-aware route once when the trip starts and again when it changes between
pickup and delivery. It reads GPS updates from the backend; it does not request
routes on each location poll.

Keep a separate, untracked `tomtom-key.json` in this directory. It belongs to
the Customer app; it is not read from or shared with the Driver app:

```json
{
  "TOMTOM_API_KEY": "your-customer-tomtom-key",
  "WASLA_API_URL": "https://wasla-api-464a.onrender.com/api"
}
```

Set a customer-specific TomTom key and backend URL there. From this directory:

```powershell
flutter pub get
flutter run -d edge --web-port 5174 --dart-define-from-file=tomtom-key.json
flutter build apk --release --dart-define-from-file=tomtom-key.json
```

Do not commit the key file. Keys passed as Dart defines are still included in a
client app/APK and can be extracted; restrict them by API and platform in
TomTom's developer portal.

The driver matching screen displays the route between pickup and delivery.
After a driver accepts, the map follows the driver's backend location to pickup,
then switches to the delivery destination once the shipment is loaded. A
missing key, routing failure, or unavailable GPS feed is shown in the map UI.
