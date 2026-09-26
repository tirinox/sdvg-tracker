<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { isOnboardingDone } from './app/connect'
import { useApp } from './app/context'
import { useLive } from './app/useLive'
import { claimRecordCelebration, loadRecord } from './app/views'
import DoneCelebration from './components/DoneCelebration.vue'
import RecordConfetti from './components/RecordConfetti.vue'
import RoutineEditor from './components/RoutineEditor.vue'
import ServerChangeDialog from './components/ServerChangeDialog.vue'
import TaskEditor from './components/TaskEditor.vue'
import WelcomeDialog from './components/WelcomeDialog.vue'
import { loadSyncConfig } from './sync/client'

const { store, editor, celebration, syncStatus, openTask, today } = useApp()

// First run without a server: suggest connecting before showing an empty, device-only list.
const welcome = ref(false)
onMounted(async () => {
  welcome.value = !(await loadSyncConfig(store)) && !(await isOnboardingDone(store))
})

// Confetti once a day, on whichever screen the record gets broken.
const record = useLive(() => loadRecord(store, today.value), null, [today])
const celebrate = ref<{ done: number; previous: number } | null>(null)
watch(record, async (r) => {
  if (r && (await claimRecordCelebration(store, r, today.value))) {
    celebrate.value = { done: r.today_done, previous: r.best_done }
  }
})

const NAV = [
  { to: '/', label: 'Сейчас', icon: '✦' },
  { to: '/day', label: 'День', icon: '☰' },
  { to: '/inbox', label: 'Входящие', icon: '📥' },
  { to: '/routines', label: 'Рутины', icon: '⟳' },
  { to: '/settings', label: 'Настройки', icon: '⚙' },
]

// Sync paused on another data set: ask once per server, the header badge asks again.
const dismissedServer = ref<string | null>(null)
const serverChange = computed(() => {
  const change = syncStatus.value.serverChange
  return change && change.serverId !== dismissedServer.value ? change : null
})

const sync = computed(() => {
  switch (syncStatus.value.state) {
    case 'idle':
      return { cls: 'ok', text: 'синхронизировано' }
    case 'syncing':
      return { cls: 'busy', text: 'синхронизация…' }
    case 'offline':
      return { cls: 'warn', text: 'офлайн' }
    case 'unconfigured':
      return { cls: 'off', text: 'только это устройство' }
    case 'server_changed':
      return { cls: 'bad', text: 'сервер сменился — нужно решение' }
    default:
      return { cls: 'bad', text: 'ошибка синхронизации' }
  }
})
</script>

<template>
  <div class="shell">
    <header class="top">
      <RouterLink to="/" class="brand">
        <span class="logo">✓</span>
        СДВГ-трекер
      </RouterLink>
      <nav class="tabs" aria-label="Разделы">
        <RouterLink v-for="n in NAV" :key="n.to" :to="n.to" class="tab">
          <span class="icon" aria-hidden="true">{{ n.icon }}</span>
          <span class="label">{{ n.label }}</span>
        </RouterLink>
      </nav>
      <button
        v-if="syncStatus.state === 'server_changed'"
        type="button"
        class="sync"
        :class="sync.cls"
        :title="sync.text"
        @click="dismissedServer = null"
      >
        <span class="dot" />
        <span class="text">{{ sync.text }}</span>
      </button>
      <RouterLink v-else to="/settings" class="sync" :class="sync.cls" :title="sync.text">
        <span class="dot" />
        <span class="text">{{ sync.text }}</span>
      </RouterLink>
    </header>

    <main class="content">
      <RouterView />
    </main>

    <button class="fab" type="button" aria-label="Новая задача" @click="openTask(null)">＋</button>

    <TaskEditor
      v-if="editor?.kind === 'task'"
      :id="editor.id"
      :key="`t${editor.id}`"
      :defaults="editor.defaults"
      @close="editor = null"
    />
    <RoutineEditor v-if="editor?.kind === 'routine'" :id="editor.id" :key="`r${editor.id}`" @close="editor = null" />
    <WelcomeDialog v-if="welcome" @close="welcome = false" />
    <ServerChangeDialog
      v-else-if="serverChange"
      :key="serverChange.serverId"
      :change="serverChange"
      @close="dismissedServer = syncStatus.serverChange?.serverId ?? null"
    />
    <RecordConfetti v-if="celebrate" v-bind="celebrate" @close="celebrate = null" />
    <DoneCelebration
      v-if="celebration"
      :key="celebration.id"
      :celebration="celebration"
      @close="celebration = null"
    />
  </div>
</template>

<style scoped>
.top {
  position: sticky;
  top: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 10px 20px;
  background: color-mix(in srgb, var(--bg) 88%, transparent);
  backdrop-filter: blur(10px);
  border-bottom: 1px solid var(--line);
}
.brand {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 700;
  color: var(--fg);
  white-space: nowrap;
}
.logo {
  display: grid;
  place-items: center;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: var(--accent);
  color: #fff;
  font-size: 15px;
}
.tabs {
  display: flex;
  gap: 2px;
  flex: 1;
}
.tab {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 7px 12px;
  border-radius: 10px;
  color: var(--muted);
  font-weight: 550;
}
.tab:hover {
  background: var(--surface-2);
}
.tab.router-link-exact-active,
.tab[href='/day'].router-link-active {
  background: var(--accent-soft);
  color: var(--accent);
}
.icon {
  font-size: 14px;
}
.sync {
  border: 0;
  background: none;
  padding: 0;
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: var(--muted);
  white-space: nowrap;
}
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--faint);
}
.ok .dot {
  background: var(--ok);
}
.busy .dot {
  background: var(--accent);
}
.warn .dot {
  background: var(--warn);
}
.bad .dot {
  background: var(--danger);
}
.content {
  max-width: 720px;
  margin: 0 auto;
  padding: 20px 16px 110px;
}
.fab {
  position: fixed;
  right: max(20px, calc(50vw - 380px));
  bottom: 24px;
  width: 56px;
  height: 56px;
  border-radius: 50%;
  border: 0;
  background: var(--accent);
  color: #fff;
  font-size: 28px;
  box-shadow: 0 6px 20px color-mix(in srgb, var(--accent) 45%, transparent);
}

@media (max-width: 760px) {
  .top {
    padding: 10px 16px;
    /* backdrop-filter would make the fixed bottom tab bar position relative to the header */
    backdrop-filter: none;
    background: var(--bg);
  }
  .brand {
    flex: 1;
  }
  .tabs {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    justify-content: space-around;
    padding: 6px 4px calc(6px + env(safe-area-inset-bottom));
    background: var(--surface);
    border-top: 1px solid var(--line);
  }
  .tab {
    flex-direction: column;
    gap: 1px;
    font-size: 11px;
    padding: 5px 6px;
  }
  .icon {
    font-size: 18px;
  }
  .sync .text {
    display: none;
  }
  .fab {
    bottom: calc(76px + env(safe-area-inset-bottom));
    right: 16px;
  }
}
</style>
