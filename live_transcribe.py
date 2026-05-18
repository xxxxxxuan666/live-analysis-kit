#!/usr/bin/env python3
"""
直播间实时语音转文字工具
捕获电脑系统音频（浏览器/App 播放的直播声音），每 N 秒转录一次

用法:
  python live_transcribe.py                    # 默认每30秒转录一次，保存到桌面
  python live_transcribe.py 20                 # 每20秒转录一次
  python live_transcribe.py 30 /path/to/dir    # 指定输出目录
  python live_transcribe.py 30 /path/to/dir "游戏名 主播名 抽卡战令"  # 自定义识别提示词
"""

import sys, os, time, numpy as np
from datetime import datetime

# Windows 终端 UTF-8 输出
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

os.environ["PATH"] = (
    os.path.join(os.path.dirname(sys.executable), "Scripts")
    + os.pathsep + os.environ.get("PATH", "")
)

CHUNK_SECONDS = int(sys.argv[1]) if len(sys.argv) > 1 else 30
TARGET_SR = 16000  # Whisper 要求 16kHz
OUTPUT_DIR = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.expanduser("~"), "Desktop")

# 第三个参数：上下文提示词，帮助 Whisper 识别专业词汇和同音字
INITIAL_PROMPT = sys.argv[3] if len(sys.argv) > 3 else (
    "这是一个手游直播间的主播口播内容，涉及游戏玩法讲解、抽卡机制、充值优惠和下载引导。"
    "常见词汇：武将、战令、抽卡、保底、充值、新区、服务器、皮肤、战力、传说、金卡、限定卡、"
    "礼包、直播间、下载、注册、体验、福利、对吧、老铁、哥们、兄弟。"
)


def resample_to_16k(audio: np.ndarray, orig_sr: int) -> np.ndarray:
    """简单线性插值重采样到 16kHz"""
    if orig_sr == TARGET_SR:
        return audio
    new_len = int(len(audio) * TARGET_SR / orig_sr)
    return np.interp(
        np.linspace(0, len(audio) - 1, new_len),
        np.arange(len(audio)),
        audio
    ).astype(np.float32)


def find_loopback_device(p):
    """找到系统默认扬声器对应的 WASAPI 回环设备"""
    import pyaudiowpatch as pyaudio
    wasapi_info = p.get_host_api_info_by_type(pyaudio.paWASAPI)
    default_speakers = p.get_device_info_by_index(wasapi_info["defaultOutputDevice"])
    speaker_name = default_speakers["name"]

    for lb in p.get_loopback_device_info_generator():
        if speaker_name in lb["name"]:
            return lb, int(default_speakers["defaultSampleRate"])

    # 如果找不到匹配的，用第一个回环设备
    for lb in p.get_loopback_device_info_generator():
        return lb, int(lb["defaultSampleRate"])

    raise RuntimeError("未找到 WASAPI 回环设备，请检查系统音频设置")


def main():
    try:
        import pyaudiowpatch as pyaudio
    except ImportError:
        print("缺少依赖，请先运行：", flush=True)
        print('  pip install PyAudioWPatch', flush=True)
        sys.exit(1)

    try:
        import whisper
    except ImportError:
        print("缺少依赖，请先运行：", flush=True)
        print('  pip install openai-whisper', flush=True)
        sys.exit(1)

    p = pyaudio.PyAudio()

    # --- 找回环设备 ---
    try:
        device_info, device_sr = find_loopback_device(p)
        channels = max(1, device_info["maxInputChannels"])
        device_index = device_info["index"]
        print(f"[音频设备] {device_info['name']}", flush=True)
        print(f"  采样率: {device_sr}Hz  声道: {channels}", flush=True)
    except Exception as e:
        print(f"[错误] 无法获取系统音频回环: {e}", flush=True)
        print("请确认：", flush=True)
        print("  1. 电脑有音频输出设备（扬声器/耳机）", flush=True)
        print("  2. 已安装 PyAudioWPatch（pip install PyAudioWPatch）", flush=True)
        p.terminate()
        sys.exit(1)

    # --- 加载 Whisper ---
    print("加载 Whisper small 模型（首次运行会自动下载 ~460MB）...", flush=True)
    model = whisper.load_model("small")

    # --- 输出文件 ---
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    ts_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_path = os.path.join(OUTPUT_DIR, f"live_transcript_{ts_str}.txt")

    print(f"每 {CHUNK_SECONDS} 秒转录一次", flush=True)
    print(f"保存路径: {out_path}", flush=True)
    print("=" * 60, flush=True)
    print("开始监听... Ctrl+C 停止", flush=True)
    print("=" * 60, flush=True)

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(f"=== 直播实时转录 {ts_str} ===\n\n")

    # --- 音频缓冲区（回调写入，主线程读取）---
    audio_buffer = []
    frames_per_chunk = device_sr * CHUNK_SECONDS
    FRAMES_PER_BUFFER = 512
    total_chars = 0

    def audio_callback(in_data, frame_count, time_info, status):
        chunk = np.frombuffer(in_data, dtype=np.float32).copy()
        if channels > 1:
            chunk = chunk.reshape(-1, channels).mean(axis=1)
        audio_buffer.extend(chunk.tolist())
        return (None, pyaudio.paContinue)

    stream = p.open(
        format=pyaudio.paFloat32,
        channels=channels,
        rate=device_sr,
        input=True,
        input_device_index=device_index,
        frames_per_buffer=FRAMES_PER_BUFFER,
        stream_callback=audio_callback,
    )
    stream.start_stream()

    try:
        while stream.is_active():
            if len(audio_buffer) >= frames_per_chunk:
                # 取出一段
                raw = np.array(audio_buffer[:frames_per_chunk], dtype=np.float32)
                del audio_buffer[:frames_per_chunk]

                # 重采样到 16kHz
                audio_16k = resample_to_16k(raw, device_sr)

                # 跳过静音
                if np.max(np.abs(audio_16k)) < 0.005:
                    print(
                        f"[{datetime.now().strftime('%H:%M:%S')}] (静音，跳过)",
                        flush=True
                    )
                    continue

                # 转录
                result = model.transcribe(
                    audio_16k,
                    language="zh",
                    fp16=False,
                    verbose=False,
                    initial_prompt=INITIAL_PROMPT,
                    beam_size=5,
                    best_of=5,
                    temperature=0.0,
                )
                text = result["text"].strip()

                if text:
                    total_chars += len(text)
                    line = f"[{datetime.now().strftime('%H:%M:%S')}] {text}"
                    print(line, flush=True)
                    with open(out_path, "a", encoding="utf-8") as f:
                        f.write(line + "\n")
                        f.flush()
            else:
                time.sleep(0.3)

    except KeyboardInterrupt:
        print(f"\n已停止。共转录 {total_chars} 字", flush=True)
        print(f"文件已保存: {out_path}", flush=True)
    finally:
        stream.stop_stream()
        stream.close()
        p.terminate()


if __name__ == "__main__":
    main()
