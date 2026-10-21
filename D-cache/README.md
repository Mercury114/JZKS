# D-Cache and Write-Policy Extension

This directory preserves the original standalone D-Cache contribution from the
team split. It is intentionally retained alongside the newer `../Cache/`
subsystem, rather than being overwritten by it.

## Contents

- `rtl/dcache.v`: four-way set-associative write-back/write-allocate cache,
  including dirty tracking, LRU replacement and byte write strobes.
- `rtl/dcache_sram_adapter.v`: optional conversion from the school SRAM port to
  four-word cache-line traffic.
- `tb/dcache_tb.v`: standalone regression testbench.
- `build/`: Vivado project, wave configuration/data and archived logs.
- `DCache_写入机制技术文档.md`: design and verification note.

For the combined I-Cache/D-Cache/arbiter/CPU integration and its system-level
tests, use `../Cache/`. The two trees are kept separate because they have
different interfaces and verification harnesses.
