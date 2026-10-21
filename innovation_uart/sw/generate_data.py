#!/usr/bin/env python3
"""创新扩展：生成数据RAM字符串及汇编常量，避免从指令RAM读取数据。"""
from pathlib import Path
import re

ITEMS = {
    'MSG_READY': 'UART CONSOLE READY\r\n',
    'MSG_HELP': 'HELP CODE <char> LED <hex> DISP <hex> SW START STOP TIME RESET STAT MIRROR ON|OFF IRQ ON|OFF|COUNT\r\n',
    'MSG_OK': 'OK\r\n',
    'MSG_ERR': 'ERR\r\n',
    'MSG_LONG': 'ERR LINE TOO LONG\r\n',
    'MSG_ASCII': 'ASCII=0x',
    'MSG_SW': 'SW=0x',
    'MSG_TIME': 'TIME=',
    'MSG_SECONDS': ' s\r\n',
    'MSG_STAT': 'STATUS=0x',
    'MSG_IRQ_COUNT': 'IRQ_COUNT=0x',
    'MSG_EOL': '\r\n',
    'CMD_HELP': 'HELP', 'CMD_CODE': 'CODE', 'CMD_LED': 'LED',
    'CMD_DISP': 'DISP', 'CMD_SW': 'SW', 'CMD_TIME': 'TIME',
    'CMD_STAT': 'STAT', 'CMD_MIRROR': 'MIRROR',
    'CMD_START': 'START', 'CMD_STOP': 'STOP', 'CMD_RESET': 'RESET',
    'CMD_IRQ': 'IRQ',
    'ARG_COUNT': 'COUNT',
    'ARG_ON': 'ON', 'ARG_OFF': 'OFF',
}

def main():
    directory = Path(__file__).resolve().parent
    blob = bytearray()
    symbols = {}
    lines = ['# 创新扩展：自动生成，内容来自 generate_data.py。']
    for name, value in ITEMS.items():
        symbols[name] = len(blob)
        lines.append(f'.equ {name}, 0x{len(blob):08x}')
        blob.extend(value.encode('ascii') + b'\0')
    lines.append('.section .rodata')
    for offset in range(0, len(blob), 16):
        lines.append('.byte ' + ', '.join(f'0x{value:02x}' for value in blob[offset:offset + 16]))
    lines.append('.section .text')
    (directory / 'command_data.inc').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    # 课程LA32R汇编器的li.w伪指令只接受字面整数，构建时展开命名常量。
    source = (directory / 'uart_echo.S').read_text(encoding='utf-8')
    source = re.sub(r'\b(?:MSG|CMD|ARG)_[A-Z_]+\b',
                    lambda match: f'0x{symbols[match.group(0)]:08x}', source)
    out = directory / 'obj'
    out.mkdir(exist_ok=True)
    (out / 'uart_console_expanded.S').write_text(source, encoding='utf-8')
    print(f'UART_DATA_GENERATED: bytes={len(blob)}')

if __name__ == '__main__':
    main()
