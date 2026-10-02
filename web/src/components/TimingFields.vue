<script setup lang="ts">
import { durationLabel, partTitle, sectionTitle } from '../app/format'
import { tr } from '../app/i18n'
import type { PartOfDay, TimeKind } from '../core/types'

const kind = defineModel<TimeKind>('kind', { required: true })
const part = defineModel<PartOfDay | null>('part', { required: true })
const time = defineModel<string | null>('time', { required: true })
const duration = defineModel<number | null>('duration', { required: true })

/** Labels are functions so they follow the interface language. */
type Choice = { id: string; label: () => string; kind: TimeKind; part?: PartOfDay }
const CHOICES: Choice[] = [
  { id: 'none', label: () => sectionTitle('anytime'), kind: 'none' },
  { id: 'morning', label: () => `🌅 ${partTitle('morning')}`, kind: 'part', part: 'morning' },
  { id: 'day', label: () => `☀️ ${partTitle('day')}`, kind: 'part', part: 'day' },
  { id: 'evening', label: () => `🌙 ${partTitle('evening')}`, kind: 'part', part: 'evening' },
  { id: 'exact', label: () => tr('⏰ Точное время', '⏰ Exact time'), kind: 'exact' },
]

const DURATIONS = [5, 10, 15, 30, 60, 120, 180]

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
    <span>{{ tr('Когда', 'When') }}</span>
    <div class="chips">
      <button
        v-for="c in CHOICES"
        :key="c.id"
        type="button"
        class="chip"
        :aria-pressed="selected(c)"
        @click="pick(c)"
      >
        {{ c.label() }}
      </button>
    </div>
  </div>
  <label v-if="kind === 'exact'" class="field">
    <span>{{ tr('Время', 'Time') }}</span>
    <input v-model="time" class="input time" type="time" required />
  </label>
  <div class="field">
    <span>{{ tr('Длительность', 'Duration') }}</span>
    <div class="chips">
      <button
        v-for="min in DURATIONS"
        :key="min"
        type="button"
        class="chip"
        :aria-pressed="duration === min"
        @click="pickDuration(min)"
      >
        {{ durationLabel(min) }}
      </button>
      <input
        class="input custom"
        type="number"
        min="1"
        max="1440"
        :value="duration ?? ''"
        :placeholder="tr('мин', 'min')"
        :aria-label="tr('Своя длительность в минутах', 'Custom duration in minutes')"
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
