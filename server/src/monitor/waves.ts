/// What a wave can contain, derived from the game's own wave formula.
///
/// DESIGN NOTE: an earlier design replayed the game's seeded RNG stream to derive the exact
/// wave composition. That was abandoned deliberately. `startWave` in the game draws from the
/// same stream for the modifier, every enemy type, the flavour message, seven pickup positions
/// and a jitter value per pickup - and enemy spawning draws more still. Any change to the game
/// shifts the stream and the monitor would start rejecting honest runs.
///
/// Instead we compute an UPPER BOUND, which needs no RNG at all: the only random input to the
/// wave size is whether the SWARM modifier rolled, so assuming it always did gives a sound
/// ceiling. That is what a plausibility check actually needs - a player cannot kill more enemies
/// than could possibly have spawned.
///
/// Mirrors startWave() in game/doodleshooter/src/main.js.

const SWARM_MULTIPLIER = 1.35;

export function isBossWave(wave: number): boolean {
  return wave > 0 && wave % 5 === 0;
}

/// The largest enemy count wave `n` could possibly queue.
export function maxEnemiesInWave(wave: number): number {
  if (wave <= 0) return 0;
  if (isBossWave(wave)) return 7 + wave + 1; // +1 for the boss itself
  return Math.round(Math.min(5 + wave * 2.0, 32 + wave) * SWARM_MULTIPLIER);
}

/// The largest crowd that can be alive at once, which bounds how fast a wave can be cleared.
export function maxAliveInWave(wave: number): number {
  if (wave <= 0) return 0;
  const base = Math.min(4 + Math.floor(wave * 0.9) + 3, 22 + Math.floor(wave / 3));
  return isBossWave(wave) ? base + 2 + Math.floor(wave / 5) : base;
}

/// A floor on how long clearing a wave can take. Spawn cadence in the game is
/// `max(0.7, 2.9 - wave * 0.13)` seconds between spawns, and every enemy must spawn before the
/// wave can end, so the spawn schedule alone sets a hard minimum.
export function minSecondsForWave(wave: number): number {
  if (wave <= 0) return 0;
  const spawnInterval = Math.max(0.7, 2.9 - wave * 0.13);
  const enemies = maxEnemiesInWave(wave);
  // Be generous: assume the fastest possible clear is one spawn interval per enemy beyond the
  // first screenful, with a small floor so wave 1 is not rejected outright.
  return Math.max(3, (enemies - maxAliveInWave(wave)) * spawnInterval);
}
