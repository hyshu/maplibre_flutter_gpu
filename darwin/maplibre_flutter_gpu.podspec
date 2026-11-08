Pod::Spec.new do |s|
  s.name = 'maplibre_flutter_gpu'
  s.version = '0.3.0'
  s.summary = 'MapLibre maps rendered with Flutter GPU.'
  s.description = <<-DESC
MapLibre maps for Flutter, rendered with Flutter GPU.
                       DESC
  s.homepage = 'https://github.com/hyshu/maplibre_flutter_gpu'
  s.license = { :file => '../LICENSE' }
  s.author = {
    'MapLibre Flutter GPU contributors' =>
      'https://github.com/hyshu/maplibre_flutter_gpu'
  }
  s.source = { :path => '.' }

  s.source_files = 'maplibre_flutter_gpu/Sources/maplibre_flutter_gpu/**/*'
  # MapLibreBridge.xcframework holds dynamic frameworks. Each one links its own
  # system dependencies, so the host app needs no extra linker settings.
  s.vendored_frameworks = 'maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework'
  s.preserve_paths = 'maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework'

  s.ios.deployment_target = '15.5'
  s.osx.deployment_target = '14.3'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.ios.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
