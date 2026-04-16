#ifndef _PARAMETER_H_
#define _PARAMETER_H_
#include "xparameters.h"

// ============================================================
// 2026 信号分离装置 — 参数配置
// 平台：AX7010 (XC7Z010)
// ============================================================

#define PI                          3.14159265358979323846f
#define PL_CLK                      50000000

// ============================================================
// DDS 参数（输出端）
// 注意：DDS 相位累加器跑在 DAC 时钟 125MHz 上，不是 PL_CLK 50MHz
// ============================================================
#define DAC_CLK                     125000000  // DAC 实际时钟 125MHz
#define DDS_FREQ                    DAC_CLK    // 频率字基准 = DAC 时钟
#define DAC_DDS_WIDTH               27
#define DDS_PHASE_WIDTH             27         // 相位字与频率字同宽度
#define FREQ_WORD(freq, width)      (1.0*freq*(((long long)1)<<(width))/DDS_FREQ)
#define PHASE_WORD(phase, width)    (1.0*phase*(((long long)1)<<(width))/(2*PI))
#define TRI_STEP(freq)              ((long long)0xffffffff*freq*2/(DAC_CLK+4*freq)+1)

// ============================================================
// DMA
// ============================================================
#define DMA_BASEADDR                XPAR_AXI_DMA_0_BASEADDR
#define COUNTER_RES_WIDTH           16

#define DDR_BASEADDR                XPAR_PS7_DDR_0_S_AXI_BASEADDR
#define DDR_HIGHADDR                XPAR_PS7_DDR_0_S_AXI_HIGHADDR

#define RESET_TIMEOUT               5000

// ============================================================
// ADC 配置 — AN9238 (AD9238, 12-bit 双通道, 65MSPS)
// ============================================================

#define ADC_WIDTH                   12
#define ADC_REVOLUTION              4096      // 2^12
#define ADC_REF                     1.0       // AD9238 参考电压 ±1V (参考 volt_cal.v: 5V/2048)
#define ADC_CLK                     65000000  // 65 MSPS
#define ADC_SNR                     70        // AD9238 典型 SNR

// ============================================================
// 采样与 FFT
// ============================================================
#define GUI_TIMER_INT_ID            XPAR_SCUTIMER_INTR
#define GUI_TIMER_DEVICE_ID         XPAR_SCUTIMER_DEVICE_ID

// AN9238: 65MSPS 需要 CIC 抽取
#define CIC_SAMPLE_RATE             25

#define SOFT_SAMPLE_RATE            1

// AN9238: 抽取后有效采样率 = 65MHz/25 = 2.6MHz, 大 FFT 提高分辨率
#define FFT_SAMPLE_LEN              (8192*2)

#define SAMPLE_LEN                  (adc_inst.adc_buf_len)
#define JUDGE_FFT_LEN               (4096*2)
// 频率分辨率 = ADC_CLK / CIC_SAMPLE_RATE / FFT_SAMPLE_LEN
//   AN9238: 65e6 / 25 / 16384 = 158.7 Hz/bin

#define TYPE_JUDGE_THRESHOLD        1e-1

#define FIR_ORDER                   100

#define ANS_POINT_NUM               1024
#define MAX_FREQ                    50e6
#define MIN_FREQ                    5e3       // 改为 5kHz（题目下限）

#define GPIO_DEVICE_ID                          XPAR_PS7_GPIO_0_DEVICE_ID
#define GPIO_BASE_ADDR                          XPAR_PS7_GPIO_0_BASEADDR
#define GPIO_HIGH_ADDR                          XPAR_PS7_GPIO_0_HIGHADDR

#define EMIO_BANK1                              XGPIOPS_BANK2
#define EMIO_BANK2                              XGPIOPS_BANK3
#define EMIO_MIN_PIN                            54
#define EMIO_PIN(num)                           (EMIO_MIN_PIN+num)
#define DATA_EMIO_MASK                          0x001fffe0
#define DATA_PIN_OFFSET                         5

#define GPIO_IN                                 0
#define GPIO_OUT                                1
#define GPIO_OUT_DISABLE                        0
#define GPIO_OUT_ENABLE                         1
#define GPIO_BANK_OUT                           0xffffffff
#define GPIO_BANK_IN                            0
#endif
