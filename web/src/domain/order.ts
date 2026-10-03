import type { Priority } from '../core/types'

const RANK: Record<Priority, number> = { high: 0, normal: 1, low: 2 }

/** Position of a priority in lists; no priority (rows from before priorities) is normal. */
export function priorityRank(p: Priority | null | undefined): number {
  return RANK[p ?? 'normal']
}

export interface OrderItem {
  done: boolean
  skipped: boolean
  priority?: Priority | null
  time: string | null
  sort_key: string
}

/** Open first, then by priority; untimed before timed ones by time, then by manual order (shared/domain-fixtures/item_order.json). */
export function compareItems(a: OrderItem, b: OrderItem): number {
  if (a.done !== b.done || a.skipped !== b.skipped) {
    return Number(a.done || a.skipped) - Number(b.done || b.skipped)
  }
  const rank = priorityRank(a.priority) - priorityRank(b.priority)
  if (rank) return rank
  if (a.time && b.time && a.time !== b.time) return a.time < b.time ? -1 : 1
  if (Boolean(a.time) !== Boolean(b.time)) return a.time ? 1 : -1
  return a.sort_key < b.sort_key ? -1 : a.sort_key > b.sort_key ? 1 : 0
}

/** High priority leads the Now screen only once its time has come; before that it ranks as normal. */
function nowRank(i: OrderItem & { started?: boolean }): number {
  return i.priority === 'high' && i.started === false ? priorityRank('normal') : priorityRank(i.priority)
}

/**
 * Top of the Now screen from items in day order (shared/domain-fixtures/now_pick.json):
 * scored items and high-priority ones whose time has come, by priority and score, topped up
 * with the next open items.
 */
export function pickTop<T extends OrderItem & { score: number; started?: boolean }>(items: T[], max = 7, min = 5): T[] {
  const open = items.filter((i) => !i.done && !i.skipped)
  const ranked = open
    .filter((i) => i.score > 0 || (i.priority === 'high' && i.started !== false))
    .sort((a, b) => nowRank(a) - nowRank(b) || b.score - a.score || compareItems(a, b))
    .slice(0, max)
  const rest = open.filter((i) => !ranked.includes(i))
  return [...ranked, ...rest.slice(0, Math.max(0, min - ranked.length))]
}
