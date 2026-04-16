`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AN9238 (AD9238) AXI-Stream Driver — 双通道独立输出版本
//
// 输出两路独立 AXI-Stream，每路 16-bit，分别对应 CH1(sin) 和 CH2(cos)。
// 两路共享同一个 tvalid，tready 取 ch1 的（两路 CIC 速率相同）。
//
// Backpressure: 当 m_ch1_tready=0 时，寄存器保持，新 ADC 采样被丢弃。
//////////////////////////////////////////////////////////////////////////////

module an9238_axis (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 65000000, PHASE 0.0, CLK_DOMAIN adc_clk" *)
    input  wire        adc_clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_n,

    // AN9238 并口接口
    input  wire [11:0] ad1_in,
    input  wire [11:0] ad2_in,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ad1_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 65000000, PHASE 0.0, CLK_DOMAIN adc_clk" *)
    output wire        ad1_clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ad2_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 65000000, PHASE 0.0, CLK_DOMAIN adc_clk" *)
    output wire        ad2_clk,

    // CH1 AXI-Stream 输出 (sin 通道)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH1 TDATA" *)
    output wire [15:0] m_ch1_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH1 TVALID" *)
    output wire        m_ch1_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH1 TREADY" *)
    input  wire        m_ch1_tready,

    // CH2 AXI-Stream 输出 (cos 通道)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH2 TDATA" *)
    output wire [15:0] m_ch2_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH2 TVALID" *)
    output wire        m_ch2_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH2 TREADY" *)
    input  wire        m_ch2_tready
);

    assign ad1_clk = adc_clk;
    assign ad2_clk = adc_clk;

    wire signed [11:0] ch1_signed_next = {~ad1_in[11], ad1_in[10:0]};
    wire signed [11:0] ch2_signed_next = {~ad2_in[11], ad2_in[10:0]};

    reg [15:0] ch1_s16;
    reg [15:0] ch2_s16;
    reg        data_valid;

    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) begin
            ch1_s16    <= 16'd0;
            ch2_s16    <= 16'd0;
            data_valid <= 1'b0;
        end
        else if (!data_valid || m_ch1_tready) begin
            // 12-bit 符号扩展到 16-bit（左移4位保持量级）
            ch1_s16    <= {{4{ch1_signed_next[11]}}, ch1_signed_next};
            ch2_s16    <= {{4{ch2_signed_next[11]}}, ch2_signed_next};
            data_valid <= 1'b1;
        end
    end

    assign m_ch1_tdata  = ch1_s16;
    assign m_ch1_tvalid = data_valid;

    assign m_ch2_tdata  = ch2_s16;
    assign m_ch2_tvalid = data_valid;

endmodule
