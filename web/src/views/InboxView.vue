<script setup lang="ts">
import { useApp } from '../app/context'
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
    <h1>Входящие</h1>
    <p class="muted intro">Всё, что пока без дня. Когда будете готовы — отправьте на сегодня или завтра.</p>
    <QuickAdd :date="null" placeholder="Записать мысль или задачу…" />

    <ul v-if="items.length" class="list">
      <li v-for="item in items" :key="item.key" class="row card">
        <button class="main" type="button" @click="openTask(item.id)">
          <EmojiCircle :emoji="item.emoji" :color="item.color" :size="34" />
          <span>{{ item.title }}</span>
        </button>
        <button class="btn" type="button" @click="plan(item.id, today)">Сегодня</button>
        <button class="btn" type="button" @click="plan(item.id, addDays(today, 1))">Завтра</button>
      </li>
    </ul>
    <p v-else class="empty">Входящие пусты ✨</p>
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
</style>
