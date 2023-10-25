const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { fundContract } = require("../utils/utilities");

const {
  abi,
} = require("../artifacts/contracts/interfaces/IERC20.sol/IERC20.json");

const provider = waffle.provider;

describe("FlashLoan Contract", () => {
  let FLASHLOAN, BORROW_AMOUNT, FUND_AMOUNT, initialFundingHuman, txArbitrage;

  const DECIMALS = 18;

  const BUSD_WHALE = "0xf977814e90da44bfa03b6295a0616a897441acec";
  const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
  const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
  const CROX = "0x2c094F5A7D1146BB93850f629501eB749f6Ed491";

  const busdInstance = new ethers.Contract(BUSD, abi, provider);

  beforeEach(async () => {
    const whale_balance = await provider.getBalance(BUSD);
    console.log(whale_balance);
    expect(whale_balance).not.equal("0");

    const FlashLoan = await ethers.getContractFactory("FlashLoan");
    FlashLoan = await FlashLoan.deploy();
    await FlashLoan.deployed();

    const borrowAmountHuman = "1";
    BORROW_AMOUNT = ethers.utils.parseUnits(borrowAmountHuman, DECIMALS);
    console.log(BORROW_AMOUNT);

    initialFundingHuman = "1";
    FUND_AMOUNT = ethers.utils.parseUnits(initialFundingHuman, DECIMALS);
    await fundContract(
      busdInstance,
      BUSD_WHALE,
      FlashLoan.address,
      initialFundingHuman
    );
    console.log(FUND_AMOUNT);
  });
  describe("Arbitrage", async () => {
    it("ensures that the contract is funded.", async () => {
      const flashLoanBalance = await FLASHLOAN.getBalanceOfToken(BUSD);
      console.log(flashLoanBalance);

      const flashLoanBalanceHuman = ethers.utils.formatUnits(
        flashLoanBalance,
        DECIMALS
      );
      console.log(flashLoanBalanceHuman);

      expect(Number(flashLoanBalanceHuman)).to.equal(
        Number(initialFundingHuman)
      );
    });

    it("executes arbitrage", async () => {
      txArbitrage = await FLASHLOAN.executeArbitrage(BUSD, BORROW_AMOUNT);
      assert(txArbitrage);
    });
  });
});
