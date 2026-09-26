<script setup lang="ts">
import { computed, ref } from 'vue'
import { useApp } from '../app/context'
import { plural } from '../app/format'
import type { Counts, ServerChange } from '../sync/client'
import Modal from './Modal.vue'

const props = defineProps<{ change: ServerChange }>()
const emit = defineEmits<{ close: [] }>()
const { sync } = useApp()
const busy = ref<'server' | 'merge' | null>(null)

const title = computed(() =>
  props.change.kind === 'first' ? 'На сервере уже есть данные' : 'Данные на сервере сменились',
)

function describe(c: Counts): string {
  if (c.task + c.routine === 0) return 'пусто'
  return [
    `${c.task} ${plural(c.task, 'задача', 'задачи', 'задач')}`,
    `${c.routine} ${plural(c.routine, 'рутина', 'рутины', 'рутин')}`,
  ].join(' · ')
}

async function choose(choice: 'server' | 'merge') {
  busy.value = choice
  try {
    await (choice === 'server' ? sync.takeServerData() : sync.mergeWithServer())
  } finally {
    busy.value = null
  }
  emit('close')
}
</script>

<template>
  <Modal :title="title" @close="emit('close')">
    <p class="lead">
      <template v-if="change.kind === 'first'">
        Задачи есть и на этом устройстве, и на сервере.
      </template>
      <template v-else>Базу на сервере пересоздали, или это другой сервер.</template>
      Синхронизация на паузе, пока вы не решите, что делать с данными.
    </p>
    <dl class="counts">
      <dt>На сервере</dt>
      <dd>{{ describe(change.server) }}</dd>
      <dt>На этом устройстве</dt>
      <dd>{{ describe(change.local) }}</dd>
    </dl>
    <div class="choices">
      <button class="choice primary" type="button" :disabled="!!busy" @click="choose('server')">
        <strong>{{ busy === 'server' ? 'Загружаю…' : 'Взять данные сервера' }}</strong>
        <span>Данные этого устройства удалятся, загрузятся серверные.</span>
      </button>
      <button class="choice" type="button" :disabled="!!busy" @click="choose('merge')">
        <strong>{{ busy === 'merge' ? 'Отправляю…' : 'Объединить' }}</strong>
        <span>Данные этого устройства добавятся к серверным.</span>
      </button>
    </div>

    <template #footer>
      <button class="btn ghost" type="button" :disabled="!!busy" @click="emit('close')">Решить позже</button>
    </template>
  </Modal>
</template>

<style scoped>
.lead {
  margin: 0;
  font-size: 15px;
}
.counts {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 4px 14px;
  margin: 0;
  padding: 10px 12px;
  border-radius: 10px;
  background: var(--surface-2);
  font-size: 14px;
}
.counts dt {
  color: var(--muted);
}
.counts dd {
  margin: 0;
  font-weight: 600;
}
.choices {
  display: grid;
  gap: 8px;
}
.choice {
  display: grid;
  gap: 2px;
  text-align: left;
  border: 1px solid var(--line);
  background: var(--surface);
  color: var(--fg);
  border-radius: 12px;
  padding: 10px 14px;
}
.choice:hover {
  background: var(--surface-2);
}
.choice span {
  font-size: 13px;
  color: var(--muted);
}
.choice.primary {
  border-color: var(--accent);
}
.choice.primary strong {
  color: var(--accent);
}
.choice:disabled {
  opacity: 0.6;
  cursor: default;
}
.choice:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: 1px;
}
</style>
