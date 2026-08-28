import 'dart:ffi';
import 'dart:io';

/// Returns the package directory containing the bridge for [abi].
///
/// A null result means the ABI uses another loading mechanism or has no
/// prebuilt desktop bridge.
String? bridgePlatformDirectory([Abi? abi]) => switch (abi ?? .current()) {
  .linuxX64 => 'linux/x64',
  .linuxArm64 => 'linux/arm64',
  .windowsX64 => 'windows/x64',
  .windowsArm64 => 'windows/arm64',
  _ => null,
};

/// Returns bridge paths in runtime-first lookup order.
///
/// Packaged Linux applications place native libraries under `lib`. Windows
/// applications place them next to the executable. Remaining paths support
/// source checkout runs from the package and its example applications.
List<String> bridgeLibraryCandidates(
  String libraryName, {
  Abi? abi,
  String? operatingSystem,
  String? executableDirectory,
  String? workingDirectory,
}) {
  final executableRoot =
      executableDirectory ?? File(Platform.resolvedExecutable).parent.path;
  final workingRoot = workingDirectory ?? Directory.current.path;
  final hostOperatingSystem = operatingSystem ?? Platform.operatingSystem;
  final packageDirectory = bridgePlatformDirectory(abi);

  return [
    if (hostOperatingSystem == 'linux') '$executableRoot/lib/$libraryName',
    '$executableRoot/$libraryName',
    if (packageDirectory != null)
      for (final relativeRoot in ['', '..', '../..', '../../..'])
        '$workingRoot/${relativeRoot.isEmpty ? '' : '$relativeRoot/'}'
            '$packageDirectory/$libraryName',
  ];
}

/// Resolves the bundled desktop bridge or throws a descriptive error.
String resolveBridgeLibraryPath(String libraryName) {
  final candidates = bridgeLibraryCandidates(libraryName);
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }

  throw StateError(
    'MapLibre bridge $libraryName was not found. Checked:\n'
    '${candidates.join('\n')}',
  );
}
