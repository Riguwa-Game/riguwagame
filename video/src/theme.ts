/** The video borrows the game's own palette: ballpoint on lined paper. */
export const C = {
  paper: '#f4efe2',
  paperDeep: '#ece5d4',
  ink: '#1e37c8',
  inkSoft: 'rgba(30,55,200,0.55)',
  dark: '#14213d',
  red: '#c0392b',
  rule: '#b9c7e8',
  margin: '#e8a0a0',
} as const;

export const FPS = 30;
export const W = 1920;
export const H = 1080;

/** Scene boundaries in frames. Narration length drives these, not the other way round. */
export const SCENES = {
  title:   { from: 0,    dur: 225 },
  problem: { from: 225,  dur: 405 },
  game:    { from: 630,  dur: 390 },
  stake:   { from: 1020, dur: 450 },
  seed:    { from: 1470, dur: 420 },
  death:   { from: 1890, dur: 390 },
  settle:  { from: 2280, dur: 270 },
  attest:  { from: 2550, dur: 630 },
  close:   { from: 3180, dur: 270 },
} as const;

export const TOTAL = SCENES.close.from + SCENES.close.dur;
