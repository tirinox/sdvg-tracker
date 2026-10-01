<script setup lang="ts">
import { onUnmounted, ref, watch } from 'vue'
import { useApp } from '../app/context'
import { tr } from '../app/i18n'
import { suggestEmoji } from '../sync/emoji'
import EmojiCircle from './EmojiCircle.vue'

/**
 * `title`: the server suggests emoji for it. `auto`: a new item without an emoji takes the
 * server's pick as the title is typed, until the user chooses one.
 */
const props = defineProps<{ title?: string; auto?: boolean }>()
const emoji = defineModel<string | null>('emoji', { required: true })
const color = defineModel<number>('color', { required: true })
const { store } = useApp()

const suggested = ref<string[]>([])
/** The emoji this component set by itself; any other value is the user's choice. */
let autoValue: string | null = null
let chosen = !props.auto || emoji.value !== null
watch(emoji, (v) => {
  if (v !== autoValue) chosen = true
})

function choose(e: string | null) {
  chosen = true
  emoji.value = e
}

let timer: ReturnType<typeof setTimeout> | undefined
let asked = 0
watch(
  () => props.title?.trim() ?? '',
  (title) => {
    clearTimeout(timer)
    if (!title) {
      suggested.value = []
      return
    }
    timer = setTimeout(async () => {
      const n = ++asked
      const s = await suggestEmoji(store, title)
      if (n !== asked) return // the title changed while the server was answering
      suggested.value = s.emoji
      if (!chosen && s.pick !== emoji.value) emoji.value = autoValue = s.pick
    }, 400)
  },
  { immediate: true },
)
onUnmounted(() => clearTimeout(timer))

const EMOJIS = [
  '✅', '📞', '💬', '📧', '🛒', '💳', '🧾', '📦', '🛠️', '💡', '🧹', '🧺',
  '🍲', '🥣', '☕', '💊', '💧', '🚿', '🪥', '🛏️', '🧘', '🏋️', '🚶', '🚼',
  '👶', '❤️', '🎁', '📚', '📖', '📝', '📊', '💻', '🗓️', '⏰', '🚗', '🏠',
  '🪴', '🐶', '🎨', '🎵', '🧠', '🌙', '☀️', '⭐', '🔥', '🎯', '🧪', '🦷',
]
const open = ref(false)
</script>

<template>
  <div class="appearance">
    <button class="preview" type="button" :title="tr('Выбрать эмодзи', 'Pick an emoji')" @click="open = !open">
      <EmojiCircle :emoji="emoji" :color="color" :size="52" />
    </button>
    <div class="colors" role="radiogroup" :aria-label="tr('Цвет', 'Color')">
      <button
        v-for="c in 12"
        :key="c"
        type="button"
        class="swatch"
        role="radio"
        :aria-checked="color === c - 1"
        :style="{ background: `var(--c${c - 1})` }"
        @click="color = c - 1"
      />
    </div>
  </div>
  <div v-if="suggested.length" class="suggested" role="group" :aria-label="tr('Подходят к названию', 'Fit the title')">
    <span class="hint">{{ tr('Подходят', 'Suggested') }}</span>
    <button
      v-for="e in suggested"
      :key="e"
      type="button"
      class="emoji"
      :aria-pressed="emoji === e"
      @click="choose(e)"
    >
      {{ e }}
    </button>
  </div>
  <div v-if="open" class="emojis">
    <input
      class="input custom"
      :value="emoji ?? ''"
      :placeholder="tr('Своё эмодзи', 'Your own emoji')"
      maxlength="8"
      @input="choose(($event.target as HTMLInputElement).value || null)"
    />
    <button
      v-for="e in EMOJIS"
      :key="e"
      type="button"
      class="emoji"
      :aria-pressed="emoji === e"
      @click="(choose(e), (open = false))"
    >
      {{ e }}
    </button>
  </div>
</template>

<style scoped>
.appearance {
  display: flex;
  align-items: center;
  gap: 14px;
}
.preview {
  border: 0;
  background: none;
  padding: 0;
}
.colors {
  display: flex;
  flex-wrap: wrap;
  gap: 7px;
}
.swatch {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  border: 2px solid var(--surface);
  box-shadow: 0 0 0 1px var(--line);
  padding: 0;
}
.swatch[aria-checked='true'] {
  box-shadow: 0 0 0 2px var(--fg);
}
.emojis {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(38px, 1fr));
  gap: 4px;
  background: var(--surface-2);
  border-radius: 12px;
  padding: 8px;
}
.custom {
  grid-column: 1 / -1;
}
.suggested {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 2px;
}
.hint {
  font-size: 13px;
  color: var(--muted);
  margin-right: 6px;
}
.suggested .emoji {
  width: 38px;
}
.emoji {
  font-size: 22px;
  border: 0;
  background: none;
  border-radius: 8px;
  padding: 4px 0;
}
.emoji:hover,
.emoji[aria-pressed='true'] {
  background: var(--surface);
}
</style>
