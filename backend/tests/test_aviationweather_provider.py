import httpx

from app.providers.aviationweather import AviationWeatherGovProvider

FOUND_RESPONSE = [
    {
        "icaoId": "VABB",
        "receiptTime": "2026-09-06T09:06:14.422Z",
        "obsTime": 1788685200,
        "reportTime": "2026-09-06T09:00:00.000Z",
        "temp": 30,
        "dewp": 25,
        "wdir": 280,
        "wspd": 12,
        "visib": 1.86,
        "altim": 1011,
        "qcField": 16,
        "wxString": "BR",
        "metarType": "METAR",
        "rawOb": "METAR VABB 060900Z 28012KT 3000 BR SCT018 FEW025TCU BKN090 30/25 Q1011 NOSIG",
        "lat": 19.1,
        "lon": 72.859,
        "elev": 14,
        "name": "Mumbai/Shivaji Intl, MM, IN",
        "cover": "BKN",
        "clouds": [
            {"cover": "SCT", "base": 1800},
            {"cover": "FEW", "base": 2500},
            {"cover": "BKN", "base": 9000},
        ],
        "fltCat": "IFR",
    }
]


def _found_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=FOUND_RESPONSE)


def _not_found_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(204, content=b"")


def test_fetch_metar_returns_normalized_result_when_found():
    client = httpx.Client(transport=httpx.MockTransport(_found_handler))
    provider = AviationWeatherGovProvider(client=client)

    result = provider.fetch_metar("VABB")

    assert result is not None
    assert result.icao_id == "VABB"
    assert result.raw_metar == (
        "METAR VABB 060900Z 28012KT 3000 BR SCT018 FEW025TCU BKN090 30/25 Q1011 NOSIG"
    )
    assert result.observed_at == "2026-09-06T09:00:00.000Z"
    assert result.temperature_c == 30
    assert result.dewpoint_c == 25
    assert result.wind_dir_deg == 280
    assert result.wind_speed_kt == 12
    assert result.visibility_sm == 1.86
    assert result.flight_category == "IFR"
    assert result.station_name == "Mumbai/Shivaji Intl, MM, IN"
    assert result.latitude == 19.1
    assert result.longitude == 72.859
    assert result.raw_payload == FOUND_RESPONSE[0]


def test_fetch_metar_returns_none_on_204_empty_response():
    client = httpx.Client(transport=httpx.MockTransport(_not_found_handler))
    provider = AviationWeatherGovProvider(client=client)

    result = provider.fetch_metar("ZZZZ")

    assert result is None
