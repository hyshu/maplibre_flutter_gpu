$ErrorActionPreference = "Stop"

$ScriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeRoot = Split-Path -Parent $ScriptsRoot
$RepositoryRoot = Split-Path -Parent $NativeRoot
$BuildDirectory = if ($env:MAPLIBRE_WINDOWS_BUILD_DIR) {
    $env:MAPLIBRE_WINDOWS_BUILD_DIR
} else {
    Join-Path $RepositoryRoot "build-windows-fluttergpu"
}
$Triplet = "x64-windows-static"
$VcpkgRoot = if ($env:VCPKG_INSTALLATION_ROOT) {
    $env:VCPKG_INSTALLATION_ROOT
} elseif ($env:VCPKG_ROOT) {
    $env:VCPKG_ROOT
} else {
    throw "VCPKG_INSTALLATION_ROOT or VCPKG_ROOT is required"
}
$Verifier = Join-Path $RepositoryRoot "tool/ci/verify_desktop_artifact.py"
$OutputDirectory = Join-Path $RepositoryRoot "windows/x64"
$Output = Join-Path $OutputDirectory "maplibre_bridge.dll"

if (-not (Get-Command cl -ErrorAction SilentlyContinue) -or
    -not (Get-Command dumpbin -ErrorAction SilentlyContinue)) {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} `
        "Microsoft Visual Studio/Installer/vswhere.exe"
    if (-not (Test-Path $VsWhere)) {
        throw "Visual Studio locator not found: $VsWhere"
    }
    $VsInstallPath = & $VsWhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $VsInstallPath) {
        throw "Visual Studio C++ tools are required"
    }
    Import-Module (Join-Path $VsInstallPath `
        "Common7/Tools/Microsoft.VisualStudio.DevShell.dll")
    Enter-VsDevShell -VsInstallPath $VsInstallPath `
        -SkipAutomaticLocation `
        -DevCmdArguments "-arch=x64 -host_arch=x64"
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
