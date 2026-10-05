<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useApp } from '../app/context'
import { adherenceLabel, shortDate, streakLabel, weekdayNames } from '../app/format'
import { tr } from '../app/i18n'
import { loadRoutineAdherence, loadRoutineHistory } from '../app/views'
import type { RoutineVersion } from '../core/types'
import { addDays } from '../domain/dates'
import type { Adherence, DayMark, RoutineHistory } from '../domain/routines'
import { archiveRoutine, createRoutine, editRoutine, routineVersions, type RoutineContent } from '../db/actions'
import AppearanceFields from './AppearanceFields.vue'
import DayMarks from './DayMarks.vue'
import Modal from './Modal.vue'
import PriorityField from './PriorityField.vue'
import TimingFields from './TimingFields.vue'

const props = defineProps<{ id: string | null }>()
const emit = defineEmits<{ close: [] }>()
const { store, today, settings } = useApp()

const form = reactive<Required<RoutineContent>>({
  title: '',
  emoji: null,
  color: 4,
  time_kind: 'none',
  part_of_day: null,
  time: null,
  duration_min: null,
  priority: 'normal',
  weekdays: 127,
})
let original: Required<RoutineContent> | null = null
const loaded = ref(props.id === null)
const adherence = ref<Adherence | null>(null)
const history = ref<RoutineHistory | null>(null)
const count = (m: DayMark) => history.value?.days.filter((x) => x === m).length ?? 0

onMounted(async () => {
  if (!props.id) return
  const latest = (await routineVersions(store, props.id))
    .sort((a, b) => (a.effective_from + a.hlc < b.effective_from + b.hlc ? -1 : 1))
    .at(-1)
  if (latest) {
    const { title, emoji, color, time_kind, part_of_day, time, duration_min, weekdays } = latest as RoutineVersion
    const priority = latest.priority ?? 'normal'
    original = { title, emoji, color, time_kind, part_of_day, time, duration_min, priority, weekdays }
    Object.assign(form, original)
  }
  adherence.value = await loadRoutineAdherence(store, props.id, today.value)
  history.value = await loadRoutineHistory(store, props.id, today.value)
  loaded.value = true
})

const valid = computed(
  () => form.title.trim().length > 0 && form.weekdays > 0 && (form.time_kind !== 'exact' || !!form.time),
)

/** 80&nbsp;% in Russian, 80% in English. */
function percent(n: number): string {
  return tr(`${n}\u00a0%`, `${n}%`)
}

function toggleDay(i: number) {
  form.weekdays ^= 1 << i
}

async function save() {
  if (!valid.value) return
  const data = {
    ...form,
    title: form.title.trim(),
    part_of_day: form.time_kind === 'part' ? form.part_of_day : null,
    time: form.time_kind === 'exact' ? form.time : null,
  }
  if (!props.id) {
    await createRoutine(store, data, today.value)
  } else {
    const changed = Object.fromEntries(
      Object.entries(data).filter(([k, v]) => original?.[k as keyof RoutineContent] !== v),
    )
    if (Object.keys(changed).length) await editRoutine(store, props.id, changed, today.value)
  }
  emit('close')
}

async function archive() {
  const question = tr(
    'Убрать рутину? Прошлые дни останутся в истории.',
    'Remove this routine? Past days stay in the history.',
  )
  if (props.id && confirm(question)) {
    await archiveRoutine(store, props.id, today.value)
    emit('close')
  }
}
</script>

<template>
  <Modal
    :title="id ? tr('Регулярная задача', 'Routine') : tr('Новая регулярная задача', 'New routine')"
    @close="emit('close')"
  >
    <template v-if="loaded">
      <input
        v-model="form.title"
        class="input title"
        :placeholder="tr('Например, «Пообедать»', 'For example, “Have lunch”')"
        @keydown.enter="save"
      />
      <AppearanceFields v-model:emoji="form.emoji" v-model:color="form.color" :title="form.title" :auto="!id" />
      <TimingFields
        v-model:kind="form.time_kind"
        v-model:part="form.part_of_day"
        v-model:time="form.time"
        v-model:duration="form.duration_min"
      />
      <PriorityField v-model="form.priority" />
      <div class="field">
        <span>{{ tr('Дни недели', 'Days of the week') }}</span>
        <div class="chips">
          <button
            v-for="(d, i) in weekdayNames()"
            :key="d"
            type="button"
            class="chip"
            :aria-pressed="Boolean(form.weekdays & (1 << i))"
            @click="toggleDay(i)"
          >
            {{ d }}
          </button>
        </div>
      </div>
      <div v-if="adherence?.percent != null" class="rate" :class="{ warn: adherence.warning }">
        <strong>
          {{ adherence.warning ? tr('⚠︎ Пропускается', '⚠︎ Being skipped') : tr('Выполняется', 'Completion rate') }}:
          {{ percent(adherence.percent) }}
        </strong>
        — {{ adherenceLabel(adherence) }}.
        <span class="muted">
          {{
            tr(
              'Считается за последние 30 дней, но не раньше первого выполнения; пропуски кнопкой «Пропуск» не в счёт.',
              'Counted over the last 30 days, but not before the first time it was done; days skipped with “Skip” don’t count.',
            )
          }}
          <template v-if="adherence.warning">
            {{
              tr(
                `Порог — ${percent(settings.routine_warn_below)}, меняется в настройках.`,
                `The warning shows below ${percent(settings.routine_warn_below)}; you can change that in Settings.`,
              )
            }}
          </template>
        </span>
        <template v-if="history">
          <DayMarks class="month" big :marks="history.days" />
          <span class="ends muted">
            <span>{{ shortDate(addDays(today, 1 - history.days.length)) }}</span>
            <span>{{ tr('сегодня', 'today') }}</span>
          </span>
          <span class="counts">
            <span class="k done">{{ tr('сделано', 'done') }} {{ count('done') }}</span>
            <span class="k missed">{{ tr('не сделано', 'missed') }} {{ count('missed') }}</span>
            <span class="k skipped">{{ tr('пропущено', 'skipped') }} {{ count('skipped') }}</span>
          </span>
          <span class="streak">🔥 {{ streakLabel(history) }}</span>
        </template>
      </div>
      <p class="muted note">
        {{
          tr(
            'Регулярные задачи не переносятся. Изменения действуют с сегодняшнего дня (или с завтрашнего, если сегодня уже отмечено) — прошлые дни остаются как были.',
            'Routines don’t move to other days. Changes apply from today (or from tomorrow, if today is already marked) — past days stay as they were.',
          )
        }}
      </p>
    </template>
    <template #footer>
      <button v-if="id" class="btn danger" type="button" @click="archive">{{ tr('Убрать рутину', 'Remove routine') }}</button>
      <span style="flex: 1" />
      <button class="btn" type="button" @click="emit('close')">{{ tr('Отмена', 'Cancel') }}</button>
      <button class="btn primary" type="button" :disabled="!valid" @click="save">{{ tr('Сохранить', 'Save') }}</button>
    </template>
  </Modal>
</template>

<style scoped>
.title {
  font-size: 17px;
  font-weight: 600;
  padding: 10px 12px;
}
.note {
  margin: 0;
  font-size: 13px;
}
.rate {
  margin: 0;
  font-size: 14px;
  padding: 10px 12px;
  border-radius: 10px;
  background: var(--surface-2);
}
.rate.warn {
  background: var(--warn-soft);
}
.rate.warn strong {
  color: var(--warn);
}
.rate .muted {
  display: block;
  margin-top: 2px;
  font-size: 13px;
}
.rate .month {
  margin-top: 10px;
}
.rate .ends {
  display: flex;
  justify-content: space-between;
  font-size: 12px;
}
.counts {
  display: flex;
  flex-wrap: wrap;
  gap: 2px 14px;
  margin-top: 8px;
  font-size: 13px;
}
.k::before {
  content: '';
  display: inline-block;
  width: 8px;
  height: 8px;
  margin-right: 5px;
  border-radius: 2px;
  background: var(--faint);
}
.k.done::before {
  background: var(--ok);
}
.k.missed::before {
  background: var(--danger);
}
.streak {
  display: block;
  margin-top: 6px;
  font-weight: 600;
}
</style>
