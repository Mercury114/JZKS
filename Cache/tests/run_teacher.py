#!/usr/bin/env python3
"""原始ex4~ex9功能点回归，所有输入随仓库保存，不依赖个人目录。"""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "Cache"
TARGETS = {4: 29, 5: 33, 6: 39, 7: 46, 8: 47, 9: 58}


def run(exp, ways=2, enabled=1):
    manifest = json.loads((CACHE / "fixtures/manifest.json").read_text())
    record = next(x for x in manifest["programs"] if x["experiment"] == exp)
    raw = gzip.decompress((CACHE / "fixtures" / record["file"]).read_bytes())
    if hashlib.sha256(raw).hexdigest() != record["uncompressed_sha256"]:
        raise ValueError("teacher COE hash mismatch")
    text = raw.decode().lower()
    if not re.search(r"memory_initialization_radix\s*=\s*16\s*;", text):
        raise ValueError("teacher COE radix must be 16")
    values = [int(v, 16) for v in re.split(r"[\s,;]+", text.split("memory_initialization_vector", 1)[1].split("=", 1)[1].strip()) if v]
    build = CACHE / "build/teacher" / f"ex{exp}-ways{ways}-enabled{enabled}"
    build.mkdir(parents=True, exist_ok=True)
    (build / "program.hex").write_text("".join(f"{w:08x}\n" for w in values + [0] * (262144 - len(values))))
    binary = build / "simulation"
    sources = [CACHE / "tb/teacher_cache_tb.v", ROOT / "Exp9_源码_v文件/rtl/confreg.v"]
    sources += sorted((ROOT / "Exp9_源码_v文件/rtl/UART").glob("*.v"))
    sources += sorted((CACHE / "rtl").glob("*.v")) + sorted((CACHE / "rtl/cpu").glob("*.v"))
    command = ["iverilog", "-g2012", "-s", "teacher_cache_tb", "-I", str(CACHE / "rtl/cpu"),
               "-P", f"teacher_cache_tb.WAY_NUM={ways}", "-P", f"teacher_cache_tb.ENABLE_CACHE={enabled}",
               "-o", str(binary), *map(str, sources)]
    subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    r = subprocess.run(["vvp", str(binary), "+ROM=program.hex", f"+POINTS={TARGETS[exp]}"],
                       cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=360)
    (build / "simulation.log").write_text(r.stdout)
    if r.returncode or f"PASS teacher cache SoC: {TARGETS[exp]} points" not in r.stdout:
        print(r.stdout)
        raise RuntimeError(f"teacher ex{exp} failed; see {build / 'simulation.log'}")
    print(f"PASS teacher ex{exp}: {TARGETS[exp]}/{TARGETS[exp]} points ways={ways} enabled={enabled}", flush=True)
    return {"experiment": exp, "points": TARGETS[exp], "ways": ways, "enabled": enabled,
            "cycles": int(re.search(r"points cycles=(\d+)", r.stdout)[1]),
            "coe_sha256": record["uncompressed_sha256"]}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--exp", type=int, choices=range(4, 10), action="append")
    p.add_argument("--ways", type=int, choices=(1, 2, 4), default=2)
    p.add_argument("--no-cache", action="store_true")
    args = p.parse_args()
    results = [run(exp, args.ways, int(not args.no_cache)) for exp in (args.exp or list(TARGETS))]
    dest = CACHE / "build/teacher" / f"results-ways{args.ways}-enabled{int(not args.no_cache)}.json"
    dest.write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
