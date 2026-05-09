
/////////////////////////MASTER CODE/////////////////////////

module i2c_master (
    input clk, reset, newd,
    input [6:0] addr,
    input read,
    inout sda,
    output scl,
    input [7:0] din,
    output [7:0] dout,
    output reg busy, ack_err, done
);

    parameter sys_freq = 40000000; //40MHZ
    parameter i2c_freq = 100000; //100KHz

    parameter clk_count4 = (sys_freq/i2c_freq); // 400
    parameter clk_count = (clk_count4)/4; // 100

    integer count = 0; // for slow clk
    reg [1:0] pulse = 0; // segmentation of 1 bit duration

    // COUNT LOGIC
    always @(posedge clk) begin
        if (reset) count <= 0;
        else begin
            if (busy == 0) count <= 0;
            else begin
                if (count == clk_count - 1) count <= 0;
                else count <= count + 1;
            end
        end
    end

    // PULSE LOGIC
    always @(posedge clk) begin
        if (reset) pulse <= 0;
        else begin
            if (busy == 0) pulse <= 0;
            else begin
                if (count == clk_count - 1) begin
                    if (pulse == 3) pulse <= 0;
                    else pulse <= pulse + 1;
                end
                else pulse <= pulse;
            end
        end
    end
    
    parameter IDLE = 0, START = 1, WRITE_ADDR = 2, ACK_1 = 3, WRITE_DATA = 4,
                READ_DATA = 5, ACK_2 = 6, MASTER_ACK = 7, STOP = 8;

    reg [3:0] state;
    reg scl_t = 0;
    reg sda_t = 0;

    reg [3:0] bit_count = 0;
    reg [7:0] data_addr = 0, data_tx = 0;
    reg r_ack;
    reg [7:0] rx_data = 0;
    reg sda_en;

    always @(posedge clk) begin
        if (reset) begin
            bit_count <= 0;
            data_addr <= 0;
            data_tx <= 0;
            scl_t <= 1;
            sda_t <= 1;
            busy <= 0;
            ack_err <= 0;
            done <= 0;
            rx_data <= 0;
            state <= IDLE;
        end
        else begin
            case (state)
                IDLE : begin
                    done <= 0;
                    if (newd) begin
                        state <= START;
                        data_addr <= {addr, read};
                        data_tx <= din;
                        busy <= 1;
                        ack_err <= 0;
                        scl_t <= 1;
                    end
                    else begin
                        state <= IDLE;
                        data_addr <= 0;
                        data_tx <= 0;
                        busy <= 0;
                        ack_err <= 0;
                    end
                end

                //////////////////////////////////////

                START : begin
                    sda_en <= 1; 
                    case (pulse)
                        0 : begin scl_t = 1; sda_t = 1; end
                        1 : begin scl_t = 1; sda_t = 1; end
                        2 : begin scl_t = 1; sda_t = 0; end
                        3 : begin scl_t = 1; sda_t = 0; end
                    endcase

                    state <= (count == clk_count - 1 & pulse == 3) ? WRITE_ADDR : START; // possible bug
                end

                //////////////////////////////////////

                WRITE_ADDR : begin
                    sda_en <= 1;
                    if (bit_count <= 7) begin
                        case (pulse)
                            0 : begin scl_t = 0; sda_t = 0; end
                            1 : begin scl_t = 0; sda_t = data_addr[7-bit_count]; end
                            2 : begin scl_t = 1; end
                            3 : begin scl_t = 1; end
                        endcase

                        if (count == clk_count - 1 & pulse == 3) begin
                            state <= WRITE_ADDR;
                            bit_count <= bit_count + 1;
                            scl_t <= 0;
                        end
                        else begin
                            state <= WRITE_ADDR;
                            bit_count <= bit_count;
                        end
                    end

                    else begin
                        state <= ACK_1;
                        scl_t <= 0;
                        sda_en <= 0;
                        bit_count <= 0;
                    end
                end

                //////////////////////////////////////

                ACK_1 : begin
                    sda_en <= 0;
                    case (pulse)
                        0 : begin scl_t <= 0; sda_t <= 0; end
                        1 : begin scl_t <= 0; sda_t <= 0; r_ack <= sda; end 
                        2 : begin scl_t <= 0; end
                        3 : begin scl_t <= 0; end
                    endcase

                    if (count == clk_count - 1 & pulse == 3) begin
                        if (r_ack == 0 & data_addr[0] == 0) begin
                            state <= WRITE_DATA;
                            sda_en <= 1;
                            sda_t <= 0;
                        end
                        else if (r_ack == 0 & data_addr[0] == 1) begin
                            state <= READ_DATA;
                            sda_en <= 0;
                            sda_t <= 0;
                        end
                        else begin
                            state <= STOP;
                            sda_en <= 1;
                            ack_err <= 1;
                        end 
                    end
                    else begin
                        state <= ACK_1;
                    end
                end

                //////////////////////////////////////

                WRITE_DATA : begin
                    if (bit_count <= 7) begin
                        
                        sda_en <= 1;
                        case (pulse)
                            0 : begin scl_t <= 0; sda_t <= 0; end
                            1 : begin scl_t <= 0; sda_t <= data_tx[7-bit_count]; end
                            2 : begin scl_t <= 1; end
                            3 : begin scl_t <= 1; end
                        endcase

                        if (count == clk_count - 1 & pulse == 3) begin
                            state <= WRITE_DATA;
                            bit_count <= bit_count + 1;
                            scl_t <= 0;
                        end
                        else begin
                            state <= WRITE_DATA;
                            bit_count <= bit_count;
                        end
                    end
                    else begin
                        state <= ACK_2;
                        sda_en <= 0;
                        scl_t <= 0;
                        bit_count <= 0; 
                    end
                end

                //////////////////////////////////////

                READ_DATA : begin
                    sda_en <= 0;
                    if (bit_count <= 7) begin
                        case (pulse)
                            0 : begin scl_t <= 0; sda_t <= 0; end
                            1 : begin scl_t <= 0; end
                            2 : begin 
                                scl_t <= 1; 
                                rx_data <= (pulse == 2 & count == 0) ? {rx_data[6:0],sda} : rx_data;
                            end
                            3 : begin scl_t <= 1; end
                        endcase

                        if (count == clk_count - 1 & pulse == 3) begin
                            bit_count <= bit_count + 1;
                            state <= READ_DATA;
                            scl_t <= 0;
                        end
                        else begin
                            state <= READ_DATA;
                            bit_count <= bit_count;
                        end
                    end
                    else begin
                        bit_count <= 0;
                        sda_en <= 1;
                        state <= MASTER_ACK;
                    end
                end

                //////////////////////////////////////

                MASTER_ACK : begin
                    sda_en <= 1;
                    case (pulse)
                        0 : begin scl_t <= 0; sda_t <= 1; end // possible bug
                        1 : begin scl_t <= 0; sda_t <= 1; end 
                        2 : begin scl_t <= 1; sda_t <= 1; end
                        3 : begin scl_t <= 1; sda_t <= 1; end  
                    endcase

                    if (count == clk_count - 1 & pulse == 3) begin
                        state <= STOP;
                        sda_t <= 0;
                        sda_en <= 1;    
                    end
                    else begin
                        state <= MASTER_ACK;
                    end
                end

                //////////////////////////////////////

                ACK_2 : begin
                    sda_en <= 0;
                    case (pulse)
                        0 : begin scl_t <= 0; sda_t <= 0; end
                        1 : begin scl_t <= 0; sda_t <= 0; end
                        2 : begin scl_t <= 1; sda_t <= 0; r_ack <= 0; end
                        3 : begin scl_t <= 1; end 
                    endcase

                    if (count == clk_count - 1 & pulse == 3) begin // possibel bug
                        if (r_ack == 0) begin
                            state <= STOP;
                            ack_err <= 0;
                            sda_en <= 1;
                            sda_t <= 0;
                        end
                        else begin
                            state <= STOP;
                            ack_err <= 1;
                        end
                    end
                    else begin
                        state <= ACK_2;
                    end
                end

                //////////////////////////////////////

                STOP : begin
                    sda_en <= 1;
                    case (pulse)
                        0 : begin scl_t <= 1; sda_t <= 0; end
                        1 : begin scl_t <= 1; sda_t <= 0; end
                        2 : begin scl_t <= 1; sda_t <= 1; end
                        3 : begin scl_t <= 1; sda_t <= 1; end
                    endcase

                    if (count == clk_count -1 & pulse == 3) begin
                        state <= IDLE;
                        scl_t <= 0;
                        sda_en <= 1;
                        busy <= 0;
                        done <= 1; // done is only high here
                    end
                    else begin
                        state <= STOP;
                        done <= 0;
                    end
                end

                //////////////////////////////////////

                default: state <= IDLE;
            endcase
        end
    end  

    assign sda = (sda_en == 1) ? (sda_t == 0) ? 1'b0 : 1'b1 : 1'bz;
    assign scl = scl_t;
    assign dout = rx_data;
endmodule











/////////////////////////SLAVE CODE////////////////////////










module i2c_slave (
    input clk, reset, scl,
    inout sda, 
    output reg ack_err, done
);
    parameter sys_freq = 40000000; // 40MHz
    parameter i2c_freq = 100000; // 100KHz

    parameter clk_count4 = (sys_freq/i2c_freq);
    parameter clk_count = clk_count4/4;

    integer count;
    reg [1:0] pulse;
    reg busy;

    // COUNT LOGIC
    always @(posedge clk) begin
        if (reset) count <= 0;
        else begin
            if (busy == 0) count <= 2;
            else begin
                if (count == clk_count - 1) count <= 0;
                else count <= count + 1;
            end
        end
    end

    // PULSE LOGIC
    always @(posedge clk) begin
        if (reset) pulse <= 0;
        else begin
            if (busy == 0) pulse <= 2;
            else begin
                if (count == clk_count - 1) begin
                    if (pulse == 3) pulse <= 0;
                    else pulse <= pulse + 1;
                end
                else pulse <= pulse;
            end
        end
    end

    integer i;
    reg [3:0] state;
    reg [7:0] mem [127:0];
    reg [3:0] bit_count = 0;
    reg [7:0] din;
    reg [7:0] dout;
    reg [6:0] addr;
    reg [7:0] r_addr;
    reg r_ack;
    reg r_mem = 0;
    reg sda_t;
    reg scl_t;
    reg sda_en;

    always @(posedge clk) begin
        if (reset) begin
            for (i=0; i<128; i++) begin
                mem[i] = i;
            end
            dout <= 8'b0;
        end
        else begin
            if (r_addr[0]) begin
                dout <= mem[addr];
            end
            else begin
                mem[addr] <= din;
            end
        end
    end

    parameter IDLE = 0, READ_ADDR = 1, SEND_ACK1 = 2, SEND_DATA = 3, MASTER_ACK = 4,
                RECEIVE_DATA = 5, SEND_ACK2 = 6, WAIT_P = 7, DETECT_STOP = 8;

    always @(posedge clk) begin
        scl_t <= scl;
    end

    always @(posedge clk) begin
        if (reset) begin
            bit_count <= 0;
            state <= IDLE;
            sda_en <= 0;
            sda_t <= 0;
            r_addr <= 8'b0;
            addr <= 0;
            busy <= 0;
            done <= 0;
            ack_err <= 0;
            din <= 0;
        end

        else begin
            case (state)
            //////////////////MAIN STATE LOGIC////////////////////////
                IDLE : begin
                    done <= 0;
                    if (sda == 0 & scl == 1) begin
                        busy <= 1;
                        state <= WAIT_P;
                    end
                    else state <= IDLE;
                end

                //////////////////////////////////////

                WAIT_P : begin
                    if (pulse == 3 & count == clk_count - 1) begin
                        state <= READ_ADDR;
                    end
                    else state <= WAIT_P;
                end

                //////////////////////////////////////

                READ_ADDR : begin
                    sda_en <= 0;
                    if (bit_count <= 7) begin
                        case (pulse)
                            0 : begin  end
                            1 : begin  end
                            2 : begin 
                                r_addr <= (pulse == 2 & count == 0) ? {r_addr[6:0], sda} : r_addr; 
                                end
                            3 : begin  end
                        endcase

                        if (count == clk_count - 1 & pulse == 3) begin
                            state <= READ_ADDR;
                            bit_count <= bit_count + 1;
                        end
                        else begin
                            state <= READ_ADDR;
                            bit_count <= bit_count;
                        end
                    end

                    else begin
                        state <= SEND_ACK1;
                        bit_count <= 0;
                        addr <= r_addr[7:1];
                        sda_en <= 1;
                    end
                end

                //////////////////////////////////////

                SEND_ACK1 : begin
                    case (pulse)
                        0 : begin sda_t <= 1'b0; end
                        1 : begin  end
                        2 : begin  end
                        3 : begin  end
                    endcase
                
                    if (pulse == 3 & count == clk_count - 1) begin
                        if (r_addr[0] == 1) begin
                            state <= SEND_DATA;
                        end
                        else begin
                            state <= RECEIVE_DATA;
                        end
                    end
                    else begin
                        state <= SEND_ACK1;
                    end
                end

                //////////////////////////////////////

                RECEIVE_DATA : begin
                    sda_en <= 0;
                    if (bit_count <= 7) begin
                        case (pulse)
                            0 : begin end
                            1 : begin end
                            2 : begin 
                                din <= (pulse == 2 & count == 0) ? {din[6:0], sda} : din; 
                                end
                            3 : begin end
                        endcase

                        if (pulse == 3 & count == clk_count - 1) begin
                            state <= RECEIVE_DATA;
                            bit_count <= bit_count + 1;
                        end
                        else begin
                            state <= RECEIVE_DATA;
                            bit_count <= bit_count;
                        end
                    end
                    
                    else begin
                        state <= SEND_ACK2;
                        bit_count <= 0;
                        sda_en <= 1;// writing to memory, mem[addr] <= din;
                    end
                end

                //////////////////////////////////////

                SEND_ACK2 : begin
                    case (pulse)
                        0 : begin sda_t <= 0; end
                        1 : begin end
                        2 : begin end
                        3 : begin end
                    endcase

                    if (pulse == 3 & count == clk_count - 1) begin
                        state <= DETECT_STOP;
                        sda_en <= 0;
                    end
                    else begin
                        state <= SEND_ACK2;
                    end
                end

                //////////////////////////////////////

                SEND_DATA : begin
                    sda_en <= 1;
                    if (bit_count <= 7) begin
                        case (pulse)
                            0 : begin end
                            1 : begin sda_t <= dout[7-bit_count]; end
                            2 : begin end
                            3 : begin end
                        endcase
                    
                        if (pulse == 3 & count == clk_count - 1) begin
                            state <= SEND_DATA;
                            bit_count <= bit_count + 1;
                        end
                        else begin
                            state <= SEND_DATA;
                            bit_count <= bit_count;
                        end
                    end

                    else begin
                        state <= MASTER_ACK;
                        bit_count <= 0;
                        sda_en <= 0;
                    end
                end

                //////////////////////////////////////

                MASTER_ACK : begin
                    case (pulse)
                        0 : begin end
                        1 : begin end
                        2 : begin r_ack <= sda; end
                        3 : begin end
                    endcase

                    if (count == clk_count - 1 & pulse == 3) begin
                        if (r_ack == 1) begin
                            state <= DETECT_STOP;
                            ack_err <= 0;
                            sda_en <= 0;
                        end
                        else begin
                            state <= DETECT_STOP;
                            ack_err <= 1;
                            sda_en <= 0;
                        end
                    end
                    else begin
                        state <= MASTER_ACK;
                    end
                end

                //////////////////////////////////////

                DETECT_STOP : begin
                    if (pulse == 2 & count == clk_count - 1) begin
                        state <= IDLE;
                        done <= 1;
                        busy <= 0;
                    end
                    else begin
                        state <= DETECT_STOP;
                    end
                end

                //////////////////////////////////////

                default: state <= IDLE;
            endcase
        end
    end

    assign sda = (sda_en == 1) ? (sda_t == 1) ? 1'b1 : 1'b0 : 1'bz;

endmodule











/////////////////////////TOP I2C MODULE////////////////////////










module i2c_top(
    input clk, reset, newd, read,
    input [6:0] addr,
    input [7:0] din,
    output [7:0] dout,
    output busy,ack_err,
    output done
);

    wire sda, scl;
    wire ack_err_s, ack_err_m;

    i2c_master MASTER(clk, reset, newd, addr, read, 
                    sda, scl, din, dout, busy, ack_err_m, done);

    i2c_slave SLAVE(clk, reset, scl, sda, ack_err_s, done);

    assign ack_err = ack_err_m | ack_err_s;
endmodule











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