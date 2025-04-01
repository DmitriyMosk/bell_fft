`include "bel_core/bel_fft_def.v"

/* По сути, это модуль просто объеденяет и соединяет разные модули */
module main_fft
(
    clk_i,
    rst_i,

    i_ram_control,
    i_ram_address,
    o_ram_readdata,
    i_ram_writedata,
    i_ram_read,
    i_ram_write,
    o_ram_readdatavalid,

    i_tw_cfg_sel,
    i_start,
    i_inverse,
    i_switch_ram_sel,
    i_shift_addr,

    finish
);

    parameter fft_size = 4096;
    parameter fft_size_mul_2 = fft_size * 2;
    parameter word_width = 32;
    parameter ram_awidth = $clog2(fft_size) + 1;

    input                               clk_i               ;
    input                               rst_i               ;

    input                               i_ram_control       ;
    input   [ram_awidth - 0:0]          i_ram_address       ;
    output  [`BEL_FFT_DWIDTH - 1:0]     o_ram_readdata      ;
    input   [`BEL_FFT_DWIDTH - 1:0]     i_ram_writedata     ;
    input                               i_ram_read          ;
    input                               i_ram_write         ;
    output                              o_ram_readdatavalid ;

    input [2 - 1:0]                     i_tw_cfg_sel        ;
    input                               i_start             ;
    input                               i_inverse           ;
    input                               i_switch_ram_sel    ;
    input [ram_awidth - 0 :0]           i_shift_addr        ;
    output                              finish              ;

    wire [`BEL_FFT_MIF_AWIDTH - 1:0]    m_address           ;
    wire [`BEL_FFT_DWIDTH - 1:0]        m_readdata          ;
    wire [`BEL_FFT_DWIDTH - 1:0]        m_writedata         ;
    wire                                m_read              ;
    wire                                m_write             ;
    wire                                m_waitrequest       ;
    wire                                m_readdatavalid     ;

    wire [`BEL_FFT_SIF_AWIDTH - 1:0]    s_address           ;
    wire [`BEL_FFT_DWIDTH - 1:0]        s_readdata          ;
    wire [`BEL_FFT_DWIDTH - 1:0]        s_writedata         ;
    wire                                s_read              ;
    wire                                s_write             ;
    wire [`BEL_FFT_BCNT - 1:0]          s_byteenable        ;
    wire                                s_waitrequest       ;
    wire                                s_readdatavalid     ;

    wire [$clog2(fft_size) - 1:0]       tw_adr              ;
    wire                                tw_rd               ;
    wire [`BEL_FFT_DWIDTH - 1:0]        tw_re               ;
    wire [`BEL_FFT_DWIDTH - 1:0]        tw_im               ;
    wire [2 - 1:0]                      tw_cfg_sel          ;

    wire                                int_o               ;

    wire [`BEL_FFT_DWIDTH - 1: 0]       ram_readdata        ;
    wire [`BEL_FFT_DWIDTH - 1: 0]       ram_writedata       ;
    wire                                ram_sel             ;
    wire [ram_awidth : 0]               ram_address         ;
    wire                                ram_write           ;
    reg                                 ram_readvalid       ;

    wire                                is_input_sel        ;
    wire                                is_left_spec        ;
    wire                                is_null             ;
    wire [ram_awidth - 0: 0]            address_fft         ;
    wire [ram_awidth - 1: 0]            address_shifted_fft ;
    wire [ram_awidth + 0: 0]            shift_addr_mul_2    ;
    reg                                 get_null            ;
    reg                                 is_input_readdata   ;
    wire [ram_awidth + 2: 0]            bound_left_null     ;
    wire [ram_awidth + 2: 0]            bound_rigth_null    ;

    assign o_ram_readdata       =   ram_readdata    ;
    assign o_ram_readdatavalid  =   ram_readvalid   ;

    /* Для shift режима часть спектра обнуляем, остальную умножаем */
    assign m_readdata = (
        (get_null)
            ? ('0)
            : (is_input_readdata & i_switch_ram_sel)
                ? ram_readdata <<< (ram_awidth - 1)
                : ram_readdata
    );

    assign m_readdatavalid      =   ram_readvalid ;
    /* не используется */
    assign m_waitrequest        =   1'b0          ;

    assign shift_addr_mul_2 = (i_shift_addr <<< 1);

    /* Флаг, который покажет, что это входная память */
    assign is_input_sel = (
        (i_switch_ram_sel)
            ? (m_address[ram_awidth + 3:ram_awidth + 2] == 2'b01)
            : (m_address[ram_awidth + 3:ram_awidth + 2] == 2'b10)
    );
    /* Флаг, который покажет, что это левая часть спектра (положительная) */
    assign is_left_spec = ( 
        (i_switch_ram_sel & is_input_sel)
            ? (m_address[ram_awidth + 1:2] < (fft_size))
            : (0)
    );

    /* Граница нулей левой части спектра (положительной)
       Когда происходит shift часть спектра свдивается,
       область из которой сдвигается нужно заполнить нулями
       это флаги границ этих областей */
    assign bound_left_null  = (shift_addr_mul_2);
    assign bound_rigth_null = (fft_size_mul_2 - shift_addr_mul_2);

    /* Определеяем что данный адрес должен указывать на ноль (сдвинутый спектр) */
    assign is_null = ( 
        (i_switch_ram_sel & is_input_sel)
        ? ( (is_left_spec)
            ? ((m_address[ram_awidth + 1:2]) <  bound_left_null )
            : ((m_address[ram_awidth + 1:2]) >= bound_rigth_null)
        )
        : (0)
    );
    /* Сдвинутый адрес */
    assign address_shifted_fft = (
        (i_switch_ram_sel & is_input_sel)
        ? (is_null)
            ? m_address [ram_awidth + 1:2]
            : (is_left_spec)
                ? (m_address[ram_awidth + 1:2] - (shift_addr_mul_2))
                : (m_address[ram_awidth + 1:2] + (shift_addr_mul_2))
        : ('0)
    );
    /* Формирование адреса вместе с битом области памяти */
    assign address_fft = (
        (i_switch_ram_sel & is_input_sel)
        ? {ram_sel, address_shifted_fft}
        : {ram_sel, m_address [ram_awidth + 1:2]}
    );

    /* разделение на две области памяти (2'b01 это входная память, 2'b10 это выходная память) при i_switch_ram_sel == 1 - наооборот */
    assign ram_sel              =   m_address[ram_awidth + 3:ram_awidth + 2] == 2'b01   ? i_switch_ram_sel  : ~i_switch_ram_sel;
    assign ram_address          =   i_ram_control                                       ? i_ram_address     : address_fft;
    assign ram_write            =   i_ram_control                                       ? i_ram_write       : m_write;
    assign ram_writedata        =   i_ram_control                                       ? i_ram_writedata   : m_writedata;

    /* у встроенной памяти нет своего валида (возможно при генерации IP можно найти такую опцию) */
    always @(posedge clk_i) begin
        if (rst_i) begin
            ram_readvalid       <= 0;
            get_null            <= 0;
            is_input_readdata   <= 0;
        end else  begin
            if (i_ram_control ? i_ram_read : m_read) begin
                ram_readvalid       <= 1;
                get_null            <= is_null & ~i_ram_control;
                is_input_readdata   <= ~i_ram_control & is_input_sel;
            end else begin
                ram_readvalid       <= 0;
                get_null            <= 0;
                is_input_readdata   <= 0;
            end
        end
    end

    bel_fft_avl #(
        .word_width             (word_width         ),
        .config_num             (2                  ),
        .stage_num              (6                  ),
        .twiddle_rom_max_awidth ($clog2(fft_size)   ),
        .fft_size               (fft_size           ),
        .fft_size1              (fft_size           ),
        .fft_size2              (0                  ),
        .fft_size3              (0                  ),
        .has_butterfly2         (0                  ))
        u_core (
        .clk_i                  (clk_i              ),
        .rst_i                  (rst_i | finish     ),
        /*                                          */
        .m_address              (m_address          ),
        .m_readdata             (m_readdata         ),
        .m_writedata            (m_writedata        ),
        .m_read                 (m_read             ),
        .m_write                (m_write            ),
        .m_waitrequest          (m_waitrequest      ),
        .m_readdatavalid        (m_readdatavalid    ),
        /*                                          */
        .s_address              (s_address          ),
        .s_readdata             (s_readdata         ),
        .s_writedata            (s_writedata        ),
        .s_read                 (s_read             ),
        .s_write                (s_write            ),
        .s_byteenable           (s_byteenable       ),
        .s_waitrequest          (s_waitrequest      ),
        .s_readdatavalid        (s_readdatavalid    ),
        /*                                          */
        .tw_adr                 (tw_adr             ),
        .tw_rd                  (tw_rd              ),
        .tw_re                  (tw_re              ),
        .tw_im                  (tw_im              ),
        .tw_cfg_sel             (tw_cfg_sel         ),
        /*                                          */
        .int_o                  (int_o              )
        );

    main_fft_twiddle_roms #(.word_width (word_width),
        .config_num     (2                                      ),
        .max_awidth     ($clog2(fft_size)                       ),
        .size           (fft_size                               ),
        .awidth         ($clog2(fft_size)                       ),
        .file_name      ("main_fft_twiddle_rom0.dat"            ),
        .size2          (fft_size                               ),
        .awidth2        ($clog2(fft_size)                       ),
        .file_name2     ("main_fft_twiddle_rom1.dat"            ),
        .size3          (0                                      ),
        .awidth3        (0                                      ),
        .file_name3     (""                                     ),
        .size4          (0                                      ),
        .awidth4        (0                                      ),
        .file_name4     (""                                     )
        ) u_twiddles (
        .clk_i          (clk_i                                  ),
        .rst_i          (rst_i | finish                         ),
        .adr_i          (tw_adr                                 ),
        .rd_i           (tw_rd                                  ),
        .dat_o          ({tw_re, tw_im}                         ),
        .cfg_sel_i      (i_tw_cfg_sel                           )
        );      

    main_fft_control #(.word_width(word_width)) fft_control (
        .i_clk              (clk_i              ),
        .i_rst              (rst_i              ),
        /*                                      */
        .i_start            (i_start            ),
        .i_int              (int_o              ),
        /*                                      */
        .o_state            (                   ),
        .o_next_state       (                   ),
        /*                                      */
        .i_inverse          (i_inverse          ),
        .i_fft_size         (fft_size           ),
        /*                                      */
        .o_s_address        (s_address          ),
        .i_s_readdata       (s_readdata         ),
        .o_s_writedata      (s_writedata        ),
        .o_s_read           (s_read             ),
        .o_s_write          (s_write            ),
        .o_s_byteenable     (s_byteenable       ),
        .i_s_waitrequest    (s_waitrequest      ),
        .i_s_readdatavalid  (s_readdatavalid    ),
        .o_finish           (finish             ));

    mem ram (
        .address    (ram_address    ),
        .clock      (clk_i          ),
        .data       (ram_writedata  ),
        .wren       (ram_write      ),
        .q          (ram_readdata   ));

endmodule

