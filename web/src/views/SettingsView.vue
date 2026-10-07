<script setup lang="ts">
import { ref } from 'vue'
import { useApp } from '../app/context'
import { langPref, setLangPref, tr, type LangPref } from '../app/i18n'
import { updateSettings } from '../db/actions'
import { clearDemo, generateDemo } from '../demo/demo'
import { syncStateText } from '../app/connect'

const { store, syncStatus, settings, today, now } = useApp()

const busy = ref('')

const LANGS = (): { id: LangPref; label: string }[] => [
  { id: 'system', label: tr('Как в системе', 'System default') },
  { id: 'ru', label: 'Русский' },
  { id: 'en', label: 'English' },
]

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

    <RouterLink to="/settings/sync" class="card block link">
      <h2>{{ tr('Синхронизация', 'Sync') }}</h2>
      <span class="muted">{{ syncStateText(syncStatus.state) }}</span>
      <span class="chevron" aria-hidden="true">›</span>
    </RouterLink>

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
      <h2>{{ tr('Вид', 'Appearance') }}</h2>
      <label class="check">
        <input
          type="checkbox"
          :checked="settings.show_color_uses"
          @change="updateSettings(store, { show_color_uses: ($event.target as HTMLInputElement).checked })"
        />
        <span>{{ tr('Показывать популярность цвета', 'Show color popularity') }}</span>
      </label>
      <p class="muted">
        {{
          tr(
            'Под каждым кружком в редакторе — сколько задач носят этот цвет; самый редкий и самый частый выделены.',
            'Under every swatch in the editor: how many tasks wear the color; the rarest and the commonest stand out.',
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
.check {
  display: flex;
  align-items: center;
  gap: 10px;
}
.check input {
  width: 18px;
  height: 18px;
  accent-color: var(--accent);
}
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 10px;
}
a.link {
  grid-template-columns: auto 1fr auto;
  align-items: center;
  color: inherit;
}
a.link .muted {
  justify-self: end;
  font-size: 14px;
  text-align: right;
}
a.link .chevron {
  color: var(--muted);
  font-size: 22px;
  line-height: 1;
}
a.link:hover {
  background: var(--surface-2);
}
</style>
