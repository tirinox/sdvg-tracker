<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { tr } from '../app/i18n'

defineProps<{ title: string }>()
const emit = defineEmits<{ close: [] }>()
const dialog = ref<HTMLDialogElement>()

onMounted(() => dialog.value?.showModal())
</script>

<template>
  <dialog ref="dialog" class="modal" @close="emit('close')" @click.self="dialog?.close()">
    <form class="body" method="dialog" @submit.prevent>
      <header>
        <h2>{{ title }}</h2>
        <button class="btn ghost" type="button" :aria-label="tr('Закрыть', 'Close')" @click="dialog?.close()">✕</button>
      </header>
      <slot />
      <footer><slot name="footer" /></footer>
    </form>
  </dialog>
</template>

<style scoped>
.modal {
  border: 0;
  padding: 0;
  border-radius: 18px;
  width: min(560px, calc(100vw - 24px));
  max-height: calc(100dvh - 24px);
  background: var(--surface);
  color: var(--fg);
  box-shadow: 0 20px 60px rgb(0 0 0 / 25%);
}
.modal::backdrop {
  background: rgb(20 18 30 / 45%);
}
.body {
  display: grid;
  gap: 14px;
  padding: 18px;
}
header,
footer {
  display: flex;
  align-items: center;
  gap: 8px;
}
header {
  justify-content: space-between;
}
h2 {
  font-size: 18px;
}
footer {
  flex-wrap: wrap;
  justify-content: flex-end;
  padding-top: 4px;
}
</style>
