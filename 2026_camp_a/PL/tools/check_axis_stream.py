from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]


def read(relpath: str) -> str:
    return (ROOT / relpath).read_text(encoding="utf-8")


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    axis_tlast = read("src/axis_tlast_gen.v")
    an9238 = read("src/an9238_axis.v")
    build = read("build.tcl")
    ps_params = (ROOT.parent / "PS" / "src" / "parameter.h").read_text(encoding="utf-8")

    failures: list[str] = []

    m_tlast_assign = re.search(r"assign\s+m_tlast\s*=\s*(.*?);", axis_tlast, re.S)
    require(m_tlast_assign is not None, "axis_tlast_gen must assign m_tlast", failures)
    if m_tlast_assign is not None:
        require(
            "m_tready" not in m_tlast_assign.group(1),
            "m_tlast must not be combinationally gated by m_tready",
            failures,
        )

    require(
        all(token in an9238 for token in [
            "ch1_pending",
            "ch2_pending",
            "ch1_accept = ch1_pending && m_ch1_tready",
            "ch2_accept = ch2_pending && m_ch2_tready",
            "sample_empty_next",
            "m_ch1_tvalid = ch1_pending",
            "m_ch2_tvalid = ch2_pending",
        ]),
        "an9238_axis must use per-channel pending flags so CH1/CH2 cannot duplicate or misalign under backpressure",
        failures,
    )

    require(
        "slice_ch1" not in build and "slice_ch2" not in build,
        "build.tcl should not instantiate stale slice_ch1/slice_ch2 after an9238_axis exports two 16-bit AXIS bundles",
        failures,
    )

    require(
        "adc_inst/M_AXIS_CH1" in build
        and "adc_inst/M_AXIS_CH2" in build
        and "adc_inst/m_ch1" not in build
        and "adc_inst/m_ch2" not in build,
        "build.tcl must connect an9238_axis by inferred M_AXIS_CH1/M_AXIS_CH2 interface names",
        failures,
    )

    ad1_port_pos = build.find("create_bd_port -dir I -from 11 -to 0 ad1_in")
    ad1_connect_pos = build.find("connect_bd_net [get_bd_pins adc_inst/ad1_in]")
    require(
        build.count("create_bd_port -dir I -from 11 -to 0 ad1_in") == 1
        and build.count("create_bd_port -dir I -from 11 -to 0 ad2_in") == 1
        and build.count("create_bd_port -dir O ad1_clk") == 1
        and build.count("create_bd_port -dir O ad2_clk") == 1
        and ad1_port_pos != -1
        and ad1_connect_pos != -1
        and ad1_port_pos < ad1_connect_pos,
        "build.tcl must create ADC external ports exactly once before connecting them",
        failures,
    )

    require(
        "GPIO_IO_O" not in build and "gpio_io_o" in build,
        "build.tcl should use Vivado Tcl AXI GPIO output pin name gpio_io_o",
        failures,
    )

    require(
        "FREQ_HZ 64000000" in an9238
        and "65000000" not in an9238
        and "CLK_DOMAIN" not in an9238,
        "an9238_axis clock metadata must match 64MHz FCLK1 and let Vivado infer CLK_DOMAIN",
        failures,
    )

    require(
        "CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {64}" in build
        and build.count("CONFIG.Input_Sample_Frequency {64}") == 2
        and build.count("CONFIG.Input_Sample_Frequency {12.8}") == 2
        and build.count("CONFIG.Clock_Frequency {64}") == 4
        and "rst_ps7_65M" not in build
        and "rst_ps7_64M" in build,
        "build.tcl must keep PS7 FCLK1, CIC metadata, and reset cell naming on the 64MHz clock plan",
        failures,
    )

    require(
        "#define ADC_CLK                     64000000" in ps_params
        and "64e6 / 25 / 16384 = 156.25" in ps_params,
        "PS sampling constants/comments must match the 64MHz / 25 = 2.56MSPS data path",
        failures,
    )

    if failures:
        for item in failures:
            print(f"FAIL: {item}")
        return 1

    print("AXIS/static checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
