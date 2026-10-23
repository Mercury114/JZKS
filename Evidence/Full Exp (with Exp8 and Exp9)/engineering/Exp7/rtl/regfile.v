module regfile(
    input  wire        clk,
    // READ PORT 1
    input  wire [ 4:0] raddr1,
    output wire [31:0] rdata1,
    // READ PORT 2
    input  wire [ 4:0] raddr2,
    output wire [31:0] rdata2,
    // WRITE PORT
    input  wire        we,       //write enable, HIGH valid
    input  wire [ 4:0] waddr,
    input  wire [31:0] wdata
);
reg [31:0] rf[31:0];

//WRITE
always @(posedge clk) begin
    if (we) rf[waddr] <= wdata;
end

//READ OUT 1 (修改：加入写回旁路)
assign rdata1 = (raddr1==5'b0) ? 32'b0 :
                (we && raddr1==waddr) ? wdata : rf[raddr1];

//READ OUT 2 (修改：加入写回旁路)
assign rdata2 = (raddr2==5'b0) ? 32'b0 :
                (we && raddr2==waddr) ? wdata : rf[raddr2];

endmodule