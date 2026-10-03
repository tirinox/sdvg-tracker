// The title of a new task against the tasks and routines already listed: the same title is taken,
// unless everything under it is done today, then it is offered with a number; a similar one is warned
// about. Normative rule: shared/domain-fixtures/title_check.json.
import type { LocalDate } from '../core/types'
import { normalizeTitle, type TitleHistory } from './suggest'

export interface ListedItem {
  kind: 'task' | 'routine'
  id: string
  title: string
  emoji: string | null
  color: number
  /** Tasks: the planned day, null for the inbox. Routines: null. */
  date: LocalDate | null
  /** Done today; every other listed item is open. */
  done_today: boolean
}

export type TitleCheck =
  | { status: 'free'; similar: ListedItem[] }
  /** Already listed and open: the new task is not created. */
  | { status: 'taken'; item: ListedItem }
  /** Listed, but done today: it can be added again under `next`. */
  | { status: 'done_today'; item: ListedItem; next: string }

const FREE: TitleCheck = { status: 'free', similar: [] }

const NUMBERED = /^(.*\S)\s*\((\d{1,9})\)$/s

/** 'Выдать статус (2)' → base 'Выдать статус', number 2; a title without one has number 0. */
export function splitNumber(title: string): { base: string; n: number } {
  const t = title.trim()
  const m = NUMBERED.exec(t)
  return m ? { base: m[1]!, n: Number(m[2]) } : { base: t, n: 0 }
}

function nextTitle(items: ListedItem[], matched: ListedItem): string {
  const { base } = splitNumber(matched.title)
  const key = normalizeTitle(base)
  let n = 0
  for (const i of items) {
    const s = splitNumber(i.title)
    if (normalizeTitle(s.base) === key) n = Math.max(n, s.n)
  }
  const keys = new Set(items.map((i) => normalizeTitle(i.title)))
  let next: string
  do next = `${base} (${++n})`
  while (keys.has(normalizeTitle(next)))
  return next
}

/** Three-character windows of each word, padded with two spaces before and one after (as pg_trgm). */
function trigrams(key: string): Set<string> {
  const out = new Set<string>()
  for (const w of key.split(' ')) {
    const cs = Array.from(`  ${w} `)
    for (let i = 0; i + 3 <= cs.length; i++) out.add(cs.slice(i, i + 3).join(''))
  }
  return out
}

export function checkTitle(items: ListedItem[], title: string, limit = 2): TitleCheck {
  const q = normalizeTitle(title)
  if (!q) return FREE
  const same = items.filter((i) => normalizeTitle(i.title) === q)
  const open = same.find((i) => !i.done_today)
  if (open) return { status: 'taken', item: open }
  if (same.length) return { status: 'done_today', item: same[0]!, next: nextTitle(items, same[0]!) }

  const qt = trigrams(q)
  const similar = items
    .filter((i) => !i.done_today)
    .map((item) => {
      const t = trigrams(normalizeTitle(item.title))
      let shared = 0
      for (const g of qt) if (t.has(g)) shared++
      return { item, shared, all: qt.size + t.size - shared }
    })
    .filter((s) => 2 * s.shared > s.all)
  // Larger share first; the sort is stable, so equal shares keep list order.
  similar.sort((a, b) => b.shared * a.all - a.shared * b.all)
  return { status: 'free', similar: similar.slice(0, limit).map((s) => s.item) }
}

/** Title suggestions without the titles that are taken now: picking one would only be refused. */
export function withoutTaken(history: TitleHistory, items: ListedItem[]): TitleHistory {
  const taken = new Set(items.filter((i) => !i.done_today).map((i) => normalizeTitle(i.title)))
  return history.filter((g) => !taken.has(g.key))
}
