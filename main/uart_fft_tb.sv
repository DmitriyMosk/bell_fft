`ifndef uart_fft_tb_sv
`define uart_fft_tb_sv

`timescale 1 ps / 1 ps

localparam fft_size = 1024;
localparam fft_size_byte = fft_size * 2;

typedef struct packed{
    logic       sb0     ;
    logic       sb1     ;
    logic [7:0] hl      ;
    logic       in      ;
    logic       out     ;
    logic       clk_4   ;
    logic       clk_100 ;
} st_uart;

task automatic testIn(
        ref byte bytes_in[],
        ref st_uart uart
    ); 
    int length = $size(bytes_in);
    for (int i = 0; i < length; i++) begin
        
        @(posedge uart.clk_100);
        uart.in = 0;
        for (int j = 0; j < 8; j++) begin
            @(posedge uart.clk_100);
            uart.in = bytes_in[i][j];
        end
        @(posedge uart.clk_100);
        uart.in = 1;
    end
endtask 

task automatic testOut(
        ref byte bytes_out[],
        ref st_uart uart
    ); 
    int cnt = 0;
    int por = fft_size_byte;
    while (cnt != por ) begin
        @(posedge uart.clk_100);
        if (uart.out == 1) begin
            continue;    
        end else begin
            byte byte_tmp;
            cnt++;
            for (int j = 0; j < 8; j++) begin
                @(posedge uart.clk_100);
                byte_tmp[j] = uart.out;
            end
            bytes_out = {bytes_out, byte_tmp};
        end        
    end
endtask 

`define FFT     0
`define IFFT    1
`define SHIFT   2

task automatic switchMode(
        input integer mode,
        ref st_uart uart
    );  
    case (mode)
        `FFT: begin
            /* nothing */
            @(posedge uart.clk_100);
            $display("Mode is FFT");
        end
        `IFFT: begin
            @(posedge uart.clk_100);
            uart.sb1 = 0;
            @(posedge uart.clk_100);
            uart.sb1 = 1;
            @(posedge uart.clk_100);
            $display("Mode is IFFT");
        end
        `SHIFT: begin
            @(posedge uart.clk_100);
            uart.sb1 = 0;
            @(posedge uart.clk_100);
            uart.sb1 = 1;
            @(posedge uart.clk_100);
            uart.sb1 = 0;
            @(posedge uart.clk_100);
            uart.sb1 = 1;
            @(posedge uart.clk_100);
            $display("Mode is SHIFT");
        end
        default: begin
            $finish;
            $display("Error, mode is not defined %d", mode);
        end
    endcase
endtask 

task automatic resetUart(
        ref st_uart uart
    );  
    uart.sb1 = 1;
    @(posedge uart.clk_100);
    uart.sb0 = 1;
    @(posedge uart.clk_100);
    @(posedge uart.clk_100);
    uart.sb0 = 0;
    @(posedge uart.clk_100);
endtask 

task automatic testUart(
        ref byte bytes_in[],
        ref byte bytes_out[],
        ref st_uart uart
    );  

    fork
        testIn(bytes_in, uart);
        testOut(bytes_out, uart);
    join

    $display("in uart_fft, size=%d", $size(bytes_in));
    // $display("%h", bytes_in);
    // $display("%b", bytes_in);
    $display("out uart_fft, size=%d", $size(bytes_out));
    // $display("%h", bytes_out);
    // $display("%b", bytes_out);
endtask 

function automatic void readFileMem (string nameFile, ref byte outBytes[]);
    int file = $fopen(nameFile, "r");
    string readAddr;
    byte readByte[2];
    while($fscanf(file, "%s %2h%2h\n", readAddr, readByte[1], readByte[0]) == 3) begin
        outBytes = {outBytes, readByte[0], readByte[1]};
    end
    $fclose(file);
    return;    
endfunction

module uart_fft_tb #()();

    byte bytes_in[];
    byte bytes_out[];
    byte bytes_in_2[];
    // byte bytes_out_2[];
    st_uart uart;

    integer f;
    integer i;
    string input_file_name = "data_to_shift.dat";
    string input_file_name_2 = "data_to_shift_2.dat";
    // string input_file_name = "data_to_fft.dat";
    // string input_file_name = "output_data.dat";
    // string input_file_name = "data_to_ifft.dat";
    string output_file_name = "output_data.dat";
    string output_file_name_2 = "output_data_2.dat";
    // string output_file_name = "data_to_ifft.dat";

    initial begin
        uart.clk_100 = 0;
        uart.clk_4 = 0;
        uart.in = 1;
        uart.sb0 = 1;
        uart.sb1 = 1;
    end

    always #8 uart.clk_100  = ~uart.clk_100;
    always #2 uart.clk_4    = ~uart.clk_4;

    initial begin
        resetUart(uart);
        switchMode(`SHIFT, uart);

        readFileMem(input_file_name, bytes_in);
        testUart(bytes_in, bytes_out, uart);
        // f = $fopen(output_file_name); 
        // for (i = 0; i < bytes_out.size(); i = i + 2) begin
        //     $fwrite (f, "@%4X %X%X\n", i / 2, bytes_out[i+1], bytes_out[i+0]);
        // end
        // $fclose (f); 

        @(posedge uart.clk_100);
        @(posedge uart.clk_100);
        @(posedge uart.clk_100);
        @(posedge uart.clk_100);

        readFileMem(input_file_name_2, bytes_in_2);
        testUart(bytes_in_2, bytes_out, uart);
        f = $fopen(output_file_name); 
        for (i = 0; i < bytes_out.size(); i = i + 2) begin
            $fwrite (f, "@%4X %X%X\n", i / 2, bytes_out[i+1], bytes_out[i+0]);
        end
        $fclose (f);          
        $stop; 
    end

    uart_fft #(.fft_size(fft_size)) uart_fft_inst
    (
        .sb0        (~uart.sb0), 
        .clk_100    (uart.clk_100), 
        .clk_4      (uart.clk_4), 
        .uart_in    (uart.in), 
        .uart_out   (uart.out),
        .hl         (uart.hl),
        .sb1        (uart.sb1)
    );
endmodule
`endif