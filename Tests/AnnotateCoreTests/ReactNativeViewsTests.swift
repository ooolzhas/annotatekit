// ReactNativeViews: RN host classes of both architectures map to the JSX component a developer
// writes, RN root/navigation wrappers are plumbing, and every other name (UIKit, SwiftUI, app
// classes) maps to nothing, so native apps keep their class names.

import Foundation
import Testing
@testable import AnnotateCore

@Suite struct ReactNativeViewsTests {
    @Test("Fabric component views map to their JSX component", arguments: [
        ("RCTViewComponentView", "View"),
        ("RCTParagraphComponentView", "Text"),
        ("RCTParagraphTextView", "Text"),
        ("RCTScrollViewComponentView", "ScrollView"),
        ("RCTEnhancedScrollView", "ScrollView"),
        ("RCTImageComponentView", "Image"),
        ("RCTTextInputComponentView", "TextInput"),
        ("RCTSwitchComponentView", "Switch"),
        ("RCTActivityIndicatorViewComponentView", "ActivityIndicator"),
        ("RCTModalHostViewComponentView", "Modal"),
        ("RCTFabricModalHostViewController", "Modal"),
        ("RCTSafeAreaViewComponentView", "SafeAreaView"),
        ("RCTPullToRefreshViewComponentView", "RefreshControl"),
        ("RCTInputAccessoryComponentView", "InputAccessoryView")
    ])
    func fabric(className: String, component: String) {
        #expect(ReactNativeViews.componentName(forClassName: className) == component)
    }

    @Test("Paper views map to the same components", arguments: [
        ("RCTView", "View"),
        ("RCTTextView", "Text"),
        ("RCTVirtualTextView", "Text"),
        ("RCTScrollView", "ScrollView"),
        ("RCTCustomScrollView", "ScrollView"),
        ("RCTImageView", "Image"),
        ("RCTSinglelineTextInputView", "TextInput"),
        ("RCTMultilineTextInputView", "TextInput"),
        ("RCTSwitch", "Switch"),
        ("RCTActivityIndicatorView", "ActivityIndicator"),
        ("RCTModalHostView", "Modal"),
        ("RCTModalHostViewController", "Modal"),
        ("RCTSafeAreaView", "SafeAreaView"),
        ("RCTRefreshControl", "RefreshControl"),
        ("RCTInputAccessoryView", "InputAccessoryView")
    ])
    func paper(className: String, component: String) {
        #expect(ReactNativeViews.componentName(forClassName: className) == component)
    }

    @Test("the UIKit views RN backs a component with, shared by both architectures")
    func backingViews() {
        #expect(ReactNativeViews.componentName(forClassName: "RCTUITextField") == "TextInput")
        #expect(ReactNativeViews.componentName(forClassName: "RCTUITextView") == "TextInput")
        #expect(ReactNativeViews.componentName(forClassName: "RCTUIImageViewAnimated") == "Image")
        #expect(ReactNativeViews.componentName(forClassName: "RNCSafeAreaViewComponentView") == "SafeAreaView")
    }

    @Test("a plain UIKit view inside a leaf component takes its name; inside a View it doesn't")
    func childOfLeaf() {
        #expect(ReactNativeViews.componentName(forChildOf: "RCTSwitchComponentView") == "Switch")
        #expect(ReactNativeViews.componentName(forChildOf: "RCTActivityIndicatorViewComponentView") == "ActivityIndicator")
        #expect(ReactNativeViews.componentName(forChildOf: "RCTViewComponentView") == nil)
        #expect(ReactNativeViews.componentName(forChildOf: "RCTScrollViewComponentView") == nil)
        // Fabric mounts inline views of a Text as its children
        #expect(ReactNativeViews.componentName(forChildOf: "RCTParagraphComponentView") == nil)
        #expect(ReactNativeViews.componentName(forChildOf: "UIStackView") == nil)
    }

    @Test("native and unknown names map to nothing", arguments: [
        "UIView", "UILabel", "UISwitch", "UIScrollView", "UIImageView", "UITextField", "UIViewController",
        "UIHostingController", "_UIHostingView", "PlatformViewHost", "HeroCardView", "RNSVGSvgView", "", "View"
    ])
    func unknown(className: String) {
        #expect(ReactNativeViews.componentName(forClassName: className) == nil)
        #expect(!ReactNativeViews.isPlumbing(className: className))
    }

    @Test("RN root and surface containers are plumbing, in both architectures", arguments: [
        "RCTRootComponentView", "RCTSurfaceView", "RCTSurfaceRootView", "RCTSurfaceHostingView",
        "RCTSurfaceHostingProxyRootView", "RCTRootView", "RCTRootContentView", "RCTScrollContentView",
        "RCTDebuggingOverlayComponentView", "RNCSafeAreaProviderComponentView", "RNCSafeAreaProvider"
    ])
    func rootPlumbing(className: String) {
        #expect(ReactNativeViews.isPlumbing(className: className))
        #expect(ReactNativeViews.componentName(forClassName: className) == nil)
    }

    @Test("react-native-screens wrappers and their controllers are plumbing", arguments: [
        "RNSScreen", "RNSScreenView", "RNSModalScreen", "RNSScreenStackView", "RNSNavigationController",
        "RNSScreenContainerView", "RNSScreenContentWrapper", "RNSScreenStackHeaderConfig",
        "RNSScreenStackHeaderSubview", "RNSFullWindowOverlayContainer", "RNSTabsHostComponentView",
        "RNSStackScreenController"
    ])
    func screensPlumbing(className: String) {
        #expect(ReactNativeViews.isPlumbing(className: className))
    }

    @Test("components a developer writes are never plumbing")
    func componentsAreNotPlumbing() {
        for name in ["RCTViewComponentView", "RCTView", "RCTParagraphComponentView", "RCTScrollView",
                     "RCTModalHostViewComponentView", "RCTFabricModalHostViewController", "RNCSafeAreaView"] {
            #expect(!ReactNativeViews.isPlumbing(className: name))
        }
    }
}
