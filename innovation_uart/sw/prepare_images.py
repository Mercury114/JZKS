#!/usr/bin/env python3
"""Prepare UART MIF inputs without overwriting the official Exp9 images."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'innovation_uart/sw/obj'

def main():
    results = {}
    for name, depth in [('inst_ram',262144), ('data_ram',65536)]:
        source=OUT/(name+'.coe')
        text=source.read_text(encoding='ascii')
        if not re.search(r'memory_initialization_radix\s*=\s*16\s*;',text,re.I):
            raise ValueError(f'{source}: expected radix 16')
        vector=re.search(r'memory_initialization_vector\s*=\s*([^;]+);',text,re.I)
        if not vector: raise ValueError(f'{source}: missing initialization vector')
        words=[int(x,16) for x in re.split(r'[\s,]+',vector[1].strip())]
        if not words or len(words)>depth or any(x<0 or x>0xffffffff for x in words):
            raise ValueError(f'{source}: invalid RAM contents')
        image=''.join(f'{word:032b}\n' for word in words)
        image+='00000000000000000000000000000000\n'*(depth-len(words))
        destination=OUT/(name+'.mif')
        destination.write_text(image,encoding='ascii',newline='\n')
        results[name]={'words':len(words),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                       'mif_sha256':hashlib.sha256(destination.read_bytes()).hexdigest()}
        print(f'UART_MIF_PREPARED: {name} words={len(words)} depth={depth}')
    (OUT/'images.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__': main()
