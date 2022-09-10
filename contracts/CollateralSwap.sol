// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.1;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./aave/interfaces/IUniswapV2Router02.sol";
import "./aave/FlashLoanReceiverBase.sol";
import "./aave/ILendingPool.sol";
import "./aave/LendingPoolAddressesProvider.sol";
import "./aave/BaseUniswapAdapter.sol";

contract CollateralSwap is FlashLoanReceiverBase, BaseUniswapAdapter {
    struct LiquidationCallLocalVars {
        uint256 initFlashBorrowedBalance;
        uint256 diffFlashBorrowedBalance;
        uint256 initCollateralBalance;
        uint256 diffCollateralBalance;
        uint256 flashLoanDebt;
        uint256 soldAmount;
        uint256 boughtAmount;
        address aToken;
        uint256 remainingTokens;
        uint256 borrowedAssetLeftovers;
    }

    struct LiquidationParams {
        address collateralAsset;
        address borrowedAsset;
        address depositAsset;
        address user;
        uint256 debtToCover;
        bool useEthPath;
    }

    using SafeMath for uint256;
    event Log(string message, uint256 val);

    constructor(
        ILendingPoolAddressesProvider addressesProvider,
        IUniswapV2Router02 uniswapRouter,
        address wethAddress
    ) BaseUniswapAdapter(addressesProvider, uniswapRouter, wethAddress) {}

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
        require(
            msg.sender == address(LENDING_POOL),
            "CALLER_MUST_BE_LENDING_POOL"
        );

        LiquidationParams memory decodedParams = _decodeParams(params);

        require(
            assets.length == 1 && assets[0] == decodedParams.borrowedAsset,
            "INCONSISTENT_PARAMS"
        );

        _liquidateAndSwapAndDeposit(
            decodedParams.collateralAsset,
            decodedParams.borrowedAsset,
            decodedParams.depositAsset,
            decodedParams.user,
            decodedParams.debtToCover,
            decodedParams.useEthPath,
            amounts[0],
            premiums[0],
            initiator
        );

        return true;
    }

    function _flashloan(address[] memory assets, uint256[] memory amounts)
        internal
    {
        address receiverAddress = address(this);

        address onBehalfOf = address(this);
        bytes memory params = "";
        uint16 referralCode = 0;

        uint256[] memory modes = new uint256[](assets.length);

        // 0 = no debt (flash), 1 = stable, 2 = variable
        for (uint256 i = 0; i < assets.length; i++) {
            modes[i] = 0;
        }

        LENDING_POOL.flashLoan(
            receiverAddress,
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
        );
    }

    function mflashloan(address[] memory assets, uint256[] memory amounts)
        public
    {
        _flashloan(assets, amounts);
    }

    function sflashloan(address _asset, uint256 amount) public {
        bytes memory data = "";
        address[] memory assets = new address[](1);
        assets[0] = _asset;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        _flashloan(assets, amounts);
    }

    function collateralSwap(
        address _asset,
        uint256 _amount,
        uint256 _mode,
        bytes calldata params
    ) public {
        // take flash loan
        sflashloan(_asset, _amount);
        LiquidationParams memory decodedParams = _decodeParams(params);

        // Transfer aToken to the msg.sender
        address aToken = _getReserveData(decodedParams.depositAsset)
            .aTokenAddress;
        uint256 aTokenUser = IERC20(aToken).balanceOf(decodedParams.user);
    }

    function _liquidateAndSwapAndDeposit(
        address collateralAsset,
        address borrowedAsset,
        address depositAsset,
        address user,
        uint256 debtToCover,
        bool useEthPath,
        uint256 flashBorrowedAmount,
        uint256 premium,
        address initiator
    ) internal {
        LiquidationCallLocalVars memory vars;
        vars.initCollateralBalance = IERC20(collateralAsset).balanceOf(
            address(this)
        );
        if (collateralAsset != borrowedAsset) {
            vars.initFlashBorrowedBalance = IERC20(borrowedAsset).balanceOf(
                address(this)
            );

            // Track leftover balance to rescue funds in case of external transfers into this contract
            vars.borrowedAssetLeftovers = vars.initFlashBorrowedBalance.sub(
                flashBorrowedAmount
            );
        }
        vars.flashLoanDebt = flashBorrowedAmount.add(premium);

        // Approve LendingPool to use debt token for liquidation
        IERC20(borrowedAsset).approve(address(LENDING_POOL), debtToCover);

        // Liquidate the user position and release the underlying collateral
        LENDING_POOL.liquidationCall(
            collateralAsset,
            borrowedAsset,
            user,
            debtToCover,
            false
        );

        // Discover the liquidated tokens
        uint256 collateralBalanceAfter = IERC20(collateralAsset).balanceOf(
            address(this)
        );

        // Track only collateral released, not current asset balance of the contract
        vars.diffCollateralBalance = collateralBalanceAfter.sub(
            vars.initCollateralBalance
        );

        if (collateralAsset != borrowedAsset) {
            // Discover flash loan balance after the liquidation
            uint256 flashBorrowedAssetAfter = IERC20(borrowedAsset).balanceOf(
                address(this)
            );

            // Use only flash loan borrowed assets, not current asset balance of the contract
            vars.diffFlashBorrowedBalance = flashBorrowedAssetAfter.sub(
                vars.borrowedAssetLeftovers
            );

            // Swap released collateral into the debt asset, to repay the flash loan
            vars.soldAmount = _swapTokensForExactTokens(
                collateralAsset,
                borrowedAsset,
                vars.diffCollateralBalance,
                vars.flashLoanDebt.sub(vars.diffFlashBorrowedBalance),
                useEthPath
            );
            vars.remainingTokens = vars.diffCollateralBalance.sub(
                vars.soldAmount
            );
        } else {
            vars.remainingTokens = vars.diffCollateralBalance.sub(premium);
        }

        // Allow repay of flash loan
        IERC20(borrowedAsset).approve(
            address(LENDING_POOL),
            vars.flashLoanDebt
        );

        // Swap remaining corrateral asset to deposit token
        if (vars.remainingTokens > 0) {
            if (collateralAsset != depositAsset) {
                vars.boughtAmount = _swapExactTokensForTokens(
                    collateralAsset,
                    depositAsset,
                    vars.remainingTokens,
                    40000000000,
                    useEthPath
                );
            }
            // Allow this contract to deposit depositAsset
            vars.aToken = _getReserveData(depositAsset).aTokenAddress;
            IERC20(depositAsset).approve(address(LENDING_POOL), 0);
            IERC20(depositAsset).approve(
                address(LENDING_POOL),
                vars.boughtAmount
            );
            LENDING_POOL.deposit(depositAsset, vars.boughtAmount, user, 0);
            uint256 aTokenUser = IERC20(vars.aToken).balanceOf(user);
        }
    }

    function _decodeParams(bytes memory params)
        internal
        pure
        returns (LiquidationParams memory)
    {
        (
            address collateralAsset,
            address borrowedAsset,
            address depositAsset,
            address user,
            uint256 debtToCover,
            bool useEthPath
        ) = abi.decode(
                params,
                (address, address, address, address, uint256, bool)
            );

        return
            LiquidationParams(
                collateralAsset,
                borrowedAsset,
                depositAsset,
                user,
                debtToCover,
                useEthPath
            );
    }
}
