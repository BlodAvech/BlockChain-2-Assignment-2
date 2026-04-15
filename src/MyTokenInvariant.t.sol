// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract TokenHandler is Test {
    MyToken public token;
    address public owner;
    address[] public actors;
    uint256 public ghostTotalMinted;
    uint256 public ghostTotalBurned;

    constructor(MyToken _token, address _owner) {
        token = _token;
        owner = _owner;
        ghostTotalMinted = _token.totalSupply();
        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
        actors.push(makeAddr("actor3"));
    }

    function transfer(uint256 fromIdx, uint256 toIdx, uint256 amount) external {
        fromIdx = bound(fromIdx, 0, actors.length - 1);
        toIdx   = bound(toIdx,   0, actors.length - 1);
        uint256 bal = token.balanceOf(actors[fromIdx]);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(actors[fromIdx]);
        token.transfer(actors[toIdx], amount);
    }

    function mint(uint256 actorIdx, uint256 amount) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        uint256 remaining = token.MAX_SUPPLY() - token.totalSupply();
        if (remaining == 0) return;
        amount = bound(amount, 1, remaining < 1000 ether ? remaining : 1000 ether);
        vm.prank(owner);
        token.mint(actors[actorIdx], amount);
        ghostTotalMinted += amount;
    }

    function burn(uint256 actorIdx, uint256 amount) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        uint256 bal = token.balanceOf(actors[actorIdx]);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(actors[actorIdx]);
        token.burn(amount);
        ghostTotalBurned += amount;
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }
}

contract MyTokenInvariantTest is Test {
    MyToken      public token;
    TokenHandler public handler;
    address      public owner;

    function setUp() public {
        owner   = makeAddr("owner");
        vm.prank(owner);
        token   = new MyToken("MyToken", "MTK", 100_000 * 10 ** 18);
        handler = new TokenHandler(token, owner);
        targetContract(address(handler));
    }

    function invariant_supplyMatchesGhost() public view {
        uint256 expected = handler.ghostTotalMinted() - handler.ghostTotalBurned();
        assertEq(token.totalSupply(), expected);
    }

    function invariant_supplyNeverExceedsMax() public view {
        assertLe(token.totalSupply(), token.MAX_SUPPLY());
    }

    function invariant_noBalanceExceedsTotalSupply() public view {
        for (uint256 i = 0; i < handler.actorsLength(); i++) {
            assertLe(
                token.balanceOf(handler.actors(i)),
                token.totalSupply()
            );
        }
    }
}