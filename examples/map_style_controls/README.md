# Semantic map style controls

This sample uses `MapLibreMapController` to change what appears in the
OpenFreeMap Liberty style. It presents familiar map concepts instead of
exposing internal layer IDs.

At startup, the app reads the current style JSON and classifies its layers into
semantic groups. Each control uses `setLayerVisibility` to show or hide 3D
buildings, labels, symbols, roads, or water.
