// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.1;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./aave/FlashLoanReceiverBase.sol";
import "./aave/ILendingPool.sol";
import "./aave/LendingPoolAddressesProvider.sol";

contract CollateralSwap is FlashLoanReceiverBase {
    using SafeMath for uint256;
    event Log(string message, uint256 val);

    constructor(ILendingPoolAddressesProvider _provider)
        FlashLoanReceiverBase(_provider)
    {}

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) public {
        LENDING_POOL.deposit(asset, amount, onBehalfOf, referralCode);
        LENDING_POOL.setUserUseReserveAsCollateral(asset, true);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) public {
        LENDING_POOL.withdraw(asset, amount, to);
    }

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral)
        public
    {
        LENDING_POOL.setUserUseReserveAsCollateral(asset, useAsCollateral);
    }

    function getCollateralLoan(
        address assetToBorrow,
        uint256 amountToBorrowInWei,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) public {
        LENDING_POOL.borrow(
            assetToBorrow,
            amountToBorrowInWei,
            interestRateMode,
            referralCode,
            onBehalfOf
        );
    }

    function getUserAccountData(address user)
        external
        view
        virtual
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return LENDING_POOL.getUserAccountData(user);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // do stuff here (arbitrage, liquidation, etc...)
        // abi.decode(params) to decode params
        for (uint256 i = 0; i < assets.length; i++) {
            emit Log("borrowed", amounts[i]);
            emit Log("fee", premiums[i]);

            uint256 amountOwing = amounts[i].add(premiums[i]);
            IERC20(assets[i]).approve(address(LENDING_POOL), amountOwing);
        }
        // repay Aave
        return true;
    }
}
