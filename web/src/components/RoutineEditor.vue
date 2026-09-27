<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useApp } from '../app/context'
import { WEEKDAYS } from '../app/format'
import type { RoutineVersion } from '../core/types'
import { archiveRoutine, createRoutine, editRoutine, routineVersions, type RoutineContent } from '../db/actions'
import AppearanceFields from './AppearanceFields.vue'
import Modal from './Modal.vue'
import TimingFields from './TimingFields.vue'

const props = defineProps<{ id: string | null }>()
const emit = defineEmits<{ close: [] }>()
const { store, today } = useApp()

const form = reactive<Required<RoutineContent>>({
  title: '',
  emoji: null,
  color: 4,
  time_kind: 'none',
  part_of_day: null,
  time: null,
  duration_min: null,
  weekdays: 127,
})
let original: Required<RoutineContent> | null = null
const loaded = ref(props.id === null)

onMounted(async () => {
  if (!props.id) return
  const latest = (await routineVersions(store, props.id))
    .sort((a, b) => (a.effective_from + a.hlc < b.effective_from + b.hlc ? -1 : 1))
    .at(-1)
  if (latest) {
    const { title, emoji, color, time_kind, part_of_day, time, duration_min, weekdays } = latest as RoutineVersion
    original = { title, emoji, color, time_kind, part_of_day, time, duration_min, weekdays }
    Object.assign(form, original)
  }
  loaded.value = true
})

const valid = computed(
  () => form.title.trim().length > 0 && form.weekdays > 0 && (form.time_kind !== 'exact' || !!form.time),
)

function toggleDay(i: number) {
  form.weekdays ^= 1 << i
}

async function save() {
  if (!valid.value) return
  const data = {
    ...form,
    title: form.title.trim(),
    part_of_day: form.time_kind === 'part' ? form.part_of_day : null,
    time: form.time_kind === 'exact' ? form.time : null,
  }
  if (!props.id) {
    await createRoutine(store, data, today.value)
  } else {
    const changed = Object.fromEntries(
      Object.entries(data).filter(([k, v]) => original?.[k as keyof RoutineContent] !== v),
    )
    if (Object.keys(changed).length) await editRoutine(store, props.id, changed, today.value)
  }
  emit('close')
}

async function archive() {
  if (props.id && confirm('Убрать рутину? Прошлые дни останутся в истории.')) {
    await archiveRoutine(store, props.id, today.value)
    emit('close')
  }
}
</script>

<template>
  <Modal :title="id ? 'Регулярная задача' : 'Новая регулярная задача'" @close="emit('close')">
    <template v-if="loaded">
      <input v-model="form.title" class="input title" placeholder="Например, «Пообедать»" @keydown.enter="save" />
      <AppearanceFields v-model:emoji="form.emoji" v-model:color="form.color" :title="form.title" :auto="!id" />
      <TimingFields
        v-model:kind="form.time_kind"
        v-model:part="form.part_of_day"
        v-model:time="form.time"
        v-model:duration="form.duration_min"
      />
      <div class="field">
        <span>Дни недели</span>
        <div class="chips">
          <button
            v-for="(d, i) in WEEKDAYS"
            :key="d"
            type="button"
            class="chip"
            :aria-pressed="Boolean(form.weekdays & (1 << i))"
            @click="toggleDay(i)"
          >
            {{ d }}
          </button>
        </div>
      </div>
      <p class="muted note">
        Регулярные задачи не переносятся. Изменения действуют с сегодняшнего дня (или с завтрашнего,
        если сегодня уже отмечено) — прошлые дни остаются как были.
      </p>
    </template>
    <template #footer>
      <button v-if="id" class="btn danger" type="button" @click="archive">Убрать рутину</button>
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
.note {
  margin: 0;
  font-size: 13px;
}
</style>
