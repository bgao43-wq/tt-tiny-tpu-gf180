module tt_um_bgao43 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: input path
    output wire [7:0] uio_out,  // IOs: output path
    output wire [7:0] uio_oe,   // IOs: output enable
    input  wire       ena,      // Always enabled on TT board
    input  wire       clk,      // Clock
    input  wire       rst_n     // Active-low reset
);

    wire sclk;
    wire mosi;
    wire cs_n;
    wire miso;

    assign sclk = ui_in[0];
    assign mosi = ui_in[1];
    assign cs_n = ui_in[2];

    // Bidirectional pins unused
    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;

    // Dedicated outputs
    assign uo_out = {7'b000_0000, ena ? miso : 1'b0};

    // Avoid unused-input lint warnings
    wire _unused = &{ui_in[7:3], uio_in, 1'b0};

    top top_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .sclk  (sclk),
        .mosi  (mosi),
        .cs_n  (cs_n),
        .miso  (miso)
    );

endmodule
