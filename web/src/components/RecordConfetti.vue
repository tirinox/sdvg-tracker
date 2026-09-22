<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { plural } from '../app/format'

const props = defineProps<{ done: number; previous: number }>()
const emit = defineEmits<{ close: [] }>()

const canvas = ref<HTMLCanvasElement | null>(null)
const COLORS = ['#f06a6a', '#f39a4c', '#eec14a', '#5dbb7a', '#4bb0de', '#7b74e6', '#e57bb8']
const DURATION_MS = 4000
let frame = 0
let timer = 0

interface Piece {
  x: number
  y: number
  vx: number
  vy: number
  rot: number
  vr: number
  w: number
  h: number
  color: string
}

onMounted(() => {
  timer = window.setTimeout(() => emit('close'), DURATION_MS + 1500)
  const el = canvas.value
  const ctx = el?.getContext('2d')
  if (!el || !ctx || matchMedia('(prefers-reduced-motion: reduce)').matches) return

  const dpr = window.devicePixelRatio || 1
  const W = window.innerWidth
  const H = window.innerHeight
  el.width = W * dpr
  el.height = H * dpr
  ctx.scale(dpr, dpr)

  // Two bursts from the bottom corners, aimed up and towards the middle.
  const pieces: Piece[] = Array.from({ length: 180 }, (_, i) => {
    const left = i % 2 === 0
    const angle = (left ? -60 : -120) * (Math.PI / 180) + (Math.random() - 0.5) * 0.7
    // Scaled to the viewport: most pieces rise to the upper third, sideways by about half the width.
    const speed = Math.sqrt(H) * (0.7 + Math.random() * 0.35)
    return {
      x: left ? 0 : W,
      y: H,
      vx: Math.cos(angle) * speed * Math.min(1, W / 1000),
      vy: Math.sin(angle) * speed,
      rot: Math.random() * Math.PI,
      vr: (Math.random() - 0.5) * 0.3,
      w: 6 + Math.random() * 6,
      h: 4 + Math.random() * 4,
      color: COLORS[i % COLORS.length]!,
    }
  })

  const start = performance.now()
  let last = start
  const tick = (t: number) => {
    const elapsed = t - start
    // Velocities are per 60 Hz frame; scale steps so the speed does not depend on the display rate.
    const k = Math.min(3, (t - last) / (1000 / 60))
    last = t
    const drag = 0.99 ** k
    ctx.clearRect(0, 0, W, H)
    ctx.globalAlpha = Math.max(0, Math.min(1, (DURATION_MS - elapsed) / 800))
    for (const p of pieces) {
      p.vy += 0.25 * k
      p.vx *= drag
      p.vy *= drag
      p.x += p.vx * k
      p.y += p.vy * k
      p.rot += p.vr * k
      ctx.save()
      ctx.translate(p.x, p.y)
      ctx.rotate(p.rot)
      ctx.fillStyle = p.color
      ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h * Math.abs(Math.cos(p.rot * 2)))
      ctx.restore()
    }
    if (elapsed < DURATION_MS) frame = requestAnimationFrame(tick)
  }
  frame = requestAnimationFrame(tick)
})

onBeforeUnmount(() => {
  cancelAnimationFrame(frame)
  clearTimeout(timer)
})
</script>

<template>
  <div class="record" role="status">
    <canvas ref="canvas" class="confetti" aria-hidden="true" />
    <button type="button" class="toast" @click="emit('close')">
      <span class="cup" aria-hidden="true">🏆</span>
      <span>
        <b>Новый рекорд!</b>
        <span class="sub">
          {{ props.done }} {{ plural(props.done, 'дело', 'дела', 'дел') }} за день — прежний был
          {{ props.previous }}
        </span>
      </span>
    </button>
  </div>
</template>

<style scoped>
.confetti {
  position: fixed;
  inset: 0;
  width: 100vw;
  height: 100vh;
  pointer-events: none;
  z-index: 50;
}
.toast {
  position: fixed;
  z-index: 51;
  top: 72px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 12px;
  max-width: calc(100vw - 32px);
  padding: 12px 18px;
  border: 0;
  border-radius: var(--radius);
  background: var(--surface);
  color: var(--fg);
  box-shadow: var(--shadow), 0 10px 30px rgb(0 0 0 / 15%);
  text-align: left;
  font: inherit;
  animation: pop 0.35s cubic-bezier(0.2, 1.4, 0.4, 1);
}
.cup {
  font-size: 30px;
}
.toast b {
  display: block;
  font-size: 16px;
}
.sub {
  font-size: 13px;
  color: var(--muted);
}
@keyframes pop {
  from {
    transform: translateX(-50%) scale(0.6);
    opacity: 0;
  }
}
</style>
