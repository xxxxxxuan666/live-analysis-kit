# Douyin Source Workflows

Use this reference when monitoring Douyin live rooms.

## Source Mode A: Real-Time Speech-To-Text

Use when the user provides live transcript text, ASR output, or a continuously updated text file.

### Process

1. Confirm the live room, account, product, start time, and business question.
2. Segment incoming transcript by time window, usually 1-5 minutes.
3. Extract:
   - Anchor hook and topic
   - Product/game feature being explained
   - Offer, activity, coupon, or gift
   - Objection handling
   - CTA and purchase/follow/join path
   - Interaction prompts
4. Keep a rolling hypothesis list:
   - Current traffic-retention tactic
   - Current conversion tactic
   - Repeated objections or unclear points
   - Scripts worth testing
5. Every 15-30 minutes, produce an interim summary with emerging patterns.

### Output Emphasis

- Best for script mining, CTA frequency, objection handling, rhythm, and offer framing.
- Weak for visual proof, comment density, UI, streamer performance, and screen composition unless paired with screenshots or manual notes.

## Source Mode B: URL Capture

Use when the user provides an authorized live room URL and wants Codex to start recording or audio capture locally.

### Process

1. Confirm live room URL, live room name, capture mode (`video` or `audio`), and whether the comment area is visible.
2. For `video`, keep only the authorized live room and intended recording area visible.
3. For `audio`, keep the live room playing and capture system audio only.
4. Use system audio, not microphone audio. Require Stereo Mix, virtual audio cable, OBS audio, or a known DirectShow system-audio device.
5. Start capture with `scripts/start-live-monitor.ps1`.
6. When the user says "暂停", run `scripts/stop-live-monitor.ps1`.
7. Use the media, audio, transcript, and archive paths from the session JSON or stop command output.
8. For video captures, sample frames at key moments:
   - Opening and traffic hooks
   - Product/game demonstration
   - Offer or coupon display
   - Comment spikes
   - CTA moments
   - Scene changes
9. Combine:
   - Visual observations
   - OCR or visible comment text
   - ASR/transcript if available
   - Manual notes

### Capture Commands

Start screen plus system audio:

```powershell
$skillDir = "C:\path\to\livestream-competitor-monitor-skill"
powershell -ExecutionPolicy Bypass -File (Join-Path $skillDir "scripts\start-live-monitor.ps1") -Url "<live-room-url>" -RoomName "<live-room-name>" -Mode video
```

Start system-audio-only capture:

```powershell
$skillDir = "C:\path\to\livestream-competitor-monitor-skill"
powershell -ExecutionPolicy Bypass -File (Join-Path $skillDir "scripts\start-live-monitor.ps1") -Url "<live-room-url>" -RoomName "<live-room-name>" -Mode audio
```

If automatic device detection cannot find system audio, pass the configured DirectShow device:

```powershell
$skillDir = "C:\path\to\livestream-competitor-monitor-skill"
powershell -ExecutionPolicy Bypass -File (Join-Path $skillDir "scripts\start-live-monitor.ps1") -Url "<live-room-url>" -RoomName "<live-room-name>" -Mode video -SystemAudioDevice "<Stereo Mix / virtual audio / OBS audio device>"
```

Stop and transcribe when user says "暂停":

```powershell
$skillDir = "C:\path\to\livestream-competitor-monitor-skill"
powershell -ExecutionPolicy Bypass -File (Join-Path $skillDir "scripts\stop-live-monitor.ps1")
```

The script stores files under the desktop archive root `直播录文件存档\<live-room-name>\` and names media/transcript files as `<live-room-name>-<yyyyMMdd-HHmmss>.*`.

Do not let the workflow fall back to microphone audio. If no system audio device is available, stop and ask the user to configure Stereo Mix, virtual audio cable, OBS audio, or pass `-SystemAudioDevice`.

### Process After Capture

1. Confirm recording file exists and has non-zero size.
2. Confirm the stop command produced an audio file and FunASR transcript path.
3. For `video` mode, use the extracted frames folder for visual analysis.
4. If transcription was skipped or failed, transcribe audio manually with FunASR:

```powershell
$skillDir = "C:\path\to\livestream-competitor-monitor-skill"
powershell -ExecutionPolicy Bypass -File (Join-Path $skillDir "scripts\transcribe-recording-audio.ps1") -AudioPath "<assets-dir>\audio.wav"
```

If no ASR is available, produce a timestamped speech summary from audible/manual notes and mark it as non-verbatim.
5. Produce:
   - Full transcript or timestamped speech summary
   - Visual content analysis
   - Comment-area analysis if visible
   - Competitor script library
   - Case-style analysis report
6. Analyze the alignment between what the anchor says, what viewers ask, and what the screen proves.

## Source Mode C: Existing Video File

Use when the user provides a local screen recording video instead of a live URL.

### Process

1. Confirm video path, live room name/account, recording date, and business question.
2. Create or identify the archive folder under `直播录文件存档\<live-room-name>\`.
3. If needed, copy the video into that folder using `<live-room-name>-<yyyyMMdd-HHmmss>.<ext>`.
4. Run asset extraction:

```powershell
$skillDir = "C:\path\to\livestream-competitor-monitor-skill"
powershell -ExecutionPolicy Bypass -File (Join-Path $skillDir "scripts\extract-recording-assets.ps1") -VideoPath "<video-path>"
```

5. Copy or rename the extracted `audio.wav` to match the live-room/date naming pattern before transcription when possible.
6. Run FunASR on the extracted audio.
7. Analyze:
   - Host styling and persona
   - Live room stickers, overlays, subtitles, and product entries
   - Game screen content and gameplay proof
   - Visible comment text and interaction state
   - Full transcript and reusable competitor script patterns

### Output Emphasis

- Best for visual tactics, overlays, live room layout, comment-section themes, streamer behavior, and product proof.
- Weak for exact script recall unless paired with ASR/transcript.

## Recommended Monitoring Cadence

- 0-5 min: opening hook, account positioning, first CTA.
- 5-15 min: product education and interaction loop.
- 15-30 min: repeated objection handling, comment themes, offer clarity.
- 30-60 min: rhythm changes, conversion pushes, streamer fatigue, audience retention pattern.
- End: closing CTA, urgency, next-session hook.

## Douyin-Specific Fields

- Live room title:
- Account positioning:
- Host persona:
- On-screen product/game state:
- Little yellow cart / product card status:
- Coupon or benefit display:
- Pinned comment:
- Comment velocity:
- Like/follow/share prompts:
- Fan group or private domain CTA:
- Moderator participation:

## Local Recording Notes

Prefer `scripts/start-live-monitor.ps1` and `scripts/stop-live-monitor.ps1` for new work. Use `scripts/record-douyin-screen.ps1`, `scripts/start-douyin-recording.ps1`, or `scripts/stop-douyin-recording.ps1` only as compatibility helpers. The workflow requires `ffmpeg` to be installed and available in PATH or at `%USERPROFILE%\Tools\ffmpeg\bin\ffmpeg.exe`.

## FunASR Integration

Use Alibaba/ModelScope FunASR for offline Chinese transcription. The setup script creates a local Python environment under the skill folder:

```powershell
$skillDir = "C:\path\to\livestream-competitor-monitor-skill"
powershell -ExecutionPolicy Bypass -File (Join-Path $skillDir "scripts\setup-funasr.ps1")
```

Default model stack:

- ASR: `paraformer-zh`
- VAD: `fsmn-vad`
- Punctuation: `ct-punc`

Use domain hotwords for games, characters, anchors, and slang when available:

```powershell
$skillDir = "C:\path\to\livestream-competitor-monitor-skill"
powershell -ExecutionPolicy Bypass -File (Join-Path $skillDir "scripts\transcribe-recording-audio.ps1") -AudioPath ".\recordings\xxx-assets\audio.wav" -Hotword "率土之滨 配将 白板 武将 战法"
```

Treat ASR output as a draft: proofread names, game terms, numbers, and homophones before turning it into a reusable competitor script library.
