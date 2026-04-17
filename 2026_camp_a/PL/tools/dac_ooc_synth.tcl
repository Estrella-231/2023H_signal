# Out-of-context synthesis check for src/dac_out.v.
# Usage:
#   vivado -mode batch -source tools/dac_ooc_synth.tcl

set script_dir [file dirname [file normalize [info script]]]
set pl_dir     [file normalize [file join $script_dir ".."]]
set out_dir    [file normalize [file join $pl_dir "ooc_dac_out"]]
file mkdir $out_dir

set part_name "xc7z010clg400-1"

read_verilog [file join $pl_dir "src" "selector.v"]
read_verilog [file join $pl_dir "src" "triangle.v"]
read_verilog [file join $pl_dir "src" "dac_out.v"]

synth_design \
    -top dac_out \
    -part $part_name \
    -mode out_of_context \
    -flatten_hierarchy rebuilt

create_clock -name dac_clk -period 8.000 [get_ports dac_clk]
create_clock -name cfg_clk -period 20.000 [get_ports cfg_clk]
set_clock_groups -name cfg_to_dac_ooc_async -asynchronous \
    -group [get_clocks cfg_clk] \
    -group [get_clocks dac_clk]

write_checkpoint -force [file join $out_dir "dac_out_post_synth.dcp"]
report_utilization -file [file join $out_dir "dac_out_utilization.rpt"]
report_timing_summary -file [file join $out_dir "dac_out_timing_summary.rpt"]
report_drc -file [file join $out_dir "dac_out_drc.rpt"]

puts "DAC OOC synthesis check finished."
puts "Output directory: $out_dir"
