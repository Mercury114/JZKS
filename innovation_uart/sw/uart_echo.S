# 创新扩展：UART命令终端。CPU使用仓库原版，所有交互均由CPU执行汇编完成。
# r20 UART基址，r21 GPIO基址，r22 TIMER，r23 行缓冲，r24 长度，
# r25 MIRROR使能，r26 超长行标记，r27 CRLF标记，r28 上次开关值。
# 创新扩展：秒表r29运行标志，r30/r31为64位累计tick；0x1100为上次tick。
# TIME快照放0x1120/0x1124，十进制输出缓冲放0x1140..0x115f。
# 字符串由数据RAM COE加载至0地址；行缓冲0x1000，栈顶0x3fff0。
    .include "command_data.inc"
    .section .text
    .globl _start
_start:
    li.w    $r3, 0x0003fff0
    li.w    $r20, 0xbfaff100
    li.w    $r21, 0xbfaff000
    li.w    $r22, 0xbfafe000
    li.w    $r23, 0x00001000
    or      $r24, $r0, $r0
    or      $r25, $r0, $r0
    or      $r26, $r0, $r0
    or      $r27, $r0, $r0
    li.w    $r28, 256
    or      $r29, $r0, $r0
    or      $r30, $r0, $r0
    or      $r31, $r0, $r0
    li.w    $r12, 0x1100
    st.w    $r0, $r12, 0
    li.w    $r12, -1
    st.w    $r12, $r21, 0x20   # 网页LED高有效，板级对本地信号取反。
    st.w    $r0, $r21, 0x50
    # 创新扩展：定时器中断。0x1160保存次数，0x1164保存LED相位。
    li.w    $r12, 0x1160
    st.w    $r0, $r12, 0
    st.w    $r0, $r12, 4
    li.w    $r12, 0x1c001000
    csrwr   $r12, 0x0c          # EENTRY，链接脚本固定的64字节对齐入口。
    li.w    $r12, 0x800
    csrwr   $r12, 0x04          # ECFG.LIE[11]允许定时器，CRMD.IE暂不开启。
    li.w    $r4, MSG_READY
    bl      puts

main_loop:
    bl      stopwatch_update
    beq     $r25, $r0, poll_rx
    ld.w    $r12, $r21, 0x60
    xori    $r12, $r12, 0xff   # 转换为网页低8位开关的直观状态。
    andi    $r12, $r12, 0xff
    beq     $r12, $r28, poll_rx
    or      $r28, $r12, $r0
    st.w    $r12, $r21, 0x50
    nor     $r13, $r12, $r0
    st.w    $r13, $r21, 0x20
poll_rx:
    ld.w    $r12, $r20, 8
    andi    $r12, $r12, 1
    beq     $r12, $r0, main_loop
    ld.w    $r14, $r20, 4
    andi    $r14, $r14, 0xff
    li.w    $r12, 13
    beq     $r14, $r12, line_cr
    li.w    $r12, 10
    beq     $r14, $r12, line_lf
    or      $r27, $r0, $r0
    bne     $r26, $r0, main_loop
    li.w    $r12, 8
    beq     $r14, $r12, backspace
    li.w    $r12, 127
    beq     $r14, $r12, backspace
    li.w    $r12, 9
    bne     $r14, $r12, printable
    li.w    $r14, 32
printable:
    li.w    $r12, 32
    bltu    $r14, $r12, main_loop
    li.w    $r12, 127
    bgeu    $r14, $r12, main_loop
    li.w    $r12, 63
    bgeu    $r24, $r12, line_too_long
    add.w   $r12, $r23, $r24
    st.b    $r14, $r12, 0
    addi.w  $r24, $r24, 1
    b       main_loop
backspace:
    beq     $r24, $r0, main_loop
    addi.w  $r24, $r24, -1
    b       main_loop
line_too_long:
    li.w    $r26, 1
    b       main_loop
line_cr:
    li.w    $r27, 1
    b       submit_line
line_lf:
    beq     $r27, $r0, submit_line
    or      $r27, $r0, $r0
    b       main_loop
submit_line:
    add.w   $r12, $r23, $r24
    st.b    $r0, $r12, 0
    bne     $r26, $r0, report_long
    beq     $r24, $r0, reset_line
    bl      process_line
    b       reset_line
report_long:
    li.w    $r4, MSG_LONG
    bl      puts
reset_line:
    or      $r24, $r0, $r0
    or      $r26, $r0, $r0
    b       main_loop

# 创新扩展：后台更新秒表。32位tick差按无符号模减法处理原始计数器回绕。
# clobber r6..r9；保留打印、解析所用寄存器及64位累计结果。
stopwatch_update:
    beq     $r29, $r0, stopwatch_update_done
    ld.w    $r6, $r22, 0
    li.w    $r7, 0x1100
    ld.w    $r8, $r7, 0
    st.w    $r6, $r7, 0
    sub.w   $r6, $r6, $r8
    add.w   $r8, $r30, $r6
    sltu    $r9, $r8, $r30
    or      $r30, $r8, $r0
    add.w   $r31, $r31, $r9
stopwatch_update_done:
    jirl    $r0, $r1, 0

# 创新扩展：发送期间继续累计时间，防止长响应阻塞后台采样。
putchar:
    addi.w  $r3, $r3, -16
    st.w    $r1, $r3, 0
putchar_wait:
    bl      stopwatch_update
    ld.w    $r12, $r20, 8
    andi    $r13, $r12, 2
    bne     $r13, $r0, putchar_wait
    st.w    $r4, $r20, 0
    ld.w    $r1, $r3, 0
    addi.w  $r3, $r3, 16
    jirl    $r0, $r1, 0

# 创新扩展：r4为数据RAM中的NUL结尾字符串地址。
puts:
    addi.w  $r3, $r3, -16
    st.w    $r1, $r3, 0
    st.w    $r14, $r3, 4
    or      $r14, $r4, $r0
puts_loop:
    ld.bu   $r4, $r14, 0
    beq     $r4, $r0, puts_done
    bl      putchar
    addi.w  $r14, $r14, 1
    b       puts_loop
puts_done:
    ld.w    $r14, $r3, 4
    ld.w    $r1, $r3, 0
    addi.w  $r3, $r3, 16
    jirl    $r0, $r1, 0

# 创新扩展：r4数值，r5十六进制位数，输出固定宽度大写十六进制。
print_hex:
    addi.w  $r3, $r3, -16
    st.w    $r1, $r3, 0
    st.w    $r15, $r3, 4
    st.w    $r16, $r3, 8
    or      $r15, $r4, $r0
    addi.w  $r16, $r5, -1
    slli.w  $r16, $r16, 2
hex_loop:
    srl.w   $r4, $r15, $r16
    andi    $r4, $r4, 15
    li.w    $r12, 10
    bltu    $r4, $r12, hex_digit
    addi.w  $r4, $r4, 55
    b       hex_send
hex_digit:
    addi.w  $r4, $r4, 48
hex_send:
    bl      putchar
    addi.w  $r16, $r16, -4
    bge     $r16, $r0, hex_loop
    ld.w    $r16, $r3, 8
    ld.w    $r15, $r3, 4
    ld.w    $r1, $r3, 0
    addi.w  $r3, $r3, 16
    jirl    $r0, $r1, 0

# 创新扩展：r4行地址，r5关键字地址；返回r5匹配标志、r4参数地址。
# 关键字大小写不敏感，CODE参数保持原字符大小写。
match_command:
match_leading:
    ld.bu   $r7, $r4, 0
    li.w    $r8, 32
    bne     $r7, $r8, match_loop
    addi.w  $r4, $r4, 1
    b       match_leading
match_loop:
    ld.bu   $r6, $r5, 0
    beq     $r6, $r0, match_boundary
    ld.bu   $r7, $r4, 0
    li.w    $r8, 97
    bltu    $r7, $r8, match_compare
    li.w    $r8, 123
    bgeu    $r7, $r8, match_compare
    addi.w  $r7, $r7, -32
match_compare:
    bne     $r6, $r7, match_fail
    addi.w  $r4, $r4, 1
    addi.w  $r5, $r5, 1
    b       match_loop
match_boundary:
    ld.bu   $r7, $r4, 0
    beq     $r7, $r0, match_success
    li.w    $r8, 32
    bne     $r7, $r8, match_fail
match_spaces:
    addi.w  $r4, $r4, 1
    ld.bu   $r7, $r4, 0
    beq     $r7, $r8, match_spaces
    b       match_success
match_success:
    li.w    $r5, 1
    jirl    $r0, $r1, 0
match_fail:
    or      $r5, $r0, $r0
    jirl    $r0, $r1, 0

# 创新扩展：解析1..r5位十六进制，可带0x前缀和尾随空格。
# 返回r4值、r5成功标志，完整校验参数，拒绝溢出和多余文本。
parse_hex:
    or      $r9, $r0, $r0
    or      $r8, $r0, $r0
    or      $r10, $r4, $r0
    ld.bu   $r7, $r10, 0
    li.w    $r11, 48
    bne     $r7, $r11, parse_loop
    ld.bu   $r7, $r10, 1
    li.w    $r11, 120
    beq     $r7, $r11, parse_prefix
    li.w    $r11, 88
    bne     $r7, $r11, parse_loop
parse_prefix:
    addi.w  $r10, $r10, 2
parse_loop:
    ld.bu   $r7, $r10, 0
    beq     $r7, $r0, parse_done
    li.w    $r11, 32
    beq     $r7, $r11, parse_spaces
    bgeu    $r8, $r5, parse_fail
    li.w    $r11, 48
    bltu    $r7, $r11, parse_fail
    li.w    $r11, 58
    bltu    $r7, $r11, parse_decimal
    li.w    $r11, 97
    bltu    $r7, $r11, parse_upper
    li.w    $r11, 103
    bgeu    $r7, $r11, parse_fail
    addi.w  $r7, $r7, -32
parse_upper:
    li.w    $r11, 65
    bltu    $r7, $r11, parse_fail
    li.w    $r11, 71
    bgeu    $r7, $r11, parse_fail
    addi.w  $r7, $r7, -55
    b       parse_accumulate
parse_decimal:
    addi.w  $r7, $r7, -48
parse_accumulate:
    slli.w  $r9, $r9, 4
    or      $r9, $r9, $r7
    addi.w  $r8, $r8, 1
    addi.w  $r10, $r10, 1
    b       parse_loop
parse_spaces:
    addi.w  $r10, $r10, 1
    ld.bu   $r7, $r10, 0
    beq     $r7, $r0, parse_done
    li.w    $r11, 32
    beq     $r7, $r11, parse_spaces
    b       parse_fail
parse_done:
    beq     $r8, $r0, parse_fail
    or      $r4, $r9, $r0
    li.w    $r5, 1
    jirl    $r0, $r1, 0
parse_fail:
    or      $r4, $r0, $r0
    or      $r5, $r0, $r0
    jirl    $r0, $r1, 0

process_line:
    addi.w  $r3, $r3, -32
    st.w    $r1, $r3, 0
    st.w    $r18, $r3, 4
    st.w    $r19, $r3, 8
    st.w    $r17, $r3, 12
    or      $r4, $r23, $r0
    li.w    $r5, CMD_HELP
    bl      match_command
    bne     $r5, $r0, command_help
    or      $r4, $r23, $r0
    li.w    $r5, CMD_CODE
    bl      match_command
    bne     $r5, $r0, command_code
    or      $r4, $r23, $r0
    li.w    $r5, CMD_LED
    bl      match_command
    bne     $r5, $r0, command_led
    or      $r4, $r23, $r0
    li.w    $r5, CMD_DISP
    bl      match_command
    bne     $r5, $r0, command_disp
    or      $r4, $r23, $r0
    li.w    $r5, CMD_SW
    bl      match_command
    bne     $r5, $r0, command_sw
    or      $r4, $r23, $r0
    li.w    $r5, CMD_TIME
    bl      match_command
    bne     $r5, $r0, command_time
    or      $r4, $r23, $r0
    li.w    $r5, CMD_START
    bl      match_command
    bne     $r5, $r0, command_start
    or      $r4, $r23, $r0
    li.w    $r5, CMD_STOP
    bl      match_command
    bne     $r5, $r0, command_stop
    or      $r4, $r23, $r0
    li.w    $r5, CMD_RESET
    bl      match_command
    bne     $r5, $r0, command_reset
    or      $r4, $r23, $r0
    li.w    $r5, CMD_STAT
    bl      match_command
    bne     $r5, $r0, command_stat
    or      $r4, $r23, $r0
    li.w    $r5, CMD_MIRROR
    bl      match_command
    bne     $r5, $r0, command_mirror
    or      $r4, $r23, $r0
    li.w    $r5, CMD_IRQ
    bl      match_command
    bne     $r5, $r0, command_irq
    # 创新扩展：单字符加回车仍可查看ASCII编码。
    li.w    $r12, 1
    bne     $r24, $r12, command_error
    or      $r4, $r23, $r0
    b       command_code
command_help:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    li.w    $r4, MSG_HELP
    bl      puts
    b       process_done
command_code:
    ld.bu   $r19, $r4, 0
    beq     $r19, $r0, command_error
    addi.w  $r18, $r4, 1
code_tail:
    ld.bu   $r12, $r18, 0
    beq     $r12, $r0, code_valid
    li.w    $r13, 32
    bne     $r12, $r13, command_error
    addi.w  $r18, $r18, 1
    b       code_tail
code_valid:
    or      $r25, $r0, $r0
    st.w    $r19, $r21, 0x50
    li.w    $r4, MSG_ASCII
    bl      puts
    or      $r4, $r19, $r0
    li.w    $r5, 2
    b       print_value
command_led:
    li.w    $r5, 4
    bl      parse_hex
    beq     $r5, $r0, command_error
    bl      irq_disable           # 创新扩展：手动LED接管前关中断，r4参数不受影响。
    or      $r25, $r0, $r0
    nor     $r12, $r4, $r0
    st.w    $r12, $r21, 0x20
    b       command_ok
command_disp:
    li.w    $r5, 2
    bl      parse_hex
    beq     $r5, $r0, command_error
    or      $r25, $r0, $r0
    st.w    $r4, $r21, 0x50
    b       command_ok
command_sw:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    ld.w    $r19, $r21, 0x60
    xori    $r19, $r19, 0xff
    andi    $r19, $r19, 0xff
    li.w    $r4, MSG_SW
    bl      puts
    or      $r4, $r19, $r0
    li.w    $r5, 2
    b       print_value
# 创新扩展：START开始/继续，运行中重复START不清零；STOP暂停；RESET清零并停止。
command_start:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    bne     $r29, $r0, command_ok
    # 创新扩展：保留64位累计值，只刷新当前tick基准，暂停期间不计时。
    ld.w    $r6, $r22, 0
    li.w    $r7, 0x1100
    st.w    $r6, $r7, 0
    li.w    $r29, 1
    b       command_ok
command_stop:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    bl      stopwatch_update
    or      $r29, $r0, $r0
    b       command_ok
command_reset:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    or      $r29, $r0, $r0
    or      $r30, $r0, $r0
    or      $r31, $r0, $r0
    li.w    $r12, 0x1100
    st.w    $r0, $r12, 0
    b       command_ok
command_time:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    bl      stopwatch_update
    # 创新扩展：先取快照，后续串口打印不会改变这次TIME的显示值。
    li.w    $r12, 0x1120
    st.w    $r30, $r12, 0
    st.w    $r31, $r12, 4
    or      $r4, $r30, $r0
    or      $r5, $r31, $r0
    li.w    $r6, 50000000
    bl      divide_u64_u32
    or      $r18, $r4, $r0
    or      $r17, $r5, $r0
    li.w    $r12, 50000
    div.wu  $r19, $r6, $r12
    li.w    $r4, MSG_TIME
    bl      puts
    or      $r4, $r18, $r0
    or      $r5, $r17, $r0
    bl      print_decimal_u64
    li.w    $r4, 46
    bl      putchar
    li.w    $r12, 100
    div.wu  $r18, $r19, $r12
    mod.wu  $r19, $r19, $r12
    addi.w  $r4, $r18, 48
    bl      putchar
    li.w    $r12, 10
    div.wu  $r18, $r19, $r12
    mod.wu  $r19, $r19, $r12
    addi.w  $r4, $r18, 48
    bl      putchar
    addi.w  $r4, $r19, 48
    bl      putchar
    li.w    $r4, MSG_SECONDS
    bl      puts
    b       process_done
command_stat:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    ld.w    $r19, $r20, 8
    # The course SRAM/MMIO path is synchronous.  Keep two independent issue
    # slots before the nested call so the status read reaches WB first.
    or      $r19, $r19, $r0
    li.w    $r4, MSG_STAT
    bl      puts
    or      $r4, $r19, $r0
    li.w    $r5, 8
    b       print_value
print_value:
    bl      print_hex
    li.w    $r4, MSG_EOL
    bl      puts
    b       process_done
command_mirror:
    or      $r18, $r4, $r0
    li.w    $r5, ARG_ON
    bl      match_command
    beq     $r5, $r0, mirror_try_off
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    bl      irq_disable           # 创新扩展：MIRROR与中断闪灯互斥。
    li.w    $r25, 1
    li.w    $r28, 256
    b       command_ok
mirror_try_off:
    or      $r4, $r18, $r0
    li.w    $r5, ARG_OFF
    bl      match_command
    beq     $r5, $r0, command_error
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    or      $r25, $r0, $r0
    b       command_ok
# 创新扩展：IRQ ON/OFF/COUNT只由CPU汇编解析，不增加CPU指令。
command_irq:
    or      $r18, $r4, $r0
    li.w    $r5, ARG_ON
    bl      match_command
    bne     $r5, $r0, irq_on
    or      $r4, $r18, $r0
    li.w    $r5, ARG_OFF
    bl      match_command
    bne     $r5, $r0, irq_off
    or      $r4, $r18, $r0
    li.w    $r5, ARG_COUNT
    bl      match_command
    beq     $r5, $r0, command_error
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    li.w    $r12, 0x1160
    ld.w    $r19, $r12, 0       # 单字读取次数快照，打印过程中允许继续中断。
    # As with STAT, let the synchronous data read retire before calling puts.
    or      $r19, $r19, $r0
    li.w    $r4, MSG_IRQ_COUNT
    bl      puts
    or      $r4, $r19, $r0
    li.w    $r5, 8
    b       print_value
irq_on:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    csrrd   $r12, 0x41
    # CSR reads write back through the same pipeline as loads.  Keep the
    # following idempotence branch from consuming its prior register value.
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    andi    $r12, $r12, 1
    bne     $r12, $r0, command_ok # 已开启时幂等，不重置次数或相位。
    # Inline the atomic disable sequence here.  This avoids a branch-after-
    # branch call/return boundary in the educational five-stage core.
    li.w    $r12, 4
    csrxchg $r0, $r12, 0x00
    csrwr   $r0, 0x41
    li.w    $r12, 1
    csrwr   $r12, 0x44
    or      $r25, $r0, $r0
    li.w    $r12, 0x1160
    st.w    $r0, $r12, 0
    st.w    $r0, $r12, 4
    li.w    $r12, -1
    st.w    $r12, $r21, 0x20    # 初始全灭，每次中断切换全部16个LED。
    li.w    $r12, 0xbfafff20
    ld.w    $r13, $r12, 0       # 使用已有SIMU_FLAG，不增加硬件接口。
    # Retire the synchronous MMIO read before selecting the timer preset.
    or      $r13, $r13, $r0
    or      $r13, $r13, $r0
    li.w    $r12, 1562503       # CPU 3.125MHz，初值1562500，周期模式+使能。
    beq     $r13, $r0, irq_configure
    li.w    $r12, 25003         # 快速仿真50MHz：25000拍，约0.5ms，便于自检。
irq_configure:
    csrwr   $r12, 0x41         # TCFG；当前CPU计数周期为初值+1拍。
    li.w    $r12, 4
    li.w    $r13, 4
    csrxchg $r13, $r12, 0x00   # 仅置CRMD.IE，保留其他控制位。
    b       command_ok
irq_off:
    ld.bu   $r12, $r4, 0
    bne     $r12, $r0, command_error
    bl      irq_disable        # 停止后保留次数和LED最后状态。
    b       command_ok

# 创新扩展：原子停止闪灯。先关全局IE，再停定时器、清挂起位。
# 仅破坏r12；用于IRQ OFF、有效LED命令和MIRROR ON。
irq_disable:
    li.w    $r12, 4
    csrxchg $r0, $r12, 0x00
    csrwr   $r0, 0x41
    li.w    $r12, 1
    csrwr   $r12, 0x44
    jirl    $r0, $r1, 0

command_ok:
    li.w    $r4, MSG_OK
    bl      puts
    b       process_done
command_error:
    li.w    $r4, MSG_ERR
    bl      puts
process_done:
    ld.w    $r17, $r3, 12
    ld.w    $r19, $r3, 8
    ld.w    $r18, $r3, 4
    ld.w    $r1, $r3, 0
    addi.w  $r3, $r3, 32
    jirl    $r0, $r1, 0

# 创新扩展：64位无符号数除以小于2^31的32位数；这里用于50MHz和十进制转换。
# 输入r5:r4、r6除数；输出r5:r4商、r6余数；64次移位减法，不修改CPU。
divide_u64_u32:
    or      $r7, $r4, $r0
    or      $r8, $r5, $r0
    or      $r9, $r0, $r0
    li.w    $r10, 64
divide_u64_loop:
    srli.w  $r11, $r8, 31
    slli.w  $r9, $r9, 1
    or      $r9, $r9, $r11
    srli.w  $r12, $r7, 31
    slli.w  $r8, $r8, 1
    or      $r8, $r8, $r12
    slli.w  $r7, $r7, 1
    bltu    $r9, $r6, divide_u64_next
    sub.w   $r9, $r9, $r6
    ori     $r7, $r7, 1
divide_u64_next:
    addi.w  $r10, $r10, -1
    bne     $r10, $r0, divide_u64_loop
    or      $r4, $r7, $r0
    or      $r5, $r8, $r0
    or      $r6, $r9, $r0
    jirl    $r0, $r1, 0

# 创新扩展：64位秒数转十进制，反向存入数据RAM，再由CPU逐字节发送。
print_decimal_u64:
    addi.w  $r3, $r3, -32
    st.w    $r1, $r3, 0
    st.w    $r14, $r3, 4
    st.w    $r15, $r3, 8
    st.w    $r16, $r3, 12
    st.w    $r17, $r3, 16
    li.w    $r14, 0x115f
    or      $r15, $r0, $r0
    or      $r16, $r4, $r0
    or      $r17, $r5, $r0
decimal_collect:
    or      $r4, $r16, $r0
    or      $r5, $r17, $r0
    li.w    $r6, 10
    bl      divide_u64_u32
    addi.w  $r6, $r6, 48
    st.b    $r6, $r14, 0
    addi.w  $r14, $r14, -1
    addi.w  $r15, $r15, 1
    or      $r16, $r4, $r0
    or      $r17, $r5, $r0
    or      $r12, $r16, $r17
    bne     $r12, $r0, decimal_collect
decimal_send:
    addi.w  $r14, $r14, 1
    ld.bu   $r4, $r14, 0
    bl      putchar
    addi.w  $r15, $r15, -1
    bne     $r15, $r0, decimal_send
    ld.w    $r17, $r3, 16
    ld.w    $r16, $r3, 12
    ld.w    $r15, $r3, 8
    ld.w    $r14, $r3, 4
    ld.w    $r1, $r3, 0
    addi.w  $r3, $r3, 32
    jirl    $r0, $r1, 0

# 创新扩展：真正的中断处理程序，放在指令RAM 0x1c001000。
# 硬件保存ERA/PRMD并关IE；软件保存所有使用的通用寄存器，不调用串口函数。
    .section .text.irq, "ax"
    .balign 64
irq_handler:
    addi.w  $r3, $r3, -32
    st.w    $r12, $r3, 0
    st.w    $r13, $r3, 4
    st.w    $r14, $r3, 8
    st.w    $r15, $r3, 12
    # This firmware enables only ECFG.LIE[11], so every accepted asynchronous
    # interrupt is the timer source.  Handle it directly instead of using a
    # CSR readback on the critical entry path; this also makes the handler
    # independent of implementation-specific CSR read forwarding latency.
    li.w    $r12, 1
    csrwr   $r12, 0x44          # TICLR清除定时器中断，避免返回后立即反复进入。
    li.w    $r12, 0x1160
    # Prime the course registered data-RAM read port.  The baseline pipeline
    # consumes the preceding read response, so the second same-address load
    # below is the architectural counter value.
    ld.w    $r13, $r12, 0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    ld.w    $r13, $r12, 0
    # The course SRAM read is synchronous; separate load and consumer in the
    # asynchronous handler just as the foreground command paths do.
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    ld.w    $r13, $r12, 0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    addi.w  $r13, $r13, 1
    st.w    $r13, $r12, 0
    # Prime the read port before consuming the LED phase as well.
    ld.w    $r14, $r12, 4
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    ld.w    $r14, $r12, 4
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    xori    $r14, $r14, 1
    st.w    $r14, $r12, 4
    sub.w   $r14, $r0, $r14
    nor     $r14, $r14, $r0    # phase=1 -> 本地0(网页全亮)，phase=0 -> 本地全1。
    li.w    $r15, 0xbfaff020
    st.w    $r14, $r15, 0
    ld.w    $r15, $r3, 12
    ld.w    $r14, $r3, 8
    ld.w    $r13, $r3, 4
    ld.w    $r12, $r3, 0
    addi.w  $r3, $r3, 32
    # Allow the final load restores to reach WB before ERTN is accepted.
    or      $r0, $r0, $r0
    or      $r0, $r0, $r0
    ertn                       # 恢复CRMD并返回ERA，继续被打断的指令。
irq_unexpected:
    csrwr   $r0, 0x41         # 非预期同步异常保留现场停住，不能当定时器返回。
irq_fault:
    b       irq_fault
