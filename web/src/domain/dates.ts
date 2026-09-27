// Calendar arithmetic on local 'YYYY-MM-DD' strings. Uses UTC internally so DST never shifts days.
import type { LocalDate, LocalDateTime, PartOfDay, Settings } from '../core/types'

const DAY_MS = 86_400_000

function utcMs(date: LocalDate, time = '00:00'): number {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number]
  const [hh, mm] = time.split(':').map(Number) as [number, number]
  return Date.UTC(y, m - 1, d, hh, mm)
}

function pad(n: number, width = 2): string {
  return String(n).padStart(width, '0')
}

export function addDays(date: LocalDate, days: number): LocalDate {
  return new Date(utcMs(date) + days * DAY_MS).toISOString().slice(0, 10)
}

/** Whole days from `from` to `to` (negative if `to` is earlier). */
export function daysBetween(from: LocalDate, to: LocalDate): number {
  return Math.round((utcMs(to) - utcMs(from)) / DAY_MS)
}

/** 0 = Monday ... 6 = Sunday. */
export function weekdayIndex(date: LocalDate): number {
  return (new Date(utcMs(date)).getUTCDay() + 6) % 7
}

export function minutesBetween(from: LocalDateTime, to: LocalDateTime): number {
  const ms = (v: LocalDateTime) => utcMs(v.slice(0, 10), v.slice(11, 16))
  return (ms(to) - ms(from)) / 60_000
}

/** Current local wall-clock moment as 'YYYY-MM-DDTHH:MM'. */
export function localNow(d: Date = new Date()): LocalDateTime {
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}`
  )
}

export function hourOf(now: LocalDateTime): number {
  return Number(now.slice(11, 13))
}

/** Logical today = local date of (now - day_start_hour): at 01:30 it is still yesterday. */
export function logicalDay(now: LocalDateTime, dayStartHour: number): LocalDate {
  const date = now.slice(0, 10)
  return hourOf(now) < dayStartHour ? addDays(date, -1) : date
}

/** The logical day `date` ends at day_start_hour on the next calendar date, not at midnight. */
export function dayEnd(date: LocalDate, dayStartHour: number): LocalDateTime {
  return `${addDays(date, 1)}T${pad(dayStartHour)}:00`
}

export type DayEndLevel = 'calm' | 'soon' | 'urgent'

/** How close the end of the day is: the last hour is 'soon', the last half hour 'urgent'. */
export function dayEndLevel(secondsLeft: number): DayEndLevel {
  if (secondsLeft <= 30 * 60) return 'urgent'
  if (secondsLeft <= 60 * 60) return 'soon'
  return 'calm'
}

/** The real moment of a local wall-clock time, in this device's time zone. */
export function instantOf(v: LocalDateTime): Date {
  const [y, m, d] = v.slice(0, 10).split('-').map(Number) as [number, number, number]
  const [hh, mm] = v.slice(11, 16).split(':').map(Number) as [number, number]
  return new Date(y, m - 1, d, hh, mm)
}

/** Evening lasts until day_start_hour; from day_start_hour until part_day_from it is morning. */
export function partOfDay(now: LocalDateTime, s: Settings): PartOfDay {
  const h = hourOf(now)
  if (h >= s.part_evening_from || h < s.day_start_hour) return 'evening'
  if (h >= s.part_day_from) return 'day'
  return 'morning'
}
