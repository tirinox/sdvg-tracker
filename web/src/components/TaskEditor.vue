<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useApp } from '../app/context'
import { plural, relativeDay, shortDate } from '../app/format'
import type { Task } from '../core/types'
import {
  copyTask,
  createTask,
  deleteTask,
  moveCount,
  postponeTask,
  rescheduleTask,
  updateTask,
  type NewTask,
} from '../db/actions'
import { addDays } from '../domain/dates'
import type { TitleSuggestion } from '../domain/suggest'
import { autoEmoji } from '../sync/emoji'
import AppearanceFields from './AppearanceFields.vue'
import Modal from './Modal.vue'
import TimingFields from './TimingFields.vue'
import TitleInput from './TitleInput.vue'

const props = defineProps<{ id: string | null; defaults: Partial<NewTask> }>()
const emit = defineEmits<{ close: [] }>()
const { store, today } = useApp()

const form = reactive({
  title: '',
  notes: '',
  emoji: null as string | null,
  color: 7,
  date: today.value as string | null,
  time_kind: 'none' as Task['time_kind'],
  part_of_day: null as Task['part_of_day'],
  time: null as string | null,
  duration_min: null as number | null,
  deadline_date: null as string | null,
  deadline_time: null as string | null,
  ...props.defaults,
})
const moves = ref(0)
const done = ref(false)
let originalDate: string | null = null
const loaded = ref(props.id === null)
const titleInput = ref<InstanceType<typeof TitleInput>>()

onMounted(async () => {
  if (props.id) {
    const t = await store.get('task', props.id)
    if (t) {
      Object.assign(form, pick(t))
      originalDate = t.date
      done.value = Boolean(t.done_on)
    }
    moves.value = await moveCount(store, props.id)
    loaded.value = true
  }
  titleInput.value?.focus()
})

function pick(t: Task) {
  const { title, notes, emoji, color, date, time_kind, part_of_day, time } = t
  const { duration_min, deadline_date, deadline_time } = t
  return { title, notes, emoji, color, date, time_kind, part_of_day, time, duration_min, deadline_date, deadline_time }
}

const inbox = computed({
  get: () => form.date === null,
  set: (v: boolean) => (form.date = v ? null : today.value),
})
/** A task from the history: its title and the look it had last time. */
function applySuggestion(s: TitleSuggestion) {
  Object.assign(form, { title: s.title, emoji: s.emoji, color: s.color })
  if (s.duration_min !== null) form.duration_min = s.duration_min
}

const valid = computed(() => form.title.trim().length > 0 && (form.time_kind !== 'exact' || !!form.time))

/** The form as a task: fields that the chosen timing and deadline do not use are cleared. */
function content() {
  return {
    ...form,
    title: form.title.trim(),
    part_of_day: form.time_kind === 'part' ? form.part_of_day : null,
    time: form.time_kind === 'exact' ? form.time : null,
    deadline_time: form.deadline_date ? form.deadline_time || null : null,
  }
}

async function persist() {
  const data = content()
  if (props.id) {
    const { date, ...rest } = data
    await updateTask(store, props.id, rest)
    if (date !== originalDate) await rescheduleTask(store, props.id, date, today.value)
  } else {
    const id = await createTask(store, data)
    if (!data.emoji) void autoEmoji(store, id, data.title)
  }
}

async function save() {
  if (!valid.value) return
  await persist()
  emit('close')
}

/** Keeps any edits made in the form, then moves the task one day forward. */
async function postpone() {
  if (!props.id || !valid.value) return
  await persist()
  await postponeTask(store, props.id, today.value)
  emit('close')
}

const copyDate = ref(addDays(today.value, 1))
const copied = ref<{ id: string; date: string } | null>(null)
const canCopy = computed(() => valid.value && copyDate.value >= today.value)

function dayLabel(d: string): string {
  return relativeDay(d, today.value)?.toLowerCase() ?? shortDate(d)
}

/** Copies the form as it is now; the task itself changes only on "Сохранить". */
async function copy() {
  if (!canCopy.value) return
  const date = copyDate.value
  copied.value = { id: await copyTask(store, content(), date), date }
}

async function undoCopy() {
  if (!copied.value) return
  await deleteTask(store, copied.value.id)
  copied.value = null
}

async function remove() {
  if (props.id && confirm('Удалить задачу?')) {
    await deleteTask(store, props.id)
    emit('close')
  }
}
</script>

<template>
  <Modal :title="id ? 'Задача' : 'Новая задача'" @close="emit('close')">
    <template v-if="loaded">
      <TitleInput
        ref="titleInput"
        v-model="form.title"
        class="title"
        placeholder="Что нужно сделать?"
        :plain="Boolean(id)"
        @enter="save"
        @pick="applySuggestion"
      />
      <AppearanceFields v-model:emoji="form.emoji" v-model:color="form.color" :title="form.title" :auto="!id" />

      <div class="field">
        <span>День</span>
        <div class="chips">
          <button type="button" class="chip" :aria-pressed="form.date === today" @click="form.date = today">
            Сегодня
          </button>
          <button
            type="button"
            class="chip"
            :aria-pressed="form.date === addDays(today, 1)"
            @click="form.date = addDays(today, 1)"
          >
            Завтра
          </button>
          <button type="button" class="chip" :aria-pressed="inbox" @click="inbox = true">📥 Во входящие</button>
          <input v-if="!inbox" v-model="form.date" class="input date" type="date" :min="today" />
        </div>
      </div>

      <TimingFields
        v-model:kind="form.time_kind"
        v-model:part="form.part_of_day"
        v-model:time="form.time"
        v-model:duration="form.duration_min"
      />

      <div class="pair">
        <label class="field">
          <span>Дедлайн (необязательно)</span>
          <input v-model="form.deadline_date" class="input" type="date" />
        </label>
        <label v-if="form.deadline_date" class="field">
          <span>до времени</span>
          <input v-model="form.deadline_time" class="input" type="time" />
        </label>
      </div>

      <label class="field">
        <span>Заметки</span>
        <textarea v-model="form.notes" class="input" rows="2" placeholder="Шаги, ссылки, мысли…" />
      </label>

      <p v-if="moves" class="moves">
        ↻ Задачу переносили уже {{ moves }} {{ plural(moves, 'раз', 'раза', 'раз') }}. Может, разбить её на
        шаги поменьше?
      </p>

      <div v-if="id" class="field">
        <span>Копия задачи</span>
        <div class="chips">
          <input v-model="copyDate" class="input date" type="date" :min="today" aria-label="День для копии" />
          <button type="button" class="btn" :disabled="!canCopy" @click="copy">
            ⧉ Копировать на {{ copyDate ? dayLabel(copyDate) : '…' }}
          </button>
        </div>
        <p v-if="copied" class="copied" role="status">
          ✓ Копия на {{ dayLabel(copied.date) }} готова
          <button type="button" class="btn ghost" @click="undoCopy">Отменить</button>
        </p>
      </div>
    </template>

    <template #footer>
      <button v-if="id" class="btn danger" type="button" @click="remove">Удалить</button>
      <span style="flex: 1" />
      <button
        v-if="id && !done"
        class="btn"
        type="button"
        :disabled="!valid"
        title="Перенести на следующий день — это посчитается как перенос"
        @click="postpone"
      >
        ↷ На завтра
      </button>
      <button class="btn" type="button" @click="emit('close')">Отмена</button>
      <button class="btn primary" type="button" :disabled="!valid" @click="save">Сохранить</button>
    </template>
  </Modal>
</template>

<style scoped>
.title :deep(.input) {
  font-size: 17px;
  font-weight: 600;
  padding: 10px 12px;
}
.date {
  width: auto;
  padding: 4px 8px;
}
.pair {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 10px;
}
.copied {
  display: flex;
  align-items: center;
  gap: 4px;
  margin: 0;
  font-size: 14px;
  color: var(--ok);
}
.copied .btn {
  padding: 2px 8px;
  color: var(--accent);
}
.moves {
  margin: 0;
  font-size: 14px;
  color: var(--warn);
  background: var(--warn-soft);
  border-radius: 10px;
  padding: 8px 10px;
}
</style>
