---
name: livestream-competitor-monitor-skill
version: "0.1.0"
description: Use when Codex needs to monitor authorized competitor livestreams, especially Douyin live rooms, from live room URLs, real-time speech-to-text, screen recordings, screenshots, transcripts, comment exports, or notes; analyze anchor scripts, comment signals, visuals, offers, objections, pacing, conversion tactics, competitor script libraries, multi-room comparisons, and recurring learnings.
---

# Livestream Competitor Monitor

## Overview

Use this skill to turn Douyin or other livestream artifacts into a structured competitive monitoring report. Work from user-provided or authorized materials such as real-time speech-to-text logs, recordings, screenshots, transcript files, comment exports, manual notes, OCR output, or ASR text.

The preferred Douyin workflow is:

1. User provides a live room URL, live room name, and chooses `video` (screen + system audio) or `audio` (system audio only).
2. Start capture with `scripts/start-live-monitor.ps1`; archive files under the desktop folder `直播录文件存档/<game-product-name>-<live-room-name>-<yyyyMMdd>/`.
3. When a Douyin URL is provided, start capture with the Douyin live comment crawler unless the user disables it. Store comments as `<直播间名称>-<yyyyMMdd-HHmmss>-comments.jsonl` in the same room archive folder.
4. When the user says "暂停", run `scripts/stop-live-monitor.ps1`; it stops ffmpeg and the comment crawler, creates/locates the audio file, and runs FunASR transcription.
5. Analyze the created recording, transcript, and comment JSONL: anchor appearance, live room overlays, game screen, comment area text, speech transcript, and offer mechanics.
6. Produce a report using the requested template: single recording, single transcript, or multi-room comparison.
7. Update `references/memory.md` with reusable, non-sensitive competitor tactics and script patterns.

## Boundaries

- Analyze only public, owned, or otherwise authorized livestream materials.
- Do not instruct users to bypass platform access controls, scraping protections, paywalls, login gates, or anti-recording measures.
- For Douyin, prefer user-visible live room observation, user-provided transcript streams, user-authorized screen recordings, or official/exported materials.
- Do not preserve private personal data from viewers. Summarize comment patterns and anonymize examples unless the user explicitly needs public brand/account names.
- Keep raw recordings, screenshots, and comment exports outside long-term skill memory. Store reusable patterns, schemas, and lessons only.
- Capture livestream sound as system audio, not microphone audio. On Windows, require Stereo Mix, virtual audio cable, OBS audio, or another DirectShow system-audio source. If no system-audio device is available, tell the user to configure one instead of silently recording microphone input.

## Workflow

1. Clarify the monitoring target.
   - Identify platform, competitor/account, product/game, live room URL, stream date, observation window, and business goal.
   - Identify available source mode: real-time speech-to-text, screen recording/video, screenshots, OCR text, comment export, manual notes, or prior reports.
   - Identify the desired output: raw monitor log, strategic analysis, cross-stream comparison, script library, issue list, or action recommendations.

2. Load references.
   - Read `references/capture-schema.md` before structuring raw observations.
   - Read `references/analysis-framework.md` before writing strategic conclusions.
   - Read `references/douyin-source-workflows.md` when the source is Douyin real-time text or screen recording.
   - Read `references/memory.md` to reuse accumulated competitor patterns and prior findings.

3. Choose the source workflow.
   - For real-time speech-to-text: create a rolling monitor log, segment by 1-5 minute windows, and continuously update script themes, CTA frequency, objections, and strategy hypotheses.
   - For URL-triggered recording: run `scripts/start-live-monitor.ps1 -Url <url> -Mode video` for screen plus system audio, or `-Mode audio` for system audio only. When `-RoomName` or `-GameProductName` is omitted, the script first runs `scripts/resolve-douyin-live-metadata.py` for about 10 seconds to infer the live room name, game product name, and visible viewer count; explicit user-provided values always win. This also starts the bundled `scripts/douyin-comment-crawler.py` and writes `<直播间名称>-<yyyyMMdd-HHmmss>-comments.jsonl` unless `-DisableComments` is passed. Wait for the user's "暂停" command, then run `scripts/stop-live-monitor.ps1`.
   - For an existing screen recording file: skip capture, run `scripts/extract-recording-assets.ps1 -VideoPath <file>`, then transcribe the extracted or copied audio with `scripts/transcribe-recording-audio.ps1`.
   - For screen recording analysis: sample key frames and combine visual/OCR/comment evidence with transcript or manual notes.
   - If `ffmpeg` is installed on Windows, `scripts/start-live-monitor.ps1` and `scripts/stop-live-monitor.ps1` record and stop the visible desktop or system audio. Do not use them to bypass platform controls.

4. Archive files.
   - Default root: desktop folder `直播录文件存档`.
   - One subfolder per game, live room, and recording date: `<game-product-name>-<live-room-name>-<yyyyMMdd>`.
   - If the game product name is unknown, fall back to `<live-room-name>-<yyyyMMdd>`.
   - Media and transcript names use `<live-room-name>-<yyyyMMdd-HHmmss>`.
   - Douyin comment files use `<live-room-name>-<yyyyMMdd-HHmmss>-comments.jsonl`.
   - Persist automatic metadata in `_metadata/<yyyyMMdd-HHmmss>-auto-metadata.json` and session fields `auto_metadata_path`, `auto_room_name`, `auto_game_product_name`, `auto_viewer_count`, and `metadata_confidence`.
   - Keep the session JSON in the archive subfolder and a pointer session JSON under the archive root so `stop-live-monitor.ps1` can find the latest session.

5. Normalize source material.
   - Segment observations by timestamp or time window.
   - Separate anchor speech, comment-section signal, screen/visual content, product offer, interaction mechanics, and conversion action.
   - Preserve exact short phrases only when they are analytically important; otherwise summarize.
   - For screenshots/video frames, describe visible product, UI, props, streamer behavior, offer text, and audience interaction state.
   - For UI evidence images, only create a `ui-evidence-manifest.json` when the user explicitly asks for UI screenshots. Use manual UI evidence selection first; treat `scripts/export-ui-evidence.ps1 -SourceImage <live-crop-or-screenshot>` as fixed-crop fallback only when the Douyin browser layout clearly matches the standard layout.
   - For the live room overlay/UI section, keep the table to two columns only: module and observation. Do not add a key screenshot/evidence column, and do not include the UI screenshot section by default because automatic UI crops can be inaccurate.

6. Build the monitoring record.
   - Use the schema in `references/capture-schema.md`.
   - Track repeated scripts, opening hooks, retention tactics, benefit claims, objection handling, urgency/scarcity language, social proof, price/package, and call-to-action.
   - Track comment themes: questions, objections, complaints, purchase intent, comparison mentions, trust signals, price sensitivity, product confusion, and sentiment.
   - When `comments_path` exists, run `scripts/summarize-comments.ps1 -CommentsPath <comments.jsonl>` before writing the report. Use the summary JSON/Markdown to fill the comment interaction table, comment insights, and any available audience-count observations. Summarize patterns and anonymize viewers unless public account names are necessary.
   - Track visual tactics: layout, product demo, streamer expression/action, overlays, subtitles, banners, countdowns, gifts, coupons, pinned comments, and live room rhythm.

7. Analyze.
   - Identify what the competitor is trying to optimize: traffic retention, conversion, payment, brand trust, event participation, community joining, or product education.
   - Connect script, comment, and visual evidence to the likely strategy.
   - For recordings, analyze three tracks separately before synthesis: visual track, speech/text track, and comment/interaction track.
   - For long livestream recordings, analyze the full stream through segmentation instead of rejecting it: the default video-analysis segment length is 12 minutes, the maximum video-analysis segment length is 20 minutes, and a single livestream case can be analyzed up to 1 hour by combining segment-level visual analysis with full ASR and comment summaries.
   - If a recording is longer than the selected video-analysis segment length, split it into chronological segments, analyze each segment separately, then synthesize a total report with timeline-level findings and cross-segment script loops.
   - Extract a full transcript with FunASR when available. Use `scripts/setup-funasr.ps1` once, then `scripts/transcribe-recording-audio.ps1 -AudioPath <assets-dir>\audio.wav`.
   - If exact transcription is not available, produce a timestamped speech summary and mark it as non-verbatim.
   - Build a competitor script library that this game can reference: opening hook, feature explanation, trust proof, objection handling, event/benefit framing, CTA, retention filler, and closing script.
   - For single transcript-only analysis, use `assets/single-transcript-analysis-template.md`.
   - Prioritize insights by business impact and repeatability.
   - Distinguish evidence from hypothesis.
   - Compare against prior competitor patterns when memory exists.

8. Output.
   - For a single stream, produce the case-style structure from `assets/douyin-case-analysis-template.md`: live room basic info with screenshot, one-sentence conclusion, visual analysis, streamer persona table, overlay/UI evidence table, core script excerpts, game screen content, script loop mechanism, interaction mechanism, recommendations, full anchor script, and learnings.
   - In the script loop mechanism section, include both a script loop Mermaid flowchart and structured stage-by-stage text analysis. The flowchart should map the actual repeated talk-track path, such as opening hook, benefit/gameplay explanation, comment objection handling, urgency/social proof, CTA, and the condition that loops back or restarts the hook. The text analysis should use numbered stages and explain each stage's purpose, key talk-track, audience response, and conversion role.
   - For multiple streams, add: Cross-stream Patterns, Differences by Account/Product/Time Slot, Reusable Script Library, Test Recommendations.
   - If the user asks for a case-style recording analysis, use `assets/douyin-case-analysis-template.md` unless the user provides another case template.
   - If the user provides only text or transcript material, use `assets/single-transcript-analysis-template.md`.
   - If the user asks to compare multiple live rooms, use `assets/multi-room-comparison-template.md`.
   - If the user asks to generate, publish, send, or convert the report to a Feishu/Lark document, call `lark-cli` to create the document from the Markdown report. Do not create a Feishu document unless the user asks for it.
   - Prefer `scripts/publish-feishu-report.ps1 -ReportPath <report.md> -Title "<game-product-name>-<live-room-name>-<date>"` for Feishu publishing. Pass `-MainScreenshot` when available so the helper restores the title and inserts the basic-info screenshot. Pass `-UiEvidenceManifest <ui-evidence-manifest.json>` only when the user explicitly asks for UI screenshots.
   - On Windows, if the `lark-cli` PowerShell shim is blocked by execution policy, invoke it through `powershell -NoProfile -ExecutionPolicy Bypass -File (Get-Command lark-cli).Source ...`.
   - Name Feishu report documents as `<游戏产品名>-<直播间名称>-<日期>`, for example `率土之滨-吾乃曹阿瞒【率土老炮】-2026-05-19`.
   - Use `lark-cli docs +create --api-version v2 --title "<游戏产品名>-<直播间名称>-<日期>" --doc-format markdown --content @<report.md>` when creating a report document. If the report has a local livestream screenshot, insert it with `lark-cli docs +media-insert --doc <doc_url_or_id> --file <screenshot.jpg> --type image --caption "直播截图（录制开始时）" --selection-with-ellipsis "直播间基本信息...录制时长" --width 800`.
   - For the "直播间贴面与 UI" section, keep the table compact with two columns and do not include the separate UI screenshot section unless the user explicitly requests it.
   - After creating the Feishu document, return the document URL or ID, the local source report path, and whether screenshot insertion succeeded.
   - Use concise, operator-facing Chinese unless the user requests another language.

9. Learn after each report.
   - Update `references/memory.md` with durable competitor tactics, reusable script patterns, recurring audience objections, and proven analysis heuristics.
   - Do not store raw comments, transcripts, or screenshots in memory.
   - Add only compact, non-sensitive summaries and source pointers.

## Quality Checklist

- The date, platform, account, product, and observation window are explicit.
- Archive folder, media file path, audio file path, and transcript path are explicit when files exist.
- Comment JSONL path and comment count are explicit when comments were captured.
- Anchor speech, comments, and visual content are separated before conclusions.
- Key conclusions cite evidence from at least one observation type.
- Viewer privacy is protected.
- Recommendations are specific enough to test in our own live room or content workflow.
- Reusable learnings have been added to memory when appropriate.

## Templates

Use `assets/monitor-report-template.md` when the user wants a reusable report format.
Use `assets/realtime-monitor-log-template.md` for live speech-to-text monitoring sessions.
Use `assets/douyin-case-analysis-template.md` for detailed single-room analysis.
Use `assets/single-transcript-analysis-template.md` for transcript-only analysis.
Use `assets/multi-room-comparison-template.md` for multi-room comparison analysis.
