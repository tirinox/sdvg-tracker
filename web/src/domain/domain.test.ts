import { describe, expect, it } from 'vitest'
import { domainCases, sharedFiles, type Case, type Json } from '../test/shared'
import { dayEnd, dayEndLevel, logicalDay, minutesBetween, partOfDay } from './dates'
import { dayRecord, dayStats, heatmapGrid, heatmapLevels, streak } from './progress'
import { routineAdherence, routinesForDay } from './routines'
import { nowScore } from './score'
import { suggestTitles, titleHistory } from './suggest'
import { attentionLevel, celebrationLevel, deadlineStatus, planRollover } from './tasks'

type Runner = (input: Json) => Json

// One adapter per shared/domain-fixtures file: fixture input -> implementation -> expect shape.
const RUNNERS: Record<string, Runner> = {
  logical_day: (i) => ({ date: logicalDay(i.now, i.day_start_hour) }),
  part_of_day: (i) => ({ part: partOfDay(i.now, i.settings) }),
  day_end: (i) => {
    const endsAt = dayEnd(logicalDay(i.now, i.day_start_hour), i.day_start_hour)
    const minutesLeft = minutesBetween(i.now, endsAt)
    return { ends_at: endsAt, minutes_left: minutesLeft, level: dayEndLevel(minutesLeft * 60) }
  },
  routines_for_day: (i) => ({
    versions: Object.fromEntries(
      [...routinesForDay(i.date, i.versions)].map(([rid, v]) => [rid, v.id]).sort(),
    ),
  }),
  routine_adherence: (i) => ({
    routines: Object.fromEntries(routineAdherence(i.today, i.versions, i.checks, i.warn_below)),
  }),
  auto_rollover: (i) => {
    const { moves, dates } = planRollover(i.today, i.tasks)
    return { new_moves: moves, task_dates: dates }
  },
  attention_level: (i) => ({ level: attentionLevel(i.moves, i.thresholds) }),
  celebration_level: (i) => ({ level: celebrationLevel(i.moves) }),
  deadline_status: (i) => ({
    status: deadlineStatus({
      now: i.now,
      dayStartHour: i.day_start_hour,
      createdOn: i.created_on,
      deadlineDate: i.deadline_date,
      deadlineTime: i.deadline_time,
      done: i.done,
    }),
  }),
  day_stats: (i) => dayStats(i.date, i.tasks, i.routine_checks),
  streak: (i) => ({ streak: streak(i.today, i.days, i.streak_min_done) }),
  day_record: (i) => dayRecord(i.today, i.days),
  now_score: (i) => nowScore(i.now, i.settings, i.item),
  heatmap_levels: (i) => ({ levels: heatmapLevels(i.counts) }),
  heatmap_grid: (i) => {
    const days = heatmapGrid(i.today)
    return { first: days[0], last: days.at(-1), days: days.length }
  },
  title_suggestions: (i) => ({
    suggestions: suggestTitles(titleHistory(i.tasks, i.today), i.query, i.limit),
  }),
}

it('every domain fixture file has a runner', () => {
  const kinds = sharedFiles('domain-fixtures').map((f) => f.replace(/\.json$/, ''))
  expect(Object.keys(RUNNERS).sort()).toEqual(kinds)
})

for (const [kind, run] of Object.entries(RUNNERS)) {
  describe(kind, () => {
    it.each<[string, Case]>(domainCases(kind).map((c) => [c.name, c]))('%s', (_name, c) => {
      expect(run(c.input)).toEqual(c.expect)
    })
  })
}
