#!/usr/bin/env python3
"""Self-contained five-stage CPU handshake regression (Icarus); no cache implementation required."""
from pathlib import Path
import subprocess, json, argparse
from cpu_program import *
ROOT=Path(__file__).resolve().parents[1]

def cache_program(smc=False):
    p=Program();e={}
    p.li(8,0x12345678);p.store(8,0x100)
    p.emit(ri(0x28800000,9,0,0x100))
    p.emit(ri(0x02800000,10,9,1));p.store(10,0x104)
    e[0x100]=0x12345678;e[0x104]=0x12345679
    if smc:
        # r12 is next PC; use unaligned CACOP address to guard against false ALE.
        target=BASE+4*(p.cursor+3)
        p.li(12,target)
        p.emit(ri(0x06000000,0x10,12,1))
        p.emit(ri(0x02800000,8,0,99))
        p.store(8,0x108);e[0x108]=11
        count=1
    else:
        p.li(12,0x123)
        for i,code in enumerate([0,1,8,9,0x10,0x11]):
            p.emit(ri(0x06000000,code,12,-3))
        # None of six code fields may be interpreted as an architectural destination.
        p.store(8,0x108);p.store(9,0x10c)
        e[0x108]=0x12345678;e[0x10c]=0x12345678
        count=6
    p.emit(0x50000000 | (2<<10));p.store(8,0x114)
    p.store(10,0x110);e[0x110]=0x12345679;e[0x114]=0
    p.finish()
    return (p,e,0,0,0),count,int(smc)

def alu_program():
    p=Program(); e={}; offset=0x100
    def check(word,expected):
        nonlocal offset
        p.emit(word);p.store(11,offset);e[offset]=expected&MASK;offset+=4
    # Independent ISA constants: register ALU, shifts, all signed/unsigned mul/div, immediates.
    p.li(8,0xffffff80);p.li(10,9)
    for op,val in [(0x00100000,-119),(0x00110000,-137),(0x00120000,1),(0x00128000,0),
                   (0x00140000,~(0xffffff80|9)),(0x00148000,0),(0x00150000,0xffffff89),
                   (0x00158000,0xffffff89),(0x00170000,0xffff0000),(0x00178000,0x007fffff),
                   (0x00180000,0xffffffff),(0x001c0000,-1152),(0x001c8000,0xffffffff),
                   (0x001d0000,8),(0x00200000,-14),(0x00208000,-2),
                   (0x00210000,0xffffff80//9),(0x00218000,0xffffff80%9)]:
        check(op|(10<<10)|(8<<5)|11,val)
    for op,imm,val in [(0x02000000,-100,1),(0x02400000,-100,1),(0x03400000,0x345,0x300),
                       (0x03800000,0x345,0xffffffc5),(0x03c00000,0x345,0xfffffcc5),
                       (0x02800000,-1,0xffffff7f)]:
        check(ri(op,11,8,imm),val)
    for op,shift,val in [(0x00408000,3,0xfffffc00),(0x00448000,3,0x1ffffff0),(0x00488000,3,0xfffffff0)]:
        check(op|(shift<<10)|(8<<5)|11,val)
    p.li(8,0x80017fff);p.store(8,0x80)
    for op,lane,val in [(0x28000000,0,-1),(0x28000000,1,127),(0x28000000,3,-128),
                        (0x28400000,0,32767),(0x28400000,2,-32767),(0x2a000000,3,128),
                        (0x2a400000,2,32769),(0x28800000,0,0x80017fff)]:
        check(ri(op,11,0,0x80+lane),val)
    p.li(8,0x1234);p.emit(ri(0x29000000,8,0,0x83));p.emit(ri(0x29400000,8,0,0x80))
    check(ri(0x28800000,11,0,0x80),0x34011234)
    p.finish();return p,e,0,0,0

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--seeds',type=int,default=3);a=ap.parse_args()
    b=ROOT/'build/cpu';b.mkdir(parents=True,exist_ok=True);binary=b/'cpu_handshake_tb'
    subprocess.run(['iverilog','-g2012','-I',str(ROOT/'rtl/cpu'),'-s','cpu_handshake_tb','-o',str(binary),str(ROOT/'tb/cpu_handshake_tb.v'),*map(str,(ROOT/'rtl/cpu').glob('*.v'))],check=True)
    drain=b/'cpu_flush_drain_tb'
    subprocess.run(['iverilog','-g2012','-I',str(ROOT/'rtl/cpu'),'-s','cpu_flush_drain_tb','-o',str(drain),str(ROOT/'tb/cpu_handshake_tb.v'),*map(str,(ROOT/'rtl/cpu').glob('*.v'))],check=True)
    subprocess.run(['vvp',str(drain)],check=True,timeout=15)
    cases=[('csr',csr_program(),0,0),('alu-load-muldiv',alu_program(),0,0)]
    cases += [('cacop-six',*cache_program()),('cacop-smc',*cache_program(True))]
    for code in [0,1,8,9,16,17]:
        cases.append((f'cacop-user-{code}',exception_program(ri(0x06000000,code,8,3),14,user=True),0,0))
    for code in [2,7,10,15,18,23,24,25,31]:
        cases.append((f'cacop-invalid-{code}',exception_program(ri(0x06000000,code,8,0),13),0,0))
    for word,code,name in [(0x002b0000,11,'syscall'),(0x002a0000,12,'break'),(0xffffffff,13,'ine'),(0x04000008,14,'ipe')]:
        cases.append((name,exception_program(word,code,user=code==14,young_branch=True),0,0))
    for op,size in [(0x28800000,4),(0x28400000,2),(0x2a400000,2),(0x29800000,4),(0x29400000,2)]:
        for lane in ([1,2,3] if size==4 else [1,3]):
            cases.append((f'ale-{op:x}-{lane}',exception_program(ri(op,8,0,0x100+lane),9,0x100+lane),0,0))
    for target,user in [(BASE+0x403,False),(0x80000400,True)]:
        cases.append((f'adef-{target:x}',exception_program(NOP,8,branch_target=target,user=user),0,0))
    for bit in range(8):cases.append((f'irq-{bit}',exception_program(NOP,0,irq=1<<bit),0,0))
    cases.append(('timer',exception_program(NOP,0,timer=True),0,0))
    runs=0
    for name,(p,e,fault,nex,irq),nca,smc in cases:
        rom=b/(name+'.hex');rom.write_text(''.join(f'{x:08x}\n' for x in p.rom))
        mem=[MASK]*256
        for addr,val in e.items():mem[addr//4]=val
        ep=b/(name+'.expect');ep.write_text(''.join(f'{x:08x}\n' for x in mem))
        for seed in range(1,a.seeds+1):
            for reset,zero in [(r,z) for r in ([0,1] if nex else [0]) for z in [0,1]]:
                r=subprocess.run(['vvp',str(binary),f'+ROM={rom.name}',f'+EXPECT={ep.name}',f'+FAULT={fault:x}',f'+EXCEPTIONS={nex}',f'+IRQ={irq}',f'+RESET={reset}',f'+CACOPS={nca}',f'+SMC={smc}',f'+SEED={seed}',f'+ZERO={zero}'],cwd=b,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=15)
                if r.returncode:print(name,seed,reset,zero,r.stdout);raise SystemExit(1)
                runs+=1
        print('PASS',name)
    (b/'coverage.json').write_text(json.dumps({'scenarios':[c[0] for c in cases],'runs':runs,'seeds':a.seeds},indent=2))
    print(f'PASS {len(cases)} scenarios / {runs} randomized-backpressure/delay runs')
if __name__=='__main__':main()
