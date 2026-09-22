import Dexie, { type Table } from 'dexie'
import type { Change, EntityName, Row } from '../core/types'

export interface OutboxEntry extends Change {
  seq?: number
}

export interface RejectedEntry extends Change {
  seq?: number
  error: string
  rejected_at: string
}

export interface MetaEntry {
  key: string
  value: unknown
}

/**
 * Local copy of all data. Rows keep the wire shape {id, fields, clocks}; indexes point into
 * fields. Nulls are not indexed by IndexedDB, so e.g. inbox tasks (date = null) are not in
 * the fields.date index.
 */
export class AppDatabase extends Dexie {
  task!: Table<Row<'task'>, string>
  task_move!: Table<Row<'task_move'>, string>
  routine!: Table<Row<'routine'>, string>
  routine_version!: Table<Row<'routine_version'>, string>
  routine_check!: Table<Row<'routine_check'>, string>
  settings!: Table<Row<'settings'>, string>
  outbox!: Table<OutboxEntry, number>
  rejected!: Table<RejectedEntry, number>
  meta!: Table<MetaEntry, string>

  constructor(name: string) {
    super(name)
    this.version(1).stores({
      task: 'id, fields.date, fields.done_on',
      task_move: 'id, fields.task_id',
      routine: 'id',
      routine_version: 'id, fields.routine_id',
      routine_check: 'id, fields.date, fields.routine_id',
      settings: 'id',
      outbox: '++seq',
      rejected: '++seq',
      meta: 'key',
    })
  }

  entityTable<E extends EntityName>(entity: E): Table<Row<E>, string> {
    return this.table(entity) as Table<Row<E>, string>
  }
}
