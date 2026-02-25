## Env vars required for initial deployment

The below are the values required to deploy the **previous** version ([b1d1bdce1def3c036c06e449787a3763bf47e766](https://github.com/zksync-association/zk-governance/tree/b1d1bdce1def3c036c06e449787a3763bf47e766)).

`MainnetRedeploy.s.sol`
```bash
PRIVATE_KEY= # Deployer
GUARDIAN_MEMBERS= # Comma separated addresses, exactly 8
SECURITY_COUNCIL_MEMBERS= # Comma separated addresses, exactly 12
CREATE3_FACTORY=0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf
ZKSYNC_ERA=0x32400084C286CF3E17e7B677ea9583e60a000324
CHAIN_TYPE_MANAGER=0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3
BRIDGE_HUB=0x303a465B659cBB0ab36eE643eA362c509EEb5213
L1_ASSET_ROUTER=0x8829AD80E425C646DAB305381ff105169FeEcE56
ZK_FOUNDATION=0xbC1653bd3829dfEc575AfC3816D4899cd103B51c
L2_PROTOCOL_GOVERNOR=0x085b8B6407f150D62adB1EF926F7f304600ec714
```

`TestnetRedeploy.s.sol`
```bash
PRIVATE_KEY= # Deployer
GUARDIAN_MEMBERS= # Comma separated addresses, exactly 8
SECURITY_COUNCIL_MEMBERS= # Comma separated addresses, exactly 12
CREATE3_FACTORY=
ZKSYNC_ERA=
L2_PROTOCOL_GOVERNOR=
CHAIN_TYPE_MANAGER=
BRIDGE_HUB=
L1_ASSET_ROUTER=
```

## Env vars required for re-deployment

The below are the values required to re-deploy the **current** version given a deployment of the **previous** version [b1d1bdce1def3c036c06e449787a3763bf47e766](https://github.com/zksync-association/zk-governance/tree/b1d1bdce1def3c036c06e449787a3763bf47e766)).

`MainnetRedeploy.s.sol`
```bash
PRIVATE_KEY= # Deployer
GUARDIAN_MEMBERS= # Comma separated addresses, exactly 8
SECURITY_COUNCIL_MEMBERS= # Comma separated addresses, exactly 12
L2_PROTOCOL_GOVERNOR=0x085b8B6407f150D62adB1EF926F7f304600ec714
PUH_PROXY_MAINNET=0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3 
```

`TestnetRedeploy.s.sol`
```bash
PRIVATE_KEY= # Deployer
GUARDIAN_MEMBERS= # Comma separated addresses, exactly 8
SECURITY_COUNCIL_MEMBERS= # Comma separated addresses, exactly 12
L2_PROTOCOL_GOVERNOR=0x085b8B6407f150D62adB1EF926F7f304600ec714
PUH_PROXY_TESTNET=0x9B956d242e6806044877C7C1B530D475E371d544 #@check 
```
