// JS hooks for <TransitionGroup> over list rows: a leaving row slides aside and collapses, so the
// rows below close the gap smoothly instead of jumping; a new row grows into place.

const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches

/** Gap between rows in .list, which the collapsing row gives back via a negative margin. */
const GAP = 8

function animate(el: HTMLElement, frames: Keyframe[], ms: number, fill: FillMode, done: () => void) {
  if (reduced()) return done()
  const a = el.animate(frames, { duration: ms, easing: 'cubic-bezier(0.4, 0, 0.2, 1)', fill })
  a.onfinish = a.oncancel = () => done()
}

function box(el: HTMLElement) {
  const cs = getComputedStyle(el)
  return {
    height: `${el.offsetHeight}px`,
    paddingTop: cs.paddingTop,
    paddingBottom: cs.paddingBottom,
    borderTopWidth: cs.borderTopWidth,
    borderBottomWidth: cs.borderBottomWidth,
    marginBottom: '0px',
  }
}

const COLLAPSED = {
  height: '0px',
  paddingTop: '0px',
  paddingBottom: '0px',
  borderTopWidth: '0px',
  borderBottomWidth: '0px',
  marginBottom: `-${GAP}px`,
}

export function rowLeave(el: Element, done: () => void) {
  const e = el as HTMLElement
  const full = box(e)
  e.style.overflow = 'hidden'
  animate(
    e,
    [
      { ...full, opacity: 1, transform: 'none' },
      { ...full, opacity: 0, transform: 'translateX(24%) scale(0.97)', offset: 0.55 },
      { ...COLLAPSED, opacity: 0, transform: 'translateX(24%) scale(0.97)' },
    ],
    520,
    // Stays collapsed until Vue removes it.
    'forwards',
    done,
  )
}

export function rowEnter(el: Element, done: () => void) {
  const e = el as HTMLElement
  const full = box(e)
  e.style.overflow = 'hidden'
  animate(
    e,
    [
      { ...COLLAPSED, opacity: 0 },
      { ...full, opacity: 0, offset: 0.5 },
      { ...full, opacity: 1 },
    ],
    420,
    // Back to its own height afterwards: the row can still grow (e.g. the "stuck" hint).
    'none',
    () => {
      e.style.overflow = ''
      done()
    },
  )
}
