<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { fetchServerStatus, type ServerStatus } from './api/health'

const status = ref<ServerStatus | null>(null)

onMounted(async () => {
  status.value = await fetchServerStatus()
})
</script>

<template>
  <main class="app">
    <h1>СДВГ-трекер</h1>
    <p class="status" :data-online="status?.online">
      <template v-if="status === null">Проверяем сервер…</template>
      <template v-else-if="status.online">Сервер на связи · API v{{ status.apiVersion }}</template>
      <template v-else>Сервер недоступен — работаем офлайн</template>
    </p>
  </main>
</template>

<style>
:root {
  --bg: #fbfaff;
  --fg: #1f1d2b;
  --muted: #6b6880;
  --ok: #2f9e6a;
  --warn: #c7771a;
  color-scheme: light dark;
  font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16151d;
    --fg: #ecebf5;
    --muted: #a19eb8;
    --ok: #5fd39a;
    --warn: #f0a94b;
  }
}
body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
}
.app {
  max-width: 640px;
  margin: 0 auto;
  padding: 32px 16px;
}
.status {
  color: var(--muted);
}
.status[data-online='true'] {
  color: var(--ok);
}
.status[data-online='false'] {
  color: var(--warn);
}
</style>
