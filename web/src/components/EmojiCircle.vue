<script setup lang="ts">
defineProps<{ emoji: string | null; color: number; size?: number }>()
</script>

<template>
  <span
    class="circle"
    :style="{ '--c': `var(--c${color})`, '--size': `${size ?? 40}px` }"
    aria-hidden="true"
  >
    {{ emoji || '•' }}
  </span>
</template>

<style scoped>
.circle {
  flex: none;
  display: inline-grid;
  place-items: center;
  width: var(--size);
  height: var(--size);
  border-radius: 50%;
  font-size: calc(var(--size) * 0.5);
  background: color-mix(in srgb, var(--c) 22%, var(--surface));
  border: 2px solid color-mix(in srgb, var(--c) 55%, var(--surface));
}
</style>
