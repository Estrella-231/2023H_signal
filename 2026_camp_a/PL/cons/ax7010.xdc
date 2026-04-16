##############################################################################
# AX7010 约束文件 — 2026 信号分离装置
# 目标芯片：XC7Z010-CLG400
# J1 扩展口 → AN9238 (AD9238, 12-bit 双通道 65MSPS)
# J2 扩展口 → AN9767 (AD9767, 14-bit 双通道 DAC)
##############################################################################

# ===========================================================================
# 时钟约束
# ===========================================================================
# ADC 时钟 65MHz (PLL 生成输出到 AN9238)
# create_clock -period 15.385 -name adc_clk [get_ports ad1_clk]

# ===========================================================================
# J1 扩展口 → AN9238 (AD9238) — Bank 35, LVCMOS33
# ===========================================================================
# AN9238 接口：2 × 12-bit 并口数据 + 2 个时钟输出

# --- CH1 12-bit 数据 ---
set_property PACKAGE_PIN W18 [get_ports {ad1_in[0]}]
set_property PACKAGE_PIN W19 [get_ports {ad1_in[1]}]
set_property PACKAGE_PIN P14 [get_ports {ad1_in[2]}]
set_property PACKAGE_PIN R14 [get_ports {ad1_in[3]}]
set_property PACKAGE_PIN Y16 [get_ports {ad1_in[4]}]
set_property PACKAGE_PIN Y17 [get_ports {ad1_in[5]}]
set_property PACKAGE_PIN V15 [get_ports {ad1_in[6]}]
set_property PACKAGE_PIN W15 [get_ports {ad1_in[7]}]
set_property PACKAGE_PIN W14 [get_ports {ad1_in[8]}]
set_property PACKAGE_PIN Y14 [get_ports {ad1_in[9]}]
set_property PACKAGE_PIN N17 [get_ports {ad1_in[10]}]
set_property PACKAGE_PIN P18 [get_ports {ad1_in[11]}]

set_property IOSTANDARD LVCMOS33 [get_ports {ad1_in[*]}]

# --- CH2 12-bit 数据 ---
set_property PACKAGE_PIN U14 [get_ports {ad2_in[0]}]
set_property PACKAGE_PIN U15 [get_ports {ad2_in[1]}]
set_property PACKAGE_PIN P15 [get_ports {ad2_in[2]}]
set_property PACKAGE_PIN P16 [get_ports {ad2_in[3]}]
set_property PACKAGE_PIN T16 [get_ports {ad2_in[4]}]
set_property PACKAGE_PIN U17 [get_ports {ad2_in[5]}]
set_property PACKAGE_PIN V17 [get_ports {ad2_in[6]}]
set_property PACKAGE_PIN V18 [get_ports {ad2_in[7]}]
set_property PACKAGE_PIN T14 [get_ports {ad2_in[8]}]
set_property PACKAGE_PIN T15 [get_ports {ad2_in[9]}]
set_property PACKAGE_PIN U13 [get_ports {ad2_in[10]}]
set_property PACKAGE_PIN V13 [get_ports {ad2_in[11]}]

set_property IOSTANDARD LVCMOS33 [get_ports {ad2_in[*]}]

# --- ADC 采样时钟输出 (65MHz, FPGA→AN9238) ---
set_property PACKAGE_PIN V12 [get_ports ad1_clk]
set_property PACKAGE_PIN T12 [get_ports ad2_clk]

set_property IOSTANDARD LVCMOS33 [get_ports ad1_clk]
set_property IOSTANDARD LVCMOS33 [get_ports ad2_clk]
set_property SLEW FAST [get_ports ad1_clk]
set_property SLEW FAST [get_ports ad2_clk]

# ===========================================================================
# J2 扩展口 → AN9767 (AD9767) — Bank 34, LVCMOS33
# ===========================================================================

# --- DAC 通道 A (DA1) 14-bit 数据 ---
set_property PACKAGE_PIN F16 [get_ports {da1_data[0]}]
set_property PACKAGE_PIN F17 [get_ports {da1_data[1]}]
set_property PACKAGE_PIN F19 [get_ports {da1_data[2]}]
set_property PACKAGE_PIN F20 [get_ports {da1_data[3]}]
set_property PACKAGE_PIN G19 [get_ports {da1_data[4]}]
set_property PACKAGE_PIN G20 [get_ports {da1_data[5]}]
set_property PACKAGE_PIN J18 [get_ports {da1_data[6]}]
set_property PACKAGE_PIN H18 [get_ports {da1_data[7]}]
set_property PACKAGE_PIN L19 [get_ports {da1_data[8]}]
set_property PACKAGE_PIN L20 [get_ports {da1_data[9]}]
set_property PACKAGE_PIN M19 [get_ports {da1_data[10]}]
set_property PACKAGE_PIN M20 [get_ports {da1_data[11]}]
set_property PACKAGE_PIN K17 [get_ports {da1_data[12]}]
set_property PACKAGE_PIN K18 [get_ports {da1_data[13]}]

set_property IOSTANDARD LVCMOS33 [get_ports {da1_data[*]}]

# --- DAC 通道 A 时钟和写使能 ---
set_property PACKAGE_PIN K19 [get_ports da1_clk]
set_property PACKAGE_PIN J19 [get_ports da1_wrt]

set_property IOSTANDARD LVCMOS33 [get_ports da1_clk]
set_property IOSTANDARD LVCMOS33 [get_ports da1_wrt]

# --- DAC 通道 B (DA2) 14-bit 数据 ---
set_property PACKAGE_PIN J20 [get_ports {da2_data[0]}]
set_property PACKAGE_PIN H20 [get_ports {da2_data[1]}]
set_property PACKAGE_PIN L16 [get_ports {da2_data[2]}]
set_property PACKAGE_PIN L17 [get_ports {da2_data[3]}]
set_property PACKAGE_PIN M17 [get_ports {da2_data[4]}]
set_property PACKAGE_PIN M18 [get_ports {da2_data[5]}]
set_property PACKAGE_PIN D19 [get_ports {da2_data[6]}]
set_property PACKAGE_PIN D20 [get_ports {da2_data[7]}]
set_property PACKAGE_PIN E18 [get_ports {da2_data[8]}]
set_property PACKAGE_PIN E19 [get_ports {da2_data[9]}]
set_property PACKAGE_PIN G17 [get_ports {da2_data[10]}]
set_property PACKAGE_PIN G18 [get_ports {da2_data[11]}]
set_property PACKAGE_PIN H16 [get_ports {da2_data[12]}]
set_property PACKAGE_PIN H17 [get_ports {da2_data[13]}]

set_property IOSTANDARD LVCMOS33 [get_ports {da2_data[*]}]

# --- DAC 通道 B 时钟和写使能 ---
set_property PACKAGE_PIN H15 [get_ports da2_clk]
set_property PACKAGE_PIN G15 [get_ports da2_wrt]

set_property IOSTANDARD LVCMOS33 [get_ports da2_clk]
set_property IOSTANDARD LVCMOS33 [get_ports da2_wrt]

# ===========================================================================
# LED（调试用）
# ===========================================================================
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN K16 [get_ports {led[2]}]
set_property PACKAGE_PIN J16 [get_ports {led[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# ===========================================================================
# 按键（调试用）
# ===========================================================================
set_property PACKAGE_PIN N15 [get_ports {key[0]}]
set_property PACKAGE_PIN N16 [get_ports {key[1]}]
set_property PACKAGE_PIN T17 [get_ports {key[2]}]
set_property PACKAGE_PIN R17 [get_ports {key[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {key[*]}]

# ===========================================================================
# IO 驱动强度和速率
# ===========================================================================
# DAC 高速输出需要 FAST slew rate
set_property SLEW FAST [get_ports {da1_data[*]}]
set_property SLEW FAST [get_ports {da2_data[*]}]
set_property SLEW FAST [get_ports da1_clk]
set_property SLEW FAST [get_ports da1_wrt]
set_property SLEW FAST [get_ports da2_clk]
set_property SLEW FAST [get_ports da2_wrt]

# ADC 时钟输出：FAST
set_property SLEW FAST [get_ports ad1_clk]
set_property SLEW FAST [get_ports ad2_clk]
