# Customer App — Design Specifications

Extracted from Figma data dump. Color tokens: `fill_a04cf29e`=#17281E (dark green), `fill_658ab2fa`=#FFFFFF (white), `fill_23df9376`=#EA4227 (red/orange), `fill_0d0c9a0e`=#A7A8AC (gray), `fill_f584bf6f`=#F1F1F1 (light gray). Typography: Poppins (primary), Noto Sans Arabic. All screens 390×844px, column layout, background fill_658ab2fa (#FFFFFF).

---

## 1. Customer / Splash — node 1:294

**Frame:** column, alignItems stretch, 390×844, bg #FFFFFF.
**Status bar** (EL-60141d05): row, padding 0 24px, space-between, alignItems center, height 44. Time "9:41" Poppins Medium 14 #17281E. Connectivity icons 18×18.

**Screen content** (EL-c93632e9): column, alignSelf stretch, gap 16px, fill/fill.
**Splash brand** (EL-4568da53): column, center, gap 24px, fill/fill.
- IMAGE-SVG "Wasla movement mark": 116×83.52, fill #EA4227.
- TEXT "wasla": Poppins Bold 40 #FFFFFF.
- TEXT "MAKE LOGISTICS SIMPLE.": Poppins Regular 13, letterSpacing 0.1538em #FFFFFF.

**Home indicator area** (EL-35658ee4): row, center, height 20. RECTANGLE 128×4 #FFFFFF borderRadius 2px.

---

## 2. Customer / Onboarding / Move anything. — node 1:311

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Status bar** same as Splash (time 9:41).

**Screen content** (EL-c93632e9): column, gap 16px.
**Onboarding content** (EL-b276d1d4): column, padding 24px, gap 24px.
- **Brand and skip** (EL-bb582553): row, space-between. Wasla mark 40×28.8 #EA4227. "Skip" Poppins Regular 13 #17281E.
- RECTANGLE "Egyptian logistics photography": layout_f024eaeb height 332, image fill, borderRadius 12px.
- **Pagination** (EL-eda14dc5): row, gap 8px. Active indicator 32×4 #EA4227 borderRadius 2px. Two inactive 8×4 #A7A8AC borderRadius 2px.
- TEXT "Move anything.": Poppins Bold 32 #17281E.
- TEXT "Furniture, packages, goods or appliances. One simple way to get it there.": Poppins Regular 16 #17281E.
- TEXT "MAKE LOGISTICS SIMPLE." (EL-fd51ac07): Poppins Regular 12 #17281E.

**Next action** (EL-18f36189): column, padding 8 24 24, gap 8.
- INSTANCE Button primary default (1:67): 56px height, fill #EA4227, borderRadius 8px. Label "Continue" Poppins Medium 15 #FFFFFF.

**Home indicator** same.

---

## 3. Customer / Onboarding / Find the right truck. — node 1:338

Same structure as Move anything. Pagination second dot active. TEXT "Find the right truck." Poppins Bold 32. TEXT "Tell us about your cargo. Wasla finds the right fit — without the guesswork." Poppins Regular 16. Button "Continue".

---

## 4. Customer / Onboarding / Track every move. — node 1:365

Same structure. Third dot active. TEXT "Track every move." Poppins Bold 32. TEXT "From your gate to their door. Real-time updates, clear ETAs and a driver you can reach." Button label "Get started".

---

## 5. Customer / Welcome — node 1:392

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Status bar** same.

**Welcome content** (EL-403): column, padding 32px, center, gap 32px, fill/fill.
- IMAGE-SVG Wasla mark: 80×57.6 #EA4227.
- TEXT "One app. Every move.": Poppins Bold 36 #17281E.
- TEXT "Welcome to Wasla. Move your world with trusted local drivers and the right truck for the job.": Poppins Regular 16 #17281E.
- IMAGE-SVG "Vehicle illustration": 260×140 #FFFFFF stroke #17281E 2px.
- **Status label** (EL-066ba233): row, padding 6 8, gap 6, #F1F1F1 borderRadius 8px. IMAGE-SVG shield-check 14×14. TEXT "Built for Egypt. Ready for your next move." Poppins Medium 11 #17281E.
- TEXT "By continuing, you agree to our Terms and Privacy Policy.": Poppins Regular 12 #17281E.

**Next action** (EL-413): column, padding 8 24 24, gap 8.
- INSTANCE Button secondary default (1:81): fill #FFFFFF, stroke #17281E 1px, borderRadius 8px, height 56. Label "I already have an account" Poppins Medium 15 #17281E.
- INSTANCE Button primary default (1:67): fill #EA4227. Label "Continue with phone".

**Home indicator** same.

---

## 6. Customer / Login — node 1:418

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Status bar** same.

**Screen heading** (EL-283bd72a): column, padding 8? Actually EL-283bd72a row? Let's note: EL-283bd72a layout mode column, alignSelf stretch, padding 16? Hmm. Actually layout template. Contains Context (back arrow + "LOGIN" Poppins Bold 11 #17281E) and TEXT "Welcome back" Poppins Bold 26 #17281E.

**Screen content** (EL-d4e73f1a): column, padding 0 24 16, gap 16, fill/fill.
- TEXT "Sign in with your phone number. We'll send you a secure code.": Poppins Regular 14 #17281E.
- INSTANCE Input/Phone Filled (1:134): column gap 8. Label "Phone number" Poppins Medium 12. Input surface #F1F1F1 borderRadius 8px, padding 16, gap 12. Icon phone 20×20. Value "+20 100 234 5678" Poppins Regular 14.
- **Card** (EL-e03670ed): column padding 16, gap 12, #F1F1F1 borderRadius 12px. Detail row: icon lock-keyhole 20×20. TEXT "Phone-first. No password to remember." Poppins Regular 13 lineHeight 32px.
- TEXT "New to Wasla? · Create account" Poppins Regular 13 boldWeight 500 #17281E.
- TEXT "Need help signing in? Contact support." Poppins Regular 12 #17281E.

**Next action**: Button primary "Continue" (label resolved from component property "Label / Primary Default" = "Continue"... actually property default "Continue").

**Home indicator** same.

---

## 7. Customer / Sign up — node 1:448

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: "CREATE ACCOUNT" Poppins Bold 11, "Let's get moving" Poppins Bold 26.

**Screen content** (EL-d4e73f1a): column, padding 0 24 16, gap 16.
- INSTANCE Input/Full name Filled (1:128): label "Full name", icon user-round, value "Mariam Adel".
- INSTANCE Input/Phone number Filled (1:134).
- FRAME "Input / Email · optional / Filled": label "Email · optional", icon mail, value "mariam.adel@email.com" Poppins Regular 14.
- Detail row: icon square-check, TEXT "I agree to the Terms and Privacy Policy" Poppins Regular 13.
- Card: TEXT "Your number is shared only with your assigned driver during a trip." Poppins Regular 12.

**Next action**: Button primary (label resolved "Continue" → component property "Label / Primary Default").

**Home indicator** same.

---

## 8. Customer / Phone number — node 1:483

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: "SECURE VERIFICATION" Poppins Bold 11, "Your phone number" Poppins Bold 26.

**Screen content** (EL-bf1bc05c): column, padding 0 24 16, gap 16.
- TEXT "Use a number you can receive messages on in Egypt." Poppins Regular 14.
- Input/Country Filled: label "Country", icon chevron-down, value "Egypt +20" Poppins Regular 14.
- Input/Mobile number Focused: label "Mobile number", input surface stroke #EA4227 2px borderRadius 8px, icon phone, value "100 234 5678".
- Status label: icon clock, TEXT "Code expires in 5 minutes" Poppins Medium 11.
- TEXT "We'll never post or share your number publicly." Poppins Regular 12.

**Next action**: Button primary "Send verification code".

**Home indicator** same.

---

## 9. Customer / OTP verification — node 1:522

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: back arrow + bell icon. TEXT "Check your messages" Poppins Bold 26.

**Screen content** (EL-d4e73f1a): column, padding 0 24 16, gap 16.
- TEXT "Enter the 6-digit code sent to +20 100 234 5678." Poppins Regular 14.
- **OTP entry** (EL-f96bbce8): row, center, gap 8, fill/fill height? Actually row justifyContent center gap 8. Six OTP digits:
  - Filled digits: frame 44×44? layout_c008c9df row center, #F1F1F1 borderRadius 8px, stroke? For filled ones (EL-1b74cffe) fill #F1F1F1 stroke #F1F1F1 2px. Text Poppins Bold 24 #17281E: "4","8","2","6","1".
  - Empty digit: frame fill #F1F1F1 stroke #EA4227 2px borderRadius 8px, text empty.
- TEXT "Resend code in · 00:24" Poppins Regular 13 boldWeight 500.
- TEXT "Wrong number? · Edit phone" Poppins Regular 13 boldWeight 500.
- Card: icon shield-check, TEXT "Never share this code with anyone." Poppins Regular 13.

**Next action**: Button primary "Verify and continue".

**Home indicator** same.

---

## 10. Customer / Home — node 1:565

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Status bar** same.

**Screen heading** (EL-283bd72a): back? Context: Wasla mark 32? Actually IMAGE-SVG Wasla mark layout a1d057c3 32×? width 32 height 23.04 fill #EA4227. TEXT "CAIRO, EGYPT" Poppins Medium 11 #17281E (uppercase). TEXT "Morning, Mariam" Poppins Bold 26 #17281E.

**Scroll viewport** (EL-dea70495): column, fill/fill height 669.
**Screen content** (EL-efbbce65): column, padding 0 24 16, gap 16, fill fixed height 669.
- **Cairo route map** (EL-20a56e5c): 390? Actually frame height 192 #F1F1F1 borderRadius 12px. Contains SVG streets, Nile, text "NASR CITY" Poppins Medium 14, "El Nasr Road" Poppins Regular 10, "MAADI" Poppins Regular 12. Shipment route stroke #EA4227 5px. Pickup marker #17281E circle 32×32 with white ellipse center 10×10. Destination marker #EA4227 32×32 with map-pin. Nearby vehicles #FFFFFF 32×32 borderRadius 8px with truck icon. Map controls locate-me 44×44 #FFFFFF borderRadius 8px. Map context chip #FFFFFF borderRadius 8px padding 8: "Closest truck · 8 min away" Poppins Medium 11 #17281E.
- TEXT "Where are you moving something?" Poppins Bold 20 #17281E.
- **Card** (EL-dc55d016): #F1F1F1 borderRadius 12px padding 16? Actually layout_bf808a75 column padding 16 gap 4. Detail row circle-dot icon + "Pickup location" Poppins Regular 13 lineHeight 32px. Detail row map-pin + "Where to?" Poppins Regular 13.
- INSTANCE Button primary "Move something" fill #EA4227.
- **Card** (EL-7a27c414): #F1F1F1 stroke #EA4227 2px borderRadius 12px padding 16 gap 8. sparkles icon. "Not sure which truck you need?" Poppins Regular 13. "Let Wasla choose it for you." Poppins Regular 12. "Estimate my cargo · →" Poppins Bold 13 #EA4227.
- **Quick cargo shortcuts** (EL-f96bbce8): row center gap 8 height 48? Actually layout_fd6745d9 row padding 12 8 16 height 80. Five quick categories: Furniture, Packages, Appliances, Commercial, Other. Each column center gap 4: icon 20×20 #17281E, label Poppins Medium 9 #17281E.

**Bottom navigation** (EL-27ad4676): instance 1:205, Audience=Customer Active=Home. Height 80, padding 12 8 16, #FFFFFF stroke top 1px #F1F1F1. Five items: Home (active #EA4227), Trips, Messages, Wallet, Profile (inactive #17281E). Icons 24? Actually layout 24×24. Labels Poppins Medium 10.

---

## 11. Customer / Home / Your activity — node 1:649

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: Wasla mark, "HOME CONTINUED" Poppins Bold 11, "Your next move" Poppins Bold 26.

**Screen content** (EL-d4e73f1a): column, padding 0 24 16, gap 16.
- TEXT "Active shipment" Poppins Bold 18 #17281E.
- **Card/Shipment/Active** (EL-f24acc80): #F1F1F1 borderRadius 12px height 224. Shipment heading row space-between: Status label #F1F1F1 borderRadius 8px padding 6 8 with truck icon + "Active" Poppins Medium 11 #EA4227. TEXT "WS-20481" Poppins Medium 11 #17281E. TEXT "Nasr City → Maadi" Poppins Bold 16 #17281E. TEXT "18 Oct · 14:00 · Quarter Truck" Poppins Regular 12 #17281E. TEXT "Ahmed Hassan · ★ 4.9 · EGP 540" Poppins Regular 13 boldWeight 500. Progress bar: two rectangles 4px height, first #EA4227, second #F1F1F1, "2 OF 6" Poppins Medium 11.
- TEXT "Recent trips" Poppins Bold 18.
- Card: route icon + "Heliopolis → New Cairo · EGP 420" boldWeight 500. "12 Oct · Small Pickup · Completed" Poppins Regular 12.
- TEXT "Saved locations" Poppins Bold 18.
- Card: house icon "Home · Nasr City · ›". building-2 icon "Office · Maadi · ›".
- INSTANCE Button primary "Move something".

**Bottom navigation** same (Home active).

---

## 12. Customer / Booking / Cargo category — node 1:695

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: back arrow, "1 OF 6" Poppins Bold 11, "What are you moving?" Poppins Bold 26.

**Screen content** (EL-d4e73f1a): column, padding 0 24 16, gap 16.
- **Booking progress**: row gap 4 padding 4. Six segments: first #EA4227 32×4, rest #F1F1F1 8×4, all borderRadius 2px.
- TEXT "Choose the closest match. We'll help you with the details." Poppins Regular 14.
- **Cargo categories** (EL-bc40306a): column gap 8? Actually layout 0e060a3b column padding 16 gap 12 borderRadius 12 #F1F1F1. Cards:
  - Selected: #F1F1F1 stroke #EA4227 2px borderRadius 12px padding 16 gap 8 (layout_bf808a75). armchair icon 20×20. "Furniture · Selected" Poppins Regular 13 boldWeight 500.
  - Others (packages, refrigerator, warehouse, hard-hat, boxes): #F1F1F1 borderRadius 12px padding 12 8? layout_dc55d016 row padding 16? Actually EL-dc55d016 layout_0eb60b7b row padding 16 gap 12 alignItems center #F1F1F1 borderRadius 8? Let's use: Card #F1F1F1 borderRadius 12px (EL-dc55d016 has borderRadius 8? Wait EL-dc55d016 borderRadius 8px). Hmm. Actually EL-dc55d016: layout_0eb60b7b row padding 16 gap 12 #F1F1F1 strokes #F1F1F1 borderRadius 8px. Text "Packages · ›" etc Poppins Regular 13 boldWeight 500.

**Next action**: Button primary "Continue".

**Home indicator** same.

---

## 13. Customer / Booking / Pickup location — node 1:755

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: "2 OF 6" Poppins Bold 11, "Where do we pick up?" Poppins Bold 26.

**Screen content** (EL-d4e73f1a): column, padding 0 24 16, gap 16.
- **Booking progress**: 2 of 6 filled.
- INSTANCE Input/Pickup location/Focused (1:115): label "Pickup location" #EA4227 focus stroke. Value "12 Abbas El Akkad, Nasr City".
- **Cairo route map** (EL-14f9febd): height 224 #F1F1F1 borderRadius 12px. Contains streets, Nile, text labels, shipment route, pickup marker #17281E, destination marker #EA4227, map controls, map context chip "Pickup A · Pin at main entrance".
- Detail row: locate-fixed icon + "Use my current location".
- Detail row: map icon + "Choose on map" (EL-629e3254) Poppins Regular 13.
- Card: house icon "Home · Nasr City", building-2 icon "Office · Maadi".

**Next action**: Button primary "Confirm pickup".

**Home indicator** same.

---

## 14. Customer / Booking / Drop-off location — node 1:819

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: "2 OF 6" Poppins Bold 11, "Where is it going?" Poppins Bold 26.

**Screen content**: column, padding 0 24 16, gap 16.
- Booking progress: 2 of 6.
- INSTANCE Input/Drop-off location/Focused (1:115): label "Drop-off location", value "18 Road 9, Maadi".
- Cairo route map (height 224): map context chip "Drop-off C · Building entrance".
- Detail row: map icon + "Choose on map".
- Card: building-2 icon "Office · 18 Road 9, Maadi", history icon "Recent · Heliopolis warehouse".
- TEXT "Add a gate, floor or landmark in cargo notes." Poppins Regular 12.

**Next action**: Button primary "Confirm drop-off".

**Home indicator** same.

---

## 15. Customer / Booking / Multi-stop route — node 1:880

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: "2 OF 6 · ALTERNATE ROUTE" Poppins Bold 11, "Add a stop, if you need" Poppins Bold 26.

**Scroll viewport** (EL-dea70495) height 670.
**Screen content** (EL-897): column, padding 0 24 16, gap 16, fixed height 670.
- Booking progress: 2 of 6.
- **Shipment route card** (EL-f24acc80): #F1F1F1 borderRadius 12px padding 16 gap 4. Detail rows:
  - circle-dot + "12 Abbas El Akkad, Nasr City · Pickup" (boldWeight 500).
  - plus + "8 Makram Ebeid, Nasr City · Pickup B" (boldWeight 500).
  - map-pin + "18 Road 9, Maadi · Drop-off" (boldWeight 500).
- Card: three text rows with edit role.
- Button secondary: plus icon + "Add stop" Poppins Medium 15 #17281E, #FFFFFF stroke #17281E? Actually EL-35c1518d layout_2597d523 fill #FFFFFF stroke #17281E? Wait EL-35c1518d fills fill_658ab2fa strokes fill_a04cf29e strokeWeight 1px borderRadius 8px height 56.
- Cairo route map (height 184) #F1F1F1 borderRadius 12px: streets, Nile, labels, shipment route, pickup marker, destination marker, map controls.
- TEXT "Extra stops update the route and price before you confirm. This alternate route is not the sample booking." Poppins Regular 12.

**Next action**: Button primary "Confirm route".

**Home indicator** same.

---

## 16. Customer / Booking / Cargo details — node 1:947

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: "3 OF 6" Poppins Bold 11, "Tell us about your cargo" Poppins Bold 26.

**Screen content** (EL-d4e73f1a): column, padding 0 24 16, gap 16.
- Booking progress: 3 of 6.
- Input "What are you moving?" Filled: #F1F1F1 borderRadius 8px, icon package, value "Sofa, washing machine, 8 boxes, 2 chairs".
- **Cargo measurements** (EL-f96bbce8): row center gap 8 height 48? Actually layout row center gap 8 height 48 #F1F1F1 borderRadius 8px. Contains two inputs side by side:
  - Input/Item count Filled (1:171): icon hash, value "12 items".
  - Input/Approx. weight Filled (1:177): icon weight, value "Not sure".
- Input "Approx. size" Filled: icon ruler, value "About one room".
- Card (EL-dc55d016): #F1F1F1 borderRadius 8px? Actually EL-dc55d016 borderRadius 8px row padding 16 gap 12. Two detail rows:
  - wine icon + "Fragile items? · Yes ✓" boldWeight 500.
  - users-round icon + "Need loading help? · 2 helpers ✓" boldWeight 500.
- Input "Notes for the driver" Filled: icon notebook-pen, value "2nd floor. Lift available. Use gate 2."
- TEXT "No technical details needed. A photo helps us estimate." Poppins Regular 12.

**Next action**: Button primary "Find my truck".

**Home indicator** same.

---

## 17. Customer / AI / Capture cargo — node 1:1006

**Frame:** column, stretch, 390×844, bg #FFFFFF.
**Screen heading**: back arrow, "WASLA AI" Poppins Bold 11 #17281E (EL-dee667b7), "Show us what's moving" Poppins Bold 26.

**Scroll viewport** (EL-dea70495) height 567.
**Screen content** (EL-1023): column, padding 0 24 16, gap 16, fixed height 567.
- TEXT "Take a clear photo of all your items. Include something familiar for scale." Poppins Regular 14.
- RECTANGLE "Cargo photo preview": height 280, image fill, borderRadius 12px.
- Card (EL-e03670ed): #F1F1F1 borderRadius 12px padding 16 gap 12. Detail row: camera icon + "Photo 1 of 3 · Living room" Poppins Regular 13. TEXT "Add another angle · +" boldWeight 500. TEXT "Keep every item visible. Don't include people or private documents." Poppins Regular 12.
- Status label: shield-check + "Photos only used to estimate your shipment" Poppins Medium 11.

**Next action**: row center gap 8 height 56 #F1F1F1 borderRadius 8px? Actually EL-18f36189 column padding 8 24 24 gap 8 contains two buttons:
- Button secondary: "Upload from gallery" fill #FFFFFF stroke #17281E.
- Button primary: "Use these photos" fill #EA4227.

**Home indicator** same.

---

## Shared Design Tokens

**Colors:**
- Primary dark: #17281E
- White: #FFFFFF
- Accent (red/orange): #EA4227
- Gray: #A7A8AC
- Light gray surface: #F1F1F1

**Typography:** Poppins (primary), Noto Sans Arabic. Weights 400/500/700. Sizes 9,10,11,12,13,14,15,16,18,20,24,26,32,36,40.

**Spacing:** padding 16px, 24px, 8px; gaps 4,8,12,16,24px. Card radius 8-12px. Button height 56px radius 8px. Input height 56? Actually input surface padding 16 gap 12. Status bar height 44. Bottom nav height 80. Home indicator 4px.

**Buttons:** Primary fill #EA4227 text #FFFFFF Poppins Medium 15 radius 8px height 56px padding 16px. Secondary fill #FFFFFF stroke #17281E 1px text #17281E.

**Inputs:** surface #F1F1F1 radius 8px padding 16px gap 12px. Label Poppins Medium 12 #17281E. Value Poppins Regular 14 #17281E. Focused stroke #EA4227 2px.

**Cards:** #F1F1F1 radius 8-12px padding 16px. Status label #F1F1F1 radius 8px padding 6 8 gap 6.

**Bottom nav:** #FFFFFF top stroke #F1F1F1 1px, height 80, padding 12 8 16, items column center gap 4. Active #EA4227, inactive #17281E. Labels Poppins Medium 10.

**Icons:** Lucide-style, typically 20×20 in inputs, 14×14 in chips, 24×24 in nav.
