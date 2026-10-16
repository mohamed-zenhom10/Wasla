"""Cargo analyzer UI: drag & drop images, get object cards (type / size / weight).

Run:   python app.py
Open:  http://localhost:8000
Needs: pip install ollama   (optional: pip install pillow  -> faster, resizes images)
"""
import io
import json
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import ollama

MODEL_NAME = "qwen3-vl:8b"
PORT = 8000
MAX_SIDE = 768  # smaller image = faster (lower accuracy, which is fine here)
NUM_PREDICT = 1600  # too small a value cuts the JSON in half -> "failed" images

PROMPT = """List the main objects in the image that would need transporting (max 6). Rough estimates are fine.
Reply with JSON only, like this example (replace the values with your estimates):
{"objects":[{"object":"refrigerator","category":"appliance","dimensions_cm":{"height":170,"width":60,"depth":65},"weight_kg":{"min":60,"max":90},"material":"metal","confidence":0.7,"note":"يُنقل في وضع رأسي"}]}
Each object once. "note" is one short Arabic handling note, or "بدون ملاحظات"."""

try:
    from PIL import Image
except ImportError:
    Image = None


def shrink(data: bytes) -> bytes:
    if Image is None:
        return data
    try:
        img = Image.open(io.BytesIO(data)).convert("RGB")
        img.thumbnail((MAX_SIDE, MAX_SIDE))
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=85)
        return buf.getvalue()
    except Exception:
        return data


def extract_json(text: str):
    """Tolerant JSON parser: strips fences/chatter and repairs truncated output."""
    text = (text or "").strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text[:4].lower() == "json":
            text = text[4:]
    start = min([i for i in (text.find("{"), text.find("[")) if i >= 0], default=-1)
    if start < 0:
        raise ValueError("no JSON in model output")
    text = text[start:]
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    end = max(text.rfind("}"), text.rfind("]"))
    if end >= 0:
        try:
            return json.loads(text[: end + 1])
        except json.JSONDecodeError:
            pass
    # truncated: keep everything up to the last complete object and close the brackets
    cut = text.rfind("},")
    while cut > 0:
        for tail in ("}]}", "}]"):
            try:
                return json.loads(text[: cut + 1] + tail[1:])
            except json.JSONDecodeError:
                pass
        cut = text.rfind("},", 0, cut)
    raise ValueError("could not parse model output")


def normalize(parsed) -> dict:
    if isinstance(parsed, list):
        return {"objects": [o for o in parsed if isinstance(o, dict)]}
    if isinstance(parsed, dict):
        if isinstance(parsed.get("objects"), list):
            return {"objects": [o for o in parsed["objects"] if isinstance(o, dict)]}
        for v in parsed.values():  # model used another key name
            if isinstance(v, list) and v and isinstance(v[0], dict):
                return {"objects": v}
        if "object" in parsed:  # a single object returned bare
            return {"objects": [parsed]}
    return {"objects": []}


def chat(image: bytes, use_format: bool, use_think: bool) -> str:
    kwargs = dict(
        model=MODEL_NAME,
        messages=[{"role": "user", "content": PROMPT, "images": [image]}],
        keep_alive="30m",
        options={"temperature": 0, "num_ctx": 4096, "num_predict": NUM_PREDICT},
    )
    if use_format:
        kwargs["format"] = "json"
    if use_think:
        kwargs["think"] = False  # skip "thinking" = faster
    try:
        response = ollama.chat(**kwargs)
    except (TypeError, ollama.ResponseError):
        if not use_think:
            raise
        kwargs.pop("think")
        response = ollama.chat(**kwargs)
    return response["message"]["content"] or ""


def analyze(data: bytes) -> dict:
    image = shrink(data)
    last_error = "empty output"
    # attempt 1: strict JSON mode; attempt 2: free text (JSON mode sometimes
    # makes qwen3-vl return empty/looping output), parsed tolerantly
    for use_format in (True, False):
        raw = ""
        try:
            raw = chat(image, use_format, use_think=True)
            result = normalize(extract_json(raw))
            if result["objects"]:
                return result
            last_error = "model found no objects"
        except ValueError as e:
            last_error = str(e)
        print(f"[attempt format={use_format}] {last_error}\nRAW: {raw[:500]!r}\n")
    raise ValueError(last_error)


HTML = r"""<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>تحليل الشحن</title>
<style>
  :root{--bg:#0f1115;--card:#1a1d24;--line:#2a2f3a;--txt:#e8eaf0;--mut:#8b93a5;--acc:#4f8cff}
  *{box-sizing:border-box}
  body{margin:0;font-family:system-ui,"Segoe UI",Tahoma,sans-serif;background:var(--bg);color:var(--txt);padding:24px}
  .wrap{max-width:1000px;margin:auto}
  h1{font-size:22px;margin:0 0 16px}
  #drop{border:2px dashed var(--line);border-radius:16px;padding:48px 16px;text-align:center;color:var(--mut);cursor:pointer;transition:.15s}
  #drop.over{border-color:var(--acc);background:#4f8cff14;color:var(--txt)}
  #drop b{color:var(--txt);font-size:18px;display:block;margin-bottom:6px}
  .group{margin-top:28px}
  .ghead{display:flex;align-items:center;gap:14px;margin-bottom:12px}
  .ghead img{width:72px;height:72px;object-fit:cover;border-radius:10px;border:1px solid var(--line)}
  .ghead .t{font-size:14px;color:var(--mut)}
  .status{font-size:13px;color:var(--acc)}
  .status.err{color:#ff6b6b}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:12px}
  .card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px}
  .card h3{margin:0 0 4px;font-size:16px}
  .badge{display:inline-block;font-size:12px;background:#4f8cff22;color:var(--acc);padding:2px 8px;border-radius:99px;margin-bottom:10px}
  .row{display:flex;justify-content:space-between;font-size:14px;padding:5px 0;border-top:1px solid var(--line)}
  .row span:first-child{color:var(--mut)}
  .note{margin-top:8px;font-size:13px;background:#ffb84d1a;color:#ffd08a;padding:8px;border-radius:8px}
  .spin{display:inline-block;width:12px;height:12px;border:2px solid var(--acc);border-top-color:transparent;border-radius:50%;animation:s .7s linear infinite;vertical-align:-2px;margin-inline-end:6px}
  @keyframes s{to{transform:rotate(360deg)}}
</style>
</head>
<body>
<div class="wrap">
  <h1>📦 تحليل الشحن</h1>
  <div id="drop"><b>اسحب الصور وارميها هنا</b>أو اضغط للاختيار (تقدر ترفع أكتر من صورة)</div>
  <input id="file" type="file" accept="image/*" multiple hidden>
  <div id="results"></div>
</div>
<script>
const drop = document.getElementById('drop'), file = document.getElementById('file'), results = document.getElementById('results');
drop.onclick = () => file.click();
file.onchange = () => { handle(file.files); file.value = ''; };
['dragenter','dragover'].forEach(e => drop.addEventListener(e, ev => {ev.preventDefault(); drop.classList.add('over');}));
['dragleave','drop'].forEach(e => drop.addEventListener(e, ev => {ev.preventDefault(); drop.classList.remove('over');}));
drop.addEventListener('drop', ev => handle(ev.dataTransfer.files));
document.addEventListener('paste', ev => handle([...ev.clipboardData.files]));
window.addEventListener('dragover', e => e.preventDefault());
window.addEventListener('drop', e => e.preventDefault());

const esc = s => String(s ?? '-').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const rng = (a, b) => (a == null || b == null || a == b) ? esc(a ?? b) : esc(a) + ' – ' + esc(b);

let queue = Promise.resolve();
function handle(files) {
  [...files].filter(f => f.type.startsWith('image/')).forEach(f => {
    const g = document.createElement('div');
    g.className = 'group';
    g.innerHTML = `<div class="ghead"><img src="${URL.createObjectURL(f)}"><div><div class="t">${esc(f.name)}</div><div class="status"><span class="spin"></span>في الانتظار...</div></div></div><div class="grid"></div>`;
    results.prepend(g);
    queue = queue.then(() => run(f, g));
  });
}

async function run(f, g) {
  const status = g.querySelector('.status'), grid = g.querySelector('.grid');
  status.innerHTML = '<span class="spin"></span>جاري التحليل...';
  const t0 = performance.now();
  try {
    const r = await fetch('/analyze', {method: 'POST', body: f});
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || 'خطأ');
    const objs = j.objects || [];
    grid.innerHTML = objs.map(o => {
      const d = o.dimensions_cm || {}, w = o.weight_kg || {};
      const note = o.note && o.note !== 'بدون ملاحظات' ? `<div class="note">⚠️ ${esc(o.note)}</div>` : '';
      return `<div class="card"><h3>${esc(o.object)}</h3><span class="badge">${esc(o.category)}</span>
        <div class="row"><span>الحجم (سم)</span><span>${esc(d.height)} × ${esc(d.width)} × ${esc(d.depth)}</span></div>
        <div class="row"><span>الوزن (كجم)</span><span>${rng(w.min, w.max)}</span></div>
        <div class="row"><span>الخامة</span><span>${esc(o.material)}</span></div>
        <div class="row"><span>الثقة</span><span>${Math.round((+o.confidence || 0) * 100)}%</span></div>${note}</div>`;
    }).join('');
    status.textContent = objs.length ? `تم — ${objs.length} عنصر (${((performance.now()-t0)/1000).toFixed(1)} ث)` : 'مفيش عناصر اتعرفت';
  } catch (e) {
    status.className = 'status err';
    status.textContent = 'فشل: ' + e.message;
  }
}
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._send(200, HTML.encode("utf-8"), "text/html; charset=utf-8")

    def do_POST(self):
        if self.path != "/analyze":
            return self._send(404, b"{}")
        try:
            size = int(self.headers.get("Content-Length", 0))
            result = analyze(self.rfile.read(size))
            self._send(200, json.dumps(result, ensure_ascii=False).encode("utf-8"))
        except json.JSONDecodeError:
            self._send(500, json.dumps({"error": "الموديل رجّع ردّ مش JSON، جرب تاني"}, ensure_ascii=False).encode("utf-8"))
        except Exception as e:
            self._send(500, json.dumps({"error": str(e)}, ensure_ascii=False).encode("utf-8"))

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"Open http://localhost:{PORT}")
    webbrowser.open(f"http://localhost:{PORT}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()