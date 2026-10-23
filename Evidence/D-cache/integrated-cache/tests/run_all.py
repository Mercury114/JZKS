#!/usr/bin/env python3
"""统一本地回归；每层独立记账，不把编译、仿真和硬件验收混为一谈。"""
from pathlib import Path
from datetime import datetime, timedelta, timezone
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "Cache"
BUILD = CACHE / "build/regression"
RTL = CACHE / "rtl"
CONF = ROOT / "Exp9_源码_v文件/rtl/confreg.v"
UART = sorted((ROOT / "Exp9_源码_v文件/rtl/UART").glob("*.v"))
GIT = shutil.which("git") or str(ROOT.parent / "mingit" / "cmd" / "git.exe")
records = []


def command(name, argv, marker=None, timeout=600):
    start = time.monotonic()
    result = subprocess.run(list(map(str, argv)), cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    (BUILD / f"{name}.log").write_text(result.stdout)
    if result.returncode or (marker and marker not in result.stdout) or "FAIL " in result.stdout:
        print(result.stdout)
        raise RuntimeError(f"{name} failed: {BUILD / (name + '.log')}")
    records.append({"name": name, "status": "PASS", "seconds": round(time.monotonic() - start, 3),
                    "command": [str(x.relative_to(ROOT)) if isinstance(x, Path) and x.is_relative_to(ROOT) else str(x) for x in argv],
                    "output": result.stdout.strip()})
    print(f"PASS {name}", flush=True)
    return result.stdout


def sim(name, top, sources, marker, parameters=None):
    binary = BUILD / name
    cmd = ["iverilog", "-g2012", "-s", top, "-I", RTL / "cpu", "-o", binary]
    for k, v in (parameters or {}).items():
        cmd += ["-P", f"{top}.{k}={v}"]
    command(f"{name}-compile", cmd + sources)
    return command(name, ["vvp", binary], marker)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--quick", action="store_true", help="Skip teacher and alternate board modes; not full delivery evidence")
    a = p.parse_args()
    for tool in ("iverilog", "vvp"):
        if not shutil.which(tool):
            raise RuntimeError(f"Required tool not found: {tool}")
    BUILD.mkdir(parents=True, exist_ok=True)
    sim("partner-dcache-original", "dcache_tb", [ROOT / "D-cache/rtl/dcache.v", ROOT / "D-cache/tb/dcache_tb.v"],
        "PASS D-Cache writeback/write-allocate/byte-enable/LRU/control regression")
    for ways in (1, 2, 4):
        sim(f"icache-ways{ways}", "icache_tb", [RTL / "cache_icache.v", CACHE / "tb/icache_tb.v"],
            "ICACHE RESET PASS", {"WAY_NUM": ways})
    sim("dcache-extended", "dcache_extended_tb", [RTL / "cache_dcache.v", CACHE / "tb/dcache_extended_tb.v"],
        "PASS all dcache extended cases")
    sim("arbiter", "arbiter_tb", [RTL / "cache_mem_arbiter.v", CACHE / "tb/arbiter_tb.v"], "PASS arbiter:")
    sub_sources = [RTL / f"cache_{x}.v" for x in ("icache", "dcache", "subsystem", "mem_arbiter")]
    for ways in (1, 2, 4):
        sim(f"subsystem-ways{ways}", "subsystem_tb", sub_sources +
            [CACHE / "tb/cache_memory_model.v", CACHE / "tb/subsystem_tb.v"], "PASS subsystem", {"WAY_NUM": ways})
    sim("original-mmio-bridge", "mmio_bridge_tb", sub_sources +
        [RTL / "cache_sram_bridge.v", CACHE / "tb/mmio_bridge_tb.v", CONF, *UART], "PASS original confreg")
    command("cpu-architectural", [sys.executable, CACHE / "tests/run_cpu.py"], "PASS 46 scenarios / 528")
    command("system-architectural-and-performance", [sys.executable, CACHE / "tests/run_system.py"], "PASS integrated system: 24 runs")
    teacher_results = []
    if not a.quick:
        command("teacher-ex4-to-ex9-two-way", [sys.executable, CACHE / "tests/run_teacher.py"], "PASS teacher ex9: 58/58")
        teacher_results += json.loads((CACHE / "build/teacher/results-ways2-enabled1.json").read_text())
        for ways in (1, 4):
            command(f"teacher-ex9-ways{ways}", [sys.executable, CACHE / "tests/run_teacher.py", "--exp", "9", "--ways", str(ways)],
                    "PASS teacher ex9: 58/58")
            teacher_results += json.loads((CACHE / f"build/teacher/results-ways{ways}-enabled1.json").read_text())
        command("teacher-ex9-no-cache", [sys.executable, CACHE / "tests/run_teacher.py", "--exp", "9", "--no-cache"], "PASS teacher ex9: 58/58")
        teacher_results += json.loads((CACHE / "build/teacher/results-ways2-enabled0.json").read_text())
    all_sources = sorted(RTL.glob("*.v")) + sorted((RTL / "cpu").glob("*.v")) + [CONF, *UART, ROOT / "Exp9_源码_v文件/rtl/remote2local.v"]
    for top in ("cache_system", "cache_soc_lite_top", "cache_remote_top"):
        command(f"default-{top}-compile", ["iverilog", "-g2012", "-tnull", "-s", top, "-I", RTL / "cpu", *all_sources])
    command("vivado-input-preparation", [sys.executable, CACHE / "scripts/prepare_vivado.py", "--exp", "9"], "Prepared ex9")
    if not Path(GIT).is_file() and not shutil.which("git"):
        raise RuntimeError("Git executable is required for the baseline-preservation check")
    # The integration branch deliberately differs from the older D-cache
    # branch. Verify that this regression itself has not modified either
    # course or partner source tree instead of comparing unrelated histories.
    dirty = subprocess.run([GIT, "diff", "--quiet", "--", "D-cache/rtl", "D-cache/tb", "Exp9_源码_v文件"], cwd=ROOT)
    if dirty.returncode:
        raise RuntimeError("Regression modified D-Cache RTL/testbench or Exp9 sources")
    source_files = sorted(RTL.rglob("*.v")) + sorted((CACHE / "tb").glob("*.v"))
    source_files += sorted((CACHE / "tests").glob("*.py")) + sorted((CACHE / "scripts").glob("*"))
    source_files += sorted((CACHE / "constraints").glob("*.xdc"))
    hashes = {str(x.relative_to(ROOT)): hashlib.sha256(x.read_bytes()).hexdigest() for x in source_files if x.is_file()}
    evidence = {
        # 上海当前使用UTC+8；不用依赖Windows默认不附带的IANA时区数据库。
        "verified_at": datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds"),
        "tier": "local RTL compilation and Icarus simulation; not Vivado/FPGA acceptance",
        "full_run": not a.quick,
        "tools": {"python": sys.version.split()[0], "iverilog": subprocess.run(["iverilog", "-V"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.splitlines()[0]},
        "source_guard": "D-cache RTL/testbench and Exp9 sources unchanged by this regression",
        "checks": records,
        "cpu": json.loads((CACHE / "build/cpu/coverage.json").read_text()),
        "system": json.loads((CACHE / "build/system/results.json").read_text()),
        "teacher": teacher_results,
        "source_sha256": hashes,
        "pending": ["Vivado XSim", "synthesis utilization", "routed timing", "bitstream", "FPGA/platform acceptance"]
    }
    docs = CACHE / "docs"
    docs.mkdir(exist_ok=True)
    dest = docs / ("verification-quick.json" if a.quick else "verification-results.json")
    dest.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n")
    print(f"PASS {'quick' if a.quick else 'full'} regression: {len(records)} checks; evidence {dest}")


if __name__ == "__main__":
    main()
