#!/usr/bin/env python3
"""Measure actual Native and GPU location captures and create a review figure."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageStat

ROOT = Path(__file__).resolve().parents[2]
CAPTURES = ROOT / "build/user_location/captures"


def load(implementation):
    directory = CAPTURES / implementation
    metadata = json.loads((directory / "metadata.json").read_text())
    return {capture["scene"]["id"]: capture for capture in metadata["captures"]}


def crop(implementation, item):
    scene_id = item["scene"]["id"]
    image = Image.open(CAPTURES / implementation / f"{implementation}-{scene_id}.png").convert("RGB")
    x, y, width, height = item["viewport"]
    scale = item["dpr"]
    return image.crop(tuple(round(v * scale) for v in (x, y, x + width, y + height)))


def count(mask):
    return mask.histogram()[255]


def masks(image, scale):
    red, green, blue = image.split()
    blue_red = ImageChops.subtract(blue, red)
    blue_green = ImageChops.subtract(blue, green)
    ink = ImageChops.multiply(
        blue_red.point(lambda value: 255 if value > 140 else 0),
        blue_green.point(lambda value: 255 if value > 60 else 0),
    )
    accuracy = ImageChops.multiply(
        blue_red.point(lambda value: 255 if 16 < value < 70 else 0),
        blue_green.point(lambda value: 255 if 5 < value < 40 else 0),
    )
    accuracy = ImageChops.subtract(accuracy, ink.filter(ImageFilter.MaxFilter(2 * round(3 * scale) + 1)))
    background = Image.new("RGB", image.size, (238, 238, 238))
    delta = ImageChops.difference(image, background)
    foreground = delta.convert("L").point(lambda value: 255 if value > 4 else 0)
    return ink, accuracy, foreground


def extents(mask, scale):
    bounds = mask.getbbox()
    if bounds is None:
        return None
    left, top, right, bottom = bounds
    return [(right - left) / scale, (bottom - top) / scale]


def intersection_over_union(first, second):
    union = count(ImageChops.lighter(first, second))
    if union == 0:
        return 1.0
    return count(ImageChops.multiply(first, second)) / union


def font(size):
    for path in ["/System/Library/Fonts/Supplemental/Arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def compare(native, gpu):
    results = []
    pictures = []
    for scene_id, reference in native.items():
        actual = gpu[scene_id]
        assert reference["scene"] == actual["scene"], f"Different inputs for {scene_id}"
        assert reference["dpr"] == actual["dpr"], f"Different display scales for {scene_id}"
        n_image = crop("native", reference)
        g_image = crop("gpu", actual)
        assert n_image.size == g_image.size, f"Different viewports for {scene_id}"
        n_ink, n_accuracy, n_foreground = masks(n_image, reference['dpr'])
        g_ink, g_accuracy, g_foreground = masks(g_image, actual['dpr'])
        union = ImageChops.lighter(n_foreground, g_foreground)
        delta = ImageChops.difference(n_image, g_image)
        means = ImageStat.Stat(delta, mask=union).mean if count(union) else [0, 0, 0]
        visible = reference["scene"].get("visible", True)
        n_position = reference["native"]["position"]
        g_position = actual["gpu"]["markerPosition"]
        anchor_error = math.dist(n_position, g_position) if visible else None
        scale = reference["dpr"]
        n_area = count(n_ink) / (scale * scale)
        g_area = count(g_ink) / (scale * scale)
        marker_iou = intersection_over_union(n_ink, g_ink)
        radius = round(2 * reference["scene"]["accuracy"] / reference["native"]["metersPerPoint"]) / 2
        polygon = actual["gpu"]["accuracyPolygon"]
        radius_error = None
        if polygon:
            radius_error = abs((max(p[0] for p in polygon) - min(p[0] for p in polygon)) / 2 - radius)
        result = {
            "scene": scene_id,
            "anchor_error_logical_px": anchor_error,
            "native_colored_marker_area_logical_px2": n_area,
            "gpu_colored_marker_area_logical_px2": g_area,
            "colored_marker_area_ratio": g_area / n_area if n_area else None,
            "colored_marker_iou": marker_iou,
            "native_accuracy_extent_logical_px": extents(n_accuracy, scale),
            "gpu_accuracy_extent_logical_px": extents(g_accuracy, scale),
            "accuracy_radius_geometry_error_logical_px": radius_error,
            "foreground_mean_absolute_rgb_error_0_255": sum(means) / 3,
            "foreground_iou": intersection_over_union(n_foreground, g_foreground),
            "native_marker_median_rgb": ImageStat.Stat(n_image, mask=n_ink).median if n_area else None,
            "gpu_marker_median_rgb": ImageStat.Stat(g_image, mask=g_ink).median if g_area else None,
        }
        for implementation in ('native', 'gpu'):
            accuracy_extent = result[f'{implementation}_accuracy_extent_logical_px']
            result[f'{implementation}_accuracy_radius_meters'] = (
                accuracy_extent[0] * 0.5 * reference['native']['metersPerPoint']
                if accuracy_extent else None
            )
        errors = []
        if visible:
            if n_area < 75 or g_area < 75:
                errors.append("Visible marker missing or too small")
            if anchor_error > 0.1:
                errors.append("Anchor error exceeds 0.1 logical pixels")
            if not 0.9 <= g_area / n_area <= 1.1:
                errors.append("Colored marker area differs by more than ten percent")
            if marker_iou < 0.9:
                errors.append("Colored marker overlap is below 90 percent")
            if result['foreground_mean_absolute_rgb_error_0_255'] > 5:
                errors.append("Foreground mean RGB error exceeds 5 of 255")
            if max(abs(a - b) for a, b in zip(result['native_marker_median_rgb'], result['gpu_marker_median_rgb'])) > 2:
                errors.append("Marker tint differs by more than two RGB levels")
            if radius_error is None or radius_error > 0.1:
                errors.append("Accuracy radius geometry differs by more than 0.1 logical pixels")
            n_extent = result["native_accuracy_extent_logical_px"]
            g_extent = result["gpu_accuracy_extent_logical_px"]
            if (n_extent is None) != (g_extent is None):
                errors.append("Accuracy visibility differs")
            elif n_extent and max(abs(a - b) for a, b in zip(n_extent, g_extent)) > 1:
                errors.append("Accuracy extent differs by more than one logical pixel")
        elif (n_area != 0 or g_area != 0 or count(n_accuracy) != 0 or count(g_accuracy) != 0
              or count(n_foreground) != 0 or count(g_foreground) != 0):
            errors.append("Hidden marker remains visible")
        result["failures"] = errors
        results.append(result)
        pictures.append((reference, n_image, g_image, delta, result))
    return results, pictures


def render(pictures, path):
    width, row_height = 1160, 410
    figure = Image.new("RGB", (width, 114 + row_height * len(pictures)), "#ffffff")
    draw = ImageDraw.Draw(figure)
    draw.text((24, 16), "User location — actual iOS rendering", fill="#111827", font=font(26))
    draw.text((24, 51), "MapLibre Native 6.27.0 / Flutter GPU · iOS 27 · DPR 3 · 180-point center crops", fill="#475569", font=font(17))
    for index, heading in enumerate(["Native default (static phase)", "Flutter GPU", "Absolute RGB difference × 6"]):
        draw.text((24 + index * 380, 84), heading, fill="#111827", font=font(17))
    for row, (reference, native, gpu, delta, result) in enumerate(pictures):
        y = 114 + row * row_height
        scene = reference["scene"]
        label = f"{scene['id']}  ·  z {scene['zoom']:g}  ·  bearing {scene['bearing']:g}°  ·  pitch {scene['pitch']:g}°  ·  accuracy {scene['accuracy']:g} m"
        draw.text((24, y), label, fill="#111827", font=font(17))
        center_x, center_y = reference['native']['position']
        scale = reference['dpr']
        crop_bounds = tuple(round(value * scale) for value in (center_x - 90, center_y - 90, center_x + 90, center_y + 90))
        for column, picture in enumerate([native, gpu, delta.point(lambda value: min(255, value * 6))]):
            picture = picture.crop(crop_bounds)
            picture.thumbnail((350, 320), Image.Resampling.LANCZOS)
            x = 24 + column * 380
            figure.paste(picture, (x, y + 30))
        anchor = result['anchor_error_logical_px']
        anchor_label = "hidden" if anchor is None else f"anchor Δ {anchor:.6f} px"
        metric = f"{anchor_label}  ·  marker IoU {result['colored_marker_iou']:.3f}  ·  foreground RGB MAE {result['foreground_mean_absolute_rgb_error_0_255']:.2f}/255"
        draw.text((24, y + 358), metric, fill="#475569", font=font(16))
        native_meters = result['native_accuracy_radius_meters']
        gpu_meters = result['gpu_accuracy_radius_meters']
        if native_meters is not None and gpu_meters is not None:
            accuracy_metric = f"Measured horizontal accuracy radius: Native {native_meters:.1f} m / GPU {gpu_meters:.1f} m (pixel rounding included)"
        else:
            accuracy_metric = "Accuracy fill hidden in both captures"
        if result['failures']:
            draw.text((24, y + 382), "; ".join(result['failures']), fill="#b91c1c", font=font(14))
        else:
            draw.text((24, y + 382), accuracy_metric, fill="#475569", font=font(14))
    path.parent.mkdir(parents=True, exist_ok=True)
    figure.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "doc/images/user-location-comparison.png")
    parser.add_argument("--report", type=Path, default=ROOT / "tool/user_location/results.json")
    args = parser.parse_args()
    results, pictures = compare(load("native"), load("gpu"))
    render(pictures, args.output)
    gpu_metadata = json.loads((CAPTURES / "gpu/metadata.json").read_text())
    args.report.write_text(json.dumps({
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "reference": "MapLibre Native iOS 6.27.0 default annotation with Core Animation animations removed at model values",
        "environment": "iPhone 18 Pro, iOS 27.0 Simulator, DPR 3",
        "source_sha256": {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in [ROOT / "tool/user_location/scenarios.dart", ROOT / "tool/user_location/NativeReference.swift",
                         ROOT / "lib/src/widgets/user_location_marker.dart", ROOT / "lib/src/widgets/user_location_overlay.dart",
                         ROOT / "lib/src/geo/map_user_location.dart", ROOT / "lib/src/state/user_location_projection.dart",
                         ROOT / "lib/src/widgets/map/map_rendering.dart", ROOT / "lib/src/native/bindings/frame_bindings.dart",
                         ROOT / "e2e/visual/gpu_app/integration_test/user_location_test.dart"]
        },
        "frozen_projection_error_logical_px": gpu_metadata.get("frozenProjectionErrorLogicalPixels"),
        "scenes": results,
    }, indent=2) + "\n")
    failures = {r['scene']: r['failures'] for r in results if r['failures']}
    for result in results:
        print(result['scene'], f"IoU={result['colored_marker_iou']:.4f}", f"MAE={result['foreground_mean_absolute_rgb_error_0_255']:.3f}", result['failures'])
    print(args.output)
    if failures:
        raise SystemExit(f"Native parity checks failed: {failures}")


if __name__ == "__main__":
    main()
