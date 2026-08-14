param(
    [ValidateSet("x64", "arm64")]
    [string] $Architecture
)

$ErrorActionPreference = "Stop"

$ScriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeRoot = Split-Path -Parent $ScriptsRoot
$RepositoryRoot = Split-Path -Parent $NativeRoot

$HostArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
$NativeArchitecture = switch ($HostArchitecture) {
    "X64" { "x64" }
    "Arm64" { "arm64" }
    default { throw "Unsupported Windows architecture: $HostArchitecture" }
}
$SelectedArchitecture = if ($Architecture) { $Architecture } else { $NativeArchitecture }
if ($SelectedArchitecture -ne $NativeArchitecture) {
    throw "Cross-building from $NativeArchitecture to $SelectedArchitecture is not supported"
}

switch ($SelectedArchitecture) {
    "x64" {
        $ArchitectureDirectory = "x64"
        $MsvcArchitecture = "x64"
        $RequiredMsvcComponent = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
        $Triplet = "x64-windows-static"
    }
    "arm64" {
        $ArchitectureDirectory = "arm64"
        $MsvcArchitecture = "arm64"
        $RequiredMsvcComponent = "Microsoft.VisualStudio.Component.VC.Tools.ARM64"
        $Triplet = "arm64-windows-static"
    }
}

$BuildDirectory = if ($env:MAPLIBRE_WINDOWS_BUILD_DIR) {
    Join-Path $env:MAPLIBRE_WINDOWS_BUILD_DIR $ArchitectureDirectory
} else {
    Join-Path $RepositoryRoot "build-windows-fluttergpu-$ArchitectureDirectory"
}
$VcpkgRoot = if ($env:VCPKG_INSTALLATION_ROOT) {
    $env:VCPKG_INSTALLATION_ROOT
} elseif ($env:VCPKG_ROOT) {
    $env:VCPKG_ROOT
} else {
    throw "VCPKG_INSTALLATION_ROOT or VCPKG_ROOT is required"
}
$Verifier = Join-Path $RepositoryRoot "tool/ci/verify_desktop_artifact.py"
$OutputDirectory = Join-Path `
    (Join-Path $RepositoryRoot "windows") `
    $ArchitectureDirectory
$Output = Join-Path $OutputDirectory "maplibre_bridge.dll"

$MsvcEnvironmentMatches =
    (Get-Command cl -ErrorAction SilentlyContinue) -and
    (Get-Command dumpbin -ErrorAction SilentlyContinue) -and
    ($env:VSCMD_ARG_TGT_ARCH -ieq $MsvcArchitecture) -and
    ($env:VSCMD_ARG_HOST_ARCH -ieq $MsvcArchitecture)
if (-not $MsvcEnvironmentMatches) {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} `
        "Microsoft Visual Studio/Installer/vswhere.exe"
    if (-not (Test-Path $VsWhere)) {
        throw "Visual Studio locator not found: $VsWhere"
    }
    $VsInstallPath = & $VsWhere -latest -products * `
        -requires $RequiredMsvcComponent `
        -property installationPath
    if (-not $VsInstallPath) {
        throw "Visual Studio C++ tools for $SelectedArchitecture are required"
    }
    Import-Module (Join-Path $VsInstallPath `
        "Common7/Tools/Microsoft.VisualStudio.DevShell.dll")
    Enter-VsDevShell -VsInstallPath $VsInstallPath `
        -SkipAutomaticLocation `
        -DevCmdArguments `
            "-arch=$MsvcArchitecture -host_arch=$MsvcArchitecture"
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "python is required"
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "cmake is required"
}
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    throw "ninja is required"
}
if (-not (Get-Command dumpbin -ErrorAction SilentlyContinue)) {
    throw "dumpbin is required. Run this script in an MSVC developer shell."
}
if (-not (Test-Path (Join-Path $RepositoryRoot "vendor/maplibre-native/CMakeLists.txt"))) {
    throw "MapLibre Native submodule is missing"
}

& (Join-Path $VcpkgRoot "vcpkg.exe") install `
    "curl:$Triplet" `
    "icu:$Triplet" `
    "libjpeg-turbo:$Triplet" `
    "libpng:$Triplet" `
    "libuv:$Triplet" `
    "libwebp:$Triplet"
if ($LASTEXITCODE -ne 0) { throw "vcpkg install failed" }

cmake `
    -S (Join-Path $NativeRoot "platforms/windows") `
    -B $BuildDirectory `
    -G Ninja `
    "-DCMAKE_BUILD_TYPE=Release" `
    "-DMAPLIBRE_TARGET_ARCHITECTURE=$ArchitectureDirectory" `
    "-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $VcpkgRoot 'scripts/buildsystems/vcpkg.cmake')" `
    "-DVCPKG_TARGET_TRIPLET=$Triplet"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

cmake --build $BuildDirectory --target maplibre_bridge --parallel
if ($LASTEXITCODE -ne 0) { throw "CMake build failed" }

$Candidate = Join-Path $BuildDirectory "out/maplibre_bridge.dll"
python $Verifier --platform windows --library $Candidate
if ($LASTEXITCODE -ne 0) { throw "Windows bridge verification failed" }

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$TemporaryOutput = "$Output.tmp.$PID"
try {
    Copy-Item -Force $Candidate $TemporaryOutput
    Move-Item -Force $TemporaryOutput $Output
} finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $TemporaryOutput
}
Write-Host "Built and verified: $Output"
