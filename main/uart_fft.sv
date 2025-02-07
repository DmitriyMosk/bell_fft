//Проект транзитного буфера с последовательным интерфейсом UART 921600 Бод 
`ifndef uart_fft_sv
`define uart_fft_sv

// для синтеза в modelsim 
// `define SYNTHESIS

`include "bel_fft_def.v"

/* Блок необходим для связывания потоковых данных uart и памятью main_fft */
/* Основная соль в том, что uart дает и принимает байты, а в памяти у нас */
/* по 32 бита (4 байта), получается, что мы постипенно записываем байты   */
module fft (
    i_rst,
    i_clk,

    i_byte,
    i_ready,

    i_next_byte,
    o_byte,
    o_valid,

    i_inverse,
    i_shift_spec,

    o_start,
    o_finish,
    o_reset_all
);
    parameter fft_size      = 1024;
    parameter word_width    = `BEL_FFT_DWIDTH;
    parameter ram_awidth    = $clog2(fft_size) + 1;
    parameter shift_size    = 50;

    input               i_rst;
    input               i_clk;

    input       [7:0]   i_byte;
    input               i_ready;

    input               i_next_byte;
    output reg  [7:0]   o_byte;
    output reg          o_valid;

    input               i_inverse;
    input               i_shift_spec;

    output              o_start;
    output              o_finish;
    output              o_reset_all;

    localparam size_byte = 8;

    wire                                                        ram_control         ;
    wire [ram_awidth - 0: 0]                                    ram_address         ;
    wire [`BEL_FFT_DWIDTH - 1: 0]                               ram_readdata        ;
    wire [`BEL_FFT_DWIDTH - 1: 0]                               ram_writedata       ;
    wire                                                        ram_read            ;
    wire                                                        ram_write           ;
    wire                                                        ram_readdatavalid   ;

    reg                                                         start_fft           ;
    reg                                                         start_ifft          ;
    reg                                                         finish_fft          ;
    reg                                                         finish_ifft         ;
    wire                                                        finish              ;
    reg                                                         work_fft            ;
    reg                                                         work_ifft           ;
    reg                                                         inverse             ;
    reg [ram_awidth - 0 :0]                                     shift_addr          ;
    reg                                                         switch_ram_sel      ;
    reg [2 - 1:0]                                               tw_cfg_sel          ;

    reg [ram_awidth - 1: 0]                                     write_addr          ;
    reg [`BEL_FFT_DWIDTH - 1: 0]                                write_it_word       ;
    reg [`BEL_FFT_DWIDTH / size_byte - 1: 0] [size_byte - 1: 0] write_data          ;
    reg                                                         write               ;
    reg                                                         write_process_begin ;
    reg                                                         write_process_end   ;
    wire                                                        write_last_it       ;
    wire                                                        write_last_addr     ;

    reg [ram_awidth - 1 :0]                                     read_addr           ;
    reg [`BEL_FFT_DWIDTH - 1: 0]                                read_it_word        ;
    reg [`BEL_FFT_DWIDTH / size_byte - 1: 0] [size_byte - 1: 0] read_data           ;
    reg                                                         read                ;
    reg                                                         read_process_begin  ;
    reg                                                         read_process_end    ;
    wire                                                        read_last_it        ;
    wire                                                        read_last_addr      ;

    /* write fft begin */
    /* Тут определены статусы записи в память (из uart) */
    always @(posedge i_clk) begin
        if (i_rst) begin
            write_process_begin  <= 0;
            write_process_end    <= 0;
        end else begin
            if (write_last_addr & write_last_it) begin
                write_process_begin  <= 1;
                write_process_end    <= 1;
            end else if (i_ready) begin
                write_process_begin  <= 1;
                write_process_end    <= 0;
            end else if (write_process_end & (read_process_end | ~read_process_begin)) begin
                write_process_begin  <= 0;
                write_process_end    <= 0;
            end
        end
    end

    /* Итерация адреса записи */
    always @(posedge i_clk) begin
        if (i_rst) begin
            write_addr <= '0;
        end else if (write) begin
            write_addr <= write_addr + 2'b10;
        end
    end

    /* Итерация записи в регистр (write_data) для конкретного байта uart поочередно дает 4 байта, fft записывает в регистр (write_data) 4 раза (по байту). 
       Сначала мы записываем первый байт в write_data, потом, когда приходит второй мы его прикрепляем к первому и записываем в write_data уже два байта.
       И так далее со следующими байтами. */
    /* Данные итератор как раз и помогает записывать байты в слово из 4 байтов */
    always @(posedge i_clk) begin
        if (i_rst) begin
            write_it_word <= '0;
        end else if (i_ready) begin
            if (write_last_it)
                write_it_word <= '0;
            else 
                write_it_word <= write_it_word + 1;
        end
    end

    /* Это и есть регистр, который поочередно принимает в себя 4 байта */
    always @(posedge i_clk) begin
        if (i_rst) begin
            write_data <= '0;
        end else if (i_ready) begin
            write_data[write_it_word] = i_byte;
        end
    end

    /* Когда мы приняли все 4 байта, то мы можем уже целое слово (4 байта) записыват в память */
    always @(posedge i_clk) begin
        if (i_rst) begin
            write <= '0;
        end else if (i_ready) begin
            if (write_last_it)
                write <= 1;
        end
        else 
            write <= 0;
    end
    /* write fft end */

    /* work fft begin */
    /* После того, как мы полностью заполнили память, мы даем сигнал start чтобы main_fft начал работу.
       Всего сейчас есть три режима работы: fft, ifft, shift. shift - это собой представляет fft и ifft.
       shift - сначала отработает fft, потом для ifft сменится режим и даются адреса со сдвигом. */
    always @(posedge i_clk) begin
        if (i_rst) begin
            start_fft       <= '0;
            start_ifft      <= '0;
            work_fft        <= '0;
            work_ifft       <= '0;
            finish_fft      <= '0;
            finish_ifft     <= '0;
            inverse         <= '0;
            switch_ram_sel  <= '0;
            shift_addr      <= shift_size;
            tw_cfg_sel      <= '0;
        end else if (i_shift_spec) begin /* shift режим */
            /* fft */
            if (write_process_end) begin
                start_fft   <= 1;
                work_fft    <= 1;
                tw_cfg_sel  <= 2'b11;
            end else if (work_fft) begin
                start_fft   <= 0;
            end
            /* ifft */
            if (finish_fft & ~finish) begin
                inverse         <= 1;
                start_ifft      <= 1;
                work_ifft       <= 1;
                switch_ram_sel  <= 1;
                tw_cfg_sel      <= 2'b10;
            end else if (work_ifft) begin
                start_ifft      <= 0;
            end
            /* сигналы окончания работы */
            if (finish & work_fft & ~work_ifft & ~finish_fft) begin
                finish_fft  <= 1;
            end else if (finish & work_fft & work_ifft & ~finish_ifft) begin
                finish_ifft <= 1;
            end else if ((finish_fft | finish_ifft) & ~finish) begin
                finish_fft  <= 0;
                finish_ifft <= 0;
            end

            /* Обнуляем флаги, чтобы можно было использовать shift в следующий раз */
            if (read_process_end & read_process_begin) begin
                work_fft        <= 0;
                work_ifft       <= 0;
                switch_ram_sel  <= 0;
            end

        end else begin /* fft или ifft */
            if (write_process_end & (read_process_end | ~read_process_begin)) begin
                start_fft   <= 1;
                work_fft    <= 1;
                inverse     <= i_inverse;
                tw_cfg_sel  <= i_inverse ? 2'b10 : 2'b11;
            end else if (work_fft) begin
                start_fft   <= 0;
                if (read_process_begin & read_process_end) begin
                    work_fft    <= 0;
                end
            end 
        end
    end
    /* work fft end */

    /* read fft begin */
    /* Статусы для чтения из памяти в uart.
       Это чтение происходит после того, когда main_fft закончил свою работу. */
    always @(posedge i_clk) begin
        if (i_rst) begin
            read_process_begin  <= 0;
            read_process_end    <= 0;
        end else begin
            if ((i_shift_spec & finish_ifft) || (~i_shift_spec & finish)) begin
                read_process_begin  <= 1;
                read_process_end    <= 0;
            end else if (read_last_addr & read_last_it & o_valid & i_next_byte) begin
                read_process_begin  <= 1;
                read_process_end    <= 1;
            end else if (read_process_begin & read_process_end & ~read & ~o_valid) begin
                read_process_begin  <= 0;
                read_process_end    <= 0;
            end
        end
    end

    /* Адрес для чтения из памяти */
    always @(posedge i_clk) begin
        if (i_rst) begin
            read_addr <= '0;
        end else if (read_last_it & o_valid & i_next_byte) begin
            read_addr <= read_addr + 2'b10;
        end
    end

    /* Итератор, который из регистра (read_data) берет 1 байт на uart */
    always @(posedge i_clk) begin
        if (i_rst) begin
            read_it_word <= '0;
        end else if (o_valid & i_next_byte) begin
            if (read_last_it) read_it_word <= '0;
            else read_it_word <= read_it_word + 1;
        end
    end

    /* сигнал валидности для uart,
       когда мы прочитали что-то из памяти, мы на следующем такте можемы вадавать байт.
       валид уходить после того, как юарт прочитает байт (даст i_next_byte). */
    always @(posedge i_clk) begin
        if (i_rst | read_process_end) begin
            o_valid <= '0;
        end else if (read & ram_readdatavalid) begin
            o_valid <= 1;
        end else if (i_next_byte)
            o_valid <= 0;
    end

    /* 1 байт, который пойдет на uart. */
    always @(posedge i_clk) begin
        if (i_rst) begin
            o_byte <= '0;
        end else if (read & ram_readdatavalid) begin
            o_byte <= read_data[read_it_word];
        end
    end

    /* Мы всегда держим сигнал на чтение, пока не прочитаем ВСЕ.
       Суть в том, что когда нам нужно, мы меняем адрес и получаем следующие данные. */
    always @(posedge i_clk) begin
        if (i_rst) begin
            read <= 0;
        end else begin
            if (read_process_begin & ~read_process_end) begin
                read <= 1;
            end else if ((read_last_it & read_last_addr) | (read_process_begin & read_process_end)) begin
                read <= 0;
            end
        end
    end

    /* wire которые определяли конец последнего байта в слове                                   */
    assign write_last_it    = (write_it_word == (`BEL_FFT_DWIDTH / size_byte - 1 - 2)) & i_ready      ;
    assign read_last_it     = read_it_word  == (`BEL_FFT_DWIDTH / size_byte - 1 - 2)                  ;
    /* wire которые определяли конец последнего адреса в памяти                                 */
    assign write_last_addr  = write_addr    == fft_size * 2 - 2                                 ;
    assign read_last_addr   = read_addr     == fft_size * 2 - 2                                 ;
    /* Управление памятью                                                                       */
    /* все адреса идут с 0 до 2047, один бит в начале делит на две части.
       С 0 до 2047 входная память для fft, в нее fft вписывает, и отуда main_fft берет данные 
       С 2048 до 4095 выходная память, там main_fft держит временные значения
       и записывает результат. Отуда мы читаем данные и кидаем в uart                           */
    assign ram_control      = write | (read_process_begin & ~read_process_end)                  ;
    assign read_data        = ram_readdata                                                      ;

    assign ram_writedata    = (
        (write_data[1][7] == 1'b1)
            ? ({16'b1111_1111_1111_1111, write_data[1], write_data[0]})
            : ({16'b0000_0000_0000_0000 , write_data[1], write_data[0]})
    );
    assign ram_read         = read                                                              ;
    assign ram_write        = write                                                             ;

    assign o_start          = start_fft | start_ifft                                            ;

    assign o_reset_all      = (read_process_end & read_process_begin)                           ;

    assign ram_address= (
        (i_shift_spec & ~write_process_begin)
        ? {write ? 1 : 0, write ? write_addr : read_addr}
        : {write ? 0 : 1, write ? write_addr : read_addr}
    );
    assign o_finish = (
        (i_shift_spec)
            ? (finish_ifft  )
            : (finish_fft   )
    );

    main_fft #(
        .fft_size(fft_size))
        main_fft_inst (
        .clk_i                  (i_clk                  ),
        .rst_i                  (i_rst                  ),
        /*                                              */
        .i_ram_control          (ram_control            ),
        .i_ram_address          (ram_address            ),
        .o_ram_readdata         (ram_readdata           ),
        .i_ram_writedata        (ram_writedata          ),
        .i_ram_read             (ram_read               ),
        .i_ram_write            (ram_write              ),
        .o_ram_readdatavalid    (ram_readdatavalid      ),
        /*                                              */
        /*                                              */
        .i_tw_cfg_sel           (tw_cfg_sel             ),
        .i_start                (start_fft | start_ifft ),
        .i_inverse              (inverse                ),
        .i_switch_ram_sel       (switch_ram_sel         ),
        .i_shift_addr           (shift_addr             ),
        /*                                              */
        .finish                 (finish                 ));
endmodule

// module uart_fft
//     (
//     input sb0, sb1,
//     //input reset,
//     input clk_100,  //тактовые импульсы 100 МГц для PLL
// `ifdef SYNTHESIS
//     input clk_4,    //частота в 4 раза выше скорости СОМ порта
// `endif
//     input  uart_in,  // последовательный вход от FTDI_BD0
//     output uart_out, //последовательный вывод на FTDI_BD1
//     output [7:0] hl
//     );
//     parameter fft_size = 1024;
//     reg reset;
//     reg inverse;
//     reg shift_spec;

//     wire [7:0] byte_out;
//     wire [7:0] byte_in;

//     wire in_enable;
//     wire ready_out;
//     wire next_byte;

//     always @ (posedge clk_100) reset <= ~sb0;
 
//     always @(posedge clk_100) begin
//         if (reset) begin
//             inverse     <= 0;
//             shift_spec  <= 0;
//         end
//         else if (~sb1) begin 
//             if (~inverse) begin
//                 inverse     <= 1;
//                 shift_spec  <= 0;
//             end else if (inverse) begin
//                 inverse     <= 0;
//                 shift_spec  <= 1;
//             end else if (shift_spec) begin
//                 inverse     <= 0;
//                 shift_spec  <= 0;
//             end
//         end
//         else if (~sb1) inverse <= ~inverse;
//     end 

//     wire start;
//     wire finish;

//     reg byte_out_reg;
//     reg byte_in_reg;
//     reg start_reg;
//     reg finish_reg;

//     always @(posedge clk_4) begin
//         if (reset)  start_reg <= 0;
//         else if (start) start_reg <= 1;
//     end 
//     always @(posedge clk_4) begin
//         if (reset)  finish_reg <= 0;
//         else if (finish) finish_reg <= 1;
//     end 
//     always @(posedge clk_4) begin
//         if (reset)  byte_out_reg <= 0;
//         else if (~uart_out) byte_out_reg <= 1;
//     end 
//     always @(posedge clk_4) begin
//         if (reset)  byte_in_reg <= 0;
//         else if (~uart_in) byte_in_reg <= 1;
//     end 

//     assign hl[0] = reset;
//     assign hl[1] = inverse;
//     assign hl[2] = shift_spec;
//     assign hl[3] = start_reg;
//     assign hl[4] = finish_reg;
//     assign hl[5] = byte_out_reg;
//     assign hl[6] = byte_in_reg;
//     assign hl[7] = 1;

// `ifndef SYNTHESIS
//     wire clk_4; //частота в 4 раза выше скорости СОМ порта
//     mypll pll_inst
//     (
// 	    .areset (1'b0   ),
// 	    .inclk0 (clk_100),
// 	    .c0     (clk_4  ),
// 	    .locked (       ) 
//     );
// `endif

// 	wire [7:0] byte_out1;
//     wire [7:0] byte_out2;

//     wire ready1;
//     wire ready_buf;
// 	wire xxx;
// 	wire enbl = ready_buf && ~ xxx;

//     UART_reciever reciever (
// 		.reset(reset), 
// 		.clk(clk_4),
// 		.bit_in(uart_in), 
// 		.byte_out(byte_out1),
// 		.ready_out(ready1)
// 	);

// 	UART_buffer buffer (
// 		.clk(clk_4), 
// 		.reset(reset), 
// 		.enable(ready1),
// 		.byte_in(byte_out1), 
// 		.byte_out(byte_out2), 
// 		.ready(ready_buf)
// 	);
	
// 	UART_transmitter transmitter (
// 		.reset(reset), 
// 		.clk(clk_4), 
// 		.byte_in(byte_out2), 
// 		.enable(enbl),
// 		.bit_out(uart_out),
// 		.busy(xxx)
// 	);

// endmodule

module uart_fft
    (
    input sb0, sb1,
    //input reset,
    input clk_100,  //тактовые импульсы 100 МГц для PLL
`ifdef SYNTHESIS
    input clk_4,    //частота в 4 раза выше скорости СОМ порта
`endif
    input  uart_in,  // последовательный вход от FTDI_BD0
    output uart_out, //последовательный вывод на FTDI_BD1
    output [7:0] hl
    );
    parameter fft_size = 1024;
    reg reset;
    reg inverse;
    reg shift_spec;

    wire [7:0] byte_out;
    wire [7:0] byte_in;

    wire in_enable;
    wire ready_out;
    wire next_byte;

    always @ (posedge clk_100) reset <= ~sb0;
 
    always @(posedge clk_100) begin
        if (reset) begin
            inverse     <= 0;
            shift_spec  <= 0;
        end
        else if (~sb1) begin 
            if (~inverse) begin
                inverse     <= 1;
                shift_spec  <= 0;
            end else if (inverse) begin
                inverse     <= 0;
                shift_spec  <= 1;
            end else if (shift_spec) begin
                inverse     <= 0;
                shift_spec  <= 0;
            end
        end
        else if (~sb1) inverse <= ~inverse;
    end 

    wire start;
    wire finish;
    wire reset_fft_o;
    reg reset_fft_i;

    reg byte_out_reg;
    reg byte_in_reg;
    reg start_reg;
    reg finish_reg;

    reg was_no_null_out;
    reg was_no_null_in;

    always @(posedge clk_4) begin
        if (reset)  start_reg <= 0;
        else if (start) start_reg <= 1;
    end 
    always @(posedge clk_4) begin
        if (reset)  finish_reg <= 0;
        else if (finish) finish_reg <= 1;
    end 
    always @(posedge clk_4) begin
        if (reset)  byte_out_reg <= 0;
        else if (~uart_out) byte_out_reg <= 1;
    end 
    always @(posedge clk_4) begin
        if (reset)  byte_in_reg <= 0;
        else if (~uart_in) byte_in_reg <= 1;
    end 
    always @(posedge clk_4) begin
        if (reset)  was_no_null_in <= 0;
        else if (in_enable && (byte_in != 0)) was_no_null_in <= 1;
    end
    always @(posedge clk_4) begin
        if (reset)  was_no_null_out <= 0;
        else if (ready_out && (byte_out != 0)) was_no_null_out <= 1;
    end 

    always @(posedge clk_4) begin
        if (reset)  reset_fft_i <= 0;
        else reset_fft_i <= reset_fft_o;
    end 

    assign hl[0] = reset;
    assign hl[1] = inverse;
    assign hl[2] = shift_spec;
    assign hl[3] = start_reg;
    assign hl[4] = finish_reg;
    assign hl[5] = byte_out_reg;
    assign hl[6] = was_no_null_in;
    assign hl[7] = was_no_null_out;

`ifndef SYNTHESIS
    wire clk_4; //частота в 4 раза выше скорости СОМ порта
    mypll pll_inst
    (
	    .areset (1'b0   ),
	    .inclk0 (clk_100),
	    .c0     (clk_4  ),
	    .locked (       ) 
    );
`endif

    UART_reciever reciever (
		.reset(reset), 
		.clk(clk_4),
		.bit_in(uart_in), 
		.byte_out(byte_out),
		.ready_out(ready_out)
	);

    fft #(.fft_size(fft_size))fft_inst(
        .i_rst          (reset | reset_fft_i),
        .i_clk          (clk_4              ),
        .i_byte         (byte_out           ),
        .i_ready        (ready_out          ),
        .i_next_byte    (next_byte          ),
        .o_byte         (byte_in            ),
        .o_valid        (in_enable          ),
        .i_inverse      (inverse            ),
        .i_shift_spec   (shift_spec         ),
        .o_start        (start              ),
        .o_finish       (finish             ),
        .o_reset_all    (reset_fft_o        )
    );

	UART_transmitter transmitter (
		.reset(reset), 
		.clk(clk_4), 
		.byte_in(byte_in), 
		.enable(in_enable),
		.bit_out(uart_out),
		.busy(),
		.next_byte(next_byte)
	);

endmodule

`endif