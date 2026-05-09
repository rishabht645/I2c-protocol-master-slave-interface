/////////////////////////TOP MODULE TESTBENCH////////////////////////


module i2c_top_tb;
 
    reg clk = 0, rst = 0, newd = 0, op;
    reg stretch = 0;
    reg [6:0] addr;
    reg [7:0] din;
    wire [7:0] dout;
    wire busy, ack_err;
    wire done;

    i2c_top TOP (clk, rst, newd, op, stretch, addr, din, dout, busy, ack_err, done);
    
    always #5 clk = ~clk;
    
    initial begin
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        
        addr = 7'd8;
        din  = 8'b10011101;
        op = 0;
        stretch = 0;
        @(posedge clk);
        newd = 1;
        repeat(5) @(posedge clk);
        newd = 0;
        @(posedge TOP.MASTER.done);
        $display("[WR] din : %0d addr: %0d, mem[%0d] : %0d",
            din, TOP.SLAVE.addr, TOP.SLAVE.addr, TOP.SLAVE.mem[addr]);
        @(posedge clk);
        
        addr = 7'd4;
        din  = 8'b10001001;
        op = 0;
        stretch = 1;
        @(posedge clk);
        newd = 1;
        wait(TOP.MASTER.state == 3);
        newd = 0;
        repeat(1200) @(posedge clk);
        stretch = 0;
        @(posedge TOP.MASTER.done);
        $display("[WR] din : %0d addr: %0d, mem[%0d] : %0d",
            din, TOP.SLAVE.addr, TOP.SLAVE.addr, TOP.SLAVE.mem[addr]);
        $display(" ");
        $display("mem[4] : %0d, mem[9] : %0d", TOP.SLAVE.mem[4], TOP.SLAVE.mem[9]);
        $finish;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
    
endmodule
