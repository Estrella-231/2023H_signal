#include <stdint.h>
#include "sleep.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

/*
 * AN9767 DAC smoke test.
 *
 * Expected output after programming the current PL bitstream:
 *   DA1: 10 kHz sine wave
 *   DA2: 20 kHz sine wave
 *
 * DDS word formula:
 *   freq_word = round(f_out * 2^27 / 125 MHz)
 *
 * gpio_wave_ctrl bit mapping from PL/build.tcl:
 *   bit0 -> wave_sel_a, 1 = DDS sine, 0 = triangle
 *   bit1 -> wave_sel_b, 1 = DDS sine, 0 = triangle
 */

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

#define DDS_WORD_10KHZ  10737U
#define DDS_WORD_20KHZ  21475U
#define PHASE_0_DEG     0U
#define WAVE_DDS_BOTH   0x00000003U

static void write_gpio32(uintptr_t baseaddr, uint32_t value, const char *name)
{
    xil_printf("%s @ 0x%08lx <- 0x%08lx\r\n",
               name,
               (unsigned long)baseaddr,
               (unsigned long)value);
    Xil_Out32(baseaddr, value);
}

int main(void)
{
    xil_printf("\r\nAN9767 DAC smoke test start\r\n");

    write_gpio32(XPAR_GPIO_A_TRI_STEP_BASEADDR, 0U, "GPIO_A_TRI_STEP");
    write_gpio32(XPAR_GPIO_B_TRI_STEP_BASEADDR, 0U, "GPIO_B_TRI_STEP");

    write_gpio32(XPAR_GPIO_A_DDS_PHASE_BASEADDR, PHASE_0_DEG, "GPIO_A_DDS_PHASE");
    write_gpio32(XPAR_GPIO_B_DDS_PHASE_BASEADDR, PHASE_0_DEG, "GPIO_B_DDS_PHASE");

    write_gpio32(XPAR_GPIO_A_DDS_FREQ_BASEADDR, DDS_WORD_10KHZ, "GPIO_A_DDS_FREQ");
    write_gpio32(XPAR_GPIO_B_DDS_FREQ_BASEADDR, DDS_WORD_20KHZ, "GPIO_B_DDS_FREQ");

    write_gpio32(XPAR_GPIO_WAVE_CTRL_BASEADDR, WAVE_DDS_BOTH, "GPIO_WAVE_CTRL");

    xil_printf("Expected: DA1=10 kHz sine, DA2=20 kHz sine\r\n");
    xil_printf("Leave the app running while probing AN9767 analog outputs.\r\n");

    while (1) {
        sleep(1);
    }

    return 0;
}
