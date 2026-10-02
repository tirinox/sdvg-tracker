// Loads routines and tasks from a JSON file into an empty sync server, using the same code as
// the web app. Everything starts on one day: routines take effect from it, tasks are planned
// on it, and routines marked "done" get a check for it.
//   npx tsx scripts/import.ts --url http://localhost:8420 --file ../private/tasks.json [--force]
//
// File: { "routines": [Item & { weekdays?: ["mon", ...], done?: true }], "tasks": [Item] }
//   Item = { title, emoji?, color?, part?: "morning" | "day" | "evening", time?: "HH:MM", duration?,
//            priority?: "low" | "normal" | "high" }
// Ids derive from the titles, so importing the same file twice updates rather than duplicates.
import 'fake-indexeddb/auto'
import { readFileSync } from 'node:fs'
import { generateNKeysBetween } from 'fractional-indexing'
import { v5 as uuidv5 } from 'uuid'
import { routineCheckId } from '../src/core/ids'
import type { PartOfDay, Priority, RoutineVersion, Task, TimeKind } from '../src/core/types'
import { localNow, logicalDay } from '../src/domain/dates'
import type { LocalChange } from '../src/db/store'
import { Store } from '../src/db/store'
import { SyncClient, saveSyncConfig } from '../src/sync/client'

interface Item {
  title: string
  emoji?: string
  color?: number
  part?: PartOfDay
  time?: string
  duration?: number
  priority?: Priority
}
interface RoutineItem extends Item {
  weekdays?: string[]
  done?: boolean
}

const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
const IMPORT_NAMESPACE = uuidv5('urn:sdvg-tracker:import', uuidv5.URL)
const importId = (key: string) => uuidv5(key, IMPORT_NAMESPACE)

const args = process.argv.slice(2)
const arg = (name: string) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined)
const url = arg('--url')
const file = arg('--file')
const token = process.env.SDVG_TOKEN
if (!url || !file || !token) {
  console.error('usage: SDVG_TOKEN=... tsx scripts/import.ts --url http://host:port --file tasks.json [--force]')
  process.exit(2)
}

const data = JSON.parse(readFileSync(file, 'utf8')) as { routines?: RoutineItem[]; tasks?: Item[] }
const routines = data.routines ?? []
const tasks = data.tasks ?? []

function timing(item: Item): { time_kind: TimeKind; part_of_day: PartOfDay | null; time: string | null } {
  if (item.time) return { time_kind: 'exact', part_of_day: null, time: item.time }
  if (item.part) return { time_kind: 'part', part_of_day: item.part, time: null }
  return { time_kind: 'none', part_of_day: null, time: null }
}

function weekdayMask(days: string[] | undefined): number {
  if (!days) return 127
  return days.reduce((mask, d) => {
    const bit = WEEKDAYS.indexOf(d.toLowerCase())
    if (bit < 0) throw new Error(`Unknown weekday "${d}", expected one of ${WEEKDAYS.join(', ')}`)
    return mask | (1 << bit)
  }, 0)
}

const store = await Store.open(`import-${crypto.randomUUID()}`)
await saveSyncConfig(store, { baseUrl: url.replace(/\/$/, ''), token })
const client = new SyncClient(store)

async function sync(step: string) {
  await client.sync()
  if (client.status.state !== 'idle') {
    console.error(`${step}: sync failed: ${client.status.state} ${client.status.error ?? ''}`)
    process.exit(1)
  }
}

await sync('pull')
const existing = (await store.rows('task')).length + (await store.rows('routine')).length
if (existing > 0 && !args.includes('--force')) {
  console.error(`The server already has ${existing} tasks and routines; import expects an empty one (--force to merge).`)
  process.exit(1)
}

const settings = await store.settings()
const today = logicalDay(localNow(), settings.day_start_hour)
const createdAt = new Date().toISOString()
const changes: LocalChange[] = []

// One sequence for both: the day view orders routines and tasks together, routines first.
const sortKeys = generateNKeysBetween(null, null, routines.length + tasks.length)
routines.forEach((item, i) => {
  const routineId = importId(`routine:${item.title}`)
  const version: RoutineVersion = {
    routine_id: routineId,
    effective_from: today,
    title: item.title,
    emoji: item.emoji ?? null,
    color: item.color ?? 0,
    ...timing(item),
    duration_min: item.duration ?? null,
    priority: item.priority ?? 'normal',
    weekdays: weekdayMask(item.weekdays),
    archived: false,
    created_at: createdAt,
  }
  changes.push(
    { entity: 'routine', id: routineId, fields: { sort_key: sortKeys[i]!, created_at: createdAt } },
    { entity: 'routine_version', id: importId(`routine_version:${item.title}:${today}`), fields: version },
  )
  if (item.done) {
    changes.push({
      entity: 'routine_check',
      id: routineCheckId(routineId, today),
      fields: {
        routine_id: routineId,
        date: today,
        status: 'done',
        done_at: createdAt,
        snapshot: {
          title: version.title,
          emoji: version.emoji,
          color: version.color,
          time_kind: version.time_kind,
          part_of_day: version.part_of_day,
          time: version.time,
        },
      },
    })
  }
})

tasks.forEach((item, i) => {
  const task: Task = {
    title: item.title,
    notes: '',
    emoji: item.emoji ?? null,
    color: item.color ?? 0,
    date: today,
    first_date: today,
    ...timing(item),
    duration_min: item.duration ?? null,
    priority: item.priority ?? 'normal',
    deadline_date: null,
    deadline_time: null,
    done_on: null,
    deleted: false,
    sort_key: sortKeys[routines.length + i]!,
    created_at: createdAt,
  }
  changes.push({ entity: 'task', id: importId(`task:${item.title}`), fields: task })
})

await store.write(changes)
await sync('push')
const done = routines.filter((r) => r.done).length
console.log(`Imported for ${today}: ${routines.length} routines (${done} done today), ${tasks.length} tasks.`)
store.close()
