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
        "!data_valid || m_axis_tready" in an9238
        or "m_axis_tready || !data_valid" in an9238,
        "an9238_axis output registers must update only when empty or downstream ready",
        failures,
    )

    require(
        "adc_ready_and" in build
        and "cic_0_ch1/S_AXIS_DATA/tready" in build
        and "cic_0_ch2/S_AXIS_DATA/tready" in build
        and "adc_inst/m_axis_tready" in build,
        "build.tcl must combine CH1 and CH2 CIC tready before feeding adc_inst/m_axis_tready",
        failures,
    )

    require(
        "GPIO_IO_O" not in build and "gpio_io_o" in build,
        "build.tcl should use Vivado Tcl AXI GPIO output pin name gpio_io_o",
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
