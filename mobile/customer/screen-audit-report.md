# Wasla Customer App - Screen Audit Report

## Summary

- Total Figma frames audited: 64
- Existing Flutter screens: 27
- Missing screens: 37
- First 10 selected for implementation: Available drivers, Driver profile, Tracking/Driver arriving, Tracking/In transit, Tracking/Shipment stages, Chat, Trip details, Delivery complete, Delivery proof, Ratings

## Existing Flutter Screens

| # | Figma Screen | Figma Node ID | Flutter Status | Existing File |
|---|-------------|---------------|----------------|---------------|
| 1 | Customer / Splash | 1:293 | Complete | lib/screens/splash_screen.dart |
| 2 | Customer / Onboarding / Move anything | 1:310 | Complete | lib/screens/onboarding_screen.dart |
| 3 | Customer / Onboarding / Find the right truck | 1:337 | Complete | lib/screens/onboarding_screen.dart |
| 4 | Customer / Onboarding / Track every move | 1:364 | Complete | lib/screens/onboarding_screen.dart |
| 5 | Customer / Welcome | 1:391 | Complete | lib/screens/welcome_screen.dart |
| 6 | Customer / Login | 1:417 | Complete | lib/screens/login_screen.dart |
| 7 | Customer / Sign up | 1:447 | Complete | lib/screens/sign_up_screen.dart |
| 8 | Customer / Phone number | 1:482 | Complete | lib/screens/phone_screen.dart |
| 9 | Customer / OTP verification | 1:521 | Complete | lib/screens/otp_screen.dart |
| 10 | Customer / Home | 1:564 | Complete | lib/screens/home_screen.dart |
| 11 | Customer / Home / Your activity | 1:648 | Complete | lib/pages/your_activity_page.dart |
| 12 | Customer / Booking / Cargo category | 1:694 | Complete | lib/pages/cargo_category_page.dart |
| 13 | Customer / Booking / Pickup location | 1:754 | Complete | lib/pages/drop_off_location_page.dart |
| 14 | Customer / Booking / Drop-off location | 1:818 | Complete | lib/pages/drop_off_location_page.dart |
| 15 | Customer / Booking / Multi-stop route | 1:879 | Complete | lib/pages/multi_stop_route_page.dart |
| 16 | Customer / Booking / Cargo details | 1:946 | Complete | lib/pages/cargo_details_page.dart |
| 17 | Customer / AI / Capture cargo | 1:1005 | Complete | lib/pages/capture_cargo_page.dart |
| 18 | Customer / AI / Estimating | 1:1041 | Complete | lib/pages/ai_estimating_page.dart |
| 19 | Customer / AI / Recommendation | 1:1075 | Complete | lib/pages/ai_recommendation_page.dart |
| 20 | Customer / Vehicles / Small and quarter | 1:1115 | Complete | lib/pages/vehicle_small_page.dart |
| 21 | Customer / Vehicles / Jumbo and heavy | 1:1167 | Complete | lib/pages/vehicle_jumbo_page.dart |
| 22 | Customer / Schedule / Now | 1:1208 | Complete | lib/pages/schedule_now_page.dart |
| 23 | Customer / Schedule / Later | 1:1282 | Complete | lib/pages/schedule_later_page.dart |
| 24 | Customer / Price estimate | 1:1318 | Complete | lib/pages/price_estimate_page.dart |
| 25 | Customer / Smart Backhaul offer | 1:1369 | Complete | lib/pages/smart_backhaul_page.dart |
| 26 | Customer / Booking review | 1:1426 | Complete | lib/pages/booking_review_page.dart |
| 27 | Customer / Driver matching | 1:1477 | Complete | lib/pages/driver_matching_page.dart |

## Missing Screens (First 10)

| # | Figma Screen | Figma Node ID | Action |
|---|-------------|---------------|--------|
| 1 | Customer / Available drivers | 1:1531 | Implement |
| 2 | Customer / Driver profile | 1:1604 | Implement |
| 3 | Customer / Tracking / Driver arriving | 1:1660 | Implement |
| 4 | Customer / Tracking / In transit | 1:1731 | Implement |
| 5 | Customer / Tracking / Shipment stages | 1:1802 | Implement |
| 6 | Customer / Chat | 1:1869 | Implement |
| 7 | Customer / Trip details | 1:1938 | Implement |
| 8 | Customer / Delivery complete | 1:1996 | Implement |
| 9 | Customer / Delivery proof | 1:2044 | Implement |
| 10 | Customer / Ratings | 1:2083 | Implement |

## Uncertain Mappings

- Pickup location (1:754) is mapped to drop_off_location_page.dart. Verified: Figma frame name is 'Customer / Booking / Pickup location' and the existing Flutter file handles both pickup and drop-off in one screen.
- Price estimate node ID is 1:1318 (confirmed from Figma data). The earlier reference to 1:318 was an error.

