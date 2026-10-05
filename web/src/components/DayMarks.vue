<script setup lang="ts">
import { computed } from 'vue'
import { tr } from '../app/i18n'
import type { DayMark } from '../domain/routines'

// A routine's last days as a row of squares, oldest first: green done, red missed, grey skipped,
// hollow for today not marked yet, faint for days off.
const props = defineProps<{ marks: DayMark[]; big?: boolean }>()

const label = computed(() => {
  const n = (m: DayMark) => props.marks.filter((x) => x === m).length
  return tr(
    `Последние ${props.marks.length} дн.: сделано ${n('done')}, не сделано ${n('missed')}, пропущено ${n('skipped')}`,
    `Last ${props.marks.length} days: ${n('done')} done, ${n('missed')} missed, ${n('skipped')} skipped`,
  )
})
</script>

<template>
  <span class="marks" :class="{ big }" role="img" :aria-label="label" :title="label">
    <i v-for="(m, i) in marks" :key="i" :class="m" />
  </span>
</template>

<style scoped>
.marks {
  display: inline-flex;
  gap: 2px;
}
i {
  width: 5px;
  height: 5px;
  border-radius: 1.5px;
  background: var(--line);
}
.done {
  background: var(--ok);
}
.missed {
  background: var(--danger);
}
.skipped {
  background: var(--faint);
}
.pending {
  background: none;
  box-shadow: inset 0 0 0 1px var(--faint);
}
.big {
  display: flex;
  gap: 3px;
}
.big i {
  flex: 1;
  width: auto;
  height: auto;
  aspect-ratio: 1;
  max-width: 16px;
  border-radius: 3px;
}
</style>
