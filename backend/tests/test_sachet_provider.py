import httpx

from app.providers.sachet import SACHETWarningProvider

SDMA_FIXTURE = [
    {
        "severity": "ALERT",
        "identifier": 100200300,
        "effective_start_time": "Sat Sep 05 16:05:00 IST 2026",
        "effective_end_time": "Sat Sep 05 18:05:00 IST 2026",
        "disaster_type": "Lightning",
        "area_description": "Belagavi district",
        "severity_level": "Very Likely",
        "type": "Warning",
        "actual_lang": "en",
        "warning_message": "Lightning likely in Belagavi district.",
        "disseminated": "true",
        "severity_color": "orange",
        "alert_id_sdma_autoinc": 42,
        "centroid": "75.1234,15.5678",
        "alert_source": "Karnataka SDMA",
        "area_covered": "Belagavi",
        "sender_org_id": "KA-SDMA",
    },
    {
        "severity": "ALERT",
        "effective_start_time": "Sat Sep 05 16:05:00 IST 2026",
        "effective_end_time": "Sat Sep 05 18:05:00 IST 2026",
        "disaster_type": "Flood",
        "area_description": "Missing identifier record",
        "warning_message": "Malformed record with no identifier field.",
        "severity_color": "red",
        "centroid": "75.0,15.0",
    },
]

NOWCAST_FIXTURE = {
    "nowcastDetails": [
        {
            "severity": "Watch",
            "effective_start_time": "Sat Sep 05 16:05:00 IST 2026",
            "effective_end_time": "Sat Sep 05 18:05:00 IST 2026",
            "identifier": "64f1a2b3c4d5e6f7a8b9c0d1",
            "entry_time": "Sat Sep 05 16:00:00 IST 2026",
            "area_description": "Kumily",
            "source": "IMD",
            "event_category": "Thunderstorm",
            "severity_color": "yellow",
            "location": {"type": "Point", "coordinates": [77.1599, 9.6]},
            "state_id": "KL",
            "events": "Thunderstorm with lightning likely over Kumily.",
        }
    ]
}


def _handler(request: httpx.Request) -> httpx.Response:
    if request.url.path.endswith("FetchAllAlertDetails"):
        return httpx.Response(200, json=SDMA_FIXTURE)
    if request.url.path.endswith("FetchIMDNowcastAlerts"):
        return httpx.Response(200, json=NOWCAST_FIXTURE)
    return httpx.Response(404)


def test_fetch_alerts_normalizes_both_endpoints():
    client = httpx.Client(transport=httpx.MockTransport(_handler))
    provider = SACHETWarningProvider(client=client)

    alerts = provider.fetch_alerts()

    assert len(alerts) == 2
    sdma_alert = next(a for a in alerts if a.source == "SACHET-SDMA")
    assert sdma_alert.external_id == "100200300"
    assert sdma_alert.severity == "ALERT"
    assert sdma_alert.event_type == "Lightning"
    assert sdma_alert.area_description == "Belagavi district"
    assert sdma_alert.longitude == 75.1234
    assert sdma_alert.latitude == 15.5678
    assert sdma_alert.warning_message == "Lightning likely in Belagavi district."
    assert sdma_alert.raw_payload == SDMA_FIXTURE[0]

    nowcast_alert = next(a for a in alerts if a.source == "SACHET-IMD-NOWCAST")
    assert nowcast_alert.external_id == "64f1a2b3c4d5e6f7a8b9c0d1"
    assert nowcast_alert.severity == "Watch"
    assert nowcast_alert.event_type == "Thunderstorm"
    assert nowcast_alert.area_description == "Kumily"
    assert nowcast_alert.longitude == 77.1599
    assert nowcast_alert.latitude == 9.6
    assert nowcast_alert.warning_message == "Thunderstorm with lightning likely over Kumily."
    assert nowcast_alert.raw_payload == NOWCAST_FIXTURE["nowcastDetails"][0]
