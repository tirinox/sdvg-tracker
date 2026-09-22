<script setup lang="ts">
import { ref } from 'vue'
import { useApp } from '../app/context'
import { connectServer, skipOnboarding, type ConnectResult } from '../app/connect'
import Modal from './Modal.vue'

const emit = defineEmits<{ close: [] }>()
const { store, sync } = useApp()

const token = ref('')
const baseUrl = ref('')
const state = ref<'idle' | 'checking' | ConnectResult>('idle')

async function connect() {
  state.value = 'checking'
  state.value = await connectServer(store, sync, baseUrl.value, token.value)
  if (state.value === 'ok') setTimeout(() => emit('close'), 900)
}

async function later() {
  await skipOnboarding(store)
  emit('close')
}
</script>

<template>
  <Modal title="Добро пожаловать 👋" @close="emit('close')">
    <p class="lead">
      Трекер работает и без сети — всё хранится на этом устройстве. Чтобы задачи были одинаковыми на
      телефоне и компьютере, подключите свой сервер.
    </p>
    <label class="field">
      <span>Токен сервера — значение <code>API_TOKEN</code> из файла <code>.env</code></span>
      <input
        v-model="token"
        class="input"
        type="password"
        autocomplete="off"
        placeholder="Вставьте токен"
        @keydown.enter="connect"
      />
    </label>
    <details>
      <summary class="muted">Сервер на другом адресе</summary>
      <label class="field">
        <span>Адрес (пусто — этот же сайт)</span>
        <input v-model="baseUrl" class="input" placeholder="http://192.168.1.10:8420" />
      </label>
    </details>
    <p v-if="state === 'ok'" class="ok">Подключено ✓ Загружаем ваши задачи…</p>
    <p v-else-if="state === 'bad-token'" class="bad">Неверный токен — проверьте значение в .env.</p>
    <p v-else-if="state === 'offline'" class="bad">Сервер не отвечает. Он запущен? (<code>make up</code>)</p>

    <template #footer>
      <button class="btn ghost" type="button" @click="later">Пока без сервера</button>
      <button
        class="btn primary"
        type="button"
        :disabled="!token.trim() || state === 'checking'"
        @click="connect"
      >
        {{ state === 'checking' ? 'Проверяю…' : 'Подключить' }}
      </button>
    </template>
  </Modal>
</template>

<style scoped>
.lead {
  margin: 0;
  font-size: 15px;
}
details summary {
  cursor: pointer;
  font-size: 14px;
  margin-bottom: 8px;
}
.ok,
.bad {
  margin: 0;
  font-weight: 600;
  font-size: 14px;
}
.ok {
  color: var(--ok);
}
.bad {
  color: var(--danger);
}
code {
  background: var(--surface-2);
  border-radius: 5px;
  padding: 0 4px;
}
</style>
