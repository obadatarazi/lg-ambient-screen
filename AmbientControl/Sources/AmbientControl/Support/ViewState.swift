import SwiftUI

/// SwiftUI's `@State` is a macro in the macOS 27 SDK and its compiler plugin ships only
/// with Xcode. Aliasing the underlying property wrapper lets this package build with the
/// Command Line Tools alone; `@ViewState` behaves exactly like `@State`.
typealias ViewState<Value> = SwiftUI.State<Value>
