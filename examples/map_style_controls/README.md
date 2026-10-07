# Semantic map style controls

This sample uses `MapLibreMapController` to change what appears in the
OpenFreeMap Liberty style. It presents familiar map concepts instead of
exposing internal layer IDs.

At startup, the app reads the current style JSON and classifies its layers into
semantic groups. Each control uses `setLayerVisibility` to show or hide 3D
buildings, labels, symbols, roads, or water.

## Current location

Select Current location alongside the map display controls to request
foreground location access and show your position. Select Follow location or
tap the map's location button to recenter and follow your position. The button
also starts location acquisition when it is off. Dragging, rotating, or
scrolling the map stops camera following while leaving the location marker
visible. Clear Current
location to hide the marker and stop location updates. Acquisition status,
retry, and system settings actions appear in the same controls area.

The sample uses `geolocator` to acquire positions and passes them to
`MapLibreMap.userLocation`. The marker and accuracy area use the package's
frame-synchronized renderer. The direction indicator uses the reported GPS
course while moving above 0.5 m/s with valid course accuracy. It does not use the
device compass. Unknown or invalid accuracy and course are omitted.

Location services being disabled, denied permission, and acquisition failures
produce a status message with retry or system settings actions as appropriate.
Subscriptions stop when the app is hidden, paused, or disposed. Returning to the
foreground rechecks existing authorization without showing a permission prompt.
Position updates are coalesced to at most ten per second, and camera commands
are serialized so only the latest pending position is applied.

The Android runner declares coarse and fine location access. Users can grant
approximate location. The iOS runner declares when-in-use access. The macOS
runner declares location usage and the location sandbox entitlement.

This example uses CocoaPods for Apple plugins. Its Podfiles define
`BYPASS_PERMISSION_LOCATION_ALWAYS=1` for `geolocator_apple`, following the
[geolocator setup instructions](https://pub.dev/packages/geolocator).
Background location is disabled in the acquisition settings and is not declared
as an app capability.
