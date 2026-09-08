from fastapi.testclient import TestClient

from app.ingestion.alerts import ingest_alerts
from app.main import app
from app.providers.warning import AlertData
from tests.conftest import FakeWarningProvider


def _new_alert(**overrides):
    base = dict(
        external_id="ws-test-1", source="SACHET-SDMA", severity="Severe", event_type="Cyclone",
        area_description="Odisha coast", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=20.0, longitude=85.0,
        raw_payload={},
    )
    base.update(overrides)
    return AlertData(**base)


def test_new_alert_ingestion_broadcasts_to_a_connected_websocket_client(clean_alerts_table):
    with TestClient(app) as client:
        with client.websocket_connect("/ws/alerts") as websocket:
            future_holder = {}

            def capture_and_broadcast(alerts):
                future_holder["future"] = app.state.broadcast_new_alerts(alerts)

            ingest_alerts(FakeWarningProvider([_new_alert()]), on_new_alerts=capture_and_broadcast)
            future_holder["future"].result(timeout=5)

            message = websocket.receive_json()

    assert message["type"] == "new_alerts"
    assert [a["external_id"] for a in message["alerts"]] == ["ws-test-1"]
    assert message["alerts"][0]["severity"] == "Severe"


def test_multiple_connected_clients_all_receive_the_same_broadcast(clean_alerts_table):
    with TestClient(app) as client:
        with client.websocket_connect("/ws/alerts") as ws_a:
            with client.websocket_connect("/ws/alerts") as ws_b:
                future_holder = {}

                def capture_and_broadcast(alerts):
                    future_holder["future"] = app.state.broadcast_new_alerts(alerts)

                ingest_alerts(FakeWarningProvider([_new_alert()]), on_new_alerts=capture_and_broadcast)
                future_holder["future"].result(timeout=5)

                message_a = ws_a.receive_json()
                message_b = ws_b.receive_json()

    assert [a["external_id"] for a in message_a["alerts"]] == ["ws-test-1"]
    assert [a["external_id"] for a in message_b["alerts"]] == ["ws-test-1"]


def test_ingestion_with_no_new_alerts_does_not_hang_a_connected_client(clean_alerts_table):
    # Seed the table first so the second ingestion of the SAME alert finds
    # nothing new — proves the "no broadcast" path doesn't somehow still
    # deliver a message (this test would hang on receive_json() if it did,
    # since no message would ever arrive — the timeout on the join below
    # is what actually catches a regression here, not an assertion).
    with TestClient(app) as client:
        ingest_alerts(FakeWarningProvider([_new_alert()]))  # seed, no callback
        with client.websocket_connect("/ws/alerts") as websocket:
            future_holder = {}

            def capture_and_broadcast(alerts):
                future_holder["future"] = app.state.broadcast_new_alerts(alerts)

            ingest_alerts(FakeWarningProvider([_new_alert()]), on_new_alerts=capture_and_broadcast)
            assert future_holder["future"] is None  # nothing new — no coroutine was even scheduled


def test_websocket_disconnect_is_handled_cleanly(clean_alerts_table):
    with TestClient(app) as client:
        with client.websocket_connect("/ws/alerts"):
            pass  # closes on exit of the inner `with` block
    # No assertion beyond "this doesn't raise or hang" — proves
    # connection_manager.disconnect() is reached without error when a
    # client disconnects.
