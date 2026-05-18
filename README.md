# 直播竞品分析工具包

实时捕获直播间音频 → Whisper 转录 → Claude 生成竞品分析报告 → 自动写入飞书文档

---

## 包含文件

| 文件 | 说明 |
|---|---|
| `install.py` | 一键安装脚本（首次运行必须） |
| `live_transcribe.py` | 实时音频转录核心脚本 |
| `feishu_post.py` | 飞书文档写入脚本 |
| `live_config.json` | 配置文件（飞书凭据填这里） |
| `skill_template.md` | Claude Code skill 模板（安装时自动填入路径） |

---

## 安装步骤

### 1. 前置要求

- **Windows 10/11**（需要 WASAPI 回环录音）
- **Python 3.9+**（推荐 3.11）
- **Claude Code**（桌面版或 CLI）

### 2. 一键安装

```bash
python install.py
```

安装脚本会自动：
- 安装 Python 依赖（PyAudioWPatch、openai-whisper、requests、Pillow）
- 创建 `桌面\竞品直播分析\` 输出文件夹
- 读取飞书配置并生成正确路径的 skill 文件
- 将 skill 复制到 `~\.claude\commands\live-transcribe.md`

首次运行会自动下载 Whisper small 模型（约 460MB），请保持网络通畅。

### 3. 配置飞书（可选）

如需自动写入飞书文档，编辑 `live_config.json`：

```json
{
  "feishu_app_id": "cli_xxxxxxxxxxxxxxxx",
  "feishu_app_secret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "feishu_wiki_token": "AbCdEfGhIjKlMnOp",
  "feishu_domain": "feishu.cn"
}
```

获取方式：
1. 打开 [飞书开放平台](https://open.feishu.cn) → 创建企业自建应用
2. 「凭证与基础信息」页面复制 App ID 和 App Secret
3. 开通权限：`wiki:wiki`、`docx:document`
4. 在飞书 Wiki 文档页面右上角「...」→「添加应用」→ 设为编辑者
5. Wiki Token 是文档 URL 最后一段：`https://xxx.feishu.cn/wiki/`**`AbCdEfGh`**

配置完成后重新运行 `python install.py` 刷新 skill。

---

## 使用方法

1. 在 Claude Code 中输入 `/live-transcribe`（可加秒数参数，如 `/live-transcribe 20`）
2. Claude 会启动后台录音，提示你打开直播间
3. 将直播间链接发给 Claude，Claude 会截图识别直播间信息
4. 等待转录实时显示在对话中
5. 说"**停止转录**"，Claude 自动生成竞品分析报告并写入飞书

---

## 注意事项

- 录音依赖 WASAPI 回环，需要电脑有扬声器或耳机输出设备
- Whisper 转录在 CPU 上运行，每段约需 5-15 秒（视 CPU 性能）
- 分析文件保存在 `桌面\竞品直播分析\[主播名]·[游戏名]·[日期]\`
- 飞书配置为空时，分析报告会直接显示在对话中，可手动复制

---

## 常见问题

**Q: 找不到音频设备**
A: 确保系统有默认音频输出设备（扬声器/耳机），并已安装 PyAudioWPatch

**Q: 转录效果不好**
A: 提高直播间音量；如果知道游戏名，在启动后发给 Claude，后续转录会带上相关词汇提示

**Q: 飞书写入失败**
A: 检查应用权限是否开通，以及是否在文档中添加了该应用为编辑者

**Q: 截图识别直播信息错误**
A: 直接在对话中告诉 Claude 正确的直播间名称和主播名即可纠正
