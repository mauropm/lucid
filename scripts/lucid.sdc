# Lucid Timing Constraints for Gowin GW2AR-18
# ===========================================
# 100 MHz system clock from PLL (27 MHz input)

# Create clock
create_clock -name sys_clk -period 10.000 [get_ports clk]

# Generated clocks from PLL
create_generated_clock -name pll_100m -source [get_ports clk_27m] \
    -divide_by 27 -multiply_by 100 [get_pins pll_inst/CLKOUT]

# Clock groups
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks pll_100m]

# Input delays (UART at 115200 baud)
set_input_delay -clock sys_clk -max 2.0 [get_ports uart_rx]
set_input_delay -clock sys_clk -min 0.5 [get_ports uart_rx]

# Output delays (UART TX)
set_output_delay -clock sys_clk -max 4.0 [get_ports uart_tx]
set_output_delay -clock sys_clk -min 1.0 [get_ports uart_tx]

# False paths
set_false_path -from [get_ports btn_rst_n]
set_false_path -to [get_ports led*]

# Clock uncertainty
set_clock_uncertainty 0.200 [get_clocks sys_clk]
set_clock_uncertainty 0.200 [get_clocks pll_100m]
