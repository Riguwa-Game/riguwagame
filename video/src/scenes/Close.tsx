import React from 'react';
import { AbsoluteFill, Img, staticFile, useCurrentFrame, useVideoConfig, spring, interpolate, Easing } from 'remotion';
import { Paper } from '../components/Paper';
import { C } from '../theme';

const FACTS = ['9 contracts, source verified', '186 tests passing', 'Creditcoin Testnet 102031'];

export const Close: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const logo = spring({ frame: f, fps, config: { damping: 200 } });
  const line = spring({ frame: f - 12, fps, config: { damping: 200 } });
  const url = interpolate(f, [60, 78], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.ease) });

  return (
    <Paper>
      <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center', textAlign: 'center' }}>
        <Img src={staticFile('logo.png')} style={{ width: 150, opacity: logo }} />
        <div style={{ fontSize: 76, color: C.ink, marginTop: 16, lineHeight: 1.15, opacity: line, transform: `translateY(${(1 - line) * 14}px)` }}>
          The chain decides what happened.<br />Not the server. Not us.
        </div>
        <div style={{ display: 'flex', gap: 18, marginTop: 40 }}>
          {FACTS.map((t, i) => {
            const a = spring({ frame: f - (34 + i * 12), fps, config: { damping: 200 } });
            return (
              <div key={t} style={{ opacity: a, transform: `translateY(${(1 - a) * 12}px)`, border: `2.5px solid ${C.ink}`, borderRadius: 26, padding: '7px 22px', fontSize: 30, color: C.ink }}>
                {t}
              </div>
            );
          })}
        </div>
        <div style={{ fontSize: 62, color: C.ink, marginTop: 44, opacity: url }}>riguwa.xyz</div>
        <div style={{ fontSize: 26, color: C.dark, opacity: url * 0.75, marginTop: 10 }}>
          github.com/Riguwa-Game/riguwagame
        </div>
        <div style={{ position: 'absolute', bottom: 26, fontSize: 19, color: C.dark, opacity: url * 0.55 }}>
          Music: "Inspired" by Kevin MacLeod (incompetech.com), licensed CC BY 4.0
        </div>
      </AbsoluteFill>
    </Paper>
  );
};
