import React from 'react';
import { AbsoluteFill, useCurrentFrame, interpolate, spring, useVideoConfig, Easing } from 'remotion';
import { C } from '../theme';

type Props = { from: [number, number]; to: [number, number]; travel: [number, number]; clickAt: number };

/**
 * A cursor that travels to a control and clicks it, with a ring that pops on the click.
 * This is the effect Cursorful sells; doing it here means the keyframes are ours and
 * the footage underneath stays untouched.
 */
export const Cursor: React.FC<Props> = ({ from, to, travel, clickAt }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = interpolate(f, travel, [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.cubic) });
  const x = from[0] + (to[0] - from[0]) * p;
  const y = from[1] + (to[1] - from[1]) * p;
  const ring = spring({ frame: f - clickAt, fps, config: { damping: 14, mass: 0.5 } });
  const showRing = f >= clickAt && f < clickAt + 40;
  const fade = interpolate(f, [travel[0] - 10, travel[0]], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });

  return (
    <AbsoluteFill style={{ opacity: fade }}>
      {showRing && (
        <div
          style={{
            position: 'absolute', left: x, top: y, width: 120, height: 120, marginLeft: -60, marginTop: -60,
            borderRadius: '50%', border: `4px solid ${C.red}`,
            transform: `scale(${0.2 + ring * 1.1})`, opacity: 1 - ring,
          }}
        />
      )}
      <svg width="46" height="58" viewBox="0 0 24 30" style={{ position: 'absolute', left: x, top: y, filter: 'drop-shadow(0 3px 5px rgba(0,0,0,0.35))' }}>
        <path d="M2 2 L2 22 L7.5 17.5 L11 26 L14.5 24.5 L11 16.5 L18 16 Z" fill={C.paper} stroke={C.dark} strokeWidth="1.8" strokeLinejoin="round" />
      </svg>
    </AbsoluteFill>
  );
};
