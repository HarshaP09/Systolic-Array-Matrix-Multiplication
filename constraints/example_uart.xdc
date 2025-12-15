# Example XDC (EDIT FOR YOUR BOARD PINOUT!)
#
# You MUST set:
# - clk pin (board oscillator)
# - UART TX pin (FPGA -> USB-UART RX)
#
# Example only (pin names are placeholders):
#
# set_property PACKAGE_PIN <CLK_PIN> [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]
# create_clock -name sys_clk -period 10.000 [get_ports clk]  ;# 100 MHz
#
# set_property PACKAGE_PIN <UART_TX_PIN> [get_ports uart_txd]
# set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]

