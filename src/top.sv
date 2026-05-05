// Top-level design
module top (
    input  logic clk,
    input  logic rst_n,

    // SPI pins
    input  logic sclk,
    input  logic mosi,
    input  logic cs_n,
    output logic miso
);

    // Internal nets between SPI and ctrl
    logic [7:0] spi_rx_data;
    logic       spi_rx_valid;
    logic [7:0] spi_tx_data;
    logic       spi_tx_valid;
    
    logic [7:0] ctrl_data_out;
    logic       ctrl_write_enable;
    
    // One-entry TX buffer in front of SPI slave
    logic spi_tx_ready;
    logic tx_buf_valid;
    logic [7:0] tx_buf_data;
    logic spi_tx_valid_reg;

    assign spi_tx_data  = tx_buf_data;
    assign spi_tx_valid = spi_tx_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_buf_valid      <= 1'b0;
            tx_buf_data       <= '0;
            spi_tx_valid_reg  <= 1'b0;
        end else begin
            spi_tx_valid_reg <= 1'b0;

            // capture data from controller when it writes
            if (ctrl_write_enable) begin
                if (!tx_buf_valid) begin
                    tx_buf_data  <= ctrl_data_out;
                    tx_buf_valid <= 1'b1;
                end
            end

            // when SPI slave indicates ready and we have buffered data, present it
            if (tx_buf_valid && spi_tx_ready) begin
                spi_tx_valid_reg <= 1'b1; // pulse to slave
                tx_buf_valid     <= 1'b0; // consumed
            end
        end
    end

    // Instantiate SPI slave interface
    spi_slave_interface #(
        .DATA_WIDTH(8),
        .CPOL(1'b0),
        .CPHA(1'b0),
        .LSB_FIRST(1'b0)
    ) spi_inst (
        .clk(clk),
        .rst_n(rst_n),
        .sclk(sclk),
        .mosi(mosi),
        .cs_n(cs_n),
        .miso(miso),
        .miso_oe(),
        .tx_data(spi_tx_data),
        .tx_valid(spi_tx_valid),
        .tx_ready(spi_tx_ready),
        .rx_data(spi_rx_data),
        .rx_valid(spi_rx_valid)
    );

    // Instantiate controller

    ctrl ctrl_inst (
        .clk(clk),
        .rst_n(rst_n),
        .input_valid(spi_rx_valid),
        .data_in(spi_rx_data),
        .write_enable(ctrl_write_enable),
        .data_out(ctrl_data_out)
    );
endmodule
