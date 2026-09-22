<script setup lang="ts">
import { ref } from 'vue'
import EmojiCircle from './EmojiCircle.vue'

const emoji = defineModel<string | null>('emoji', { required: true })
const color = defineModel<number>('color', { required: true })

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
    <button class="preview" type="button" title="Выбрать эмодзи" @click="open = !open">
      <EmojiCircle :emoji="emoji" :color="color" :size="52" />
    </button>
    <div class="colors" role="radiogroup" aria-label="Цвет">
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
  <div v-if="open" class="emojis">
    <input
      class="input custom"
      :value="emoji ?? ''"
      placeholder="Своё эмодзи"
      maxlength="8"
      @input="emoji = ($event.target as HTMLInputElement).value || null"
    />
    <button
      v-for="e in EMOJIS"
      :key="e"
      type="button"
      class="emoji"
      :aria-pressed="emoji === e"
      @click="((emoji = e), (open = false))"
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
