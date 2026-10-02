<script setup lang="ts">
import { computed, nextTick, ref, shallowRef, useId, watch } from 'vue'
import { useApp } from '../app/context'
import { tr } from '../app/i18n'
import { loadTitleHistory } from '../app/views'
import { suggestTitles, type TitleHistory, type TitleSuggestion } from '../domain/suggest'
import EmojiCircle from './EmojiCircle.vue'

/**
 * Task title input that suggests titles of earlier tasks as you type.
 * Enter with nothing highlighted emits `enter`; a click or Enter on a suggestion emits `pick`,
 * the ↖ button (with `fillButton`) emits `fill` to put the title into the input for editing.
 * `plain` turns suggestions off (editing an existing task).
 */
const title = defineModel<string>({ required: true })
const props = defineProps<{ placeholder?: string; ariaLabel?: string; fillButton?: boolean; plain?: boolean }>()
const emit = defineEmits<{ enter: []; pick: [s: TitleSuggestion]; fill: [s: TitleSuggestion] }>()
const { store, today } = useApp()

const input = ref<HTMLInputElement>()
const list = ref<HTMLUListElement>()
const history = shallowRef<TitleHistory>([])
const open = ref(false)
const active = ref(-1)
const listId = useId()

const items = computed(() => (open.value && !props.plain ? suggestTitles(history.value, title.value) : []))

async function load() {
  if (props.plain) return
  history.value = await loadTitleHistory(store, today.value)
}

// Re-read the history when a new title starts, so tasks added a moment ago are in it.
watch(title, (v, old) => {
  active.value = -1
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

defineExpose({ focus: () => input.value?.focus() })
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
</style>
