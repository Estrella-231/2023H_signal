##############################################################################
# 2026 信号分离装置 — Vivado Block Design 构建脚本 (v2)
# 目标：AX7010 (XC7Z010-1CLG400C)
# ADC: AN9238 (AD9238, 12-bit 双通道 65MSPS)
# DAC: AN9767 (AD9767, 14-bit 双通道 125MSPS)
#
# 用法：在 Vivado TCL Console 中执行
#   cd <本文件所在目录>
#   source build.tcl
##############################################################################

# ===================== 工程设置 =====================
set project_name "signal_separator_2026"
set project_dir  [file normalize [file dirname [info script]]]
set part_name    "xc7z010clg400-1"

# 创建工程（-force 会覆盖同名工程）
create_project $project_name $project_dir/$project_name -part $part_name -force

# 设置 IP 仓库路径
set_property ip_repo_paths [list "$project_dir/ip_repo"] [current_project]
update_ip_catalog

# ===================== 添加 HDL 源文件 =====================
add_files -norecurse [list \
    "$project_dir/src/an9238_axis.v"      \
    "$project_dir/src/axis_tlast_gen.v"   \
    "$project_dir/src/ad7606_axis.v"      \
    "$project_dir/src/dac_out.v"          \
    "$project_dir/src/triangle.v"         \
    "$project_dir/src/selector.v"         \
    "$project_dir/src/chufa.v"            \
    "$project_dir/src/mearsure_phase.v"   \
    "$project_dir/src/freq_measure.v"     \
    "$project_dir/src/signed_extend.v"    \
    "$project_dir/src/complement_2_true.v"\
]

update_compile_order -fileset sources_1

add_files -fileset constrs_1 -norecurse "$project_dir/cons/ax7010.xdc"

# ===================== 创建 Block Design =====================
create_bd_design "system"

# =====================================================================
# 1. ZYNQ Processing System
# =====================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7

set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {64} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO {8} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR3} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
] [get_bd_cells ps7]

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
    [get_bd_cells ps7]

# 时钟命名:
#   FCLK_CLK0 = 50MHz  (AXI 总线、DMA、GPIO)
#   FCLK_CLK1 = 64MHz  (ADC 采样时钟)

# =====================================================================
# 2. Processor System Reset (50MHz 域)
# =====================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_50M
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_ps7_50M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_50M/ext_reset_in]

# =====================================================================
# 3. Clocking Wizard: 50MHz → 125MHz (DAC 时钟)
# =====================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125} \
    CONFIG.CLK_IN1_BOARD_INTERFACE {Custom} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.RESET_PORT {resetn} \
] [get_bd_cells clk_wiz_0]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins clk_wiz_0/clk_in1]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins clk_wiz_0/resetn]

# =====================================================================
# 4. AXI Interconnect (PS → 外设控制)
#    M00 = DMA S_AXI_LITE
#    M01~M08 = 8 个 AXI GPIO
# =====================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property CONFIG.NUM_MI {9} [get_bd_cells axi_interconnect_0]

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] \
                    [get_bd_intf_pins axi_interconnect_0/S00_AXI]

# GP0 时钟
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]

# Interconnect 全局 + S00 + 所有 M 端口时钟/复位
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN]

for {set i 0} {$i < 9} {incr i} {
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] \
        [get_bd_pins axi_interconnect_0/[format "M%02d_ACLK" $i]]
    connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] \
        [get_bd_pins axi_interconnect_0/[format "M%02d_ARESETN" $i]]
}

# =====================================================================
# 5. AXI DMA (S2MM: ADC 数据 → DDR)
#    + AXI SmartConnect 做 AXI4→AXI3 协议转换 (DMA↔HP0)
# =====================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_s2mm_burst_size {64} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
] [get_bd_cells axi_dma_0]

# DMA 控制通道 → AXI Interconnect M00
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
                    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

# AXI SmartConnect: AXI4 (DMA) → AXI3 (PS HP0) 协议转换
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0
set_property CONFIG.NUM_SI {1} [get_bd_cells smartconnect_0]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] \
                    [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] \
                    [get_bd_intf_pins ps7/S_AXI_HP0]

# SmartConnect 时钟和复位
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins smartconnect_0/aclk]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins smartconnect_0/aresetn]

# DMA 时钟和复位
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins axi_dma_0/axi_resetn]

# DMA S2MM 中断 → PS
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins ps7/IRQ_F2P]

# HP0 时钟
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/S_AXI_HP0_ACLK]

# =====================================================================
# 6. CIC 级联抽取 + 64MHz 域独立复位
# 策略: ADC 输出 32-bit {ch2_s16, ch1_s16}
#       先用 xlslice 各取 16-bit，分别经独立 CIC 链抽取，
#       再在 50MHz 域合并回 32-bit 后送 DMA
# =====================================================================

# 64MHz 域独立复位
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_64M
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins rst_ps7_64M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_64M/ext_reset_in]

# 125MHz 域独立复位（DAC 域）
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_125M
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rst_ps7_125M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_125M/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_ps7_125M/dcm_locked]

# ---- CH1: 取 adc_tdata 低 16-bit ----

# ---- CH2: 取 adc_tdata 高 16-bit ----

# CIC_0_CH1: CH1 64MHz→12.8MHz (5×)
create_bd_cell -type ip -vlnv xilinx.com:ip:cic_compiler:4.0 cic_0_ch1
set_property -dict [list \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Number_Of_Stages {4} \
    CONFIG.Sample_Rate_Changes {Fixed} \
    CONFIG.Fixed_Or_Initial_Rate {5} \
    CONFIG.Input_Sample_Frequency {64} \
    CONFIG.Clock_Frequency {64} \
    CONFIG.Input_Data_Width {16} \
    CONFIG.Quantization {Truncation} \
    CONFIG.Output_Data_Width {16} \
    CONFIG.Number_Of_Channels {1} \
    CONFIG.SamplePeriod {1} \
    CONFIG.HAS_ARESETN {true} \
] [get_bd_cells cic_0_ch1]

# CIC_1_CH1: CH1 12.8MHz→2.56MHz (5×)
create_bd_cell -type ip -vlnv xilinx.com:ip:cic_compiler:4.0 cic_1_ch1
set_property -dict [list \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Number_Of_Stages {4} \
    CONFIG.Sample_Rate_Changes {Fixed} \
    CONFIG.Fixed_Or_Initial_Rate {5} \
    CONFIG.Input_Sample_Frequency {12.8} \
    CONFIG.Clock_Frequency {64} \
    CONFIG.Input_Data_Width {16} \
    CONFIG.Quantization {Truncation} \
    CONFIG.Output_Data_Width {16} \
    CONFIG.Number_Of_Channels {1} \
    CONFIG.SamplePeriod {1} \
    CONFIG.HAS_ARESETN {true} \
] [get_bd_cells cic_1_ch1]

# CIC_0_CH2 / CIC_1_CH2: 同结构
create_bd_cell -type ip -vlnv xilinx.com:ip:cic_compiler:4.0 cic_0_ch2
set_property -dict [list \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Number_Of_Stages {4} \
    CONFIG.Sample_Rate_Changes {Fixed} \
    CONFIG.Fixed_Or_Initial_Rate {5} \
    CONFIG.Input_Sample_Frequency {64} \
    CONFIG.Clock_Frequency {64} \
    CONFIG.Input_Data_Width {16} \
    CONFIG.Quantization {Truncation} \
    CONFIG.Output_Data_Width {16} \
    CONFIG.Number_Of_Channels {1} \
    CONFIG.SamplePeriod {1} \
    CONFIG.HAS_ARESETN {true} \
] [get_bd_cells cic_0_ch2]

create_bd_cell -type ip -vlnv xilinx.com:ip:cic_compiler:4.0 cic_1_ch2
set_property -dict [list \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Number_Of_Stages {4} \
    CONFIG.Sample_Rate_Changes {Fixed} \
    CONFIG.Fixed_Or_Initial_Rate {5} \
    CONFIG.Input_Sample_Frequency {12.8} \
    CONFIG.Clock_Frequency {64} \
    CONFIG.Input_Data_Width {16} \
    CONFIG.Quantization {Truncation} \
    CONFIG.Output_Data_Width {16} \
    CONFIG.Number_Of_Channels {1} \
    CONFIG.SamplePeriod {1} \
    CONFIG.HAS_ARESETN {true} \
] [get_bd_cells cic_1_ch2]

# 时钟和复位连接
foreach cic_cell {cic_0_ch1 cic_1_ch1 cic_0_ch2 cic_1_ch2} {
    connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins $cic_cell/aclk]
    connect_bd_net [get_bd_pins rst_ps7_64M/peripheral_aresetn] [get_bd_pins $cic_cell/aresetn]
}

# CIC 级联
connect_bd_intf_net [get_bd_intf_pins cic_0_ch1/M_AXIS_DATA] [get_bd_intf_pins cic_1_ch1/S_AXIS_DATA]
connect_bd_intf_net [get_bd_intf_pins cic_0_ch2/M_AXIS_DATA] [get_bd_intf_pins cic_1_ch2/S_AXIS_DATA]

# =====================================================================
# 7. 时钟域转换 + AXIS Concat + TLAST 生成器
# =====================================================================

# Clock Converter CH1: 64MHz → 50MHz
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 clkconv_ch1
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins clkconv_ch1/s_axis_aclk]
connect_bd_net [get_bd_pins rst_ps7_64M/peripheral_aresetn] [get_bd_pins clkconv_ch1/s_axis_aresetn]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins clkconv_ch1/m_axis_aclk]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins clkconv_ch1/m_axis_aresetn]
connect_bd_intf_net [get_bd_intf_pins cic_1_ch1/M_AXIS_DATA] [get_bd_intf_pins clkconv_ch1/S_AXIS]

# Clock Converter CH2
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 clkconv_ch2
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins clkconv_ch2/s_axis_aclk]
connect_bd_net [get_bd_pins rst_ps7_64M/peripheral_aresetn] [get_bd_pins clkconv_ch2/s_axis_aresetn]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins clkconv_ch2/m_axis_aclk]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins clkconv_ch2/m_axis_aresetn]
connect_bd_intf_net [get_bd_intf_pins cic_1_ch2/M_AXIS_DATA] [get_bd_intf_pins clkconv_ch2/S_AXIS]

# AXIS Combiner: 合并 CH1(16-bit) + CH2(16-bit) → 32-bit {ch2,ch1}
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_combiner:1.1 axis_combiner_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.NUM_SI {2}] [get_bd_cells axis_combiner_0]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axis_combiner_0/aclk]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins axis_combiner_0/aresetn]
connect_bd_intf_net [get_bd_intf_pins clkconv_ch1/M_AXIS] [get_bd_intf_pins axis_combiner_0/S00_AXIS]
connect_bd_intf_net [get_bd_intf_pins clkconv_ch2/M_AXIS] [get_bd_intf_pins axis_combiner_0/S01_AXIS]

# axis_tlast_gen RTL 模块: 每 1024 拍打一次 TLAST，与 ADC DMA smoke test 的 CAPTURE_WORDS 匹配
create_bd_cell -type module -reference axis_tlast_gen tlast_gen_0
set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.PKT_LEN {1024}] [get_bd_cells tlast_gen_0]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins tlast_gen_0/aclk]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins tlast_gen_0/aresetn]
connect_bd_intf_net [get_bd_intf_pins axis_combiner_0/M_AXIS] [get_bd_intf_pins tlast_gen_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins tlast_gen_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# =====================================================================
# 8. AXI GPIO × 8 + an9238_axis + dac_out
# =====================================================================

# ---- 先创建所有 GPIO ----
foreach {gpio_name} {gpio_a_dds_freq gpio_a_dds_phase gpio_b_dds_freq gpio_b_dds_phase \
                      gpio_a_tri_step gpio_b_tri_step gpio_wave_ctrl} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 $gpio_name
    set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_OUTPUTS {1}] [get_bd_cells $gpio_name]
}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 gpio_phase_read
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1}] [get_bd_cells gpio_phase_read]

# Keep the phase-read AXI GPIO internal. Replace this constant with real
# phase-measurement logic when that feedback path is ready.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_phase_read
set_property -dict [list CONFIG.CONST_WIDTH {32} CONFIG.CONST_VAL {0}] [get_bd_cells const_phase_read]
connect_bd_net [get_bd_pins const_phase_read/dout] [get_bd_pins gpio_phase_read/gpio_io_i]

# GPIO → Interconnect M01~M08
set gpio_list [list gpio_a_dds_freq gpio_a_dds_phase gpio_b_dds_freq gpio_b_dds_phase \
               gpio_a_tri_step gpio_b_tri_step gpio_wave_ctrl gpio_phase_read]
set idx 1
foreach gpio $gpio_list {
    set mi [format "M%02d_AXI" $idx]
    connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/$mi] [get_bd_intf_pins $gpio/S_AXI]
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $gpio/s_axi_aclk]
    connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins $gpio/s_axi_aresetn]
    incr idx
}

# ---- an9238_axis: ADC 驱动（RTL module） ----
# an9238_axis.v 现在有两个独立的 16-bit AXIS 输出接口：
#   m_ch1 (m_ch1_tdata/m_ch1_tvalid/m_ch1_tready) → CIC_0_CH1
#   m_ch2 (m_ch2_tdata/m_ch2_tvalid/m_ch2_tready) → CIC_0_CH2
create_bd_cell -type module -reference an9238_axis adc_inst

connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins adc_inst/adc_clk]
connect_bd_net [get_bd_pins rst_ps7_64M/peripheral_aresetn] [get_bd_pins adc_inst/rst_n]

create_bd_port -dir I -from 11 -to 0 ad1_in
create_bd_port -dir I -from 11 -to 0 ad2_in
create_bd_port -dir O ad1_clk
create_bd_port -dir O ad2_clk

# ADC 外部时钟端口
connect_bd_net [get_bd_pins adc_inst/ad1_clk] [get_bd_ports ad1_clk]
connect_bd_net [get_bd_pins adc_inst/ad2_clk] [get_bd_ports ad2_clk]
connect_bd_net [get_bd_pins adc_inst/ad1_in]  [get_bd_ports ad1_in]
connect_bd_net [get_bd_pins adc_inst/ad2_in]  [get_bd_ports ad2_in]

# CH1 → CIC_0_CH1 (用 connect_bd_intf_net 连整个 bundle)
connect_bd_intf_net [get_bd_intf_pins adc_inst/M_AXIS_CH1] \
                    [get_bd_intf_pins cic_0_ch1/S_AXIS_DATA]

# CH2 → CIC_0_CH2
connect_bd_intf_net [get_bd_intf_pins adc_inst/M_AXIS_CH2] \
                    [get_bd_intf_pins cic_0_ch2/S_AXIS_DATA]

# ---- dac_out: DAC 输出（RTL module） ----
create_bd_cell -type module -reference dac_out dac_inst

connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins dac_inst/dac_clk]
connect_bd_net [get_bd_pins rst_ps7_125M/peripheral_aresetn] [get_bd_pins dac_inst/rst_n]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins dac_inst/cfg_clk]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins dac_inst/cfg_rst_n]

connect_bd_net [get_bd_pins gpio_a_dds_freq/gpio_io_o]  [get_bd_pins dac_inst/dds_a_freq]
connect_bd_net [get_bd_pins gpio_a_dds_phase/gpio_io_o] [get_bd_pins dac_inst/dds_a_phase]
connect_bd_net [get_bd_pins gpio_b_dds_freq/gpio_io_o]  [get_bd_pins dac_inst/dds_b_freq]
connect_bd_net [get_bd_pins gpio_b_dds_phase/gpio_io_o] [get_bd_pins dac_inst/dds_b_phase]
connect_bd_net [get_bd_pins gpio_a_tri_step/gpio_io_o]  [get_bd_pins dac_inst/tri_a_step]
connect_bd_net [get_bd_pins gpio_b_tri_step/gpio_io_o]  [get_bd_pins dac_inst/tri_b_step]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 wave_sel_a_slice
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells wave_sel_a_slice]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 wave_sel_b_slice
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1}] [get_bd_cells wave_sel_b_slice]
connect_bd_net [get_bd_pins gpio_wave_ctrl/gpio_io_o] [get_bd_pins wave_sel_a_slice/Din]
connect_bd_net [get_bd_pins gpio_wave_ctrl/gpio_io_o] [get_bd_pins wave_sel_b_slice/Din]
connect_bd_net [get_bd_pins wave_sel_a_slice/Dout] [get_bd_pins dac_inst/wave_sel_a]
connect_bd_net [get_bd_pins wave_sel_b_slice/Dout] [get_bd_pins dac_inst/wave_sel_b]

# =====================================================================
# 10. 外部端口并连线
# =====================================================================

# AN9767 DAC 端口
create_bd_port -dir O -from 13 -to 0 da1_data
create_bd_port -dir O da1_clk
create_bd_port -dir O da1_wrt
create_bd_port -dir O -from 13 -to 0 da2_data
create_bd_port -dir O da2_clk
create_bd_port -dir O da2_wrt

connect_bd_net [get_bd_pins dac_inst/da1_data] [get_bd_ports da1_data]
connect_bd_net [get_bd_pins dac_inst/da1_clk]  [get_bd_ports da1_clk]
connect_bd_net [get_bd_pins dac_inst/da1_wrt]  [get_bd_ports da1_wrt]
connect_bd_net [get_bd_pins dac_inst/da2_data] [get_bd_ports da2_data]
connect_bd_net [get_bd_pins dac_inst/da2_clk]  [get_bd_ports da2_clk]
connect_bd_net [get_bd_pins dac_inst/da2_wrt]  [get_bd_ports da2_wrt]

# LED 调试端口（连到常量 0）
create_bd_port -dir O -from 3 -to 0 led
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_led
set_property CONFIG.CONST_WIDTH {4} [get_bd_cells const_led]
connect_bd_net [get_bd_pins const_led/dout] [get_bd_ports led]

# 按键输入（悬空，暂不使用）
create_bd_port -dir I -from 3 -to 0 key

# =====================================================================
# 10. 地址映射
# =====================================================================
assign_bd_address

# =====================================================================
# 11. 验证并保存
# =====================================================================
validate_bd_design
save_bd_design

# 生成 Wrapper
make_wrapper -files [get_files system.bd] -top

# 用绝对路径添加 wrapper（避免 glob 匹配失败）
set wrapper_path [file normalize \
    "$project_dir/$project_name/${project_name}.gen/sources_1/bd/system/hdl/system_wrapper.v"]
if {[file exists $wrapper_path]} {
    add_files -norecurse $wrapper_path
    set_property top system_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    puts "INFO: Wrapper added: $wrapper_path"
} else {
    # 兜底：搜索工程目录下所有 system_wrapper.v
    set found [glob -nocomplain "$project_dir/$project_name/*.gen/sources_1/bd/system/hdl/system_wrapper.v"]
    if {$found ne ""} {
        add_files -norecurse [lindex $found 0]
        set_property top system_wrapper [current_fileset]
        update_compile_order -fileset sources_1
        puts "INFO: Wrapper added: [lindex $found 0]"
    } else {
        puts "WARNING: system_wrapper.v not found. Please add manually via Add Sources."
    }
}
set_property top system_wrapper [current_fileset]

puts ""
puts "============================================"
puts " Block Design 创建完成!"
puts ""
puts " 数据链路:"
puts "   AN9238 (64MHz) → an9238_axis → CIC_0 (5x) → CIC_1 (5x) → CLK_CONV → DMA → DDR"
puts "   GPIO → dac_out (DDS/TRI/SEL) → AN9767 (125MHz)"
puts ""
puts " 所有模块已完整连线，包括："
puts "   - an9238_axis (ADC 驱动，RTL module)"
puts "   - dac_out (DAC 输出，RTL module)"
puts "   - 64MHz 域独立复位 (rst_ps7_64M)"
puts "   - CIC 级联 25x 抽取"
puts "   - AXIS 时钟域转换 (64MHz → 50MHz)"
puts "   - AXI4→AXI3 SmartConnect (DMA → HP0)"
puts "============================================"
