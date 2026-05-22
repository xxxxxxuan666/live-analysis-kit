import argparse
import json
from pathlib import Path

from funasr import AutoModel


def normalize_results(results):
    if isinstance(results, dict):
        results = [results]
    normalized = []
    for item in results or []:
        text = item.get("text", "") if isinstance(item, dict) else str(item)
        sentence_info = item.get("sentence_info", []) if isinstance(item, dict) else []
        normalized.append(
            {
                "key": item.get("key", "") if isinstance(item, dict) else "",
                "text": text,
                "sentence_info": sentence_info,
                "raw": item,
            }
        )
    return normalized


def ms_to_stamp(ms):
    if ms is None:
        return ""
    total = int(ms) / 1000.0
    minutes = int(total // 60)
    seconds = total - minutes * 60
    return f"{minutes:02d}:{seconds:05.2f}"


def write_markdown(path, normalized, source):
    lines = [
        "# FunASR Transcript",
        "",
        f"- Source: `{source}`",
        "",
        "## Full Text",
        "",
    ]
    full_text = "\n".join(item["text"] for item in normalized if item.get("text"))
    lines.append(full_text.strip() or "(empty)")
    lines.extend(["", "## Timestamped Sentences", ""])

    any_sentence = False
    for item in normalized:
        for sent in item.get("sentence_info") or []:
            any_sentence = True
            start = sent.get("start")
            end = sent.get("end")
            text = sent.get("text", "")
            lines.append(f"- {ms_to_stamp(start)}-{ms_to_stamp(end)} {text}")

    if not any_sentence:
        lines.append("No sentence-level timestamps returned by the model.")

    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Transcribe audio with FunASR.")
    parser.add_argument("--input", required=True, help="Audio file path, preferably 16k mono wav.")
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-md", required=True)
    parser.add_argument("--model", default="paraformer-zh")
    parser.add_argument("--vad-model", default="fsmn-vad")
    parser.add_argument("--punc-model", default="ct-punc")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--batch-size-s", type=int, default=300)
    parser.add_argument("--hotword", default="")
    args = parser.parse_args()

    kwargs = {
        "model": args.model,
        "vad_model": args.vad_model,
        "punc_model": args.punc_model,
        "device": args.device,
        "disable_update": True,
    }
    model = AutoModel(**kwargs)
    generate_kwargs = {
        "input": args.input,
        "batch_size_s": args.batch_size_s,
        "sentence_timestamp": True,
    }
    if args.hotword:
        generate_kwargs["hotword"] = args.hotword

    results = model.generate(**generate_kwargs)
    normalized = normalize_results(results)

    Path(args.output_json).write_text(
        json.dumps(normalized, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    write_markdown(args.output_md, normalized, args.input)


if __name__ == "__main__":
    main()
