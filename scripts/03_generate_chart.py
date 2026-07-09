"""
Generate reorder-rate-by-department bar chart (SVG, no matplotlib required).
Output: assets/reorder_rate_by_department.svg
"""
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "instacart.db"
OUT_PATH = ROOT / "assets" / "reorder_rate_by_department.svg"

query = """
SELECT department, ROUND(100.0 * SUM(reorders) / SUM(items), 1) AS rate
FROM user_departments GROUP BY department ORDER BY rate DESC;
"""

conn = sqlite3.connect(DB_PATH)
rows = conn.execute(query).fetchall()
conn.close()

OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

bar_height = 22
gap = 6
margin_left = 160
margin_top = 40
width = 720
chart_height = len(rows) * (bar_height + gap) + margin_top + 30
max_rate = max(r[1] for r in rows)

def color(rate: float) -> str:
    if rate >= 60:
        return "#2ecc71"
    if rate >= 45:
        return "#f39c12"
    return "#e74c3c"

lines = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{chart_height}">',
    '<rect width="100%" height="100%" fill="#fafafa"/>',
    '<text x="20" y="24" font-family="Arial" font-size="16" font-weight="bold">'
    "Reorder Rate by Department</text>",
    f'<line x1="{margin_left}" y1="{margin_top - 10}" x2="{width - 20}" y2="{margin_top - 10}" stroke="#ccc"/>',
    f'<line x1="{margin_left}" y1="{margin_top - 10}" x2="{margin_left}" y2="{chart_height - 20}" stroke="#ccc"/>',
]

avg_x = margin_left + (59.0 / max_rate) * (width - margin_left - 40)
lines.append(
    f'<line x1="{avg_x:.1f}" y1="{margin_top - 10}" x2="{avg_x:.1f}" y2="{chart_height - 20}" '
    'stroke="#3498db" stroke-dasharray="4,3"/>'
)
lines.append(
    f'<text x="{avg_x + 4:.1f}" y="{margin_top - 14}" font-family="Arial" font-size="11" fill="#3498db">'
    "59% avg</text>"
)

for i, (dept, rate) in enumerate(rows):
    y = margin_top + i * (bar_height + gap)
    bar_w = (rate / max_rate) * (width - margin_left - 40)
    lines.append(
        f'<text x="8" y="{y + 15}" font-family="Arial" font-size="12">{dept}</text>'
    )
    lines.append(
        f'<rect x="{margin_left}" y="{y}" width="{bar_w:.1f}" height="{bar_height}" '
        f'fill="{color(rate)}" rx="3"/>'
    )
    lines.append(
        f'<text x="{margin_left + bar_w + 6:.1f}" y="{y + 15}" font-family="Arial" '
        f'font-size="12">{rate}%</text>'
    )

lines.append("</svg>")
OUT_PATH.write_text("\n".join(lines))
print(f"Chart saved: {OUT_PATH}")
