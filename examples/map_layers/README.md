# Map layers

This sample uses `MapLibreMapController` to explore style layers over the
OpenFreeMap Positron basemap.

- Displays earthquake density with a Heatmap layer.
- Opens layer controls from the toolbar without resizing the map.
- Changes radius, intensity, opacity, and magnitude weighting with
  `setLayerProperties`.
- Shows individual earthquake points with `setLayerVisibility`.

The historical USGS earthquake sample comes from the
[MapLibre Heatmap example](https://maplibre.org/maplibre-gl-js/docs/examples/heatmap-layer/).
The basemap comes from [OpenFreeMap](https://openfreemap.org/quick_start/), using
[OpenStreetMap data](https://www.openstreetmap.org/copyright).
Both require internet access and no API key.
