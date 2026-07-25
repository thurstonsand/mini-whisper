#!/usr/bin/env python3
import argparse
import html
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = json.loads(args.results.read_text())
    manifest = {item["id"]: item for item in json.loads(args.manifest.read_text())}
    output = args.output or args.results.with_name("review.html")
    cards = []
    for fixture in result["fixtures"]:
        source = (
            (args.manifest.parent / manifest[fixture["id"]]["file"]).resolve().as_uri()
        )
        points = " ".join(
            f"{index * 3},{100 - min(100, probability * 100):.1f}"
            for index, probability in enumerate(fixture["probabilities"])
        )
        width = max(300, len(fixture["probabilities"]) * 3)
        segments = html.escape(
            json.dumps(
                fixture["segments"][
                    f"t{result['selected_settings']['threshold']:.2f}-m{result['selected_settings']['minimum_speech_ms']}"
                ]
            )
        )
        transcript = (
            html.escape(fixture.get("no_gate_transcript") or "") or "<em>empty</em>"
        )
        cards.append(f"""
<section>
  <h2>{html.escape(fixture["id"])}</h2>
  <p><strong>{fixture["split"]} · {fixture["label"]} · {"ACCEPT" if fixture["selected_accepts"] else "REJECT"}</strong></p>
  <audio controls src="{source}"></audio>
  <div class="timeline"><svg viewBox="0 0 {width} 100" preserveAspectRatio="none"><line x1="0" y1="50" x2="{width}" y2="50"/><polyline points="{points}"/></svg></div>
  <p>Segments: <code>{segments}</code></p>
  <p>No-gate transcript: {transcript}</p>
</section>""")
    document = f"""<!doctype html>
<meta charset="utf-8">
<title>Silence rejection review</title>
<style>
body {{ font: 15px system-ui; max-width: 1000px; margin: 2rem auto; padding: 0 1rem; background: #111; color: #eee }}
section {{ border: 1px solid #444; border-radius: 10px; margin: 1rem 0; padding: 1rem }}
audio {{ width: 100% }} .timeline {{ overflow-x: auto; background: #191919; margin-top: .75rem }}
svg {{ width: 100%; min-width: 300px; height: 120px }} line {{ stroke: #a66; stroke-dasharray: 4 3 }} polyline {{ fill: none; stroke: #7bd; stroke-width: 1.5 }}
code {{ overflow-wrap: anywhere }} em {{ color: #aaa }}
</style>
<h1>Silence rejection review</h1>
<p>Blue is Silero speech probability; the dashed line is 0.5. Listen before accepting the labels.</p>
{"".join(cards)}
"""
    output.write_text(document)
    print(output)


if __name__ == "__main__":
    main()
