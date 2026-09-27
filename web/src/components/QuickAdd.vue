<script setup lang="ts">
import { ref, watch } from 'vue'
import { useApp } from '../app/context'
import { createTask, type NewTask } from '../db/actions'
import type { TitleSuggestion } from '../domain/suggest'
import { autoEmoji } from '../sync/emoji'
import TitleInput from './TitleInput.vue'

type Look = Pick<NewTask, 'emoji' | 'color' | 'duration_min'>

const props = defineProps<{ date: string | null; placeholder?: string }>()
const { store, openTask } = useApp()
const title = ref('')
/** Look of a suggestion put into the input with ↖, kept while its title is being edited. */
let look: Look = {}

watch(title, (v) => {
  if (!v.trim()) look = {}
})

function lookOf(s: TitleSuggestion): Look {
  return { emoji: s.emoji, color: s.color, duration_min: s.duration_min }
}

// The input is cleared before the write, so typing the next task right away loses nothing.
async function add() {
  const t = title.value.trim()
  if (!t) return
  const extra = look
  title.value = ''
  const id = await createTask(store, { title: t, date: props.date, ...extra })
  if (!extra.emoji) void autoEmoji(store, id, t)
}

/** A suggestion is added right away, looking like the last time. */
async function pick(s: TitleSuggestion) {
  title.value = ''
  const id = await createTask(store, { title: s.title, date: props.date, ...lookOf(s) })
  if (!s.emoji) void autoEmoji(store, id, s.title)
}

function fill(s: TitleSuggestion) {
  title.value = s.title
  look = lookOf(s)
}
</script>

<template>
  <div class="quick">
    <TitleInput
      v-model="title"
      :placeholder="placeholder ?? 'Добавить задачу и нажать Enter'"
      aria-label="Новая задача"
      fill-button
      @enter="add"
      @pick="pick"
      @fill="fill"
    />
    <button
      class="btn"
      type="button"
      title="Подробнее"
      @click="openTask(null, { title, date, ...look })"
    >
      ＋
    </button>
  </div>
</template>

<style scoped>
.quick {
  display: flex;
  gap: 6px;
}
.quick :deep(.input) {
  padding: 10px 12px;
}
</style>
