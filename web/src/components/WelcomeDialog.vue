<script setup lang="ts">
import { ref } from 'vue'
import { useApp } from '../app/context'
import { connectServer, skipOnboarding, type ConnectResult } from '../app/connect'
import { tr } from '../app/i18n'
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
  <Modal :title="tr('Добро пожаловать 👋', 'Welcome 👋')" @close="emit('close')">
    <p class="lead">
      {{
        tr(
          'Трекер работает и без сети — всё хранится на этом устройстве. Чтобы задачи были одинаковыми на телефоне и компьютере, подключите свой сервер.',
          'The tracker works offline too — everything is stored on this device. To have the same tasks on your phone and computer, connect your own server.',
        )
      }}
    </p>
    <label class="field">
      <span>
        {{ tr('Токен сервера — значение', 'Server token —') }} <code>API_TOKEN</code>
        {{ tr('из файла', 'from') }} <code>.env</code>
      </span>
      <input
        v-model="token"
        class="input"
        type="password"
        autocomplete="off"
        :placeholder="tr('Вставьте токен', 'Paste the token')"
        @keydown.enter="connect"
      />
    </label>
    <details>
      <summary class="muted">{{ tr('Сервер на другом адресе', 'Server at a different address') }}</summary>
      <label class="field">
        <span>{{ tr('Адрес (пусто — этот же сайт)', 'Address (empty — this same site)') }}</span>
        <input v-model="baseUrl" class="input" placeholder="http://192.168.1.10:8420" />
      </label>
    </details>
    <p v-if="state === 'ok'" class="ok">{{ tr('Подключено ✓ Загружаем ваши задачи…', 'Connected ✓ Loading your tasks…') }}</p>
    <p v-else-if="state === 'bad-token'" class="bad">
      {{ tr('Неверный токен — проверьте значение в .env.', 'Wrong token — check the value in .env.') }}
    </p>
    <p v-else-if="state === 'offline'" class="bad">
      {{ tr('Сервер не отвечает. Он запущен?', 'The server isn’t responding. Is it running?') }} (<code>make up</code>)
    </p>

    <template #footer>
      <button class="btn ghost" type="button" @click="later">{{ tr('Пока без сервера', 'No server for now') }}</button>
      <button
        class="btn primary"
        type="button"
        :disabled="!token.trim() || state === 'checking'"
        @click="connect"
      >
        {{ state === 'checking' ? tr('Проверяю…', 'Checking…') : tr('Подключить', 'Connect') }}
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
