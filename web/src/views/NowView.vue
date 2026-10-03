<script setup lang="ts">
import { computed } from 'vue'
import { useApp } from '../app/context'
import { dayTitle, shortDate } from '../app/format'
import { tr, trn, trWord } from '../app/i18n'
import { rowEnter, rowLeave } from '../app/listMotion'
import { useLive } from '../app/useLive'
import { loadDay, loadStats, pickNow, type DayView, type StatsView } from '../app/views'
import DayCountdown from '../components/DayCountdown.vue'
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

const THINGS: [[string, string, string], [string, string]] = [
  ['дело', 'дела', 'дел'],
  ['thing', 'things'],
]
</script>

<template>
  <section class="now">
    <header class="head">
      <div>
        <h1>{{ tr('Сейчас', 'Now') }}</h1>
        <p class="muted">{{ title.subtitle }}</p>
      </div>
      <DayCountdown />
    </header>

    <p v-if="syncStatus.state === 'unconfigured'" class="banner">
      {{ tr('Данные пока хранятся только в этом браузере.', 'For now, your data lives only in this browser.') }}
      <RouterLink to="/settings/sync">{{ tr('Подключить сервер', 'Connect a server') }}</RouterLink
      >{{ tr(', чтобы синхронизировать с телефоном.', ' to sync with your phone.') }}
    </p>

    <div class="stats">
      <div class="stat card">
        <span class="big">🔥 {{ stats?.streak ?? '—' }}</span>
        <span class="muted">{{
          tr(
            `${trWord(stats?.streak ?? 0, ['день', 'дня', 'дней'], ['day', 'days'])} подряд`,
            `${trWord(stats?.streak ?? 0, ['день', 'дня', 'дней'], ['day', 'days'])} in a row`,
          )
        }}</span>
      </div>
      <div class="stat card">
        <span class="big">{{ day?.done ?? 0 }}<small>/{{ day?.total ?? 0 }}</small></span>
        <span class="muted">{{ tr('сегодня', 'today') }}</span>
        <span class="bar"><span :style="{ width: `${progress}%` }" /></span>
      </div>
      <div class="stat card">
        <span class="big">{{ stats?.totalDone ?? 0 }}</span>
        <span class="muted">{{ tr('всего сделано', 'done in total') }}</span>
      </div>
    </div>

    <div v-if="record?.best_date" class="record card" :class="{ broken: record.broken }">
      <span class="cup" aria-hidden="true">🏆</span>
      <div v-if="record.broken">
        <b>{{
          tr(
            `Новый рекорд: ${trn(record.today_done, ...THINGS)} за день`,
            `New record: ${trn(record.today_done, ...THINGS)} in a day`,
          )
        }}</b>
        <span class="muted">
          {{ tr('Прежний', 'Previous') }} — {{ record.best_done }}, {{ shortDate(record.best_date) }}
        </span>
      </div>
      <div v-else>
        <b>{{
          tr(`Рекорд: ${trn(record.best_done, ...THINGS)} за день`, `Record: ${trn(record.best_done, ...THINGS)} in a day`)
        }}</b>
        <span class="muted">
          {{ shortDate(record.best_date) }} ·
          {{
            tr(
              `чтобы побить, сделайте сегодня ещё ${record.to_beat}`,
              `do ${record.to_beat} more today to beat it`,
            )
          }}
        </span>
      </div>
      <span v-if="!record.broken" class="bar">
        <span :style="{ width: `${(record.today_done / (record.best_done + 1)) * 100}%` }" />
      </span>
    </div>

    <h2 class="section-title">{{ tr('Главное сейчас', 'Up next') }}</h2>
    <TransitionGroup v-if="top.length" tag="ul" name="row" class="list" :css="false" @enter="rowEnter" @leave="rowLeave">
      <ItemRow v-for="item in top" :key="item.key" :item="item" reasons />
    </TransitionGroup>
    <p v-else-if="day && day.total" class="empty card">
      {{ tr('Всё на сегодня сделано 🎉', 'All done for today 🎉') }}<br />
      <span class="muted">{{ tr('Можно отдохнуть или заглянуть во входящие.', 'Take a break, or peek into your inbox.') }}</span>
    </p>
    <p v-else-if="day" class="empty card">
      {{ tr('На сегодня пока ничего нет.', 'Nothing for today yet.') }}<br />
      <span class="muted">{{ tr('Добавьте задачу ниже или заведите рутины.', 'Add a task below or set up some routines.') }}</span>
    </p>
    <div class="more">
      <RouterLink to="/day">{{ tr('Весь день →', 'Whole day →') }}</RouterLink>
      <span v-if="left" class="muted">{{ tr(`ещё ${trn(left, ...THINGS)}`, `${trn(left, ...THINGS)} to go`) }}</span>
    </div>

    <QuickAdd :date="today" />

    <h2 class="section-title">{{ tr('Активность', 'Activity') }}</h2>
    <div class="card heat">
      <Heatmap v-if="stats" :cells="stats.heatmap" />
    </div>
  </section>
</template>

<style scoped>
.head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
}
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
