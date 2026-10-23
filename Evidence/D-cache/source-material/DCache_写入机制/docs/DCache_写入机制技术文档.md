# D-Cache + Write Mechanism Technical Document

## 1. Scope

This implementation corresponds to the "D-Cache + write mechanism" assignment in Cache模块双人协作分工.md. The completed Exp9 CPU project is kept unchanged. This directory provides an independently verifiable D-Cache module for later CPU/shared-memory integration.

Implemented:
- 256 sets, 4-way set associative data cache.
- 16-byte cache line, four 32-bit words per line.
- CPU-side 32-bit read/write requests and 4-bit byte strobes.
- Read hit, write hit, completion handshake, and request holding.
- Read miss line refill.
- Write miss write-allocate: refill first, then merge the write.
- Write-back policy with dirty bits.
- Whole-line writeback for dirty victims.
- Invalid-way preference and LRU replacement when all ways are valid.
- Four 32-bit memory return beats and 128-bit whole-line writeback.

## 2. Files

rtl/cache.v: D-Cache RTL.
tb/cache_top.v: school cache verification wrapper.
tb/testbench.v: school 256-index regression test.
tb/clk_pll_stub.v: simulation-only PLL pass-through.
run_cache_sim.tcl: Vivado 2023.2 simulation script.
cache_sim.log: generated simulation log.

The supplied cache_top memory model checks refill data, writeback address, and complete writeback line contents, so the test is stronger than a simple response/no-response check.

## 3. Cache organization

The interface splits an address as follows:

tag = address[31:12], 20 bits
index = address[11:4], 8 bits, 256 sets
offset = address[3:0], 4 bits, 16-byte line

Each set has four ways. Each way stores a tag, valid bit, dirty bit, two-bit LRU age, and four 32-bit words. Age 0 is most recently used and age 3 is least recently used. A hit or refill makes the selected way age 0 and ages older valid ways. If all ways are valid, the largest age is selected.

## 4. CPU-side protocol

Inputs are valid, op, index, tag, offset, wstrb, and wdata. op=0 is read and op=1 is write. addr_ok is asserted only while the cache is idle; the requester must hold address and data until the handshake. data_ok is a completion pulse and rdata is valid for a read completion.

A read hit selects the word using offset[3:2]. A write hit merges only enabled byte lanes and sets dirty. No second CPU request is accepted while a refill or writeback is active.

## 5. Memory-side protocol

For a read miss, rd_req requests the line base address with rd_type=3'b100. After rd_rdy, memory returns four 32-bit beats, written to words 0 through 3; ret_last marks the final beat.

For a dirty victim, wr_req requests the old tag plus current index and zero offset. wr_type=3'b100, wr_wstrb=4'b1111, and wr_data is {word3,word2,word1,word0}. The victim is invalidated and its dirty bit cleared only after wr_rdy accepts the writeback.

## 6. State machine

ST_IDLE: accept a request and compare tags.
ST_WB_REQ: wait for dirty victim whole-line writeback.
ST_REFILL_REQ: wait for memory to accept a line read.
ST_REFILL_WAIT: receive four return beats.
ST_REFILL_APPLY: install tag/valid and complete the saved request.
ST_RESP: generate data_ok.

A read miss writes back a dirty victim when needed, refills the line, then returns the requested word. A write miss follows the same refill path, merges the requested bytes, and marks the new line dirty. This is write-allocate.

## 7. Byte-write behavior

merge_bytes(old, new, wstrb) follows:
wstrb[0]=1 updates bits [7:0].
wstrb[1]=1 updates bits [15:8].
wstrb[2]=1 updates bits [23:16].
wstrb[3]=1 updates bits [31:24].

Disabled lanes retain their old values. Therefore byte and halfword stores do not corrupt adjacent bytes. The school test uses wstrb=4'b0111 for the final word to verify that the highest byte remains unchanged while the lower three bytes update.

## 8. Test and result

Run with:

D:\Vivado2023\Vivado\2023.2\bin\vivado.bat -mode batch -source D:\lasttime\DCache_写入机制\run_cache_sim.tcl -log D:\lasttime\DCache_写入机制\cache_sim.log -nojournal

The regression covers first write misses, four-word line accesses, hit reads and writes, all 256 indexes, byte enables, dirty-victim writeback, replacement/LRU behavior, four-beat refill, and request handshakes.

Vivado 2023.2 compilation and XSim simulation succeeded. The log reports index 00 finished through index ff finished and ends with:

Test end!
----PASS!!!

The simulation ends at approximately 232395 ns.

## 9. Integration boundary

This directory completes the D-Cache module and write mechanism only; it does not modify the already-passing Exp9 CPU. Full-system integration still requires CPU data-port adaptation, pipeline stall/load completion handling, shared I/D memory arbitration, and uncached bypass for peripheral addresses. The module-level PASS result must not be described as a complete integrated Cache result.

