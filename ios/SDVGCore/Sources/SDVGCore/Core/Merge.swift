/// Field-level last-writer-wins merge, see shared/README.md.
/// Applies a change to a row in place; returns true if any field was updated.
@discardableResult
public func mergeFields(_ fields: inout Fields, _ clocks: inout Clocks, _ changeFields: Fields, _ changeClocks: Clocks) -> Bool {
    var changed = false
    for (name, value) in changeFields {
        guard let clock = changeClocks[name] else { continue }
        if let current = clocks[name], clock <= current { continue }
        fields[name] = value
        clocks[name] = clock
        changed = true
    }
    return changed
}
