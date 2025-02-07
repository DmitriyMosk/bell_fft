`include "bel_fft_def.v"

module testbench_8;

    parameter input_file_name = "input_data_1024.dat";
    parameter fft_size = 1024;
    parameter word_width = 32;
    parameter ram_awidth = $clog2(fft_size) + 1;

    reg inverse;
    reg clk;
    reg rst;

    reg                                 ram_control      ;
    wire [ram_awidth - 1:0]             ram_address      ;
    wire [`BEL_FFT_DWIDTH - 1:0]        ram_readdata     ;
    wire [`BEL_FFT_DWIDTH - 1:0]        ram_writedata    ;
    wire                                ram_read         ;
    wire                                ram_write        ;
    wire                                ram_waitrequest  ;
    wire                                ram_readdatavalid;

    wire int;

    /* values ram control begin */
    reg out_ram_cp_in_ram;
    /* values ram control end */

    /* values fft_control begin */
    reg start_fft_control;
    /* values fft_control end */

    task waitForInterrupt;
        begin
            @(posedge int);
        end
    endtask

    /* tasks ram control begin */   
    task reset_ram_control;
        begin
            /* broken */
            out_ram_cp_in_ram <= 0;
            in_ram_control  <= 0;
            out_ram_control <= 0;
        end
    endtask

    task cp_ram;
        begin
            /* broken */
            reset_ram_control ();
            @(posedge clk);
            out_ram_cp_in_ram <= '1;
            @(posedge clk);
            out_ram_cp_in_ram <= '0;
            @(posedge clk);
        end
    endtask
    /* tasks ram control end */

    /* values fft_control begin */
    task reset_start_fft_control;
        begin
            start_fft_control = 0;
        end
    endtask

    task run_fft_control;
        begin
            repeat (10)
                @(posedge clk);
            inverse = 0;
            start_fft_control = 1;
            @(posedge clk);
            start_fft_control = 0;
            @ (posedge clk);
            waitForInterrupt();
        end
    endtask

    task run_ifft_control;
        begin
            @ (posedge clk);
            inverse = 1;
            start_fft_control = 1;
            @(posedge clk);
            start_fft_control = 0;
            @ (posedge clk);
            waitForInterrupt();
        end
    endtask
    /* values fft_control end */

    initial begin
        rst = 1'b1;
        #20 rst = 1'b0;
    end

    initial begin
        clk = 1'b0;
    end

    always begin
        #10 clk = 1'b1;
        #10 clk = 1'b0;
    end

    initial begin
        reset_start_fft_control ();
        /* broken */
        reset_ram_control ();
        repeat (10)
            @(posedge clk);
        run_fft_control ();
        cp_ram ();
        // shift_freq_sig();
        run_ifft_control ();
        $finish;
    end

    initial begin
        // Timeout in case of errors
        #100000000 $finish;
    end

    main_fft u_fft (
            .clk_i                      (clk                    ),
            .rst_i                      (rst                    ),
            /*                                                  */
            .i_ram_control              (ram_control            ),
            .i_ram_address              (ram_address            ),
            .o_ram_readdata             (ram_readdata           ),
            .i_ram_writedata            (ram_writedata          ),
            .i_ram_read                 (ram_read               ),
            .i_ram_write                (ram_write              ),
            .o_ram_waitrequest          (ram_waitrequest        ),
            .o_ram_readdatavalid        (ram_readdatavalid      ),
            /*                                                  */
            .i_start                    (start_fft_control      ),
            .i_inverse                  (inverse                ),
            /*                                                  */
            .finish                     (int                    ));

endmodule

