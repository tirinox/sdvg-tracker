// Title suggestions for a new task from the task history. Normative rule:
// shared/domain-fixtures/title_suggestions.json.
import type { LocalDate } from '../core/types'
import { daysBetween } from './dates'

export interface HistoryTask {
  id: string
  title: string
  emoji: string | null
  color: number
  duration_min: number | null
  done_on: LocalDate | null
  deleted: boolean
  /** Local date the task was created. */
  created_on: LocalDate
}

export interface TitleSuggestion {
  title: string
  emoji: string | null
  color: number
  duration_min: number | null
  uses: number
}

interface Group extends TitleSuggestion {
  key: string
  words: string[]
  weight: number
  lastUsed: LocalDate
}

/** Built once per history load; `suggestTitles` then runs on every keystroke. */
export type TitleHistory = Group[]

const HALF_LIFE_DAYS = 30

/** NFC, lowercase, ё → е, runs of non-letters/digits → one space. */
export function normalizeTitle(s: string): string {
  return s
    .normalize('NFC')
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

export function titleHistory(tasks: HistoryTask[], today: LocalDate): TitleHistory {
  const used = (t: HistoryTask) => t.done_on ?? t.created_on
  const byKey = new Map<string, HistoryTask[]>()
  for (const t of tasks) {
    if (t.deleted && !t.done_on) continue
    const key = normalizeTitle(t.title)
    if (!key) continue
    byKey.set(key, [...(byKey.get(key) ?? []), t])
  }
  const groups: Group[] = []
  for (const [key, list] of byKey) {
    // Latest first.
    list.sort((a, b) => cmp(used(b), used(a)) || cmp(b.id, a.id))
    const latest = list[0]!
    const look = list.find((t) => t.emoji) ?? latest
    groups.push({
      key,
      words: key.split(' '),
      title: latest.title.trim(),
      emoji: look.emoji,
      color: look.color,
      duration_min: list.find((t) => t.duration_min !== null)?.duration_min ?? null,
      uses: list.length,
      weight: list.reduce(
        (w, t) => w + 0.5 ** (Math.max(0, daysBetween(used(t), today)) / HALF_LIFE_DAYS),
        0,
      ),
      lastUsed: used(latest),
    })
  }
  return groups
}

export function suggestTitles(history: TitleHistory, query: string, limit = 5): TitleSuggestion[] {
  const q = normalizeTitle(query)
  if (!q) return []
  const qWords = q.split(' ')
  const tierOf = (g: Group): number | null => {
    if (g.key === q) return null
    if (g.key.startsWith(q)) return 0
    return qWords.every((w) => g.words.some((gw) => gw.startsWith(w))) ? 1 : null
  }
  return history
    .flatMap((g) => {
      const tier = tierOf(g)
      return tier === null ? [] : [{ g, tier }]
    })
    .sort(
      (a, b) =>
        a.tier - b.tier ||
        b.g.weight - a.g.weight ||
        cmp(b.g.lastUsed, a.g.lastUsed) ||
        cmp(a.g.key, b.g.key),
    )
    .slice(0, limit)
    .map(({ g }) => ({
      title: g.title,
      emoji: g.emoji,
      color: g.color,
      duration_min: g.duration_min,
      uses: g.uses,
    }))
}

/** Plain string order, not locale-aware, so web and iOS sort the same. */
function cmp(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}
