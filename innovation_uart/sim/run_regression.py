#!/usr/bin/env python3
"""Run the course pipeline UART firmware against source-level synchronous RAM."""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
RTL = next(ROOT.glob('*/rtl/mycpu_top.v')).parent
BUILD = ROOT / 'innovation_uart' / 'build' / 'regression'
MODES = {'console': ('tb_uart_console', 'UART_CONSOLE_PASS'),
         'console_hw': ('tb_uart_console_hwclk', 'UART_CONSOLE_PASS'),
         'stopwatch': ('tb_uart_stopwatch', 'UART_STOPWATCH_PASS'),
         'stopwatch_hw': ('tb_uart_stopwatch_hwclk', 'UART_STOPWATCH_PASS'),
         'irq': ('tb_uart_irq', 'UART_IRQ_PASS'),
         'irq_hw': ('tb_uart_irq_hwclk', 'UART_IRQ_PASS'),
         'fifo': ('tb_uart_fifo', 'UART_FIFO_PASS')}

def image(name):
    text = (ROOT / f'innovation_uart/sw/obj/{name}.coe').read_text()
    words = [int(x.strip(), 16) for x in text.split('memory_initialization_vector=')[1].strip().rstrip(';').split(',')]
    # Full-size RAM images avoid short-file warnings and make initialization explicit.
    depth = 262144 if name == 'inst_ram' else 65536
    words += [0] * (depth - len(words))
    (BUILD / f'{name}.mif').write_text(''.join(f'{x:032b}\n' for x in words), encoding='ascii')

def run(mode):
    top, marker = MODES[mode]
    base = top.removesuffix('_hwclk')
    bench = ROOT / f'innovation_uart/sim/{base}.v'
    sources = [RTL / x for x in ('mycpu_top.v', 'tools.v', 'alu.v', 'regfile.v', 'IF_stage.v',
               'ID_stage.v', 'EXE_stage.v', 'MEM_stage.v', 'WB_stage.v', 'bridge_1x2.v',
               'confreg.v', 'soc_lite_top.v', 'course_ram.v', 'UART/uart_tx.v',
               'UART/uart_rx.v', 'UART/uart_mmio.v')]
    command = ['iverilog', '-g2012', '-s', top, '-I', str(RTL), '-o', str(BUILD / mode), *map(str, sources), str(bench)]
    compile_result = subprocess.run(command, cwd=BUILD, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (BUILD / f'{mode}-compile.log').write_text(compile_result.stdout)
    if compile_result.returncode:
        print(compile_result.stdout)
        raise RuntimeError(f'{mode}: compile failed')
    start = time.monotonic()
    result = subprocess.run(['vvp', str(BUILD / mode)], cwd=BUILD, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
    (BUILD / f'{mode}.log').write_text(result.stdout)
    print(result.stdout, end='', flush=True)
    if result.returncode or marker not in result.stdout or re.search(r'UART_\w*FAIL:', result.stdout):
        raise RuntimeError(f'{mode}: failed (see {BUILD / (mode + ".log")})')
    return dict(mode=mode, seconds=round(time.monotonic()-start, 2), output=result.stdout.strip())

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=list(MODES) + ['all'], default='all')
    args = parser.parse_args()
    for tool in ('iverilog', 'vvp'):
        if not shutil.which(tool):
            raise SystemExit(f'Missing {tool}; install Icarus Verilog first')
    BUILD.mkdir(parents=True, exist_ok=True)
    image('inst_ram'); image('data_ram')
    modes = MODES if args.mode == 'all' else [args.mode]
    records = [run(mode) for mode in modes]
    (BUILD / f'results-{args.mode}.json').write_text(json.dumps(records, indent=2), encoding='utf-8')
    print('UART_PIPELINE_REGRESSION_PASS:', ','.join(modes))

if __name__ == '__main__':
    main()
