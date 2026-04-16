# 2026 校电子设计竞赛 A 题现状与后续计划

日期：2026-04-16

## 目标

题目要求制作信号分离装置。外部双路信号源产生周期信号 A 和 B，频率范围 20 kHz 到 100 kHz，且 fA < fB，峰峰值均为 1 V。独立加法器产生混合信号 C=A+B。分离电路只能从 C 中恢复出 A' 和 B'，要求 A'、B' 相对 A、B 波形无明显失真，并能在示波器上稳定同频显示。

关键约束：

- 加法器必须是独立电路板，由移动电源供电。
- 加法器和分离电路之间只能连接 C 和 GND。
- 分离电路最多配置一个启动键。
- 设置完信号源参数后，允许按一次启动键，后续不能人工干预。
- 分离时间不大于 20 s。
- 需要预留 A、B、C、A'、B' 测试端口。

评分方向：

- 基本要求 1：制作增益为 1 的加法器，实现 C=A+B。
- 基本要求 2：A、B 均为正弦波，fA=50 kHz，fB=100 kHz，正确分离。
- 基本要求 3：A、B 均为正弦波，频率为 10 kHz 整数倍，正确分离。
- 发挥要求 1：A、B 为正弦波或三角波，频率为 5 kHz 整数倍，正确分离。
- 发挥要求 2：A、B 均为正弦波且 fB 是 fA 的整数倍时，设置并控制 B' 与 A' 的初相位差，范围 0 到 180 度，分辨率 10 度，误差不大于 10 度。

## 当前工程现状

当前主要工程在 `2026_camp_a` 下，结构上分为 PL 和 PS 两部分。

PL 当前目标架构：

```text
AN9238 ADC -> an9238_axis -> CIC decimation -> AXIS clock conversion
           -> AXIS combiner -> AXI DMA S2MM -> Zynq PS DDR

Zynq PS -> AXI GPIO -> dac_out -> AN9767 DAC
```

已经具备的 PL 部分：

- `an9238_axis.v`：AN9238 双通道 ADC RTL 采样模块，把两个 12-bit 通道扩展并打包成 32-bit 数据。
- `dac_out.v`：AN9767 双通道 DAC 输出模块，内部包含正弦 DDS、三角波发生和波形选择。
- `axis_tlast_gen.v`：固定长度 AXIS 包 TLAST 发生器，目标是给 AXI DMA S2MM 提供帧边界。
- `build.tcl`：尝试自动生成 Zynq PS、DMA、SmartConnect、CIC、AXI GPIO、ADC/DAC RTL module 和外部端口。
- `ax7010.xdc`：包含 AN9238、AN9767、LED、按键等管脚约束。

已经具备的 PS 部分：

- `PS/src/main.c`：主循环中调用采样、FFT、A/B 参数识别和 DAC 配置。
- `PS/src/adc_dma.c`：AXI DMA S2MM 接收 ADC 数据，并把 32-bit 样本解包为浮点电压数组。
- `PS/src/amp_freq.c`：包含核心算法函数：
  - `get_fft()`：采样后做 FFT。
  - `get_ab()`：根据频谱峰判断 A/B 频率和波形类型。
  - `set_dac_freq()`：配置 DAC 输出频率、相位和波形。
  - `comp_phase()`：用于相位补偿闭环。
- `PS/src/ne10/`：NE10 DSP 库，用于 FFT。

重要结论：

PS 软件算法不是从零缺失。它已经从 `2023-H` 搬入了主体代码。当前问题是“移植和验证未完成”，不是“没有算法”。

## 当前主要缺口

### 1. PL 构建还需要收敛

当前 `build.tcl` 已经在朝正确方向改，但还需要重点检查：

- `axis_tlast_gen.v` 需要加入 `add_files`，否则 `create_bd_cell -type module -reference axis_tlast_gen` 可能找不到模块。
- `axis_tlast_gen.v` 没有 AXIS interface 属性时，Vivado 可能不会自动生成 `S_AXIS` 和 `M_AXIS` bundle 接口。可以选择：
  - 给 RTL 端口加 `X_INTERFACE_INFO` 属性；
  - 或在 `build.tcl` 中用 `connect_bd_net` 连接散线端口。
- 当前 ADC 输出拆成 CH1/CH2 两路 CIC 后，只把 CH1 的 `tready` 反馈给 `adc_inst/m_axis_tready`。如果 CH2 反压不同步，可能破坏 AXIS 握手。更稳的方案是两路前面加 FIFO，或把两个 `tready` 做 AND，再反馈给 ADC。
- `an9238_axis.v` 注释说遵守 backpressure，但实际寄存器仍然每个 `adc_clk` 更新。连续 ADC 场景如果下游 `tready=0`，会丢样或违反 AXIS 保持规则。需要明确策略：
  - 允许丢样：不要把它声明成严格 AXIS source；
  - 不允许丢样：加入 FIFO 或握手保持逻辑。
- `axis_combiner` 的 TDATA 字节数、输入顺序和输出 `{ch2,ch1}` 格式需要用仿真或 BD validate 确认。
- 生成 XSA 后必须重新导入 Vitis/SDK，让 `xparameters.h` 和当前 PL 完全一致。

### 2. PS 与当前 PL 外设名不匹配

这是当前最容易导致 PS 编译失败或运行失败的点。

`amp_freq.c` 仍在使用 2023-H 的外设宏，例如：

```c
XPAR_A_B_OUT_A_B_TRI_DEVICE_ID
XPAR_A_B_OUT_A_B_WHICH_DEVICE_ID
XPAR_A_B_OUT_A_DDS_DEVICE_ID
XPAR_A_B_OUT_B_DDS_DEVICE_ID
XPAR_SYNC1_AXI_GPIO_0_DEVICE_ID
XPAR_PHASE_GPIO_DEVICE_ID
```

而当前 `build.tcl` 创建的是：

```text
gpio_a_dds_freq
gpio_a_dds_phase
gpio_b_dds_freq
gpio_b_dds_phase
gpio_a_tri_step
gpio_b_tri_step
gpio_wave_ctrl
gpio_phase_read
```

需要二选一：

- 方案 A：修改 `amp_freq.c`，让 PS 代码适配当前 8 个单通道 GPIO。
- 方案 B：修改 `build.tcl`，把 GPIO cell 命名和通道结构尽量恢复成 2023-H 旧接口，减少 PS 改动。

建议采用方案 A。当前 PL 结构更清晰，PS 侧只需要重写 GPIO 初始化和 `set_dac_freq()` 写寄存器逻辑。

### 3. 正式比赛流程还没从“调试循环”改成“一键运行”

当前 `main.c` 是无限循环：

```text
package_process()
get_fft()
get_ab()
set_dac_freq()
send_ab_information()
```

这适合调试，但比赛约束要求：

- 设置过程中不触碰分离电路；
- 设置完成后只按一次启动键；
- 后续无人干预；
- 20 s 内完成分离。

后续需要改成状态机：

```text
WAIT_START -> CAPTURE -> ANALYZE -> CONFIG_DAC -> OUTPUT_HOLD
```

屏幕和串口可以保留为调试手段，但正式测试时应避免依赖人工交互。

### 4. 输入通道要严格按题目约束使用

题目中分离电路只能输入混合信号 C。当前 ADC 模块是双通道，PS 解包为 `sin_volt` 和 `cos_volt` 两组数组。正式测试时必须保证：

- CH1 接 C，作为算法输入；
- CH2 不能接 A 或 B 作为参考；
- 如果 CH2 暂时不用，应在文档和接线上说明只作调试预留或悬空处理。

否则即使算法能跑，也不符合题目规则。

### 5. 模拟电路还没有闭环确认

除了 Zynq 和 FPGA，还必须有这些硬件部分：

- 独立加法器板：实现 C=A+B，增益为 1，独立供电，只和分离电路连接 C 和 GND。
- ADC 前端：C 输入缓冲、电平偏置、保护、抗混叠滤波、输入阻抗匹配。
- DAC 后端：重构低通滤波、输出缓冲、幅度调节、偏置处理。
- 测试端口：A、B、C、A'、B'。
- 启动键和状态指示：至少一个 Start key，以及若干 LED 状态输出。

当前数字工程不能替代这些模拟链路。尤其是幅度“峰峰值不小于 1 V”和“波形无失真”，最终主要靠 ADC/DAC 模拟前后端和标定保证。

## 推荐后续路线

### 阶段 0：先让工程可构建

目标：`source build.tcl` 能完成，`validate_bd_design` 通过，能生成 bitstream 和 XSA。

任务：

- 把 `axis_tlast_gen.v` 加入 `build.tcl` 的 `add_files`。
- 修正 `axis_tlast_gen` 的 BD 接口连接方式。
- 检查 ADC 到双 CIC 到 DMA 的 AXIS 握手。
- 检查 AXI GPIO 全部能分配地址。
- 清理 XDC 中和当前顶层端口不匹配的旧约束。
- 生成 bitstream 和 XSA。

验收：

- Vivado BD validate 无 error。
- 综合、实现、bitstream 生成通过。
- 导出 XSA 后 Vitis 能生成新的 `xparameters.h`。

### 阶段 1：完成 PS 移植适配

目标：2023-H 搬来的算法能在当前 2026 PL 上编译运行。

任务：

- 根据新 XSA 更新 BSP。
- 修改 `amp_freq.c` 的 GPIO 宏和 `dac_gpio_init()`。
- 修改 `set_dac_freq()`，适配当前 `gpio_a_dds_freq/gpio_a_dds_phase/...`。
- 暂时禁用或改造旧的 `sync1`、`phase_gpio` 依赖。
- 确认 `adc_dma.c` 的样本数、字节数和 cache invalidate 流程正确。
- 让 `main.c` 先保留调试循环，能打印识别到的 A/B 频率和波形。

验收：

- PS 工程编译通过。
- DMA 能采样到 C。
- 对 50 kHz + 100 kHz 正弦混合信号，能识别出两个频率。
- DAC 能输出对应 A'、B'。

### 阶段 2：基本要求闭环

目标：先拿基本分。

任务：

- 输入 50 kHz 和 100 kHz 正弦，验证 A'、B' 频率稳定。
- 扩展到 10 kHz 整数倍频率组合。
- 做 ADC 幅度标定和 DAC 幅度标定。
- 固定输出幅度，使 A'、B' 峰峰值不小于 1 V。
- 用示波器确认 A 与 A'、B 与 B' 稳定同频显示。

验收：

- 基本要求 2 通过。
- 基本要求 3 的典型组合通过，例如 20/30、30/70、50/100 kHz。
- 输出无明显削顶、失真或漂移。

### 阶段 3：发挥要求 1，支持三角波

目标：支持 A、B 为正弦或三角，频率为 5 kHz 整数倍。

任务：

- 完善 `get_ab()` 的三角波判别逻辑。
- 对三角波的 3f、5f、7f 谐波做规则判断，避免把谐波误判为另一路信号。
- 处理 fB 是 fA 整数倍时的谐波重叠。
- 校准 `triangle.v` 的频率步进公式和实际输出频率。
- 检查 DAC 后端低通是否会削弱三角波高次谐波，导致三角波看起来失真。

验收：

- 正弦+正弦、正弦+三角、三角+正弦、三角+三角都能分离。
- 5 kHz 网格频率组合能稳定识别。
- 输出三角波幅度和形状满足示波器观察要求。

### 阶段 4：发挥要求 2，相位控制

目标：B' 与 A' 初相位差可控，0 到 180 度，10 度分辨率，误差不大于 10 度。

任务：

- 明确比赛时目标相位差如何设置，避免违反“唯一启动键”约束。
- 让 A/B DDS 使用统一启动同步信号，保证相位起点确定。
- 修复或重建 PL 相位测量模块，给 PS 提供相位反馈。
- 在 PS 中加入相位字计算和补偿表。
- 标定 DAC 通道、模拟滤波器和输出缓冲造成的相位偏移。

验收：

- 设置 0、30、60、90、120、150、180 度时，示波器测量误差不大于 10 度。
- 频率变化后相位控制仍稳定。

### 阶段 5：正式化和报告

目标：形成可测试、可展示、可写报告的完整系统。

任务：

- 正式流程改为一键状态机。
- LED 显示等待、采样、分析、输出、错误状态。
- 固化测试用例表。
- 保存示波器截图或波形记录。
- 写清楚方案论证、分离理论、相位控制方法、测试结果和误差分析。

验收：

- 开机后等待启动键。
- 按键一次后 20 s 内稳定输出。
- 不需要屏幕或串口人工干预。
- 报告中每个评分点都有对应测试数据。

## 近期最优先任务

优先级从高到低：

1. 修 `build.tcl`，让 PL 工程能稳定构建并导出 XSA。
2. 用新 XSA 更新 Vitis/SDK BSP，确认 `xparameters.h` 外设宏。
3. 改 `amp_freq.c` 的 GPIO 适配层，让 PS 能控制当前 `dac_out`。
4. 用单一输入 C 跑通 50 kHz + 100 kHz 正弦的识别和输出。
5. 再扩展 10 kHz 网格、5 kHz 网格、三角波和相位控制。

## 当前风险清单

| 风险 | 影响 | 处理建议 |
| --- | --- | --- |
| PS 外设宏和 PL cell 名不匹配 | PS 编译失败或写错外设 | 重新导出 XSA，按新 `xparameters.h` 改 `amp_freq.c` |
| AXIS 握手不严格 | DMA 数据错位、丢样、频谱异常 | 加 FIFO 或明确丢样策略，仿真验证 |
| 只用 CH1 还是双通道输入不清晰 | 可能违反题目规则 | 正式方案只让 C 进入算法 |
| 模拟前端未标定 | 幅度不准、失真、削顶 | 做 ADC/DAC 幅度和偏置标定 |
| 三角波谐波重叠 | 波形类型和频率误判 | 用谐波模板和 5 kHz 网格规则判别 |
| 相位控制没有统一同步 | B' 与 A' 相位漂移 | 加 DDS 同步启动和相位补偿 |
| HMI/串口依赖人工交互 | 不满足一键测试要求 | 正式模式改成 Start key 状态机 |

## 一句话结论

现在已经有比较完整的数字处理雏形，也已经搬入了 2023-H 的 PS 算法主体。下一步的重点不是继续堆 IP，而是把 PL 构建、PS 外设适配、单输入 C 的正弦分离闭环跑通；跑通基本要求后，再做三角波识别、相位控制和模拟链路标定。
