#
# fe_ar iOS: ARKit (+ LiDAR scene depth) tracking, Filament (Metal) rendering,
# Vision barcodes, and the shared C core (../src, via Classes/fe_ar_core_shim.c).
#
# CocoaPods, not Swift Package Manager: Filament ships for iOS as a pod (or a
# release tarball), not as a Swift package. The FieldOps app builds its other
# plugins with SwiftPM; Flutter falls back to CocoaPods for a plugin that has
# no Package.swift, so enabling fe_ar makes the app's iOS build use both
# (a Podfile appears on the first `flutter build ios`).
#
Pod::Spec.new do |s|
  s.name             = 'fe_ar'
  s.version          = '0.1.0'
  s.summary          = 'FieldOps AR engine: ARKit + Filament, native half of the fusioneco/ar channel.'
  s.description      = 'Headless AR engine for the FusionEco FieldOps app. See README.md and CHANNEL.md.'
  s.homepage         = 'https://fusionapps.com'
  s.license          = { :type => 'Proprietary', :text => 'Internal to FusionEco FieldOps.' }
  s.author           = { 'FusionEco' => 'dev@fusionapps.com' }
  s.source           = { :path => '.' }

  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.requires_arc     = true

  s.source_files        = 'Classes/**/*.{h,m,mm,c,swift}'
  s.public_header_files = 'Classes/FeArCore.h', 'Classes/FeArRenderer.h'
  # Compiled Filament materials (tool/compile_materials.sh writes them here).
  s.resource_bundles    = { 'fe_ar_assets' => ['Assets/*.filamat'] }

  s.dependency 'Flutter'
  # MUST match the Filament version SceneView uses on Android
  # (android/build.gradle feArFilamentVersion) and the matc that compiled
  # Assets/*.filamat. Bump all three together.
  # TODO(slice-0): confirm 1.72.1 is on CocoaPods trunk (the repo's podspec is at 1.77.x).
  s.dependency 'Filament/filament', '1.72.1'
  s.dependency 'Filament/gltfio_core', '1.72.1'

  s.frameworks = 'ARKit', 'Vision', 'Metal', 'MetalKit', 'CoreImage', 'CoreVideo', 'AVFoundation'
  s.libraries  = 'c++'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'GCC_C_LANGUAGE_STANDARD' => 'gnu99',
    # Filament's prebuilt libraries are device + simulator xcframeworks, but
    # Metal-backed AR can't run in the simulator; don't try to link i386.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
