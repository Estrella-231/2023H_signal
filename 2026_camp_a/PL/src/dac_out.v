`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// DAC 输出顶层模块 -- AN9767 (AD9767) 双通道 14-bit
//
// 功能：
//   - 双通道 DDS 正弦波生成（由 PS 通过 AXI GPIO 设置频率字/相位字）
//   - 双通道三角波生成（由 PS 通过 AXI GPIO 设置步长）
//   - 波形选择 MUX（PS 通过 AXI GPIO 控制）
//   - 输出 14-bit 数据 + 时钟/写使能给 AN9767
//
// 时钟：
//   - cfg_clk = 50MHz PS/AXI GPIO 配置域
//   - dac_clk = 125MHz DAC 波形域（由外部 PLL 提供）
//////////////////////////////////////////////////////////////////////////////
module dac_out (
    input  wire        dac_clk,        // 125MHz DAC 时钟
    input  wire        rst_n,          // DAC 域低电平复位
    input  wire        cfg_clk,        // AXI GPIO 配置域时钟
    input  wire        cfg_rst_n,      // AXI GPIO 配置域低电平复位

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
    // AXI GPIO 配置跨时钟域
    // =====================================================================
    localparam CFG_BUS_WIDTH = 194;    // 6*32-bit + 2*1-bit

    wire [CFG_BUS_WIDTH-1:0] cfg_bus_cfg;
    wire [CFG_BUS_WIDTH-1:0] cfg_bus_dac;

    wire [31:0] dds_a_freq_dac;
    wire [31:0] dds_a_phase_dac;
    wire [31:0] tri_a_step_dac;
    wire [31:0] dds_b_freq_dac;
    wire [31:0] dds_b_phase_dac;
    wire [31:0] tri_b_step_dac;
    wire        wave_sel_a_dac;
    wire        wave_sel_b_dac;

    assign cfg_bus_cfg = {
        dds_a_freq,
        dds_a_phase,
        tri_a_step,
        dds_b_freq,
        dds_b_phase,
        tri_b_step,
        wave_sel_a,
        wave_sel_b
    };

    assign {
        dds_a_freq_dac,
        dds_a_phase_dac,
        tri_a_step_dac,
        dds_b_freq_dac,
        dds_b_phase_dac,
        tri_b_step_dac,
        wave_sel_a_dac,
        wave_sel_b_dac
    } = cfg_bus_dac;

    config_bus_cdc #(
        .WIDTH (CFG_BUS_WIDTH)
    ) cfg_cdc_inst (
        .src_clk   (cfg_clk),
        .src_rst_n (cfg_rst_n),
        .src_data  (cfg_bus_cfg),
        .dst_clk   (dac_clk),
        .dst_rst_n (rst_n),
        .dst_data  (cfg_bus_dac)
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
    //   f_out = freq_word * 125MHz / 2^27
    // 相位字是固定偏移量，不参与每拍累加
    // =====================================================================
    // A 通道 DDS
    reg  [26:0] phase_acc_a;
    wire [13:0] sin_out_a;
    wire [26:0] phase_total_a;

    always @(posedge dac_clk) begin
        if (!rst_n)
            phase_acc_a <= 27'd0;
        else
            phase_acc_a <= phase_acc_a + dds_a_freq_dac[26:0];
    end

    // 相位偏移在查表地址上一次性加入（不影响频率）
    assign phase_total_a = phase_acc_a + dds_a_phase_dac[26:0];

    // 正弦查找表（取相位高 10 位作为地址）
    sin_lut sin_lut_a (
        .clk    (dac_clk),
        .addr   (phase_total_a[26:17]),  // 10-bit 地址 -> 1024 点
        .dout   (sin_out_a)              // 14-bit 输出
    );

    // B 通道 DDS
    reg  [26:0] phase_acc_b;
    wire [13:0] sin_out_b;
    wire [26:0] phase_total_b;

    always @(posedge dac_clk) begin
        if (!rst_n)
            phase_acc_b <= 27'd0;
        else
            phase_acc_b <= phase_acc_b + dds_b_freq_dac[26:0];
    end

    assign phase_total_b = phase_acc_b + dds_b_phase_dac[26:0];

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
        .step    (tri_a_step_dac),
        .tri_out (tri_out_a)
    );

    triangle #(
        .WIDTH   (32),
        .CNT_MAX (32'hFFFFFFFF)
    ) triangle_b (
        .clk     (dac_clk),
        .rst_n   (rst_n),
        .step    (tri_b_step_dac),
        .tri_out (tri_out_b)
    );

    // =====================================================================
    // 波形选择 MUX（复用 2023-H 的 selector.v）
    // =====================================================================
    selector #(.WIDTH(14)) sel_a (
        .dds_in    (sin_out_a),
        .tri_in    (tri_out_a),
        .which     (wave_sel_a_dac),   // 1=DDS, 0=TRI
        .signal_out(da1_data)
    );

    selector #(.WIDTH(14)) sel_b (
        .dds_in    (sin_out_b),
        .tri_in    (tri_out_b),
        .which     (wave_sel_b_dac),
        .signal_out(da2_data)
    );

endmodule

//////////////////////////////////////////////////////////////////////////////
// 配置总线 CDC
//
// AXI GPIO 输出在 cfg_clk 域更新，DAC 波形逻辑运行在 dac_clk 域。这里用
// toggle/ack 握手让多 bit 配置总线在源域保持稳定，目标域只在完整事务到达后
// 一次性采样，避免简单逐 bit 双触发同步带来的频率字/相位字撕裂。
//////////////////////////////////////////////////////////////////////////////
module config_bus_cdc #(
    parameter WIDTH = 1
)(
    input  wire             src_clk,
    input  wire             src_rst_n,
    input  wire [WIDTH-1:0] src_data,
    input  wire             dst_clk,
    input  wire             dst_rst_n,
    output reg  [WIDTH-1:0] dst_data
);

    reg [WIDTH-1:0] src_hold;
    reg             src_req;
    reg             dst_ack;
    reg             dst_req_seen;

    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync_src;
    (* ASYNC_REG = "TRUE" *) reg [1:0] req_sync_dst;

    always @(posedge src_clk) begin
        if (!src_rst_n) begin
            src_hold     <= {WIDTH{1'b0}};
            src_req      <= 1'b0;
            ack_sync_src <= 2'b00;
        end else begin
            ack_sync_src <= {ack_sync_src[0], dst_ack};

            if ((ack_sync_src[1] == src_req) && (src_data != src_hold)) begin
                src_hold <= src_data;
                src_req  <= ~src_req;
            end
        end
    end

    always @(posedge dst_clk) begin
        if (!dst_rst_n) begin
            dst_data     <= {WIDTH{1'b0}};
            dst_ack      <= 1'b0;
            dst_req_seen <= 1'b0;
            req_sync_dst <= 2'b00;
        end else begin
            req_sync_dst <= {req_sync_dst[0], src_req};

            if (req_sync_dst[1] != dst_req_seen) begin
                dst_data     <= src_hold;
                dst_req_seen <= req_sync_dst[1];
                dst_ack      <= req_sync_dst[1];
            end
        end
    end

endmodule

//////////////////////////////////////////////////////////////////////////////
// 正弦查找表（ROM）
// 1024 x 14-bit，存储 1/4 周期正弦波，通过对称性生成完整周期
// 输出范围：0 ~ 16383（unsigned，中点 8192）
//////////////////////////////////////////////////////////////////////////////
module sin_lut (
    input  wire        clk,
    input  wire [9:0]  addr,           // 10-bit 地址 (0~1023)
    output reg  [13:0] dout            // 14-bit 输出
);

    // 利用 1/4 对称性：只存 256 点，用地址高 2 位做象限映射
    wire [1:0] quadrant = addr[9:8];
    wire [7:0] lut_addr = quadrant[0] ? ~addr[7:0] : addr[7:0];

    reg [13:0] quarter_sin [0:255];    // 1/4 正弦表 (256 x 14-bit)

    // 初始化正弦表（综合时由 Vivado 推断为 ROM）
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            // sin(0..90 deg) 映射到 0..8191
            quarter_sin[i] = $rtoi(8191.0 * $sin(3.14159265358979 * i / 512.0) + 0.5);
        end
    end

    reg [1:0]  quadrant_d;
    reg [13:0] quarter_val;

    always @(posedge clk) begin
        quadrant_d  <= quadrant;
        quarter_val <= quarter_sin[lut_addr];

        case (quadrant_d)
            2'b00: dout <= 14'd8192 + quarter_val;  // 0~90 deg
            2'b01: dout <= 14'd8192 + quarter_val;  // 90~180 deg
            2'b10: dout <= 14'd8192 - quarter_val;  // 180~270 deg
            2'b11: dout <= 14'd8192 - quarter_val;  // 270~360 deg
        endcase
    end

endmodule
