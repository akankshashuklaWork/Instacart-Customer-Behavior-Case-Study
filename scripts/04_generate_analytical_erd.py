"""
Generate analytical ERD assets for README.
Outputs:
  - assets/erd_analytical_instacart.svg  (primary — crisp on GitHub)
  - assets/erd_analytical_instacart.png  (fallback preview)
"""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
SVG = ASSETS / "erd_analytical_instacart.svg"
PNG = ASSETS / "erd_analytical_instacart.png"


def svg_to_png() -> None:
    """Convert SVG to PNG if cairosvg or rsvg-convert is available."""
    try:
        import cairosvg
        cairosvg.svg2png(url=str(SVG), write_to=str(PNG), output_width=1920)
        print(f"PNG (cairosvg): {PNG}")
        return
    except ImportError:
        pass

    for cmd in (
        ["rsvg-convert", "-w", "1920", str(SVG), "-o", str(PNG)],
        ["qlmanage", "-t", "-s", "1920", "-o", str(ASSETS), str(SVG)],
    ):
        try:
            subprocess.run(cmd, check=True, capture_output=True)
            if PNG.exists():
                print(f"PNG: {PNG}")
                return
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue

    print("SVG saved. Install cairosvg for PNG export: pip install cairosvg")


def main() -> None:
    if not SVG.exists():
        raise FileNotFoundError(f"SVG not found: {SVG}")
    svg_to_png()


if __name__ == "__main__":
    main()
