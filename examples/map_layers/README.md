# Map layers

This sample uses `MapLibreMapController` to explore style layers over the
OpenFreeMap Positron basemap.

- Switches between earthquake density and Alpine shaded relief.
- Opens layer controls from the toolbar without resizing the map.
- Changes radius, intensity, opacity, and magnitude weighting with
  `setLayerProperties`.
- Shows individual earthquake points with `setLayerVisibility`.
- Adjusts hillshade exaggeration, light direction and altitude, and shading method.

The historical USGS earthquake sample comes from the
[MapLibre Heatmap example](https://maplibre.org/maplibre-gl-js/docs/examples/heatmap-layer/).
The [MapLibre Hillshade example](https://maplibre.org/maplibre-gl-js/docs/examples/add-a-hillshade-layer/)
provides [AW3D30 (JAXA)](https://earth.jaxa.jp/en/data/policy/) elevation tiles around Innsbruck.
The basemap comes from [OpenFreeMap](https://openfreemap.org/quick_start/), using
[OpenStreetMap data](https://www.openstreetmap.org/copyright).
The data sources require internet access and no API key.
