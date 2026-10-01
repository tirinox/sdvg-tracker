<script setup lang="ts">
import { computed, ref } from 'vue'
import { useApp } from '../app/context'
import { tr, trn } from '../app/i18n'
import type { Counts, ServerChange } from '../sync/client'
import Modal from './Modal.vue'

const props = defineProps<{ change: ServerChange }>()
const emit = defineEmits<{ close: [] }>()
const { sync } = useApp()
const busy = ref<'server' | 'merge' | null>(null)

const title = computed(() =>
  props.change.kind === 'first'
    ? tr('На сервере уже есть данные', 'The server already has data')
    : tr('Данные на сервере сменились', 'The data on the server has changed'),
)

function describe(c: Counts): string {
  if (c.task + c.routine === 0) return tr('пусто', 'empty')
  return [
    trn(c.task, ['задача', 'задачи', 'задач'], ['task', 'tasks']),
    trn(c.routine, ['рутина', 'рутины', 'рутин'], ['routine', 'routines']),
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
        {{
          tr('Задачи есть и на этом устройстве, и на сервере.', 'There are tasks both on this device and on the server.')
        }}
      </template>
      <template v-else>
        {{
          tr(
            'Базу на сервере пересоздали, или это другой сервер.',
            'The server database was recreated, or this is a different server.',
          )
        }}
      </template>
      {{
        tr(
          'Синхронизация на паузе, пока вы не решите, что делать с данными.',
          'Sync is paused until you decide what to do with the data.',
        )
      }}
    </p>
    <dl class="counts">
      <dt>{{ tr('На сервере', 'On the server') }}</dt>
      <dd>{{ describe(change.server) }}</dd>
      <dt>{{ tr('На этом устройстве', 'On this device') }}</dt>
      <dd>{{ describe(change.local) }}</dd>
    </dl>
    <div class="choices">
      <button class="choice primary" type="button" :disabled="!!busy" @click="choose('server')">
        <strong>
          {{ busy === 'server' ? tr('Загружаю…', 'Downloading…') : tr('Взять данные сервера', 'Use the server’s data') }}
        </strong>
        <span>
          {{
            tr(
              'Данные этого устройства удалятся, загрузятся серверные.',
              'The data on this device is deleted and the server’s data is downloaded.',
            )
          }}
        </span>
      </button>
      <button class="choice" type="button" :disabled="!!busy" @click="choose('merge')">
        <strong>{{ busy === 'merge' ? tr('Отправляю…', 'Uploading…') : tr('Объединить', 'Merge') }}</strong>
        <span>
          {{ tr('Данные этого устройства добавятся к серверным.', 'The data on this device is added to the server’s.') }}
        </span>
      </button>
    </div>

    <template #footer>
      <button class="btn ghost" type="button" :disabled="!!busy" @click="emit('close')">
        {{ tr('Решить позже', 'Decide later') }}
      </button>
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
