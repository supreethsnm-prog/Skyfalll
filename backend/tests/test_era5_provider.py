import shutil
import tempfile
import zipfile

import pytest

from app.providers.era5 import CdsEra5Provider

FIXTURE = "tests/fixtures/era5_mumbai_sample.zip"


def test_parses_the_real_committed_fixture_into_correct_converted_values():
    provider = CdsEra5Provider(client=None)  # no real client needed — parsing only
    reading = provider._parse_response(
        FIXTURE,
        location_name="Mumbai",
        latitude=19.08,
        longitude=72.88,
        observation_date="2023-07-15",
    )

    assert reading is not None
    assert reading.location_name == "Mumbai"
    assert reading.observation_date == "2023-07-15"
    # Real values from this exact fixture, hand-verified against the raw
    # NetCDF (t2m 300.45037841796875 K -> 27.30C; msl 100651.625 Pa ->
    # 1006.52 hPa; tp 0.0007300376892089844 m -> 0.73 mm; u10 4.1006622,
    # v10 1.7135010 m/s -> 4.4443 m/s -> 16.00 km/h from 247.32 deg, i.e.
    # WSW — the July monsoon flow, as expected for Mumbai mid-July).
    assert abs(reading.temp_2m_c - 27.30) < 0.01
    assert abs(reading.dewpoint_2m_c - 25.39) < 0.01
    assert abs(reading.wind_speed_10m_kmh - 16.00) < 0.05
    assert abs(reading.wind_direction_10m_deg - 247.32) < 0.1
    assert abs(reading.mslp_hpa - 1006.52) < 0.01
    assert abs(reading.precip_mm - 0.73) < 0.01


def test_returns_none_fields_gracefully_if_a_variable_is_absent():
    # A defensive check, not exercised by the fixture (which has all six
    # variables) — confirms the parser doesn't crash if a future request
    # variant omits one, consistent with the nullable reading columns.
    provider = CdsEra5Provider(client=None)
    with tempfile.TemporaryDirectory() as tmp:
        partial_zip = f"{tmp}/partial.zip"
        # Build a zip containing only the "instant" member from the real
        # fixture (drop "accum"/tp) — proves precip_mm comes back None
        # rather than crashing when one file is simply missing.
        with zipfile.ZipFile(FIXTURE) as src:
            with zipfile.ZipFile(partial_zip, "w") as dst:
                for name in src.namelist():
                    if "instant" in name:
                        dst.writestr(name, src.read(name))

        reading = provider._parse_response(
            partial_zip,
            location_name="Mumbai",
            latitude=19.08,
            longitude=72.88,
            observation_date="2023-07-15",
        )
        assert reading.precip_mm is None
        assert reading.temp_2m_c is not None


def test_parses_a_plain_unzipped_netcdf_response():
    # CDS returns a bare NetCDF file (not a zip) when a request happens to
    # resolve to a single stepType, so the parser must sniff the container
    # rather than trust the target filename.
    provider = CdsEra5Provider(client=None)
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(FIXTURE) as src:
            instant = next(n for n in src.namelist() if "instant" in n)
            # Deliberately extension-less, exactly like the retrieve() target.
            plain = f"{tmp}/era5_response"
            with src.open(instant) as member, open(plain, "wb") as out:
                shutil.copyfileobj(member, out)

        assert not zipfile.is_zipfile(plain)
        reading = provider._parse_response(
            plain,
            location_name="Mumbai",
            latitude=19.08,
            longitude=72.88,
            observation_date="2023-07-15",
        )
        assert abs(reading.temp_2m_c - 27.30) < 0.01
        assert reading.precip_mm is None


def test_fetch_reading_without_a_key_raises_a_pointed_error(monkeypatch):
    # The lazy-client design means construction never needs a key, but an
    # actual fetch does — and the error must say how to get one.
    from app.config import Settings, get_settings

    get_settings.cache_clear()
    monkeypatch.setattr(
        "app.config.get_settings", lambda: Settings(cds_api_key=None, _env_file=None)
    )
    provider = CdsEra5Provider()
    with pytest.raises(ValueError, match="CDS_API_KEY"):
        provider.fetch_reading("Delhi", 28.61, 77.21, "2023-01-15")
    get_settings.cache_clear()


def test_fetch_reading_builds_the_expected_cds_request_and_parses_the_result():
    # A stub client stands in for the real CDS client so the full
    # fetch_reading path (request shape + zip parsing) is covered without a
    # 25s-to-2min live call.
    captured = {}

    class _StubClient:
        def retrieve(self, dataset, request, target):
            captured["dataset"] = dataset
            captured["request"] = request
            shutil.copyfile(FIXTURE, target)

    provider = CdsEra5Provider(client=_StubClient())
    reading = provider.fetch_reading("Mumbai", 19.08, 72.88, "2023-07-15")

    assert captured["dataset"] == "reanalysis-era5-single-levels"
    request = captured["request"]
    assert request["product_type"] == "reanalysis"
    assert request["data_format"] == "netcdf"
    assert (request["year"], request["month"], request["day"]) == ("2023", "07", "15")
    assert "2m_temperature" in request["variable"]
    assert "total_precipitation" in request["variable"]
    # [north, west, south, east] — a 1-degree box centred on the point.
    north, west, south, east = request["area"]
    assert north == pytest.approx(19.58)
    assert west == pytest.approx(72.38)
    assert south == pytest.approx(18.58)
    assert east == pytest.approx(73.38)

    assert abs(reading.temp_2m_c - 27.30) < 0.01
    assert abs(reading.precip_mm - 0.73) < 0.01
    provider.close()
