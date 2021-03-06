pragma solidity 0.5.16;

// TODO To be removed in mainnet deployment
import "hardhat/console.sol";

import { AvatarBase } from "./AvatarBase.sol";

import { IPriceOracle } from "../interfaces/CTokenInterfaces.sol";
import { ICToken } from "../interfaces/CTokenInterfaces.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Abstract Comptroller contract for Avatar
 */
contract AbsComptroller is AvatarBase {

    function enterMarket(address cToken) external onlyBComptroller returns (uint256) {
        return _enterMarket(cToken);
    }

    function _enterMarket(address cToken) internal postPoolOp(false) returns (uint256) {
        bool isMember = comptroller.checkMembership(address(this), cToken);
        if(isMember) return 0;

        address[] memory cTokens = new address[](1);
        cTokens[0] = cToken;
        return _enterMarkets(cTokens)[0];
    }

    function enterMarkets(address[] calldata cTokens) external onlyBComptroller returns (uint256[] memory) {
        return _enterMarkets(cTokens);
    }

    function _enterMarkets(address[] memory cTokens) internal postPoolOp(false) returns (uint256[] memory) {
        uint256[] memory result = comptroller.enterMarkets(cTokens);
        for(uint256 i = 0; i < cTokens.length; i++) {
            enableCToken(ICToken(cTokens[i]));
        }
        return result;
    }

    function exitMarket(ICToken cToken) external onlyBComptroller postPoolOp(true) returns (uint256) {
        comptroller.exitMarket(address(cToken));
        _disableCToken(cToken);
    }

    /**
     * @dev Anyone allowed to enable a CToken on Avatar
     * @param cToken CToken address to enable
     */
    function enableCToken(ICToken cToken) public {
        // 1. If cToken is cETH then just return
        if(address(cToken) == address(cETH)) return;

        // 2. Validate cToken supported on the Compound
        (bool isListed,) = comptroller.markets(address(cToken));
        require(isListed, "CToken-not-supported");

        // 3. Initiate inifinite approval
        IERC20 underlying = cToken.underlying();
        // 3.1 De-approve any previous approvals, before approving again
        underlying.safeApprove(address(cToken), 0);
        // 3.2 Initiate inifinite approval
        underlying.safeApprove(address(cToken), uint256(-1));
    }

    function _disableCToken(ICToken cToken) internal {
        cToken.underlying().safeApprove(address(cToken), 0);
    }

    function claimComp(address owner) external onlyBComptroller {
        comptroller.claimComp(address(this));
        comp.safeTransfer(owner, comp.balanceOf(address(this)));
    }

    function claimComp(address[] calldata cTokens, address owner) external onlyBComptroller {
        comptroller.claimComp(address(this), cTokens);
        comp.safeTransfer(owner, comp.balanceOf(address(this)));
    }

    function getAccountLiquidity(address oracle) external view returns (uint err, uint liquidity, uint shortFall) {
        return _getAccountLiquidity(oracle);
    }

    function getAccountLiquidity() external view returns (uint err, uint liquidity, uint shortFall) {
        return _getAccountLiquidity(comptroller.oracle());
    }

    function _getAccountLiquidity(address oracle) internal view returns (uint err, uint liquidity, uint shortFall) {
        // If not topped up, get the account liquidity from Comptroller
        (err, liquidity, shortFall) = comptroller.getAccountLiquidity(address(this));
        if(!isToppedUp()) {
            return (err, liquidity, shortFall);
        }
        require(err == 0, "Error-in-getting-account-liquidity");

        uint256 price = IPriceOracle(oracle).getUnderlyingPrice(toppedUpCToken);
        console.log("In getAccountLiquidity, price: %s", price);
        uint256 toppedUpAmtInETH = mulTrucate(toppedUpAmount, price);

        console.log("In getAccountLiquidity, liquidity: %s", liquidity);
        console.log("In getAccountLiquidity, toppedUpAmtInETH: %s", toppedUpAmtInETH);
        // liquidity = 0 and shortFall = 0
        if(liquidity == toppedUpAmtInETH) return(0, 0, 0);

        // when shortFall = 0
        if(shortFall == 0 && liquidity > 0) {
            if(liquidity > toppedUpAmtInETH) {
                liquidity = sub_(liquidity, toppedUpAmtInETH);
            } else {
                shortFall = sub_(toppedUpAmtInETH, liquidity);
                liquidity = 0;
            }
        } else if(liquidity == 0 && shortFall > 0) { // We can just check for `liquidity == 0`, to cover both of the following cases
            shortFall = add_(shortFall, toppedUpAmtInETH);
        } else {
            // Handling case when compound returned liquidity = 0 and shortFall = 0
            shortFall = add_(shortFall, toppedUpAmtInETH);
            // FIXME We can combine last two `else` block, as calculation is same??
        }
    }

}