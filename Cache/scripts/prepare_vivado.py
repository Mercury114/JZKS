#!/usr/bin/env python3
"""验证教师输入哈希，并准备不含个人绝对路径的Vivado程序镜像。"""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import re

CACHE = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--exp", type=int, choices=range(4, 10), default=9)
    a = p.parse_args()
    manifest = json.loads((CACHE / "fixtures/manifest.json").read_text())
    record = next(x for x in manifest["programs"] if x["experiment"] == a.exp)
    raw = gzip.decompress((CACHE / "fixtures" / record["file"]).read_bytes())
    if hashlib.sha256(raw).hexdigest() != record["uncompressed_sha256"]:
        raise ValueError("Teacher COE hash mismatch")
    text = raw.decode().split("memory_initialization_vector", 1)[1].split("=", 1)[1].strip()
    words = [int(v, 16) for v in re.split(r"[\s,;]+", text) if v]
    if len(words) > 262144:
        raise ValueError("Program exceeds instruction RAM")
    build = CACHE / "build/vivado_input"
    build.mkdir(parents=True, exist_ok=True)
    (build / "program.hex").write_text("".join(f"{w:08x}\n" for w in words + [0] * (262144 - len(words))))
    target = {4: 29, 5: 33, 6: 39, 7: 46, 8: 47, 9: 58}[a.exp]
    (build / "settings.tcl").write_text(f"set cache_exp {a.exp}\nset cache_points {target}\n")
    print(f"Prepared ex{a.exp}, {target} points: {build / 'program.hex'}")


if __name__ == "__main__":
    main()
