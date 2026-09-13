import React from 'react';
import { AbsoluteFill, useCurrentFrame, useVideoConfig, spring, interpolate, Easing } from 'remotion';
import { Paper } from '../components/Paper';
import { C } from '../theme';

const LINES = [
  'A leaderboard is a database row.',
  "A payout is a server's word.",
  'Cross-chain entry trusts a bridge operator.',
];

export const Problem: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const head = spring({ frame: f, fps, config: { damping: 200 } });
  const punch = interpolate(f, [250, 275], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic) });

  return (
    <Paper>
      <AbsoluteFill style={{ justifyContent: 'center', paddingLeft: 210, paddingRight: 120 }}>
        <div style={{ fontSize: 68, color: C.ink, lineHeight: 1.15, opacity: head, transform: `translateY(${(1 - head) * 16}px)` }}>
          Web3 games put value on-chain.<br />
          They do not put the reason you earned it on-chain.
        </div>
        <div style={{ marginTop: 46 }}>
          {LINES.map((l, i) => {
            // Staggered, not simultaneous. Everything arriving at once reads as a slide, not a film.
            const a = spring({ frame: f - (70 + i * 40), fps, config: { damping: 200 } });
            return (
              <div key={l} style={{ fontSize: 44, color: C.dark, marginBottom: 16, opacity: a, transform: `translateX(${(1 - a) * -26}px)` }}>
                <span style={{ color: C.red, marginRight: 14 }}>-</span>{l}
              </div>
            );
          })}
        </div>
        <div style={{ marginTop: 44, fontSize: 56, color: C.ink, opacity: punch, transform: `translateY(${(1 - punch) * 14}px)` }}>
          The asset is trustless. The claim behind it is not.
        </div>
      </AbsoluteFill>
    </Paper>
  );
};
