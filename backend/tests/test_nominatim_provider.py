import httpx

from app.providers.nominatim import NominatimGeocodingProvider

FOUND_RESPONSE = [
    {
        "place_id": 248916270,
        "licence": "Data © OpenStreetMap contributors, ODbL 1.0. http://osm.org/copyright",
        "osm_type": "node",
        "osm_id": 16173235,
        "lat": "19.0549990",
        "lon": "72.8692035",
        "category": "place",
        "type": "city",
        "place_rank": 16,
        "importance": 0.7153284564294777,
        "addresstype": "city",
        "name": "Mumbai",
        "display_name": "Mumbai, Mumbai Suburban District, Maharashtra, 400051, India",
        "address": {
            "city": "Mumbai",
            "state_district": "Mumbai Suburban District",
            "state": "Maharashtra",
            "ISO3166-2-lvl4": "IN-MH",
            "postcode": "400051",
            "country": "India",
            "country_code": "in",
        },
        "boundingbox": ["18.8949990", "19.2149990", "72.7092035", "73.0292035"],
    }
]

NOT_FOUND_RESPONSE: list = []


def _found_handler(request: httpx.Request) -> httpx.Response:
    assert request.headers["User-Agent"] == "WeatherGPT/0.1 (SIH 2026 hackathon project)"
    return httpx.Response(200, json=FOUND_RESPONSE)


def _not_found_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=NOT_FOUND_RESPONSE)


def test_geocode_returns_normalized_result_when_found():
    client = httpx.Client(transport=httpx.MockTransport(_found_handler))
    provider = NominatimGeocodingProvider(client=client)

    result = provider.geocode("mumbai")

    assert result is not None
    assert result.query == "mumbai"
    assert result.display_name == (
        "Mumbai, Mumbai Suburban District, Maharashtra, 400051, India"
    )
    assert result.latitude == 19.0549990
    assert result.longitude == 72.8692035
    assert result.country == "India"
    assert result.state == "Maharashtra"
    assert result.raw_payload == FOUND_RESPONSE[0]


def test_geocode_returns_none_when_not_found():
    client = httpx.Client(transport=httpx.MockTransport(_not_found_handler))
    provider = NominatimGeocodingProvider(client=client)

    result = provider.geocode("zzznonexistentplacexyz123456")

    assert result is None
