import { Config } from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);
// Line art compresses badly at low quality; the paper grain turns to mush.
Config.setCrf(18);
