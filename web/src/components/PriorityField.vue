<script setup lang="ts">
import { priorityTitle } from '../app/format'
import { tr } from '../app/i18n'
import type { Priority } from '../core/types'

const priority = defineModel<Priority>({ required: true })

const CHOICES: { id: Priority; mark: string }[] = [
  { id: 'low', mark: '↓' },
  { id: 'normal', mark: '' },
  { id: 'high', mark: '!!' },
]
</script>

<template>
  <div class="field">
    <span>{{ tr('Приоритет', 'Priority') }}</span>
    <div class="chips">
      <button
        v-for="c in CHOICES"
        :key="c.id"
        type="button"
        class="chip"
        :class="c.id"
        :aria-pressed="priority === c.id"
        @click="priority = c.id"
      >
        {{ [c.mark, priorityTitle(c.id)].filter(Boolean).join(' ') }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.chip.high[aria-pressed='true'] {
  background: var(--accent);
  color: #fff;
}
</style>
