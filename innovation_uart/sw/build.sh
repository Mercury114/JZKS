#!/usr/bin/env bash
# 创新扩展：UART命令终端，分别编译指令ROM和字符串数据RAM初始化文件。
set -euo pipefail
sw_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
default_tools="${XDG_DATA_HOME:-$HOME/.local/share}/jzks-uart/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin"
tools="${LA32R_TOOLCHAIN_BIN:-$default_tools}"
prefix="$tools/loongarch32r-linux-gnusf-"
out="$sw_dir/obj"
for tool in as ld objcopy objdump readelf; do
    test -x "${prefix}${tool}" || { printf 'Missing LA32R tool: %s\n' "${prefix}${tool}" >&2; exit 1; }
done
mkdir -p "$out"
python3 "$sw_dir/generate_data.py"
"${prefix}as" -I "$sw_dir" "$out/uart_console_expanded.S" -o "$out/main.o"
"${prefix}ld" -T "$sw_dir/uart.lds" "$out/main.o" -o "$out/main.elf"
"${prefix}objcopy" -O binary -j .text "$out/main.elf" "$out/main.bin"
"${prefix}objcopy" -O binary -j .rodata "$out/main.elf" "$out/data_ram.bin"
"${prefix}objdump" -d "$out/main.elf" > "$out/test.s"
"${prefix}readelf" -h "$out/main.elf" > "$out/elf_header.txt"
python3 "$sw_dir/bin_to_coe.py"
printf 'UART_CONSOLE_BUILD_PASS\n'
