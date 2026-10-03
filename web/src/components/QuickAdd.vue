<script setup lang="ts">
import { ref, watch } from 'vue'
import { useApp } from '../app/context'
import { tr } from '../app/i18n'
import { createTask, type NewTask } from '../db/actions'
import type { TitleSuggestion } from '../domain/suggest'
import { autoEmoji } from '../sync/emoji'
import TitleInput from './TitleInput.vue'

type Look = Pick<NewTask, 'emoji' | 'color' | 'duration_min'>

const props = defineProps<{ date: string | null; placeholder?: string }>()
const { store, openTask } = useApp()
const title = ref('')
const input = ref<InstanceType<typeof TitleInput>>()
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
  if (!t || !input.value?.confirm(t)) return
  const extra = look
  title.value = ''
  const id = await createTask(store, { title: t, date: props.date, ...extra })
  if (!extra.emoji) void autoEmoji(store, id, t)
}

/** A suggestion is added right away, looking like the last time; if it was done today, it waits in the input. */
async function pick(s: TitleSuggestion) {
  fill(s)
  await add()
}

function fill(s: TitleSuggestion) {
  title.value = s.title
  look = lookOf(s)
}
</script>

<template>
  <div class="quick">
    <TitleInput
      ref="input"
      v-model="title"
      :placeholder="placeholder ?? tr('Добавить задачу и нажать Enter', 'Add a task and press Enter')"
      :aria-label="tr('Новая задача', 'New task')"
      fill-button
      @enter="add"
      @pick="pick"
      @fill="fill"
    />
    <button
      class="btn"
      type="button"
      :title="tr('Подробнее', 'More details')"
      @click="openTask(null, { title, date, ...look })"
    >
      ＋
    </button>
  </div>
</template>

<style scoped>
.quick {
  display: flex;
  align-items: flex-start;
  gap: 6px;
}
.quick > .btn {
  padding: 10px 12px;
}
.quick :deep(.input) {
  padding: 10px 12px;
}
</style>
