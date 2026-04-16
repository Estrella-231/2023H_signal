#include "xaxidma.h"
#include "adc_dma.h"
#include "my_func.h"
#include "xscugic.h"
#include "my_func.h"
#include "parameter.h"
#include "interrupt.h"
#include "math.h"

static XAxiDma axi_dma_inst;
Adc_control adc_inst;

int dma_check(){
    return (XAxiDma_ReadReg(axi_dma_inst.RegBase, XAXIDMA_RX_OFFSET+XAXIDMA_SR_OFFSET) & XAXIDMA_IRQ_ERROR_MASK);
}

static void s2mm_handler(int vector, void* CallbackRef){
    rt_interrupt_enter();
    u32 irq_status;
    XAxiDma* p_inst = (XAxiDma*)CallbackRef;
    XAxiDma_IntrDisable(p_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    irq_status = XAxiDma_IntrGetIrq(p_inst, XAXIDMA_DEVICE_TO_DMA);

    if(!(irq_status&XAXIDMA_IRQ_ALL_MASK))
        return ;

    if (irq_status & XAXIDMA_IRQ_ERROR_MASK){
//        error_say(1, "dma s2mm intrrupt error\n");
        adc_inst.error = XST_FAILURE;
		XAxiDma_Reset(p_inst);
		int time_out = RESET_TIMEOUT;

		while(time_out){
			if (XAxiDma_ResetIsDone(p_inst))
				break;
			time_out -= 1;
		}
	}
    
    if(irq_status & XAXIDMA_IRQ_IOC_MASK)
        adc_inst.rx_done = 1;

    XAxiDma_IntrAckIrq(p_inst, irq_status, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrEnable(p_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    rt_interrupt_leave();
}

static int dma_intr_init(int intr_s2mm_id){

    rt_hw_interrupt_install(intr_s2mm_id, s2mm_handler, &axi_dma_inst, "adc_dma");
    rt_hw_interrupt_umask(intr_s2mm_id);

    XAxiDma_IntrEnable(&axi_dma_inst, (XAXIDMA_IRQ_IOC_MASK|XAXIDMA_IRQ_ERROR_MASK), XAXIDMA_DEVICE_TO_DMA);

    return XST_SUCCESS;
}

static int dma_init(int device_id, int intr_id, int s2mm_intr_id){
    XAxiDma_Config* dma_config = XAxiDma_LookupConfig(device_id);
    if(dma_config == NULL){
        xil_printf("dma look up config error");
        xil_printf("can not find target dma device\n");
        return XST_FAILURE;
    }

    if(XAxiDma_CfgInitialize(&axi_dma_inst, dma_config) != XST_SUCCESS)
        return XST_FAILURE;

    XAxiDma_Reset(&axi_dma_inst);
    while(XAxiDma_ResetIsDone(&axi_dma_inst) == 0);

    if(dma_check() != 0) {
        xil_printf("dma return an error\n");
        return XST_FAILURE;
    }

    return dma_intr_init(s2mm_intr_id);

    return XST_SUCCESS;
}

int adc_translation_init(){
    int status = XST_SUCCESS;
    status = dma_init(
            XPAR_AXIDMA_0_DEVICE_ID,
            XPAR_SCUGIC_0_DEVICE_ID,
            XPAR_FABRIC_AXIDMA_0_VEC_ID);

    adc_inst.adc_dma = &axi_dma_inst;
    adc_inst.rx_done = 0;
    adc_inst.error = status;

    // DMA buffer: MaxTransferLen 是最大字节数，除以 4 得到 32-bit 采样点数
    uint32_t max_bytes = adc_inst.adc_dma->TxBdRing.MaxTransferLen;
    uint32_t max_samples = max_bytes / sizeof(uint32_t);

    adc_inst.adc_buf = (uint32_t*)rt_malloc_align(max_bytes, 32);  // 32-byte 对齐（Cache line）
    adc_inst.adc_buf_len = max_samples;  // 采样点数（非字节数）
    adc_inst.sin_volt = (float*)rt_malloc_align(max_samples * sizeof(float), sizeof(float));
    adc_inst.cos_volt = (float*)rt_malloc_align(max_samples * sizeof(float), sizeof(float));
    return status;
}
INIT_DEVICE_EXPORT(adc_translation_init);

// ============================================================
// AN9238 数据解包：DMA 传入 32-bit = {ch2_s16[15:0], ch1_s16[15:0]}
// PL 端 an9238_axis.v 已完成偏移二进制→有符号补码 + 12→16 位扩展
// 此处只需拆出两个 16-bit 有符号通道并转浮点电压
// ============================================================
static void adc_volt(uint32_t* iq_data, uint32_t num_samples){
    for(uint32_t i = 0; i < num_samples; ++i){
        int16_t ch1_raw = (int16_t)(iq_data[i] & 0xFFFF);         // 低 16-bit = CH1
        int16_t ch2_raw = (int16_t)((iq_data[i] >> 16) & 0xFFFF); // 高 16-bit = CH2

        // AN9238 PL 端做了 12→16 bit 符号扩展（高 4 位是符号位复制）
        // 实际有效范围 -2048 ~ +2047, 对应 ±ADC_REF
        (adc_inst.sin_volt)[i] = (float)ch1_raw / (float)(1 << (ADC_WIDTH - 1)) * ADC_REF;
        (adc_inst.cos_volt)[i] = (float)ch2_raw / (float)(1 << (ADC_WIDTH - 1)) * ADC_REF;
    }
}


int adc_translation(int recv_samples){
    int time_out = RESET_TIMEOUT;
    if(time_out == 0)
        return XST_FAILURE;

    // recv_samples 是采样点数，DMA 传输需要字节数
    uint32_t recv_bytes = recv_samples * sizeof(uint32_t);

    // DMA 写入前先 Invalidate，确保 CPU 缓存不会覆盖 DMA 写入的数据
    Xil_DCacheInvalidateRange((INTPTR)adc_inst.adc_buf, recv_bytes);

    int status = XAxiDma_SimpleTransfer(adc_inst.adc_dma, (UINTPTR)adc_inst.adc_buf, recv_bytes, XAXIDMA_DEVICE_TO_DMA);
    if(status != XST_SUCCESS)
        return status;

    while(adc_inst.rx_done == 0);
    adc_inst.rx_done = 0;

    // DMA 完成后再次 Invalidate，丢弃 CPU 缓存中的旧行
    Xil_DCacheInvalidateRange((INTPTR)adc_inst.adc_buf, recv_bytes);

    adc_volt(adc_inst.adc_buf, recv_samples);

    return XST_SUCCESS;
}

