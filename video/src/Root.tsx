import React from 'react';
import { Composition } from 'remotion';
import { loadFont } from '@remotion/google-fonts/PatrickHand';
import { Demo } from './Demo';
import { FPS, W, H, TOTAL } from './theme';

loadFont();

export const RemotionRoot: React.FC = () => (
  <Composition id="Demo" component={Demo} durationInFrames={TOTAL} fps={FPS} width={W} height={H} />
);
