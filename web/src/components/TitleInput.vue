<script setup lang="ts">
import { computed, nextTick, ref, shallowRef, useId, watch } from 'vue'
import { useApp } from '../app/context'
import { shortDate } from '../app/format'
import { tr } from '../app/i18n'
import { useLive } from '../app/useLive'
import { loadListed, loadTitleHistory } from '../app/views'
import { addDays } from '../domain/dates'
import { checkTitle, withoutTaken, type ListedItem } from '../domain/duplicates'
import { suggestTitles, type TitleHistory, type TitleSuggestion } from '../domain/suggest'
import EmojiCircle from './EmojiCircle.vue'

/**
 * Task title input that suggests titles of earlier tasks as you type.
 * Enter with nothing highlighted emits `enter`; a click or Enter on a suggestion emits `pick`,
 * the ↖ button (with `fillButton`) emits `fill` to put the title into the input for editing.
 * `plain` turns suggestions off (editing an existing task).
 *
 * For a new task the title is also checked against the listed tasks and routines (domain/duplicates):
 * under the input it says when the title is taken, done today or similar to another one.
 * Before creating, the parent calls `confirm(title)`.
 */
const title = defineModel<string>({ required: true })
const props = defineProps<{ placeholder?: string; ariaLabel?: string; fillButton?: boolean; plain?: boolean }>()
const emit = defineEmits<{ enter: []; pick: [s: TitleSuggestion]; fill: [s: TitleSuggestion] }>()
const { store, today, openTask, openRoutine } = useApp()

const input = ref<HTMLInputElement>()
const list = ref<HTMLUListElement>()
const offer = ref<HTMLButtonElement>()
const history = shallowRef<TitleHistory>([])
/** Followed live: a stale list would let a duplicate through or offer a number that is taken by now. */
const listed = useLive(() => (props.plain ? Promise.resolve([]) : loadListed(store, today.value)), [] as ListedItem[], [today])
const open = ref(false)
const active = ref(-1)
/** Enter on a taken title; each one shakes the notice anew. */
const nudges = ref(0)
const listId = useId()

const offered = computed(() => withoutTaken(history.value, listed.value))
const items = computed(() => (open.value && !props.plain ? suggestTitles(offered.value, title.value) : []))
const check = computed(() => checkTitle(listed.value, title.value))

async function load() {
  if (props.plain) return
  history.value = await loadTitleHistory(store, today.value)
}

/**
 * Whether a task can be created under `t`, the parent's title: the model here catches up only on the
 * next render. A taken title is refused with a nudge; one done today is refused too, with its numbered
 * title offered (focused, so a second Enter takes it). Synchronous, so the input can be cleared before the write.
 */
function confirm(t: string): boolean {
  const c = checkTitle(listed.value, t)
  if (c.status === 'free') return true
  if (c.status === 'taken') nudges.value++
  else void nextTick(() => offer.value?.focus())
  return false
}

function takeOffer(next: string) {
  title.value = next
  input.value?.focus()
  emit('enter')
}

function openItem(i: ListedItem) {
  title.value = ''
  if (i.kind === 'task') openTask(i.id)
  else openRoutine(i.id)
}

function where(i: ListedItem): string {
  if (i.kind === 'routine') return tr('рутина', 'routine')
  if (i.date === null) return tr('во входящих', 'in the inbox')
  if (i.date <= today.value) return tr('на сегодня', 'for today')
  if (i.date === addDays(today.value, 1)) return tr('на завтра', 'for tomorrow')
  return tr(`на ${shortDate(i.date)}`, `for ${shortDate(i.date)}`)
}

// Re-read the history when a new title starts, so tasks added a moment ago are in it.
watch(title, (v, old) => {
  active.value = -1
  nudges.value = 0
  if (v.trim() && !old.trim()) void load()
})

watch(
  () => items.value.length > 0,
  async (shown) => {
    if (!shown) return
    await nextTick()
    list.value?.scrollIntoView({ block: 'nearest' })
  },
)

function onFocus() {
  open.value = true
  void load()
}

function onKeydown(e: KeyboardEvent) {
  if (e.isComposing) return
  const n = items.value.length
  if (e.key === 'ArrowDown' && n) {
    e.preventDefault()
    active.value = (active.value + 1) % n
  } else if (e.key === 'ArrowUp' && n) {
    e.preventDefault()
    active.value = active.value <= 0 ? n - 1 : active.value - 1
  } else if (e.key === 'Enter') {
    e.preventDefault()
    const s = items.value[active.value]
    if (s) choose('pick', s)
    else emit('enter')
  } else if (e.key === 'Escape' && n) {
    // Close the list, not the dialog around it.
    e.preventDefault()
    e.stopPropagation()
    open.value = false
  }
}

function choose(kind: 'pick' | 'fill', s: TitleSuggestion) {
  if (kind === 'pick') emit('pick', s)
  else emit('fill', s)
  open.value = false
  active.value = -1
}

defineExpose({ focus: () => input.value?.focus(), confirm })
</script>

<template>
  <div class="suggest">
    <input
      ref="input"
      v-model="title"
      class="input"
      :placeholder="placeholder"
      :aria-label="ariaLabel"
      role="combobox"
      aria-autocomplete="list"
      :aria-expanded="items.length > 0"
      :aria-controls="listId"
      :aria-activedescendant="active >= 0 ? `${listId}-${active}` : undefined"
      autocomplete="off"
      @focus="onFocus"
      @input="open = true"
      @blur="open = false"
      @keydown="onKeydown"
    />
    <ul v-if="items.length" :id="listId" ref="list" class="list" role="listbox" :aria-label="tr('Из прошлых задач', 'From past tasks')">
      <li
        v-for="(s, i) in items"
        :id="`${listId}-${i}`"
        :key="s.title"
        class="item"
        role="option"
        :aria-selected="i === active"
        @mousedown.prevent
        @mouseenter="active = i"
        @click="choose('pick', s)"
      >
        <EmojiCircle :emoji="s.emoji" :color="s.color" :size="28" />
        <span class="name">{{ s.title }}</span>
        <button
          v-if="fillButton"
          class="fill"
          type="button"
          tabindex="-1"
          :title="tr('Вставить в поле, чтобы изменить', 'Put in the field to edit')"
          :aria-label="tr('Вставить в поле', 'Put in the field')"
          @mousedown.prevent
          @click.stop="choose('fill', s)"
        >
          ↖
        </button>
      </li>
    </ul>
    <div
      v-if="check.status !== 'free' || check.similar.length"
      :key="nudges"
      class="notice"
      :class="[check.status, { nudged: nudges > 0 }]"
      role="status"
    >
      <template v-if="check.status === 'taken'">
        <span class="text">
          <template v-if="check.item.kind === 'task'">
            {{ tr('Такая задача уже есть', 'Already on your list') }} {{ where(check.item) }}
          </template>
          <template v-else>{{ tr('Такая рутина уже есть', 'There is a routine with this name') }}</template>
        </span>
        <button class="btn ghost act" type="button" @click="openItem(check.item)">{{ tr('Открыть', 'Open') }}</button>
      </template>
      <template v-else-if="check.status === 'done_today'">
        <span class="text">
          ✓
          {{
            check.item.kind === 'task'
              ? tr('Такая задача уже сделана сегодня', 'Already done today')
              : tr('Эта рутина уже сделана сегодня', 'This routine is already done today')
          }}
        </span>
        <button ref="offer" class="btn act" type="button" @click="takeOffer(check.next)">
          {{ tr(`Добавить «${check.next}»`, `Add “${check.next}”`) }}
        </button>
      </template>
      <template v-else>
        <span class="text">{{ tr('Похожая уже есть:', 'A similar one exists:') }}</span>
        <button
          v-for="i in check.similar"
          :key="i.id"
          class="similar"
          type="button"
          :title="tr('Открыть', 'Open')"
          @mousedown.prevent
          @click="openItem(i)"
        >
          <EmojiCircle :emoji="i.emoji" :color="i.color" :size="20" />
          <span class="name">{{ i.title }}</span>
          <span class="where">{{ where(i) }}</span>
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.suggest {
  position: relative;
  flex: 1;
  min-width: 0;
}
.list {
  position: absolute;
  z-index: 20;
  top: calc(100% + 4px);
  left: 0;
  right: 0;
  margin: 0;
  padding: 4px;
  list-style: none;
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 12px;
  box-shadow: 0 8px 28px rgb(31 29 43 / 14%);
}
.item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 5px 6px;
  border-radius: 8px;
  cursor: pointer;
}
.item[aria-selected='true'] {
  background: var(--accent-soft);
}
.name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.fill {
  flex: none;
  width: 32px;
  height: 32px;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--muted);
  font: inherit;
  font-size: 16px;
  cursor: pointer;
}
.fill:hover {
  background: var(--line);
  color: var(--fg);
}
.notice {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 8px;
  margin-top: 6px;
  padding: 5px 6px 5px 10px;
  border-radius: 10px;
  font-size: 14px;
  background: var(--surface-2);
  color: var(--muted);
}
.notice.taken {
  background: var(--caution-soft);
  color: var(--caution);
}
.notice.done_today {
  background: var(--accent-soft);
  color: var(--fg);
}
.notice .text {
  min-width: 0;
}
.notice.taken .text,
.notice.done_today .text {
  flex: 1 1 auto;
}
/* A long title in the offer is cut, not wrapped. */
.act {
  display: block;
  max-width: 100%;
  margin-left: auto;
  overflow: hidden;
  padding: 3px 10px;
  font-size: 14px;
  color: inherit;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.similar {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  max-width: 100%;
  min-width: 0;
  padding: 2px 8px 2px 2px;
  border: 0;
  border-radius: 999px;
  background: var(--surface);
  color: var(--fg);
  font: inherit;
  cursor: pointer;
}
.similar:hover {
  background: var(--line);
}
.similar .where {
  flex: none;
  font-size: 13px;
  color: var(--muted);
}
.nudged {
  animation: nudge 0.35s;
}
@keyframes nudge {
  25% {
    transform: translateX(-4px);
  }
  75% {
    transform: translateX(4px);
  }
}
</style>
