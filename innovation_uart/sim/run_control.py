#!/usr/bin/env python3
"""ISA-level regressions for the course pipeline CSR/IRQ correction."""
from pathlib import Path
import subprocess
import sys
import json
import argparse

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Cache/tests'))
from cpu_program import Program, ri, csr, BASE
RTL = next(ROOT.glob('*/rtl/mycpu_top.v')).parent
BUILD = ROOT / 'innovation_uart/build/control'

def program(test_case):
    p=Program()
    if test_case==0:
        p.li(8,0x12345678); p.emit(csr(8,0x30,1)); p.store(8,0x100)
        p.emit(csr(10,0x30)); p.store(10,0x104)
        p.li(8,0xabcdef01); p.li(9,0x00ff00ff)
        p.emit(csr(8,0x30,9)); p.store(8,0x108)
        p.emit(csr(10,0x30)); p.store(10,0x10c)
        p.li(8,0x76543210); p.emit(csr(8,0x40,1))
        p.li(8,0x13579bdf); p.store(8,0x180)
        p.emit(ri(0x28800000,8,0,0x180)); p.emit(csr(8,0x40,1)); p.store(8,0x110)
        p.emit(csr(0,0x40,1)); p.emit(csr(10,0x40)); p.store(10,0x114)
        p.li(10,1); p.store(10,0x3fc); p.emit(0x50000000)
    else:
        for reg in range(1,32): p.li(reg,0x3000 if reg==3 else reg+0x100)
        p.li(4,0)
        p.store(0,0x110); p.store(0,0x114)
        p.li(12,BASE+0x800); p.emit(csr(12,0xc,1))
        p.li(12,0x800); p.emit(csr(12,4,1))
        p.li(12,403); p.emit(csr(12,0x41,1))
        p.li(10,1); p.store(10,0x120)
        p.li(12,4); p.emit(csr(12,0,1))
        loop=p.cursor
        p.emit(ri(0x02800000,4,4,1)); p.store(4,0x100)
        p.emit(ri(0x28800000,5,0,0x100)); p.emit(ri(0x02800000,5,5,7)); p.store(5,0x104)
        offset=(loop-p.cursor)&0x3ffffff
        p.emit(0x50000000 | ((offset&0xffff)<<10) | (offset>>16))
        p.cursor=0x800//4
        p.emit(ri(0x02800000,3,3,-32))
        for reg,offset in [(12,0),(13,4),(14,8),(15,12)]: p.emit(ri(0x29800000,reg,3,offset))
        p.li(12,1); p.emit(csr(12,0x44,1))
        p.emit(ri(0x28800000,13,0,0x110)); p.emit(ri(0x02800000,13,13,1)); p.store(13,0x110)
        p.emit(ri(0x28800000,14,0,0x114)); p.emit(ri(0x03c00000,14,14,1)); p.store(14,0x114)
        for reg,offset in [(15,12),(14,8),(13,4),(12,0)]: p.emit(ri(0x28800000,reg,3,offset))
        p.emit(ri(0x02800000,3,3,32)); p.emit(0x06483800)
    return p.rom

def main():
    global RTL, BUILD
    parser=argparse.ArgumentParser()
    parser.add_argument('--case',choices=['all','csr','irq'],default='all')
    parser.add_argument('--baseline',help='Compile a Git revision instead of working-tree RTL; expected to fail for a6223e5')
    args=parser.parse_args()
    if args.baseline:
        revision=subprocess.check_output(['git','rev-parse','--verify',args.baseline+'^{commit}'],cwd=ROOT,text=True).strip()
        BUILD=ROOT/f'innovation_uart/build/control-baseline-{revision[:8]}'
        source_dir=BUILD/'rtl'
        source_dir.mkdir(parents=True,exist_ok=True)
        for name in ['mycpu_top','ID_stage','EXE_stage','MEM_stage','WB_stage','IF_stage','regfile','alu','tools','mycpu_head']:
            relative=(RTL/(name+'.v')).relative_to(ROOT).as_posix()
            data=subprocess.check_output(['git','show',f'{revision}:{relative}'],cwd=ROOT)
            (source_dir/(name+'.v')).write_bytes(data)
        RTL=source_dir
    BUILD.mkdir(parents=True,exist_ok=True)
    names=['mycpu_top','ID_stage','EXE_stage','MEM_stage','WB_stage','IF_stage','regfile','alu','tools']
    result=subprocess.run(['iverilog','-g2012','-I',str(RTL),'-s','tb_pipeline_control','-o',str(BUILD/'sim'),
                           *[str(RTL/(x+'.v')) for x in names],str(ROOT/'innovation_uart/sim/tb_pipeline_control.v')],capture_output=True,text=True)
    (BUILD/'compile.log').write_text(result.stdout+result.stderr)
    if result.returncode: raise SystemExit(result.stderr)
    records=[]
    for case in ([0,1] if args.case=='all' else [0 if args.case=='csr' else 1]):
        (BUILD/'control.hex').write_text(''.join(f'{word:08x}\n' for word in program(case)))
        run=subprocess.run(['vvp',str(BUILD/'sim'),f'+CASE={case}'],cwd=BUILD,text=True,capture_output=True,timeout=120)
        (BUILD/f'case{case}.log').write_text(run.stdout+run.stderr)
        print(run.stdout,end='',flush=True)
        if run.returncode or 'PIPELINE_CONTROL_PASS:' not in run.stdout: raise SystemExit(1)
        records.append(dict(case=case,output=run.stdout))
    (BUILD/'results.json').write_text(json.dumps(records,indent=2))

if __name__=='__main__': main()
