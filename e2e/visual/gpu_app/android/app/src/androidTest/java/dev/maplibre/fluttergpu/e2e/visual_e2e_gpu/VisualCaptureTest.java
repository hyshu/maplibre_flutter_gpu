package dev.maplibre.fluttergpu.e2e.visual_e2e_gpu;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;

import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;

import org.junit.Test;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public final class VisualCaptureTest {
    private static final String INITIAL_ROUTE_EXTRA = "route";
    private static final String INITIAL_ROUTE_PREFIX = "/visual-e2e/";
    private static final String READY_LOG_PREFIX =
            "VISUAL_E2E_READY|maplibre_flutter_gpu|";
    private static final long READY_TIMEOUT_MILLIS = 60_000;

    private static final List<String> EXPECTED_SCENES = Arrays.asList(
            "geometry",
            "text-symbol",
            "3d-buildings",
            "mvt",
            "tilejson-mvt",
            "image-source",
            "geojson-url",
            "raster-jpeg",
            "raster-webp",
            "raster-tms",
            "wmts");

    @Test
    public void capturesReadyMaps() throws Exception {
        UiDevice device = UiDevice.getInstance(
                InstrumentationRegistry.getInstrumentation());
        Context targetContext =
                InstrumentationRegistry.getInstrumentation().getTargetContext();
        File externalFiles = targetContext.getExternalFilesDir(null);
        assertNotNull("External files directory is unavailable", externalFiles);

        for (String scene : visualScenes()) {
            captureScene(device, targetContext, externalFiles, scene);
        }
    }

    private static List<String> visualScenes() {
        Bundle arguments = InstrumentationRegistry.getArguments();
        String rawScenes = arguments.getString("visualScenes");
        assertNotNull("Instrumentation argument visualScenes is required", rawScenes);

        List<String> scenes = new ArrayList<>();
        for (String value : rawScenes.split("\\|", -1)) {
            scenes.add(value.trim());
        }

        Set<String> uniqueScenes = new HashSet<>(scenes);
        assertEquals(
                "visualScenes contains duplicate scenes",
                scenes.size(),
                uniqueScenes.size());
        assertEquals(
                "visualScenes must contain every supported scene",
                new HashSet<>(EXPECTED_SCENES),
                uniqueScenes);

        return scenes;
    }

    private static void captureScene(
            UiDevice device,
            Context targetContext,
            File externalFiles,
            String scene) throws Exception {
        Intent launchIntent = targetContext.getPackageManager()
                .getLaunchIntentForPackage(targetContext.getPackageName());
        assertNotNull("Could not resolve the app launch activity", launchIntent);
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        launchIntent.putExtra(INITIAL_ROUTE_EXTRA, INITIAL_ROUTE_PREFIX + scene);
        targetContext.startActivity(launchIntent);

        assertTrue(
                "Map did not reach its settled state for " + scene,
                waitForReadyLog(device, READY_LOG_PREFIX + scene));
        Thread.sleep(1_000);

        File sceneDirectory = new File(new File(externalFiles, "visual-e2e"), scene);
        assertTrue(
                "Could not create screenshot directory for " + scene,
                sceneDirectory.isDirectory() || sceneDirectory.mkdirs());
        File output = new File(sceneDirectory, "gpu.png");
        assertTrue(
                "Could not capture screenshot for " + scene,
                device.takeScreenshot(output));
        assertTrue(
                "Screenshot is empty for " + scene,
                output.isFile() && output.length() > 0);
    }

    private static boolean waitForReadyLog(UiDevice device, String readyMarker)
            throws Exception {
        long deadline = SystemClock.uptimeMillis() + READY_TIMEOUT_MILLIS;
        while (SystemClock.uptimeMillis() < deadline) {
            String logs = device.executeShellCommand("logcat -d flutter:I '*:S'");
            if (logs.contains(readyMarker)) {
                return true;
            }
            Thread.sleep(250);
        }

        return false;
    }
}
