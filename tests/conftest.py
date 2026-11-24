"""
Shared pytest fixtures.

Builds a tiny, hand-made event dataset (Parquet, same nested schema as the
real data) where every answer is known in advance, then runs the full
pipeline on it once per test session.

Scenario (two days, two publishers):

  2025-05-12  pv1  pub 1  a.com/art1  device d1
                   mounts img1, img2
                   img1 shows: desk, desk (duplicate entry), bed
                   img2 shows: oz table
                   clicks: desk on img1, oz table on img2   (Oz CPC rate 0.50 that day)
  2025-05-13  pv2  pub 1  a.com/art1  device d2
                   mounts img3; img3 shows desk, oz table
                   clicks: oz table (rate 0.75 from 13 May), desk
                   -> the desk click is ingested after midnight (2025-05-14 00:01)
  2025-05-13  pv3  pub 1  a.com/art2  device d1   tagload only, no mount
  2025-05-13  pv4  pub 2  b.com/x     device d1   (same device id, other publisher)
                   mounts img4; img4 shows bed, desk; click: bed
                   -> its TagLoaded event is delivered twice (duplicate eid)
  plus one broken event with no page view id (must be quarantined)

Products / brands come from the real dim CSVs in data/:
  desk = Como Desk (Fantastic Furniture, CPC 1.00)
  bed  = Divina Queen Storage Bed (Fantastic Furniture)
  oz   = Oblong Wagon Wheel table (Oz Home Hub, CPC 0.50 -> 0.75 on 13 May)
The event brand_id is deliberately WRONG on every product entry, like the real data.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import duckdb
import pytest

ROOT = Path(__file__).resolve().parents[1]

DESK = "31d9c096799c7e4644da0d90b12a554a"
BED = "751b1daa1895836e17b3e0b2ea868415"
OZ = "f1b08a890212bfc069427c9feb1d7f8b"
WRONG_BRAND = "60ffee806fe59800740af36d"  # The Iconic - never the right brand here

EVENT_DATA_TYPE = (
    "STRUCT(brand_id VARCHAR, click_id VARCHAR, image_id VARCHAR, "
    "mounts STRUCT(image_id VARCHAR, mount_index BIGINT)[], product_id VARCHAR, "
    "product_image_url VARCHAR, product_name VARCHAR, product_price DOUBLE, product_url VARCHAR, "
    "products STRUCT(brand_id VARCHAR, product_id VARCHAR, product_image_url VARCHAR, "
    "product_name VARCHAR, product_price DOUBLE, product_url VARCHAR)[])"
)
EVENT_CONTEXT_TYPE = (
    "STRUCT(did VARCHAR, domain VARCHAR, eid VARCHAR, publisher_id BIGINT, "
    "pvid VARCHAR, ua VARCHAR, url VARCHAR)"
)

UA_MOBILE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile/15E148"
PAGES = {
    "pv1": dict(publisher_id=1, domain="a.com", url="a.com/art1", did="d1"),
    "pv2": dict(publisher_id=1, domain="a.com", url="a.com/art1", did="d2"),
    "pv3": dict(publisher_id=1, domain="a.com", url="a.com/art2", did="d1"),
    "pv4": dict(publisher_id=2, domain="b.com", url="b.com/x", did="d1"),
}


def _event(eid, pvid, name, ts, data=None):
    p = PAGES.get(pvid, PAGES["pv1"])
    return {
        "event_created_at": ts,
        "event_name": name,
        "event_data": data or {},
        "event_context": {
            "did": p["did"], "domain": p["domain"], "eid": eid,
            "publisher_id": p["publisher_id"], "pvid": pvid if pvid in PAGES else None,
            "ua": UA_MOBILE, "url": p["url"],
        },
    }


def _product(pid, price):
    return {"brand_id": WRONG_BRAND, "product_id": pid, "product_name": f"name-{pid[:6]}",
            "product_price": price, "product_url": "https://example.com", "product_image_url": "https://example.com/i.jpg"}


def _click(click_id, image_id, pid, price):
    return {"click_id": click_id, "image_id": image_id, "brand_id": WRONG_BRAND, "product_id": pid,
            "product_name": f"name-{pid[:6]}", "product_price": price,
            "product_url": "https://example.com", "product_image_url": "https://example.com/i.jpg"}


def _mounts(*images):
    return {"mounts": [{"image_id": img, "mount_index": i} for i, img in enumerate(images)]}


def build_events() -> dict[str, list[dict]]:
    day12 = [
        _event("e01", "pv1", "TagLoaded", "2025-05-12T09:00:00"),
        _event("e02", "pv1", "Mounts", "2025-05-12T09:00:01", _mounts("img1", "img2")),
        _event("e03", "pv1", "ProductImpressions", "2025-05-12T09:00:02",
               {"image_id": "img1", "products": [_product(DESK, 119.0), _product(DESK, 119.0), _product(BED, 569.0)]}),
        _event("e04", "pv1", "ProductImpressions", "2025-05-12T09:00:03",
               {"image_id": "img2", "products": [_product(OZ, 326.0)]}),
        _event("e05", "pv1", "ProductClick", "2025-05-12T09:00:10", _click("c1", "img1", DESK, 119.0)),
        _event("e06", "pv1", "ProductClick", "2025-05-12T09:00:20", _click("c2", "img2", OZ, 326.0)),
    ]
    day13 = [
        _event("e07", "pv2", "TagLoaded", "2025-05-13T23:59:00"),
        _event("e08", "pv2", "Mounts", "2025-05-13T23:59:01", _mounts("img3")),
        _event("e09", "pv2", "ProductImpressions", "2025-05-13T23:59:02",
               {"image_id": "img3", "products": [_product(DESK, 119.0), _product(OZ, 326.0)]}),
        _event("e10", "pv2", "ProductClick", "2025-05-13T23:59:30", _click("c3", "img3", OZ, 326.0)),
        _event("e11", "pv2", "ProductClick", "2025-05-14T00:01:00", _click("c4", "img3", DESK, 119.0)),  # late ingest
        _event("e12", "pv3", "TagLoaded", "2025-05-13T10:00:00"),
        _event("e13", "pv4", "TagLoaded", "2025-05-13T11:00:00"),
        _event("e13", "pv4", "TagLoaded", "2025-05-13T11:00:00"),  # duplicate delivery
        _event("e14", "pv4", "Mounts", "2025-05-13T11:00:01", _mounts("img4")),
        _event("e15", "pv4", "ProductImpressions", "2025-05-13T11:00:02",
               {"image_id": "img4", "products": [_product(BED, 569.0), _product(DESK, 119.0)]}),
        _event("e16", "pv4", "ProductClick", "2025-05-13T11:00:09", _click("c5", "img4", BED, 569.0)),
        _event("e17", "missing", "TagLoaded", "2025-05-13T12:00:00"),  # no pvid -> rejected
    ]
    return {"2025-05-12": day12, "2025-05-13": day13}


def _sql(value: str) -> str:
    return value.replace("'", "''")


def write_fixture(target: Path, extra_campaign_rows: list[str] | None = None) -> Path:
    """Write the fixture into `target`. extra_campaign_rows are appended to dim_campaign.csv."""
    target.mkdir(parents=True, exist_ok=True)
    for name in ("dim_product.csv", "dim_campaign.csv"):
        shutil.copy(ROOT / "data" / name, target / name)
    if extra_campaign_rows:
        campaigns = (target / "dim_campaign.csv").read_text(encoding="utf-8").rstrip("\n")
        (target / "dim_campaign.csv").write_text(
            campaigns + "\n" + "\n".join(extra_campaign_rows) + "\n", encoding="utf-8")
    con = duckdb.connect()
    for day, events in build_events().items():
        ndjson = target / f"{day}.ndjson"
        ndjson.write_text("\n".join(json.dumps(e) for e in events), encoding="utf-8")
        con.execute(f"""
            COPY (
                SELECT * FROM read_json('{_sql(ndjson.as_posix())}', format = 'newline_delimited', columns = {{
                    'event_created_at': 'VARCHAR', 'event_name': 'VARCHAR',
                    'event_data': '{EVENT_DATA_TYPE}', 'event_context': '{EVENT_CONTEXT_TYPE}'
                }})
            ) TO '{_sql((target / f"{day}.parquet").as_posix())}' (FORMAT PARQUET)
        """)
        ndjson.unlink()
    con.close()
    return target


def run_pipeline(data_dir: Path, out: Path) -> dict:
    db = out / "test.duckdb"
    result = subprocess.run(
        [sys.executable, str(ROOT / "run_pipeline.py"),
         "--data-dir", str(data_dir), "--db", str(db), "--output-dir", str(out / "output")],
        capture_output=True, text=True,
    )
    return {"result": result, "db": db, "output": out / "output"}


# Folder names contain an apostrophe on purpose: paths are placed inside SQL
# string literals, so this proves they are escaped correctly.
@pytest.fixture(scope="session")
def fixture_dir(tmp_path_factory) -> Path:
    return write_fixture(tmp_path_factory.mktemp("o'brien data"))


@pytest.fixture(scope="session")
def pipeline_run(fixture_dir, tmp_path_factory):
    return run_pipeline(fixture_dir, tmp_path_factory.mktemp("run's output"))


@pytest.fixture(scope="session")
def con(pipeline_run):
    assert pipeline_run["result"].returncode == 0, pipeline_run["result"].stderr
    c = duckdb.connect(str(pipeline_run["db"]), read_only=True)
    yield c
    c.close()
