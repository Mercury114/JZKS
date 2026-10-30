"""Render focused timing diagrams from Vivado XSim VCD files.

The VCD files are produced by the same debug-enabled AXI testbench snapshots
that generate the Vivado WDB files.  This script does not infer signal values;
every edge and bus value comes from the VCD transition records.
"""

from __future__ import annotations

import argparse
from bisect import bisect_right
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle


def parse_vcd(path: Path):
    scopes = []
    names = {}
    widths = {}
    changes = defaultdict(list)
    in_header = True
    time_ps = 0
    for raw in path.read_text(encoding="ascii", errors="replace").splitlines():
        line = raw.strip()
        if in_header:
            fields = line.split()
            if line.startswith("$scope "):
                scopes.append(fields[2])
            elif line.startswith("$upscope "):
                scopes.pop()
            elif line.startswith("$var "):
                width, symbol, name = int(fields[2]), fields[3], fields[4]
                full_name = "/" + "/".join(scopes + [name])
                names[full_name] = symbol
                widths[full_name] = width
            elif line.startswith("$enddefinitions"):
                in_header = False
            continue
        if not line or line.startswith("$"):
            continue
        if line.startswith("#"):
            time_ps = int(line[1:])
        elif line[0] in "01xXzZ":
            changes[line[1:]].append((time_ps, line[0].lower()))
        elif line[0] in "bB":
            bits, symbol = line[1:].split()
            changes[symbol].append((time_ps, bits.lower()))

    # Multiple hierarchical aliases can share one VCD symbol.
    signals = {}
    for name, symbol in names.items():
        events = changes[symbol]
        deduped = []
        for time, value in events:
            if deduped and deduped[-1][0] == time:
                deduped[-1] = (time, value)
            elif not deduped or deduped[-1][1] != value:
                deduped.append((time, value))
        signals[name] = (widths[name], deduped)
    return signals


def value_at(events, time_ps):
    times = [item[0] for item in events]
    pos = bisect_right(times, time_ps) - 1
    return events[pos][1] if pos >= 0 else "x"


def handshake_times(signals, top, valid, ready):
    clk = signals[f"/{top}/clk"][1]
    v = signals[f"/{top}/{valid}"][1]
    r = signals[f"/{top}/{ready}"][1]
    result = []
    for time, state in clk:
        if state == "1" and value_at(v, time - 1) == "1" and value_at(r, time - 1) == "1":
            result.append(time / 1000)
    return result


def display_value(bits, width):
    if any(ch not in "01" for ch in bits):
        return "X"
    number = int(bits, 2)
    if width <= 4:
        return f"{number:X}"
    return f"0x{number:0{(width + 3) // 4}X}"


def segments(events, lo_ps, hi_ps):
    selected = [(lo_ps, value_at(events, lo_ps))]
    selected += [(t, v) for t, v in events if lo_ps < t < hi_ps]
    selected.append((hi_ps, selected[-1][1]))
    return selected


def make_plot(signals, top, title, rows, lo_ns, hi_ns, output):
    fig_h = max(4.0, len(rows) * 0.38 + 1.15)
    fig, ax = plt.subplots(figsize=(16, fig_h), dpi=200)
    fig.patch.set_facecolor("#ffffff")
    ax.set_facecolor("#f8fafc")
    lo_ps, hi_ps = int(lo_ns * 1000), int(hi_ns * 1000)
    lane_count = len(rows)
    for index, (name, color) in enumerate(rows):
        full_name = f"/{top}/{name}"
        if full_name not in signals:
            raise KeyError(f"VCD does not contain {full_name}")
        width, events = signals[full_name]
        y = lane_count - index - 1
        ax.axhline(y + 0.1, color="#dce3ec", linewidth=0.7)
        section = segments(events, lo_ps, hi_ps)
        if width == 1:
            xs, ys = [], []
            for time, value in section:
                xs.append(time / 1000)
                ys.append(y + (0.64 if value == "1" else 0.16 if value == "0" else 0.4))
            ax.step(xs, ys, where="post", color=color, linewidth=2)
            for i in range(len(section) - 1):
                t0, value = section[i]
                t1 = section[i + 1][0]
                if value == "1" and t1 > t0:
                    ax.add_patch(Rectangle((t0 / 1000, y + 0.16),
                                           (t1 - t0) / 1000, 0.48,
                                           facecolor=color, alpha=0.17,
                                           linewidth=0))
        else:
            for i in range(len(section) - 1):
                t0, value = section[i]
                t1 = section[i + 1][0]
                if t1 <= t0:
                    continue
                x0, x1 = t0 / 1000, t1 / 1000
                ax.add_patch(Rectangle((x0, y + 0.17), x1 - x0, 0.48,
                                       facecolor=color, edgecolor=color,
                                       alpha=0.13, linewidth=1))
                if x1 - x0 >= (hi_ns - lo_ns) / 35:
                    ax.text((x0 + x1) / 2, y + 0.41,
                            display_value(value, width), ha="center",
                            va="center", fontsize=8.5, color="#17243a",
                            clip_on=True)
        label = name.rsplit("/", 1)[-1].removeprefix("m_axi_")
        ax.text(lo_ns - (hi_ns - lo_ns) * 0.012, y + 0.4, label,
                ha="right", va="center", fontsize=10, color="#14243e")

    ax.set_xlim(lo_ns, hi_ns)
    ax.set_ylim(-0.1, lane_count + 0.15)
    ax.set_yticks([])
    ax.set_xlabel("Simulation time (ns)", fontsize=11)
    ax.set_title(title, fontsize=15, weight="bold", pad=14)
    ax.grid(axis="x", color="#d1dbe8", linewidth=0.8)
    ax.tick_params(axis="x", labelsize=10)
    plt.subplots_adjust(left=0.16, right=0.99, top=0.92, bottom=0.09)
    fig.savefig(output, dpi=200)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bridge-vcd", type=Path, required=True)
    parser.add_argument("--cpu-vcd", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    bridge = parse_vcd(args.bridge_vcd)
    cpu = parse_vcd(args.cpu_vcd)

    for label, signals, top in [
        ("bridge", bridge, "cache_axi_bridge_tb"),
        ("cpu", cpu, "mycpu_top_axi_tb"),
    ]:
        for valid, ready in [
            ("arvalid", "arready"), ("rvalid", "rready"),
            ("awvalid", "awready"), ("wvalid", "wready"),
            ("bvalid", "bready"),
        ]:
            print(f"{label} {valid}/{ready}: {handshake_times(signals, top, valid, ready)} ns")

    make_plot(bridge, "cache_axi_bridge_tb", "AXI read: request, AR and R",
              [(name, color) for name, color in [
                  ("clk", "#4b5563"), ("mem_valid", "#16a34a"),
                  ("mem_ready", "#16a34a"), ("mem_addr", "#16a34a"),
                  ("arvalid", "#2563eb"), ("arready", "#2563eb"),
                  ("araddr", "#2563eb"), ("arsize", "#2563eb"),
                  ("rvalid", "#9333ea"), ("rready", "#9333ea"),
                  ("rdata", "#9333ea"), ("dut/m_axi_rlast", "#9333ea"),
                  ("mem_rvalid", "#16a34a"), ("mem_rdata", "#16a34a"),
              ]], 25, 130, args.output_dir / "axi_read_zoom.png")

    make_plot(bridge, "cache_axi_bridge_tb", "AXI write: independent AW/W, then B",
              [(name, color) for name, color in [
                  ("clk", "#4b5563"), ("mem_valid", "#16a34a"),
                  ("mem_ready", "#16a34a"), ("mem_addr", "#16a34a"),
                  ("mem_wstrb", "#16a34a"),
                  ("awvalid", "#2563eb"), ("awready", "#2563eb"),
                  ("awaddr", "#2563eb"), ("awsize", "#2563eb"),
                  ("wvalid", "#db2777"), ("wready", "#db2777"),
                  ("wdata", "#db2777"), ("wstrb", "#db2777"),
                  ("bvalid", "#9333ea"), ("bready", "#9333ea"),
                  ("bresp", "#9333ea"), ("mem_rvalid", "#16a34a"),
                  ("axi_error", "#dc2626"),
              ]], 105, 240, args.output_dir / "axi_write_zoom.png")

    make_plot(cpu, "mycpu_top_axi_tb", "Five-stage CPU: AXI and MMIO completion",
              [(name, color) for name, color in [
                  ("clk", "#4b5563"), ("awvalid", "#2563eb"),
                  ("awready", "#2563eb"), ("awaddr", "#2563eb"),
                  ("wvalid", "#db2777"), ("wready", "#db2777"),
                  ("wdata", "#db2777"), ("wstrb", "#db2777"),
                  ("bvalid", "#9333ea"), ("bready", "#9333ea"),
                  ("mmio_value", "#16a34a"),
                  ("wb_we", "#0f766e"), ("wb_num", "#0f766e"),
                  ("wb_data", "#0f766e"), ("axi_error", "#dc2626"),
              ]], 1220, 1335, args.output_dir / "axi_cpu_zoom.png")


if __name__ == "__main__":
    main()
