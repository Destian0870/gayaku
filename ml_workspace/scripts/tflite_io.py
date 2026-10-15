#!/usr/bin/env python3
"""Read a .tflite flatbuffer's tensor IO without TensorFlow, Litert, or the `tflite` package.

    python ml_workspace/scripts/tflite_io.py flutter_app/assets/models/u2netp_320.tflite
    python ml_workspace/scripts/tflite_io.py model.tflite --json

This is a ~100-line reader over the parts of the TFLite schema we care about (Model /
SubGraph / Tensor), so the workspace stays installable-free. It is verified against the
pip `tflite` bindings in ml_workspace/README.md.

Schema field numbers used (flatbuffers, tflite/schema/schema.fbs):

    Model     { 0:version 2:subgraphs 3:description }
    SubGraph  { 0:tensors 1:inputs 2:outputs 3:operators }
    Tensor    { 0:shape 1:type 2:buffer 3:name }
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

MAGIC = b"TFL3"
TENSOR_TYPES = {
    0: "float32",
    1: "float16",
    2: "int32",
    3: "uint8",
    4: "int64",
    5: "string",
    6: "bool",
    7: "int16",
    8: "complex64",
    9: "int8",
    10: "float64",
    11: "complex128",
    12: "uint64",
    13: "resource",
    14: "variant",
    15: "uint32",
    16: "uint16",
}


class TfliteError(Exception):
    """The file is not a TFLite flatbuffer, or not the one we expect."""


class Table:
    """A flatbuffers table: fields are reached through its vtable."""

    def __init__(self, buf: bytes, pos: int) -> None:
        self.buf = buf
        self.pos = pos

    def _field(self, index: int) -> int | None:
        vtable = self.pos - int.from_bytes(self.buf[self.pos : self.pos + 4], "little", signed=True)
        vtable_len = int.from_bytes(self.buf[vtable : vtable + 2], "little")
        offset = 4 + 2 * index
        if offset + 2 > vtable_len:
            return None
        relative = int.from_bytes(self.buf[vtable + offset : vtable + offset + 2], "little")
        return None if relative == 0 else self.pos + relative

    def _indirect(self, pos: int) -> int:
        return pos + int.from_bytes(self.buf[pos : pos + 4], "little")

    def integer(self, index: int, unsigned: bool = False) -> int | None:
        pos = self._field(index)
        if pos is None:
            return None
        return int.from_bytes(self.buf[pos : pos + 4], "little", signed=not unsigned)

    def byte(self, index: int, default: int | None = None) -> int | None:
        pos = self._field(index)
        if pos is None:
            return default
        return int.from_bytes(self.buf[pos : pos + 1], "little", signed=True)

    def string(self, index: int) -> str | None:
        pos = self._field(index)
        if pos is None:
            return None
        start = self._indirect(pos)
        length = int.from_bytes(self.buf[start : start + 4], "little")
        return self.buf[start + 4 : start + 4 + length].decode("utf-8", "replace")

    def integers(self, index: int) -> list[int]:
        pos = self._field(index)
        if pos is None:
            return []
        start = self._indirect(pos)
        count = int.from_bytes(self.buf[start : start + 4], "little")
        return [
            int.from_bytes(self.buf[start + 4 + 4 * i : start + 8 + 4 * i], "little", signed=True)
            for i in range(count)
        ]

    def tables(self, index: int) -> list[Table]:
        pos = self._field(index)
        if pos is None:
            return []
        start = self._indirect(pos)
        count = int.from_bytes(self.buf[start : start + 4], "little")
        return [Table(self.buf, self._indirect(start + 4 + 4 * i)) for i in range(count)]


def read_model(path: Path, subgraph_index: int = 0) -> dict:
    blob = path.read_bytes()
    if len(blob) < 8 or blob[4:8] != MAGIC:
        raise TfliteError(f"{path} is not a TFLite flatbuffer: bytes 4..8 are {blob[4:8]!r}")
    model = Table(blob, int.from_bytes(blob[0:4], "little"))
    subgraphs = model.tables(2)
    if subgraph_index >= len(subgraphs):
        raise TfliteError(f"{path} has {len(subgraphs)} subgraphs, no index {subgraph_index}")
    subgraph = subgraphs[subgraph_index]
    tensors = subgraph.tables(0)

    def describe(index: int) -> dict:
        tensor = tensors[index]
        # flatbuffers omits fields equal to the schema default, and TensorType's default
        # (0) is float32 -- read the default back in rather than reporting "unknown"
        tensor_type = tensor.byte(1, default=0)
        return {
            "name": tensor.string(3),
            "shape": tensor.integers(0),
            "dtype": TENSOR_TYPES.get(tensor_type, f"type {tensor_type}"),
        }

    return {
        "path": str(path),
        "bytes": len(blob),
        "sha256": hashlib.sha256(blob).hexdigest(),
        "schema_version": model.integer(0, unsigned=True),
        "producer": model.string(3),
        "subgraphs": len(subgraphs),
        "operator_count": len(subgraph.tables(3)),
        "inputs": [describe(index) for index in subgraph.integers(1)],
        "outputs": [describe(index) for index in subgraph.integers(2)],
    }


def format_record(record: dict) -> str:
    lines = [
        f"{record['path']}",
        f"  flatbuffer TFL3, schema v{record['schema_version']}, producer {record['producer']!r}",
        f"  {record['bytes']} bytes, sha256 {record['sha256']}",
        f"  {record['operator_count']} operators in subgraph 0 of {record['subgraphs']}",
    ]
    for kind in ("inputs", "outputs"):
        for index, tensor in enumerate(record[kind]):
            lines.append(
                f"  {kind[:-1]} {index}: name={tensor['name']!r} "
                f"shape={tensor['shape']} dtype={tensor['dtype']}"
            )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("model", type=Path)
    parser.add_argument("--subgraph", type=int, default=0)
    parser.add_argument("--json", action="store_true", help="print the record as one JSON object")
    args = parser.parse_args(argv)
    try:
        record = read_model(args.model, args.subgraph)
    except (TfliteError, OSError) as exc:
        print(f"tflite_io: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(record) if args.json else format_record(record))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
