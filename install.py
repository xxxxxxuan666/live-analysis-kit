#!/usr/bin/env python3
"""
直播竞品分析工具包 - 一键安装脚本
运行方式: python install.py
"""

import sys, os, json, shutil, subprocess
from pathlib import Path

# Windows terminal UTF-8 output
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

PYTHON = sys.executable
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR_ESC = SCRIPTS_DIR.replace("\\", "\\\\")

DESKTOP = os.path.join(os.path.expanduser("~"), "Desktop")
OUTPUT_BASE = os.path.join(DESKTOP, "竞品直播分析")
COMMANDS_DIR = os.path.join(os.path.expanduser("~"), ".claude", "commands")
SKILL_DEST = os.path.join(COMMANDS_DIR, "live-transcribe.md")
CONFIG_DEST = os.path.join(SCRIPTS_DIR, "live_config.json")
TEMPLATE_PATH = os.path.join(SCRIPTS_DIR, "skill_template.md")


def print_step(n, text):
    print(f"\n{'='*60}")
    print(f"  步骤 {n}: {text}")
    print(f"{'='*60}")


def print_ok(text):
    print(f"  ✅ {text}")


def print_warn(text):
    print(f"  ⚠️  {text}")


def print_err(text):
    print(f"  ❌ {text}")


# ─── 步骤 1：检查并安装依赖 ─────────────────────────────────────

def install_deps():
    print_step(1, "检查并安装 Python 依赖")
    packages = ["PyAudioWPatch", "faster-whisper", "requests", "Pillow"]
    missing = []
    import_names = {
        "PyAudioWPatch": "pyaudiowpatch",
        "faster-whisper": "faster_whisper",
        "requests": "requests",
        "Pillow": "PIL",
    }
    for pkg in packages:
        mod = import_names[pkg]
        try:
            __import__(mod)
            print_ok(f"{pkg} 已安装")
        except ImportError:
            missing.append(pkg)
            print_warn(f"{pkg} 未安装，即将安装...")

    if missing:
        print(f"\n  正在安装: {', '.join(missing)}")
        cmd = [PYTHON, "-m", "pip", "install"] + missing
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print_err("安装失败，请手动运行：")
            print(f"  {PYTHON} -m pip install {' '.join(missing)}")
            print(result.stderr[-500:] if result.stderr else "")
            return False
        print_ok("依赖安装完成")
    return True


# ─── 步骤 2：创建输出文件夹 ──────────────────────────────────────

def create_output_folder():
    print_step(2, "创建竞品直播分析输出文件夹")
    os.makedirs(OUTPUT_BASE, exist_ok=True)
    print_ok(f"输出文件夹：{OUTPUT_BASE}")


# ─── 步骤 3：安装 lark-cli ────────────────────────────────────────

def install_lark_cli():
    print_step(3, "检查并安装 lark-cli（飞书文档写入）")
    result = subprocess.run(
        ["npm", "install", "-g", "@larksuite/cli", "--registry=https://registry.npmjs.org"],
        capture_output=True, text=True, shell=True
    )
    if result.returncode != 0:
        print_warn("lark-cli 安装失败，请手动运行：")
        print("  npm install -g @larksuite/cli --registry=https://registry.npmjs.org")
        return False

    ver = subprocess.run(["lark-cli", "--version"], capture_output=True, text=True, shell=True)
    print_ok(f"lark-cli 已安装：{ver.stdout.strip()}")
    print()
    print("  接下来需要在浏览器中完成飞书授权（两步）：")
    print("    lark-cli config init --new   # 创建/绑定飞书应用")
    print("    lark-cli auth login --recommend  # 登录飞书账号")
    print()
    print("  请在安装完成后手动运行以上两条命令完成授权。")
    return True


# ─── 步骤 4：生成并安装 skill 文件 ───────────────────────────────

def install_skill():
    print_step(4, "生成并安装 Claude Code skill 文件")

    if not os.path.exists(TEMPLATE_PATH):
        print_err(f"找不到模板文件：{TEMPLATE_PATH}")
        return False

    with open(TEMPLATE_PATH, encoding="utf-8") as f:
        template = f.read()

    # 替换所有占位符
    skill = (template
        .replace("{{PYTHON}}", PYTHON)
        .replace("{{SCRIPTS_DIR_ESC}}", SCRIPTS_DIR_ESC)
        .replace("{{SCRIPTS_DIR}}", SCRIPTS_DIR)
        .replace("{{OUTPUT_BASE}}", OUTPUT_BASE)
    )

    # 确保 commands 目录存在
    os.makedirs(COMMANDS_DIR, exist_ok=True)

    with open(SKILL_DEST, "w", encoding="utf-8") as f:
        f.write(skill)

    print_ok(f"Skill 已安装到：{SKILL_DEST}")
    return True


# ─── 步骤 5：验证安装 ────────────────────────────────────────────

def verify():
    print_step(5, "验证安装")
    ok = True

    checks = [
        (os.path.exists(SKILL_DEST), f"Skill 文件：{SKILL_DEST}"),
        (os.path.exists(OUTPUT_BASE), f"输出文件夹：{OUTPUT_BASE}"),
        (os.path.exists(os.path.join(SCRIPTS_DIR, "live_transcribe.py")), "live_transcribe.py"),
    ]

    for passed, label in checks:
        if passed:
            print_ok(label)
        else:
            print_err(f"缺失：{label}")
            ok = False

    # 检查 lark-cli
    lark = subprocess.run(["lark-cli", "--version"], capture_output=True, text=True, shell=True)
    if lark.returncode == 0:
        print_ok(f"lark-cli：{lark.stdout.strip()}")
    else:
        print_warn("lark-cli 未安装，请运行：npm install -g @larksuite/cli --registry=https://registry.npmjs.org")
        ok = False

    return ok


# ─── 步骤 6：打印后续操作指引 ────────────────────────────────────

def print_next_steps():
    print(f"\n{'='*60}")
    print("  🎉 安装完成！")
    print(f"{'='*60}")
    print("""
  使用方法：
    1. 完成飞书授权（如尚未完成）：
       lark-cli config init --new
       lark-cli auth login --recommend
    2. 在 Claude Code 中输入 /live-transcribe 启动转录
    3. 打开直播间并保持音量开启
    4. 将直播链接发给 Claude，等待识别
    5. 说"停止转录"生成分析报告并自动创建飞书文档
""")
    print(f"  📁 分析文件保存位置：{OUTPUT_BASE}")
    print()


# ─── 主流程 ─────────────────────────────────────────────────────

def main():
    print()
    print("直播竞品分析工具包 安装程序")
    print(f"Python：{PYTHON}")
    print(f"工具包目录：{SCRIPTS_DIR}")

    deps_ok = install_deps()
    if not deps_ok:
        print_warn("依赖安装遇到问题，但仍继续安装 skill 文件...")

    create_output_folder()
    install_lark_cli()
    skill_ok = install_skill()

    if not skill_ok:
        print_err("Skill 安装失败，请检查上方错误信息")
        sys.exit(1)

    all_ok = verify()
    print_next_steps()

    if not all_ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
