import pytest

from app.geo import haversine_km


def test_haversine_same_point_is_zero():
    assert haversine_km(19.05, 72.87, 19.05, 72.87) == 0.0


def test_haversine_known_distance_mumbai_to_delhi():
    # Real-world distance Mumbai <-> Delhi is ~1150-1160 km great-circle.
    distance = haversine_km(19.0760, 72.8777, 28.7041, 77.1025)
    assert 1100 < distance < 1200


def test_haversine_is_symmetric():
    a_to_b = haversine_km(19.05, 72.87, 28.6, 77.2)
    b_to_a = haversine_km(28.6, 77.2, 19.05, 72.87)
    assert a_to_b == pytest.approx(b_to_a)
