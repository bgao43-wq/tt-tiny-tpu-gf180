# Tiny TPU Systolic Array

This project implements a small TPU-style matrix multiplication accelerator using a systolic array architecture. The design is intended for TinyTapeout and uses a simple SPI-style serial interface to configure the design, load data, start computation, and read results.

## How it works

The design is built around a small systolic array made of processing elements. Each processing element performs multiply-accumulate operations and passes data through the array. The controller receives commands through the SPI interface, manages configuration and execution, and sends results back through the serial output.

The TinyTapeout wrapper maps the external signals as follows:

- `ui_in[0]`: SCLK
- `ui_in[1]`: MOSI
- `ui_in[2]`: CS_N
- `uo_out[0]`: MISO

The system clock and reset use the standard TinyTapeout `clk` and `rst_n` pins.

## How to test

The project can be tested using the TinyTapeout cocotb testbench flow. The testbench drives the TinyTapeout wrapper interface, applies reset, sends SPI command sequences through `ui_in`, and observes the serial output through `uo_out[0]`.

To run the test locally:

```bash
cd test
make -B
```

The GitHub Actions workflow also runs the RTL test automatically after pushing changes to the repository.

## External hardware

No external hardware is required. The design only uses the TinyTapeout digital input, output, clock, and reset pins.
