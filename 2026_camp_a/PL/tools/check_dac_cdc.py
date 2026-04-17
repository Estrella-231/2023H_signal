from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DAC = ROOT / "src" / "dac_out.v"
BUILD = ROOT / "build.tcl"
XDC = ROOT / "cons" / "ax7010.xdc"


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def main():
    dac = DAC.read_text(encoding="utf-8", errors="ignore")
    build = BUILD.read_text(encoding="utf-8", errors="ignore")
    xdc = XDC.read_text(encoding="utf-8", errors="ignore")

    require("input  wire        cfg_clk" in dac, "dac_out is missing cfg_clk")
    require("input  wire        cfg_rst_n" in dac, "dac_out is missing cfg_rst_n")
    require("config_bus_cdc" in dac, "dac_out is missing config_bus_cdc")
    require("cfg_cdc_inst" in dac, "dac_out is missing cfg_cdc_inst")

    expected_uses = [
        "dds_a_phase_dac[26:0]",
        "dds_b_phase_dac[26:0]",
        ".step    (tri_a_step_dac)",
        ".step    (tri_b_step_dac)",
    ]
    for token in expected_uses:
        require(token in dac, f"dac_out does not use CDC signal: {token}")

    freq_a_is_cdc = "dds_a_freq_dac[26:0]" in dac
    freq_b_is_cdc = "dds_b_freq_dac[26:0]" in dac
    freq_a_is_forced = "dds_a_freq_active = DDS_WORD_10KHZ" in dac
    freq_b_is_forced = "dds_b_freq_active = DDS_WORD_20KHZ" in dac
    require(
        freq_a_is_cdc or freq_a_is_forced,
        "dac_out must use CDC dds_a_freq_dac or force channel A frequency during bring-up",
    )
    require(
        freq_b_is_cdc or freq_b_is_forced,
        "dac_out must use CDC dds_b_freq_dac or force channel B frequency during bring-up",
    )

    wave_a_is_cdc = ".which     (wave_sel_a_dac)" in dac
    wave_b_is_cdc = ".which     (wave_sel_b_dac)" in dac
    wave_a_is_forced_dds = ".which     (1'b1)" in dac
    wave_b_is_forced_dds = dac.count(".which     (1'b1)") >= 2
    require(
        wave_a_is_cdc or wave_a_is_forced_dds,
        "dac_out must use CDC wave_sel_a_dac or force channel A to DDS during bring-up",
    )
    require(
        wave_b_is_cdc or wave_b_is_forced_dds,
        "dac_out must use CDC wave_sel_b_dac or force channel B to DDS during bring-up",
    )
    if wave_a_is_forced_dds or wave_b_is_forced_dds:
        require(
            "force DDS during bring-up" in dac,
            "forced DDS mode must be explicitly documented in dac_out.v",
        )

    require(
        "ps7/FCLK_CLK0] [get_bd_pins dac_inst/cfg_clk]" in build,
        "build.tcl does not connect cfg_clk",
    )
    require(
        "rst_ps7_50M/peripheral_aresetn] [get_bd_pins dac_inst/cfg_rst_n]" in build,
        "build.tcl does not connect cfg_rst_n",
    )
    require("cfg_to_dac_cdc_async" in xdc, "XDC is missing CDC clock group")
    require("clk_fpga_0" in xdc, "XDC does not reference clk_fpga_0")
    require("clk_out1_system_clk_wiz_0_0" in xdc, "XDC does not reference DAC clock")

    print("dac CDC static checks passed")


if __name__ == "__main__":
    main()
