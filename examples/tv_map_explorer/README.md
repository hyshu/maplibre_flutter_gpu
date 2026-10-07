# TV Map Explorer

An Android-only example for TV remotes with a D-pad and select button. The map
uses OpenFreeMap Liberty and requires internet access without an API key.

- Start in New York's map movement mode. Move the camera with all four
  directions. Hold a direction to keep moving.
- Press select to open the menu. Choose zoom, a flat or tilted view,
  another city or map attribution. Select **Move map** to resume exploring.
- Select **Cities** to choose New York, London, Paris or Sydney with left and
  right, then press select to start exploring that city.
- Every action works with direction and select keys. Back optionally returns
  from the menu to the map, then to the city list.

The controls also accept keyboard arrow keys and Enter or numpad Enter. The
remote's select key maps to `LogicalKeyboardKey.select`. Held select keys do
not repeatedly activate controls.
