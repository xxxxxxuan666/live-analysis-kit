---
description: 实时捕获直播间系统音频，Whisper 转录，停止后自动生成竞品分析报告并写入飞书文档
---

启动直播间实时转录 + 分析 + 飞书写入流水线。可选参数：$ARGUMENTS（数字=每段秒数，默认30）

---

## 第一步：检查依赖

```bash
"{{PYTHON}}" -c "import pyaudiowpatch, whisper, requests; print('依赖 OK')" 2>&1
```

如果缺少依赖，依次安装：
```bash
"{{PYTHON}}" -m pip install PyAudioWPatch openai-whisper requests Pillow
```

---

## 第二步：创建会话文件夹 + 启动实时转录

从参数 $ARGUMENTS 中提取数字作为每段秒数（无数字则用 30）。

### 2a. 创建临时会话文件夹

```bash
"{{PYTHON}}" -c "
import os
from datetime import datetime
ts = datetime.now().strftime('%Y%m%d_%H%M%S')
folder = os.path.join(r'{{OUTPUT_BASE}}', '_session_' + ts)
os.makedirs(folder, exist_ok=True)
print(folder)
" 2>&1
```

记录返回的文件夹路径，后续所有文件都保存到这里。

### 2b. 启动转录，输出到会话文件夹

用 Bash 工具 **run_in_background: true** 运行（第三个参数是识别提示词，如果还不知道游戏名先用默认值）：
```bash
"{{PYTHON}}" -u "{{SCRIPTS_DIR}}\live_transcribe.py" [秒数] "[会话文件夹路径]" "[游戏名/主播名，如：三国SLG手游直播，武将战令抽卡充值]" 2>&1
```

如果还未知游戏信息，省略第三个参数：
```bash
"{{PYTHON}}" -u "{{SCRIPTS_DIR}}\live_transcribe.py" [秒数] "[会话文件夹路径]" 2>&1
```

保存返回的 task_id，用于后续停止。

然后告知用户：
> 🎙️ **已开始监听系统音频**
> - 打开抖音/浏览器直播间，保持音量开启
> - **请把直播间链接发给我**，我将截图识别直播间名称和弹幕
> - 每 [秒数] 秒转录一段，文字会实时显示在这里
> - 在录制过程中，可以随时发送「[评论] xxx」来补充记录关键评论
> - 说"**停止转录**"结束并自动生成分析报告写入飞书

---

## 第三步：收到直播链接时，识别直播间信息

用户发来直播链接后，告知用户：
> 📸 **请确保浏览器直播画面在屏幕上可见，2 秒后自动截图识别**

### 3a. 从浏览器窗口标题获取直播间名称

```bash
"{{PYTHON}}" -c "
import subprocess, re
result = subprocess.run(
    ['powershell', '-Command',
     \"Get-Process | Where-Object { \$_.MainWindowTitle -match '抖音直播|douyin' } | Select-Object -ExpandProperty MainWindowTitle\"],
    capture_output=True, text=True, encoding='utf-8'
)
title = result.stdout.strip().splitlines()[0] if result.stdout.strip() else ''
m = re.match(r'^(.+?)\s*-\s*抖音直播', title)
name = m.group(1).strip() if m else ''
print('STREAM_NAME=' + name if name else 'STREAM_NAME=未识别')
" 2>&1
```

记录 `STREAM_NAME` 的值作为直播间名称。若为"未识别"则在截图识别后手动补充。

### 3b. 截取当前屏幕，保存到会话文件夹

```bash
"{{PYTHON}}" -c "
from PIL import ImageGrab
import time
time.sleep(2)
try:
    screenshot = ImageGrab.grab()
    out = r'[会话文件夹路径]\_stream_screenshot.png'
    screenshot.save(out)
    print(f'截图保存成功: {out} ({screenshot.size[0]}x{screenshot.size[1]})')
except Exception as e:
    print(f'截图失败: {e}')
" 2>&1
```

### 3c. 用 Read 工具读取截图，识别弹幕

用 Read 工具读取图片文件 `[会话文件夹路径]\_stream_screenshot.png`，从图像中识别：
1. 评论区 / 弹幕内容（通常在直播画面右侧或下方，逐条列出可见的评论文字，最多 10 条）

注意：直播间名称已通过窗口标题获取，**无需从截图识别名称**。不要读取在线观众人数。

### 3d. 整合信息并重命名会话文件夹

将识别结果整理后，**立即重命名会话文件夹**为正式名称：

```bash
"{{PYTHON}}" -c "
import os
from datetime import datetime
old = r'[当前会话文件夹路径]'
date = datetime.now().strftime('%Y%m%d')
new_name = '[直播间名称]·' + date
new = os.path.join(os.path.dirname(old), new_name)
os.rename(old, new)
print(new)
" 2>&1
```

记录新的文件夹路径，后续所有文件使用这个路径。

告知用户：
> ✅ **已识别直播间信息**
> - **直播间名称**：[窗口标题解析结果]
> - **评论区**：「xxx」「xxx」...（如无可见评论则注明"评论区暂无可见内容"）
> - **会话文件夹**：`竞品直播分析\[直播间名称]·[日期]\`
> （如识别有误，用户可直接纠正）

### 3e. 启动定时截图，保存到会话文件夹

用 Bash **run_in_background: true** 启动定时截图，每 60 秒截一次，最多 20 张：

```bash
"{{PYTHON}}" -u -c "
from PIL import ImageGrab
import time, os

out_dir = r'[会话文件夹路径]'
for i in range(20):
    time.sleep(60)
    try:
        screenshot = ImageGrab.grab()
        path = os.path.join(out_dir, f'_stream_snap_{i+1:02d}.png')
        screenshot.save(path)
        print(f'[截图 {i+1}/20] {path}', flush=True)
    except Exception as e:
        print(f'[截图 {i+1}/20] 失败: {e}', flush=True)
" 2>&1
```

保存这个后台任务的 task_id，停止转录时一并停止。

---

## 第四步：实时展示转录

用 Monitor 工具监听后台进程输出，command（将 `[会话文件夹路径]` 替换为实际路径）：
```bash
"{{PYTHON}}" -u -c "
import time, os, glob
time.sleep(8)
folder = r'[会话文件夹路径]'
files = sorted(glob.glob(os.path.join(folder, 'live_transcript_*.txt')), key=os.path.getmtime, reverse=True)
if not files:
    print('等待转录文件...')
    time.sleep(5)
    files = sorted(glob.glob(os.path.join(folder, 'live_transcript_*.txt')), key=os.path.getmtime, reverse=True)
if files:
    last_pos = 0
    while True:
        with open(files[0], encoding='utf-8', errors='replace') as f:
            f.seek(last_pos)
            new = f.read()
            if new.strip():
                print(new.strip(), flush=True)
            last_pos = f.tell()
        time.sleep(2)
"
```

在转录过程中，如果用户发送「[评论] xxx」格式的消息，将这些内容收集到内存中，作为"观察到的评论互动"，在报告中单独列出。

---

## 第五步：用户说"停止转录"时

1. 用 TaskStop 停止后台转录进程和定时截图进程
2. 等待 2 秒让文件写入完成
3. 找到会话文件夹内的转录文件：

```bash
"{{PYTHON}}" -c "
import glob, os
folder = r'[会话文件夹路径]'
files = sorted(glob.glob(os.path.join(folder, 'live_transcript_*.txt')), key=os.path.getmtime, reverse=True)
print(files[0] if files else 'NOT_FOUND')
"
```

4. 用 Read 工具读取该转录文件的完整内容
5. 查看会话文件夹内的截图数量（`_stream_snap_*.png`），选取 2-3 张有代表性的用 Read 工具读取，补充弹幕信息

---

## 第六步：生成分析报告

基于转录文稿 + 截图识别的直播间信息 + 会话中收集的评论，生成 Markdown 格式分析报告：

```markdown
### 直播间基本信息

| 字段 | 内容 |
|---|---|
| **直播间名称** | [窗口标题解析结果] |
| **评论区样本** | [截图中可见的评论文字，若无则填"未采集"] |
| **直播链接** | [用户发来的链接] |
| **录制时长** | 约 X 分钟 |

### 主播人设

| 维度 | 内容 |
|---|---|
| **角色定位** | ... |
| **核心标签** | ... |
| **直播风格** | ... |
| **信任建立方式** | ... |
| **情绪/人设支撑点** | ... |

### 核心内容提炼

**核心钩子话术**
> （直接引用原文最关键的话术）

**产品/服务/活动机制**
（用流程图或列表说明）

**价格体系 / 激励结构**
（如有）

**引流 CTA 话术**
（下载引导、关注引导等）

### 评论区互动记录

（截图弹幕样本 + 用户录制期间补充的 [评论] 记录；若两者均无则注明"本次未采集"）

### 脚本循环机制

循环周期：约 X 分钟/圈

① [第一个动作]
↓
② [第二个动作]
↓
③ [第三个动作]
↓
回到 ①

### 策略亮点与借鉴点

1. **[亮点标题]**：[具体描述，结合原文话术举例]
2. **[亮点标题]**：...

### 原始转录摘要

（从转录内容中提取最具代表性的 5-8 条关键话术，格式：[时间戳] 话术内容）
```

---

## 第七步：写入飞书文档

分析报告生成后，执行以下步骤：

### 1. 保存本地存档

将分析报告写入会话文件夹内的 `分析报告.md`（永久存档），再写一份临时文件：

```bash
"{{PYTHON}}" -c "
import os
report = '''[分析报告 Markdown 内容]'''
folder = r'[会话文件夹路径]'
with open(os.path.join(folder, '分析报告.md'), 'w', encoding='utf-8') as f:
    f.write(report)
tmp = os.path.join(r'{{OUTPUT_BASE}}', '_analysis_temp.md')
with open(tmp, 'w', encoding='utf-8') as f:
    f.write(report)
print(tmp)
" 2>&1
```

### 2. 用 lark-cli 创建飞书文档

文档标题格式：`[直播间名称] · [日期]`

```bash
lark-cli docs +create --title "[直播间名称] · [日期]" --doc-format markdown --content "$(cat '{{OUTPUT_BASE}}\_analysis_temp.md')" 2>&1
```

从返回的 JSON 中提取 `url` 字段，展示给用户：

> ✅ **已生成飞书文档**
> 📄 [文档链接]

如果 lark-cli 未登录或 token 过期，提示用户运行：
```bash
lark-cli auth login --recommend
```

---

## 附：完整流程图

```
用户: /live-transcribe
  → 创建临时会话文件夹
  → 启动后台转录进程 (live_transcribe.py)
  → 提示用户发送直播链接

用户: [发送链接]
  → PowerShell 读浏览器窗口标题 → 解析直播间名称
  → 截图 → Read 识别弹幕
  → 重命名会话文件夹为 [直播间名称]·[日期]
  → 启动后台定时截图（每60秒），持续采集弹幕变化
  → Monitor 实时显示转录文字

用户: [发送 "[评论] xxx"] （可选，随时）
  → 收集到评论记录池

用户: 停止转录
  → TaskStop 停止转录进程 + 定时截图进程
  → 读取转录文件 + 2-3 张截图
  → Claude 生成竞品分析报告
  → 保存 分析报告.md 到会话文件夹
  → lark-cli docs +create 创建飞书文档
  → 返回文档链接
```
