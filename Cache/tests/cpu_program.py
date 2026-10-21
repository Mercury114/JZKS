# Program helpers copied from user la-course-design/tests/part6/run.py; source preserved.
#!/usr/bin/env python3
"""Part 6 短程序按 ISA 建立固定期望，覆盖 CSR 与精确异常。"""
from pathlib import Path
import argparse
import json
import subprocess
ROOT=Path(__file__).resolve().parents[2]
BASE=0x1c000000
NOP=0x02800000
MASK=0xffffffff

def ri(op,rd,rj,imm):
    return op | ((imm&4095)<<10) | (rj<<5) | rd

def csr(rd,num,rj=0):
    return 0x04000000 | (num<<10) | (rj<<5) | rd

class Program:
    def __init__(self):
        self.rom=[NOP]*1024
        self.cursor=0
    def emit(self,x):
        pc=BASE+4*self.cursor
        self.rom[self.cursor]=x
        self.cursor+=1
        return pc
    def li(self,rd,v):
        v &= MASK
        low=(v&4095)-(4096 if v&2048 else 0)
        self.emit(0x14000000 | ((((v-low)&MASK)>>12)<<5) | rd)
        self.emit(ri(0x02800000,rd,rd,low))
    def store(self,rd,offset):
        self.emit(ri(0x29800000,rd,0,offset))
    def finish(self):
        self.emit(ri(0x02800000,29,0,0x55a))
        self.emit(0x50000000)

def exception_program(word,ecode,badv=None,user=False,irq=0,timer=False,branch_target=None,
                      young_mul=False,young_branch=False):
    p=Program()
    p.li(12,BASE+0x800);p.emit(csr(12,0xc,1))
    p.li(8,77);p.li(9,3);p.li(10,0x345);p.store(10,0x100)
    p.li(12,0x12345678);p.emit(csr(12,0x31,1))
    if irq or timer:
        p.li(12,(irq<<2) | (0x800 if timer else 0));p.emit(csr(12,4,1))
        if timer:
            p.li(12,1);p.emit(csr(12,0x41,1))
            for _ in range(12):p.emit(NOP)
        p.li(12,4);p.emit(csr(12,0,1))
    elif user:
        p.li(12,3);p.emit(csr(12,0,1))
    if branch_target is not None:
        p.li(12,branch_target)
        p.emit(0x4c000000 | (12<<5))
        fault_pc=branch_target
    else:
        fault_pc=p.emit(word)
    # Part 6: 可将年轻乘法放在异常之后，检查正在保存的乘积被 WB 冲刷取消。
    if young_mul:
        p.emit(0x001c0000 | (9<<10) | (8<<5) | 8)
    # Part 6: 年轻分支的待重定向状态与老异常提交交叠，WB必须保持优先级。
    if young_branch:
        p.emit(NOP)
        p.emit(0x50000000 | (0x40<<10))
    # Part 6: 错路依次含 store、除法和 CSR 写；异常/返回必须取消这些副作用。
    p.store(10,0x104)
    p.emit(0x00200000 | (9<<10) | (8<<5) | 8)
    p.li(12,0xabcdef01);p.emit(csr(12,0x31,1))
    p.emit(ri(0x02800000,8,0,999))
    resume=BASE+4*p.cursor
    p.store(8,0x10c)
    if not user:
        p.emit(csr(12,0x31));p.store(12,0x110)
    p.finish()
    p.cursor=0x800//4
    for num,offset in [(6,0x200),(5,0x204),(7,0x208),(0,0x20c),(1,0x210)]:
        p.emit(csr(12,num));p.store(12,offset)
    p.emit(csr(12,0x31));p.store(12,0x110)
    p.emit(csr(0,5,1))
    p.li(12,1);p.emit(csr(12,0x44,1))
    p.li(12,resume);p.emit(csr(12,6,1));p.emit(0x06483800)
    expect={0x100:0x345,0x104:0,0x10c:77,0x110:0x12345678,
            0x200:fault_pc,0x204:(ecode<<16) | (0x800 if timer else 0),0x208:(badv if badv is not None else (fault_pc if ecode==8 else 0)),
            0x20c:8,0x210:4 if irq or timer else 3 if user else 0}
    return p,expect,fault_pc,1,irq

def csr_program():
    p=Program();expect={}
    p.li(8,0x12345678);p.emit(csr(8,0x30,1));p.store(8,0x100)
    p.emit(csr(10,0x30));p.store(10,0x104)
    p.li(8,0xabcdef01);p.li(9,0x00ff00ff)
    p.emit(csr(8,0x30,9));p.store(8,0x108)
    p.emit(csr(10,0x30));p.store(10,0x10c)
    p.li(8,0x76543210);p.emit(csr(8,0x40,1))
    p.emit(0x00006000 | (11<<5));p.store(11,0x110)
    p.emit(0x00006400 | 12);p.store(12,0x114)
    p.emit(csr(10,0x3fff));p.store(10,0x118)
    # Part 6: 零目的寄存器仍执行 CSR 软件写；未实现 CSR 写不产生其他状态。
    p.emit(csr(0,0x30,1));p.emit(csr(10,0x30));p.store(10,0x11c)
    p.li(8,MASK);p.emit(csr(8,0x3fff,1));p.store(8,0x120)
    p.finish()
    expect={0x100:0,0x104:0x12345678,0x108:0x12345678,0x10c:0x12cd5601,
            0x110:0x76543210,0x114:0,0x118:0,0x11c:0,0x120:0}
    return p,expect,0,0,0
