"""
抖音直播评论爬取器 - Playwright CDP 方案

原理：让浏览器自己解密 Protobuf/WebSocket，我们在 JS 渲染层截获明文评论。

用法：
    python crawler.py --url "https://live.douyin.com/直播间号"
    python crawler.py --url "https://live.douyin.com/直播间号" --output comments.jsonl

首次运行会弹出浏览器，如需登录请在浏览器内完成，之后自动继续。

依赖：
    pip install playwright
    playwright install chromium
"""

import argparse
import asyncio
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from playwright.async_api import async_playwright, Browser, Page

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

PROFILE_DIR = Path.home() / ".dy-crawler" / "profile"
CHROME_DEBUG_PORT = 9222
COMMENT_HTTP_PORT = 7891

CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]


def find_chrome() -> str:
    for p in CHROME_CANDIDATES:
        if Path(p).exists():
            return p
    raise FileNotFoundError("未找到 Chrome，请确认已安装")


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
    raise RuntimeError("Chrome 启动超时")

LIVE_ROOM_SELECTORS = [
    '[class*="webcast-chatroom"]',
    '[class*="ChatroomContentBox"]',
    '[class*="chatroom-message"]',
    '[class*="live-chatroom"]',
    '[class*="CommentList"]',
]

LOGIN_SELECTORS = [
    '[data-e2e="login-panel"]',
    '[class*="login-modal"]',
    '[class*="LoginModal"]',
    '[class*="login-dialog"]',
]

# ── 经 DOM 调试确认的选择器 ──────────────────────────────────────
# webcast-chatroom___list   → 评论列表容器（三个下划线）
# webcast-chatroom___item   → 单条评论节点
# webcast-chatroom___content-with-emoji-text → 评论正文
# 用户名无语义 class，通过位置推断（非 badge、非 content 的直接子 span）
# ────────────────────────────────────────────────────────────────

OBSERVER_JS = r"""
(function () {
    if (window.__DY_CRAWLER_OBSERVER_INSTALLED__) {
        console.log('[DY Crawler] Observer 已存在，跳过重复注入');
        return;
    }
    window.__DY_CRAWLER_OBSERVER_INSTALLED__ = true;

    const LIST_SEL    = '[class*="webcast-chatroom___list"]';
    const ITEM_SEL    = '[class*="webcast-chatroom___item"]';
    const CONTENT_SEL = '[class*="webcast-chatroom___content-with-emoji"]';

    // 系统通知关键词，命中则过滤
    const SYSTEM_PATTERNS = [
        /关注主播/,
        /发现更多直播/,
        /点击右上角/,
        /欢迎.*直播间/,
        /请遵守直播间/,
    ];
    function isSystemMsg(text) {
        return SYSTEM_PATTERNS.some(p => p.test(text));
    }

    function extractComment(node) {
        const contentEl = node.querySelector(CONTENT_SEL);
        if (!contentEl) return null;
        const content = contentEl.innerText.trim();
        if (!content) return null;

        // 用户名：在 contentEl 的父 div 的直接子 span 里，
        // 排除含 <img> 的 badge span 和包含 contentEl 的 wrapper span
        let user = '匿名';
        const innerDiv = contentEl.closest('div');
        if (innerDiv) {
            for (const span of innerDiv.querySelectorAll(':scope > span')) {
                if (span.querySelector('img')) continue;
                if (span.contains(contentEl)) continue;
                const t = span.innerText.trim();
                if (t) { user = t.replace(/[：:]\s*$/, '').trim(); break; }
            }
        }
        return { user, content };
    }

    function push(comment) {
        // 用 Image beacon 发到本地 HTTP 服务，无 CORS 问题，Python 死了也不影响 Chrome
        const data = encodeURIComponent(JSON.stringify({ ...comment, ts: Date.now() }));
        new Image().src = 'http://localhost:7891/?d=' + data;
    }

    function attachObserver(container) {
        const seenIds  = new Set(); // data-id 去重（虚拟滚动复用节点时仍唯一）
        const seenTexts = new Set(); // 无 data-id 时按「用户+内容」去重

        function getItemId(contentEl) {
            const item = contentEl.closest('[data-id]');
            return item ? item.getAttribute('data-id') : null;
        }

        function processContentEl(contentEl) {
            const content = contentEl.innerText.trim();
            if (!content || isSystemMsg(content)) return;

            const id = getItemId(contentEl);
            if (id) {
                if (seenIds.has(id)) return;
                seenIds.add(id);
            }

            let user = '匿名';
            const innerDiv = contentEl.closest('div');
            if (innerDiv) {
                for (const span of innerDiv.querySelectorAll(':scope > span')) {
                    if (span.querySelector('img')) continue;
                    if (span.contains(contentEl)) continue;
                    const t = span.innerText.trim();
                    if (t) { user = t.replace(/[：:]\s*$/, '').trim(); break; }
                }
            }

            if (!id) {
                const key = user + '\x00' + content;
                if (seenTexts.has(key)) return;
                seenTexts.add(key);
            }

            push({ user, content });
        }

        function scanContainer() {
            for (const el of container.querySelectorAll(CONTENT_SEL)) {
                processContentEl(el);
            }
        }

        // 初始抓取
        let existing = 0;
        for (const el of container.querySelectorAll(CONTENT_SEL)) {
            processContentEl(el);
            existing++;
        }
        console.log('[DY Crawler] 已抓已有评论 ' + existing + ' 条，挂载 Observer...');

        // MutationObserver 捕获新增节点（立即响应）
        const observer = new MutationObserver((mutations) => {
            const batch = [];
            for (const mut of mutations) {
                for (const node of mut.addedNodes) {
                    if (node.nodeType !== 1) continue;
                    if (node.matches && node.matches(CONTENT_SEL)) batch.push(node);
                    for (const el of node.querySelectorAll(CONTENT_SEL)) batch.push(el);
                }
            }
            batch.sort((a, b) => a.compareDocumentPosition(b) & 4 ? -1 : 1);
            for (const el of batch) processContentEl(el);
        });
        observer.observe(container, { childList: true, subtree: true });

        // 定时扫描补漏虚拟滚动复用节点（每 300ms）
        setInterval(scanContainer, 300);
        console.log('[DY Crawler] Observer 就绪');
    }

    function tryAttach() {
        // 先查一次，如果已经存在直接挂上
        const el = document.querySelector(LIST_SEL);
        if (el) { attachObserver(el); return; }

        // 否则用 MutationObserver 监听 DOM，容器一出现立刻挂上（比轮询快得多）
        const bodyObserver = new MutationObserver(() => {
            const found = document.querySelector(LIST_SEL);
            if (found) {
                bodyObserver.disconnect();
                attachObserver(found);
            }
        });
        bodyObserver.observe(document.documentElement, { childList: true, subtree: true });
        console.log('[DY Crawler] 等待评论容器出现...');
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', tryAttach);
    } else {
        tryAttach();
    }
})();
"""


async def wait_for_live_room(page: Page, timeout_s: int = 300) -> bool:
    print("[等待] 检测页面状态...", flush=True)
    deadline = asyncio.get_event_loop().time() + timeout_s
    login_hint_shown = False

    while asyncio.get_event_loop().time() < deadline:
        for sel in LIVE_ROOM_SELECTORS:
            try:
                if await page.query_selector(sel):
                    print("[就绪] 已进入直播间，开始监听评论", flush=True)
                    return True
            except Exception:
                pass

        for sel in LOGIN_SELECTORS:
            try:
                if await page.query_selector(sel) and not login_hint_shown:
                    print("[登录] 检测到登录提示，请在浏览器内扫码...", flush=True)
                    login_hint_shown = True
            except Exception:
                pass

        await asyncio.sleep(2)

    print("[超时] 未能进入直播间", flush=True)
    return False


def safe_filename(title: str, fallback: str) -> str:
    name = re.sub(r'[\\/:*?"<>|]', '_', title).strip() or fallback
    return name[:80]  # 限制长度


def is_same_live_room_url(url: str, target_room_id: str) -> bool:
    if not url or not target_room_id:
        return False
    parsed = urlparse(url)
    return parsed.netloc.endswith("douyin.com") and parsed.path.strip("/") == target_room_id


async def find_reusable_live_page(context, live_url: str) -> Page | None:
    target_room_id = room_id_from_url(live_url)
    for page in context.pages:
        try:
            if is_same_live_room_url(page.url, target_room_id):
                return page
        except Exception:
            continue
    return None


async def close_duplicate_live_pages(context, keep_page: Page, live_url: str) -> None:
    target_room_id = room_id_from_url(live_url)
    for page in list(context.pages):
        if page == keep_page:
            continue
        try:
            if is_same_live_room_url(page.url, target_room_id):
                await page.close()
        except Exception:
            continue


async def crawl(live_url: str, output_path: Path | None) -> None:
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    output_file = None  # 进入直播间后再确定文件名

    def open_output(path: Path):
        nonlocal output_file
        output_file = open(path, "a", encoding="utf-8")
        print(f"[输出] {path}", flush=True)

    def on_comment(raw: str) -> None:
        try:
            c = json.loads(raw)
        except json.JSONDecodeError:
            return
        ts = datetime.fromtimestamp(c.get("ts", 0) / 1000).strftime("%H:%M:%S")
        print(f"[{ts}] {c['user']}: {c['content']}", flush=True)
        if output_file:
            output_file.write(json.dumps(c, ensure_ascii=False) + "\n")
            output_file.flush()

    # 启动本地 HTTP 服务器接收评论（Image beacon，无 CORS 问题）
    class _Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            qs = parse_qs(urlparse(self.path).query)
            if "d" in qs:
                on_comment(qs["d"][0])
            self.send_response(200)
            self.send_header("Content-Type", "image/gif")
            self.send_header("Content-Length", "0")
            self.end_headers()
        def log_message(self, *args): pass

    http_server = HTTPServer(("localhost", COMMENT_HTTP_PORT), _Handler)
    threading.Thread(target=http_server.serve_forever, daemon=True).start()
    print(f"[HTTP] 评论接收服务启动 (端口 {COMMENT_HTTP_PORT})", flush=True)

    # 只用 CDP 做初始化：导航、注入脚本、获取标题，完成后立即断开
    # 断开后 Chrome 完全独立运行，Python 进程死亡不会影响浏览器窗口
    async with async_playwright() as pw:
        if chrome_debug_running():
            print(f"[连接] 复用已运行的 Chrome (端口 {CHROME_DEBUG_PORT})", flush=True)
        else:
            print(f"[启动] 以独立进程启动 Chrome (端口 {CHROME_DEBUG_PORT})...", flush=True)
            launch_chrome_detached()

        browser: Browser = await pw.chromium.connect_over_cdp(
            f"http://127.0.0.1:{CHROME_DEBUG_PORT}"
        )
        context = browser.contexts[0] if browser.contexts else await browser.new_context()

        page: Page | None = await find_reusable_live_page(context, live_url)
        if page:
            print("[复用] 使用已打开的直播间页面，避免重复开页", flush=True)
        else:
            page = await context.new_page()
        page.on("console", lambda msg: print(f"[JS] {msg.text}", flush=True)
                if "[DY" in msg.text else None)
        await page.add_init_script(OBSERVER_JS)

        await close_duplicate_live_pages(context, page, live_url)
        await page.bring_to_front()

        if not is_same_live_room_url(page.url, room_id_from_url(live_url)):
            print(f"[打开] {live_url}", flush=True)
            try:
                await page.goto(live_url, wait_until="domcontentloaded", timeout=30_000)
            except Exception as e:
                print(f"[警告] 页面加载超时（继续）: {e}", flush=True)

        try:
            await page.evaluate(OBSERVER_JS)
        except Exception as e:
            print(f"[警告] 评论监听脚本注入失败（继续等待页面脚本）: {e}", flush=True)

        ok = await wait_for_live_room(page, timeout_s=300)
        if not ok:
            return

        # 确定输出文件：优先用参数，否则用页面标题命名
        if output_path:
            open_output(output_path)
        else:
            try:
                title = await page.title()
                title = title.replace("抖音", "").replace("直播", "").strip(" -_|")
            except Exception:
                title = ""
            fallback = room_id_from_url(live_url)
            name = safe_filename(title, fallback) if title else fallback
            open_output(Path(f"{name}.jsonl"))

        print("[CDP] 初始化完成，Chrome 独立运行，评论继续通过 HTTP 接收", flush=True)

    # async with 退出后 Playwright 停止，但 connect_over_cdp 的 Chrome 不会被关闭
    # 之后只用 HTTP 服务器收评论，Python 进程可安全终止
    print("[监听] 实时评论（Ctrl+C 停止）:\n", flush=True)
    try:
        while True:
            await asyncio.sleep(1)
    except (KeyboardInterrupt, asyncio.CancelledError):
        print("\n[停止] 已退出", flush=True)
    finally:
        if output_file:
            output_file.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="抖音直播评论爬取器")
    parser.add_argument("--url", required=True, help="直播间 URL")
    parser.add_argument("--output", default=None, help="输出 JSONL 文件路径")
    return parser.parse_args()


def room_id_from_url(url: str) -> str:
    m = re.search(r"live\.douyin\.com/(\d+)", url)
    return m.group(1) if m else "unknown"


if __name__ == "__main__":
    args = parse_args()
    asyncio.run(crawl(
        live_url=args.url,
        output_path=Path(args.output) if args.output else None,
    ))
