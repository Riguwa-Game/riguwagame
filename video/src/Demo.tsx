import React from 'react';
import { AbsoluteFill, Audio, Sequence, staticFile, useCurrentFrame, interpolate } from 'remotion';
import { Paper } from './components/Paper';
import { Screen } from './components/Screen';
import { Caption } from './components/Caption';
import { Cursor } from './components/Cursor';
import { Title } from './scenes/Title';
import { Problem } from './scenes/Problem';
import { Close } from './scenes/Close';
import { SCENES as S, TOTAL, C } from './theme';

/** Footage scene: paper, framed clip, caption. Kept in one place so every scene matches. */
const Shot: React.FC<{
  src: string; dur: number; lines: string[]; zoomFrom?: number; zoomTo?: number;
  focus?: [number, number]; image?: boolean; startFrom?: number; children?: React.ReactNode;
}> = ({ src, dur, lines, zoomFrom, zoomTo, focus, image, startFrom, children }) => (
  <Paper>
    <Screen src={src} dur={dur} zoomFrom={zoomFrom} zoomTo={zoomTo} focus={focus} image={image} startFrom={startFrom} />
    {children}
    <Caption lines={lines} />
  </Paper>
);

/** One narration file per scene, so retiming a scene never desyncs the rest. */
const VO: React.FC<{ file: string }> = ({ file }) => (
  <Audio src={staticFile(file)} volume={1} />
);

export const Demo: React.FC = () => {
  const f = useCurrentFrame();
  // Music sits under the narration and gets out of the way at the end.
  const musicVol = interpolate(f, [0, 60, TOTAL - 120, TOTAL - 20], [0, 0.16, 0.16, 0], {
    extrapolateLeft: 'clamp', extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill style={{ backgroundColor: C.paper, fontFamily: '"Patrick Hand", "Comic Sans MS", "Marker Felt", sans-serif' }}>
      <Audio src={staticFile('music.mp3')} volume={musicVol} />

      <Sequence from={S.title.from} durationInFrames={S.title.dur} premountFor={30}>
        <Title />
        <VO file="01-title.wav" />
      </Sequence>

      <Sequence from={S.problem.from} durationInFrames={S.problem.dur} premountFor={30}>
        <Problem />
        <VO file="02-problem.wav" />
      </Sequence>

      <Sequence from={S.game.from} durationInFrames={S.game.dur} premountFor={30}>
        <Shot src="combat1.mp4" dur={S.game.dur} zoomTo={1.1} focus={[50, 45]}
              lines={['Rendered entirely in code', 'No models. No textures. No sound files.']} />
        <VO file="03-game.wav" />
      </Sequence>

      <Sequence from={S.stake.from} durationInFrames={S.stake.dur} premountFor={30}>
        <Shot src="staking.mp4" dur={S.stake.dur} zoomTo={1.14} focus={[50, 42]}
              lines={['Every run is staked', 'startRun reserves the 3x ceiling before it takes your money']}>
          <Cursor from={[1180, 470]} to={[960, 560]} travel={[120, 210]} clickAt={215} />
        </Shot>
        <VO file="04-stake.wav" />
      </Sequence>

      <Sequence from={S.seed.from} durationInFrames={S.seed.dur} premountFor={30}>
        <Shot src="combat2.mp4" dur={S.seed.dur} zoomTo={1.1} focus={[50, 50]}
              lines={['The seed comes from blockhash', 'The waves were committed before the first enemy spawned']} />
        <VO file="05-seed.wav" />
      </Sequence>

      <Sequence from={S.death.from} durationInFrames={S.death.dur} premountFor={30}>
        <Shot src="death.mp4" dur={S.death.dur} zoomTo={1.12} focus={[50, 46]} startFrom={150}
              lines={['Wave 2. Below wave 5 the stake joins the pool.', 'Settled on-chain, by the monitor, with nobody asked']} />
        <VO file="06-death.wav" />
      </Sequence>

      <Sequence from={S.settle.from} durationInFrames={S.settle.dur} premountFor={30}>
        {/* Cropped to the header. Blockscout sells a sponsor slot mid-page and the
            current buyer is a gambling ad, which has no business in this video. */}
        <Shot src="settle.mp4" dur={S.settle.dur} zoomFrom={1.80} zoomTo={1.90} focus={[34, 16]}
              lines={['The settlement, on Blockscout']} />
        <VO file="07-settle.wav" />
      </Sequence>

      <Sequence from={S.attest.from} durationInFrames={S.attest.dur} premountFor={30}>
        <Sequence durationInFrames={190}>
          <Shot src="relay.mp4" dur={190} zoomTo={1.05} focus={[50, 30]}
                lines={['Entry paid on Ethereum Sepolia', 'Verified inside the same Creditcoin transaction']} />
        </Sequence>
        <Sequence from={190} durationInFrames={S.attest.dur - 190}>
          <Shot src="attestcoin-proof.png" image dur={S.attest.dur - 190} zoomTo={1.18} focus={[42, 34]}
                lines={['First log: TransactionVerified', 'Emitted by the BlockProver precompile, not by us']} />
        </Sequence>
        <VO file="08-attest.wav" />
      </Sequence>

      <Sequence from={S.close.from} durationInFrames={S.close.dur} premountFor={30}>
        <Close />
        <VO file="09-close.wav" />
      </Sequence>
    </AbsoluteFill>
  );
};
