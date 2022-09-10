# Collateral Swap On Aave

This project demonstrates a collateral swap on Aave.

```shell
virtualenv -p python3 venv
source venv/bin/activate
pip install vyper
cp .env.sample .env
```

```shell
npx hardhat node --fork <MAINNET_FORK_NODE_URL>
or
source .env
npx hardhat node --fork $NODE_URL
```

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
GAS_REPORT=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.ts
```
