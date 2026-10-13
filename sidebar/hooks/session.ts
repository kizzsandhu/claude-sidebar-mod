// A session start time worth timing from, epoch ms. A usage reading can land
// before session.start has stored one, and a resumed session can report 0;
// timed from 0, the elapsed time reads as the years since 1970.
export const isKnownStart = (t: number | undefined): t is number => t !== undefined && t > 0

// The elapsed time, or '-' while the start isn't known.
export const elapsedText = (startedAt: number | undefined, now: number, fmt: (ms: number) => string) =>
  isKnownStart(startedAt) && now >= startedAt ? fmt(now - startedAt) : '-'
