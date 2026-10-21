`timescale 1ns/1ps
module dcache_tb;
    reg clk=0, resetn=0; always #5 clk=~clk;
    reg valid,op; reg [7:0] index; reg [19:0] tag; reg [3:0] offset,wstrb; reg [31:0] wdata;
    wire addr_ok,data_ok; wire [31:0] rdata;
    wire rd_req; wire [2:0] rd_type; wire [31:0] rd_addr; reg rd_rdy,ret_valid,ret_last; reg [31:0] ret_data;
    wire wr_req; wire [2:0] wr_type; wire [31:0] wr_addr; wire [3:0] wr_wstrb; wire [127:0] wr_data; reg wr_rdy;
    reg ctrl_valid; reg [1:0] ctrl_op; reg [7:0] ctrl_index; reg [19:0] ctrl_tag; wire ctrl_done;
    dcache dut(.clk(clk),.resetn(resetn),.valid(valid),.op(op),.index(index),.tag(tag),.offset(offset),.wstrb(wstrb),.wdata(wdata),
        .ctrl_valid(ctrl_valid),.ctrl_op(ctrl_op),.ctrl_index(ctrl_index),.ctrl_tag(ctrl_tag),.ctrl_done(ctrl_done),
        .addr_ok(addr_ok),.data_ok(data_ok),.rdata(rdata),.rd_req(rd_req),.rd_type(rd_type),.rd_addr(rd_addr),.rd_rdy(rd_rdy),
        .ret_valid(ret_valid),.ret_last(ret_last),.ret_data(ret_data),.wr_req(wr_req),.wr_type(wr_type),.wr_addr(wr_addr),
        .wr_wstrb(wr_wstrb),.wr_data(wr_data),.wr_rdy(wr_rdy));
    reg [31:0] mem [0:131071]; reg active; reg [16:0] base; reg [1:0] beat; integer n;
    always @(*) begin rd_rdy=!active; wr_rdy=1'b1; end
    always @(posedge clk) begin
        ret_valid<=0; ret_last<=0;
        if(rd_req && rd_rdy) begin active<=1; base<=rd_addr[18:2]; beat<=0; end
        else if(active) begin ret_valid<=1; ret_last<=beat==3; ret_data<=mem[base+beat]; if(beat==3) active<=0; else beat<=beat+1'b1; end
        if(wr_req && wr_rdy) begin mem[wr_addr[18:2]]<=wr_data[31:0]; mem[wr_addr[18:2]+1]<=wr_data[63:32]; mem[wr_addr[18:2]+2]<=wr_data[95:64]; mem[wr_addr[18:2]+3]<=wr_data[127:96]; end
    end
    task automatic request(input write,input [31:0] a,input [31:0] v,input [3:0] s,output [31:0] got);
        integer t; begin
            op=write; index=a[11:4]; tag=a[31:12]; offset=a[3:0]; wdata=v; wstrb=s; valid=1; #1;
            t=0; while(!addr_ok && t<1000) begin @(posedge clk); #1; t=t+1; end
            if(t>=1000) begin $display("FAIL address handshake %h",a); $finish; end
            @(posedge clk); #1; valid=0; t=0; while(!data_ok && t<1000) begin @(posedge clk); #1; t=t+1; end
            if(t>=1000) begin $display("FAIL completion %h",a); $finish; end
            got=rdata;
        end
    endtask
    reg [31:0] got;
    initial begin
        valid=0; op=0; index=0; tag=0; offset=0; wstrb=0; wdata=0; rd_rdy=1; ret_valid=0; ret_last=0; ret_data=0; wr_rdy=1;
        ctrl_valid=0; ctrl_op=0; ctrl_index=0; ctrl_tag=0; active=0;
        for(n=0;n<131072;n=n+1) mem[n]=32'h20000000+n;
        #20 resetn=1;
        request(1,32'h00001000,32'h11223344,4'b1111,got);
        request(0,32'h00001000,0,0,got); if(got!==32'h11223344) begin $display("FAIL write allocate %h",got); $finish; end
        request(1,32'h00001001,32'h0000abcd,4'b0011,got);
        request(0,32'h00001000,0,0,got); if(got!==32'h1122abcd) begin $display("FAIL byte merge %h",got); $finish; end
        request(1,32'h00011000,32'h1,4'b1111,got); request(1,32'h00021000,32'h2,4'b1111,got); request(1,32'h00031000,32'h3,4'b1111,got); request(1,32'h00041000,32'h4,4'b1111,got);
        #1; if(mem[17'h00400]!==32'h1122abcd) begin $display("FAIL dirty victim %h",mem[17'h00400]); $finish; end
        ctrl_index=0; ctrl_tag=20'h00041; ctrl_op=2; ctrl_valid=1; while(!ctrl_done) begin @(posedge clk); #1; end ctrl_valid=0;
        #1; if(mem[17'h10400]!==32'h4) begin $display("FAIL control writeback %h",mem[17'h10400]); $finish; end
        $display("PASS D-Cache writeback/write-allocate/byte-enable/LRU/control regression"); #20 $finish;
    end
endmodule
