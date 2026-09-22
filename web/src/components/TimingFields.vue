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
  <div class="row">
    <label v-if="kind === 'exact'" class="field">
      <span>Время</span>
      <input v-model="time" class="input" type="time" required />
    </label>
    <label class="field">
      <span>Длительность, мин</span>
      <input
        class="input"
        type="number"
        min="1"
        max="1440"
        step="5"
        :value="duration ?? ''"
        placeholder="—"
        @input="duration = Number(($event.target as HTMLInputElement).value) || null"
      />
    </label>
  </div>
</template>

<style scoped>
.row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 10px;
}
</style>
