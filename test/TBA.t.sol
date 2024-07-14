// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { NFT } from "../src/NFT.sol";
import { TBA } from "../src/TBA.sol";
import { ERC6551Registry } from "../lib/reference/src/ERC6551Registry.sol";
import { ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { NFTMarketPlace } from "../src/NFTMarketPlace.sol";
using SafeERC20 for ERC20;

contract TBATest is Test {
    address user;
    address constant registryAddress = 0x000000006551c19487814612e58FE06813775758;
    ERC6551Registry registry = ERC6551Registry(registryAddress);

    address constant USDCAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    ERC20 USDC = ERC20(USDCAddress);

    NFT public nft;
    TBA public tbaBase;
    address tbaAddress1;
    address tbaAddress2;
    address tbaAddress3;
    TBA tba1;
    TBA tba2;
    TBA tba3;

    NFTMarketPlace public nftMarketPlace;


    event ERC6551AccountCreated(
        address account,
        address indexed implementation,
        bytes32 salt,
        uint256 chainId,
        address indexed tokenContract,
        uint256 indexed tokenId
    );

    function setUp() public{
        //FORK ENVIRONMENT
        string memory rpc = vm.envString("RPC_URL");
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        //USER SETUP
        user = makeAddr("user");
        deal(user, 10 ether);
        deal(USDCAddress, user, 1000 * 10**6);

        //user1 ACTIONS
        vm.startPrank(user);
        nft = new NFT();
        tbaBase = new TBA();
        nftMarketPlace = new NFTMarketPlace(address(nft));

        //Create TBA1
        tbaAddress1 = registry.account(address(tbaBase), 0, block.chainid, address(nft), 1);
        nft.mint(user);
        registry.createAccount(address(tbaBase), 0, block.chainid, address(nft), 1);
        tba1 = TBA(payable(tbaAddress1));

        //Create TBA2
        tbaAddress2 = registry.account(address(tbaBase), 0, block.chainid, address(nft), 2);
        nft.mint(user);
        registry.createAccount(address(tbaBase), 0, block.chainid, address(nft), 2);
        tba2 = TBA(payable(tbaAddress2));

        //Create TBA3
        tbaAddress3 = registry.account(address(tbaBase), 0, block.chainid, address(nft), 3);
        nft.mint(user);
        registry.createAccount(address(tbaBase), 0, block.chainid, address(nft), 3);
        tba3 = TBA(payable(tbaAddress3));
        vm.stopPrank();
    }

    function test_createOwnershipCycle() public{
        vm.startPrank(user);
        nft.transferFrom(user, tbaAddress1, 2); 
        nft.transferFrom(user, tbaAddress2, 3);
        nft.transferFrom(user, tbaAddress3, 1);
        assertEq(nft.ownerOf(1), tbaAddress3);
        assertEq(nft.ownerOf(2), tbaAddress1);
        assertEq(nft.ownerOf(3), tbaAddress2);
        assertEq(tba1.owner(), tbaAddress3);
        assertEq(tba2.owner(), tbaAddress1);
        assertEq(tba3.owner(), tbaAddress2);
        vm.stopPrank();
    }

    function test_breakOwnershipCycle() public{
        vm.startPrank(user);

        //initialize guardians
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");
        address guardian3 = makeAddr("guardian3");
        address[] memory guardians = new address[](3);
        guardians[0] = guardian1;
        guardians[1] = guardian2;
        guardians[2] = guardian3;
        tba1.initializeGuardians(guardians);

        //create ownership cycle
        nft.transferFrom(user, tbaAddress1, 2); 
        nft.transferFrom(user, tbaAddress2, 3);
        nft.transferFrom(user, tbaAddress3, 1);
        vm.stopPrank();

        //break ownership cycle
        vm.prank(guardian1);
        tba1.proposeRecovery(guardian1, address(nft), 2);
        vm.prank(guardian2);
        tba1.voteRecovery();
        vm.startPrank(guardian3);
        tba1.executeRecovery();

        assertEq(nft.ownerOf(1), tbaAddress3);
        assertEq(nft.ownerOf(2), guardian1);
        assertEq(nft.ownerOf(3), tbaAddress2);
        assertEq(tba1.owner(), tbaAddress3);
        assertEq(tba2.owner(), guardian1);
        assertEq(tba3.owner(), tbaAddress2);
        vm.stopPrank();
    }   

    function test_approveThroughExecute() public {
        vm.startPrank(user);
        vm.expectRevert("Approve is not allowed");
        bytes memory data = abi.encodeWithSelector(nft.approve.selector, tbaAddress2, 1);
        tba1.execute(address(nft), 0, data, 0);
        vm.expectRevert("Approve is not allowed");
        bytes memory data2 = abi.encodeWithSelector(nft.approve.selector, tbaAddress2, 10000);
        tba1.execute(USDCAddress, 0, data2, 0);
        bytes memory data3 = abi.encodeWithSelector(nft.setApprovalForAll.selector, tbaAddress2, true);
        vm.expectRevert("setApprovalForAll is not allowed");
        tba1.execute(address(nft), 0, data3, 0);
        vm.stopPrank();
    }

    function test_approvalForAll() public {
        address user2 = makeAddr("user2");
        vm.startPrank(user);
        nft.mint(tbaAddress1);
        tba1.setOperator(address(nft), user2, true);
        tba1.approveToken(USDCAddress, user2, 1000 * 10**6);
        tba1.approveNFT(address(nft), 4, user2);
        (TBA.TokenData[] memory tokenApprovals, 
        TBA.NFTData[] memory nftApprovals, 
        address[] memory nftOperators) = tba1.getApprovals();
        assertEq(tokenApprovals[0].tokenAddress, USDCAddress);
        assertEq(nftApprovals[0].tokenAddress, address(nft));
        assertEq(nftApprovals[0].tokenID, 4);
        assertEq(nftOperators[0], user2);
    }

    function test_frontrunAttack() public {
        address user2 = makeAddr("user2");
        deal(user2, 12 ether);
        vm.startPrank(user);

        //Deposit tokens in TBA1
        tbaAddress1.call{value: 10 ether}("");
        USDC.transfer(tbaAddress1, 1000 * 10**6);

        //user1 list TBA
        nft.approve(address(nftMarketPlace), 1);
        nftMarketPlace.listNFT(1);
        vm.stopPrank();

        //user2 sees TBA and offer 12 ether
        vm.prank(user2);
        nftMarketPlace.buyOffer{value: 12 ether}(1, 12 ether);

        //user1 withdraws assets and acceptOffer
        vm.startPrank(user);
        tba1.execute(user, 10 ether, "", 0);
        //transfer 1000 usdc to user
        bytes memory data = abi.encodeWithSelector(USDC.transfer.selector, user, 1000 * 10**6);
        tba1.execute(USDCAddress, 0, data, 0);
        nftMarketPlace.acceptOffer(1);
        vm.stopPrank();
        
        assertEq(nft.ownerOf(1), user2);
        assertEq(address(tba1).balance, 0);
        assertEq(USDC.balanceOf(tbaAddress1), 0);
        assertEq(USDC.balanceOf(user), 1000 * 10**6);
        assertEq(user.balance, 22 ether);
    }

    function test_backrunAttack() public {
        address user2 = makeAddr("user2");
        deal(user2, 12 ether);
        vm.startPrank(user);

        //Deposit tokens in TBA1 and approve
        USDC.transfer(tbaAddress1, 1000 * 10**6);
        tba1.approveToken(USDCAddress, user, 1000 * 10**6);

        //user1 list TBA
        nft.approve(address(nftMarketPlace), 1);
        nftMarketPlace.listNFT(1);
        vm.stopPrank();

        //user2 sees TBA and offer 12 ether
        vm.prank(user2);
        nftMarketPlace.buyOffer{value: 1 ether}(1, 1 ether);

        //user1 accepts offer and call transferFrom to rugpull
        vm.startPrank(user);
        nftMarketPlace.acceptOffer(1);
        USDC.transferFrom(tbaAddress1, user, 1000 * 10**6);

        assertEq(nft.ownerOf(1), user2);
        assertEq(USDC.balanceOf(tbaAddress1), 0);
        assertEq(USDC.balanceOf(user), 1000 * 10**6);
    }

    function test_lockAndReset() public {
        address user2 = makeAddr("user2");
        deal(user2, 12 ether);

        //Deposit tokens in TBA1 and approve
        vm.startPrank(user);
        USDC.transfer(tbaAddress1, 1000 * 10**6);
        tba1.approveToken(USDCAddress, user, 1000 * 10**6);

        //set lock and reset to prepare for listing
        tba1.setReceiver(address(nftMarketPlace));
        tba1.lock(10 minutes);
        tba1.reset();

        //approve and list NFT
        nft.approve(address(nftMarketPlace), 1);
        nftMarketPlace.listNFT(1);
        vm.stopPrank();

        //user2 sees TBA and offer 12 ether
        vm.prank(user2);
        nftMarketPlace.buyOffer{value: 1 ether}(1, 1 ether);

        //user1 attempts to withdraw assets and acceptOffer
        vm.startPrank(user);
        //transfer 1000 usdc to user
        bytes memory data = abi.encodeWithSelector(USDC.transfer.selector, user, 1000 * 10**6);
        vm.expectRevert("Contract is locked");
        tba1.execute(USDCAddress, 0, data, 0);
        nftMarketPlace.acceptOffer(1);
        //user attempts to rugpull
        vm.expectRevert();
        USDC.transferFrom(tbaAddress1, user, 1000 * 10**6);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), user2);
        assertEq(USDC.balanceOf(tbaAddress1), 1000 * 10**6);
        assertEq(USDC.balanceOf(user), 0);
    }
}