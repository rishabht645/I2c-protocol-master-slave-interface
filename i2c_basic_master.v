module tb;
    reg clk =0; 
    reg rst = 0;
    reg newd = 0;
    reg [6:0] addr = 0;
    reg read = 0;
    reg [7:0] din;
    wire [7:0] dout;
    wire sda,scl;
    wire busy;
    wire ack_err;
    wire done;
    
    i2c_master dut (clk, rst, newd, addr, read ,sda, scl, din, dout, busy, ack_err, done);

    always #5 clk = ~clk;
    
    initial begin
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        newd = 1;
        read = 0;
        addr = 7'b1111000;
        din = 8'b10101010;
        @(negedge busy);
        repeat(5) @(posedge clk);
        $finish;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
endmodule
