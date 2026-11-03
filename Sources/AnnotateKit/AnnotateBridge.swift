// Objective-C entry point for apps whose AppDelegate is ObjC/ObjC++ (React Native < 0.77 and Expo
// SDK < 53 templates ship `AppDelegate.mm`), which can't call `Annotate.install(_:file:)`: it's a
// static on a Swift enum and its `file:` default is a Swift `#filePath`.
// Public: AnnotateBridge.install(file:) — ObjC `[AnnotateBridge installWithFile:@__FILE__];`
// Exists in every configuration like the rest of the public API (a no-op in Release, because
// `Annotate.install` is); compiled out where there's no ObjC runtime.

#if canImport(ObjectiveC)
#if canImport(AnnotateCore) // the CocoaPods build compiles AnnotateCore into this module
import AnnotateCore
#endif
import Foundation

@objc(AnnotateBridge)
public final class AnnotateBridge: NSObject {
    /// ObjC: `[AnnotateBridge installWithFile:@__FILE__];` in `application:didFinishLaunchingWithOptions:`.
    /// - Parameter file: the call site's path (`@__FILE__`), which locates the project root, as
    ///   `#filePath` does for Swift callers. The Expo config plugin generates this exact call.
    @MainActor @objc public static func install(file: String) {
        Annotate.install(AnnotateOptions(), file: file)
    }
}
#endif
