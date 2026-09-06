import httpx

from app.providers.incois import INCOISMarineProvider

FOUND_RESPONSE = {
    "type": "FeatureCollection",
    "totalFeatures": 2,
    "features": [
        {
            "type": "Feature",
            "id": "pfzlines.1",
            "geometry": {
                "type": "MultiLineString",
                "coordinates": [[[68.4367, 22.7704], [68.4363, 22.7694]]],
            },
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 2,
                "SECTORBO_1": 1,
                "SECTORNAME": "",
                "Julian_day": "248",
                "Sno": "001",
                "Year": 2021,
                "UID": 2021248001,
                "Length": 45.9872025145,
            },
        },
        {
            "type": "Feature",
            "id": "pfzlines.2",
            "geometry": {
                "type": "MultiLineString",
                "coordinates": [[[70.1, 20.5], [70.2, 20.6]]],
            },
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 3,
                "SECTORBO_1": 1,
                "SECTORNAME": "West Coast",
                "Julian_day": "248",
                "Sno": "002",
                "Year": 2021,
                "UID": 2021248002,
                "Length": 30.5,
            },
        },
    ],
}

MALFORMED_RESPONSE = {
    "type": "FeatureCollection",
    "totalFeatures": 2,
    "features": [
        {
            "type": "Feature",
            "id": "pfzlines.3",
            "geometry": {"type": "MultiLineString", "coordinates": [[[1.0, 2.0]]]},
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 1,
                "SECTORBO_1": 1,
                "SECTORNAME": "",
                "Julian_day": "100",
                "Sno": "003",
                "Year": 2021,
                "UID": 2021100003,
                "Length": 10.0,
            },
        },
        {
            # Missing "geometry" entirely — malformed, must be skipped, not raise.
            "type": "Feature",
            "id": "pfzlines.4",
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 1,
                "SECTORBO_1": 1,
                "SECTORNAME": "",
                "Julian_day": "100",
                "Sno": "004",
                "Year": 2021,
                "UID": 2021100004,
                "Length": 5.0,
            },
        },
    ],
}


FLOAT_UID_RESPONSE = {
    "type": "FeatureCollection",
    "totalFeatures": 1,
    "features": [
        {
            "type": "Feature",
            "id": "pfzlines.5",
            "geometry": {
                "type": "MultiLineString",
                "coordinates": [[[68.4367, 22.7704], [68.4363, 22.7694]]],
            },
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 2,
                "SECTORBO_1": 1,
                "SECTORNAME": "",
                "Julian_day": "248",
                "Sno": "001",
                "Year": 2021,
                "UID": 2021248001.0,
                "Length": 45.9872025145,
            },
        },
    ],
}

NULL_PROPERTIES_RESPONSE = {
    "type": "FeatureCollection",
    "totalFeatures": 2,
    "features": [
        {
            "type": "Feature",
            "id": "pfzlines.6",
            "geometry": {"type": "MultiLineString", "coordinates": [[[1.0, 2.0]]]},
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 1,
                "SECTORBO_1": 1,
                "SECTORNAME": "",
                "Julian_day": "100",
                "Sno": "006",
                "Year": 2021,
                "UID": 2021100006,
                "Length": 10.0,
            },
        },
        {
            # properties is present but null — must be skipped, not fatal
            # to the whole batch.
            "type": "Feature",
            "id": "pfzlines.7",
            "geometry": {"type": "MultiLineString", "coordinates": [[[3.0, 4.0]]]},
            "properties": None,
        },
    ],
}


def _found_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=FOUND_RESPONSE)


def _malformed_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=MALFORMED_RESPONSE)


def _float_uid_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=FLOAT_UID_RESPONSE)


def _null_properties_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=NULL_PROPERTIES_RESPONSE)


def test_fetch_pfz_zones_normalizes_all_features():
    client = httpx.Client(transport=httpx.MockTransport(_found_handler))
    provider = INCOISMarineProvider(client=client)

    zones = provider.fetch_pfz_zones()

    assert len(zones) == 2
    first = next(z for z in zones if z.external_id == "pfzlines.1")
    assert first.category == "ghrsst"
    assert first.sector_boundary == 2
    assert first.sector_name == ""
    assert first.julian_day == "248"
    assert first.serial_number == "001"
    assert first.year == 2021
    assert first.uid == 2021248001
    assert first.length_km == 45.9872025145
    assert first.geometry == FOUND_RESPONSE["features"][0]["geometry"]
    assert first.raw_payload == FOUND_RESPONSE["features"][0]

    second = next(z for z in zones if z.external_id == "pfzlines.2")
    assert second.sector_name == "West Coast"


def test_fetch_pfz_zones_skips_malformed_feature_without_failing_the_batch():
    client = httpx.Client(transport=httpx.MockTransport(_malformed_handler))
    provider = INCOISMarineProvider(client=client)

    zones = provider.fetch_pfz_zones()

    assert len(zones) == 1
    assert zones[0].external_id == "pfzlines.3"


def test_fetch_pfz_zones_coerces_float_uid_to_int():
    client = httpx.Client(transport=httpx.MockTransport(_float_uid_handler))
    provider = INCOISMarineProvider(client=client)

    zones = provider.fetch_pfz_zones()

    assert len(zones) == 1
    assert zones[0].uid == 2021248001
    assert isinstance(zones[0].uid, int)


def test_fetch_pfz_zones_skips_feature_with_null_properties_without_failing_the_batch():
    client = httpx.Client(transport=httpx.MockTransport(_null_properties_handler))
    provider = INCOISMarineProvider(client=client)

    zones = provider.fetch_pfz_zones()

    assert len(zones) == 1
    assert zones[0].external_id == "pfzlines.6"
