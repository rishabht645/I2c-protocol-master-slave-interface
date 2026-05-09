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
            if (r_mem) begin
                dout <= mem[addr];
            end
            else begin
                mem[addr] <= din;
            end
        end
    end

    parameter IDLE = 0, READ_ADDR = 1, SEND_ACK1 = 2, SEND_DATA = 3, MASTER_ACK = 4,
                RECEIVE_DATA = 5, SEND_ACK2 = 6, WAIT_P = 7, DETECT_STOP = 8;

    wire start;
    always @(posedge clk) begin
        scl_t <= scl;
    end
    assign start = ~scl & scl_t;

    always @(posedge clk) begin
        if (reset) begin
            bit_count <= 0;
            state <= IDLE;
            sda_en <= 0;
            sda_t <= 0;
            r_addr <= 8'b0;
            addr <= 0;
            r_mem <= 0;
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
                            r_mem <= 1;
                        end
                        else begin
                            state <= RECEIVE_DATA;
                            r_mem <= 0;
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
                        sda_en <= 1;
                        r_mem <= 0; // writing to memory, mem[addr] <= din;
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