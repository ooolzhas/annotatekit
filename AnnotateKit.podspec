# AnnotateKit for CocoaPods, which is how React Native and Expo apps link it (iOS only).
#
# One pod, one module: React Native autolinking links exactly one podspec per npm package (the
# one at the package root), so AnnotateCore and AnnotateKit compile together into a single module
# named `AnnotateKit`. That is why every `import AnnotateCore` in Sources/AnnotateKit sits behind
# `#if canImport(AnnotateCore)`; SwiftPM still builds them as two modules.
#
# The overlay is gated on `#if DEBUG`. CocoaPods sets SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG
# on every Debug-type configuration of the Pods project and pod targets inherit it, so no
# pod_target_xcconfig is needed. Release compiles to the same no-op stubs as the SwiftPM build.
#
# The npm package `annotate-ios` ships this file with Sources/AnnotateCore and Sources/AnnotateKit
# (copied in by .github/workflows/release.yml), so the globs below resolve from the package root.
# Keep s.version equal to the release tag; the release workflow checks it.

Pod::Spec.new do |s|
  s.name          = 'AnnotateKit'
  s.version       = '0.4.2'
  s.summary       = 'Visual feedback for iOS apps, straight to your coding agent.'
  s.description   = <<-DESC
    A DEBUG-only overlay for pinning comments and drawings onto a frozen screen of your running
    app. Send writes a session bundle that the `annotate` CLI delivers to a coding agent.
    Release builds compile to no-op stubs.
  DESC
  s.homepage      = 'https://annotatekit.com'
  s.license       = { :type => 'MIT', :file => 'LICENSE' }
  s.author        = { 'Olzhas Beisenbayev' => 'https://github.com/ooolzhas' }
  s.source        = { :git => 'https://github.com/ooolzhas/annotatekit.git', :tag => "v#{s.version}" }

  s.platform      = :ios, '17.0'
  s.swift_versions = ['6.0']
  s.module_name   = 'AnnotateKit'

  s.source_files  = 'Sources/AnnotateCore/**/*.swift', 'Sources/AnnotateKit/**/*.swift'
  s.exclude_files = 'Sources/AnnotateCore/AnnotateCore.docc', 'Sources/AnnotateKit/AnnotateKit.docc'
  s.frameworks    = 'UIKit', 'SwiftUI', 'CoreGraphics', 'CoreImage', 'ImageIO', 'PhotosUI'

  # Lets Objective-C / ObjC++ AppDelegates (older RN and Expo templates) `#import "AnnotateKit-Swift.h"`.
  # As a static library (RN's default) CocoaPods puts that header only behind the module map, and
  # `@import` fails in .mm files because RN doesn't pass -fcxx-modules. Harmless with frameworks.
  s.user_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"${PODS_CONFIGURATION_BUILD_DIR}/AnnotateKit/Swift Compatibility Header"'
  }
end
