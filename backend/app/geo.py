"""Shared great-circle distance helper.

No PostGIS or other geospatial extension is used in this codebase — at the
row counts involved (hundreds of alerts, tens of PFZ zones), a plain
in-Python haversine calculation over already-fetched rows is simpler to
operate than adding a database extension, and fast enough that it never
needs to run inside SQL.
"""

import math

_EARTH_RADIUS_KM = 6371.0


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * _EARTH_RADIUS_KM * math.asin(math.sqrt(a))
