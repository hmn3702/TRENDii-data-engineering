"""
End-to-end tests: run the pipeline on the hand-made fixture (see conftest.py)
and check every answer against values worked out by hand.
"""
import subprocess
import sys

from conftest import BED, DESK, OZ, ROOT, WRONG_BRAND

FF_CAMPAIGN = "14929485386"   # Fantastic Furniture, CPC 1.00
OZ_CAMPAIGN = "33451439714"   # Oz Home Hub, CPC 0.50 until 12 May, 0.75 from 13 May


def rows(con, sql):
    return con.execute(sql).fetchall()


# ---------------------------------------------------------------- pipeline run

def test_pipeline_succeeds_and_exports_answers(pipeline_run):
    assert pipeline_run["result"].returncode == 0, pipeline_run["result"].stderr
    files = sorted(p.name for p in pipeline_run["output"].glob("*.csv"))
    assert files == [
        "q1_top_articles_by_domain.csv",
        "q2_top_clicked_products_final_week.csv",
        "q3_top_product_per_campaign.csv",
        "q4_mount_rate_by_domain.csv",
        "q5_unique_users_advertised.csv",
    ]


def test_missing_data_folder_fails_cleanly(tmp_path):
    result = subprocess.run(
        [sys.executable, str(ROOT / "run_pipeline.py"), "--data-dir", str(tmp_path / "nope"),
         "--db", str(tmp_path / "x.duckdb"), "--output-dir", str(tmp_path / "out")],
        capture_output=True, text=True,
    )
    assert result.returncode == 1
    assert "Data folder not found" in result.stderr


# ---------------------------------------------------------------- staging

def test_bad_event_is_quarantined_not_loaded(con):
    assert rows(con, "SELECT reject_reason FROM stg_events_rejected") == [("missing page_view_id",)]


def test_duplicate_event_is_removed(con):
    # 6 events on day 12 + 12 rows on day 13, minus 1 duplicate and 1 rejected
    assert rows(con, "SELECT count(*), count(DISTINCT event_id) FROM stg_events") == [(16, 16)]


def test_event_date_comes_from_partition_not_ingestion_time(con):
    # click c4 was ingested 2025-05-14 00:01 but generated on 13 May
    assert rows(con, "SELECT event_date::VARCHAR, clicked_at::DATE::VARCHAR FROM fct_product_clicks WHERE click_id = 'c4'") \
        == [("2025-05-13", "2025-05-14")]


# ---------------------------------------------------------------- facts

def test_impressions_are_deduplicated_with_raw_count_kept(con):
    assert rows(con, f"""
        SELECT impression_occurrences FROM fct_product_impressions
        WHERE page_view_id = 'pv1' AND image_id = 'img1' AND product_id = '{DESK}'""") == [(2,)]
    assert rows(con, "SELECT count(*), sum(impression_occurrences) FROM fct_product_impressions") == [(7, 8)]


def test_brand_comes_from_product_table_not_event(con):
    assert rows(con, f"SELECT count(*) FROM fct_product_impressions WHERE brand_id = '{WRONG_BRAND}'") == [(0,)]
    assert rows(con, f"SELECT count(*) FROM fct_product_clicks WHERE brand_id = '{WRONG_BRAND}'") == [(0,)]


def test_campaign_version_matches_event_date(con):
    # Oz Home Hub rate changed on 13 May: c2 (12 May) earns 0.50, c3 (13 May) earns 0.75
    assert rows(con, "SELECT click_id, cpc_revenue FROM fct_product_clicks "
                     f"WHERE campaign_id = '{OZ_CAMPAIGN}' ORDER BY click_id") == [("c2", 0.5), ("c3", 0.75)]
    assert rows(con, f"SELECT sum(cpc_revenue) FROM fct_product_clicks WHERE campaign_id = '{FF_CAMPAIGN}'") == [(3.0,)]


def test_page_view_funnel(con):
    assert rows(con, """
        SELECT page_view_id, mounted_images, impressed_images, product_impressions, clicks, has_mount
        FROM fct_page_views ORDER BY page_view_id""") == [
        ("pv1", 2, 2, 3, 2, True),
        ("pv2", 1, 1, 2, 2, True),
        ("pv3", 0, 0, 0, 0, False),
        ("pv4", 1, 1, 2, 1, True),
    ]


def test_same_device_on_two_publishers_is_two_users(con):
    assert rows(con, "SELECT user_key FROM dim_user ORDER BY user_key") == [("1:d1",), ("1:d2",), ("2:d1",)]


# ---------------------------------------------------------------- answers

def test_q1_top_articles(con):
    assert rows(con, "SELECT domain, traffic_rank, article_url, tagloads FROM ans_q1_top_articles_by_domain") == [
        ("a.com", 1, "a.com/art1", 2),
        ("a.com", 2, "a.com/art2", 1),
        ("b.com", 1, "b.com/x", 1),
    ]


def test_q2_top_clicked_products_final_week(con):
    assert rows(con, """SELECT week_start::VARCHAR, week_end::VARCHAR, brand_name, click_rank, product_id, clicks
                        FROM ans_q2_top_clicked_products_final_week""") == [
        ("2025-05-07", "2025-05-13", "Fantastic Furniture", 1, DESK, 2),
        ("2025-05-07", "2025-05-13", "Fantastic Furniture", 2, BED, 1),
        ("2025-05-07", "2025-05-13", "theozhomehub", 1, OZ, 2),
    ]


def test_q3_top_product_per_campaign(con):
    assert rows(con, """SELECT campaign_id, product_id, impressions, raw_impression_occurrences
                        FROM ans_q3_top_product_per_campaign ORDER BY campaign_id""") == [
        (FF_CAMPAIGN, DESK, 3, 4),
        (OZ_CAMPAIGN, OZ, 2, 2),
    ]


def test_q4_mount_rate(con):
    assert rows(con, "SELECT * FROM ans_q4_mount_rate_by_domain") == [
        ("a.com", 3, 2, 66.67, 3, 1.0),
        ("b.com", 1, 1, 100.0, 1, 1.0),
        ("ALL DOMAINS", 4, 3, 75.0, 4, 1.0),
    ]


def test_q5_unique_users_advertised(con):
    assert rows(con, "SELECT * FROM ans_q5_unique_users_advertised") == [
        ("a.com", 2, 2, 100.0),
        ("b.com", 1, 1, 100.0),
        ("ALL DOMAINS", 3, 3, 100.0),
    ]
