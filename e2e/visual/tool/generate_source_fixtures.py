#!/usr/bin/env python3
"""Generate deterministic PMTiles and MBTiles vector fixtures."""

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PMTILES_PYTHON = ROOT / "vendor/maplibre-native/vendor/PMTiles/python/pmtiles"
sys.path.insert(0, str(PMTILES_PYTHON))

from pmtiles.tile import Compression, TileType, zxy_to_tileid  # noqa: E402
from pmtiles.writer import Writer  # noqa: E402

SOURCE = ROOT / "vendor/maplibre-native/test/fixtures/map/issue12432"
OUTPUT = ROOT / "e2e/visual/shared/assets/resources/archives"


def metadata():
    return {
        "name": "MapLibre Flutter GPU source format fixture",
        "vector_layers": [{"id": "water", "fields": {}}],
    }


def write_pmtiles(name, tile_name, *, mlt=False):
    target = OUTPUT / name
    with target.open("wb") as output:
        writer = Writer(output)
        writer.write_tile(zxy_to_tileid(0, 0, 0), (SOURCE / tile_name).read_bytes())
        writer.finalize(
            {
                "tile_type": TileType.MVT,
                "tile_compression": Compression.NONE,
                "min_lon_e7": -1800000000,
                "min_lat_e7": -850511290,
                "max_lon_e7": 1800000000,
                "max_lat_e7": 850511290,
                "center_zoom": 0,
                "center_lon_e7": 0,
                "center_lat_e7": 0,
            },
            metadata(),
        )
    if mlt:
        archive = bytearray(target.read_bytes())
        archive[99] = 6  # PMTiles extension value used by MapLibre Native.
        target.write_bytes(archive)


def write_mbtiles(name, tile_name, *, mlt=False):
    target = OUTPUT / name
    target.unlink(missing_ok=True)
    with sqlite3.connect(target) as database:
        database.executescript(
            """
            CREATE TABLE metadata (name TEXT, value TEXT);
            CREATE TABLE tiles (
              zoom_level INTEGER,
              tile_column INTEGER,
              tile_row INTEGER,
              tile_data BLOB
            );
            CREATE UNIQUE INDEX tile_index
              ON tiles (zoom_level, tile_column, tile_row);
            """
        )
        values = {
            "name": "MapLibre Flutter GPU source format fixture",
            "format": "mlt" if mlt else "pbf",
            "bounds": "-180,-85.051129,180,85.051129",
            "center": "0,0,0",
            "minzoom": "0",
            "maxzoom": "0",
            "json": json.dumps(metadata()),
        }
        database.executemany(
            "INSERT INTO metadata (name, value) VALUES (?, ?)", values.items()
        )
        database.execute(
            "INSERT INTO tiles VALUES (0, 0, 0, ?)",
            ((SOURCE / tile_name).read_bytes(),),
        )


OUTPUT.mkdir(parents=True, exist_ok=True)
write_pmtiles("map-vector.pmtiles", "0-0-0.mvt")
write_pmtiles("map-mlt.pmtiles", "0-0-0.mlt", mlt=True)
write_mbtiles("map-vector.mbtiles", "0-0-0.mvt")
write_mbtiles("map-mlt.mbtiles", "0-0-0.mlt", mlt=True)
