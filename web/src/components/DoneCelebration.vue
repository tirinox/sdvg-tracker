<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import type { Celebration } from '../app/context'
import { plural } from '../app/format'

const props = defineProps<{ celebration: Celebration }>()
const emit = defineEmits<{ close: [] }>()

const COLORS = ['#f06a6a', '#f39a4c', '#eec14a', '#5dbb7a', '#4bb0de', '#7b74e6', '#e57bb8']
// Level 1 is a confetti puff from the check, 2 adds fireworks, 3 is a long show with applause.
const DURATION_MS = [0, 2200, 4800, 7200][props.celebration.level]!
const ROCKETS = [0, 0, 6, 18][props.celebration.level]!
const LAUNCH_SPAN_MS = [0, 0, 1800, 3600][props.celebration.level]!

const canvas = ref<HTMLCanvasElement | null>(null)
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
const claps = props.celebration.level === 3 && !reduced
  ? Array.from({ length: 15 }, (_, i) => ({
      left: 4 + Math.random() * 88,
      delay: (i / 15) * 3.2 + Math.random() * 0.4,
      duration: 2.6 + Math.random() * 1.4,
      size: 26 + Math.random() * 26,
      sway: (Math.random() - 0.5) * 80,
    }))
  : []

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

interface Rocket {
  at: number
  x: number
  y: number
  vy: number
  colors: string[]
  size: number
  crackle: boolean
  exploded: boolean
}

interface Spark {
  x: number
  y: number
  px: number
  py: number
  vx: number
  vy: number
  life: number
  max: number
  color: string
  crackle: boolean
}

const pick = () => COLORS[Math.floor(Math.random() * COLORS.length)]!

onMounted(() => {
  timer = window.setTimeout(() => emit('close'), reduced ? 3000 : DURATION_MS + 600)
  const el = canvas.value
  const ctx = el?.getContext('2d')
  if (!el || !ctx || reduced) return

  const dpr = window.devicePixelRatio || 1
  const W = window.innerWidth
  const H = window.innerHeight
  el.width = W * dpr
  el.height = H * dpr
  ctx.scale(dpr, dpr)

  const { x: ox, y: oy, level } = props.celebration
  // Confetti fountain from the check button, mostly upwards.
  const pieces: Piece[] = Array.from({ length: [0, 70, 90, 140][level]! }, (_, i) => {
    const angle = -Math.PI / 2 + (Math.random() - 0.5) * 2.4
    const speed = 5 + Math.random() * 8 + level
    return {
      x: ox,
      y: oy,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      rot: Math.random() * Math.PI,
      vr: (Math.random() - 0.5) * 0.35,
      w: 5 + Math.random() * 5,
      h: 3 + Math.random() * 4,
      color: COLORS[i % COLORS.length]!,
    }
  })

  // Rockets rise from the bottom and burst in the upper half; level 3 ends with a volley.
  const rockets: Rocket[] = Array.from({ length: ROCKETS }, (_, i) => {
    const finale = level === 3 && i >= ROCKETS - 5
    const apex = H * (0.12 + Math.random() * 0.33)
    return {
      at: finale ? LAUNCH_SPAN_MS : (i / ROCKETS) * LAUNCH_SPAN_MS + Math.random() * 200,
      x: W * (0.12 + Math.random() * 0.76),
      y: H,
      // Launch speed that just reaches the apex under the rocket gravity below.
      vy: -Math.sqrt(2 * 0.12 * (H - apex)),
      colors: Math.random() < 0.4 ? [pick(), pick()] : [pick()],
      size: (level === 3 ? 1.25 : 1) * (0.8 + Math.random() * 0.5) * Math.min(1, Math.max(0.6, W / 900)),
      crackle: level === 3 && Math.random() < 0.35,
      exploded: false,
    }
  })
  const sparks: Spark[] = []

  const burst = (r: Rocket) => {
    r.exploded = true
    const n = Math.round(80 * r.size)
    for (let i = 0; i < n; i++) {
      const angle = (i / n) * Math.PI * 2 + Math.random() * 0.2
      const speed = (2 + Math.random() * 4) * r.size * 1.5
      const max = 55 + Math.random() * 35
      sparks.push({
        x: r.x,
        y: r.y,
        px: r.x,
        py: r.y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        life: max,
        max,
        color: r.colors[i % r.colors.length]!,
        crackle: r.crackle,
      })
    }
  }

  const start = performance.now()
  let last = start
  const tick = (t: number) => {
    const elapsed = t - start
    // Velocities are per 60 Hz frame; scale steps so the speed does not depend on the display rate.
    const k = Math.min(3, (t - last) / (1000 / 60))
    last = t
    ctx.clearRect(0, 0, W, H)
    const fade = Math.max(0, Math.min(1, (DURATION_MS - elapsed) / 700))

    ctx.globalAlpha = fade
    const drag = 0.975 ** k
    for (const p of pieces) {
      p.vy += 0.28 * k
      p.vx *= drag
      p.vy *= drag
      p.x += p.vx * k
      p.y += p.vy * k
      p.rot += p.vr * k
      if (p.y > H + 20) continue
      ctx.save()
      ctx.translate(p.x, p.y)
      ctx.rotate(p.rot)
      ctx.fillStyle = p.color
      ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h * Math.abs(Math.cos(p.rot * 2)))
      ctx.restore()
    }

    for (const r of rockets) {
      if (r.exploded || elapsed < r.at) continue
      r.vy += 0.12 * k
      r.y += r.vy * k
      ctx.globalAlpha = fade
      ctx.strokeStyle = r.colors[0]!
      ctx.lineWidth = 2.5
      ctx.lineCap = 'round'
      ctx.beginPath()
      ctx.moveTo(r.x, r.y)
      ctx.lineTo(r.x, r.y - r.vy * 4)
      ctx.stroke()
      if (r.vy >= 0) burst(r)
    }

    const sparkDrag = 0.955 ** k
    for (const s of sparks) {
      if (s.life <= 0) continue
      s.life -= k
      s.px = s.x
      s.py = s.y
      s.vy += 0.05 * k
      s.vx *= sparkDrag
      s.vy *= sparkDrag
      s.x += s.vx * k
      s.y += s.vy * k
      const a = (s.life / s.max) ** 0.7 * fade
      ctx.globalAlpha = s.crackle && s.life < s.max * 0.6 ? a * (Math.random() < 0.5 ? 1 : 0.15) : a
      ctx.strokeStyle = s.color
      ctx.lineWidth = 2.2
      ctx.beginPath()
      // A short streak behind each spark reads as a trail.
      ctx.moveTo(s.px - (s.x - s.px) * 2, s.py - (s.y - s.py) * 2)
      ctx.lineTo(s.x, s.y)
      ctx.stroke()
    }

    if (elapsed < DURATION_MS) frame = requestAnimationFrame(tick)
    else ctx.clearRect(0, 0, W, H)
  }
  frame = requestAnimationFrame(tick)
})

onBeforeUnmount(() => {
  cancelAnimationFrame(frame)
  clearTimeout(timer)
})

const moves = props.celebration.moves
const times = `${moves} ${plural(moves, 'раз', 'раза', 'раз')}`
</script>

<template>
  <div class="celebration" role="status">
    <canvas ref="canvas" class="sky" aria-hidden="true" />
    <div v-if="claps.length" class="claps" aria-hidden="true">
      <span
        v-for="(c, i) in claps"
        :key="i"
        class="clap"
        :style="{
          left: `${c.left}%`,
          fontSize: `${c.size}px`,
          animationDelay: `${c.delay}s`,
          animationDuration: `${c.duration}s`,
          '--sway': `${c.sway}px`,
        }"
        >👏</span
      >
    </div>
    <button v-if="celebration.level >= 2" type="button" class="toast" :class="`l${celebration.level}`" @click="emit('close')">
      <span class="emoji" aria-hidden="true">{{ celebration.level === 3 ? '👏' : '🎆' }}</span>
      <span>
        <b>{{ celebration.level === 3 ? 'Вот это победа!' : 'Салют!' }}</b>
        <span class="sub">
          {{ celebration.level === 3 ? `Задачу переносили ${times} — и она сделана` : `Переносили ${times}, а вы её сделали` }}
        </span>
      </span>
    </button>
  </div>
</template>

<style scoped>
.sky {
  position: fixed;
  inset: 0;
  width: 100vw;
  height: 100vh;
  pointer-events: none;
  z-index: 50;
}
.claps {
  position: fixed;
  inset: 0;
  overflow: hidden;
  pointer-events: none;
  z-index: 52;
}
.clap {
  position: absolute;
  bottom: -60px;
  line-height: 1;
  opacity: 0;
  animation-name: rise;
  animation-timing-function: cubic-bezier(0.3, 0.6, 0.5, 1);
  animation-fill-mode: both;
}
@keyframes rise {
  0% {
    transform: translate(0, 0) scale(0.6) rotate(-12deg);
    opacity: 0;
  }
  12% {
    opacity: 1;
  }
  30% {
    transform: translate(calc(var(--sway) * 0.4), -32vh) scale(1.05) rotate(10deg);
  }
  55% {
    transform: translate(calc(var(--sway) * -0.3), -62vh) scale(0.95) rotate(-8deg);
  }
  80% {
    opacity: 1;
  }
  100% {
    transform: translate(var(--sway), -110vh) scale(1.1) rotate(6deg);
    opacity: 0;
  }
}
.toast {
  position: fixed;
  z-index: 53;
  /* Below the record toast, which can fall on the same tap. */
  top: 144px;
  /* Centered without left: 50%, which would cap the width at half the screen on phones. */
  left: 16px;
  right: 16px;
  width: fit-content;
  margin: 0 auto;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 18px;
  border: 0;
  border-radius: var(--radius);
  background: var(--surface);
  color: var(--fg);
  box-shadow: var(--shadow), 0 10px 30px rgb(0 0 0 / 15%);
  text-align: left;
  font: inherit;
  animation: pop 0.4s cubic-bezier(0.2, 1.4, 0.4, 1);
}
.toast.l3 {
  background: linear-gradient(135deg, var(--warn-soft), var(--accent-soft));
}
.emoji {
  font-size: 30px;
}
.l3 .emoji {
  animation: clap 0.5s ease-in-out 6;
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
    transform: scale(0.6);
    opacity: 0;
  }
}
@keyframes clap {
  50% {
    transform: scale(1.25) rotate(-10deg);
  }
}
</style>
