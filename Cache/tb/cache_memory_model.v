`timescale 1ns / 1ps

// 测试用独立内存：可固定延迟，也可给请求/返回加入可复现的空拍。
// 写在完成时修改内存；因此能检查仲裁器没有把接受误当成写完成。
module cache_memory_model #(
    parameter LATENCY = 5,
    parameter JITTER = 1
)(
    input wire clk,
    input wire resetn,
    input wire mem_valid,
    input wire mem_write,
    input wire [3:0] mem_wstrb,
    input wire [31:0] mem_addr,
    input wire [31:0] mem_wdata,
    output wire mem_ready,
    output reg mem_rvalid,
    output reg [31:0] mem_rdata,
    output reg [31:0] mmio_value,
    output reg [31:0] mmio_writes,
    output reg [31:0] read_count,
    output reg [31:0] write_count
);
    reg [31:0] inst [0:262143];
    reg [31:0] data [0:65535];
    reg [31:0] lfsr;
    reg pending;
    reg write_r;
    reg [3:0] strobe_r;
    reg [31:0] addr_r;
    reg [31:0] data_r;
    reg [1023:0] filename;
    integer delay_left;
    integer i;
    integer lane;
    integer rom_words;
    reg [31:0] value;
    initial begin
        for (i = 0; i < 262144; i = i + 1) inst[i] = 32'h02800000;
        for (i = 0; i < 65536; i = i + 1) data[i] = 0;
        rom_words = 262144;
        if ($value$plusargs("ROM_WORDS=%d", rom_words)) begin end
        if ($value$plusargs("ROM=%s", filename)) $readmemh(filename, inst, 0, rom_words - 1);
    end
    assign mem_ready = resetn && !pending && (!JITTER || lfsr[2:0] != 3'b0);
    always @(posedge clk) begin
        if (!resetn) begin
            pending <= 0;
            mem_rvalid <= 0;
            mem_rdata <= 0;
            mmio_value <= 0;
            mmio_writes <= 0;
            read_count <= 0;
            write_count <= 0;
            lfsr <= 32'h12345678;
            delay_left <= 0;
            addr_r <= 0;
            data_r <= 0;
            strobe_r <= 0;
            write_r <= 0;
        end else begin
            lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            mem_rvalid <= 0;
            if (mem_valid && mem_ready) begin
                pending <= 1;
                addr_r <= mem_addr;
                data_r <= mem_wdata;
                strobe_r <= mem_wstrb;
                write_r <= mem_write;
                delay_left <= LATENCY + (JITTER ? lfsr[5:3] : 0);
            end
            if (pending) begin
                if (delay_left != 0) delay_left <= delay_left - 1;
                else begin
                    pending <= 0;
                    mem_rvalid <= 1;
                    if ((addr_r & 32'h1fff0000) == 32'h1faf0000) value = mmio_value;
                    else if (addr_r[31:20] == 12'h1c0) value = inst[addr_r[19:2]];
                    else value = data[addr_r[17:2]];
                    mem_rdata <= value;
                    if (write_r) begin
                        write_count <= write_count + 1;
                        for (lane = 0; lane < 4; lane = lane + 1)
                            if (strobe_r[lane]) value[lane*8 +: 8] = data_r[lane*8 +: 8];
                        if ((addr_r & 32'h1fff0000) == 32'h1faf0000) begin
                            mmio_value <= value;
                            mmio_writes <= mmio_writes + 1;
                        end else if (addr_r[31:20] == 12'h1c0) inst[addr_r[19:2]] <= value;
                        else data[addr_r[17:2]] <= value;
                    end else read_count <= read_count + 1;
                end
            end
        end
    end
endmodule
