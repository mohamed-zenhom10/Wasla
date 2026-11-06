
import requests
import json
from pathlib import Path

# -------------------------
# API CONFIGURATION
# -------------------------

API_KEY = "API"
API_URL = "https://api.ocr.space/parse/image"

# -------------------------
# IMAGE PATH
# -------------------------

BASE_DIR = Path(__file__).resolve().parent
image = BASE_DIR / "licensees.jpg"

if not image.is_file():
    print("ERROR: licensees.jpg not found next to the script!")
    exit()
# -------------------------
# OCR TEST
# -------------------------

for engine in [2, 3]:

    print(f"\nTesting OCR Engine {engine}...")

    try:
        with image.open("rb") as file:
            response = requests.post(
                API_URL,
                headers={"apikey": API_KEY},
                data={
                    "OCREngine": str(engine),
                    "isOverlayRequired": "true"
                },
                files={
                    "file": (image.name, file)
                },
                timeout=180
            )

        # -------------------------
        # HTTP ERROR HANDLING
        # -------------------------

        if response.status_code != 200:
            print("HTTP Status:", response.status_code)
            print("Server Response:")
            print(response.text[:3000])
            continue

        # -------------------------
        # JSON RESPONSE
        # -------------------------

        try:
            result = response.json()
        except ValueError:
            print("ERROR: Server returned invalid JSON.")
            print(response.text[:3000])
            continue

        # -------------------------
        # SAVE FULL JSON
        # -------------------------

        output = image.with_name(
            f"{image.stem}_engine_{engine}.json"
        )

        output.write_text(
            json.dumps(result, ensure_ascii=False, indent=2),
            encoding="utf-8"
        )

        # -------------------------
        # OCR PROCESSING ERROR
        # -------------------------

        if result.get("IsErroredOnProcessing"):
            print("OCR ERROR:")
            print(result.get("ErrorMessage"))
            print(result.get("ErrorDetails"))
            continue

        # -------------------------
        # EXTRACTED TEXT
        # -------------------------

        pages = result.get("ParsedResults", [])

        if not pages:
            print("No text detected.")
            continue

        for index, page in enumerate(pages, start=1):
            print(f"\n--- Page {index} ---")
            print(page.get("ParsedText", ""))

        print("\nOCR Exit Code:", result.get("OCRExitCode"))
        print("Processing Time:",
              result.get("ProcessingTimeInMilliseconds"), "ms")

        print("\nFull JSON saved:", output)

    except requests.exceptions.Timeout:
        print("ERROR: Request timed out.")

    except requests.exceptions.ConnectionError:
        print("ERROR: Could not connect to OCR.space.")

    except requests.exceptions.RequestException as error:
        print("REQUEST ERROR:", error)

    except Exception as error:
        print("UNEXPECTED ERROR:", error)

print("\nOCR testing finished.")
