# Lucid Yosys Synthesis Script for Gowin GW2AR-18
# ================================================
# Usage: yosys -c syn_lucid.tcl

yosys -import

# Read all RTL files needed for synthesis
# Listing files explicitly to avoid SV-only constructs
set rtl_files [list \
    rtl/bus/wishbone_bus.sv \
    rtl/cpu/rv32im_core.sv \
    rtl/cpu/boot_rom.sv \
    rtl/cpu/mgmt_ram.sv \
    rtl/peripherals/uart.sv \
    rtl/peripherals/bram.sv \
    rtl/messages/fifo.sv \
    rtl/scheduler/graph_scheduler.sv \
    rtl/peripherals/gowin_pll.sv \
    rtl/top/lucid_top.sv \
]

foreach f $rtl_files {
    if {[file exists $f]} {
        puts "Reading $f"
        read_verilog -sv -DSYNTHESIS $f
    } else {
        puts "Warning: $f not found, skipping"
    }
}

# Set top module
hierarchy -top lucid_top

# Generic synthesis
synth -top lucid_top

# Technology mapping (4-LUT, like iCE40/GW2AR)
dfflibmap -liberty /dev/null
abc -lut 4

# Optimization
opt_clean -purge
opt -full

# Statistics
puts ""
puts "=== Statistics ==="
stat -top lucid_top

# Write synthesized netlist
write_json build/synth/lucid_top.json
write_verilog build/synth/lucid_top_synth.v

puts ""
puts "=== Synthesis Complete ==="
puts "Output files:"
puts "  build/synth/lucid_top.json"
puts "  build/synth/lucid_top_synth.v"
