# Minimal constraints for Boolean Spartan-7 board (XC7S50-CSGA324)
# Top module: top_boolean_mm
#
# Required ports:
#   input  clk
#   input  btn0
#   output UART_txd
#
# 100 MHz oscillator clock on F14
create_clock -period 10.000 -name gclk [get_ports clk]
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports clk]

# BTN0 on J2 (active-high)
set_property -dict { PACKAGE_PIN J2 IOSTANDARD LVCMOS33 } [get_ports btn0]

# UART TX pin (FPGA -> USB-UART RX)
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports UART_txd]

# Board configuration bank voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

