<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useApp } from '../app/context'
import { lang, tr } from '../app/i18n'
import { useLive } from '../app/useLive'
import { connectServer, syncStateText, type ConnectResult } from '../app/connect'
import { loadSyncConfig } from '../sync/client'

const { store, sync, syncStatus } = useApp()

const conn = reactive({ baseUrl: '', token: '' })
const check = ref<'idle' | 'checking' | ConnectResult>('idle')
const outbox = useLive(() => store.db.outbox.count(), 0)
const rejected = useLive(() => store.db.rejected.count(), 0)

onMounted(async () => {
  const cfg = await loadSyncConfig(store)
  if (cfg) Object.assign(conn, cfg)
})

async function connect() {
  check.value = 'checking'
  check.value = await connectServer(store, sync, conn.baseUrl, conn.token)
}
</script>

<template>
  <section class="settings">
    <RouterLink to="/settings" class="back">‹ {{ tr('Настройки', 'Settings') }}</RouterLink>
    <h1>{{ tr('Синхронизация', 'Sync') }}</h1>

    <div class="card block">
      <h2>{{ tr('Сервер', 'Server') }}</h2>
      <p class="muted">
        {{
          tr(
            'Приложение работает и без сервера. Сервер нужен, чтобы данные были одинаковыми на телефоне и в браузере.',
            'The app works without a server too. A server keeps your data the same on your phone and in the browser.',
          )
        }}
        {{ tr('Токен — значение', 'The token is the') }} <code>API_TOKEN</code>
        {{ tr('из файла', 'value from the') }} <code>.env</code>{{ tr('.', ' file.') }}
      </p>
      <label class="field">
        <span>{{ tr('Адрес сервера (пусто — этот же сайт)', 'Server address (empty means this site)') }}</span>
        <input v-model="conn.baseUrl" class="input" placeholder="http://192.168.1.10:8420" />
      </label>
      <label class="field">
        <span>{{ tr('Токен', 'Token') }}</span>
        <input v-model="conn.token" class="input" type="password" autocomplete="off" />
      </label>
      <div class="actions">
        <button class="btn primary" type="button" :disabled="!conn.token || check === 'checking'" @click="connect">
          {{ tr('Подключить', 'Connect') }}
        </button>
        <span v-if="check === 'ok'" class="ok">{{ tr('Подключено ✓', 'Connected ✓') }}</span>
        <span v-else-if="check === 'bad-token'" class="bad">{{ tr('Неверный токен', 'Wrong token') }}</span>
        <span v-else-if="check === 'offline'" class="bad">{{ tr('Сервер не отвечает', 'Server isn’t responding') }}</span>
      </div>
    </div>

    <div class="card block">
      <h2>{{ tr('Состояние', 'Status') }}</h2>
      <dl class="status">
        <dt>{{ tr('Состояние', 'Status') }}</dt>
        <dd>{{ syncStateText(syncStatus.state) }}</dd>
        <dt>{{ tr('Последняя синхронизация', 'Last sync') }}</dt>
        <dd>{{ syncStatus.lastSyncAt ? new Date(syncStatus.lastSyncAt).toLocaleString(lang) : '—' }}</dd>
        <dt>{{ tr('Ждут отправки', 'Waiting to send') }}</dt>
        <dd>{{ outbox }}</dd>
        <template v-if="rejected">
          <dt>{{ tr('Отклонены сервером', 'Rejected by the server') }}</dt>
          <dd class="bad">{{ rejected }}</dd>
        </template>
      </dl>
      <div class="actions">
        <button class="btn" type="button" @click="sync.sync()">{{ tr('Синхронизировать сейчас', 'Sync now') }}</button>
      </div>
    </div>
  </section>
</template>

<style scoped>
.settings {
  display: grid;
  gap: 14px;
}
.back {
  justify-self: start;
  font-weight: 550;
}
h1 {
  font-size: 26px;
}
.block {
  display: grid;
  gap: 12px;
  padding: 16px;
}
.block h2 {
  font-size: 17px;
}
.block p {
  margin: 0;
  font-size: 14px;
}
.actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}
.status {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 4px 12px;
  margin: 0;
  font-size: 14px;
}
.status dt {
  color: var(--muted);
}
.status dd {
  margin: 0;
}
.ok {
  color: var(--ok);
  font-weight: 600;
}
.bad {
  color: var(--danger);
  font-weight: 600;
}
code {
  background: var(--surface-2);
  border-radius: 5px;
  padding: 0 4px;
}
</style>
