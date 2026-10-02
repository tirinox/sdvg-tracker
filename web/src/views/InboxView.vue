<script setup lang="ts">
import { useApp } from '../app/context'
import { priorityStyle, priorityTag } from '../app/format'
import { tr } from '../app/i18n'
import { useLive } from '../app/useLive'
import { loadInbox, type DayItem } from '../app/views'
import EmojiCircle from '../components/EmojiCircle.vue'
import QuickAdd from '../components/QuickAdd.vue'
import { updateTask } from '../db/actions'
import { addDays } from '../domain/dates'

const { store, now, today, openTask } = useApp()
const items = useLive<DayItem[]>(() => loadInbox(store, now.value), [], [now])

const plan = (id: string, date: string) => updateTask(store, id, { date })
</script>

<template>
  <section>
    <h1>{{ tr('Входящие', 'Inbox') }}</h1>
    <p class="muted intro">
      {{
        tr(
          'Всё, что пока без дня. Когда будете готовы — отправьте на сегодня или завтра.',
          'Everything without a day yet. When you’re ready, send it to today or tomorrow.',
        )
      }}
    </p>
    <QuickAdd :date="null" :placeholder="tr('Записать мысль или задачу…', 'Jot down a thought or a task…')" />

    <ul v-if="items.length" class="list">
      <li
        v-for="item in items"
        :key="item.key"
        class="row card"
        :class="`prio-${item.priority}`"
        :style="item.priority === 'high' ? priorityStyle(item.key, item.color) : undefined"
      >
        <span v-if="item.priority === 'high'" class="prio-fx" aria-hidden="true" />
        <button class="main" type="button" @click="openTask(item.id)">
          <EmojiCircle :emoji="item.emoji" :color="item.color" :size="34" />
          <span class="title">{{ item.title }}</span>
          <span v-if="item.priority === 'high'" class="prio-tag">{{ priorityTag() }}</span>
        </button>
        <button class="btn" type="button" @click="plan(item.id, today)">{{ tr('Сегодня', 'Today') }}</button>
        <button class="btn" type="button" @click="plan(item.id, addDays(today, 1))">{{ tr('Завтра', 'Tomorrow') }}</button>
      </li>
    </ul>
    <p v-else class="empty">{{ tr('Входящие пусты ✨', 'Inbox is empty ✨') }}</p>
  </section>
</template>

<style scoped>
h1 {
  font-size: 26px;
}
.intro {
  margin: 4px 0 14px;
}
.list {
  display: grid;
  gap: 8px;
  padding: 0;
  margin: 14px 0 0;
}
.row {
  position: relative;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px;
  list-style: none;
}
.main {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 10px;
  border: 0;
  background: none;
  text-align: left;
  font-weight: 550;
  min-width: 0;
}
.prio-high {
  border-color: color-mix(in srgb, var(--c) 40%, var(--line));
}
.prio-high .title {
  font-weight: 700;
}
.prio-low .title {
  color: var(--muted);
  font-weight: 450;
}
</style>
