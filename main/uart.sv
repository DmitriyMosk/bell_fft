module UART_buffer
    (
        input clk,
        input reset,
        input enable,
        input      [7:0] byte_in,
        output reg [7:0] byte_out,
        output reg ready
    );

always @(posedge clk) begin
    if (reset) begin
        byte_out <= '0;
        ready <= 0;
    end else begin
        ready <= enable;    //изменил
        if (enable) begin
            byte_out <= byte_in;
        end
    end
end
endmodule

module shift_reg_par_in_serial_out # (parameter M = 5)
    (
        input clk,
        input reset,
        input [M-1:0] bus_in,
        input set,
        input shift,
        output bit_out
    );

    reg [M-1:0] register;
    assign bit_out = register[0];

    always @(posedge clk) begin
        if (reset) begin
            register <= '0;
        end else begin
            if (set) begin
                register <= bus_in;
            end else begin
                if (shift) begin
                    register <= {1'b1, register[M-1:1]};
                end
            end
        end
    end
endmodule


module shift_reg_serial_in_par_out # (parameter M = 5)
    (
        input clk,
        input reset,
        input bit_in,
        input shift,
        output reg [M-1:0] byte_out
    );

    always @(posedge clk)
    begin
        if (reset) begin
            byte_out <= '0;
        end else begin
            if (shift) begin
                byte_out <= {bit_in, byte_out[M-1:1]};
            end
        end
    end
endmodule

module UART_reciever    (
        input reset,
        input clk,
        input bit_in,
        output [7:0] byte_out,
        output ready_out
    );

reg [5:0] clk_1;
reg [5:0] clk_2;
reg [5:0] clk_3;

logic state;
logic read;
wire shift_wire;

assign shift_wire = (clk_2 == 3);
assign ready_out = read;

shift_reg_serial_in_par_out #(.M(8)) shift_reg (
    .clk(clk), .reset(reset),
    .bit_in(bit_in), .byte_out(byte_out),
    .shift(shift_wire)
);

assign ready_out = read;

always @(posedge clk)
begin
    if (reset) begin
        clk_1 <= '0;
        clk_2 <= '0;
        clk_3 <= '0;
        read <=   0;
    end else begin
        if (bit_in == 0 || state == 1) begin
            clk_1 <= clk_1 + 1;
            if (clk_1 == 35) begin
                state <= 0;
                read <= 0;
                clk_1 <= '0;
            end else begin
                if (clk_1 == 2) begin
                    state <= 1;
                    read <= 0;
                    clk_2 <= '0;
                end else begin
                    clk_2 <= clk_2 + 1;
                    if (clk_2 == 3) begin
                        clk_2 <= '0;
                        if (clk_3 == 7) begin
                            read <= 1;
                            clk_3 <= '0;
                        end else begin
                            clk_3 <= clk_3 + 1;
                        end
                    end
                end
            end
        end
    end
end
endmodule

module UART_transmitter (
        input reset,
        input clk,
        input [7:0] byte_in,    //был входной регистр
        input enable,
        output bit_out,
        output busy,     //добавил
        output next_byte
    );


reg [2:0] cnt_2;
reg [4:0] cnt_3;

logic sw;
logic tr_next;

wire shift_wire;
wire set_wire;
wire uart_0;
// wire next_byte;


shift_reg_par_in_serial_out # ( .M(10)) par_in
    (
        .clk(clk),
        .reset(reset),
        .bus_in({1'b1, byte_in, 1'b0}),
        .set(set_wire),
        .shift(shift_wire),
        .bit_out(uart_0)
    );

assign shift_wire = (cnt_2 == 3);
assign set_wire = (enable == 1 && sw == 0);
assign bit_out = sw ? uart_0 : 1;
assign busy = sw;
assign next_byte = tr_next;

always @(posedge clk) begin
    if (reset) begin
        cnt_2 <= 0;
        cnt_3 <= 0;
        sw <= 0;
        tr_next <= 0;
    end else begin
        if (enable == 1 && sw == 0) begin
            sw <= 1;
            cnt_2 <= 0;
            tr_next <= 1;
        end
        if (sw == 1) begin
            cnt_2 <= cnt_2 + 1;
            tr_next <= 0;
            if (cnt_2 == 3) begin
                cnt_2 <= 0;
                cnt_3 <= cnt_3 + 1;
            end
            if (cnt_3 == 9) begin
                sw <= 0;
                cnt_3 <= 0;
            end
        end
    end
end

endmodule
