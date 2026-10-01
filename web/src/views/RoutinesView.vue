<script setup lang="ts">
import { computed } from 'vue'
import { useApp } from '../app/context'
import { adherenceLabel, sectionTitle, shortDate, timingLabel, weekdaysLabel } from '../app/format'
import { tr, trn } from '../app/i18n'
import { useLive } from '../app/useLive'
import { SECTIONS, loadRoutines, type RoutineListItem } from '../app/views'
import EmojiCircle from '../components/EmojiCircle.vue'

const { store, today, settings, openRoutine } = useApp()
const routines = useLive<RoutineListItem[]>(() => loadRoutines(store, today.value), [], [today])

const sections = computed(() =>
  SECTIONS.map((s) => ({
    id: s,
    title: sectionTitle(s),
    items: routines.value.filter((r) => r.section === s),
  })).filter((s) => s.items.length),
)
const lagging = computed(() => routines.value.filter((r) => r.adherence.warning).length)
</script>

<template>
  <section>
    <header class="head">
      <h1>{{ tr('Рутины', 'Routines') }}</h1>
      <button class="btn primary" type="button" @click="openRoutine(null)">{{ tr('＋ Добавить', '＋ Add') }}</button>
    </header>
    <p class="muted intro">
      {{ trn(routines.length, ['регулярная задача', 'регулярные задачи', 'регулярных задач'], ['routine', 'routines']) }}.
      {{ tr('Они повторяются по расписанию и не переносятся.', 'They repeat on a schedule and never get moved.') }}
    </p>
    <p v-if="lagging" class="lagging-note">
      ⚠︎
      {{
        trn(
          lagging,
          ['рутина пропускается', 'рутины пропускаются', 'рутин пропускаются'],
          ['routine is being skipped', 'routines are being skipped'],
        )
      }}:
      {{
        tr(
          `за последние 30 дней сделано меньше ${settings.routine_warn_below}\u00a0%.`,
          `done less than ${settings.routine_warn_below}% of the time over the last 30 days.`,
        )
      }}
    </p>

    <template v-for="s in sections" :key="s.id">
      <h2 class="section-title">{{ s.title }}</h2>
      <ul class="list">
        <li v-for="r in s.items" :key="r.id">
          <button class="row card" type="button" @click="openRoutine(r.id)">
            <EmojiCircle :emoji="r.version.emoji" :color="r.version.color" :size="36" />
            <span class="text">
              <span class="title">{{ r.version.title }}</span>
              <span class="meta muted">
                {{ [timingLabel(r.version), weekdaysLabel(r.version.weekdays)].filter(Boolean).join(' · ') }}
                <span v-if="r.pendingFrom" class="pending">{{
                  tr(`изменения с ${shortDate(r.pendingFrom)}`, `changes from ${shortDate(r.pendingFrom)}`)
                }}</span>
              </span>
            </span>
            <span
              v-if="r.adherence.percent !== null"
              class="rate"
              :class="{ warn: r.adherence.warning }"
              :title="adherenceLabel(r.adherence)"
            >
              <template v-if="r.adherence.warning">⚠︎ </template>{{ r.adherence.percent }}{{ tr('\u00a0%', '%') }}
            </span>
          </button>
        </li>
      </ul>
    </template>
    <p v-if="!routines.length" class="empty">{{ tr('Пока нет регулярных задач.', 'No routines yet.') }}</p>
  </section>
</template>

<style scoped>
.head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
h1 {
  font-size: 26px;
}
.intro {
  margin: 4px 0 0;
}
.list {
  display: grid;
  gap: 6px;
  padding: 0;
  margin: 0;
  list-style: none;
}
.row {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 10px;
  text-align: left;
}
.row:hover {
  background: var(--surface-2);
}
.text {
  flex: 1;
  display: grid;
  gap: 1px;
}
.title {
  font-weight: 550;
}
.meta {
  font-size: 13px;
}
.pending {
  margin-left: 6px;
  color: var(--accent);
  font-weight: 600;
}
.rate {
  flex-shrink: 0;
  font-size: 13px;
  font-weight: 600;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
}
.rate.warn {
  border-radius: 6px;
  padding: 0 6px;
  line-height: 20px;
  background: var(--warn-soft);
  color: var(--warn);
}
.lagging-note {
  margin: 8px 0 0;
  font-size: 14px;
  font-weight: 600;
  color: var(--warn);
}
</style>
