<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApp } from '../app/context'
import { dayDistance, dayTitle, groupTitle, shortDate } from '../app/format'
import { tr } from '../app/i18n'
import { rowEnter, rowLeave } from '../app/listMotion'
import { useLive } from '../app/useLive'
import { dayGroups, loadDay, type DayView } from '../app/views'
import DayCountdown from '../components/DayCountdown.vue'
import ItemRow from '../components/ItemRow.vue'
import QuickAdd from '../components/QuickAdd.vue'
import { addDays } from '../domain/dates'

const route = useRoute()
const router = useRouter()
const { store, now, today, openRoutine } = useApp()

const date = computed(() => (route.params.date as string | undefined) || today.value)
const day = useLive<DayView | null>(() => loadDay(store, date.value, now.value), null, [date, now])
const title = computed(() => dayTitle(date.value, today.value))
const isToday = computed(() => date.value === today.value)
const isPast = computed(() => date.value < today.value)
const addPlaceholder = computed(() => {
  if (isToday.value) return undefined
  const day = date.value === addDays(today.value, 1) ? tr('завтра', 'tomorrow') : shortDate(date.value)
  return tr(`Добавить задачу на ${day}`, `Add a task for ${day}`)
})

// One flat list of headers and rows: a row that gets done slides down into "Сделано", and a part
// of the day left empty folds its header away, instead of rows jumping between separate lists.
const rows = computed(() =>
  dayGroups(day.value?.items ?? []).flatMap((g) => [
    { key: `head:${g.id}`, title: groupTitle(g.id), item: null },
    ...g.items.map((item) => ({ key: item.key, title: null, item })),
  ]),
)

const go = (d: string) => router.push(d === today.value ? '/day' : `/day/${d}`)
</script>

<template>
  <section>
    <!-- Stays in view while scrolling, so nothing is added or checked on another day by mistake. -->
    <div v-if="!isToday" class="not-today" role="status">
      <span><span class="icon" aria-hidden="true">📅</span>{{ tr('Не сегодня', 'Not today') }} — {{ dayDistance(date, today) }}</span>
      <button class="btn" type="button" @click="go(today)">{{ tr('К сегодня', 'Back to today') }}</button>
    </div>
    <header class="head">
      <button class="btn ghost nav" type="button" :aria-label="tr('Предыдущий день', 'Previous day')" @click="go(addDays(date, -1))">‹</button>
      <div class="titles">
        <h1>{{ title.title }}</h1>
        <p class="muted">{{ title.subtitle }}</p>
      </div>
      <button class="btn ghost nav" type="button" :aria-label="tr('Следующий день', 'Next day')" @click="go(addDays(date, 1))">›</button>
    </header>
    <div class="sub">
      <DayCountdown v-if="isToday" />
      <span v-if="day" class="muted">{{
        tr(`Сделано ${day.done} из ${day.total}`, `${day.done} of ${day.total} done`)
      }}</span>
    </div>

    <QuickAdd v-if="!isPast" :date="date" :placeholder="addPlaceholder" />

    <!-- Keyed by the loaded day, so switching days swaps the list instead of animating every row. -->
    <TransitionGroup
      v-if="rows.length"
      :key="day?.date"
      tag="ul"
      name="row"
      class="list"
      :css="false"
      @enter="rowEnter"
      @leave="rowLeave"
    >
      <template v-for="r in rows" :key="r.key">
        <ItemRow v-if="r.item" :item="r.item" :date="date" />
        <li v-else class="group"><h2 class="section-title">{{ r.title }}</h2></li>
      </template>
    </TransitionGroup>

    <p v-if="day && !day.items.length" class="empty">
      {{ tr('На этот день ничего нет.', 'Nothing on this day.') }}
      <button class="btn" type="button" @click="openRoutine(null)">{{ tr('Добавить рутину', 'Add a routine') }}</button>
    </p>
  </section>
</template>

<style scoped>
.not-today {
  position: sticky;
  top: calc(var(--top-h, 0px) + 8px);
  z-index: 4;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
  padding: 6px 6px 6px 14px;
  border: 1px solid color-mix(in srgb, var(--warn) 45%, var(--line));
  border-radius: 12px;
  background: var(--warn-soft);
  color: var(--warn);
  font-weight: 600;
  box-shadow: var(--shadow);
}
.not-today .icon {
  margin-right: 6px;
}
.not-today .btn {
  flex-shrink: 0;
  border-color: color-mix(in srgb, var(--warn) 45%, var(--line));
  color: var(--warn);
}
.head {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 8px;
}
.titles {
  text-align: center;
}
.titles h1 {
  font-size: 24px;
}
.titles p {
  margin: 2px 0 0;
}
.nav {
  font-size: 26px;
  line-height: 1;
  padding: 4px 12px;
}
.sub {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  margin: 10px 0 12px;
  min-height: 34px;
  font-size: 14px;
}
.sub .muted:only-child {
  margin-left: auto;
}
.list {
  display: grid;
  gap: 8px;
  padding: 0;
  margin: 8px 0 0;
}
/* The gap above plus this padding keep the old section spacing; padding, not margin, so the
   header folds away completely when it leaves. */
.group {
  list-style: none;
  padding-top: 10px;
}
.group .section-title {
  margin: 0 4px;
}
</style>
