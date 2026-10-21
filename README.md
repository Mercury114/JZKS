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

Checked-in historical logs are reference material only. The current branch is
validated only by commands executed after integration; see the cache test
harness under `Cache/tests/` and the course/UART test records added with their
respective runs. A feature is not considered complete merely because an old
artifact or an earlier branch reports PASS.
