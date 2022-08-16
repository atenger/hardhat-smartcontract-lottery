// Raffle contract needs 4 components:
// 1> Enter the lottery (pay some amount)
// 2> Pick a random winner (verifiably random)
// 3> Winner to be selected every x minutes -> completely automated
// 4> Need a Chainlink oracle for 2 pieces of functionality:
// randomness and automated executition, b/c a smart contract can't do either

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

error Raffle__NotEnoughETHEntered();
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

/** @title A sample Raffle Contract
 *  @author Adrienne Shulman
 *  @notice This contract is for creating a sample raffle contract that is untamperable & decentralized
 *  @dev This implements the Chainlink VRF Version 2 & Chainlink keepers
 */
contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /* State Variables - Storage & non storage variables */
    //Set the min entrance fee, make it immutable & private to use less gas, then create constructor to set it and function to read it
    uint256 private immutable i_entranceFee;
    //create an array to store all the players as an array of type address, players must be a storage variable b/c it changes
    address payable[] private s_players; // set it payable so you can pay out to the winner
    VRFCoordinatorV2Interface private immutable i_vrfCoordinater;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;

    /* Lottery Variables */
    address private s_recentWinner;
    RaffleState private s_raffleState;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;

    /* Events */
    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner);

    /* Functions */
    constructor(
        address vrfCoordinatorV2,
        uint256 entranceFee,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        uint256 interval
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_entranceFee = entranceFee;
        i_vrfCoordinater = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
    }

    function enterRaffle() public payable {
        //Verify that the amount of token being sent to contract is at least the entrance fee
        //can use "require" but more gas effecient to use a custom error
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHEntered();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }

        // add whoever is calling this function (aka msg.sender) into the array to keep track of them
        s_players.push(payable(msg.sender));
        // We should Emit an event whenever we update a dynamic array or mapping!
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This is the function that the chainlink keeper nodes call, they
     * look for the 'upkeepNeeded' to return true
     * The following should be true in order to return true.
     * 1. our time internal should have passed
     * 2. Lottery should have at least 1 player and have some eth
     * 3. our subscription is funded with some LINK
     * 4. The lottery should be in an open state
     */

    function checkUpkeep(
        bytes memory /*checkData*/
    )
        public
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        //Ternary check - bool_isopen will be true if raffle state = open, otherwise false
        bool isOpen = (RaffleState.OPEN == s_raffleState);
        // Need to check if enough time has passed,
        //by checking current block timestamp with the last block timestamp which keep track of in state variable
        //and then compare to our interval
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        //do we have enough players?
        bool hasPlayers = (s_players.length > 0);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
    }

    function performUpkeep(
        bytes calldata /*performData*/
    ) external override {
        //validate: Need to make sure this only gets called when checkup is true
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        // Request a random number, and then once we get it, do something with it

        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = i_vrfCoordinater.requestRandomWords(
            i_gasLane, //gaslane
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        // This is redundant, b/c the VRF Coordinator function request random words emits request iD
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256, /*requestId*/
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        // After picking winner, reopen the lottery and reset the players array
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        //we identified the winner, now we need to pay them!
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        // require success
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentWinner);
    }

    /* View/ Pure getter functions */

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getLatestTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }
}
