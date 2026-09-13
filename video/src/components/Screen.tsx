import React from 'react';
import { AbsoluteFill, OffthreadVideo, Img, useCurrentFrame, interpolate, Easing, staticFile } from 'remotion';
import { C } from '../theme';

type Props = {
  src: string;
  startFrom?: number;
  /** Ken Burns: 1 = no push, 1.12 = a slow 12% push in. */
  zoomTo?: number;
  /** Start already pushed in. Used to crop a page region, eg. past an ad slot. */
  zoomFrom?: number;
  /** Where the push converges, in percent. Doubles as the cursor focus. */
  focus?: [number, number];
  image?: boolean;
  dur: number;
};

/**
 * Footage inside an ink frame, with a slow push. Cursorful sells the push-to-cursor
 * effect as a product; here it is four lines of interpolate, and we control the keyframes.
 */
export const Screen: React.FC<Props> = ({ src, startFrom = 0, zoomFrom = 1, zoomTo = 1.08, focus = [50, 50], image, dur }) => {
  const f = useCurrentFrame();
  const scale = interpolate(f, [0, dur], [zoomFrom, zoomTo], {
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.ease),
  });
  const enter = interpolate(f, [0, 18], [0, 1], { extrapolateRight: 'clamp', easing: Easing.out(Easing.ease) });
  const lift = interpolate(f, [0, 18], [26, 0], { extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic) });

  return (
    <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center', opacity: enter }}>
      <div
        style={{
          width: 1560,
          height: 878,
          borderRadius: 18,
          border: `4px solid ${C.ink}`,
          overflow: 'hidden',
          transform: `translateY(${lift}px)`,
          boxShadow: '0 26px 60px rgba(20,33,61,0.22)',
          background: C.paper,
        }}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            transform: `scale(${scale})`,
            transformOrigin: `${focus[0]}% ${focus[1]}%`,
          }}
        >
          {image ? (
            <Img src={staticFile(src)} style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top' }} />
          ) : (
            <OffthreadVideo src={staticFile(src)} startFrom={startFrom} muted style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          )}
        </div>
      </div>
    </AbsoluteFill>
  );
};
