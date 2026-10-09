"""Geographic coordinate helpers for the Lagos map pipeline.

Converts WGS84 lat/lon to a local metre coordinate system anchored at a
documented origin (spec §3.3, §8.2). We never use raw lat/lon as world
positions. The transform is an equirectangular (local tangent plane)
approximation, which is accurate to well under a metre across a few-kilometre
chunk at Lagos' latitude and keeps the map near a local origin to avoid
floating-point precision issues (spec §8.5).

Axis convention (matches the Godot vehicle controller, spec §5.3):
    East  -> +X
    North -> +Z
    Up    -> +Y
"""
from __future__ import annotations
import math

# WGS84 mean metres-per-degree at the equator for latitude; longitude scaled by
# cos(latitude). These constants are standard local-tangent-plane values.
_M_PER_DEG_LAT = 110574.0
_M_PER_DEG_LON_EQ = 111320.0


def latlon_to_local(lat: float, lon: float, lat0: float, lon0: float) -> tuple[float, float]:
    """Return (x_east_m, z_north_m) relative to the (lat0, lon0) origin."""
    x = (lon - lon0) * _M_PER_DEG_LON_EQ * math.cos(math.radians(lat0))
    z = (lat - lat0) * _M_PER_DEG_LAT
    return x, z


def local_to_latlon(x: float, z: float, lat0: float, lon0: float) -> tuple[float, float]:
    """Inverse of latlon_to_local (useful for debugging / round-trip checks)."""
    lat = lat0 + z / _M_PER_DEG_LAT
    lon = lon0 + x / (_M_PER_DEG_LON_EQ * math.cos(math.radians(lat0)))
    return lat, lon


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres, for validating the local transform
    preserves approximate real-world distances (spec §18 map tests)."""
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))
