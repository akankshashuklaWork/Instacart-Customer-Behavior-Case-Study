"""
Load cleaned Instacart data into SQLite for customer behavior SQL analysis.
"""
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
DB_PATH = DATA_DIR / "instacart.db"


def main() -> None:
    orders = pd.read_csv(DATA_DIR / "orders_enriched.csv")
    products = pd.read_csv(DATA_DIR / "products_dim.csv")
    user_departments = pd.read_csv(DATA_DIR / "user_departments.csv")

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    if DB_PATH.exists():
        DB_PATH.unlink()

    conn = sqlite3.connect(DB_PATH)
    orders.to_sql("orders", conn, if_exists="replace", index=False)
    products.to_sql("products", conn, if_exists="replace", index=False)
    user_departments.to_sql("user_departments", conn, if_exists="replace", index=False)

    conn.execute("CREATE INDEX idx_orders_user ON orders(user_id);")
    conn.execute("CREATE INDEX idx_orders_number ON orders(order_number);")
    conn.execute("CREATE INDEX idx_orders_dow ON orders(order_dow);")
    conn.execute("CREATE INDEX idx_user_dept_user ON user_departments(user_id);")
    conn.execute("CREATE INDEX idx_user_dept_dept ON user_departments(department);")
    conn.execute("CREATE INDEX idx_products_dept ON products(department_id);")
    conn.commit()

    cur = conn.execute(
        """
        SELECT COUNT(*), COUNT(DISTINCT user_id), COUNT(DISTINCT order_id)
        FROM orders;
        """
    )
    print("Order rows, Users, Orders:", cur.fetchone())
    conn.close()
    print(f"SQLite DB built: {DB_PATH}")


if __name__ == "__main__":
    main()
