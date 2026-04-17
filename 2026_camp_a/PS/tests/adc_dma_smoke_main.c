#include <stdint.h>
#include "sleep.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"

/*
 * ADC DMA smoke test for 2026 signal separator.
 *
 * Expected PL stream format:
 *   one 32-bit AXIS word = {CH2 signed 16-bit, CH1 signed 16-bit}
 *
 * CAPTURE_WORDS intentionally over-provisions the DMA buffer. If PL TLAST is
 * generated every 1024 32-bit words, an 8192-byte DMA receive should complete
 * after the shorter packet. If this still fails with DMA_INTERNAL_ERR, TLAST is
 * not reaching DMA before the buffer fills.
 */

#if defined(XPAR_AXI_DMA_0_DEVICE_ID)
#define DMA_DEV_ID XPAR_AXI_DMA_0_DEVICE_ID
#elif defined(XPAR_AXIDMA_0_DEVICE_ID)
#define DMA_DEV_ID XPAR_AXIDMA_0_DEVICE_ID
#else
#error "Cannot find AXI DMA device id in xparameters.h"
#endif

#ifndef XPAR_GPIO_A_DDS_FREQ_BASEADDR
#error "Missing XPAR_GPIO_A_DDS_FREQ_BASEADDR. Regenerate BSP from current XSA."
#endif
#ifndef XPAR_GPIO_A_DDS_PHASE_BASEADDR
#error "Missing XPAR_GPIO_A_DDS_PHASE_BASEADDR. Regenerate BSP from current XSA."
#endif
#ifndef XPAR_GPIO_B_DDS_FREQ_BASEADDR
#error "Missing XPAR_GPIO_B_DDS_FREQ_BASEADDR. Regenerate BSP from current XSA."
#endif
#ifndef XPAR_GPIO_B_DDS_PHASE_BASEADDR
#error "Missing XPAR_GPIO_B_DDS_PHASE_BASEADDR. Regenerate BSP from current XSA."
#endif
#ifndef XPAR_GPIO_A_TRI_STEP_BASEADDR
#error "Missing XPAR_GPIO_A_TRI_STEP_BASEADDR. Regenerate BSP from current XSA."
#endif
#ifndef XPAR_GPIO_B_TRI_STEP_BASEADDR
#error "Missing XPAR_GPIO_B_TRI_STEP_BASEADDR. Regenerate BSP from current XSA."
#endif
#ifndef XPAR_GPIO_WAVE_CTRL_BASEADDR
#error "Missing XPAR_GPIO_WAVE_CTRL_BASEADDR. Regenerate BSP from current XSA."
#endif

#define GPIO_A_DDS_FREQ   XPAR_GPIO_A_DDS_FREQ_BASEADDR
#define GPIO_A_DDS_PHASE  XPAR_GPIO_A_DDS_PHASE_BASEADDR
#define GPIO_B_DDS_FREQ   XPAR_GPIO_B_DDS_FREQ_BASEADDR
#define GPIO_B_DDS_PHASE  XPAR_GPIO_B_DDS_PHASE_BASEADDR
#define GPIO_A_TRI_STEP   XPAR_GPIO_A_TRI_STEP_BASEADDR
#define GPIO_B_TRI_STEP   XPAR_GPIO_B_TRI_STEP_BASEADDR
#define GPIO_WAVE_CTRL    XPAR_GPIO_WAVE_CTRL_BASEADDR

#define DDS_WORD_10KHZ    10737U
#define DDS_WORD_20KHZ    21475U
#define PHASE_0_DEG       0U
#define WAVE_DDS_BOTH     0x00000003U

#define CAPTURE_WORDS     2048U
#define CAPTURE_BYTES     (CAPTURE_WORDS * sizeof(uint32_t))
#define DMA_TIMEOUT       20000000U
#define PRINT_SAMPLES     32U

static XAxiDma dma_inst;
static uint32_t rx_buf[CAPTURE_WORDS] __attribute__((aligned(64)));

static void print_dma_status(u32 sr)
{
    xil_printf("S2MM_DMASR=0x%08lx", (unsigned long)sr);
    if (sr & XAXIDMA_HALTED_MASK)      xil_printf(" HALTED");
    if (sr & XAXIDMA_IDLE_MASK)        xil_printf(" IDLE");
    if (sr & XAXIDMA_ERR_INTERNAL_MASK) xil_printf(" DMA_INTERNAL_ERR");
    if (sr & XAXIDMA_ERR_SLAVE_MASK)    xil_printf(" DMA_SLAVE_ERR");
    if (sr & XAXIDMA_ERR_DECODE_MASK)   xil_printf(" DMA_DECODE_ERR");
    if (sr & XAXIDMA_IRQ_IOC_MASK)      xil_printf(" IOC_IRQ");
    if (sr & XAXIDMA_IRQ_DELAY_MASK)    xil_printf(" DELAY_IRQ");
    if (sr & XAXIDMA_IRQ_ERROR_MASK)    xil_printf(" ERR_IRQ");
    xil_printf("\r\n");
}

static void dac_set_dds_test_tones(void)
{
    xil_printf("write GPIO_A_TRI_STEP  0x%08lx...\r\n", (unsigned long)GPIO_A_TRI_STEP);
    Xil_Out32(GPIO_A_TRI_STEP, 0U);
    xil_printf("ok\r\n");

    xil_printf("write GPIO_B_TRI_STEP  0x%08lx...\r\n", (unsigned long)GPIO_B_TRI_STEP);
    Xil_Out32(GPIO_B_TRI_STEP, 0U);
    xil_printf("ok\r\n");

    xil_printf("write GPIO_A_DDS_PHASE 0x%08lx...\r\n", (unsigned long)GPIO_A_DDS_PHASE);
    Xil_Out32(GPIO_A_DDS_PHASE, PHASE_0_DEG);
    xil_printf("ok\r\n");

    xil_printf("write GPIO_B_DDS_PHASE 0x%08lx...\r\n", (unsigned long)GPIO_B_DDS_PHASE);
    Xil_Out32(GPIO_B_DDS_PHASE, PHASE_0_DEG);
    xil_printf("ok\r\n");

    xil_printf("write GPIO_A_DDS_FREQ  0x%08lx...\r\n", (unsigned long)GPIO_A_DDS_FREQ);
    Xil_Out32(GPIO_A_DDS_FREQ, DDS_WORD_10KHZ);
    xil_printf("ok\r\n");

    xil_printf("write GPIO_B_DDS_FREQ  0x%08lx...\r\n", (unsigned long)GPIO_B_DDS_FREQ);
    Xil_Out32(GPIO_B_DDS_FREQ, DDS_WORD_20KHZ);
    xil_printf("ok\r\n");

    xil_printf("write GPIO_WAVE_CTRL   0x%08lx...\r\n", (unsigned long)GPIO_WAVE_CTRL);
    Xil_Out32(GPIO_WAVE_CTRL, WAVE_DDS_BOTH);
    xil_printf("ok\r\n");
}

static int dma_init(void)
{
    xil_printf("DMA lookup dev id=%d\r\n", DMA_DEV_ID);
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (cfg == NULL) {
        xil_printf("DMA lookup failed\r\n");
        return XST_FAILURE;
    }

    xil_printf("DMA cfg base=0x%08lx\r\n", (unsigned long)cfg->BaseAddr);
    int status = XAxiDma_CfgInitialize(&dma_inst, cfg);
    if (status != XST_SUCCESS) {
        xil_printf("DMA cfg init failed: %d\r\n", status);
        return status;
    }

    if (XAxiDma_HasSg(&dma_inst)) {
        xil_printf("DMA is in SG mode, this test needs simple mode\r\n");
        return XST_FAILURE;
    }

    xil_printf("DMA reset...\r\n");
    print_dma_status(XAxiDma_ReadReg(
        dma_inst.RegBase,
        XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET
    ));

    XAxiDma_Reset(&dma_inst);
    for (uint32_t t = 0; t < DMA_TIMEOUT; ++t) {
        if (XAxiDma_ResetIsDone(&dma_inst)) {
            xil_printf("DMA reset done\r\n");
            print_dma_status(XAxiDma_ReadReg(
                dma_inst.RegBase,
                XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET
            ));
            break;
        }
        if (t == DMA_TIMEOUT - 1U) {
            xil_printf("DMA reset timeout\r\n");
            print_dma_status(XAxiDma_ReadReg(
                dma_inst.RegBase,
                XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET
            ));
            return XST_FAILURE;
        }
    }

    XAxiDma_IntrDisable(&dma_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}

static int dma_capture_once(void)
{
    for (uint32_t i = 0; i < CAPTURE_WORDS; ++i) {
        rx_buf[i] = 0xDEADBEEFU;
    }

    Xil_DCacheFlushRange((INTPTR)rx_buf, CAPTURE_BYTES);
    Xil_DCacheInvalidateRange((INTPTR)rx_buf, CAPTURE_BYTES);

    int status = XAxiDma_SimpleTransfer(
        &dma_inst,
        (UINTPTR)rx_buf,
        CAPTURE_BYTES,
        XAXIDMA_DEVICE_TO_DMA
    );
    if (status != XST_SUCCESS) {
        xil_printf("DMA SimpleTransfer failed: %d, bytes=%lu\r\n",
                   status, (unsigned long)CAPTURE_BYTES);
        return status;
    }

    for (uint32_t t = 0; t < DMA_TIMEOUT; ++t) {
        u32 sr = XAxiDma_ReadReg(
            dma_inst.RegBase,
            XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET
        );
        if (sr & XAXIDMA_IRQ_ERROR_MASK) {
            print_dma_status(sr);
            xil_printf("DMA stopped with error before transfer completed\r\n");
            xil_printf("The incoming AXIS packet exceeded the DMA buffer length\r\n");
            xil_printf("Most likely: TLAST is not reaching DMA, or the programmed bit is stale\r\n");
            return XST_FAILURE;
        }

        if (!XAxiDma_Busy(&dma_inst, XAXIDMA_DEVICE_TO_DMA)) {
            Xil_DCacheInvalidateRange((INTPTR)rx_buf, CAPTURE_BYTES);
            print_dma_status(sr);
            u32 actual_len = XAxiDma_ReadReg(
                dma_inst.RegBase,
                XAXIDMA_RX_OFFSET + XAXIDMA_BUFFLEN_OFFSET
            );
            xil_printf("S2MM_LENGTH after completion=%lu bytes\r\n",
                       (unsigned long)actual_len);
            return XST_SUCCESS;
        }
    }

    u32 sr = XAxiDma_ReadReg(
        dma_inst.RegBase,
        XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET
    );
    xil_printf("DMA timeout\r\n");
    print_dma_status(sr);
    xil_printf("Check ADC clock/data and TLAST packet length\r\n");
    return XST_FAILURE;
}

static void analyze_and_print(void)
{
    int16_t ch1_min = 32767;
    int16_t ch1_max = -32768;
    int16_t ch2_min = 32767;
    int16_t ch2_max = -32768;
    int64_t ch1_sum = 0;
    int64_t ch2_sum = 0;

    for (uint32_t i = 0; i < CAPTURE_WORDS; ++i) {
        int16_t ch1 = (int16_t)(rx_buf[i] & 0xFFFFU);
        int16_t ch2 = (int16_t)((rx_buf[i] >> 16) & 0xFFFFU);

        if (ch1 < ch1_min) ch1_min = ch1;
        if (ch1 > ch1_max) ch1_max = ch1;
        if (ch2 < ch2_min) ch2_min = ch2;
        if (ch2 > ch2_max) ch2_max = ch2;

        ch1_sum += ch1;
        ch2_sum += ch2;
    }

    xil_printf("CH1 min=%d max=%d pp=%d avg=%ld\r\n",
               ch1_min, ch1_max, ch1_max - ch1_min,
               (long)(ch1_sum / (int64_t)CAPTURE_WORDS));
    xil_printf("CH2 min=%d max=%d pp=%d avg=%ld\r\n",
               ch2_min, ch2_max, ch2_max - ch2_min,
               (long)(ch2_sum / (int64_t)CAPTURE_WORDS));

    xil_printf("First %lu samples: raw32 ch1 ch2\r\n",
               (unsigned long)PRINT_SAMPLES);
    for (uint32_t i = 0; i < PRINT_SAMPLES; ++i) {
        int16_t ch1 = (int16_t)(rx_buf[i] & 0xFFFFU);
        int16_t ch2 = (int16_t)((rx_buf[i] >> 16) & 0xFFFFU);
        xil_printf("%04lu: 0x%08lx %6d %6d\r\n",
                   (unsigned long)i,
                   (unsigned long)rx_buf[i],
                   ch1,
                   ch2);
    }
}

int main(void)
{
    xil_printf("\r\nADC DMA smoke test start\r\n");
    xil_printf("CAPTURE_WORDS=%lu CAPTURE_BYTES=%lu\r\n",
               (unsigned long)CAPTURE_WORDS,
               (unsigned long)CAPTURE_BYTES);
    xil_printf("rx_buf address=0x%08lx\r\n", (unsigned long)rx_buf);

    dac_set_dds_test_tones();
    xil_printf("DAC DDS test tones set: CH1 10 kHz, CH2 20 kHz\r\n");
    usleep(100000);

    if (dma_init() != XST_SUCCESS) {
        xil_printf("DMA init failed\r\n");
        return XST_FAILURE;
    }
    xil_printf("DMA init ok\r\n");

    while (1) {
        int status = dma_capture_once();
        if (status == XST_SUCCESS) {
            xil_printf("capture ok\r\n");
            analyze_and_print();
        } else {
            xil_printf("capture failed: %d\r\n", status);
        }

        sleep(1);
    }
}
