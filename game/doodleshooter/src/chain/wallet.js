// Wallet connection through Reown AppKit with the wagmi adapter.
// AppKit, @wagmi/core and viem are vendored as one pre-bundled ES module; see
// tools/bundle-appkit.sh. `wagmi` proper needs React, so the framework-agnostic @wagmi/core is
// what the adapter runs on here.
import { createAppKit, WagmiAdapter, getAccount, watchAccount, switchChain } from 'appkit';
import { CHAIN, creditcoinTestnet, REOWN_PROJECT_ID } from './config.js';

const origin = typeof location !== 'undefined' ? location.origin : 'http://127.0.0.1:8910';

const wagmiAdapter = new WagmiAdapter({
  networks: [creditcoinTestnet],
  projectId: REOWN_PROJECT_ID,
});

// Module scope on purpose: createAppKit must run exactly once per page load. Calling it inside a
// function creates duplicate instances with broken state.
export const modal = createAppKit({
  adapters: [wagmiAdapter],
  networks: [creditcoinTestnet],
  defaultNetwork: creditcoinTestnet,
  projectId: REOWN_PROJECT_ID,
  metadata: {
    name: 'Doodle District - Inkstake Arena',
    description: 'A ballpoint-doodle survival shooter with staked runs on Creditcoin',
    url: origin,
    icons: [origin + '/public/ctc.png'],
  },
  features: { analytics: false, email: false, socials: [] },
  themeMode: 'light',
});

/// The wagmi config every @wagmi/core action needs as its first argument.
export const wagmiConfig = wagmiAdapter.wagmiConfig;

const listeners = [];
let address = null;

export const currentAddress = () => address;
export const isConnected = () => !!address;
export const shortAddress = (a) => (a ? a.slice(0, 6) + '…' + a.slice(-4) : '');
export const openWallet = () => modal.open();
export const disconnect = () => modal.disconnect();

export function onAccountChange(cb) {
  listeners.push(cb);
  if (address) cb(address);
}

function announce() {
  for (const cb of listeners) cb(address);
}

// wagmi drives the whole lifecycle: connect, disconnect, account switch, chain switch.
watchAccount(wagmiConfig, {
  onChange(account) {
    const next = account.isConnected ? account.address : null;
    if (next === address) return;
    address = next;
    announce();
    // If the wallet lands on another chain, bring it back.
    if (account.isConnected && account.chainId !== CHAIN.id) {
      switchChain(wagmiConfig, { chainId: CHAIN.id }).catch(() => {
        /* the user declined; the stake call will surface it */
      });
    }
  },
});

// Pick up a session restored from a previous visit.
{
  const existing = getAccount(wagmiConfig);
  if (existing.isConnected && existing.address) {
    address = existing.address;
  }
}
