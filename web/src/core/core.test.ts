import { describe, expect, it } from 'vitest'
import { loadShared, sharedFiles, type Json } from '../test/shared'
import { Clock, parseHlc } from './hlc'
import { IDS_NAMESPACE, routineCheckId, taskMoveId } from './ids'
import { mergeFields } from './merge'

describe('HLC vectors', () => {
  const vectors = loadShared('vectors/hlc.json')

  it.each<[string, Json]>(vectors.cases.map((c: Json) => [c.name, c]))('%s', (_name, c) => {
    let pt = 0
    const initial = c.initial ?? { l: 0, c: 0 }
    const clock = new Clock(c.node_id, () => pt, { ms: initial.l, counter: initial.c })
    for (const step of c.steps) {
      pt = step.pt
      const got = step.op === 'now' ? clock.now() : clock.receive(step.remote)
      expect(got).toBe(step.expect)
    }
  })

  it('orders by plain string comparison', () => {
    const ordering: string[] = vectors.ordering
    expect([...ordering].sort()).toEqual(ordering)
    const byParts = [...ordering].sort((a, b) => {
      const x = parseHlc(a)
      const y = parseHlc(b)
      return x.ms - y.ms || x.counter - y.counter || x.nodeId.localeCompare(y.nodeId)
    })
    expect(byParts).toEqual(ordering)
  })

  it('resumes past a persisted timestamp even if the wall clock went back', () => {
    const clock = Clock.resume('0123456789abcdef', '1790000005000-0003-0123456789abcdef', () => 1)
    expect(clock.now()).toBe('1790000005000-0004-0123456789abcdef')
  })
})

describe('deterministic ids', () => {
  const vectors = loadShared('vectors/ids.json')

  it('namespace matches', () => {
    expect(IDS_NAMESPACE).toBe(vectors.namespace)
  })

  it.each<[string, Json]>(vectors.cases.map((c: Json) => [c.name, c]))('%s', (_name, c) => {
    const [entity, id, date] = c.name.split(':')
    const got = entity === 'routine_check' ? routineCheckId(id, date) : taskMoveId(id, date)
    expect(got).toBe(c.expect)
  })
})

describe('merge fixtures', () => {
  function apply(initial: Json[], changes: Json[]): Json[] {
    const rows = new Map<string, Json>()
    for (const ch of structuredClone([...initial, ...changes])) {
      const key = `${ch.entity}|${ch.id}`
      if (!rows.has(key)) rows.set(key, { entity: ch.entity, id: ch.id, fields: {}, clocks: {} })
      const row = rows.get(key)
      mergeFields(row.fields, row.clocks, ch.fields, ch.clocks)
    }
    const byKey = (a: Json, b: Json) =>
      a.entity === b.entity ? (a.id < b.id ? -1 : 1) : a.entity < b.entity ? -1 : 1
    return [...rows.values()].sort(byKey)
  }

  function* permutations<T>(items: T[]): Generator<T[]> {
    if (items.length <= 1) {
      yield items
      return
    }
    for (let i = 0; i < items.length; i++) {
      const rest = [...items.slice(0, i), ...items.slice(i + 1)]
      for (const p of permutations(rest)) yield [items[i]!, ...p]
    }
  }

  const cases = sharedFiles('sync-fixtures').flatMap((f) =>
    loadShared(`sync-fixtures/${f}`).cases.map((c: Json) => [`${f}: ${c.name}`, c]),
  )

  it.each<[string, Json]>(cases)('%s', (_name, c) => {
    const orders = c.order_independent ? permutations(c.changes) : [c.changes]
    for (const order of orders) expect(apply(c.initial, order)).toEqual(c.expected)
  })
})
