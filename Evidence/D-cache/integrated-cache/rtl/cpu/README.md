# Cache-aware five-stage CPU

Provenance: copied from the user's own `la-course-design/lab/mycpu_env/myCPU`
(12 Verilog files, source commit `6de28bfaf3fa0b7d55f7011616e244f2b30d98a1`), retaining IF → ID → EXE → MEM → WB stage registers,
forwarding, ALU, multiplier/divider, CSR, exceptions/ERTN, timer and interrupts.
`mycpu_top.v` is renamed to `cache_cpu.v` / `cache_cpu`. The source project and
`Exp9_源码_v文件` are unchanged. Compile this directory as its own fileset;
its historical submodule names must not be mixed with another CPU's fileset.

## External contract

All historical SRAM/debug/interrupt ports remain. `inst_sram_en` and
`data_sram_en` now mean request valid; `*_addr_ok` accepts once. The accepted
transaction completes on `*_data_ok`, including stores. Data/write mask/address
remain stable until acceptance. One outstanding fetch and one data operation
are supported, with no assumed latency. Zero-latency acceptance/response is
covered alongside random delayed responses.
Resetn clears CPU and cache/bus transaction ownership in the same reset domain.

IF has a returned-instruction buffer and tracks the accepted PC separately.
A redirect cancels unaccepted/buffered work; accepted wrong-path work must drain
before another fetch, and its response is discarded. EXE waits for actual data
completion and carries a latched response into MEM. Load forwarding stays pending
in EXE, then uses the real extended result in MEM. Stores wait until older MEM/WB
instructions have committed. Accepted transactions survive flush as drain-only
ownership, so an old response cannot complete a new instruction.

## CACOP

Instruction `[31:22]=0000011000`; code is rd, effective address is rj + signed si12.
Legal codes: 00/01 (index initialize), 08/09 (index invalidate / writeback-invalidate),
10/11 (hit invalidate / writeback-invalidate). Other codes raise INE; PLV != 0 on a
legal CACOP raises IPE. CACOP has no GPR destination and no word-alignment requirement.
It waits for older commits in ID, then asserts `cacop_valid/code/addr` until
`cacop_ready`, and waits once for `cacop_done`. WB flushes all prefetched instructions
and resumes at its PC+4. Cache operation semantics belong to the cache subsystem.
SYS_META grows by one bit (`sys_op[7]`), preserving the prior low bus fields.

## Verification

Run `python3 Cache/tests/run_cpu.py` from the group repository (Icarus required).
The self-contained helpers were copied from the user's Part 6 test generators;
no source-tree or external test resources are needed at runtime. Builds and
coverage records go under `Cache/build/cpu`.

The default regression covers 46 architectural scenarios / 528 runs with three
pseudo-random backpressure/delay seeds (both zero/delayed response modes) and reset reruns for exceptions: ALU,
load-use, byte/halfword loads/stores, multiply/divide, single-acceptance stores,
branch/exception wrong-path fetch cancellation, six CACOP codes and signed
addresses, unaligned self-modifying-code/CACOP refetch, no CACOP GPR write,
invalid codes, user privilege, CSR/ERTN, ADEF/ALE/INE/IPE/SYSCALL/BREAK, eight
hardware interrupt bits, and timer. A separate stage-level injected-flush test
checks old accepted load/CACOP response drain and immediate completion of the
first new request after cancellation. Local simulation is not FPGA/timing evidence.
