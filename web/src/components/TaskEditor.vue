<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useApp } from '../app/context'
import { plural } from '../app/format'
import type { Task } from '../core/types'
import { createTask, deleteTask, moveCount, rescheduleTask, updateTask, type NewTask } from '../db/actions'
import { addDays } from '../domain/dates'
import AppearanceFields from './AppearanceFields.vue'
import Modal from './Modal.vue'
import TimingFields from './TimingFields.vue'

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
let originalDate: string | null = null
const loaded = ref(props.id === null)
const title = ref<HTMLInputElement>()

onMounted(async () => {
  if (props.id) {
    const t = await store.get('task', props.id)
    if (t) {
      Object.assign(form, pick(t))
      originalDate = t.date
    }
    moves.value = await moveCount(store, props.id)
    loaded.value = true
  }
  title.value?.focus()
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
const valid = computed(() => form.title.trim().length > 0 && (form.time_kind !== 'exact' || !!form.time))

async function save() {
  if (!valid.value) return
  const data = {
    ...form,
    title: form.title.trim(),
    part_of_day: form.time_kind === 'part' ? form.part_of_day : null,
    time: form.time_kind === 'exact' ? form.time : null,
    deadline_time: form.deadline_date ? form.deadline_time || null : null,
  }
  if (props.id) {
    const { date, ...rest } = data
    await updateTask(store, props.id, rest)
    if (date !== originalDate) await rescheduleTask(store, props.id, date, today.value)
  } else {
    await createTask(store, data)
  }
  emit('close')
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
      <input
        ref="title"
        v-model="form.title"
        class="input title"
        placeholder="Что нужно сделать?"
        @keydown.enter="save"
      />
      <AppearanceFields v-model:emoji="form.emoji" v-model:color="form.color" />

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
    </template>

    <template #footer>
      <button v-if="id" class="btn danger" type="button" @click="remove">Удалить</button>
      <span style="flex: 1" />
      <button class="btn" type="button" @click="emit('close')">Отмена</button>
      <button class="btn primary" type="button" :disabled="!valid" @click="save">Сохранить</button>
    </template>
  </Modal>
</template>

<style scoped>
.title {
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
.moves {
  margin: 0;
  font-size: 14px;
  color: var(--warn);
  background: var(--warn-soft);
  border-radius: 10px;
  padding: 8px 10px;
}
</style>
