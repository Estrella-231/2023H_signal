`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// DAC 输出顶层模块 — AN9767 (AD9767) 双通道 14-bit
//
// 功能：
//   - 双通道 DDS 正弦波生成（由 PS 通过 AXI GPIO 设置频率字/相位字）
//   - 双通道三角波生成（由 PS 通过 AXI GPIO 设置步长）
//   - 波形选择 MUX（PS 通过 AXI GPIO 控制）
//   - 输出 14-bit 数据 + 时钟/写使能给 AN9767
//
// 时钟：dac_clk = 125MHz（由外部 PLL 提供）
//////////////////////////////////////////////////////////////////////////////
module dac_out (
    input  wire        dac_clk,        // 125MHz DAC 时钟
    input  wire        rst_n,          // 低电平复位

    // DDS A 通道参数（来自 AXI GPIO）
    input  wire [31:0] dds_a_freq,     // A 通道频率字（27-bit 有效）
    input  wire [31:0] dds_a_phase,    // A 通道相位字
    input  wire [31:0] tri_a_step,     // A 三角波步长

    // DDS B 通道参数（来自 AXI GPIO）
    input  wire [31:0] dds_b_freq,     // B 通道频率字
    input  wire [31:0] dds_b_phase,    // B 通道相位字
    input  wire [31:0] tri_b_step,     // B 三角波步长

    // 波形选择（来自 AXI GPIO）
    input  wire        wave_sel_a,     // 1=DDS(正弦), 0=三角波
    input  wire        wave_sel_b,     // 1=DDS(正弦), 0=三角波

    // AN9767 通道 A 接口
    output wire [13:0] da1_data,
    output wire        da1_clk,
    output wire        da1_wrt,

    // AN9767 通道 B 接口
    output wire [13:0] da2_data,
    output wire        da2_clk,
    output wire        da2_wrt
);

    // =====================================================================
    // DAC 时钟和写使能
    // =====================================================================
    // AN9767 使用 CLK 上升沿锁存数据，WRT 与 CLK 同相
    assign da1_clk = dac_clk;
    assign da1_wrt = dac_clk;
    assign da2_clk = dac_clk;
    assign da2_wrt = dac_clk;

    // =====================================================================
    // DDS 正弦波生成器（相位累加器 + 正弦查找表）
    // 频率字计算基准：dac_clk = 125MHz
    //   f_out = freq_word × 125MHz / 2^27
    // 相位字是固定偏移量，不参与每拍累加
    // =====================================================================
    // A 通道 DDS
    reg  [26:0] phase_acc_a;           // 27-bit 相位累加器
    wire [13:0] sin_out_a;
    wire [26:0] phase_total_a;

    always @(posedge dac_clk or negedge rst_n) begin
        if (!rst_n)
            phase_acc_a <= 27'd0;
        else
            phase_acc_a <= phase_acc_a + dds_a_freq[26:0];  // 只累加频率字
    end

    // 相位偏移在查表地址上一次性加入（不影响频率）
    assign phase_total_a = phase_acc_a + dds_a_phase[26:0];

    // 正弦查找表（取相位高 10 位作为地址）
    sin_lut sin_lut_a (
        .clk    (dac_clk),
        .addr   (phase_total_a[26:17]),  // 10-bit 地址 → 1024 点
        .dout   (sin_out_a)              // 14-bit 输出
    );

    // B 通道 DDS
    reg  [26:0] phase_acc_b;
    wire [13:0] sin_out_b;
    wire [26:0] phase_total_b;

    always @(posedge dac_clk or negedge rst_n) begin
        if (!rst_n)
            phase_acc_b <= 27'd0;
        else
            phase_acc_b <= phase_acc_b + dds_b_freq[26:0];  // 只累加频率字
    end

    assign phase_total_b = phase_acc_b + dds_b_phase[26:0];

    sin_lut sin_lut_b (
        .clk    (dac_clk),
        .addr   (phase_total_b[26:17]),
        .dout   (sin_out_b)
    );

    // =====================================================================
    // 三角波生成器（复用 2023-H 的 triangle.v）
    // =====================================================================
    wire [13:0] tri_out_a;
    wire [13:0] tri_out_b;

    triangle #(
        .WIDTH   (32),
        .CNT_MAX (32'hFFFFFFFF)
    ) triangle_a (
        .clk     (dac_clk),
        .rst_n   (rst_n),
        .step    (tri_a_step),
        .tri_out (tri_out_a)
    );

    triangle #(
        .WIDTH   (32),
        .CNT_MAX (32'hFFFFFFFF)
    ) triangle_b (
        .clk     (dac_clk),
        .rst_n   (rst_n),
        .step    (tri_b_step),
        .tri_out (tri_out_b)
    );

    // =====================================================================
    // 波形选择 MUX（复用 2023-H 的 selector.v）
    // =====================================================================
    selector #(.WIDTH(14)) sel_a (
        .dds_in    (sin_out_a),
        .tri_in    (tri_out_a),
        .which     (wave_sel_a),       // 1=DDS, 0=TRI
        .signal_out(da1_data)
    );

    selector #(.WIDTH(14)) sel_b (
        .dds_in    (sin_out_b),
        .tri_in    (tri_out_b),
        .which     (wave_sel_b),
        .signal_out(da2_data)
    );

endmodule

//////////////////////////////////////////////////////////////////////////////
// 正弦查找表（ROM）
// 1024 × 14-bit，存储 1/4 周期正弦波，通过对称性生成完整周期
// 输出范围：0 ~ 16383（unsigned，中点 8192）
//////////////////////////////////////////////////////////////////////////////
module sin_lut (
    input  wire        clk,
    input  wire [9:0]  addr,           // 10-bit 地址 (0~1023)
    output reg  [13:0] dout            // 14-bit 输出
);

    // 利用 1/4 对称性：只存 256 点，用地址高 2 位做象限映射
    wire [1:0]  quadrant = addr[9:8];
    wire [7:0]  lut_addr = (quadrant[0]) ? ~addr[7:0] : addr[7:0];

    reg  [13:0] quarter_sin [0:255];   // 1/4 正弦表 (256 × 14-bit)

    // 初始化正弦表（综合时由 Vivado 推断为 BRAM 或 LUT ROM）
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            // sin(0..90°) 映射到 0..8191
            // quarter_sin[i] = round(8191 * sin(i * π / 512))
            quarter_sin[i] = $rtoi(8191.0 * $sin(3.14159265358979 * i / 512.0));
        end
    end

    reg [13:0] quarter_val;

    always @(posedge clk) begin
        quarter_val <= quarter_sin[lut_addr];

        // 象限映射
        case (quadrant)
            2'b00: dout <= 14'd8192 + quarter_val;           // 0°~90°
            2'b01: dout <= 14'd8192 + quarter_val;           // 90°~180° (对称)
            2'b10: dout <= 14'd8192 - quarter_val;           // 180°~270°
            2'b11: dout <= 14'd8192 - quarter_val;           // 270°~360° (对称)
        endcase
    end

endmodule
