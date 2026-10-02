<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useApp } from '../app/context'
import {
  adherenceLabel,
  deadlineLabel,
  movesLabel,
  priorityStyle,
  priorityTag,
  reasonLabels,
  shortDate,
  timingLabel,
} from '../app/format'
import { tr } from '../app/i18n'
import { loadRoutineAdherence, type DayItem } from '../app/views'
import {
  completeTask,
  deleteTask,
  reopenTask,
  setRoutineCheck,
  updateTask,
} from '../db/actions'
import type { Adherence } from '../domain/routines'
import { celebrationLevel } from '../domain/tasks'
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

const { store, today, now, openTask, openRoutine, celebrate } = useApp()

const isTask = computed(() => props.item.kind === 'task')
const day = computed(() => props.date ?? today.value)
const timing = computed(() => timingLabel(props.item))
const deadline = computed(() => deadlineLabel(props.item, today.value))
// Deadline and moves already have tags on the row; the hint adds only the timing reason.
const hints = computed(() =>
  props.reasons ? reasonLabels({ ...props.item, reasons: props.item.reasons.filter((r) => r === 'now') }, now.value, today.value) : [],
)
const future = computed(() => day.value > today.value)

/** Time for the check to play before the row is marked done and leaves or moves down. */
const CHECK_MS = 420
/** The same when the "being skipped" tag has a new percent to count up to. */
const BOOST_MS = 1500
/** The count takes longer the further the percent goes, up to this. */
const COUNT_MS = 700

const reducedMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches

// Set on tap, before the write: the check fills at once and plays its animation.
const checking = ref(false)
const checked = computed(() => props.item.done || checking.value)

// The routine's adherence as the check makes it; the tag counts up to it at once.
const boost = ref<Adherence | null>(null)
/** What the "being skipped" tag shows, if anything: once the row is checked, the new rate. */
const lagging = computed(() => {
  if (checking.value && boost.value) return boost.value
  const a = props.item.adherence
  return a?.warning && !props.item.done && !props.item.skipped ? a : null
})
const shownPercent = ref(lagging.value?.percent ?? 0)
// Green with a thumbs up; follows the warning once the count has got there.
const ok = ref(false)
let counting = 0

watch(
  () => lagging.value?.percent ?? null,
  (target, before) => {
    cancelAnimationFrame(counting)
    if (target === null) return
    const warning = lagging.value!.warning
    const from = shownPercent.value
    if (warning) ok.value = false
    // A tag that was not there has nothing to count from.
    if (before === null || reducedMotion() || from === target) {
      shownPercent.value = target
      ok.value = !warning
      return
    }
    const ms = Math.min(COUNT_MS, 200 + 50 * Math.abs(target - from))
    const start = performance.now()
    const step = (t: number) => {
      const k = Math.min(1, (t - start) / ms)
      shownPercent.value = Math.round(from + (target - from) * (1 - (1 - k) ** 3))
      if (k < 1) counting = requestAnimationFrame(step)
      else ok.value = !warning
    }
    counting = requestAnimationFrame(step)
  },
)
onBeforeUnmount(() => cancelAnimationFrame(counting))

async function toggleDone(e: MouseEvent) {
  const i = props.item
  if (checking.value) return
  if (i.done) {
    await (i.kind === 'task' ? reopenTask(store, i.id) : setRoutineCheck(store, i.id, day.value, null))
    return
  }
  const lagged = i.kind === 'routine' && lagging.value !== null
  checking.value = true
  const level = i.kind === 'task' ? celebrationLevel(i.moves) : 0
  if (level) {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
    celebrate({ level, moves: i.moves, x: r.left + r.width / 2, y: r.top + r.height / 2 })
  }
  if (lagged) boost.value = await loadRoutineAdherence(store, i.id, today.value, day.value).catch(() => null)
  // The new percent is there to be read, so it gets its time with reduced motion too.
  if (boost.value || !reducedMotion()) {
    await new Promise((resolve) => setTimeout(resolve, boost.value ? BOOST_MS : CHECK_MS))
  }
  try {
    await (i.kind === 'task' ? completeTask(store, i.id, today.value) : setRoutineCheck(store, i.id, day.value, 'done'))
  } finally {
    // The check stays filled from the data now; keeping the flag a bit longer lets its animation finish.
    setTimeout(() => {
      checking.value = false
      boost.value = null
    }, 400)
  }
}

async function toggleSkip() {
  await setRoutineCheck(store, props.item.id, day.value, props.item.skipped ? null : 'skipped')
}

const toInbox = () => updateTask(store, props.item.id, { date: null })
const remove = () => deleteTask(store, props.item.id)
const edit = () => (isTask.value ? openTask(props.item.id) : openRoutine(props.item.id))
</script>

<template>
  <li
    class="row"
    :class="[
      `att-${item.attention}`,
      `dl-${item.deadline}`,
      `prio-${item.priority}`,
      { done: item.done, skipped: item.skipped, checking },
    ]"
    :style="item.priority === 'high' ? priorityStyle(item.key, item.color) : undefined"
  >
    <span v-if="item.priority === 'high'" class="prio-fx" :class="{ still: item.done || item.skipped }" aria-hidden="true" />
    <button class="main" type="button" @click="edit">
      <EmojiCircle :emoji="item.emoji" :color="item.color" />
      <span class="text">
        <span class="title">{{ item.title }}</span>
        <span class="meta">
          <span v-if="item.priority === 'high'" class="prio-tag">{{ priorityTag() }}</span>
          <span v-if="item.kind === 'routine'" class="tag routine" :title="tr('Регулярная', 'Routine')">⟳</span>
          <span v-if="timing">{{ timing }}</span>
          <span v-if="deadline && !item.done" class="tag deadline">{{ deadline }}</span>
          <span v-if="item.moves && !item.done" class="tag moves" :title="movesLabel(item.moves)">
            ↻ {{ item.moves }}
          </span>
          <span
            v-if="lagging"
            class="tag lagging"
            :class="{ ok }"
            :title="
              lagging.warning
                ? tr(`Рутина пропускается: ${adherenceLabel(lagging)}`, `Routine being skipped: ${adherenceLabel(lagging)}`)
                : tr(`Рутина снова выполняется: ${adherenceLabel(lagging)}`, `Routine back on track: ${adherenceLabel(lagging)}`)
            "
          >
            <span v-if="ok" class="thumb" aria-hidden="true">👍</span><template v-else>⚠︎</template>
            {{ shownPercent }}{{ tr('\u00a0%', '%') }}
          </span>
          <span v-if="item.skipped">{{ tr('пропущено', 'skipped') }}</span>
          <span v-if="item.priority === 'low' && !item.done && !item.skipped">↓ {{ tr('не срочно', 'not urgent') }}</span>
          <span v-if="compact && item.deadline_date" class="muted">
            {{ tr(`до ${shortDate(item.deadline_date)}`, `due ${shortDate(item.deadline_date)}`) }}
          </span>
        </span>
        <span v-if="hints.length" class="hints">
          <span v-for="h in hints" :key="h" class="hint">{{ h }}</span>
        </span>
      </span>
    </button>

    <div class="actions">
      <button
        v-if="!isTask && !item.done"
        class="icon"
        type="button"
        :title="item.skipped ? tr('Вернуть', 'Undo skip') : tr('Пропустить сегодня', 'Skip today')"
        @click="toggleSkip"
      >
        {{ item.skipped ? '↺' : '⤼' }}<span class="lbl">{{ item.skipped ? tr('Вернуть', 'Undo') : tr('Пропуск', 'Skip') }}</span>
      </button>
      <button
        class="check"
        :class="{ pop: checking }"
        type="button"
        :aria-pressed="checked"
        :disabled="!isTask && future"
        :title="item.done ? tr('Снять отметку', 'Mark as not done') : tr('Готово', 'Mark as done')"
        @click="toggleDone"
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path pathLength="1" d="M5 12.5l4.5 4.5L19 7.5" /></svg>
      </button>
    </div>

    <div v-if="item.attention >= 4 && !item.done" class="stuck">
      {{ tr('Застряла?', 'Stuck?') }}
      <button type="button" @click="edit">{{ tr('Разбить на шаги', 'Break into steps') }}</button>
      <button type="button" @click="toInbox">{{ tr('Во входящие', 'To inbox') }}</button>
      <button type="button" @click="remove">{{ tr('Удалить', 'Delete') }}</button>
    </div>
  </li>
</template>

<style scoped>
.row {
  position: relative;
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
/* Priority: high gets a stripe, a tag and a pulse (.prio-fx, styles.css); low steps back. */
.prio-high {
  border-color: color-mix(in srgb, var(--c) 40%, var(--line));
}
.prio-high .title {
  font-weight: 700;
}
.prio-low .title {
  color: var(--muted);
  font-weight: 450;
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
.tag.lagging {
  background: var(--warn-soft);
  color: var(--warn);
  font-variant-numeric: tabular-nums;
  transition:
    background 0.3s,
    color 0.3s;
}
/* A check took the routine out of the warning zone. */
.tag.lagging.ok {
  background: color-mix(in srgb, var(--ok) 14%, var(--surface));
  color: var(--ok);
}
.thumb {
  display: inline-block;
  transform-origin: 50% 80%;
  animation: thumb-pop 0.5s cubic-bezier(0.3, 1.6, 0.5, 1) both;
}
@keyframes thumb-pop {
  from {
    transform: scale(0.1) rotate(-30deg);
    opacity: 0;
  }
  60% {
    opacity: 1;
  }
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

/* Tap to done: the circle fills with a bounce, the tick draws itself and a ring ripples out. */
.check.pop {
  position: relative;
  animation: check-pop 0.45s cubic-bezier(0.3, 1.6, 0.5, 1);
}
.check.pop svg path {
  stroke-dasharray: 1;
  animation: check-draw 0.3s 0.08s ease-out both;
}
.check.pop::after {
  content: '';
  position: absolute;
  inset: -2px;
  border-radius: 50%;
  border: 2px solid var(--ok);
  animation: check-ring 0.55s ease-out forwards;
  pointer-events: none;
}
.row.checking {
  animation: row-flash 0.6s ease-out;
}
@keyframes check-pop {
  0% {
    transform: scale(1);
  }
  35% {
    transform: scale(0.82);
  }
  100% {
    transform: scale(1);
  }
}
@keyframes check-draw {
  from {
    stroke-dashoffset: 1;
  }
  to {
    stroke-dashoffset: 0;
  }
}
@keyframes check-ring {
  from {
    transform: scale(1);
    opacity: 0.8;
  }
  to {
    transform: scale(1.9);
    opacity: 0;
  }
}
@keyframes row-flash {
  30% {
    background: color-mix(in srgb, var(--ok) 14%, var(--surface));
    border-color: color-mix(in srgb, var(--ok) 50%, var(--line));
  }
}
@media (prefers-reduced-motion: reduce) {
  .check.pop,
  .check.pop svg path,
  .check.pop::after,
  .row.checking,
  .thumb {
    animation: none;
  }
  .check.pop::after {
    display: none;
  }
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
