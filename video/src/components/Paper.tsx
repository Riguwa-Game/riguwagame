import React from 'react';
import { AbsoluteFill } from 'remotion';
import { C } from '../theme';

/** The page everything sits on: ruled lines and a red margin, same as the game. */
export const Paper: React.FC<{ children?: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill
    style={{
      backgroundColor: C.paper,
      backgroundImage: `repeating-linear-gradient(${C.paper} 0 47px, ${C.rule} 47px 49px)`,
    }}
  >
    <div style={{ position: 'absolute', left: 118, top: 0, bottom: 0, width: 3, background: C.margin }} />
    {children}
  </AbsoluteFill>
);
