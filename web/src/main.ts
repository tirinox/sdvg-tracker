import { computed, createApp, effectScope, ref, watch } from 'vue'
import { createRouter, createWebHistory } from 'vue-router'
import App from './App.vue'
import { APP, type AppContext, type Celebration, type EditorState } from './app/context'
import { useLive } from './app/useLive'
import { DEFAULT_SETTINGS } from './core/types'
import { runRollover } from './db/actions'
import { Store } from './db/store'
import { localNow, logicalDay } from './domain/dates'
import { SyncClient, type SyncStatus } from './sync/client'
import { startSyncScheduler } from './sync/scheduler'
import './styles.css'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: () => import('./views/NowView.vue') },
    { path: '/day/:date(\\d{4}-\\d{2}-\\d{2})?', component: () => import('./views/DayView.vue') },
    { path: '/inbox', component: () => import('./views/InboxView.vue') },
    { path: '/routines', component: () => import('./views/RoutinesView.vue') },
    { path: '/settings', component: () => import('./views/SettingsView.vue') },
    { path: '/:rest(.*)*', redirect: '/' },
  ],
})

async function bootstrap() {
  const store = await Store.open()
  const sync = new SyncClient(store)
  const app = createApp(App)

  // App-wide reactive state lives for the whole page, in its own effect scope.
  effectScope(true).run(() => {
    const syncStatus = ref<SyncStatus>(sync.status)
    sync.onStatus((s) => (syncStatus.value = s))

    // The clock moves on the minute, so the day turns right when its countdown runs out.
    const now = ref(localNow())
    const tick = () => {
      now.value = localNow()
      setTimeout(tick, 60_000 - (Date.now() % 60_000))
    }
    tick()

    const settings = useLive(() => store.settings(), DEFAULT_SETTINGS)
    const today = computed(() => logicalDay(now.value, settings.value.day_start_hour))
    // Open tasks from earlier days move to today, on start and whenever the day turns.
    watch(today, (d) => void runRollover(store, d), { immediate: true })

    const editor = ref<EditorState | null>(null)
    const celebration = ref<Celebration | null>(null)
    let celebrations = 0
    const ctx: AppContext = {
      store,
      sync,
      syncStatus,
      now,
      settings,
      today,
      editor,
      celebration,
      openTask: (id = null, defaults = {}) => (editor.value = { kind: 'task', id, defaults }),
      openRoutine: (id = null) => (editor.value = { kind: 'routine', id }),
      celebrate: (c) => (celebration.value = { ...c, id: ++celebrations }),
    }
    app.provide(APP, ctx)
  })

  startSyncScheduler(sync, store)
  app.use(router).mount('#app')
}

void bootstrap()
