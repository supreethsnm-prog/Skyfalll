import threading

from sqlalchemy import select

from app.db import get_engine
from app.ingestion.alerts import ingest_alerts
from app.models import Alert
from app.providers.warning import AlertData
from tests.conftest import FakeWarningProvider


def test_ingest_alerts_removes_rows_absent_from_the_latest_fetch(clean_alerts_table):
    stale_alert = AlertData(
        external_id="resolved-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Old", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([stale_alert]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1  # sanity check before reconciliation

    still_active = AlertData(
        external_id="active-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="New", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([still_active]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert {r["external_id"] for r in rows} == {"active-1"}


def test_ingest_alerts_keeps_rows_still_present_in_the_latest_fetch(clean_alerts_table):
    alert = AlertData(
        external_id="persistent-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Still here", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([alert]))
    ingest_alerts(FakeWarningProvider([alert]))  # same external_id, second run

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "persistent-1"


def test_ingest_alerts_does_not_wipe_existing_rows_on_an_empty_fetch(clean_alerts_table):
    alert = AlertData(
        external_id="keep-me-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Should survive", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([alert]))

    count = ingest_alerts(FakeWarningProvider([]))  # empty fetch

    assert count == 0
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "keep-me-1"


def _sample_alert(severity: str = "ALERT") -> AlertData:
    return AlertData(
        external_id="ingest-test-1",
        source="SACHET-SDMA",
        severity=severity,
        event_type="Flood",
        area_description="Test District",
        effective_start_time="Sat Sep 05 16:05:00 IST 2026",
        effective_end_time="Sat Sep 05 18:05:00 IST 2026",
        warning_message="Test warning message.",
        severity_color="red",
        latitude=15.37,
        longitude=75.12,
        raw_payload={"identifier": "ingest-test-1"},
    )


def test_ingest_alerts_inserts_new_alert(clean_alerts_table):
    count = ingest_alerts(FakeWarningProvider([_sample_alert()]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(Alert).where(Alert.external_id == "ingest-test-1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].severity == "ALERT"


def test_ingest_alerts_upserts_existing_alert_by_external_id(clean_alerts_table):
    ingest_alerts(FakeWarningProvider([_sample_alert(severity="ALERT")]))
    count = ingest_alerts(FakeWarningProvider([_sample_alert(severity="WATCH")]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(Alert).where(Alert.external_id == "ingest-test-1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].severity == "WATCH"


def test_ingest_alerts_reconciliation_is_scoped_by_source(clean_alerts_table):
    # SACHETWarningProvider.fetch_alerts() concatenates two independent
    # endpoints (SDMA, IMD-NOWCAST) into one list. Each has pre-existing
    # leniency that can silently degrade to zero rows for just ONE of them
    # (e.g. _fetch_imd_nowcast_alerts()'s `.get("nowcastDetails", [])`)
    # without the overall fetch being empty. Reconciliation must therefore
    # only delete rows within the sources that actually contributed rows
    # this cycle — otherwise a degraded IMD-NOWCAST endpoint would look
    # like "all IMD-NOWCAST alerts resolved" and wipe them out.
    sdma_alert = AlertData(
        external_id="sdma-old-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="SDMA area", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    imd_nowcast_alert = AlertData(
        external_id="imd-nowcast-1", source="SACHET-IMD-NOWCAST", severity="Severe",
        event_type="Thunderstorm", area_description="IMD area", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=13.08, longitude=80.27, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([sdma_alert, imd_nowcast_alert]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert {r["external_id"] for r in rows} == {"sdma-old-1", "imd-nowcast-1"}  # sanity check

    # Simulate IMD-NOWCAST silently degrading to empty (e.g. the
    # "nowcastDetails" key disappearing upstream) while SDMA keeps working
    # and reports a DIFFERENT alert than before.
    new_sdma_alert = AlertData(
        external_id="sdma-new-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="SDMA area v2", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.10, longitude=72.90, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([new_sdma_alert]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    external_ids = {r["external_id"] for r in rows}
    # The old SDMA row should be reconciled away (SDMA reported a fresh
    # fetch that no longer includes it), but the IMD-NOWCAST row must
    # SURVIVE untouched, since IMD-NOWCAST contributed nothing this cycle.
    # Without source-scoping, the old `notin_`-only delete would remove
    # "imd-nowcast-1" too, since its external_id is absent from this fetch.
    assert external_ids == {"sdma-new-1", "imd-nowcast-1"}


def test_ingest_alerts_concurrent_calls_do_not_deadlock_or_corrupt_state(clean_alerts_table):
    # Regression test for a real, empirically-reproduced bug: the
    # scheduler's background thread and the manual /internal/ingest/alerts
    # endpoint can call ingest_alerts() concurrently. Without serialization
    # via a Postgres advisory lock, concurrent transactions racing through
    # upsert + reconciliation caused real deadlocks and lost-insert windows
    # against a live Postgres database. This spawns several real threads
    # calling the SAME function against the same table to prove the
    # advisory lock (taken as the first statement inside the transaction)
    # serializes them safely.
    shared_alert = AlertData(
        external_id="shared-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Shared", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )

    def _fetch_for_thread(n: int) -> list[AlertData]:
        # Each thread's fetch overlaps on "shared-1" (so real upsert +
        # reconciliation logic runs across the overlap) but also carries a
        # thread-specific alert, so the final state must correspond
        # entirely to ONE thread's fetch set, never a mix of two.
        thread_specific = AlertData(
            external_id=f"thread-{n}-1", source="SACHET-SDMA", severity="Moderate",
            event_type="Flood", area_description=f"Thread {n}", effective_start_time=None,
            effective_end_time=None, warning_message=None, severity_color=None,
            latitude=19.05, longitude=72.87, raw_payload={},
        )
        return [shared_alert, thread_specific]

    fetch_sets = {n: {a.external_id for a in _fetch_for_thread(n)} for n in range(5)}
    errors: list[BaseException] = []
    barrier = threading.Barrier(5)

    def _worker(n: int) -> None:
        try:
            barrier.wait()  # maximize overlap so the lock is actually exercised
            ingest_alerts(FakeWarningProvider(_fetch_for_thread(n)))
        except BaseException as exc:  # noqa: BLE001 - capture for the assertion below
            errors.append(exc)

    threads = [threading.Thread(target=_worker, args=(n,)) for n in range(5)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30.0)

    assert not errors  # no deadlock/exception should propagate from any thread

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    final_ids = {r["external_id"] for r in rows}

    # The final state must match exactly ONE thread's fetch set - not a
    # mix of half-applied writes from two different threads.
    assert final_ids in fetch_sets.values()


def test_ingest_calls_on_new_alerts_with_only_genuinely_new_alerts(clean_alerts_table):
    from app.providers.warning import AlertData
    from tests.conftest import FakeWarningProvider

    existing = AlertData(
        external_id="old-1", source="SACHET-SDMA", severity="Minor", event_type="Flood",
        area_description=None, effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=None, longitude=None,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([existing]))  # seed the table on a first cycle, no callback

    new_one = AlertData(
        external_id="new-1", source="SACHET-SDMA", severity="Severe", event_type="Cyclone",
        area_description="Odisha coast", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=20.0, longitude=85.0,
        raw_payload={},
    )
    captured = []
    ingest_alerts(FakeWarningProvider([existing, new_one]), on_new_alerts=captured.append)

    assert len(captured) == 1
    assert [a["external_id"] for a in captured[0]] == ["new-1"]
    assert captured[0][0]["severity"] == "Severe"
    assert captured[0][0]["event_type"] == "Cyclone"
    assert "raw_payload" not in captured[0][0]
    assert "id" not in captured[0][0]


def test_ingest_calls_on_new_alerts_with_empty_list_when_nothing_is_new(clean_alerts_table):
    from app.providers.warning import AlertData
    from tests.conftest import FakeWarningProvider

    existing = AlertData(
        external_id="old-1", source="SACHET-SDMA", severity="Minor", event_type="Flood",
        area_description=None, effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=None, longitude=None,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([existing]))

    captured = []
    ingest_alerts(FakeWarningProvider([existing]), on_new_alerts=captured.append)

    assert captured == [[]]


def test_ingest_without_on_new_alerts_still_works_unchanged(clean_alerts_table):
    from app.providers.warning import AlertData
    from tests.conftest import FakeWarningProvider

    alert = AlertData(
        external_id="a-1", source="SACHET-SDMA", severity="Minor", event_type="Flood",
        area_description=None, effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=None, longitude=None,
        raw_payload={},
    )
    count = ingest_alerts(FakeWarningProvider([alert]))  # no on_new_alerts at all
    assert count == 1


def test_a_raising_on_new_alerts_callback_does_not_fail_the_ingestion(clean_alerts_table):
    # The ingestion has already COMMITTED by the time on_new_alerts runs, so a
    # failure in the notification layer must never be misreported as an
    # ingestion failure. The concrete reachable case is
    # asyncio.run_coroutine_threadsafe against an already-closed event loop
    # (a shutdown race), which raises synchronously — previously that
    # propagated out of ingest_alerts, making the scheduled job log
    # "ingestion failed" for a fully successful run and making
    # /internal/ingest/alerts return a false HTTP 500 that an operator would
    # reasonably retry.
    alert = AlertData(
        external_id="callback-boom-1", source="SACHET-SDMA", severity="Severe",
        event_type="Cyclone", area_description="Odisha coast", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=20.0, longitude=85.0, raw_payload={},
    )

    def _exploding_callback(new_alerts):
        raise RuntimeError("Event loop is closed")

    count = ingest_alerts(FakeWarningProvider([alert]), on_new_alerts=_exploding_callback)

    # The ingestion's own success is unaffected by the broken notification.
    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(Alert).where(Alert.external_id == "callback-boom-1")
        ).fetchall()
    assert len(rows) == 1  # and the data really did commit


def test_ingest_does_not_call_on_new_alerts_when_fetch_is_empty(clean_alerts_table):
    from tests.conftest import FakeWarningProvider

    captured = []
    count = ingest_alerts(FakeWarningProvider([]), on_new_alerts=captured.append)

    assert count == 0
    assert captured == []  # the empty-fetch guard returns before any callback logic runs
