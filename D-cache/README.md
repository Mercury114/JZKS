# D-Cache Extension

This directory contains the four-way write-back/write-allocate D-Cache, its
line-protocol adapter, an independent Vivado regression, and the design note.

## Contents

- `rtl/dcache.v`: cache core with dirty/LRU, byte strobes, refill and writeback.
- `rtl/dcache_sram_adapter.v`: single-word SRAM request to four-beat line adapter.
- `tb/dcache_tb.v`: standalone regression testbench.
- `build/dcache_extension.xpr`: Vivado 2023.2 project.
- `docs/DCache_写入机制技术文档.md`: design and verification details.

The standalone regression reports:

```text
PASS D-Cache writeback/write-allocate/byte-enable/LRU/control regression
```

The adapter is kept as an optional integration block so the original school
SRAM timing remains unchanged until a board-level BRAM/AXI backend is selected.
