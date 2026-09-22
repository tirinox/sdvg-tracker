<script setup lang="ts">
import { computed } from 'vue'
import { useApp } from '../app/context'
import { deadlineLabel, movesLabel, reasonLabels, shortDate, timingLabel } from '../app/format'
import type { DayItem } from '../app/views'
import {
  completeTask,
  deleteTask,
  postponeTask,
  reopenTask,
  setRoutineCheck,
  updateTask,
} from '../db/actions'
import EmojiCircle from './EmojiCircle.vue'

const props = defineProps<{
  item: DayItem
  /** Day the row is shown on (routine marks go to this day). */
  date?: string
  /** Show "why it's here" hints (Now screen). */
  reasons?: boolean
  /** Show the planned date instead of timing (Inbox). */
  compact?: boolean
}>()

const { store, today, now, openTask, openRoutine } = useApp()

const isTask = computed(() => props.item.kind === 'task')
const day = computed(() => props.date ?? today.value)
const timing = computed(() => timingLabel(props.item))
const deadline = computed(() => deadlineLabel(props.item, today.value))
// Deadline and moves already have tags on the row; the hint adds only the timing reason.
const hints = computed(() =>
  props.reasons ? reasonLabels({ ...props.item, reasons: props.item.reasons.filter((r) => r === 'now') }, now.value, today.value) : [],
)
const future = computed(() => day.value > today.value)

async function toggleDone() {
  const i = props.item
  if (i.kind === 'task') {
    await (i.done ? reopenTask(store, i.id) : completeTask(store, i.id, today.value))
  } else {
    await setRoutineCheck(store, i.id, day.value, i.done ? null : 'done')
  }
}

async function toggleSkip() {
  await setRoutineCheck(store, props.item.id, day.value, props.item.skipped ? null : 'skipped')
}

const postpone = () => postponeTask(store, props.item.id, today.value)
const toInbox = () => updateTask(store, props.item.id, { date: null })
const remove = () => deleteTask(store, props.item.id)
const edit = () => (isTask.value ? openTask(props.item.id) : openRoutine(props.item.id))
</script>

<template>
  <li
    class="row"
    :class="[`att-${item.attention}`, `dl-${item.deadline}`, { done: item.done, skipped: item.skipped }]"
  >
    <button class="main" type="button" @click="edit">
      <EmojiCircle :emoji="item.emoji" :color="item.color" />
      <span class="text">
        <span class="title">{{ item.title }}</span>
        <span class="meta">
          <span v-if="item.kind === 'routine'" class="tag routine" title="Регулярная">⟳</span>
          <span v-if="timing">{{ timing }}</span>
          <span v-if="deadline && !item.done" class="tag deadline">{{ deadline }}</span>
          <span v-if="item.moves && !item.done" class="tag moves" :title="movesLabel(item.moves)">
            ↻ {{ item.moves }}
          </span>
          <span v-if="item.skipped">пропущено</span>
          <span v-if="compact && item.deadline_date" class="muted">
            до {{ shortDate(item.deadline_date) }}
          </span>
        </span>
        <span v-if="hints.length" class="hints">
          <span v-for="h in hints" :key="h" class="hint">{{ h }}</span>
        </span>
      </span>
    </button>

    <div class="actions">
      <button
        v-if="isTask && !item.done"
        class="icon"
        type="button"
        title="Перенести на завтра"
        @click="postpone"
      >
        ↷<span class="lbl">Завтра</span>
      </button>
      <button
        v-if="!isTask && !item.done"
        class="icon"
        type="button"
        :title="item.skipped ? 'Вернуть' : 'Пропустить сегодня'"
        @click="toggleSkip"
      >
        {{ item.skipped ? '↺' : '⤼' }}<span class="lbl">{{ item.skipped ? 'Вернуть' : 'Пропуск' }}</span>
      </button>
      <button
        class="check"
        type="button"
        :aria-pressed="item.done"
        :disabled="!isTask && future"
        :title="item.done ? 'Снять отметку' : 'Готово'"
        @click="toggleDone"
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
      </button>
    </div>

    <div v-if="item.attention >= 4 && !item.done" class="stuck">
      Застряла?
      <button type="button" @click="edit">Разбить на шаги</button>
      <button type="button" @click="toInbox">Во входящие</button>
      <button type="button" @click="remove">Удалить</button>
    </div>
  </li>
</template>

<style scoped>
.row {
  list-style: none;
  display: grid;
  grid-template-columns: 1fr auto;
  align-items: center;
  gap: 4px 8px;
  padding: 8px 10px 8px 8px;
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  transition: opacity 0.2s;
}
.main {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
  border: 0;
  background: none;
  padding: 0;
  text-align: left;
}
.text {
  display: grid;
  gap: 2px;
  min-width: 0;
}
.title {
  font-weight: 550;
  overflow-wrap: anywhere;
}
.meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 8px;
  font-size: 13px;
  color: var(--muted);
}
.tag {
  border-radius: 6px;
  padding: 0 6px;
  font-weight: 600;
  font-size: 12px;
  line-height: 20px;
}
.tag.routine {
  padding: 0;
  color: var(--faint);
}
.hints {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 2px;
}
.hint {
  font-size: 12px;
  background: var(--accent-soft);
  color: var(--accent);
  border-radius: 6px;
  padding: 1px 7px;
  font-weight: 600;
}

.actions {
  display: flex;
  align-items: center;
  gap: 4px;
}
.icon {
  border: 1px solid var(--line);
  background: var(--surface);
  border-radius: 10px;
  height: 34px;
  padding: 0 9px;
  color: var(--muted);
  font-size: 16px;
  display: inline-flex;
  align-items: center;
  gap: 5px;
}
.icon:hover {
  background: var(--surface-2);
  color: var(--fg);
}
.lbl {
  font-size: 13px;
}
@media (max-width: 520px) {
  .lbl {
    display: none;
  }
}
.check {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  border: 2px solid var(--line);
  background: var(--surface);
  display: grid;
  place-items: center;
  padding: 0;
}
.check svg {
  width: 20px;
  height: 20px;
  fill: none;
  stroke: var(--faint);
  stroke-width: 2.5;
  stroke-linecap: round;
  stroke-linejoin: round;
  opacity: 0.35;
}
.check:hover svg {
  opacity: 1;
}
.check[aria-pressed='true'] {
  background: var(--ok);
  border-color: var(--ok);
}
.check[aria-pressed='true'] svg {
  stroke: #fff;
  opacity: 1;
}

.done,
.skipped {
  opacity: 0.55;
}
.done .title {
  text-decoration: line-through;
  text-decoration-color: var(--faint);
}

/* Deadlines */
.dl-ok .deadline {
  background: var(--surface-2);
  color: var(--muted);
}
.dl-soon .deadline {
  background: var(--warn-soft);
  color: var(--warn);
}
.dl-today .deadline,
.dl-overdue .deadline {
  background: var(--danger-soft);
  color: var(--danger);
}

/* Attention by postpone count: grows louder the more a task is moved. */
.moves {
  background: var(--surface-2);
  color: var(--muted);
}
.att-2 .moves {
  background: var(--warn-soft);
  color: var(--warn);
}
.att-2 {
  border-color: color-mix(in srgb, var(--warn) 45%, var(--line));
}
.att-3 .moves,
.att-4 .moves {
  background: var(--danger);
  color: #fff;
}
.att-3,
.att-4 {
  border-color: color-mix(in srgb, var(--danger) 55%, var(--line));
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--danger) 25%, transparent);
}
.att-3:not(.done) .moves,
.att-4:not(.done) .moves {
  animation: pulse 2.4s ease-in-out infinite;
}
@keyframes pulse {
  50% {
    box-shadow: 0 0 0 5px color-mix(in srgb, var(--danger) 18%, transparent);
  }
}
.stuck {
  grid-column: 1 / -1;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: var(--danger);
  font-weight: 600;
  padding: 6px 4px 2px 52px;
}
.stuck button {
  border: 1px solid color-mix(in srgb, var(--danger) 40%, var(--line));
  background: var(--danger-soft);
  color: var(--danger);
  border-radius: 8px;
  padding: 2px 9px;
  font-size: 13px;
}
</style>
