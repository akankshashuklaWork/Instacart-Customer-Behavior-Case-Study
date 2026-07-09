"""
Prepare Instacart Market Basket data for customer behavior SQL analysis.

Reads raw CSVs from ../Instacart/, engineers order-level and user-department
aggregates, and writes cleaned files to data/.
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT.parent / "Instacart"
OUT_DIR = ROOT / "data"

ORDER_PRODUCT_FILES = [
    RAW_DIR / "order_products__prior.csv",
    RAW_DIR / "order_products__train.csv",
]


def load_dimensions() -> pd.DataFrame:
    products = pd.read_csv(RAW_DIR / "products.csv")
    aisles = pd.read_csv(RAW_DIR / "aisles.csv")
    departments = pd.read_csv(RAW_DIR / "departments.csv")
    return products.merge(aisles, on="aisle_id").merge(departments, on="department_id")


def process_order_products(
    orders: pd.DataFrame, products: pd.DataFrame
) -> tuple[pd.DataFrame, pd.DataFrame]:
    dept_by_product = products.set_index("product_id")["department"].to_dict()
    aisle_by_product = products.set_index("product_id")["aisle_id"].to_dict()
    dept_id_by_product = products.set_index("product_id")["department_id"].to_dict()
    user_by_order = orders.set_index("order_id")["user_id"].to_dict()

    order_stats: dict[int, dict] = {}
    user_dept_counts: dict[tuple[int, str], dict] = {}

    for path in ORDER_PRODUCT_FILES:
        print(f"Processing {path.name} ...")
        for chunk in pd.read_csv(path, chunksize=1_000_000):
            chunk["department"] = chunk["product_id"].map(dept_by_product)
            chunk["aisle_id"] = chunk["product_id"].map(aisle_by_product)
            chunk["department_id"] = chunk["product_id"].map(dept_id_by_product)
            chunk["user_id"] = chunk["order_id"].map(user_by_order)
            chunk = chunk.dropna(subset=["department", "user_id"])
            chunk["user_id"] = chunk["user_id"].astype(int)

            for order_id, group in chunk.groupby("order_id"):
                stats = order_stats.setdefault(
                    order_id,
                    {
                        "cart_size": 0,
                        "reordered_items": 0,
                        "distinct_departments": set(),
                        "distinct_aisles": set(),
                    },
                )
                stats["cart_size"] += len(group)
                stats["reordered_items"] += int(group["reordered"].sum())
                stats["distinct_departments"].update(group["department_id"].dropna().astype(int))
                stats["distinct_aisles"].update(group["aisle_id"].dropna().astype(int))

            grouped = chunk.groupby(["user_id", "department"]).agg(
                items=("product_id", "count"),
                reorders=("reordered", "sum"),
                orders=("order_id", "nunique"),
            )
            for (user_id, department), row in grouped.iterrows():
                key = (int(user_id), department)
                bucket = user_dept_counts.setdefault(
                    key, {"items": 0, "reorders": 0, "orders": 0}
                )
                bucket["items"] += int(row["items"])
                bucket["reorders"] += int(row["reorders"])
                bucket["orders"] += int(row["orders"])

    order_rows = [
        {
            "order_id": order_id,
            "cart_size": stats["cart_size"],
            "reordered_items": stats["reordered_items"],
            "reorder_rate": round(stats["reordered_items"] / stats["cart_size"], 4)
            if stats["cart_size"]
            else 0,
            "distinct_departments": len(stats["distinct_departments"]),
            "distinct_aisles": len(stats["distinct_aisles"]),
        }
        for order_id, stats in order_stats.items()
    ]

    user_dept_rows = [
        {
            "user_id": user_id,
            "department": department,
            "items": vals["items"],
            "reorders": vals["reorders"],
            "orders_with_dept": vals["orders"],
            "reorder_rate": round(vals["reorders"] / vals["items"], 4) if vals["items"] else 0,
        }
        for (user_id, department), vals in user_dept_counts.items()
    ]
    return pd.DataFrame(order_rows), pd.DataFrame(user_dept_rows)


def main() -> None:
    if not RAW_DIR.exists():
        raise FileNotFoundError(f"Instacart raw data not found at {RAW_DIR}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Loading orders and dimensions ...")
    orders = pd.read_csv(RAW_DIR / "orders.csv")
    products = load_dimensions()

    order_metrics, user_departments = process_order_products(orders, products)

    orders = orders.merge(order_metrics, on="order_id", how="left")
    orders["cart_size"] = orders["cart_size"].fillna(0).astype(int)
    orders["reordered_items"] = orders["reordered_items"].fillna(0).astype(int)
    orders["reorder_rate"] = orders["reorder_rate"].fillna(0)
    orders["distinct_departments"] = orders["distinct_departments"].fillna(0).astype(int)
    orders["distinct_aisles"] = orders["distinct_aisles"].fillna(0).astype(int)

    dow_labels = {
        0: "Sunday",
        1: "Monday",
        2: "Tuesday",
        3: "Wednesday",
        4: "Thursday",
        5: "Friday",
        6: "Saturday",
    }
    orders["order_dow_name"] = orders["order_dow"].map(dow_labels)
    orders["is_first_order"] = orders["order_number"] == 1

    products.to_csv(OUT_DIR / "products_dim.csv", index=False)
    orders.to_csv(OUT_DIR / "orders_enriched.csv", index=False)
    user_departments.to_csv(OUT_DIR / "user_departments.csv", index=False)

    print(f"Users: {orders.user_id.nunique():,}")
    print(f"Orders: {len(orders):,}")
    print(f"Products: {len(products):,}")
    print(f"User-department rows: {len(user_departments):,}")
    print(f"Avg cart size: {orders.cart_size.mean():.1f}")
    print(
        "Overall reorder rate:",
        f"{orders.reordered_items.sum() / orders.cart_size.sum():.1%}",
    )
    print(f"Saved cleaned files to {OUT_DIR}")


if __name__ == "__main__":
    main()
