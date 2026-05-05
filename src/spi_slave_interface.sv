// SPI slave interface (parameterizable, generic byte/word width, supports SPI modes)
// Non-blocking, clock-domain sampled SCLK/CS/MOSI with edge detection.
// Provides simple TX/RX handshake: tx_valid accepted when CS is inactive (tx_ready high).
// rx_valid pulses when a FRAME (DATA_WIDTH bits) is received while CS is active.
module spi_slave_interface #(
    parameter int DATA_WIDTH = 8,
    parameter bit CPOL       = 1'b0,  // clock polarity
    parameter bit CPHA       = 1'b0,  // clock phase
    parameter bit LSB_FIRST  = 1'b0   // 0 = MSB first, 1 = LSB first
) (
    input  logic                  clk,      // system clock (domain for SPI sampling)
    input  logic                  rst_n,    // active-low reset
    // SPI pins (external)
    input  logic                  sclk,     // serial clock from master
    input  logic                  mosi,     // master out -> slave in
    input  logic                  cs_n,     // chip select, active low
    output logic                  miso,     // slave out -> master in (data)
    output logic                  miso_oe,  // miso output enable (for external tri-state)
    // Simple parallel TX/RX interface (clocked in 'clk' domain)
    input  logic [DATA_WIDTH-1:0] tx_data,
    input  logic                  tx_valid,
    output logic                  tx_ready,
    output logic [DATA_WIDTH-1:0] rx_data,
    output logic                  rx_valid
);

    // -------------------------------------------------------------------------
    // 2-FF synchronizers for async SPI inputs -> system clock domain
    // -------------------------------------------------------------------------
    logic [2:0] sclk_sync, cs_n_sync, mosi_sync;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= '1;   // idle SCLK = CPOL (treated below)
            cs_n_sync <= '1;
            mosi_sync <= '0;
        end else begin
            sclk_sync <= {sclk_sync[1:0], sclk};
            cs_n_sync <= {cs_n_sync[1:0], cs_n};
            mosi_sync <= {mosi_sync[1:0], mosi};
        end
    end

    // Stable sampled values (after 2-FF)
    wire sclk_s = sclk_sync[1];
    wire cs_n_s = cs_n_sync[1];
    wire mosi_s = mosi_sync[1];

    // Previous-cycle values for edge detection
    wire sclk_prev = sclk_sync[2];
    wire cs_n_prev = cs_n_sync[2];

    // Edge flags relative to system clock
    wire sclk_rise = ( sclk_s & ~sclk_prev);
    wire sclk_fall = (~sclk_s &  sclk_prev);
    wire cs_n_fall = (~cs_n_s &  cs_n_prev);  // CS asserted (active low)
    wire cs_n_rise = ( cs_n_s & ~cs_n_prev);  // CS deasserted

    // -------------------------------------------------------------------------
    // SPI mode decode
    //   CPOL=0,CPHA=0 (Mode 0): sample rising,  shift falling
    //   CPOL=0,CPHA=1 (Mode 1): sample falling, shift rising
    //   CPOL=1,CPHA=0 (Mode 2): sample falling, shift rising
    //   CPOL=1,CPHA=1 (Mode 3): sample rising,  shift falling
    // -------------------------------------------------------------------------
    wire sample_edge = (CPOL ^ CPHA) ? sclk_fall : sclk_rise;
    wire shift_edge  = (CPOL ^ CPHA) ? sclk_rise : sclk_fall;

    // -------------------------------------------------------------------------
    // TX / RX shift registers and bit counter
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] tx_shift;
    logic [DATA_WIDTH-1:0] rx_shift;
    logic [$clog2(DATA_WIDTH):0] bit_cnt;   // counts 0..DATA_WIDTH

    // -------------------------------------------------------------------------
    // TX handshake
    //   tx_ready is high while CS is deasserted, indicating the slave can
    //   accept new tx_data before the next transaction starts.
    // -------------------------------------------------------------------------
    assign tx_ready = cs_n_s;

    // Latch tx_data when tx_valid is asserted and CS is inactive (tx_ready high)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift <= '0;
        end else if (cs_n_s && tx_valid) begin
            // Pre-load TX shift register (idle / between frames)
            tx_shift <= tx_data;
        end else if (!cs_n_s) begin
            if (cs_n_fall) begin
                // CS just asserted: if CPHA=1 the first shift happens on the
                // leading edge, so keep current tx_shift; MISO is driven below.
                // Nothing extra needed here; tx_shift was loaded while CS was high.
            end else if (shift_edge) begin
                // Shift out next bit
                if (LSB_FIRST)
                    tx_shift <= {1'b0, tx_shift[DATA_WIDTH-1:1]};
                else
                    tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
            end
        end
    end

    // -------------------------------------------------------------------------
    // MISO drive
    //   Output enable follows CS (active when CS is asserted).
    //   Drive the MSB (or LSB) of the TX shift register continuously;
    //   the shift register rotates on every shift_edge.
    // -------------------------------------------------------------------------
    assign miso_oe = ~cs_n_s;
    assign miso    = miso_oe
                   ? (LSB_FIRST ? tx_shift[0] : tx_shift[DATA_WIDTH-1])
                   : 1'bz;

    // -------------------------------------------------------------------------
    // RX shift register and rx_valid generation
    // -------------------------------------------------------------------------
    logic rx_valid_r;
    assign rx_valid = rx_valid_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift   <= '0;
            rx_data    <= '0;
            rx_valid_r <= 1'b0;
            bit_cnt    <= '0;
        end else begin
            rx_valid_r <= 1'b0;  // default: pulse for one clock only

            if (cs_n_rise || cs_n_s) begin
                // CS deasserted or inactive: reset counter
                bit_cnt  <= '0;
                rx_shift <= '0;
            end else begin
                // CS is active
                if (sample_edge) begin
                    // Shift MOSI into RX register
                    if (LSB_FIRST)
                        rx_shift <= {mosi_s, rx_shift[DATA_WIDTH-1:1]};
                    else
                        rx_shift <= {rx_shift[DATA_WIDTH-2:0], mosi_s};

                    // Increment bit counter; assert rx_valid after full frame
                    if (bit_cnt == DATA_WIDTH[$clog2(DATA_WIDTH):0] - 1) begin
                        bit_cnt    <= '0;
                        rx_valid_r <= 1'b1;
                        // Capture completed frame
                        if (LSB_FIRST)
                            rx_data <= {mosi_s, rx_shift[DATA_WIDTH-1:1]};
                        else
                            rx_data <= {rx_shift[DATA_WIDTH-2:0], mosi_s};
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
            end
        end
    end

endmodule