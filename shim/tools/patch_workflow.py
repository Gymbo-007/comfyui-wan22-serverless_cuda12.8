#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def patch(workflow: dict, expose_width: bool = False) -> dict:
    nodes = workflow.get("nodes", [])
    by_id = {n.get("id"): n for n in nodes if isinstance(n, dict) and "id" in n}

    def set_widgets_value(node_id: int, idx: int, value):
        n = by_id.get(node_id)
        if not n:
            return
        wv = n.get("widgets_values")
        if isinstance(wv, list) and len(wv) > idx:
            wv[idx] = value
            n["widgets_values"] = wv

    def set_vhs_fps(node_id: int, value):
        n = by_id.get(node_id)
        if not n:
            return
        wv = n.get("widgets_values")
        if isinstance(wv, dict):
            wv["frame_rate"] = value
            n["widgets_values"] = wv

    # Prompts
    set_widgets_value(104, 0, "__PROMPT__")
    set_widgets_value(107, 0, "__NEGATIVE__")

    # Input image filename
    set_widgets_value(129, 0, "__INPUT_IMAGE_FILENAME__")

    # Video length (frames)
    set_widgets_value(96, 0, "__NUM_FRAMES__")

    # FPS for both base and final combine
    set_vhs_fps(16, "__FPS__")
    set_vhs_fps(85, "__FPS__")

    # Global steps
    set_widgets_value(91, 0, "__STEPS__")

    # Seed fixed
    seed = by_id.get(121)
    if seed and isinstance(seed.get("widgets_values"), list):
        wv = seed["widgets_values"]
        if len(wv) >= 1:
            wv[0] = "__SEED__"
        if len(wv) >= 2:
            wv[1] = "fixed"
        seed["widgets_values"] = wv

    # Optional: expose long-side resolution as WIDTH placeholder
    if expose_width:
        set_widgets_value(26, 0, "__WIDTH__")

    return workflow


def main():
    ap = argparse.ArgumentParser(description="Patch ComfyUI workflow to shim-ready placeholders.")
    ap.add_argument("input", type=Path, help="Path to original workflow JSON")
    ap.add_argument("output", type=Path, help="Path to write sim-ready workflow JSON")
    ap.add_argument("--expose-width", action="store_true", help="Expose long-side resolution as __WIDTH__ placeholder")
    args = ap.parse_args()

    data = json.loads(Path(args.input).read_text(encoding="utf-8"))
    out = patch(data, expose_width=args.expose_width)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote sim-ready workflow to: {args.output}")


if __name__ == "__main__":
    main()

