[CmdletBinding()]
param(
    [Alias("Output")]
    [string]$OutputPath = "",
    [string]$Scene = "",
    [string]$Scenes = "",
    [string]$Baseline = "",
    [switch]$UpdateBaseline,
    [switch]$AllowMissingBaseline,
    [string]$MinimumSimilarity = "",
    [string]$IdleRetries = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Exit-WithUsageError {
    param([string]$Message)

    [Console]::Error.WriteLine($Message)
    exit 2
}

function Record-Status {
    param([int]$Status)

    if ($Status -ne 0 -and $script:SuiteStatus -eq 0) {
        $script:SuiteStatus = $Status
    }
}

function Get-EnvironmentVariable {
    param([string]$Name)

    return [Environment]::GetEnvironmentVariable($Name)
}

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

if ($PSBoundParameters.ContainsKey("Scene")) {
    $RequestedScenes = @($Scene)
} elseif ($PSBoundParameters.ContainsKey("Scenes")) {
    $RequestedScenes = $Scenes.Split(",")
} elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvironmentVariable "VISUAL_E2E_SCENES"))) {
    $RequestedScenes = (Get-EnvironmentVariable "VISUAL_E2E_SCENES").Split(",")
} elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvironmentVariable "VISUAL_E2E_SCENE"))) {
    $RequestedScenes = @((Get-EnvironmentVariable "VISUAL_E2E_SCENE"))
} else {
    $RequestedScenes = @("geometry")
}

$SupportedScenes = @(
    "geometry",
    "text-symbol",
    "3d-buildings",
    "line-variants",
    "raster-pattern",
    "mvt",
    "mlt",
    "tilejson-mvt",
    "pmtiles-raster",
    "mbtiles-raster",
    "image-source",
    "geojson-url",
    "raster-jpeg",
    "raster-webp",
    "raster-tms",
    "wmts",
    "pmtiles-vector",
    "pmtiles-mlt",
    "mbtiles-vector",
    "mbtiles-mlt"
)
$NormalizedScenes = @()
foreach ($Candidate in $RequestedScenes) {
    $CurrentScene = $Candidate.Trim()
    if ($SupportedScenes -notcontains $CurrentScene) {
        Exit-WithUsageError "Unsupported Windows visual scene: $CurrentScene"
    }
    if ($NormalizedScenes -contains $CurrentScene) {
        Exit-WithUsageError "Duplicate Windows visual scene: $CurrentScene"
    }
    $NormalizedScenes += $CurrentScene
}

if ($NormalizedScenes.Count -eq 0) {
    Exit-WithUsageError "At least one Windows visual scene is required."
}
if ([string]::IsNullOrWhiteSpace($IdleRetries)) {
    $IdleRetries = Get-EnvironmentVariable "VISUAL_E2E_IDLE_RETRIES"
}
if ([string]::IsNullOrWhiteSpace($IdleRetries)) {
    $RetryCount = if ($NormalizedScenes.Count -eq 1) { 3 } else { 0 }
} else {
    $RetryCount = 0
    if (-not [int]::TryParse($IdleRetries, [ref]$RetryCount) -or $RetryCount -lt 0) {
        Exit-WithUsageError "-IdleRetries must be a non-negative integer (got `"$IdleRetries`")."
    }
}
if (-not [string]::IsNullOrWhiteSpace($Baseline) -and $NormalizedScenes.Count -ne 1) {
    Exit-WithUsageError "-Baseline requires exactly one scene."
}
if ($UpdateBaseline -and $NormalizedScenes.Count -ne 1) {
    Exit-WithUsageError "-UpdateBaseline requires exactly one scene."
}
if ($AllowMissingBaseline -and $NormalizedScenes.Count -ne 1) {
    Exit-WithUsageError "-AllowMissingBaseline requires exactly one scene."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Get-EnvironmentVariable "VISUAL_E2E_WINDOWS_OUTPUT"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $Output = Join-Path $RepositoryRoot "e2e/visual/report-windows"
} elseif ([IO.Path]::IsPathRooted($OutputPath)) {
    $Output = [IO.Path]::GetFullPath($OutputPath)
} else {
    $Output = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $OutputPath))
}

$BaselinePath = ""
if (-not [string]::IsNullOrWhiteSpace($Baseline)) {
    $BaselinePath = if ([IO.Path]::IsPathRooted($Baseline)) {
        [IO.Path]::GetFullPath($Baseline)
    } else {
        [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $Baseline))
    }
}
if ([string]::IsNullOrWhiteSpace($MinimumSimilarity)) {
    $MinimumSimilarity = Get-EnvironmentVariable "VISUAL_E2E_MINIMUM_SIMILARITY"
}
if ([string]::IsNullOrWhiteSpace($MinimumSimilarity)) {
    $MinimumSimilarity = "1.0"
}

$LogsDirectory = if ($NormalizedScenes.Count -eq 1) {
    Join-Path (Join-Path $Output $NormalizedScenes[0]) "logs"
} else {
    Join-Path $Output "logs"
}
New-Item -ItemType Directory -Force -Path $LogsDirectory | Out-Null
Get-ChildItem -Path $LogsDirectory -Filter "maplibre_flutter_gpu-test*.log" |
    Remove-Item -Force

foreach ($CurrentScene in $NormalizedScenes) {
    $SceneOutput = Join-Path $Output $CurrentScene
    $ImagesDirectory = Join-Path $SceneOutput "images"
    Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath @(
        (Join-Path $ImagesDirectory "gpu.png"),
        (Join-Path $ImagesDirectory "baseline.png"),
        (Join-Path $ImagesDirectory "baseline-diff.png"),
        (Join-Path $ImagesDirectory "command-coverage.json"),
        (Join-Path $SceneOutput "index.html"),
        (Join-Path $SceneOutput "results.json"),
        (Join-Path $SceneOutput "baseline-results.json")
    )
}

$CaptureDirectory = Join-Path (
    [IO.Path]::GetTempPath()
) ("maplibre-windows-e2e-{0}" -f [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $CaptureDirectory | Out-Null

$script:SuiteStatus = 0
try {
    Push-Location (Join-Path $RepositoryRoot "e2e/visual/gpu_app")
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }

    $SuiteLog = Join-Path $LogsDirectory "maplibre_flutter_gpu-test.log"
    [IO.File]::WriteAllText($SuiteLog, "")
    foreach ($CurrentScene in $NormalizedScenes) {
        $TestArguments = @(
            "test",
            "--enable-flutter-gpu",
            "integration_test/visual_test.dart",
            "-d",
            "windows",
            "--dart-define=VISUAL_E2E_SCREENSHOT_DIR=$CaptureDirectory",
            "--dart-define=VISUAL_E2E_SCENE=$CurrentScene"
        )
        $Attempt = 1
        $MaximumAttempts = $RetryCount + 1
        while ($true) {
            $CurrentLog = Join-Path $CaptureDirectory "$CurrentScene-test-attempt-$Attempt.log"
            $AttemptLog = Join-Path $LogsDirectory "maplibre_flutter_gpu-test-attempt-$Attempt.log"
            Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath @(
                (Join-Path $CaptureDirectory "$CurrentScene.png"),
                (Join-Path $CaptureDirectory "$CurrentScene.coverage.json"),
                $CurrentLog
            )

            Push-Location (Join-Path $RepositoryRoot "e2e/visual/gpu_app")
            try {
                & flutter @TestArguments 2>&1 |
                    Tee-Object -FilePath $CurrentLog |
                    Tee-Object -FilePath $AttemptLog -Append
                $TestStatus = $LASTEXITCODE
            } finally {
                Pop-Location
            }

            if ($TestStatus -eq 0) {
                [IO.File]::AppendAllText(
                    $SuiteLog,
                    [IO.File]::ReadAllText($CurrentLog)
                )
                break
            }
            if (-not (Select-String -LiteralPath $CurrentLog -SimpleMatch "did not become idle" -Quiet)) {
                [Console]::Error.WriteLine(
                    "Visual E2E scene $CurrentScene failed for a reason other than the idle timeout."
                )
                exit $TestStatus
            }
            if ($Attempt -ge $MaximumAttempts) {
                [Console]::Error.WriteLine(
                    "Visual E2E scene $CurrentScene did not become idle after $Attempt attempts."
                )
                exit $TestStatus
            }
            [Console]::Error.WriteLine(
                "Scene $CurrentScene attempt $Attempt hit the idle timeout. Retrying."
            )
            $Attempt += 1
            Start-Sleep -Seconds 5
        }
    }

    Push-Location (Join-Path $RepositoryRoot "e2e/visual/runner")
    try {
        & dart pub get
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }

    $StrictScenes = @(
        "geometry",
        "text-symbol",
        "3d-buildings",
        "line-variants",
        "raster-pattern"
    )
    foreach ($CurrentScene in $NormalizedScenes) {
        $SceneOutput = Join-Path $Output $CurrentScene
        $ImagesDirectory = Join-Path $SceneOutput "images"
        $Screenshot = Join-Path $ImagesDirectory "gpu.png"
        $Coverage = Join-Path $ImagesDirectory "command-coverage.json"
        New-Item -ItemType Directory -Force -Path $ImagesDirectory | Out-Null
        Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath @(
            $Screenshot,
            (Join-Path $ImagesDirectory "baseline.png"),
            (Join-Path $ImagesDirectory "baseline-diff.png"),
            $Coverage,
            (Join-Path $SceneOutput "index.html"),
            (Join-Path $SceneOutput "results.json"),
            (Join-Path $SceneOutput "baseline-results.json")
        )
        Copy-Item -LiteralPath (
            Join-Path $CaptureDirectory "$CurrentScene.png"
        ) -Destination $Screenshot
        Copy-Item -LiteralPath (
            Join-Path $CaptureDirectory "$CurrentScene.coverage.json"
        ) -Destination $Coverage

        Push-Location (Join-Path $RepositoryRoot "e2e/visual/runner")
        try {
            & dart run bin/verify_desktop_smoke.dart `
                --platform Windows `
                --screenshot $Screenshot `
                --scene $CurrentScene `
                --output $SceneOutput
            Record-Status $LASTEXITCODE
        } finally {
            Pop-Location
        }

        $SceneBaseline = if ($BaselinePath) {
            $BaselinePath
        } else {
            Join-Path $RepositoryRoot "e2e/visual/baseline/windows-$CurrentScene.png"
        }
        $CoverageExpectation = Join-Path $RepositoryRoot (
            "e2e/visual/baseline/windows-$CurrentScene.coverage.json"
        )

        if ($UpdateBaseline) {
            Push-Location (Join-Path $RepositoryRoot "e2e/visual/runner")
            try {
                & dart run bin/verify_desktop_baseline.dart `
                    --platform Windows `
                    --screenshot $Screenshot `
                    --baseline $SceneBaseline `
                    --scene $CurrentScene `
                    --output $SceneOutput `
                    --update-baseline
                $Status = $LASTEXITCODE
                if ($Status -eq 0) {
                    & dart run bin/verify_command_coverage.dart `
                        --coverage $Coverage `
                        --expected $CoverageExpectation `
                        --scene $CurrentScene `
                        --update-expected
                    $Status = $LASTEXITCODE
                }
                Record-Status $Status
            } finally {
                Pop-Location
            }
        } elseif (
            $NormalizedScenes.Count -eq 1 -or
            $StrictScenes -contains $CurrentScene -or
            $BaselinePath
        ) {
            if ($AllowMissingBaseline -and -not (Test-Path -LiteralPath $SceneBaseline)) {
                [Console]::Error.WriteLine(
                    "WARNING: no Windows baseline at $SceneBaseline."
                )
            } else {
                Push-Location (Join-Path $RepositoryRoot "e2e/visual/runner")
                try {
                    & dart run bin/verify_desktop_baseline.dart `
                        --platform Windows `
                        --screenshot $Screenshot `
                        --baseline $SceneBaseline `
                        --scene $CurrentScene `
                        --output $SceneOutput `
                        --minimum-similarity $MinimumSimilarity
                    Record-Status $LASTEXITCODE
                } finally {
                    Pop-Location
                }
            }

            if ($AllowMissingBaseline -and -not (Test-Path -LiteralPath $CoverageExpectation)) {
                [Console]::Error.WriteLine(
                    "WARNING: no coverage expectation at $CoverageExpectation."
                )
            } else {
                Push-Location (Join-Path $RepositoryRoot "e2e/visual/runner")
                try {
                    & dart run bin/verify_command_coverage.dart `
                        --coverage $Coverage `
                        --expected $CoverageExpectation `
                        --scene $CurrentScene
                    Record-Status $LASTEXITCODE
                } finally {
                    Pop-Location
                }
            }
        }
    }
} finally {
    Remove-Item -LiteralPath $CaptureDirectory -Recurse -Force
}

exit $script:SuiteStatus
