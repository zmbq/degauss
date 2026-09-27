"""Phosphor colors of vintage monochrome monitors.

A sample file for Retro Looks screenshots: it uses comments, strings,
keywords, numbers, imports and a decorator, so every look shows all its colors.
"""
from dataclasses import dataclass
from functools import lru_cache

# P1 green, P3 amber and P4 white were the classic phosphors.
PHOSPHORS = {
    "P1": ("green", 0x40F040),
    "P3": ("amber", 0xF0A848),
    "P4": ("white", 0xE8ECF0),
}


@dataclass(frozen=True)
class Monitor:
    name: str
    year: int
    columns: int = 80
    phosphor: str = "P1"

    def describe(self) -> str:
        color, rgb = PHOSPHORS[self.phosphor]
        return f"{self.name} ({self.year}): {self.columns} columns, {color} #{rgb:06X}"


@lru_cache(maxsize=None)
def brightness(rgb: int) -> float:
    r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return (0.3 * r + 0.59 * g + 0.11 * b) / 255


if __name__ == "__main__":
    for monitor in (Monitor("Apple Monitor II", 1983), Monitor("IBM 3278", 1977, phosphor="P1")):
        print(monitor.describe())
    print("READY.")
