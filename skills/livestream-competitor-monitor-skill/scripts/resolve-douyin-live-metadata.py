import argparse
import asyncio
import json
import re
import socket
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

PROFILE_DIR = Path.home() / ".dy-crawler" / "profile"
CHROME_DEBUG_PORT = 9222
CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]

GAME_CANDIDATES = [
    "\u65e0\u5c3d\u51ac\u65e5",
    "\u7387\u571f\u4e4b\u6ee8",
    "\u5e15\u840c",
    "\u4e09\u56fd\u5fd7\u6218\u7565\u7248",
    "\u4e07\u56fd\u89c9\u9192",
    "\u5251\u4e0e\u8fdc\u5f81",
]


def find_chrome() -> str:
    for candidate in CHROME_CANDIDATES:
        if Path(candidate).exists():
            return candidate
    raise FileNotFoundError("Chrome was not found.")


def chrome_debug_running() -> bool:
    try:
        with socket.create_connection(("localhost", CHROME_DEBUG_PORT), timeout=1):
            return True
    except OSError:
        return False


def launch_chrome_detached() -> None:
    chrome = find_chrome()
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.Popen(
        [
            chrome,
            f"--remote-debugging-port={CHROME_DEBUG_PORT}",
            f"--user-data-dir={PROFILE_DIR}",
            "--disable-blink-features=AutomationControlled",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-sync",
            "--lang=zh-CN",
        ],
        creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
        close_fds=True,
    )
    for _ in range(20):
        if chrome_debug_running():
            return
        time.sleep(0.5)
    raise RuntimeError("Chrome launch timed out.")


def room_id_from_url(url: str) -> str:
    match = re.search(r"live\.douyin\.com/(\d+)", url)
    if match:
        return match.group(1)
    parsed = urlparse(url)
    return parsed.path.strip("/").split("/")[0] or "unknown"


def clean_value(value: str) -> str:
    value = re.sub(r"\s+", " ", value or "").strip()
    value = re.sub(r'[\\/:*?"<>|]', "_", value)
    return value[:80].strip(" -_|")


def clean_douyin_title(title: str) -> str:
    cleaned = title or ""
    cleaned = re.sub(r"\s*[-_|]\s*\u6296\u97f3\u76f4\u64ad\s*$", "", cleaned)
    cleaned = re.sub(r"\u7684\u6296\u97f3\u76f4\u64ad\u95f4\s*$", "", cleaned)
    cleaned = re.sub(r"\u7684\u76f4\u64ad\u95f4\s*$", "", cleaned)
    cleaned = cleaned.replace("\u6296\u97f3", "")
    cleaned = cleaned.replace("\u76f4\u64ad\u95f4", "")
    cleaned = cleaned.replace("\u76f4\u64ad", "")
    cleaned = re.sub(r"\u7684\s*$", "", cleaned)
    return clean_value(cleaned)


def extract_room_name(title: str, body_text: str, room_id: str) -> tuple[str, str]:
    candidates = []
    if title:
        cleaned = clean_douyin_title(title)
        candidates.append(cleaned)
    for line in (body_text or "").splitlines()[:80]:
        line = clean_value(line)
        if 2 <= len(line) <= 40 and any(token in line for token in GAME_CANDIDATES):
            candidates.append(line)
    for candidate in candidates:
        candidate = clean_value(candidate)
        if candidate:
            return candidate, "page_title_or_visible_text"
    return f"douyin-live-room-{room_id}", "room_id_fallback"


def infer_game_product(room_name: str, title: str, body_text: str) -> tuple[str, str]:
    combined = "\n".join([room_name or "", title or "", body_text or ""])
    for game in GAME_CANDIDATES:
        if game in combined:
            return game, "known_game_keyword"
    for value in (room_name, clean_douyin_title(title)):
        if value and "-" in value:
            prefix = clean_value(value.split("-", 1)[0])
            if 2 <= len(prefix) <= 30:
                return prefix, "title_prefix_before_dash"
    return "", "not_found"


def extract_viewer_count(body_text: str) -> tuple[str, str]:
    text = body_text or ""
    patterns = [
        r"([0-9]+(?:\.[0-9]+)?[wW\u4e07]?)\s*\u4eba\u5728\u770b",
        r"([0-9]+(?:\.[0-9]+)?[wW\u4e07]?)\s*\u89c2\u770b",
        r"\u89c2\u770b\u4eba\u6570[:\uff1a]?\s*([0-9]+(?:\.[0-9]+)?[wW\u4e07]?)",
    ]
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return match.group(1), "visible_text"
    return "", "not_found"


async def resolve_metadata(url: str, timeout_s: int) -> dict:
    from playwright.async_api import async_playwright

    room_id = room_id_from_url(url)
    metadata = {
        "url": url,
        "room_id": room_id,
        "room_name": f"douyin-live-room-{room_id}",
        "game_product_name": "",
        "viewer_count": "",
        "confidence": 0.2,
        "source": "room_id_fallback",
        "room_name_source": "room_id_fallback",
        "game_product_source": "not_found",
        "viewer_count_source": "not_found",
        "page_title": "",
        "resolved_at": datetime.now().isoformat(timespec="seconds"),
        "error": "",
    }
    async with async_playwright() as pw:
        if not chrome_debug_running():
            launch_chrome_detached()
        browser = await pw.chromium.connect_over_cdp(f"http://127.0.0.1:{CHROME_DEBUG_PORT}")
        context = browser.contexts[0] if browser.contexts else await browser.new_context()
        page = await context.new_page()
        try:
            await page.goto(url, wait_until="domcontentloaded", timeout=30_000)
        except Exception:
            pass
        await page.wait_for_timeout(max(1000, timeout_s * 1000))
        page_data = await page.evaluate(
            """() => ({
                title: document.title || "",
                bodyText: document.body ? document.body.innerText.slice(0, 30000) : ""
            })"""
        )
        await page.close()
    title = page_data.get("title", "")
    body_text = page_data.get("bodyText", "")
    room_name, room_source = extract_room_name(title, body_text, room_id)
    game_product, game_source = infer_game_product(room_name, title, body_text)
    viewer_count, viewer_source = extract_viewer_count(body_text)
    confidence = 0.2
    if room_source != "room_id_fallback":
        confidence += 0.4
    if game_product:
        confidence += 0.25
    if viewer_count:
        confidence += 0.1
    metadata.update(
        {
            "room_name": room_name,
            "game_product_name": game_product,
            "viewer_count": viewer_count,
            "confidence": round(min(confidence, 0.95), 2),
            "source": "playwright_page",
            "room_name_source": room_source,
            "game_product_source": game_source,
            "viewer_count_source": viewer_source,
            "page_title": title,
        }
    )
    return metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Resolve Douyin live room metadata.")
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", default="")
    parser.add_argument("--timeout", type=int, default=10)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        metadata = asyncio.run(resolve_metadata(args.url, args.timeout))
    except Exception as exc:
        room_id = room_id_from_url(args.url)
        metadata = {
            "url": args.url,
            "room_id": room_id,
            "room_name": f"douyin-live-room-{room_id}",
            "game_product_name": "",
            "viewer_count": "",
            "confidence": 0.1,
            "source": "error_fallback",
            "room_name_source": "room_id_fallback",
            "game_product_source": "not_found",
            "viewer_count_source": "not_found",
            "page_title": "",
            "resolved_at": datetime.now().isoformat(timespec="seconds"),
            "error": str(exc),
        }
    payload = json.dumps(metadata, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(payload, encoding="utf-8")
    print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
