<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useApp } from '../app/context'
import { countdownLabel } from '../app/format'
import { dayEnd, dayEndLevel, instantOf } from '../domain/dates'

// Time left in the logical day: yellow in the last hour, red in the last half hour.
const { today, settings } = useApp()

// Ticks on every second of its own; the app clock only moves once a minute.
const nowMs = ref(Date.now())
let timer: ReturnType<typeof setTimeout> | undefined
function tick() {
  nowMs.value = Date.now()
  timer = setTimeout(tick, 1005 - (nowMs.value % 1000))
}
onMounted(tick)
onUnmounted(() => clearTimeout(timer))

const endsAt = computed(() => dayEnd(today.value, settings.value.day_start_hour))
const secondsLeft = computed(() =>
  Math.max(0, Math.ceil((instantOf(endsAt.value).getTime() - nowMs.value) / 1000)),
)
const level = computed(() => dayEndLevel(secondsLeft.value))
</script>

<template>
  <span class="countdown" :class="level" role="timer" :title="`День закончится в ${endsAt.slice(11)}`">
    <span aria-hidden="true">⏳</span>
    <b>{{ countdownLabel(secondsLeft) }}</b>
    <span>до конца дня</span>
  </span>
</template>

<style scoped>
.countdown {
  display: inline-flex;
  align-items: baseline;
  gap: 5px;
  padding: 5px 11px;
  border-radius: 999px;
  background: var(--surface-2);
  color: var(--muted);
  font-size: 14px;
  white-space: nowrap;
  transition:
    background 0.3s,
    color 0.3s;
}
b {
  color: var(--fg);
  font-weight: 650;
  font-variant-numeric: tabular-nums;
}
.soon {
  background: var(--caution-soft);
  color: var(--caution);
}
.urgent {
  background: var(--danger-soft);
  color: var(--danger);
}
.soon b,
.urgent b {
  color: inherit;
}
</style>
