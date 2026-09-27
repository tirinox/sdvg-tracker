// Russian labels for dates, timing, deadlines and reasons.
import type { LocalDate, LocalDateTime, PartOfDay } from '../core/types'
import { addDays, daysBetween, minutesBetween } from '../domain/dates'
import type { DayGroupId, DayItem, Section } from './views'

export function plural(n: number, one: string, few: string, many: string): string {
  const m10 = n % 10
  const m100 = n % 100
  if (m10 === 1 && m100 !== 11) return one
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few
  return many
}

const utc = (d: LocalDate) => new Date(`${d}T12:00:00Z`)
const dayMonth = new Intl.DateTimeFormat('ru', { day: 'numeric', month: 'long', timeZone: 'UTC' })
const weekday = new Intl.DateTimeFormat('ru', { weekday: 'long', timeZone: 'UTC' })
const short = new Intl.DateTimeFormat('ru', { day: 'numeric', month: 'short', timeZone: 'UTC' })

const monthShort = new Intl.DateTimeFormat('ru', { month: 'short', timeZone: 'UTC' })

/** Standalone short month name: «май», «сент». */
export function monthLabel(d: LocalDate): string {
  return monthShort.format(utc(d)).replace('.', '')
}

export function shortDate(d: LocalDate): string {
  return short.format(utc(d)).replace('.', '')
}

export function relativeDay(d: LocalDate, today: LocalDate): string | null {
  if (d === today) return 'Сегодня'
  if (d === addDays(today, 1)) return 'Завтра'
  if (d === addDays(today, -1)) return 'Вчера'
  return null
}

export function dayTitle(d: LocalDate, today: LocalDate): { title: string; subtitle: string } {
  const wd = weekday.format(utc(d))
  const dm = dayMonth.format(utc(d))
  const rel = relativeDay(d, today)
  return rel
    ? { title: rel, subtitle: `${wd}, ${dm}` }
    : { title: wd[0]!.toUpperCase() + wd.slice(1), subtitle: dm }
}

export const SECTION_TITLES: Record<Section, string> = {
  anytime: 'В любое время',
  morning: 'Утро',
  day: 'День',
  evening: 'Вечер',
}

export const GROUP_TITLES: Record<DayGroupId, string> = { ...SECTION_TITLES, done: 'Сделано' }

export const PART_TITLES: Record<PartOfDay, string> = {
  morning: 'Утро',
  day: 'День',
  evening: 'Вечер',
}

export function durationLabel(min: number | null): string {
  if (!min) return ''
  if (min < 60) return `${min} мин`
  const h = Math.floor(min / 60)
  const m = min % 60
  return m ? `${h} ч ${m} мин` : `${h} ч`
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
    return dur ? `${PART_TITLES[i.part_of_day]} · ${dur}` : PART_TITLES[i.part_of_day]
  }
  return dur
}

export function deadlineLabel(i: Pick<DayItem, 'deadline' | 'deadline_date' | 'deadline_time'>, today: LocalDate): string {
  if (i.deadline === 'none' || !i.deadline_date) return ''
  const time = i.deadline_time ? ` до ${i.deadline_time}` : ''
  if (i.deadline === 'overdue') {
    const late = daysBetween(i.deadline_date, today)
    return late > 0 ? `просрочено на ${late} ${plural(late, 'день', 'дня', 'дней')}` : `просрочено${time}`
  }
  if (i.deadline === 'today') return `дедлайн сегодня${time}`
  const left = daysBetween(today, i.deadline_date)
  if (left === 1) return `дедлайн завтра${time}`
  return `дедлайн через ${left} ${plural(left, 'день', 'дня', 'дней')}`
}

export function movesLabel(n: number): string {
  return `${n} ${plural(n, 'перенос', 'переноса', 'переносов')}`
}

/** Short "why is this here" hints for the Now screen. */
export function reasonLabels(i: DayItem, now: LocalDateTime, today: LocalDate): string[] {
  const out: string[] = []
  if (i.reasons.includes('now')) {
    if (i.time_kind === 'exact' && i.time) {
      let mins = Math.round(minutesBetween(now, `${today}T${i.time}`))
      if (mins < -12 * 60) mins += 24 * 60 // times after midnight belong to the same logical day
      out.push(
        mins > 0 ? `⏰ через ${mins} мин` : mins === 0 ? '⏰ сейчас' : `⏰ идёт ${-mins} мин`,
      )
    } else {
      out.push('🕐 самое время')
    }
  }
  if (i.reasons.includes('deadline')) out.push(`🔥 ${deadlineLabel(i, today)}`)
  if (i.reasons.includes('postponed')) out.push(`↻ ${movesLabel(i.moves)}`)
  return out
}

const WEEKDAYS = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс']

export function weekdaysLabel(mask: number): string {
  if (mask === 127) return 'каждый день'
  if (mask === 0b0011111) return 'по будням'
  if (mask === 0b1100000) return 'по выходным'
  return WEEKDAYS.filter((_, i) => mask & (1 << i)).join(', ')
}

export { WEEKDAYS }
