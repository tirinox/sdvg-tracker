// Labels for dates, timing, deadlines and reasons, in the interface language.
import type { LocalDate, LocalDateTime, PartOfDay, Priority } from '../core/types'
import { addDays, daysBetween, minutesBetween } from '../domain/dates'
import type { Adherence } from '../domain/routines'
import { lang, plural, tr, trn, type Lang } from './i18n'
import type { DayGroupId, DayItem, Section } from './views'

export { plural }

const utc = (d: LocalDate) => new Date(`${d}T12:00:00Z`)

function formatters(l: Lang) {
  const f = (o: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat(l, { ...o, timeZone: 'UTC' })
  return {
    dayMonth: f({ day: 'numeric', month: 'long' }),
    weekday: f({ weekday: 'long' }),
    short: f({ day: 'numeric', month: 'short' }),
    month: f({ month: 'short' }),
  }
}
const FORMATTERS = { ru: formatters('ru'), en: formatters('en') }
const fmt = () => FORMATTERS[lang.value]

/** Standalone short month name: «май», «сент» / 'May', 'Sep'. */
export function monthLabel(d: LocalDate): string {
  return fmt().month.format(utc(d)).replace('.', '')
}

export function shortDate(d: LocalDate): string {
  return fmt().short.format(utc(d)).replace('.', '')
}

export function relativeDay(d: LocalDate, today: LocalDate): string | null {
  if (d === today) return tr('Сегодня', 'Today')
  if (d === addDays(today, 1)) return tr('Завтра', 'Tomorrow')
  if (d === addDays(today, -1)) return tr('Вчера', 'Yesterday')
  return null
}

const DAYS: [[string, string, string], [string, string]] = [
  ['день', 'дня', 'дней'],
  ['day', 'days'],
]

/** How far a day is from today: 'завтра', 'через 3 дня', '5 дней назад'. */
export function dayDistance(d: LocalDate, today: LocalDate): string {
  const n = daysBetween(today, d)
  if (n === 0) return tr('сегодня', 'today')
  if (n === 1) return tr('завтра', 'tomorrow')
  if (n === 2) return tr('послезавтра', 'the day after tomorrow')
  if (n === -1) return tr('вчера', 'yesterday')
  if (n === -2) return tr('позавчера', 'the day before yesterday')
  const days = trn(Math.abs(n), ...DAYS)
  return n > 0 ? tr(`через ${days}`, `in ${days}`) : tr(`${days} назад`, `${days} ago`)
}

export function dayTitle(d: LocalDate, today: LocalDate): { title: string; subtitle: string } {
  const wd = fmt().weekday.format(utc(d))
  const dm = fmt().dayMonth.format(utc(d))
  const rel = relativeDay(d, today)
  return rel
    ? { title: rel, subtitle: `${wd}, ${dm}` }
    : { title: wd[0]!.toUpperCase() + wd.slice(1), subtitle: dm }
}

export function partTitle(p: PartOfDay): string {
  switch (p) {
    case 'morning':
      return tr('Утро', 'Morning')
    case 'day':
      return tr('День', 'Afternoon')
    case 'evening':
      return tr('Вечер', 'Evening')
  }
}

export function sectionTitle(s: Section): string {
  return s === 'anytime' ? tr('В любое время', 'Anytime') : partTitle(s)
}

export function groupTitle(g: DayGroupId): string {
  return g === 'done' ? tr('Сделано', 'Done') : sectionTitle(g)
}

export function durationLabel(min: number | null): string {
  if (!min) return ''
  if (min < 60) return tr(`${min} мин`, `${min} min`)
  const h = Math.floor(min / 60)
  const m = min % 60
  return m ? tr(`${h} ч ${m} мин`, `${h} h ${m} min`) : tr(`${h} ч`, `${h} h`)
}

/** A running countdown, like a timer: '7:48:12', under an hour '47:12'. */
export function countdownLabel(seconds: number): string {
  const s = Math.max(0, Math.round(seconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const ss = String(s % 60).padStart(2, '0')
  return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`
}

export function timingLabel(i: Pick<DayItem, 'time_kind' | 'part_of_day' | 'time' | 'duration_min'>): string {
  const dur = durationLabel(i.duration_min)
  if (i.time_kind === 'exact' && i.time) return dur ? `${i.time} · ${dur}` : i.time
  if (i.time_kind === 'part' && i.part_of_day) {
    return dur ? `${partTitle(i.part_of_day)} · ${dur}` : partTitle(i.part_of_day)
  }
  return dur
}

export function deadlineLabel(i: Pick<DayItem, 'deadline' | 'deadline_date' | 'deadline_time'>, today: LocalDate): string {
  if (i.deadline === 'none' || !i.deadline_date) return ''
  const time = i.deadline_time ? tr(` до ${i.deadline_time}`, ` by ${i.deadline_time}`) : ''
  if (i.deadline === 'overdue') {
    const late = daysBetween(i.deadline_date, today)
    return late > 0
      ? tr(`просрочено на ${trn(late, ...DAYS)}`, `${trn(late, ...DAYS)} overdue`)
      : tr(`просрочено${time}`, `overdue${time}`)
  }
  if (i.deadline === 'today') return tr(`дедлайн сегодня${time}`, `due today${time}`)
  const left = daysBetween(today, i.deadline_date)
  if (left === 1) return tr(`дедлайн завтра${time}`, `due tomorrow${time}`)
  return tr(`дедлайн через ${trn(left, ...DAYS)}`, `due in ${trn(left, ...DAYS)}`)
}

export function movesLabel(n: number): string {
  return trn(n, ['перенос', 'переноса', 'переносов'], ['move', 'moves'])
}

/** Where a routine's percent comes from: «сделано 5 из 8 дней с 5 сент». */
export function adherenceLabel(a: Adherence): string {
  const from = a.from ? shortDate(a.from) : ''
  return tr(
    `сделано ${a.done} из ${a.total} ${plural(a.total, 'дня', 'дней', 'дней')}${from ? ` с ${from}` : ''}`,
    `done ${a.done} of ${a.total} ${a.total === 1 ? 'day' : 'days'}${from ? ` since ${from}` : ''}`,
  )
}

/** Short "why is this here" hints for the Now screen. */
export function reasonLabels(i: DayItem, now: LocalDateTime, today: LocalDate): string[] {
  const out: string[] = []
  if (i.reasons.includes('now')) {
    if (i.time_kind === 'exact' && i.time) {
      let mins = Math.round(minutesBetween(now, `${today}T${i.time}`))
      if (mins < -12 * 60) mins += 24 * 60 // times after midnight belong to the same logical day
      out.push(
        mins > 0
          ? tr(`⏰ через ${mins} мин`, `⏰ in ${mins} min`)
          : mins === 0
            ? tr('⏰ сейчас', '⏰ now')
            : tr(`⏰ идёт ${-mins} мин`, `⏰ started ${-mins} min ago`),
      )
    } else {
      out.push(tr('🕐 самое время', '🕐 good time for it'))
    }
  }
  if (i.reasons.includes('deadline')) out.push(`🔥 ${deadlineLabel(i, today)}`)
  if (i.reasons.includes('postponed')) out.push(`↻ ${movesLabel(i.moves)}`)
  return out
}

/** Short weekday names, Monday first (bit 0 of a weekday mask). */
export function weekdayNames(): string[] {
  return lang.value === 'ru' ? ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'] : ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
}

export function weekdaysLabel(mask: number): string {
  if (mask === 127) return tr('каждый день', 'every day')
  if (mask === 0b0011111) return tr('по будням', 'on weekdays')
  if (mask === 0b1100000) return tr('по выходным', 'on weekends')
  return weekdayNames()
    .filter((_, i) => mask & (1 << i))
    .join(', ')
}

/** "!! важно": the tag of a high-priority item. */
export function priorityTag(): string {
  return tr('!! важно', '!! important')
}

export function priorityTitle(p: Priority): string {
  if (p === 'high') return tr('Высокий', 'High')
  if (p === 'low') return tr('Низкий', 'Low')
  return tr('Обычный', 'Normal')
}

/**
 * Inline style of a row with a priority: its color for the stripe, tag and pulse, and a pulse
 * delay picked from the id, so neighbouring rows do not pulse in step.
 */
export function priorityStyle(id: string, color: number): Record<string, string> {
  let h = 0
  for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) >>> 0
  return { '--c': `var(--c${color})`, '--pulse-delay': `${-(h % 7) * 0.5}s` }
}
