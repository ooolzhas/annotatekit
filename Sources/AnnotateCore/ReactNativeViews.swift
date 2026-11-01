// React Native host views, named the way a developer writes them in JSX. RN renders real UIViews, so
// the scanner finds RN content like any UIKit view, but their classes (`RCTParagraphComponentView`)
// mean nothing to an agent reading `<Text>`. `componentName` maps a native class to its component;
// `isPlumbing` names the root/surface and navigation wrappers that, like UIKit's private views,
// shouldn't become candidates or breadcrumb entries. Unknown names give nil/false, so native apps
// are unchanged. Foundation only: it works on class-name strings.
//
// Class names come from the sources, both architectures:
// - Fabric (new architecture), facebook/react-native@main:
//   packages/react-native/React/Fabric/Mounting/ComponentViews/** (`*ComponentView`, plus the
//   private `RCTParagraphTextView` in Text/RCTParagraphComponentView.mm, `RCTEnhancedScrollView`
//   and Modal/RCTFabricModalHostViewController), packages/react-native/React/Base/Surface/**.
// - Paper (old architecture), facebook/react-native@v0.76.0 (removed from main since):
//   packages/react-native/React/Views/** (RCTView, RCTSwitch, RCTActivityIndicatorView,
//   RCTModalHostView[Controller], SafeAreaView/, RefreshControl/, ScrollView/ with the private
//   `RCTCustomScrollView` in RCTScrollView.m), Libraries/Text/** (RCTTextView, RCTVirtualTextView,
//   TextInput/**), Libraries/Image/** (RCTImageView, RCTUIImageViewAnimated),
//   React/Base/RCTRootView.h and RCTRootContentView.h.
// - software-mansion/react-native-screens@main ios/** (legacy/ for 4.x, react/ and core/ for the
//   newer containers) and AppAndFlow/react-native-safe-area-context@main ios/**.

import Foundation

public enum ReactNativeViews {
    /// The JSX component for a React Native host view or view controller class, nil for anything else.
    public static func componentName(forClassName name: String) -> String? {
        components[name]
    }

    /// The JSX component for a plain UIKit view RN creates inside a leaf component (the `UISwitch`
    /// in `RCTSwitchComponentView`), given the parent's class. Only components that never host
    /// React children qualify, so a child view of a `View` keeps its own name.
    public static func componentName(forChildOf parentClassName: String) -> String? {
        guard let name = components[parentClassName], leafComponents.contains(name) else { return nil }
        return name
    }

    /// RN root/surface containers and navigation wrappers: full-screen boxes no one writes in JSX.
    public static func isPlumbing(className name: String) -> Bool {
        plumbing.contains(name)
    }

    private static let components: [String: String] = [
        // View
        "RCTViewComponentView": "View",
        "RCTView": "View",
        // Text (`RCTParagraphTextView` draws inside the Fabric paragraph; nested Text is virtual)
        "RCTParagraphComponentView": "Text",
        "RCTParagraphTextView": "Text",
        "RCTTextView": "Text",
        "RCTVirtualTextView": "Text",
        // ScrollView, with the UIScrollView each architecture hosts inside
        "RCTScrollViewComponentView": "ScrollView",
        "RCTEnhancedScrollView": "ScrollView",
        "RCTScrollView": "ScrollView",
        "RCTCustomScrollView": "ScrollView",
        // Image (`RCTUIImageViewAnimated` is the inner UIImageView in both)
        "RCTImageComponentView": "Image",
        "RCTImageView": "Image",
        "RCTUIImageViewAnimated": "Image",
        // TextInput (`RCTUITextField`/`RCTUITextView` are the backing UIKit inputs in both)
        "RCTTextInputComponentView": "TextInput",
        "RCTBaseTextInputView": "TextInput",
        "RCTSinglelineTextInputView": "TextInput",
        "RCTMultilineTextInputView": "TextInput",
        "RCTUITextField": "TextInput",
        "RCTUITextView": "TextInput",
        // Switch, ActivityIndicator
        "RCTSwitchComponentView": "Switch",
        "RCTSwitch": "Switch",
        "RCTActivityIndicatorViewComponentView": "ActivityIndicator",
        "RCTActivityIndicatorView": "ActivityIndicator",
        // Modal: its content lives in the presented controller's view
        "RCTModalHostViewComponentView": "Modal",
        "RCTFabricModalHostViewController": "Modal",
        "RCTModalHostView": "Modal",
        "RCTModalHostViewController": "Modal",
        // SafeAreaView, from react-native and from react-native-safe-area-context
        "RCTSafeAreaViewComponentView": "SafeAreaView",
        "RCTSafeAreaView": "SafeAreaView",
        "RNCSafeAreaViewComponentView": "SafeAreaView",
        "RNCSafeAreaView": "SafeAreaView",
        // RefreshControl
        "RCTPullToRefreshViewComponentView": "RefreshControl",
        "RCTRefreshControl": "RefreshControl",
        // InputAccessoryView
        "RCTInputAccessoryComponentView": "InputAccessoryView",
        "RCTInputAccessoryContentView": "InputAccessoryView",
        "RCTInputAccessoryView": "InputAccessoryView",
        "RCTInputAccessoryViewContent": "InputAccessoryView"
    ]

    /// Components whose host view only ever holds RN's own UIKit backing view.
    private static let leafComponents: Set<String> = ["Switch", "ActivityIndicator", "Image", "TextInput"]

    private static let plumbing: Set<String> = [
        // react-native: surface and root containers, the ScrollView content box, dev overlays
        "RCTRootComponentView",
        "RCTSurfaceView",
        "RCTSurfaceRootView",
        "RCTSurfaceHostingView",
        "RCTSurfaceHostingProxyRootView",
        "RCTRootView",
        "RCTRootContentView",
        "RCTScrollContentView",
        "RCTLegacyViewManagerInteropComponentView",
        "RCTDebuggingOverlayComponentView",
        "RCTDebuggingOverlay",
        "RCTWrapperViewController",
        // react-native-safe-area-context
        "RNCSafeAreaProviderComponentView",
        "RNCSafeAreaProvider",
        // react-native-screens 4.x: screens, stacks, containers, header and overlay wrappers
        "RNSScreen",
        "RNSScreenView",
        "RNSModalScreen",
        "RNSScreenStackView",
        "RNSNavigationController",
        "RNSContainerNavigationController",
        "RNSScreenContainerView",
        "RNSScreenNavigationContainerView",
        "RNSViewController",
        "RNSScreenContentWrapper",
        "RNSScreenFooter",
        "RNSScreenStackHeaderConfig",
        "RNSScreenStackHeaderSubview",
        "RNSNavigationBar",
        "RNSFullWindowOverlay",
        "RNSFullWindowOverlayContainer",
        // react-native-screens: newer stack, tabs, split and modal containers
        "RNSStackHostComponentView",
        "RNSStackScreenComponentView",
        "RNSStackScreenController",
        "RNSStackNavigationController",
        "RNSStackNavigationBar",
        "RNSStackHeaderConfigComponentView",
        "RNSStackHeaderItemWrapperView",
        "RNSTabsHostComponentView",
        "RNSTabsScreenComponentView",
        "RNSTabsScreenViewController",
        "RNSTabBarController",
        "RNSTabsBottomAccessoryComponentView",
        "RNSTabsBottomAccessoryContentComponentView",
        "RNSTabsBottomAccessoryWrapperView",
        "RNSSplitHostComponentView",
        "RNSSplitHostController",
        "RNSSplitNavigationController",
        "RNSSplitScreenComponentView",
        "RNSSplitScreenController",
        "RNSFormSheetHostComponentView",
        "RNSFormSheetContentWrapperComponentView",
        "RNSFormSheetContentView",
        "RNSFormSheetContentController",
        "RNSContainedModalHostComponentView",
        "RNSContainedModalProviderComponentView",
        "RNSContainedModalProviderController",
        "RNSContainedModalContentView",
        "RNSContainedModalContentController",
        "RNSScrollViewMarkerComponentView",
        "RNSScrollToTopGuard"
    ]
}
