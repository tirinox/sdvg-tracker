<script setup lang="ts">
import type { PartOfDay, TimeKind } from '../core/types'

const kind = defineModel<TimeKind>('kind', { required: true })
const part = defineModel<PartOfDay | null>('part', { required: true })
const time = defineModel<string | null>('time', { required: true })
const duration = defineModel<number | null>('duration', { required: true })

type Choice = { label: string; kind: TimeKind; part?: PartOfDay }
const CHOICES: Choice[] = [
  { label: 'В любое время', kind: 'none' },
  { label: '🌅 Утро', kind: 'part', part: 'morning' },
  { label: '☀️ День', kind: 'part', part: 'day' },
  { label: '🌙 Вечер', kind: 'part', part: 'evening' },
  { label: '⏰ Точное время', kind: 'exact' },
]

const DURATIONS = [
  { min: 5, label: '5 мин' },
  { min: 10, label: '10 мин' },
  { min: 15, label: '15 мин' },
  { min: 30, label: '30 мин' },
  { min: 60, label: '1 ч' },
  { min: 120, label: '2 ч' },
  { min: 180, label: '3 ч' },
]

/** Tapping the selected duration again clears it. */
const pickDuration = (min: number) => (duration.value = duration.value === min ? null : min)

const selected = (c: Choice) => c.kind === kind.value && (c.kind !== 'part' || c.part === part.value)

function pick(c: Choice) {
  kind.value = c.kind
  if (c.part) part.value = c.part
  if (c.kind === 'exact' && !time.value) time.value = '09:00'
}
</script>

<template>
  <div class="field">
    <span>Когда</span>
    <div class="chips">
      <button
        v-for="c in CHOICES"
        :key="c.label"
        type="button"
        class="chip"
        :aria-pressed="selected(c)"
        @click="pick(c)"
      >
        {{ c.label }}
      </button>
    </div>
  </div>
  <label v-if="kind === 'exact'" class="field">
    <span>Время</span>
    <input v-model="time" class="input time" type="time" required />
  </label>
  <div class="field">
    <span>Длительность</span>
    <div class="chips">
      <button
        v-for="d in DURATIONS"
        :key="d.min"
        type="button"
        class="chip"
        :aria-pressed="duration === d.min"
        @click="pickDuration(d.min)"
      >
        {{ d.label }}
      </button>
      <input
        class="input custom"
        type="number"
        min="1"
        max="1440"
        :value="duration ?? ''"
        placeholder="мин"
        aria-label="Своя длительность в минутах"
        @input="duration = Number(($event.target as HTMLInputElement).value) || null"
      />
    </div>
  </div>
</template>

<style scoped>
.time {
  width: auto;
}
.custom {
  width: 78px;
  padding: 4px 8px;
  border-radius: 999px;
}
</style>
