/* 创新扩展：Harvard结构，字符串放数据RAM，程序放指令RAM，各自生成COE。 */
OUTPUT_ARCH(loongarch)
ENTRY(_start)
SECTIONS
{
    . = 0x1c000000;
    .text : {
        *(.text)
        ASSERT(. <= 0x1c001000, "Main firmware overlaps IRQ entry");
        . = 0x1000;
        KEEP(*(.text.irq))
    }
    . = 0x00000000;
    .rodata : { *(.rodata*) }
    . = 0x00001000;
    .bss (NOLOAD) : { *(.bss*) *(COMMON) }
}
