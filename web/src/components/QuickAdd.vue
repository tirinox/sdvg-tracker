<script setup lang="ts">
import { ref } from 'vue'
import { useApp } from '../app/context'
import { createTask } from '../db/actions'

const props = defineProps<{ date: string | null; placeholder?: string }>()
const { store, openTask } = useApp()
const title = ref('')

async function add() {
  const t = title.value.trim()
  if (!t) return
  await createTask(store, { title: t, date: props.date })
  title.value = ''
}
</script>

<template>
  <div class="quick">
    <input
      v-model="title"
      class="input"
      :placeholder="placeholder ?? 'Добавить задачу и нажать Enter'"
      aria-label="Новая задача"
      @keydown.enter="add"
    />
    <button class="btn" type="button" title="Подробнее" @click="openTask(null, { title, date })">＋</button>
  </div>
</template>

<style scoped>
.quick {
  display: flex;
  gap: 6px;
}
.quick .input {
  padding: 10px 12px;
}
</style>
