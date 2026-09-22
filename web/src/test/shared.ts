import { readdirSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

export const SHARED_DIR = fileURLToPath(new URL('../../../shared/', import.meta.url))

// Fixtures are loosely typed JSON: each test file narrows the shapes it needs.
export type Json = any

export function loadShared(rel: string): Json {
  return JSON.parse(readFileSync(SHARED_DIR + rel, 'utf8'))
}

export function sharedFiles(dir: string): string[] {
  return readdirSync(SHARED_DIR + dir)
    .filter((f) => f.endsWith('.json'))
    .sort()
}

export interface Case<I = Json, E = Json> {
  name: string
  input: I
  expect: E
}

export function domainCases<I = Json, E = Json>(kind: string): Case<I, E>[] {
  return loadShared(`domain-fixtures/${kind}.json`).cases
}
