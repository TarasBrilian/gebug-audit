// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Minimal ERC4626-style vault that ships with a first-depositor share
// inflation bug (lending.md L1.1 in the gebug attack-vector catalog).
// This contract is intentionally vulnerable and exists only as a
// regression fixture for gebug-audit. Do NOT deploy.

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Vault {
    IERC20 public immutable asset;
    uint256 public totalShares;
    mapping(address => uint256) public shareOf;

    constructor(IERC20 _asset) {
        asset = _asset;
    }

    // Vulnerability: when totalShares == 0, the first depositor mints
    // `assets` shares 1:1. They can then donate underlying directly to
    // the vault contract, inflating totalAssets. The next depositor
    // computes `shares = assets * totalShares / totalAssets`, which
    // rounds to zero for any deposit below the donated balance.
    //
    // Canonical fix: pre-mint a virtual supply, or block the first
    // deposit below a configured minimum.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        uint256 totalAssets = asset.balanceOf(address(this));
        if (totalShares == 0) {
            shares = assets;
        } else {
            shares = (assets * totalShares) / totalAssets;
        }
        require(shares > 0, "ZERO_SHARES");
        require(asset.transferFrom(msg.sender, address(this), assets), "TRANSFER_FAILED");
        totalShares += shares;
        shareOf[receiver] += shares;
    }

    function withdraw(uint256 shares, address receiver) external returns (uint256 assets) {
        uint256 totalAssets = asset.balanceOf(address(this));
        assets = (shares * totalAssets) / totalShares;
        require(shareOf[msg.sender] >= shares, "INSUFFICIENT_SHARES");
        shareOf[msg.sender] -= shares;
        totalShares -= shares;
        require(asset.transfer(receiver, assets), "TRANSFER_FAILED");
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        if (totalShares == 0) return assets;
        return (assets * totalShares) / asset.balanceOf(address(this));
    }
}
