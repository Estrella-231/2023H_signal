`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AN9238 / AD9238 dual-channel AXI-Stream source.
//
// The two ADC channels are sampled on adc_clk and exported as two 16-bit
// signed AXI-Stream channels. Each output keeps a pending flag so CH1 and CH2
// do not get duplicated or misaligned if only one CIC input deasserts TREADY.
//////////////////////////////////////////////////////////////////////////////

module an9238_axis (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 64000000, PHASE 0.0, ASSOCIATED_RESET rst_n, ASSOCIATED_BUSIF M_AXIS_CH1:M_AXIS_CH2" *)
    input  wire        adc_clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_n,

    input  wire [11:0] ad1_in,
    input  wire [11:0] ad2_in,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ad1_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 64000000, PHASE 0.0" *)
    output wire        ad1_clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ad2_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 64000000, PHASE 0.0" *)
    output wire        ad2_clk,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH1 TDATA" *)
    output wire [15:0] m_ch1_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH1 TVALID" *)
    output wire        m_ch1_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CH1 TREADY" *)
    input  wire        m_ch1_tready,

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
    reg        ch1_pending;
    reg        ch2_pending;

    wire ch1_accept = ch1_pending && m_ch1_tready;
    wire ch2_accept = ch2_pending && m_ch2_tready;

    wire ch1_empty_next = !ch1_pending || ch1_accept;
    wire ch2_empty_next = !ch2_pending || ch2_accept;
    wire sample_empty_next = ch1_empty_next && ch2_empty_next;

    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) begin
            ch1_s16     <= 16'd0;
            ch2_s16     <= 16'd0;
            ch1_pending <= 1'b0;
            ch2_pending <= 1'b0;
        end else begin
            if (ch1_accept)
                ch1_pending <= 1'b0;

            if (ch2_accept)
                ch2_pending <= 1'b0;

            if (sample_empty_next) begin
                ch1_s16     <= {{4{ch1_signed_next[11]}}, ch1_signed_next};
                ch2_s16     <= {{4{ch2_signed_next[11]}}, ch2_signed_next};
                ch1_pending <= 1'b1;
                ch2_pending <= 1'b1;
            end
        end
    end

    assign m_ch1_tdata  = ch1_s16;
    assign m_ch1_tvalid = ch1_pending;

    assign m_ch2_tdata  = ch2_s16;
    assign m_ch2_tvalid = ch2_pending;

endmodule
