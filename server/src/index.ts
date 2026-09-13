import { startMonitor } from './monitor/server.ts';
import { startRelayer } from './relayer/index.ts';

startMonitor();
startRelayer();

process.on('unhandledRejection', (reason) => {
  console.error('[fatal] unhandled rejection:', reason);
});
