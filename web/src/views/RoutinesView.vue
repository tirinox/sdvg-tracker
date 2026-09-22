<script setup lang="ts">
import { computed } from 'vue'
import { useApp } from '../app/context'
import { SECTION_TITLES, plural, shortDate, timingLabel, weekdaysLabel } from '../app/format'
import { useLive } from '../app/useLive'
import { SECTIONS, loadRoutines, type RoutineListItem } from '../app/views'
import EmojiCircle from '../components/EmojiCircle.vue'

const { store, today, openRoutine } = useApp()
const routines = useLive<RoutineListItem[]>(() => loadRoutines(store, today.value), [], [today])

const sections = computed(() =>
  SECTIONS.map((s) => ({
    id: s,
    title: SECTION_TITLES[s],
    items: routines.value.filter((r) => r.section === s),
  })).filter((s) => s.items.length),
)
</script>

<template>
  <section>
    <header class="head">
      <h1>Рутины</h1>
      <button class="btn primary" type="button" @click="openRoutine(null)">＋ Добавить</button>
    </header>
    <p class="muted intro">
      {{ routines.length }} {{ plural(routines.length, 'регулярная задача', 'регулярные задачи', 'регулярных задач') }}.
      Они повторяются по расписанию и не переносятся.
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
                <span v-if="r.pendingFrom" class="pending">изменения с {{ shortDate(r.pendingFrom) }}</span>
              </span>
            </span>
          </button>
        </li>
      </ul>
    </template>
    <p v-if="!routines.length" class="empty">Пока нет регулярных задач.</p>
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
</style>
