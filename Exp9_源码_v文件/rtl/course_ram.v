// Self-contained synchronous RAM models for the course SRAM interfaces.
// Keeping these in source control avoids relying on locked 2018.3 XCI output
// products when the project is opened with Vivado 2023.2.
module inst_ram(
    input wire clka,
    input wire ena,
    input wire [3:0] wea,
    input wire [17:0] addra,
    input wire [31:0] dina,
    output reg [31:0] douta
);
    reg [31:0] mem [0:262143];
    integer i;
    initial begin
        // UART board fix: keep simulation padding out of synthesis.
        // The MIF is the sole synthesis initialization source.
        // synthesis translate_off
        for (i = 0; i < 262144; i = i + 1) mem[i] = 32'b0;
        // synthesis translate_on
        $readmemb("inst_ram.mif", mem);
    end
    always @(posedge clka) begin
        if (ena) begin
            if (wea[0]) mem[addra][7:0]   <= dina[7:0];
            if (wea[1]) mem[addra][15:8]  <= dina[15:8];
            if (wea[2]) mem[addra][23:16] <= dina[23:16];
            if (wea[3]) mem[addra][31:24] <= dina[31:24];
            douta <= mem[addra];
        end
    end
endmodule

module data_ram(
    input wire clka,
    input wire ena,
    input wire [3:0] wea,
    input wire [15:0] addra,
    input wire [31:0] dina,
    output reg [31:0] douta
);
    reg [31:0] mem [0:65535];
    integer i;
    initial begin
        // UART board fix: keep simulation padding out of synthesis.
        // The MIF is the sole synthesis initialization source.
        // synthesis translate_off
        for (i = 0; i < 65536; i = i + 1) mem[i] = 32'b0;
        // synthesis translate_on
        $readmemb("data_ram.mif", mem);
    end
    always @(posedge clka) begin
        if (ena) begin
            if (wea[0]) mem[addra][7:0]   <= dina[7:0];
            if (wea[1]) mem[addra][15:8]  <= dina[15:8];
            if (wea[2]) mem[addra][23:16] <= dina[23:16];
            if (wea[3]) mem[addra][31:24] <= dina[31:24];
            douta <= mem[addra];
        end
    end
endmodule
