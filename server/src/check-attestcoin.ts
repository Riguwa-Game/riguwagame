/// Proves the Attestcoin SDK works against the live chain with the provider the relayer builds.
/// Run with: npm run check:attestcoin
import { JsonRpcProvider } from 'ethers';
import { chainInfo, proofProvider } from '@gluwa/usc-sdk';
import { config } from './config.ts';

const provider = new JsonRpcProvider(config.creditcoinRpc);
const ci = new chainInfo.PrecompileChainInfoProvider(provider as never);

const chains = await ci.getSupportedChains();
console.log('supported chains:');
for (const c of chains) console.log(' ', JSON.stringify(c, (_k, v) => (typeof v === 'bigint' ? v.toString() : v)));

const j = (v: unknown) => JSON.stringify(v, (_k, x) => (typeof x === 'bigint' ? x.toString() : x));

console.log('genesis height  :', await ci.getAttestationGenesisHeight(config.sourceChainKey));
console.log('latest attested :', j(await ci.getLatestAttestedHeightAndHash(config.sourceChainKey)));
console.log('sepolia chain   :', j(await ci.getSupportedChainByKey(config.sourceChainKey)));

const pb = new proofProvider.service.ProofBuilder(config.sourceChainKey, config.proofBuilderUrl);
console.log('ProofBuilder constructed for', config.proofBuilderUrl);
console.log('\nSDK works against the live chain with the relayer provider.');
