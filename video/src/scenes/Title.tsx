import React from 'react';
import { AbsoluteFill, Img, staticFile, useCurrentFrame, useVideoConfig, spring, interpolate, Easing } from 'remotion';
import { Paper } from '../components/Paper';
import { C } from '../theme';

export const Title: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const logo = spring({ frame: f, fps, config: { damping: 200 } });
  const name = spring({ frame: f - 10, fps, config: { damping: 200 } });
  const tag = interpolate(f, [26, 44], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.ease) });
  const url = interpolate(f, [44, 62], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.ease) });

  return (
    <Paper>
      <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center', textAlign: 'center' }}>
        <Img src={staticFile('logo.png')} style={{ width: 230, opacity: logo, transform: `scale(${0.86 + logo * 0.14})` }} />
        <div style={{ fontSize: 132, color: C.ink, letterSpacing: 4, marginTop: 8, opacity: name, transform: `translateY(${(1 - name) * 18}px)` }}>
          RIGUWA
        </div>
        <div style={{ fontSize: 44, color: C.dark, marginTop: 10, opacity: tag, maxWidth: 1250, lineHeight: 1.3 }}>
          A survival shooter where the reward is real,<br />and the chain proves you earned it before it pays.
        </div>
        <div style={{ fontSize: 38, color: C.ink, marginTop: 40, opacity: url }}>riguwa.xyz</div>
      </AbsoluteFill>
    </Paper>
  );
};
