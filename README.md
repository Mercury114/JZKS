# JZKS: LA32 Course Processor and Extensions

This branch keeps the course fifth-chapter five-stage processor and all
extension assets in separate, reviewable trees. No branch is overwritten.

- `Exp9_源码_v文件/`: course-oriented Exp8/Exp9 five-stage processor sources and
  the original testbench/materials.
- `Cache/`: integrated I-Cache, D-Cache, memory arbiter, SRAM bridge, cache-aware
  five-stage CPU and standalone/system regression harnesses.
- `D-cache/`: original independent D-Cache plus write-back/write-allocate work,
  its Vivado project and archived test artifacts.
- `innovation_uart/`: UART command-console extension, firmware and simulation
  assets.
- `PIPELINE_CACHE_UART.md`: integration notes for the course pipeline, cache and
  UART work.

## Verification status

Checked-in historical logs are reference material only. The current cache
integration has a fresh full Icarus regression record in
`Cache/docs/verification-results.json`: it covers the D-Cache and I-Cache
units, cache subsystem, MMIO bridge, CPU exception/interrupt coverage,
system-level trace equivalence, teacher Ex4--Ex9, and Exp9 under 1/2/4-way
and no-cache configurations. UART console, stopwatch and timer-IRQ regressions on the course five-stage SoC
now pass in both fast and hardware-clock modes; see
`innovation_uart/docs/VERIFICATION.md` and `TIMER_IRQ.md`. The UART bitstream now also passes synthesized board-startup and routed-timing checks;
FPGA/platform retesting is pending. Hardware UART builds use `vivado/console_build_uart_board/`;
source-level simulation projects use `vivado/console_build_uart/`.
