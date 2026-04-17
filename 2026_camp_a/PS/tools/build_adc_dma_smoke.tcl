# Build the ADC/DMA smoke-test standalone application from the current XSA.
#
# Usage:
#   xsct build_adc_dma_smoke.tcl
#
# Output:
#   ../vitis_adc_dma_smoke_ws_<timestamp>/adc_dma_smoke/Debug/adc_dma_smoke.elf

set script_dir [file dirname [file normalize [info script]]]
set ps_dir     [file normalize [file join $script_dir ".."]]
set proj_dir   [file normalize [file join $ps_dir ".."]]

set xsa_file   [file normalize [file join $proj_dir "PL" "system_wrapper.xsa"]]
set src_file   [file normalize [file join $ps_dir "tests" "adc_dma_smoke_main.c"]]

set stamp      [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set workspace_dir [file normalize [file join $ps_dir "vitis_adc_dma_smoke_ws_$stamp"]]
set platform_name "system_adc_dma_smoke_platform"
set app_name      "adc_dma_smoke"
set proc_core     "ps7_cortexa9_0"
set domain_name   "standalone_domain"
set elf_file      [file join $workspace_dir $app_name "Debug" "$app_name.elf"]
set last_elf_file [file normalize [file join $ps_dir "vitis_adc_dma_smoke_last_elf.txt"]]

proc require_file {path label} {
    if {![file exists $path]} {
        puts "ERROR: missing $label: $path"
        exit 1
    }
}

require_file $xsa_file "XSA"
require_file $src_file "smoke-test source"

puts "XSA:       $xsa_file"
puts "Source:    $src_file"
puts "Workspace: $workspace_dir"

file mkdir $workspace_dir
setws $workspace_dir

puts "Creating platform..."
platform create \
    -name $platform_name \
    -hw $xsa_file \
    -proc $proc_core \
    -os standalone \
    -out $workspace_dir

platform active $platform_name
domain active $domain_name

puts "Generating platform/BSP..."
platform generate

puts "Creating empty application..."
app create \
    -name $app_name \
    -platform $platform_name \
    -domain $domain_name \
    -template "Empty Application"

set app_src_dir [file join $workspace_dir $app_name "src"]
file mkdir $app_src_dir
file copy -force $src_file [file join $app_src_dir "main.c"]

puts "Building application..."
app build -name $app_name

if {![file exists $elf_file]} {
    puts "ERROR: build finished but ELF was not found: $elf_file"
    exit 2
}

set f [open $last_elf_file "w"]
puts $f $elf_file
close $f

puts "BUILD_OK"
puts "ELF: $elf_file"
puts "Last ELF path written to: $last_elf_file"
