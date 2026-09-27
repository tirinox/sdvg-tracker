<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApp } from '../app/context'
import { GROUP_TITLES, dayTitle } from '../app/format'
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
const isPast = computed(() => date.value < today.value)

// One flat list of headers and rows: a row that gets done slides down into "Сделано", and a part
// of the day left empty folds its header away, instead of rows jumping between separate lists.
const rows = computed(() =>
  dayGroups(day.value?.items ?? []).flatMap((g) => [
    { key: `head:${g.id}`, title: GROUP_TITLES[g.id], item: null },
    ...g.items.map((item) => ({ key: item.key, title: null, item })),
  ]),
)

const go = (d: string) => router.push(d === today.value ? '/day' : `/day/${d}`)
</script>

<template>
  <section>
    <header class="head">
      <button class="btn ghost nav" type="button" aria-label="Предыдущий день" @click="go(addDays(date, -1))">‹</button>
      <div class="titles">
        <h1>{{ title.title }}</h1>
        <p class="muted">{{ title.subtitle }}</p>
      </div>
      <button class="btn ghost nav" type="button" aria-label="Следующий день" @click="go(addDays(date, 1))">›</button>
    </header>
    <div class="sub">
      <button v-if="date !== today" class="btn" type="button" @click="go(today)">К сегодняшнему дню</button>
      <DayCountdown v-else />
      <span v-if="day" class="muted">Сделано {{ day.done }} из {{ day.total }}</span>
    </div>

    <QuickAdd v-if="!isPast" :date="date" />

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
      На этот день ничего нет.
      <button class="btn" type="button" @click="openRoutine(null)">Добавить рутину</button>
    </p>
  </section>
</template>

<style scoped>
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
