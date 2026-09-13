import React from 'react';
import { AbsoluteFill, useCurrentFrame, interpolate, Easing } from 'remotion';
import { C } from '../theme';

/**
 * Lower third. Most people watch a demo muted the first time, so the claim has to
 * survive without the narration.
 */
export const Caption: React.FC<{ lines: string[]; at?: number }> = ({ lines, at = 10 }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [at, at + 14], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.ease) });
  const y = interpolate(f, [at, at + 14], [18, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic) });
  return (
    <AbsoluteFill style={{ justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 54 }}>
      <div style={{ opacity: o, transform: `translateY(${y}px)`, textAlign: 'center', maxWidth: 1500 }}>
        {lines.map((l, i) => (
          <div
            key={i}
            style={{
              display: 'inline-block',
              background: 'rgba(244,239,226,0.94)',
              border: `2.5px solid ${C.ink}`,
              borderRadius: 12,
              padding: '8px 22px',
              margin: '5px 6px',
              color: i === 0 ? C.ink : C.dark,
              fontSize: i === 0 ? 42 : 34,
              lineHeight: 1.25,
            }}
          >
            {l}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};
