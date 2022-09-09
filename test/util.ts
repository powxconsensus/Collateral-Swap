const BN = require("bn.js");

async function sendEther(ethers: any, from: any, to: any, amount: any) {
  let provider = ethers.getDefaultProvider();
  from
    .sendTransaction({
      from,
      to,
      value: ethers.utils.parseEther(amount.toString()),
    })
    .then(console.log);
}

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

function cast(x: any) {
  if (x instanceof BN) {
    return x;
  }
  return new BN(x);
}

function eq(x: any, y: any) {
  x = cast(x);
  y = cast(y);
  return x.eq(y);
}

function pow(x: any, y: any) {
  x = cast(x);
  y = cast(y);
  return x.pow(y);
}

function frac(x: any, n: any, d: any) {
  x = cast(x);
  n = cast(n);
  d = cast(d);
  return x.mul(n).div(d);
}

module.exports = {
  sendEther,
  ZERO_ADDRESS,
  eq,
  pow,
  frac,
};
