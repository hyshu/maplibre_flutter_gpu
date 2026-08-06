import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_landmarks_example/landmarks.dart';

void main() {
  test('world landmark list covers multiple continents', () {
    expect(worldLandmarks, hasLength(greaterThanOrEqualTo(10)));
    expect(
      worldLandmarks.map((landmark) => landmark.country).toSet(),
      containsAll(<String>[
        'Japan',
        'France',
        'United States',
        'Brazil',
        'Egypt',
      ]),
    );
  });

  test('every landmark has a practical destination zoom', () {
    for (final landmark in worldLandmarks) {
      expect(landmark.symbol, isNotEmpty);
      expect(landmark.zoom, inInclusiveRange(9, 17));
    }
  });

  test('marker scale grows with map zoom and stays bounded', () {
    expect(landmarkMarkerScale(1), 0.55);
    expect(landmarkMarkerScale(10), greaterThan(landmarkMarkerScale(2)));
    expect(landmarkMarkerScale(100), 1.15);
  });
}
