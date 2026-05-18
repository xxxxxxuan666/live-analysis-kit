# 直播竞品分析 Skill 安装指引

本工具实现：抖音/游戏直播实时转录 → Claude 竞品分析 → 自动生成飞书文档。

## 环境要求

- Windows 10/11（依赖 WASAPI 回环录音）
- Python 3.9+（推荐 3.11）
- Node.js 16+
- Claude Code

## 安装步骤（AI Agent 执行）

> 以下步骤面向 AI Agent，部分步骤需要用户在浏览器中配合完成。

### 第 1 步 — 下载工具包

```bash
git clone https://github.com/xxxxxxuan666/live-analysis-kit.git "C:\live-analysis-kit"
```

如未安装 git，改用以下方式下载压缩包并解压到 `C:\live-analysis-kit`：

```
https://github.com/xxxxxxuan666/live-analysis-kit/archive/refs/heads/main.zip
```

### 第 2 步 — 运行一键安装脚本

```bash
python "C:\live-analysis-kit\install.py"
```

安装脚本会自动完成：
- 安装 Python 依赖（PyAudioWPatch、openai-whisper、requests、Pillow）
- 创建 `桌面\竞品直播分析\` 输出文件夹
- 安装 lark-cli（飞书 CLI）
- 生成并部署 `/live-transcribe` skill 到 Claude Code

### 第 3 步 — 配置飞书应用

> 在后台运行此命令，命令会输出授权链接，提取该链接并发给用户，用户在浏览器完成后命令自动退出。

```bash
lark-cli config init --new
```

### 第 4 步 — 登录飞书账号

> 同上，后台运行，提取授权链接发给用户。

```bash
lark-cli auth login --recommend
```

### 第 5 步 — 验证

```bash
lark-cli auth status
```

看到 `"tokenStatus": "valid"` 即表示安装成功。

## 完成后的使用方式

1. 在 Claude Code 中输入 `/live-transcribe` 启动转录
2. 打开抖音直播间，保持音量开启
3. 将直播链接发给 Claude
4. 说"**停止转录**"自动生成竞品分析报告并写入飞书文档

## 常见问题

**找不到音频设备**：确保系统有默认音频输出设备（扬声器/耳机），并已安装 PyAudioWPatch

**转录效果不好**：提高直播间音量；如果知道游戏名，启动后发给 Claude 补充识别提示词

**lark-cli token 过期**：运行 `lark-cli auth login --recommend` 重新授权
