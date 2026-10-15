#!/usr/bin/env python3
"""Clone or update the CC0 bootstrap dataset (alexeygrigorev/clothing-dataset-small).

`docs/adr/0003` keeps the Kaggle catalogue as the final training set; this CC0
set (no attribution required) is ADR-0003's own optional augmentation set and is
what lets the scanner pipeline be verified end to end without Kaggle credentials.

    python ml_workspace/bootstrap/fetch_dataset.py
    python ml_workspace/bootstrap/fetch_dataset.py --dest /mnt/d/.../data/clothing-dataset-small
    python ml_workspace/bootstrap/fetch_dataset.py --force      # wipe and re-clone

The clone is `--depth 1` (~103 MB) and lands in `bootstrap/data/`, which
`bootstrap/.gitignore` keeps out of git. Without a network the script stops with
the failing git command and what to check — it never leaves a half-clone behind
(a failed clone into a fresh directory is removed).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from common import (
    DATASET_ID,
    DATASET_URL,
    DEFAULT_DATA_DIR,
    DEFAULT_LABELS,
    SPLITS,
    BootstrapError,
    dataset_classes,
    split_images,
    vocabulary,
    write_json,
)

CLONE_TIMEOUT = 900


def run_git(args: list[str], timeout: int = CLONE_TIMEOUT) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            ["git", *args],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise BootstrapError("git is not on PATH; install git or clone the dataset by hand") from exc
    except subprocess.TimeoutExpired as exc:
        raise BootstrapError(f"git {args[0]} timed out after {timeout}s (no network?)") from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        hint = ""
        if args[0] in {"clone", "fetch", "ls-remote"}:
            hint = (
                "\n  A clone/fetch failure usually means no network, a proxy, or a blocked"
                "\n  github.com. Check with: git ls-remote " + DATASET_URL
            )
        raise BootstrapError(f"git {' '.join(args)} failed:\n{detail}{hint}") from exc


def check_network(url: str) -> str:
    """`git ls-remote` doubles as the reachability probe; returns the HEAD sha."""
    result = run_git(["ls-remote", url, "HEAD"], timeout=60)
    line = result.stdout.strip().splitlines()
    if not line:
        raise BootstrapError(f"git ls-remote {url} returned nothing; the remote is unreachable")
    return line[0].split()[0]


def clone_or_update(dest: Path, url: str, force: bool) -> str:
    if force and dest.exists():
        print(f"fetch_dataset: --force, removing {dest}")
        shutil.rmtree(dest)

    if (dest / ".git").is_dir():
        branch = run_git(["-C", str(dest), "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
        if not branch or branch == "HEAD":
            branch = "master"
        print(f"fetch_dataset: updating {dest} (shallow fetch of {branch})")
        run_git(["-C", str(dest), "fetch", "--depth", "1", "origin", branch])
        run_git(["-C", str(dest), "reset", "--hard", "FETCH_HEAD"])
    elif dest.exists() and any(dest.iterdir()):
        raise BootstrapError(
            f"{dest} exists, is not empty, and is not a git clone; move it aside or pass --force"
        )
    else:
        print(f"fetch_dataset: cloning {url} -> {dest}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            run_git(["clone", "--depth", "1", url, str(dest)])
        except BootstrapError:
            if dest.exists():  # never leave a half-clone behind
                shutil.rmtree(dest, ignore_errors=True)
            raise
    return run_git(["-C", str(dest), "rev-parse", "HEAD"]).stdout.strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dest", type=Path, default=DEFAULT_DATA_DIR, help="%(default)s")
    parser.add_argument("--url", default=DATASET_URL, help="%(default)s")
    parser.add_argument("--labels", type=Path, default=DEFAULT_LABELS, help="%(default)s")
    parser.add_argument("--force", action="store_true", help="delete --dest first")
    args = parser.parse_args(argv)

    try:
        remote_head = check_network(args.url)
        print(f"fetch_dataset: {DATASET_ID} reachable (HEAD {remote_head[:12]})")
        commit = clone_or_update(args.dest, args.url, args.force)
        vocab = vocabulary(args.labels)
        pairs = dataset_classes(args.dest, vocab)
        folders = [folder for folder, _ in pairs]
        report = {
            "dataset": DATASET_ID,
            "url": args.url,
            "licence": "CC0-1.0",
            "commit": commit,
            "remote_head": remote_head,
            "dest": str(args.dest),
            "splits": {},
        }
        print(f"fetch_dataset: commit {commit}")
        for split in SPLITS:
            images = split_images(args.dest, split, folders)
            report["splits"][split] = {folder: len(paths) for folder, paths in images.items()}
            total = sum(len(paths) for paths in images.values())
            print(f"  {split:<10} {total:>5} images, {len(images)} classes")
        for folder, label in pairs:
            print(f"  {folder:<12} -> {label}")
        write_json(args.dest.parent / "dataset_summary.json", report)
        print(f"fetch_dataset: wrote {args.dest.parent / 'dataset_summary.json'}")
    except BootstrapError as exc:
        print(f"fetch_dataset: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
