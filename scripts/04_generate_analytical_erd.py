"""
Generate analytical ERD as PNG for README.
Output: assets/erd_analytical_instacart.png
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "erd_analytical_instacart.png"

W, H = 1100, 620
img = Image.new("RGB", (W, H), "#f8f9fa")
draw = ImageDraw.Draw(img)

try:
    title_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
    header_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 15)
    body_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 13)
    small_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
except OSError:
    title_font = header_font = body_font = small_font = ImageFont.load_default()


def table(x, y, w, h, title, title_color, rows, row_count_label=None):
    draw.rounded_rectangle([x, y, x + w, y + h], radius=6, fill="white", outline="#2c3e50", width=2)
    draw.rectangle([x, y, x + w, y + 28], fill=title_color)
    draw.text((x + w / 2, y + 6), title, fill="white", font=header_font, anchor="mt")
    ty = y + 38
    for row in rows:
        draw.text((x + 12, ty), row, fill="#222", font=body_font)
        ty += 22
    if row_count_label:
        draw.text((x + w / 2, y + h - 18), row_count_label, fill="#666", font=small_font, anchor="mt")


def line(x1, y1, x2, y2):
    draw.line([x1, y1, x2, y2], fill="#2c3e50", width=2)


def arrow(x, y, direction="right"):
    if direction == "right":
        draw.polygon([(x, y), (x - 10, y - 5), (x - 10, y + 5)], fill="#2c3e50")
    elif direction == "left":
        draw.polygon([(x, y), (x + 10, y - 5), (x + 10, y + 5)], fill="#2c3e50")


draw.text((W / 2, 24), "ANALYTICAL DATABASE ERD (instacart.db — after ETL)", fill="#1a1a1a", font=title_font, anchor="mt")

table(
    60, 80, 250, 230, "orders", "#2980b9",
    [
        "order_id (int) PK",
        "user_id (int)",
        "order_number (int)",
        "cart_size (int)",
        "reordered_items (int)",
        "reorder_rate (float)",
        "days_since_prior_order (float)",
        "order_dow, order_hour_of_day",
        "distinct_departments (int)",
    ],
    "3.4M rows",
)

table(
    430, 90, 270, 185, "user_departments", "#27ae60",
    [
        "user_id (int) FK",
        "department (text)",
        "items (int)",
        "reorders (int)",
        "reorder_rate (float)",
        "orders_with_dept (int)",
    ],
    "2.3M rows",
)

table(
    430, 340, 270, 145, "products", "#8e44ad",
    [
        "product_id (int) PK",
        "product_name (text)",
        "aisle (text)",
        "department (text)",
    ],
    "49K rows",
)

line(310, 180, 430, 165)
draw.text((370, 148), "user_id", fill="#2c3e50", font=small_font, anchor="mt")
arrow(430, 165, "right")

draw.rounded_rectangle([760, 110, 1040, 280], radius=6, fill="white", outline="#bdc3c7", width=1)
draw.text((770, 125), "Join notes", fill="#1a1a1a", font=header_font)
notes = [
    "orders.user_id",
    "  → user_departments.user_id",
    "",
    "products is standalone.",
    "Department stats are pre-",
    "aggregated at ETL time.",
    "",
    "No 33M-row joins needed",
    "at query time.",
]
ny = 155
for note in notes:
    draw.text((780, ny), note, fill="#444", font=body_font)
    ny += 20

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT, "PNG")
print(f"Saved: {OUT}")
