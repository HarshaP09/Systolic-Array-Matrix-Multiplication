# Boolean Spartan-7 (xc7s50csga324) constraints for this project
# Top module expected: top_boolean_mm
#
# Clock: 100 MHz oscillator -> clk (PACKAGE_PIN F14)
create_clock -period 10.000 -name gclk [get_ports clk]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports {clk}]

# Set Bank 0 voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# UART TX (FPGA -> USB-UART RX)
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {UART_txd}]

