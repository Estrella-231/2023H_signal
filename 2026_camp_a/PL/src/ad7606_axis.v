`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AD7606 AXI-Stream Driver
//
// 基于 AN706 示例改造，添加 AXI-Stream 主机输出接口
// 功能：驱动 AD7606 并口采样，将 CH1+CH2 打包为 32-bit AXI-Stream 输出
//       {ch2[15:0], ch1[15:0]} → m_axis_tdata[31:0]
//
// 采样率控制：CONV_WAIT_CYCLES 参数决定采样间隔
//   50MHz 时钟下：CONV_WAIT_CYCLES=250 → 200kSPS
//                 CONV_WAIT_CYCLES=500 → 100kSPS
//////////////////////////////////////////////////////////////////////////////
module ad7606_axis #(
    parameter CONV_WAIT_CYCLES = 250   // 采样间隔（时钟周期数），默认 200kSPS @ 50MHz
)(
    input  wire        clk,            // 50MHz 系统时钟
    input  wire        rst_n,          // 低电平复位

    // AD7606 并口接口
    input  wire [15:0] ad_data,        // AD7606 16-bit 并口数据
    input  wire        ad_busy,        // AD7606 BUSY 标志
    input  wire        first_data,     // AD7606 第一个数据标志
    output wire [2:0]  ad_os,          // 过采样倍率选择 (000=无过采样)
    output reg         ad_cs,          // 片选 (active low)
    output reg         ad_rd,          // 读使能 (active low)
    output reg         ad_reset,       // 复位 (active high)
    output reg         ad_convstab,    // 转换启动 (active low pulse)

    // AXI-Stream 主机输出
    output wire [31:0] m_axis_tdata,   // {ch2[15:0], ch1[15:0]}
    output reg         m_axis_tvalid,  // 数据有效
    input  wire        m_axis_tready,  // 下游就绪
    output reg         m_axis_tlast    // 帧结束标志（每次转换 = 1 帧）
);

    // 过采样关闭
    assign ad_os = 3'b000;

    // 状态定义
    localparam S_RESET      = 4'd0;    // 上电复位
    localparam S_IDLE       = 4'd1;    // 等待采样间隔
    localparam S_CONV       = 4'd2;    // 发起转换脉冲
    localparam S_WAIT_CONV  = 4'd3;    // 等待 CONVST 脉冲完成
    localparam S_WAIT_BUSY  = 4'd4;    // 等待 BUSY 下降沿
    localparam S_READ_CH1   = 4'd5;    // 读通道 1
    localparam S_READ_CH2   = 4'd6;    // 读通道 2
    localparam S_READ_CH3   = 4'd7;    // 读通道 3（跳过）
    localparam S_READ_CH4   = 4'd8;    // 读通道 4（跳过）
    localparam S_READ_CH5   = 4'd9;    // 读通道 5（跳过）
    localparam S_READ_CH6   = 4'd10;   // 读通道 6（跳过）
    localparam S_READ_CH7   = 4'd11;   // 读通道 7（跳过）
    localparam S_READ_CH8   = 4'd12;   // 读通道 8（跳过）
    localparam S_OUTPUT     = 4'd13;   // AXI-Stream 输出握手
    localparam S_DONE       = 4'd14;   // 单次完成

    reg [3:0]  state;
    reg [15:0] wait_cnt;               // 采样间隔计数器
    reg [3:0]  rd_cnt;                 // 读时序计数器（RD低电平持续周期数）
    reg [15:0] reset_cnt;              // 复位计数器

    // 通道数据锁存
    reg [15:0] ch1_data;
    reg [15:0] ch2_data;

    // AXI-Stream 数据输出：{ch2, ch1} 打包
    assign m_axis_tdata = {ch2_data, ch1_data};

    // =========================================================================
    // 主状态机
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_RESET;
            ad_cs         <= 1'b1;
            ad_rd         <= 1'b1;
            ad_reset      <= 1'b1;
            ad_convstab   <= 1'b1;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            wait_cnt      <= 16'd0;
            rd_cnt        <= 4'd0;
            reset_cnt     <= 16'd0;
            ch1_data      <= 16'd0;
            ch2_data      <= 16'd0;
        end
        else begin
            case (state)

            // ----- 上电复位：保持 ad_reset 高至少 50ns（3 clk @ 50MHz） -----
            S_RESET: begin
                ad_reset <= 1'b1;
                ad_cs    <= 1'b1;
                ad_rd    <= 1'b1;
                ad_convstab <= 1'b1;
                if (reset_cnt >= 16'd1000) begin  // 20us 复位
                    reset_cnt <= 16'd0;
                    ad_reset  <= 1'b0;
                    state     <= S_IDLE;
                end
                else begin
                    reset_cnt <= reset_cnt + 1'b1;
                end
            end

            // ----- 等待采样间隔 -----
            S_IDLE: begin
                ad_cs       <= 1'b1;
                ad_rd       <= 1'b1;
                ad_convstab <= 1'b1;
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;

                if (wait_cnt >= CONV_WAIT_CYCLES - 1) begin
                    wait_cnt <= 16'd0;
                    state    <= S_CONV;
                end
                else begin
                    wait_cnt <= wait_cnt + 1'b1;
                end
            end

            // ----- 发起转换：CONVST 低脉冲 ≥ 25ns（2 clk） -----
            S_CONV: begin
                ad_convstab <= 1'b0;     // 拉低启动转换
                if (rd_cnt >= 4'd2) begin
                    rd_cnt      <= 4'd0;
                    ad_convstab <= 1'b1;  // 释放
                    state       <= S_WAIT_CONV;
                end
                else begin
                    rd_cnt <= rd_cnt + 1'b1;
                end
            end

            // ----- 等待 BUSY 上升沿（转换开始） -----
            S_WAIT_CONV: begin
                if (rd_cnt >= 4'd5) begin  // 等待 100ns 让 BUSY 拉高
                    rd_cnt <= 4'd0;
                    state  <= S_WAIT_BUSY;
                end
                else begin
                    rd_cnt <= rd_cnt + 1'b1;
                end
            end

            // ----- 等待 BUSY 下降沿（转换完成，典型 3~4 us） -----
            S_WAIT_BUSY: begin
                if (ad_busy == 1'b0) begin
                    rd_cnt <= 4'd0;
                    state  <= S_READ_CH1;
                end
            end

            // ----- 读 CH1：RD 低脉冲 ≥ 20ns（2 clk），第 3 clk 锁存数据 -----
            S_READ_CH1: begin
                ad_cs <= 1'b0;
                if (rd_cnt == 4'd0) begin
                    ad_rd  <= 1'b0;
                    rd_cnt <= rd_cnt + 1'b1;
                end
                else if (rd_cnt <= 4'd2) begin
                    rd_cnt <= rd_cnt + 1'b1;
                end
                else begin
                    ch1_data <= ad_data;   // 锁存 CH1
                    ad_rd    <= 1'b1;
                    rd_cnt   <= 4'd0;
                    state    <= S_READ_CH2;
                end
            end

            // ----- 读 CH2 -----
            S_READ_CH2: begin
                if (rd_cnt == 4'd0) begin
                    ad_rd  <= 1'b0;
                    rd_cnt <= rd_cnt + 1'b1;
                end
                else if (rd_cnt <= 4'd2) begin
                    rd_cnt <= rd_cnt + 1'b1;
                end
                else begin
                    ch2_data <= ad_data;   // 锁存 CH2
                    ad_rd    <= 1'b1;
                    rd_cnt   <= 4'd0;
                    state    <= S_READ_CH3;
                end
            end

            // ----- 读 CH3~CH8（空读，不使用数据但需要完成时序） -----
            S_READ_CH3, S_READ_CH4, S_READ_CH5,
            S_READ_CH6, S_READ_CH7, S_READ_CH8: begin
                if (rd_cnt == 4'd0) begin
                    ad_rd  <= 1'b0;
                    rd_cnt <= rd_cnt + 1'b1;
                end
                else if (rd_cnt <= 4'd2) begin
                    rd_cnt <= rd_cnt + 1'b1;
                end
                else begin
                    ad_rd  <= 1'b1;
                    rd_cnt <= 4'd0;
                    if (state == S_READ_CH8)
                        state <= S_OUTPUT;
                    else
                        state <= state + 1'b1;  // 下一个通道
                end
            end

            // ----- AXI-Stream 输出握手 -----
            S_OUTPUT: begin
                ad_cs         <= 1'b1;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= 1'b1;

                if (m_axis_tready) begin
                    // 下游接收成功
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    state         <= S_DONE;
                end
            end

            // ----- 单次完成，回到 IDLE -----
            S_DONE: begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
                state         <= S_IDLE;
            end

            default: state <= S_RESET;
            endcase
        end
    end

endmodule
