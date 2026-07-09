#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PYTHON="${PYTHON:-python3}"
if [[ -x ".venv/bin/python" ]]; then
  PYTHON=".venv/bin/python"
fi

echo "==> Step 1/2: Clean raw data"
"$PYTHON" scripts/01_clean_data.py

echo "==> Step 2/3: Build SQLite database"
"$PYTHON" scripts/02_build_sql_db.py

echo "==> Step 3/3: Generate chart"
"$PYTHON" scripts/03_generate_chart.py

echo ""
echo "Done."
echo "  Schema check:  sqlite3 data/instacart.db < sql/00_schema_exploration.sql"
echo "  Analysis:      sqlite3 data/instacart.db < sql/analysis_queries.sql"
