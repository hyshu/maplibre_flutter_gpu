package dev.maplibre.fluttergpu.e2e.visual_e2e_gpu;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.content.Intent;

import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.Until;

import org.junit.Test;

import java.io.File;

public final class VisualCaptureTest {
    @Test
    public void capturesReadyMap() throws Exception {
        UiDevice device = UiDevice.getInstance(
                InstrumentationRegistry.getInstrumentation());
        Context targetContext =
                InstrumentationRegistry.getInstrumentation().getTargetContext();
        Intent launchIntent = targetContext.getPackageManager()
                .getLaunchIntentForPackage(targetContext.getPackageName());
        assertNotNull("Could not resolve the app launch activity", launchIntent);
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        targetContext.startActivity(launchIntent);

        assertNotNull(
                "Map did not reach its settled state",
                device.wait(Until.findObject(By.desc("VISUAL_E2E_READY")), 60_000));
        Thread.sleep(1_000);

        File output = new File(
                targetContext.getExternalFilesDir(null),
                "gpu.png");
        assertTrue("Could not capture screenshot", device.takeScreenshot(output));
    }
}
