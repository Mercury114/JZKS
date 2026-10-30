"""Create or verify the AXI evidence file inventory and SHA256 checksums."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


AXI_ROOT = Path(__file__).resolve().parents[1]
IMPORTANT = AXI_ROOT / "Important"
MANIFEST = IMPORTANT / "manifest.json"
SUMS = IMPORTANT / "SHA256SUMS.txt"


def source_of(relative: str) -> str:
    name = Path(relative).name
    if relative.endswith("screenshots/axi_read_vivado.png"):
        return "user Vivado GUI screenshot: 屏幕截图 2026-10-29 220357.png"
    if relative.endswith("screenshots/axi_write_vivado.png"):
        return "user Vivado GUI screenshot: 屏幕截图 2026-10-29 220617.png"
    if relative.endswith("screenshots/axi_cpu_overview_vivado.png"):
        return "Vivado GUI CPU overview screenshot"
    if relative.startswith("Important/AXI_PASS/bridge/"):
        if name == "open_wave.tcl":
            return "archive-local Vivado opening helper"
        if name == "vcd_export.log":
            return "Cache/build/axi/cache_axi_bridge_tb_vcd.log"
        if name.endswith(".wcfg"):
            return "Vivado-generated WCFG with viewing layout adjustments"
        return f"Cache/build/axi/{name if name != 'xsim.log' else 'cache_axi_bridge_tb_wave.log'}"
    if relative.startswith("Important/AXI_PASS/cpu/"):
        if name == "open_wave.tcl":
            return "archive-local Vivado opening helper"
        if name == "vcd_export.log":
            return "Cache/build/axi/mycpu_top_axi_tb_vcd.log"
        if name.endswith(".wcfg"):
            return "Vivado-generated WCFG with viewing layout adjustments"
        return f"Cache/build/axi/{name if name != 'xsim.log' else 'mycpu_top_axi_tb_wave.log'}"
    if relative.startswith("Supplementary/"):
        return "Cache/scripts/plot_axi_waveforms.py from XSim VCD"
    return "AXI evidence documentation"


def inventory() -> list[dict[str, object]]:
    entries = []
    for path in sorted(AXI_ROOT.rglob("*")):
        if not path.is_file() or path in (MANIFEST, SUMS):
            continue
        relative = path.relative_to(AXI_ROOT).as_posix()
        entries.append({
            "path": relative,
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "source": source_of(relative),
        })
    return entries


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    files = inventory()
    sums = "".join(f"{item['sha256']}  {item['path']}\n" for item in files)
    if args.verify:
        recorded = json.loads(MANIFEST.read_text(encoding="utf-8"))
        if recorded["files"] != files or SUMS.read_text(encoding="utf-8") != sums:
            raise SystemExit("AXI evidence manifest/checksums do not match archived files")
        print(f"PASS AXI evidence integrity: {len(files)} files")
        return
    repo_root = AXI_ROOT.parents[1]
    source_commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repo_root, text=True
    ).strip()
    manifest = {
        "source_commit": source_commit,
        "archive_date": "2026-10-30",
        "files": files,
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    SUMS.write_text(sums, encoding="utf-8")
    print(f"Wrote AXI evidence inventory: {len(files)} files")


if __name__ == "__main__":
    main()
