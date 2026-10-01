// Interface language: Russian (the source) or English, picked in settings or taken from the system.
// Strings stay inline as pairs — tr('Сделано', 'Done') — and follow the language reactively.
import { computed, ref, watchEffect } from 'vue'

export type Lang = 'ru' | 'en'
export type LangPref = 'system' | Lang

const KEY = 'sdvg.lang'

/** Russian for a Russian system, English for everything else. */
function detect(): Lang {
  const langs = typeof navigator === 'undefined' ? [] : navigator.languages ?? [navigator.language]
  return langs[0]?.toLowerCase().startsWith('ru') ? 'ru' : 'en'
}

function load(): LangPref {
  try {
    const v = localStorage.getItem(KEY)
    if (v === 'ru' || v === 'en' || v === 'system') return v
  } catch {
    // Storage may be unavailable (private mode); the system language still works.
  }
  return 'system'
}

const systemLang = ref<Lang>(detect())
if (typeof window !== 'undefined') window.addEventListener('languagechange', () => (systemLang.value = detect()))

/** What the user picked: a language or 'system'. Kept per device, not synced. */
export const langPref = ref<LangPref>(load())

/** The language in effect. */
export const lang = computed<Lang>(() => (langPref.value === 'system' ? systemLang.value : langPref.value))

export function setLangPref(p: LangPref) {
  langPref.value = p
  try {
    localStorage.setItem(KEY, p)
  } catch {
    // Not saved, but applies until reload.
  }
}

if (typeof document !== 'undefined') watchEffect(() => (document.documentElement.lang = lang.value))

/** The string for the current language. */
export function tr(ru: string, en: string): string {
  return lang.value === 'ru' ? ru : en
}

/** Russian plural form: 1 день, 2 дня, 5 дней. */
export function plural(n: number, one: string, few: string, many: string): string {
  const m10 = n % 10
  const m100 = n % 100
  if (m10 === 1 && m100 !== 11) return one
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few
  return many
}

/** The plural word alone, in the current language: trWord(3, ['день', 'дня', 'дней'], ['day', 'days']) → 'дня'. */
export function trWord(n: number, ru: [string, string, string], en: [string, string]): string {
  return lang.value === 'ru' ? plural(n, ...ru) : Math.abs(n) === 1 ? en[0] : en[1]
}

/** A count with its word: trn(3, ['день', 'дня', 'дней'], ['day', 'days']) → '3 дня' / '3 days'. */
export function trn(n: number, ru: [string, string, string], en: [string, string]): string {
  return `${n} ${trWord(n, ru, en)}`
}
