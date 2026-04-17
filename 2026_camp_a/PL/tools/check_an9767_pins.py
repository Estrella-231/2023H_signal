#!/usr/bin/env python3
"""Check AN9767 DAC pin assignments against the known-good reference design."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
XDC_PATH = ROOT / "cons" / "ax7010.xdc"

EXPECTED_PINS = {
    "da1_data[0]": "K17",
    "da1_data[1]": "K18",
    "da1_data[2]": "M19",
    "da1_data[3]": "M20",
    "da1_data[4]": "L19",
    "da1_data[5]": "L20",
    "da1_data[6]": "J18",
    "da1_data[7]": "H18",
    "da1_data[8]": "G19",
    "da1_data[9]": "G20",
    "da1_data[10]": "F19",
    "da1_data[11]": "F20",
    "da1_data[12]": "F16",
    "da1_data[13]": "F17",
    "da1_wrt": "J19",
    "da1_clk": "K19",
    "da2_data[0]": "H15",
    "da2_data[1]": "G15",
    "da2_data[2]": "H16",
    "da2_data[3]": "H17",
    "da2_data[4]": "G17",
    "da2_data[5]": "G18",
    "da2_data[6]": "E18",
    "da2_data[7]": "E19",
    "da2_data[8]": "D19",
    "da2_data[9]": "D20",
    "da2_data[10]": "M17",
    "da2_data[11]": "M18",
    "da2_data[12]": "L16",
    "da2_data[13]": "L17",
    "da2_clk": "H20",
    "da2_wrt": "J20",
}


PACKAGE_PIN_RE = re.compile(
    r"^\s*set_property\s+PACKAGE_PIN\s+(\S+)\s+\[get_ports\s+\{?([^}\]]+(?:\][^}\]]*)?)\}?\]\s*$"
)


def parse_xdc(path: Path):
    mapping = {}
    duplicates = []

    for lineno, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.split("#", 1)[0].strip()
        match = PACKAGE_PIN_RE.match(line)
        if not match:
            continue

        pin, port = match.groups()
        port = port.strip()
        if port in mapping:
            duplicates.append((port, mapping[port], (pin, lineno)))
        mapping[port] = (pin, lineno)

    return mapping, duplicates


def main() -> int:
    mapping, duplicates = parse_xdc(XDC_PATH)
    errors = []

    for port, expected_pin in EXPECTED_PINS.items():
        actual = mapping.get(port)
        if actual is None:
            errors.append(f"missing PACKAGE_PIN for {port}, expected {expected_pin}")
            continue

        actual_pin, lineno = actual
        if actual_pin != expected_pin:
            errors.append(
                f"{port}: expected {expected_pin}, got {actual_pin} at {XDC_PATH}:{lineno}"
            )

    for port, first, second in duplicates:
        errors.append(
            f"{port}: duplicate PACKAGE_PIN assignments at lines {first[1]} and {second[1]}"
        )

    if errors:
        print("AN9767 pin check failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print("AN9767 pin check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
