/////////////////////////TOP MODULE TESTBENCH////////////////////////



module tb;
    reg clk = 0, rst = 0, newd = 0, read;
    reg [6:0] addr;
    reg [7:0] din;
    wire [7:0] dout;
    wire busy,ack_err;
    wire done;
    integer i;

    i2c_top TOP(clk, rst, newd, read, addr, din, dout, busy, ack_err, done);

    always #5 clk <= ~clk;


    initial begin
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(40) @(posedge clk);
        //////////// write operation
        
        for(i = 0; i < 10 ; i++) begin
            newd = 1;
            read = 0;
            addr = i*i;
            din  = $random & 8'hFF;
            repeat(5) @(posedge clk);
            newd <= 1'b0;
            @(posedge done);
            $display("[WR] din : %0d addr: %0d mem[%0d] : %0d",TOP.SLAVE.din, addr, addr, TOP.SLAVE.mem[addr]);
            @(posedge clk);
        end
        $display("                   ");
        $display("                   ");
        $display("                   ");
        
        ////////////read operation
        
        for(i = 0; i < 10 ; i++) begin
            newd = 1;
            read = 1;
            addr = i*i;
            din = 0;
            repeat(5) @(posedge clk);
            newd <= 1'b0;  
            @(posedge done);
            $display("[RD] dout : %0d addr: %0d", dout, addr);
            @(posedge clk);
        end
        repeat(10) @(posedge clk);
        $finish;
    end
    
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
endmodule
