<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { monthLabel, shortDate, weekdayNames } from '../app/format'
import { tr, trn } from '../app/i18n'
import type { HeatCell } from '../app/views'

const props = defineProps<{ cells: HeatCell[] }>()
const router = useRouter()

const weeks = computed(() => {
  const out: HeatCell[][] = []
  for (let i = 0; i < props.cells.length; i += 7) out.push(props.cells.slice(i, i + 7))
  return out
})

// Month label above the first week that starts in that month.
const months = computed(() =>
  weeks.value.map((w, i) => {
    const m = w[0]!.date.slice(5, 7)
    const prev = i ? weeks.value[i - 1]![0]!.date.slice(5, 7) : ''
    return m !== prev ? monthLabel(w[0]!.date) : ''
  }),
)

const label = (c: HeatCell) =>
  `${shortDate(c.date)}: ${trn(c.count, ['дело', 'дела', 'дел'], ['thing', 'things'])}`
</script>

<template>
  <div class="scroll">
    <div class="grid" role="grid" :aria-label="tr('Активность за год', 'Activity over the year')">
      <div class="months">
        <span v-for="(m, i) in months" :key="i">{{ m }}</span>
      </div>
      <div class="days">
        <span>{{ weekdayNames()[0] }}</span><span></span><span>{{ weekdayNames()[2] }}</span><span></span
        ><span>{{ weekdayNames()[4] }}</span><span></span><span></span>
      </div>
      <div class="weeks">
        <div v-for="(w, i) in weeks" :key="i" class="week">
          <button
            v-for="c in w"
            :key="c.date"
            type="button"
            class="cell"
            :class="`l${c.level}`"
            :title="c.level >= 0 ? label(c) : ''"
            :aria-label="label(c)"
            :disabled="c.level < 0"
            @click="router.push(`/day/${c.date}`)"
          />
        </div>
      </div>
    </div>
  </div>
  <div class="legend muted">
    {{ tr('меньше', 'less') }}
    <span class="cell l0" /><span class="cell l1" /><span class="cell l2" /><span class="cell l3" /><span
      class="cell l4"
    />
    {{ tr('больше', 'more') }}
  </div>
</template>

<style scoped>
/* rtl on the scroller makes it start at the right edge (latest weeks) without measuring */
.scroll {
  overflow-x: auto;
  padding-bottom: 4px;
  direction: rtl;
}
.grid {
  direction: ltr;
  display: grid;
  grid-template-columns: auto 1fr;
  grid-template-rows: auto auto;
  gap: 4px 6px;
  width: max-content;
  font-size: 11px;
  color: var(--muted);
}
.months {
  grid-column: 2;
  display: grid;
  grid-auto-flow: column;
  grid-auto-columns: 14px;
  gap: 3px;
  white-space: nowrap;
}
.days {
  display: grid;
  grid-template-rows: repeat(7, 11px);
  gap: 3px;
  line-height: 11px;
}
.weeks {
  display: flex;
  gap: 3px;
}
.week {
  display: grid;
  grid-template-rows: repeat(7, 11px);
  gap: 3px;
}
.cell {
  display: inline-block;
  width: 14px;
  height: 11px;
  border-radius: 3px;
  border: 0;
  padding: 0;
}
.cell:not(:disabled):hover {
  outline: 2px solid var(--accent);
}
.l-1 {
  background: transparent;
  cursor: default;
}
.l0 {
  background: var(--heat0);
}
.l1 {
  background: var(--heat1);
}
.l2 {
  background: var(--heat2);
}
.l3 {
  background: var(--heat3);
}
.l4 {
  background: var(--heat4);
}
.legend {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 3px;
  font-size: 11px;
  margin-top: 6px;
}
</style>
