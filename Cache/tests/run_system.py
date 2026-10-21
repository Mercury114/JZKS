#!/usr/bin/env python3
"""同程序、同主存延迟、等缓存容量的整机回归；期望来自独立 ISA 小解释器。"""
from pathlib import Path
import argparse
import itertools
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "Cache"
BUILD = CACHE / "build" / "system"
BASE = 0x1C000000
MASK = 0xFFFFFFFF


def sx(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def ri(op, rd, rj, imm):
    return op | ((imm & 4095) << 10) | (rj << 5) | rd


class Program:
    def __init__(self):
        self.words = [0x02800000] * 1024
        self.cursor = 0
        self.labels = {}
        self.fixups = []

    def emit(self, word):
        self.words[self.cursor] = word
        self.cursor += 1

    def li(self, rd, value):
        value &= MASK
        low = sx(value & 4095, 12)
        self.emit(0x14000000 | ((((value - low) & MASK) >> 12) << 5) | rd)
        self.emit(ri(0x02800000, rd, rd, low))

    def label(self, name):
        self.labels[name] = self.cursor

    def branch(self, name, op=0x50000000, rj=0, rd=0):
        self.fixups.append((self.cursor, name, op, rj, rd))
        self.emit(0)

    def cacop(self, code, rj, imm=0):
        self.emit(ri(0x06000000, code, rj, imm))

    def finish(self, resolve=True):
        self.emit(ri(0x02800000, 29, 0, 0x55A))
        self.emit(0x50000000)
        if not resolve:
            return
        for index, name, op, rj, rd in self.fixups:
            off = self.labels[name] - index
            if op in (0x50000000, 0x54000000):
                v = off & 0x3FFFFFF
                self.words[index] = op | ((v & 65535) << 10) | (v >> 16)
            else:
                self.words[index] = op | ((off & 65535) << 10) | (rj << 5) | rd


def reference(program, board=False):
    """只解释这些原创短程序用到的指令；不读取 DUT，也不从仿真结果生成答案。"""
    regs = [0] * 32
    inst = {BASE + 4 * i: w for i, w in enumerate(program.words)}
    memory = {}
    csr = {0: 8}
    pc = BASE
    trace = []
    touched = set()
    mmio = 0
    def physical(a):
        if not board or a >> 20 == 0x1C0 or (a & 0x1FFF0000) == 0x1FAF0000:
            return a
        return a & 0x3FFFF
    for _ in range(30000):
        w = inst.get(pc, 0)
        rd, rj, rk = w & 31, (w >> 5) & 31, (w >> 10) & 31
        a, b = regs[rj], regs[rk]
        immediate = sx((w >> 10) & 4095, 12)
        next_pc = (pc + 4) & MASK
        result = None
        if (w >> 25) == 0b0001010:
            result = ((w >> 5) & 0xFFFFF) << 12
        elif (w & 0xFFC00000) == 0x02800000:
            result = a + immediate
        elif (w & 0xFFFF8000) == 0x00100000:
            result = a + b
        elif (w & 0xFFC00000) in (0x28800000, 0x28000000, 0x2A000000, 0x28400000, 0x2A400000):
            address = physical((a + immediate) & MASK)
            if (address & 0x1FFF0000) == 0x1FAF0000:
                word = mmio
            else:
                word = inst.get(address & ~3, 0) if address >> 20 == 0x1C0 else memory.get(address & ~3, 0)
            op = w & 0xFFC00000
            size = 4 if op == 0x28800000 else 1 if op in (0x28000000, 0x2A000000) else 2
            value = (word >> (8 * (address & 3))) & ((1 << (size * 8)) - 1)
            result = sx(value, size * 8) if op in (0x28000000, 0x28400000) else value
        elif (w & 0xFFC00000) in (0x29800000, 0x29000000, 0x29400000):
            address = physical((a + immediate) & MASK)
            op = w & 0xFFC00000
            size = 4 if op == 0x29800000 else 1 if op == 0x29000000 else 2
            mask = ((1 << (8 * size)) - 1) << (8 * (address & 3))
            if (address & 0x1FFF0000) == 0x1FAF0000:
                mmio = (mmio & ~mask) | ((regs[rd] << (8 * (address & 3))) & mask)
            else:
                target = inst if address >> 20 == 0x1C0 else memory
                aligned = address & ~3
                target[aligned] = (target.get(aligned, 0) & ~mask) | ((regs[rd] << (8 * (address & 3))) & mask)
                touched.add(aligned)
        elif (w & 0xFC000000) in (0x50000000, 0x54000000):
            off = sx(((w & 1023) << 16) | ((w >> 10) & 65535), 26) * 4
            if (w & 0xFC000000) == 0x54000000:
                rd, result = 1, pc + 4
            next_pc = (pc + off) & MASK
        elif (w & 0xFC000000) == 0x5C000000:
            if a != regs[rd]:
                next_pc = (pc + sx((w >> 10) & 65535, 16) * 4) & MASK
        elif (w & 0xFC000000) == 0x4C000000:
            next_pc = (a + sx((w >> 10) & 65535, 16) * 4) & MASK
            result = pc + 4
        elif (w & 0xFFC00000) == 0x06000000:
            pass  # 架构可见内存不因维护动作改变；缓存端必须自行保证一致性。
        elif (w & 0xFF000000) == 0x04000000:
            number = (w >> 10) & 0x3FFF
            result = csr.get(number, 0)
            if rj:
                mask = MASK if rj == 1 else regs[rj]
                csr[number] = (result & ~mask) | (regs[rd] & mask)
        elif w == 0x002B0000:
            csr[1] = csr.get(0, 8) & 7
            csr[0] = csr.get(0, 8) & ~7
            csr[5] = 11 << 16
            csr[6] = pc
            next_pc = csr.get(12, 0) & ~63
        elif w == 0x06483800:
            csr[0] = (csr.get(0, 8) & ~7) | (csr.get(1, 0) & 7)
            next_pc = csr[6]
        else:
            raise AssertionError(f"unimplemented reference opcode {w:08x} pc={pc:08x}")
        if result is not None and rd:
            regs[rd] = result & MASK
            trace.append(f"{pc:08x} {rd:02x} {regs[rd]:08x}")
            if rd == 29 and regs[rd] == 0x55A:
                final = {a: inst[a] if a >> 20 == 0x1C0 else memory[a] for a in touched}
                final[0xBFAFF050] = mmio
                return trace, final
        pc = next_pc
    raise AssertionError("reference timeout")


def hot_loop(conflict=False):
    p = Program()
    p.li(8, 0x2000)
    p.li(14, 0x2200 if conflict else 0x2004)
    p.li(9, 64)
    p.li(10, 0)
    p.label("loop")
    for base in (8, 14):
        p.emit(ri(0x28800000, 11, base, 0))
        p.emit(ri(0x02800000, 11, 11, 1))
        p.emit(ri(0x29800000, 11, base, 0))
        p.emit(0x00100000 | (11 << 10) | (10 << 5) | 10)
    p.emit(ri(0x02800000, 9, 9, -1))
    p.branch("loop", 0x5C000000, 9, 0)
    p.cacop(0x11, 8)
    p.cacop(0x11, 14)
    p.li(12, 0xBFAFF050)
    p.emit(ri(0x29800000, 10, 12, 0))
    p.finish()
    return p


def functional():
    p = Program()
    p.li(8, 0x1000)
    p.li(9, 0xA1B2C3D4)
    p.emit(ri(0x29800000, 9, 8, 0))
    p.li(9, 0x80)
    p.emit(ri(0x29000000, 9, 8, 1))
    p.emit(ri(0x28000000, 10, 8, 1))
    p.emit(ri(0x2A000000, 11, 8, 1))
    p.li(9, 0x1234)
    p.emit(ri(0x29400000, 9, 8, 2))
    p.emit(ri(0x28800000, 13, 8, 0))
    p.emit(ri(0x02800000, 14, 13, 3))
    p.cacop(0x11, 8)
    # 同一取指行先执行旧函数，再D写回代码并I无效化。
    p.branch("routine", 0x54000000)
    p.li(8, BASE + 0x400)
    p.li(9, ri(0x02800000, 15, 0, 42))
    p.emit(ri(0x29800000, 9, 8, 0))
    p.cacop(0x11, 8)
    p.cacop(0x10, 8)
    p.branch("routine", 0x54000000)
    # 初始化/索引操作选未使用的组，way低位不要求对齐。
    p.li(8, 0x11F1)
    for code in (0x00, 0x01, 0x08, 0x09):
        p.cacop(code, 8)
    p.li(12, BASE + 0x800)
    p.emit(0x04000000 | (12 << 10) | (1 << 5) | 12)
    p.li(8, 0x1100)
    p.li(9, 0x777)
    p.emit(0x002B0000)
    p.emit(ri(0x29800000, 9, 8, 0))  # 异常后错误路径store，handler跳过它。
    p.label("resume")
    p.branch("safe")
    p.emit(ri(0x29800000, 9, 8, 4))  # 分支后的错误路径store。
    p.label("safe")
    p.emit(ri(0x28800000, 16, 8, 0))
    p.emit(ri(0x28800000, 17, 8, 4))
    p.cacop(0x11, 8)
    p.li(12, 0xBFAFF050)
    p.emit(ri(0x29800000, 15, 12, 0))
    p.emit(ri(0x28800000, 18, 12, 0))
    p.li(12, 0x1FAFF050)
    p.emit(ri(0x29800000, 14, 12, 0))
    p.finish(resolve=False)
    p.cursor = 0x400 // 4
    p.label("routine")
    p.emit(ri(0x02800000, 15, 0, 1))
    p.emit(0x4C000000 | (1 << 5))
    p.cursor = 0x800 // 4
    p.emit(0x04000000 | (6 << 10) | 20)  # ERA
    p.emit(ri(0x02800000, 20, 20, 8))
    p.emit(0x04000000 | (6 << 10) | (1 << 5) | 20)
    p.emit(0x06483800)
    p.finish()  # resolves later function labels, unreachable marker is harmless
    return p


def board_alias():
    p = Program()
    p.li(8, 0x100)
    p.li(9, 0x11223344)
    p.emit(ri(0x29800000, 9, 8, 0))
    p.li(14, 0x40100)
    p.emit(ri(0x28800000, 15, 14, 0))
    p.emit(ri(0x02800000, 15, 15, 1))
    p.emit(ri(0x29800000, 15, 14, 0))
    p.li(14, 0x80000100)
    p.emit(ri(0x28800000, 16, 14, 0))
    p.cacop(0x11, 14)
    p.emit(ri(0x28800000, 17, 8, 0))
    p.finish()
    return p


def run(name, program, mode, latency, jitter, board=False):
    enabled, ways, index_width = {"none": (0, 1, 5), "direct": (1, 1, 5),
                                   "two-way": (1, 2, 4), "four-way": (1, 4, 3)}[mode]
    work = BUILD / f"{name}-{mode}-l{latency}-j{jitter}"
    work.mkdir(parents=True, exist_ok=True)
    trace, expected = reference(program, board)
    (work / "program.hex").write_text("".join(f"{w:08x}\n" for w in program.words))
    (work / "memory.expect").write_text("".join(f"{a:08x} {v:08x}\n" for a, v in sorted(expected.items())))
    (work / "golden.trace").write_text("\n".join(trace) + "\n")
    binary = work / "simulation"
    command = ["iverilog", "-g2012", "-s", "system_tb", "-I", str(CACHE / "rtl/cpu"), "-o", str(binary)]
    for parameter, value in dict(INDEX_WIDTH=index_width, WAY_NUM=ways, ENABLE_CACHE=enabled,
                                 LATENCY=latency, JITTER=jitter, BOARD_ADDR_MAP=int(board)).items():
        command += ["-P", f"system_tb.{parameter}={value}"]
    command += [str(CACHE / "tb/system_tb.v"), str(CACHE / "tb/cache_memory_model.v")]
    command += [str(x) for x in sorted((CACHE / "rtl").glob("*.v"))]
    command += [str(x) for x in sorted((CACHE / "rtl/cpu").glob("*.v"))]
    subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    result = subprocess.run(["vvp", str(binary), "+ROM=program.hex", f"+ROM_WORDS={len(program.words)}", "+TRACE=actual.trace", "+EXPECT=memory.expect"],
                            check=True, cwd=work, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    (work / "simulation.log").write_text(result.stdout)
    actual = (work / "actual.trace").read_text().splitlines()
    if trace != actual:
        for i, (want, got) in enumerate(itertools.zip_longest(trace, actual)):
            if want != got:
                raise AssertionError(f"{work.name}: first trace mismatch at write {i}: expected={want} got={got}")
    metrics = re.search(r"METRICS (.+)", result.stdout)
    if not metrics:
        raise AssertionError(result.stdout)
    data = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", metrics[1])}
    data.update(program=name, mode=mode, latency=latency, jitter=jitter,
                capacity_each=0 if not enabled else (1 << index_width) * ways * 16,
                trace_writes=len(trace), board_addr_map=board)
    print(f"PASS {work.name}: {data['cycles']} cycles, {len(trace)} exact architectural writes", flush=True)
    return data


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--quick", action="store_true")
    args = p.parse_args()
    results = []
    programs = [("hot-loop", hot_loop()), ("conflict-loop", hot_loop(True)), ("functional-smc-trap", functional())]
    for name, program in programs:
        for mode in ("none", "direct", "two-way", "four-way"):
            results.append(run(name, program, mode, 8, 0))
    if not args.quick:
        for latency in (0, 3):
            for mode in ("none", "direct", "two-way", "four-way"):
                results.append(run("functional-smc-trap", functional(), mode, latency, 1))
    for mode in ("none", "direct", "two-way", "four-way"):
        results.append(run("board-physical-alias", board_alias(), mode, 2, 1, board=True))
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print(f"PASS integrated system: {len(results)} runs; golden GPR traces and committed memory matched")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(e.stdout or "")
        raise
