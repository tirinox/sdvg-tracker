// Field-level last-writer-wins merge, see shared/README.md.

type Fields = Record<string, unknown>
type Clocks = Record<string, string | undefined>

/** Apply a change to a row in place. Returns true if any field was updated. */
export function mergeFields(
  fields: Fields,
  clocks: Clocks,
  changeFields: Fields,
  changeClocks: Clocks,
): boolean {
  let changed = false
  for (const [name, value] of Object.entries(changeFields)) {
    const clock = changeClocks[name]!
    const current = clocks[name]
    if (current === undefined || clock > current) {
      fields[name] = value
      clocks[name] = clock
      changed = true
    }
  }
  return changed
}
