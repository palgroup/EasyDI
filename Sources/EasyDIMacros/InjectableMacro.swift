public import SwiftSyntax
import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@Injectable(as: NoteService.self, .weak)` on a class, struct or actor.
///
/// Adds a record to the `__DATA,__easydi` section of the binary. EasyDI reads the
/// section of every loaded image, so the type is registered without a central list.
/// The record builds the type with `init()`; building it as the contract is what
/// checks, at compile time, that the type conforms to it.
public struct InjectableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let provider = try ProvidedType(declaration, macro: "@Injectable", context: context)
        let arguments = node.arguments?.as(LabeledExprListSyntax.self).map(Array.init) ?? []
        let named = arguments.first { $0.label?.text == "as" }.map { displayName(of: $0.expression.trimmedDescription) }
        let contract = named.map(existential) ?? "\(provider.name).self"
        let lifetime = arguments.first { $0.label == nil }?.expression.trimmedDescription ?? ".singleton"
        if lifetime.hasSuffix(".weak"), !provider.isReference {
            throw MacroExpansionErrorMessage(
                "@Injectable(.weak) keeps one instance while something holds it, which needs a class; \(provider.name) is a value type. Use .singleton or .transient."
            )
        }
        return [
            """
            @section("__DATA,__easydi") @used
            private nonisolated static let __easyDIRecord: @convention(c) () -> Void = {
                EasyDI.__register(\(raw: contract), provider: \(raw: provider.name).self, contractName: \(literal: named ?? provider.name), providerName: \(literal: provider.name), lifetime: \(raw: lifetime)) {
                    \(raw: provider.name)()
                }
            }
            """
        ]
    }
}

/// `NoteService.self` and `(any NoteService).self` → `NoteService`.
func displayName(of contract: String) -> String {
    var name = contract.hasSuffix(".self") ? String(contract.dropLast(".self".count)) : contract
    if name.hasPrefix("("), name.hasSuffix(")") { name = String(name.dropFirst().dropLast()) }
    if name.hasPrefix("any ") { name = String(name.dropFirst("any ".count)) }
    return name
}

/// A contract named in `as:` or `@Mock` is a protocol. The expansion spells it
/// `(any NoteService).self`: a bare `NoteService.self` is a warning with
/// ExistentialAny and an error in Swift 7.
func existential(_ name: String) -> String {
    "(any \(name)).self"
}

/// The type a macro registers, and the checks every registration needs.
struct ProvidedType {
    let name: String
    let isReference: Bool

    init(_ declaration: some SyntaxProtocol, macro: String, context: some MacroExpansionContext) throws {
        let generics: GenericParameterClauseSyntax?
        if let type = declaration.as(ClassDeclSyntax.self) {
            (name, isReference, generics) = (type.name.text, true, type.genericParameterClause)
        } else if let type = declaration.as(ActorDeclSyntax.self) {
            (name, isReference, generics) = (type.name.text, true, type.genericParameterClause)
        } else if let type = declaration.as(StructDeclSyntax.self) {
            (name, isReference, generics) = (type.name.text, false, type.genericParameterClause)
        } else {
            throw MacroExpansionErrorMessage("\(macro) goes on a class, struct or actor.")
        }
        if generics != nil {
            throw MacroExpansionErrorMessage("\(macro) can't register the generic type \(name): there is no one type to build. Register a concrete type.")
        }
        try requireNonGenericContext(macro: macro, context: context)
    }
}

/// A section record is a C function pointer, which can't depend on generic parameters.
func requireNonGenericContext(macro: String, context: some MacroExpansionContext) throws {
    for scope in context.lexicalContext {
        let generics = scope.as(ClassDeclSyntax.self)?.genericParameterClause
            ?? scope.as(StructDeclSyntax.self)?.genericParameterClause
            ?? scope.as(EnumDeclSyntax.self)?.genericParameterClause
            ?? scope.as(ActorDeclSyntax.self)?.genericParameterClause
        if generics != nil {
            throw MacroExpansionErrorMessage("\(macro) can't be used inside a generic type.")
        }
    }
}
