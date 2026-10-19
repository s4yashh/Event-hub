"""Render the editable team plan as a two-or-more-page PDF with Matplotlib."""

from pathlib import Path
import re
import textwrap

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.patches import Rectangle


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "team-work-division.md"
TARGET = ROOT / "docs" / "team-work-division.pdf"


def plain(markdown: str) -> str:
    value = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", markdown)
    return value.replace("**", "").replace("`", "").strip()


def render() -> None:
    page_number = 0
    figure = None
    axis = None
    y = 0.0

    with PdfPages(TARGET) as pdf:
        def save_page() -> None:
            if figure is not None:
                axis.text(0.07, 0.035, "EVENTHUB  /  TEAM RESPONSIBILITIES", size=7.5,
                          color="#727b85", transform=axis.transAxes)
                axis.text(0.93, 0.035, str(page_number), size=7.5,
                          color="#727b85", ha="right", transform=axis.transAxes)
                pdf.savefig(figure)
                plt.close(figure)

        def new_page() -> None:
            nonlocal figure, axis, y, page_number
            save_page()
            page_number += 1
            figure, axis = plt.subplots(figsize=(8.27, 11.69))
            figure.patch.set_facecolor("white")
            axis.set_xlim(0, 1)
            axis.set_ylim(0, 1)
            axis.axis("off")
            axis.add_patch(Rectangle((0, 0.972), 1, 0.028, color="#302b52"))
            if page_number > 1:
                axis.text(0.07, 0.94, "EVENTHUB  /  TEAM WORK DIVISION", size=10,
                          weight="bold", color="#302b52", transform=axis.transAxes)
                y = 0.90
            else:
                y = 0.935

        def ensure_space(height: float) -> None:
            if y - height < 0.075:
                new_page()

        def draw_lines(value: str, *, indent: float = 0, color: str = "#27313c",
                       weight: str = "normal", size: float = 9.2,
                       width: int = 102, spacing: float = 0.018) -> None:
            nonlocal y
            lines = textwrap.wrap(plain(value), width=width, break_long_words=False,
                                  break_on_hyphens=False) or [""]
            ensure_space(len(lines) * spacing + 0.006)
            for line in lines:
                axis.text(0.07 + indent, y, line, va="top", size=size,
                          color=color, weight=weight, transform=axis.transAxes)
                y -= spacing
            y -= 0.005

        new_page()
        for raw in SOURCE.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line:
                y -= 0.005
                continue
            if line.startswith("# "):
                draw_lines(line[2:], color="#302b52", weight="bold", size=22,
                           width=49, spacing=0.037)
                axis.add_patch(Rectangle((0.07, y - 0.005), 0.15, 0.006,
                                         color="#9b83d3"))
                y -= 0.025
            elif line.startswith("## "):
                ensure_space(0.09)
                y -= 0.013
                draw_lines(line[3:], color="#302b52", weight="bold", size=12.2,
                           width=77, spacing=0.026)
                axis.plot([0.07, 0.93], [y + 0.002, y + 0.002], color="#ddd7ea",
                          linewidth=0.9, transform=axis.transAxes)
                y -= 0.008
            elif re.match(r"^\d+\. ", line):
                draw_lines(line, indent=0.012, width=98)
            elif line.startswith("- "):
                draw_lines("• " + line[2:], indent=0.012, width=97)
            else:
                draw_lines(line)
        save_page()

    print(TARGET)


if __name__ == "__main__":
    render()
