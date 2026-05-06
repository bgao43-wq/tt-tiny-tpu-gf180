# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


async def set_spi(dut, cs_n, sclk, mosi):
    """
    Tiny TPU pin mapping:
      ui_in[0] = SCLK
      ui_in[1] = MOSI
      ui_in[2] = CS_N
    """
    dut.ui_in.value = (cs_n << 2) | (mosi << 1) | sclk


async def spi_send_byte(dut, value):
    """
    Send one SPI-like byte, MSB first, mode 0 style.
    Hold each SCLK level for several system-clock cycles so the DUT
    can safely sample the async SPI pins.
    """
    await set_spi(dut, 0, 0, 0)
    await ClockCycles(dut.clk, 4)

    for bit in range(7, -1, -1):
        mosi = (value >> bit) & 1

        # Data stable before rising edge
        await set_spi(dut, 0, 0, mosi)
        await ClockCycles(dut.clk, 4)

        # Rising edge: DUT samples MOSI
        await set_spi(dut, 0, 1, mosi)
        await ClockCycles(dut.clk, 4)

        # Falling edge
        await set_spi(dut, 0, 0, mosi)
        await ClockCycles(dut.clk, 4)

    # End frame
    await set_spi(dut, 1, 0, 0)
    await ClockCycles(dut.clk, 6)


def assert_resolvable(signal, name):
    assert signal.value.is_resolvable, f"{name} has X/Z value: {signal.value}"


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start Tiny TPU smoke test")

    # 10 ns period = 100 MHz, matching clock_hz = 100000000
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.ena.value = 1
    dut.uio_in.value = 0

    # SPI idle: CS_N high, SCLK low, MOSI low
    await set_spi(dut, 1, 0, 0)

    # Reset
    dut._log.info("Reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # Basic wrapper checks
    assert_resolvable(dut.uio_out, "uio_out")
    assert_resolvable(dut.uio_oe, "uio_oe")

    assert int(dut.uio_out.value) == 0
    assert int(dut.uio_oe.value) == 0

    dut._log.info("Send SPI command sequence")

    # Controller opcode format is data_in[7:4].
    # Known opcodes from ctrl.sv:
    #   0x2? = SET_MODE
    #   0x4? = SET_DIM
    #   0x6? = LOAD_W
    #   0x8? = EXEC
    await spi_send_byte(dut, 0x20)  # SET_MODE, 8-bit unsigned mode
    await spi_send_byte(dut, 0x42)  # SET_DIM, dimension/count = 2

    await spi_send_byte(dut, 0x60)  # LOAD_W
    await spi_send_byte(dut, 0x11)  # weight byte 0
    await spi_send_byte(dut, 0x22)  # weight byte 1

    await spi_send_byte(dut, 0x80)  # EXEC
    await spi_send_byte(dut, 0x12)  # activation byte 0
    await spi_send_byte(dut, 0x34)  # activation byte 1

    await ClockCycles(dut.clk, 20)

    dut._log.info(f"uo_out = {dut.uo_out.value}")

    # The upper 7 output bits should stay tied to 0 by the wrapper.
    # uo_out[0] is MISO.
    assert_resolvable(dut.uo_out, "uo_out")
    assert (int(dut.uo_out.value) & 0xFE) == 0
