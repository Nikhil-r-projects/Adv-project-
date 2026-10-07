# Vivado Synthesis Script for ntt_core
# Target: Xilinx Artix-7 (xc7a100tcsg324-1)

set_param general.maxThreads 8

# Create in-memory project
create_project -in_memory -part xc7a100tcsg324-1

# Read RTL files
read_verilog -sv {
    rtl/ntt/butterfly.sv
    rtl/ntt/ntt_memory.sv
    rtl/ntt/twiddle_rom.sv
    rtl/ntt/ntt_controller.sv
    rtl/ntt/ntt_core.sv
    tb/stubs/mod_mul.sv
    tb/stubs/mod_add.sv
    tb/stubs/mod_sub.sv
}

# Read constraints
read_xdc scripts/constraints.xdc

# Run Out-Of-Context synthesis
synth_design -top ntt_core -part xc7a100tcsg324-1 -mode out_of_context

# Report utilization and timing
report_utilization -file docs/utilization_synth.rpt
report_timing_summary -file docs/timing_synth.rpt

puts "Synthesis completed successfully!"
exit
