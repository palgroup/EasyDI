public import SwiftUI

/// Builds a screen with the mocks and instances selected around it.
///
/// ```swift
/// static func build() -> some View {
///     Injected { NoteListScreen(data: NoteListData()) }
/// }
///
/// #Preview("Error") {
///     NoteListBuilder.build().mock("failing")
/// }
/// ```
///
/// The selection comes from the environment, so a screen pushed or presented from
/// this one, built with its own `Injected`, gets it too. When the selection changes
/// the content is built again, with new data.
public struct Injected<Content: View>: View {
    @Environment(\.injectionSelection) private var selection
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Container.shared.with(selection, content)
            .id(selection)
    }
}

extension View {
    /// Under this view, contracts that have a mock named `name` get it.
    public func mock(_ name: String) -> some View {
        modifier(SelectionModifier(selection: .mock(name)))
    }

    /// Under this view, `contract` gets its mock named `name`.
    public func mock<Contract>(_ name: String, for contract: Contract.Type) -> some View {
        modifier(SelectionModifier(selection: .mock(name, for: contract)))
    }

    /// Under this view, `value` answers for the contract its type is registered for.
    public func inject<Value>(_ value: Value) -> some View {
        modifier(SelectionModifier(selection: .inject(value)))
    }

    /// Under this view, `value` answers for `contract`.
    public func inject<Contract>(_ value: Contract, as contract: Contract.Type) -> some View {
        modifier(SelectionModifier(selection: .inject(value, as: contract)))
    }
}

private struct SelectionModifier: ViewModifier {
    let selection: Injection.Selection
    @Environment(\.injectionSelection) private var current

    func body(content: Content) -> some View {
        content.environment(\.injectionSelection, current.merging(selection))
    }
}

private struct SelectionKey: EnvironmentKey {
    static var defaultValue: Injection.Selection { Injection.Selection() }
}

extension EnvironmentValues {
    var injectionSelection: Injection.Selection {
        get { self[SelectionKey.self] }
        set { self[SelectionKey.self] = newValue }
    }
}
