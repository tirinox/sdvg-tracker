<script setup lang="ts">
import { computed } from 'vue'
import { useApp } from '../app/context'
import { dayTitle, plural, shortDate } from '../app/format'
import { rowEnter, rowLeave } from '../app/listMotion'
import { useLive } from '../app/useLive'
import { loadDay, loadStats, pickNow, type DayView, type StatsView } from '../app/views'
import Heatmap from '../components/Heatmap.vue'
import ItemRow from '../components/ItemRow.vue'
import QuickAdd from '../components/QuickAdd.vue'

const { store, now, today, syncStatus } = useApp()

const day = useLive<DayView | null>(() => loadDay(store, today.value, now.value), null, [today, now])
const stats = useLive<StatsView | null>(() => loadStats(store, today.value), null, [today])
const top = computed(() => (day.value ? pickNow(day.value) : []))
const title = computed(() => dayTitle(today.value, today.value))
const progress = computed(() =>
  day.value && day.value.total ? Math.round((day.value.done / day.value.total) * 100) : 0,
)
const record = computed(() => stats.value?.record ?? null)
const left = computed(() => (day.value ? day.value.total - day.value.done : 0))
</script>

<template>
  <section class="now">
    <header class="head">
      <div>
        <h1>Сейчас</h1>
        <p class="muted">{{ title.subtitle }}</p>
      </div>
    </header>

    <p v-if="syncStatus.state === 'unconfigured'" class="banner">
      Данные пока хранятся только в этом браузере.
      <RouterLink to="/settings">Подключить сервер</RouterLink>, чтобы синхронизировать с телефоном.
    </p>

    <div class="stats">
      <div class="stat card">
        <span class="big">🔥 {{ stats?.streak ?? '—' }}</span>
        <span class="muted">{{ plural(stats?.streak ?? 0, 'день', 'дня', 'дней') }} подряд</span>
      </div>
      <div class="stat card">
        <span class="big">{{ day?.done ?? 0 }}<small>/{{ day?.total ?? 0 }}</small></span>
        <span class="muted">сегодня</span>
        <span class="bar"><span :style="{ width: `${progress}%` }" /></span>
      </div>
      <div class="stat card">
        <span class="big">{{ stats?.totalDone ?? 0 }}</span>
        <span class="muted">всего сделано</span>
      </div>
    </div>

    <div v-if="record?.best_date" class="record card" :class="{ broken: record.broken }">
      <span class="cup" aria-hidden="true">🏆</span>
      <div v-if="record.broken">
        <b>Новый рекорд: {{ record.today_done }} {{ plural(record.today_done, 'дело', 'дела', 'дел') }} за день</b>
        <span class="muted">
          Прежний — {{ record.best_done }}, {{ shortDate(record.best_date) }}
        </span>
      </div>
      <div v-else>
        <b>Рекорд: {{ record.best_done }} {{ plural(record.best_done, 'дело', 'дела', 'дел') }} за день</b>
        <span class="muted">
          {{ shortDate(record.best_date) }} · чтобы побить, сделайте сегодня ещё {{ record.to_beat }}
        </span>
      </div>
      <span v-if="!record.broken" class="bar">
        <span :style="{ width: `${(record.today_done / (record.best_done + 1)) * 100}%` }" />
      </span>
    </div>

    <h2 class="section-title">Главное сейчас</h2>
    <TransitionGroup v-if="top.length" tag="ul" name="row" class="list" :css="false" @enter="rowEnter" @leave="rowLeave">
      <ItemRow v-for="item in top" :key="item.key" :item="item" reasons />
    </TransitionGroup>
    <p v-else-if="day && day.total" class="empty card">
      Всё на сегодня сделано 🎉<br />
      <span class="muted">Можно отдохнуть или заглянуть во входящие.</span>
    </p>
    <p v-else-if="day" class="empty card">
      На сегодня пока ничего нет.<br />
      <span class="muted">Добавьте задачу ниже или заведите рутины.</span>
    </p>
    <div class="more">
      <RouterLink to="/day">Весь день →</RouterLink>
      <span v-if="left" class="muted">ещё {{ left }} {{ plural(left, 'дело', 'дела', 'дел') }}</span>
    </div>

    <QuickAdd :date="today" />

    <h2 class="section-title">Активность</h2>
    <div class="card heat">
      <Heatmap v-if="stats" :cells="stats.heatmap" />
    </div>
  </section>
</template>

<style scoped>
.head h1 {
  font-size: 26px;
}
.head p {
  margin: 2px 0 0;
}
.banner {
  background: var(--accent-soft);
  border-radius: 12px;
  padding: 10px 12px;
  font-size: 14px;
}
.stats {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
  margin-top: 14px;
}
.stat {
  display: grid;
  gap: 2px;
  padding: 12px;
  font-size: 13px;
}
.big {
  font-size: 22px;
  font-weight: 700;
}
.big small {
  font-size: 14px;
  color: var(--muted);
  font-weight: 500;
}
.bar {
  height: 5px;
  border-radius: 3px;
  background: var(--surface-2);
  overflow: hidden;
  margin-top: 4px;
}
.bar span {
  display: block;
  height: 100%;
  background: var(--ok);
  transition: width 0.3s;
}
.record {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  column-gap: 12px;
  margin-top: 8px;
  padding: 12px;
  font-size: 13px;
}
.record b {
  display: block;
  font-size: 15px;
}
.record .cup {
  font-size: 26px;
}
.record .bar {
  grid-column: 1 / -1;
  margin-top: 8px;
}
.record .bar span {
  background: var(--warn);
}
.record.broken {
  background: var(--warn-soft);
}
.list {
  display: grid;
  gap: 8px;
  padding: 0;
  margin: 0;
}
.more {
  display: flex;
  justify-content: space-between;
  margin: 10px 4px 14px;
  font-size: 14px;
}
.heat {
  padding: 12px;
}
</style>
