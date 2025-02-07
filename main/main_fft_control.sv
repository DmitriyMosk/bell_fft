`ifndef main_fft_control_v
`define main_fft_control_v

`include "bel_fft_def.v"


/* улучшалка, можно было сделать enum*/
/* мкросы, которые определяю состояния FSM */
`define MAIN_FFT_CONTROL_INIT_STATE                             4'b0000     /* - состояние ожидания работы              */
`define MAIN_FFT_CONTROL_START_STATE                            4'b0001     /* - пустой так, начало работы              */
`define MAIN_FFT_CONTROL_START_WRITE_SIZE_REG_ADDR_STATE        4'b0010     /* - запись размера области памяти для fft  */
`define MAIN_FFT_CONTROL_START_WRITE_SOURCE_REG_ADDR_STATE      4'b0011     /* - запись src области памяти              */
`define MAIN_FFT_CONTROL_START_WRITE_DEST_REG_ADDR_STATE        4'b0100     /* - запись dest области памяти             */
`define MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_1_STATE   4'b0101     /* - запись коэффициентов для fft           */
`define MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_2_STATE   4'b0110     /* - запись коэффициентов для fft           */
`define MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_3_STATE   4'b0111     /* - запись коэффициентов для fft           */
`define MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_4_STATE   4'b1000     /* - запись коэффициентов для fft           */
`define MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_5_STATE   4'b1001     /* - запись коэффициентов для fft           */
`define MAIN_FFT_CONTROL_RUN_WRITE_CONTROL_REG_ADDR_STATE       4'b1010     /* - start                                  */
`define MAIN_FFT_CONTROL_RUN_READ_STATUS_REG_ADDR_STATE         4'b1011     /* - wait int_o ждем конец работы fft       */
`define MAIN_FFT_CONTROL_FINISH_STATE                           4'b1100     /* - закончили                              */
`define MAIN_FFT_CONTROL_STATE_BITS_SIZE                        4

module main_fft_control (
    i_clk               ,
    i_rst               ,

    i_start             ,   /* сингнал от мастера main_fft - начни работу                               */
    i_int               ,   /* сигнал от bel_fft_cor что закончил                                       */
    i_inverse           ,   /* сигнал от мастера main_fft - сделай обратный fft                         */

    i_fft_size          ,

    o_state             ,   /* Дебаг инфа о состояниях, нет необходимости, можно не вываливать наружу   */
    o_next_state        ,   /* Дебаг инфа о состояниях, нет необходимости, можно не вываливать наружу   */

    o_s_address         ,   /* Провода для управлением состояния bel_fft_core                           */
    i_s_readdata        ,   /* Провода для управлением состояния bel_fft_core                           */
    o_s_writedata       ,   /* Провода для управлением состояния bel_fft_core                           */
    o_s_read            ,   /* Провода для управлением состояния bel_fft_core                           */
    o_s_write           ,   /* Провода для управлением состояния bel_fft_core                           */
    o_s_byteenable      ,   /* Провода для управлением состояния bel_fft_core                           */
    i_s_waitrequest     ,   /* Провода для управлением состояния bel_fft_core                           */
    i_s_readdatavalid   ,   /* Провода для управлением состояния bel_fft_core                           */

    o_finish
);
    parameter word_width = `BEL_FFT_DWIDTH;

    input                                                   i_clk               ;
    input                                                   i_rst               ;
    input                                                   i_start             ;
    input                                                   i_int               ;
    input                                                   i_inverse           ;

    input       [`BEL_FFT_DWIDTH - 1:0]                     i_fft_size          ;

    output reg  [`MAIN_FFT_CONTROL_STATE_BITS_SIZE - 1:0]   o_state             ;
    output reg  [`MAIN_FFT_CONTROL_STATE_BITS_SIZE - 1:0]   o_next_state        ;

    output reg  [`BEL_FFT_SIF_AWIDTH - 1:0]                 o_s_address         ;
    input  wire [`BEL_FFT_DWIDTH - 1:0]                     i_s_readdata        ;
    output reg  [`BEL_FFT_DWIDTH - 1:0]                     o_s_writedata       ;
    output reg                                              o_s_read            ;
    output reg                                              o_s_write           ;
    output reg  [`BEL_FFT_BCNT - 1:0]                       o_s_byteenable      ;
    input  wire                                             i_s_waitrequest     ;
    input  wire                                             i_s_readdatavalid   ;

    output reg                                              o_finish            ;

    reg wait_request;

    /* Блок для перехода в новое состояние */
    always @ (posedge i_clk or posedge i_rst) begin
        if (i_rst == 1'b1) begin
            o_state <= `MAIN_FFT_CONTROL_INIT_STATE;
        end else begin
            o_state <= o_next_state;
        end
    end

/* Макрос чтобы заменить большое кол-во copy-paste. */
/* Его основная суть в том, что он в нужный адресс  */
/* Нужную информацию управления.                    */
`define WRITE_REGISTER(state, next_state, addr, data)   \
            (state): begin                              \
                if (!wait_request                       \
                    && next_state != o_next_state) begin\
                    o_s_address     <= (addr);          \
                    o_s_writedata   <= (data);          \
                    o_s_write       <= 1'b1;            \
                    o_s_byteenable  <= 4'b1111;         \
                    wait_request    <= 1'b1;            \
                end else begin                          \
                    o_s_address     <= '0;              \
                    o_s_writedata   <= '0;              \
                    o_s_write       <= '0;              \
                    o_s_byteenable  <= '0;              \
                    wait_request    <= '0;              \
                    o_next_state <= (next_state);       \
                end                                     \
            end

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst == 1'b1) begin
            o_next_state        <= `MAIN_FFT_CONTROL_INIT_STATE;
            o_s_address         <= '0;
            o_s_writedata       <= '0;
            o_s_read            <= '0;
            o_s_write           <= '0;
            o_s_byteenable      <= '0;
            wait_request        <= '0;
            o_finish            <= 0;
        end else begin
            case (o_state)
                `MAIN_FFT_CONTROL_INIT_STATE: begin
                    if (i_start) begin
                        o_next_state <= `MAIN_FFT_CONTROL_START_STATE;
                    end
                    o_finish <= 0;
                end
                `MAIN_FFT_CONTROL_START_STATE: begin
                    o_next_state <= `MAIN_FFT_CONTROL_START_WRITE_SIZE_REG_ADDR_STATE;
                end
                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_START_WRITE_SIZE_REG_ADDR_STATE,
                    `MAIN_FFT_CONTROL_START_WRITE_SOURCE_REG_ADDR_STATE,
                    `BEL_FFT_SIZE_REG_ADDR,
                    (i_fft_size)
                )
                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_START_WRITE_SOURCE_REG_ADDR_STATE,
                    `MAIN_FFT_CONTROL_START_WRITE_DEST_REG_ADDR_STATE,
                    `BEL_FFT_SOURCE_REG_ADDR,
                    (i_fft_size * (word_width * 2 / `BEL_FFT_DWIDTH * `BEL_FFT_BCNT))
                )
                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_START_WRITE_DEST_REG_ADDR_STATE,
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_1_STATE,
                    `BEL_FFT_DEST_REG_ADDR,
                    (2 * i_fft_size * (word_width * 2 / `BEL_FFT_DWIDTH * `BEL_FFT_BCNT))
                )

                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_1_STATE,
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_2_STATE,
                    (`BEL_FFT_FACTORS_REG_ADDR + 0),
                    (32'h0004_0100)
                )

                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_2_STATE,
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_3_STATE,
                    (`BEL_FFT_FACTORS_REG_ADDR + 1),
                    (32'h0004_0040)
                )

                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_3_STATE,
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_4_STATE,
                    (`BEL_FFT_FACTORS_REG_ADDR + 2),
                    (32'h0004_0010)
                )

                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_4_STATE,
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_5_STATE,
                    (`BEL_FFT_FACTORS_REG_ADDR + 3),
                    (32'h0004_0004)
                )

                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_START_WRITE_FACTORS_REG_ADDR_5_STATE,
                    `MAIN_FFT_CONTROL_RUN_WRITE_CONTROL_REG_ADDR_STATE,
                    (`BEL_FFT_FACTORS_REG_ADDR + 4),
                    (32'h0004_0001)
                )

                `WRITE_REGISTER(
                    `MAIN_FFT_CONTROL_RUN_WRITE_CONTROL_REG_ADDR_STATE,
                    `MAIN_FFT_CONTROL_RUN_READ_STATUS_REG_ADDR_STATE,
                    `BEL_FFT_CONTROL_REG_ADDR,
                    (i_inverse * 65536 + 257)
                )
                `MAIN_FFT_CONTROL_RUN_READ_STATUS_REG_ADDR_STATE: begin
                    if (i_int)
                        o_next_state <= `MAIN_FFT_CONTROL_FINISH_STATE;
                    else
                        o_next_state <= `MAIN_FFT_CONTROL_RUN_READ_STATUS_REG_ADDR_STATE;
                end
                `MAIN_FFT_CONTROL_FINISH_STATE: begin
                    o_next_state <= `MAIN_FFT_CONTROL_INIT_STATE;
                    o_finish <= 1;
                end
                default: begin
                    o_finish <= 0;
                end
            endcase
        end
    end
endmodule


`endif /* main_fft_control_v */