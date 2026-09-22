<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useApp } from '../app/context'
import { useLive } from '../app/useLive'
import { updateSettings } from '../db/actions'
import { clearDemo, generateDemo } from '../demo/demo'
import { connectServer, type ConnectResult } from '../app/connect'
import { loadSyncConfig } from '../sync/client'

const { store, sync, syncStatus, settings, today, now } = useApp()

const conn = reactive({ baseUrl: '', token: '' })
const check = ref<'idle' | 'checking' | ConnectResult>('idle')
const busy = ref('')
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

const STATE_TEXT: Record<string, string> = {
  idle: 'синхронизировано',
  syncing: 'синхронизация…',
  offline: 'сервер недоступен — работаем офлайн',
  unauthorized: 'неверный токен',
  unconfigured: 'сервер не подключён',
  error: 'ошибка',
}

async function setNumber(key: keyof typeof settings.value, value: string) {
  const n = Number(value)
  if (Number.isInteger(n)) await updateSettings(store, { [key]: n })
}

async function run(label: string, fn: () => Promise<unknown>) {
  busy.value = label
  try {
    await fn()
  } finally {
    busy.value = ''
  }
}

const fillDemo = () =>
  confirm('Добавить демо-данные: ~24 рутины, ~40 задач и историю за 4 месяца?') &&
  run('demo', () => generateDemo(store, today.value, now.value))
const removeDemo = () =>
  confirm('Удалить все демо-данные? Ваши собственные задачи останутся.') &&
  run('clear', () => clearDemo(store))
</script>

<template>
  <section class="settings">
    <h1>Настройки</h1>

    <div class="card block">
      <h2>Синхронизация</h2>
      <p class="muted">
        Приложение работает и без сервера. Сервер нужен, чтобы данные были одинаковыми на телефоне и в
        браузере. Токен — значение <code>API_TOKEN</code> из файла <code>.env</code>.
      </p>
      <label class="field">
        <span>Адрес сервера (пусто — этот же сайт)</span>
        <input v-model="conn.baseUrl" class="input" placeholder="http://192.168.1.10:8420" />
      </label>
      <label class="field">
        <span>Токен</span>
        <input v-model="conn.token" class="input" type="password" autocomplete="off" />
      </label>
      <div class="actions">
        <button class="btn primary" type="button" :disabled="!conn.token || check === 'checking'" @click="connect">
          Подключить
        </button>
        <span v-if="check === 'ok'" class="ok">Подключено ✓</span>
        <span v-else-if="check === 'bad-token'" class="bad">Неверный токен</span>
        <span v-else-if="check === 'offline'" class="bad">Сервер не отвечает</span>
      </div>
      <dl class="status">
        <dt>Состояние</dt>
        <dd>{{ STATE_TEXT[syncStatus.state] }}</dd>
        <dt>Последняя синхронизация</dt>
        <dd>{{ syncStatus.lastSyncAt ? new Date(syncStatus.lastSyncAt).toLocaleString('ru') : '—' }}</dd>
        <dt>Ждут отправки</dt>
        <dd>{{ outbox }}</dd>
        <template v-if="rejected">
          <dt>Отклонены сервером</dt>
          <dd class="bad">{{ rejected }}</dd>
        </template>
      </dl>
      <button class="btn" type="button" @click="sync.sync()">Синхронизировать сейчас</button>
    </div>

    <div class="card block">
      <h2>День</h2>
      <div class="grid">
        <label class="field">
          <span>День начинается в (ч)</span>
          <input
            class="input"
            type="number"
            min="0"
            max="12"
            :value="settings.day_start_hour"
            @change="setNumber('day_start_hour', ($event.target as HTMLInputElement).value)"
          />
        </label>
        <label class="field">
          <span>Утро с (ч)</span>
          <input
            class="input"
            type="number"
            min="0"
            max="23"
            :value="settings.part_morning_from"
            @change="setNumber('part_morning_from', ($event.target as HTMLInputElement).value)"
          />
        </label>
        <label class="field">
          <span>День с (ч)</span>
          <input
            class="input"
            type="number"
            min="0"
            max="23"
            :value="settings.part_day_from"
            @change="setNumber('part_day_from', ($event.target as HTMLInputElement).value)"
          />
        </label>
        <label class="field">
          <span>Вечер с (ч)</span>
          <input
            class="input"
            type="number"
            min="0"
            max="23"
            :value="settings.part_evening_from"
            @change="setNumber('part_evening_from', ($event.target as HTMLInputElement).value)"
          />
        </label>
        <label class="field">
          <span>Стрик: минимум дел в день</span>
          <input
            class="input"
            type="number"
            min="1"
            :value="settings.streak_min_done"
            @change="setNumber('streak_min_done', ($event.target as HTMLInputElement).value)"
          />
        </label>
      </div>
      <p class="muted">После полуночи и до начала дня всё ещё считается «вчера» и «вечер».</p>
    </div>

    <div class="card block">
      <h2>Демо-данные</h2>
      <p class="muted">
        Чтобы посмотреть приложение в деле. Демо-данные отмечены особыми ID и удаляются одной кнопкой на
        всех устройствах — ваши задачи не пострадают.
      </p>
      <div class="actions">
        <button class="btn" type="button" :disabled="!!busy" @click="fillDemo">
          {{ busy === 'demo' ? 'Заполняю…' : 'Заполнить демо-данными' }}
        </button>
        <button class="btn danger" type="button" :disabled="!!busy" @click="removeDemo">
          {{ busy === 'clear' ? 'Удаляю…' : 'Удалить демо-данные' }}
        </button>
      </div>
    </div>
  </section>
</template>

<style scoped>
.settings {
  display: grid;
  gap: 14px;
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
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
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
