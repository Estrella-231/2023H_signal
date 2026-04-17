`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AXIS TLAST Generator
//
// 每 PKT_LEN 个有效拍在最后一拍置 tlast=1，形成固定长度数据包
// 供 AXI DMA S2MM 使用。
//////////////////////////////////////////////////////////////////////////////
module axis_tlast_gen #(
    parameter DATA_WIDTH = 32,
    parameter PKT_LEN    = 1024
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 50000000" *)
    input  wire                   aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                   aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [DATA_WIDTH-1:0]  s_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire                   s_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire                   s_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [DATA_WIDTH-1:0]  m_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire                   m_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire                   m_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire                   m_tready
);

    // 透传，不缓存
    assign m_tdata  = s_tdata;
    assign m_tvalid = s_tvalid;
    assign s_tready = m_tready;

    // 计数器：每 PKT_LEN 个成功握手（valid & ready）置一次 tlast
    reg [$clog2(PKT_LEN)-1:0] cnt;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            cnt <= 0;
        else if (s_tvalid && m_tready) begin
            if (cnt == PKT_LEN - 1)
                cnt <= 0;
            else
                cnt <= cnt + 1;
        end
    end

    assign m_tlast = s_tvalid && (cnt == PKT_LEN - 1);

endmodule
