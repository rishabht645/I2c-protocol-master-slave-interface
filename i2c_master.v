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
    reg [7:0] rx_data;
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
                        1 : begin scl_t <= 0; sda_t <= 0; end // 0 ack coz no slave rn
                        2 : begin scl_t <= 1; sda_t <= 0; r_ack <= 0; end // change logic, when slave avl
                        3 : begin scl_t <= 1; sda_t <= 0; end
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
                            sda_t <= 1;
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
