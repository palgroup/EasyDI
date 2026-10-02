public import SwiftSyntax
import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@Mock(NoteService.self)` or `@Mock(NoteService.self, "failing")` on a type
/// (built with `init()`) or on a static property that returns a mock.
///
/// Like `@Injectable`, it leaves a record in the `__DATA,__easydi` section. It is a
/// peer macro because a property can't take members; a peer of a nested type or of
/// a static property is a static member of the enclosing type.
public struct MockMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let arguments = node.arguments?.as(LabeledExprListSyntax.self).map(Array.init) ?? []
        guard let contractName = arguments.first.map({ displayName(of: $0.expression.trimmedDescription) }) else {
            throw MacroExpansionErrorMessage("@Mock needs the contract it stands for: @Mock(NoteService.self).")
        }
        let name = arguments.count > 1 ? arguments[1].expression.trimmedDescription : "nil"
        let owner = context.lexicalContext.lazy.compactMap(typeName(of:)).first

        let make: String
        let label: String
        let type: String
        let recordName: String
        let isMember: Bool
        if let variable = declaration.as(VariableDeclSyntax.self) {
            let isStatic = variable.modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
            guard isStatic, let owner, let binding = variable.bindings.first,
                  let property = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                throw MacroExpansionErrorMessage("@Mock goes on a type or on a static property of a type.")
            }
            try requireNonGenericContext(macro: "@Mock", context: context)
            make = "\(owner).\(property)"
            label = "\(owner).\(property)"
            // Only a concrete type tells `.inject(instance)` which contract an instance stands for.
            if let annotated = binding.typeAnnotation?.type, !annotated.is(SomeOrAnyTypeSyntax.self) {
                type = "\(annotated.trimmedDescription).self"
            } else {
                type = "nil"
            }
            recordName = property
            isMember = true
        } else {
            let mock = try ProvidedType(declaration, macro: "@Mock", context: context)
            make = "\(mock.name)()"
            label = mock.name
            type = "\(mock.name).self"
            recordName = mock.name
            isMember = owner != nil
        }
        return [
            """
            private nonisolated final class __EasyDIMock_\(raw: recordName): EasyDI.__PreviewRecord {
                override class func register() {
                    EasyDI.__registerMock(\(raw: existential(contractName)), name: \(raw: name), type: \(raw: type), contractName: \(literal: contractName), label: \(literal: label)) {
                        \(raw: make)
                    }
                }
            }
            """,
            """
            @section("__DATA,__easydi") @used
            private nonisolated \(raw: isMember ? "static " : "")let __easyDIMock_\(raw: recordName): @convention(c) () -> Void = {
                __EasyDIMock_\(raw: recordName).register()
            }
            """,
        ]
    }
}

private func typeName(of scope: Syntax) -> String? {
    scope.as(ClassDeclSyntax.self)?.name.text
        ?? scope.as(StructDeclSyntax.self)?.name.text
        ?? scope.as(EnumDeclSyntax.self)?.name.text
        ?? scope.as(ActorDeclSyntax.self)?.name.text
        ?? scope.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription
}
