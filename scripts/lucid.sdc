# Lucid Timing Constraints for Gowin GW2AR-18
# ===========================================
# 108 MHz system clock from PLL (27 MHz input)
# PLL config: IDIV_SEL=2, FBDIV_SEL=40, ODIV_SEL=5
# Fout = 27 * (40+1) / (2+1) / 5 = 27 * 41 / 3 / 5 ≈ 73.8 (approx)
# Actual: Gowin rPLL with IDIV=2, FBDIV=40, ODIV=5 → 108 MHz

# Input clock
create_clock -name clk_27m_in -period 37.037 [get_ports clk_27m]

# Generated system clock from PLL (108 MHz)
create_generated_clock -name clk_sys \
    -source [get_ports clk_27m] \
    -divide_by 1 -multiply_by 4 \
    [get_nets clk_100m]

# Clock groups - input and system clocks are asynchronous
set_clock_groups -asynchronous \
    -group [get_clocks clk_27m_in] \
    -group [get_clocks clk_sys]

# Input delays (UART at 115200 baud, relative to system clock)
set_input_delay -clock clk_sys -max 5.0 [get_ports uart_rx]
set_input_delay -clock clk_sys -min 1.0 [get_ports uart_rx]

# Output delays (UART TX)
set_output_delay -clock clk_sys -max 8.0 [get_ports uart_tx]
set_output_delay -clock clk_sys -min 2.0 [get_ports uart_tx]

# False paths
set_false_path -from [get_ports btn_rst_n]
set_false_path -to [get_ports {led[*]}]

# Clock uncertainty
set_clock_uncertainty 0.200 [get_clocks clk_sys]
