<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useApp } from '../app/context'
import { lang, langPref, setLangPref, tr, type LangPref } from '../app/i18n'
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

const LANGS = (): { id: LangPref; label: string }[] => [
  { id: 'system', label: tr('Как в системе', 'System default') },
  { id: 'ru', label: 'Русский' },
  { id: 'en', label: 'English' },
]

function stateText(state: string): string {
  const texts: Record<string, string> = {
    idle: tr('синхронизировано', 'synced'),
    syncing: tr('синхронизация…', 'syncing…'),
    offline: tr('сервер недоступен — работаем офлайн', 'server unreachable — working offline'),
    unauthorized: tr('неверный токен', 'wrong token'),
    unconfigured: tr('сервер не подключён', 'no server connected'),
    server_changed: tr('на паузе: данные на сервере сменились', 'paused: the data on the server changed'),
    error: tr('ошибка', 'error'),
  }
  return texts[state] ?? ''
}

async function setNumber(key: keyof typeof settings.value, value: string) {
  const n = Number(value)
  if (Number.isInteger(n)) await updateSettings(store, { [key]: n })
}

async function setPercent(key: keyof typeof settings.value, value: string) {
  const n = Number(value)
  if (Number.isInteger(n)) await updateSettings(store, { [key]: Math.min(100, Math.max(0, n)) })
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
  confirm(
    tr(
      'Добавить демо-данные: ~24 рутины, ~40 задач и историю за 4 месяца?',
      'Add demo data: ~24 routines, ~40 tasks and 4 months of history?',
    ),
  ) &&
  run('demo', () => generateDemo(store, today.value, now.value))
const removeDemo = () =>
  confirm(tr('Удалить все демо-данные? Ваши собственные задачи останутся.', 'Delete all demo data? Your own tasks will stay.')) &&
  run('clear', () => clearDemo(store))
</script>

<template>
  <section class="settings">
    <h1>{{ tr('Настройки', 'Settings') }}</h1>

    <div class="card block">
      <h2>{{ tr('Язык', 'Language') }}</h2>
      <div class="chips" role="group" :aria-label="tr('Язык', 'Language')">
        <button
          v-for="l in LANGS()"
          :key="l.id"
          type="button"
          class="chip"
          :aria-pressed="langPref === l.id"
          @click="setLangPref(l.id)"
        >
          {{ l.label }}
        </button>
      </div>
      <p class="muted">{{ tr('Только на этом устройстве.', 'This device only.') }}</p>
    </div>

    <div class="card block">
      <h2>{{ tr('Синхронизация', 'Sync') }}</h2>
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
      <dl class="status">
        <dt>{{ tr('Состояние', 'Status') }}</dt>
        <dd>{{ stateText(syncStatus.state) }}</dd>
        <dt>{{ tr('Последняя синхронизация', 'Last sync') }}</dt>
        <dd>{{ syncStatus.lastSyncAt ? new Date(syncStatus.lastSyncAt).toLocaleString(lang) : '—' }}</dd>
        <dt>{{ tr('Ждут отправки', 'Waiting to send') }}</dt>
        <dd>{{ outbox }}</dd>
        <template v-if="rejected">
          <dt>{{ tr('Отклонены сервером', 'Rejected by the server') }}</dt>
          <dd class="bad">{{ rejected }}</dd>
        </template>
      </dl>
      <button class="btn" type="button" @click="sync.sync()">{{ tr('Синхронизировать сейчас', 'Sync now') }}</button>
    </div>

    <div class="card block">
      <h2>{{ tr('День', 'Day') }}</h2>
      <div class="grid">
        <label class="field">
          <span>{{ tr('День начинается в (ч)', 'Day starts at (h)') }}</span>
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
          <span>{{ tr('Утро с (ч)', 'Morning from (h)') }}</span>
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
          <span>{{ tr('День с (ч)', 'Afternoon from (h)') }}</span>
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
          <span>{{ tr('Вечер с (ч)', 'Evening from (h)') }}</span>
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
          <span>{{ tr('Стрик: минимум дел в день', 'Streak: minimum things a day') }}</span>
          <input
            class="input"
            type="number"
            min="1"
            :value="settings.streak_min_done"
            @change="setNumber('streak_min_done', ($event.target as HTMLInputElement).value)"
          />
        </label>
      </div>
      <p class="muted">
        {{
          tr(
            'После полуночи и до начала дня всё ещё считается «вчера» и «вечер».',
            'From midnight until the day starts, it still counts as “yesterday” and “evening”.',
          )
        }}
      </p>
    </div>

    <div class="card block">
      <h2>{{ tr('Рутины', 'Routines') }}</h2>
      <label class="field narrow">
        <span>{{ tr('Предупреждать, если сделано меньше (%)', 'Warn when done less than (%)') }}</span>
        <input
          class="input"
          type="number"
          min="0"
          max="100"
          step="5"
          :value="settings.routine_warn_below"
          @change="setPercent('routine_warn_below', ($event.target as HTMLInputElement).value)"
        />
      </label>
      <p class="muted">
        {{
          tr(
            'Выполняемость рутины — какая доля её дней за последние 30 выполнена (у новой — с первого выполнения). ' +
              'Дни, пропущенные кнопкой «Пропуск», не в счёт, сегодняшний — только когда сделан. ' +
              'Ниже порога рутина помечается как пропускаемая. 0 — не предупреждать.',
            'A routine’s completion rate is the share of its days in the last 30 that got done (for a new one, since it was first done). ' +
              'Days skipped with the “Skip” button don’t count, and today counts only once it’s done. ' +
              'Below the threshold, the routine is flagged as being skipped. 0 turns warnings off.',
          )
        }}
      </p>
    </div>

    <div class="card block">
      <h2>{{ tr('Демо-данные', 'Demo data') }}</h2>
      <p class="muted">
        {{
          tr(
            'Чтобы посмотреть приложение в деле. Демо-данные отмечены особыми ID и удаляются одной кнопкой на всех устройствах — ваши задачи не пострадают.',
            'To see the app in action. Demo data is tagged with special IDs and removed with one button on all devices — your own tasks stay safe.',
          )
        }}
      </p>
      <div class="actions">
        <button class="btn" type="button" :disabled="!!busy" @click="fillDemo">
          {{ busy === 'demo' ? tr('Заполняю…', 'Filling…') : tr('Заполнить демо-данными', 'Fill with demo data') }}
        </button>
        <button class="btn danger" type="button" :disabled="!!busy" @click="removeDemo">
          {{ busy === 'clear' ? tr('Удаляю…', 'Deleting…') : tr('Удалить демо-данные', 'Delete demo data') }}
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
.narrow {
  max-width: 300px;
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
