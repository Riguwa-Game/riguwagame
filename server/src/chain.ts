import { createPublicClient, createWalletClient, defineChain, http } from 'viem';
import { config } from './config.ts';
import { monitorAccount } from './signer.ts';
import type { Hex } from 'viem';

export const creditcoinTestnet = defineChain({
  id: config.creditcoinChainId,
  name: 'Creditcoin Testnet',
  nativeCurrency: { name: 'Testnet Creditcoin', symbol: 'tCTC', decimals: 18 },
  rpcUrls: { default: { http: [config.creditcoinRpc] } },
  blockExplorers: {
    default: { name: 'Blockscout', url: 'https://creditcoin-testnet.blockscout.com' },
  },
  testnet: true,
});

export const publicClient = createPublicClient({
  chain: creditcoinTestnet,
  transport: http(config.creditcoinRpc),
});

export function walletClient() {
  return createWalletClient({
    account: monitorAccount(config.monitorKey() as Hex),
    chain: creditcoinTestnet,
    transport: http(config.creditcoinRpc),
  });
}
