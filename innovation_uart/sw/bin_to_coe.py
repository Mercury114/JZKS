#!/usr/bin/env python3
"""创新扩展：为独立的指令RAM和数据RAM生成小端32位COE。"""
from pathlib import Path
import hashlib
import json

def convert(source, output):
    data = source.read_bytes()
    if not data:
        raise SystemExit(f'Empty binary: {source}')
    data += bytes((-len(data)) % 4)
    words = [int.from_bytes(data[i:i + 4], 'little') for i in range(0, len(data), 4)]
    output.write_text('memory_initialization_radix=16;\nmemory_initialization_vector=\n'
                      + ',\n'.join(f'{word:08x}' for word in words) + ';\n', encoding='ascii')
    print(f'COE_GENERATED: {output.name} words={len(words)} bytes={len(data)}')
    return len(words)

def main():
    out = Path(__file__).resolve().parent / 'obj'
    inst_words = convert(out / 'main.bin', out / 'inst_ram.coe')
    data_words = convert(out / 'data_ram.bin', out / 'data_ram.coe')
    report = dict(program='UART command console', entry='0x1c000000',
                  instruction_words=inst_words, data_words=data_words,
                  binary_sha256=hashlib.sha256((out / 'main.bin').read_bytes()).hexdigest(),
                  data_sha256=hashlib.sha256((out / 'data_ram.bin').read_bytes()).hexdigest())
    (out / 'verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')

if __name__ == '__main__':
    main()
