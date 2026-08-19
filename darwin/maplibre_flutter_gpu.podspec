Pod::Spec.new do |s|
  s.name = 'maplibre_flutter_gpu'
  s.version = '0.0.4'
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
  s.vendored_frameworks = 'maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework'
  s.preserve_paths = 'maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework'
  s.static_framework = true

  s.ios.deployment_target = '14.3'
  s.osx.deployment_target = '14.3'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.ios.frameworks = 'CFNetwork', 'CoreGraphics', 'CoreLocation', 'CoreText',
                     'Foundation', 'Metal', 'MetalKit', 'Security',
                     'SystemConfiguration', 'UIKit'
  s.osx.frameworks = 'AppKit', 'CFNetwork', 'CoreGraphics', 'CoreImage',
                     'CoreLocation', 'CoreText', 'Foundation', 'Security',
                     'SystemConfiguration'
  s.ios.libraries = 'c++', 'sqlite3', 'z'
  s.osx.libraries = 'c++', 'sqlite3', 'z'

  s.ios.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.ios.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -ObjC'
  }
  s.osx.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -ObjC'
  }
  s.swift_version = '5.9'
end
