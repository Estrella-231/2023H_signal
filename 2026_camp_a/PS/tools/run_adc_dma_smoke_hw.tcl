# Program the FPGA and run the last built ADC/DMA smoke-test ELF over JTAG.
#
# Usage:
#   xsct run_adc_dma_smoke_hw.tcl
#
# This starts the CPU. The smoke-test text is printed on the board UART,
# not in the XSCT console.

set script_dir [file dirname [file normalize [info script]]]
set ps_dir     [file normalize [file join $script_dir ".."]]
set proj_dir   [file normalize [file join $ps_dir ".."]]

set bit_file   [file normalize [file join $proj_dir "PL" "signal_separator_2026" "signal_separator_2026.runs" "impl_1" "system_wrapper.bit"]]
set init_file  [file normalize [file join $proj_dir "PL" "signal_separator_2026" "signal_separator_2026.gen" "sources_1" "bd" "system" "ip" "system_ps7_0" "ps7_init.tcl"]]
set last_elf_file [file normalize [file join $ps_dir "vitis_adc_dma_smoke_last_elf.txt"]]

proc require_file {path label} {
    if {![file exists $path]} {
        puts "ERROR: missing $label: $path"
        exit 1
    }
}

require_file $bit_file "bitstream"
require_file $init_file "ps7_init.tcl"
require_file $last_elf_file "last ELF pointer"

set f [open $last_elf_file "r"]
set elf_file [string trim [read $f]]
close $f
require_file $elf_file "ELF"

puts "Bitstream: $bit_file"
puts "PS init:   $init_file"
puts "ELF:       $elf_file"

connect
puts "Available targets:"
targets

puts "Programming FPGA..."
targets -set -nocase -filter {name =~ "*xc7z010*"}
fpga -file $bit_file

puts "Initializing PS7..."
source $init_file
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
rst -processor
ps7_init
ps7_post_config

puts "Downloading and starting ELF..."
dow $elf_file
con

puts "RUN_STARTED"
puts "Open the board UART terminal to read ADC/DMA smoke-test output."
