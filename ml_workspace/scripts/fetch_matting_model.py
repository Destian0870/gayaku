#!/usr/bin/env python3
"""Fetch the u2netp matting model into flutter_app/assets/models/u2netp_320.tflite.

    python ml_workspace/scripts/fetch_matting_model.py
    python ml_workspace/scripts/fetch_matting_model.py --url <mirror> --target <path>

The script downloads the first candidate that answers over HTTPS, refuses anything that is
not a TFLite flatbuffer (magic bytes "TFL3" at offset 4) or that does not parse as the
TFLite schema, then prints the sha256, the file size and the model's input/output tensors
(name, shape, dtype) read straight from the flatbuffer by scripts/tflite_io.py -- never
guessed. The same numbers are recorded in ml_workspace/README.md and in
flutter_app/assets/models/LICENSES.md.

The shipped build is u2netp (U^2-Net small): one NHWC RGB input, seven mask outputs of
which the first is the fused saliency map. See README.md for why NHWC and not NCHW.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tflite_io import TfliteError, format_record, read_model  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TARGET = REPO_ROOT / "flutter_app" / "assets" / "models" / "u2netp_320.tflite"
MASK_SIZE = [1, 320, 320, 1]


@dataclass(frozen=True)
class Candidate:
    url: str
    note: str


CANDIDATES = (
    Candidate(
        "https://huggingface.co/abhimanyu666/u2nettflite/resolve/main/u2netp.tflite",
        "U^2-Net small (u2netp), 4.6 MB, the build this asset ships",
    ),
    Candidate(
        "https://huggingface.co/litert-community/U-2-Net/resolve/main/u2net_fp16.tflite",
        "full U^2-Net, float16, 88 MB, NCHW [1,3,320,320]; only if the u2netp mirror "
        "disappears, and it changes the APK budget and the Dart preprocessing",
    ),
)


class FetchError(Exception):
    """Download or verification failure."""


def download(url: str, destination: Path) -> None:
    print(f"fetch_matting_model: downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "gayaku-ml-workspace"})
    with urllib.request.urlopen(request) as response, destination.open("wb") as out:
        shutil.copyfileobj(response, out)
        print(f"fetch_matting_model: HTTP {response.status}, {out.tell()} bytes")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--url", help="download exactly this URL instead of the candidates")
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET, help="%(default)s")
    parser.add_argument(
        "--json", action="store_true", help="also print the record as one JSON object"
    )
    args = parser.parse_args(argv)

    args.target.parent.mkdir(parents=True, exist_ok=True)
    staged = args.target.with_suffix(".part")
    sources = (Candidate(args.url, "explicit --url"),) if args.url else CANDIDATES
    failures: list[str] = []
    for candidate in sources:
        try:
            download(candidate.url, staged)
            record = read_model(staged)
        except (TfliteError, OSError, ValueError) as exc:
            print(f"fetch_matting_model: {candidate.url} unusable: {exc}", file=sys.stderr)
            failures.append(f"{candidate.url} -- {exc}")
            continue
        if not record["inputs"] or not record["outputs"]:
            print(f"fetch_matting_model: {candidate.url} has no input/output tensors", file=sys.stderr)
            failures.append(f"{candidate.url} -- no tensor IO")
            continue
        staged.replace(args.target)
        record = read_model(args.target)
        record["source"] = candidate.url
        record["source_note"] = candidate.note
        print(f"fetch_matting_model: wrote {args.target}")
        print(format_record(record))
        print(f"  source {record['source']} ({record['source_note']})")
        if record["outputs"][0]["shape"] != MASK_SIZE:
            print(
                f"fetch_matting_model: warning: first output is {record['outputs'][0]['shape']}, "
                f"expected {MASK_SIZE}; update the Dart preprocessing and this script together"
            )
        if args.json:
            print(json.dumps(record))
        return 0
    print("fetch_matting_model: every candidate failed: " + "; ".join(failures), file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
