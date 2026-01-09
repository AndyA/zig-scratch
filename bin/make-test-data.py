#!/usr/bin/env python3

import argparse
import struct
from pathlib import Path
from typing import Iterable


def txt_to_doubles(in_file: Path, out_file: Path) -> None:
    with in_file.open("r", encoding="utf-8") as fin, out_file.open("wb") as fout:
        for lineno, raw in enumerate(fin, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                value = float(line)
            except ValueError as exc:
                raise ValueError(f"Invalid float on line {lineno}: {line!r}") from exc
            fout.write(struct.pack(">d", value))


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Convert a text file of numbers (one per line) to big-endian"
            " 64-bit doubles in a binary file."
        )
    )
    p.add_argument("input", type=Path, help="Input text file (one number per line)")
    p.add_argument("output", type=Path, help="Output binary file")
    return p.parse_args(argv)


def main() -> None:
    args = parse_args()
    if not args.input.exists():
        raise SystemExit(f"Input file does not exist: {args.input}")
    txt_to_doubles(args.input, args.output)
    print(f"Wrote doubles to {args.output}")


if __name__ == "__main__":
    main()
