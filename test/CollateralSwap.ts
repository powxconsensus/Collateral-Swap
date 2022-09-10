import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import "@nomiclabs/hardhat-ethers";

import { expect } from "chai";
const assert = require("assert");
import { BigNumber } from "ethers";
const hre = require("hardhat");
const { ethers } = hre;

const {
  abi,
} = require("./../artifacts/@openzeppelin/contracts/token/ERC20/IERC20.sol/IERC20.json");
const BN = require("bn.js");
const { sendEther, pow } = require("./util");

const {
  DAI,
  DAI_WHALE,
  USDC,
  USDC_WHALE,
  USDT,
  USDT_WHALE,
  WETH_WHALE,
  WETH,
} = require("./config.ts");

const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545/");

describe("TestCollateralSwap", () => {
  const WHALE = WETH_WHALE;
  const TOKEN_BORROW = USDC;
  const DECIMALS = 6;
  const FUND_AMOUNT = pow(10, DECIMALS).mul(new BN(2000));
  const BORROW_AMOUNT = pow(10, DECIMALS).mul(new BN(1000));
  const ADDRESS_PROVIDER = "0xd05e3E715d945B59290df0ae8eF85c1BdB684744";
  let collateralSwap: any;
  let token: any;
  let accounts: any = [];
  beforeEach(async () => {
    accounts = await ethers.getSigners();
    // await Promise.all(
    //   [0, 1, 2, 3, 4, 5].map(async (idx) => {
    //     accounts.push(await ethers.getSigners(idx));
    //   })
    // );

    let contract = new ethers.Contract(TOKEN_BORROW, abi, provider);
    token = contract.attach(TOKEN_BORROW);

    const [owner, feeCollector, operator] = accounts;

    await sendEther(ethers, accounts[0], WHALE, 1);

    await owner.sendTransaction({
      to: operator.address,
      value: ethers.utils.parseEther("1.0"), // Sends exactly 1.0 ether
    });

    await token.balanceOf(WHALE);
    const CollateralSwap = await ethers.getContractFactory("CollateralSwap");
    collateralSwap = await CollateralSwap.attach(ADDRESS_PROVIDER);
  });

  it("supply", async () => {
    const amount = 100;
    await expect(
      collateralSwap.supply(WHALE, amount, collateralSwap.address, 0)
    ).to.eventually.be.fulfilled;
  });

  it("Borrow", async () => {
    await expect(
      collateralSwap.getCollateralLoan(
        USDT_WHALE,
        10,
        1,
        0,
        accounts[0].address
      )
    ).to.eventually.be.fulfilled;
  });

  it("Supply then borrow", async () => {
    const amount = 20 * 10 ** 10; // I have ether to supply 20 ether
    await expect(collateralSwap.supply(WETH, amount, collateralSwap.address, 0))
      .to.eventually.be.fulfilled;

    // const bHealthFactor = await collateralSwap.getUserAccountData(
    //   accounts[1].address
    // );
    // console.log(bHealthFactor);
    await expect(
      collateralSwap.getCollateralLoan(USDT, 1000, 1, 0, accounts[0].address)
    ).to.eventually.be.fulfilled;
    // const aHealthFactor = await collateralSwap.getUserAccountData(
    //   accounts[1].address
    // );
    // assert(bHealthFactor > aHealthFactor);
  });

  it("Testing Collateral Swap", async () => {
    // let's borrow after supplying WETH
    const supplied_weth = ethers.utils.parseEther("100.0");
    await expect(
      collateralSwap.supply(WETH, supplied_weth, collateralSwap.address, 0)
    ).to.eventually.be.fulfilled;
    // let's borrow DAI by giving WETH.
    const borrowed_amount = ethers.utils.parseEther("100.0");
    await expect(
      collateralSwap.getCollateralLoan(
        DAI,
        borrowed_amount,
        1,
        0,
        accounts[0].address
      )
    ).to.eventually.be.fulfilled;
    // let's swap collateral WETH with USDT
    let amount = ethers.utils.parseEther("110.0");
    await expect(collateralSwap.collateralSwap(DAI, amount, 1, 1)).to.eventually
      .be.fulfilled;
  });
});
