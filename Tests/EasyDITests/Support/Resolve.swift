import EasyDI

/// What `@Inject` gives here: a local wrapper can't sit in a closure.
func resolve<Value>() -> Value {
    @Inject var value: Value
    return value
}
