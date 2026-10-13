import { expect, test } from 'claude-code/testing'

import { elapsedText, isKnownStart } from '../hooks/session'

const NOW = Date.parse('2026-10-13T12:00:00Z')
const STARTED = Date.parse('2026-10-13T09:31:27Z')
const fmt = (ms: number) => `${Math.round(ms / 1000)}s`

test('times the session from a known start', async () => {
  expect(isKnownStart(STARTED)).toBe(true)
  expect(elapsedText(STARTED, STARTED + 5000, fmt)).toBe('5s')
})

test('never times the session from 1970: an unknown or 0 start shows -', async () => {
  expect(isKnownStart(0)).toBe(false)
  expect(isKnownStart(undefined)).toBe(false)
  expect(elapsedText(0, NOW, fmt)).toBe('-')
  expect(elapsedText(undefined, NOW, fmt)).toBe('-')
  // Before the clock tick has run, now is 0.
  expect(elapsedText(STARTED, 0, fmt)).toBe('-')
})
