// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle
 * @author Ryan Dwiky Darmawan
 * @notice This contract is a simple raffle system where users can enter by sending ETH.
 * @dev Implement Chainlink VRF2.5 for random number generation.
 */

contract Raffle is VRFConsumerBaseV2Plus {
    /* error */
    error Raffle__SendMoreEthToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    /* type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /* state variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    //  wWhat data structure should we use?how to keep track of players?
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Send more ETH to enter the raffle");
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreEthToEnterRaffle();
        }
        if( s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        // require(msg.value >= Raffle_SendMoreEthToEnterRaffle);
        s_players.push(payable(msg.sender));
        // makes migration easier
        // makes frontend "indexing" easier
        emit RaffleEntered(msg.sender);
    }

    // When should the winner be picked?
    /**
     * @dev This is the function that the Chainlink nodes will call to see
     * if the lottery is reaady to have a winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed
     * 2. The lottery is in an "open" state
     * 3. The contract has some ETH balance
     * 4. The contract has players
     * 5. Impicityly, the subscription is funded with LINK
     * @param - ignored
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */

    function checkUpKeep(bytes memory /* checkData */)
        public
        view
        returns (bool upkeepNeeded,bytes memory /* performData */)
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (isOpen && timeHasPassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "");
    }

    // 3. Be automatically called after a certain time period
    function performUpKeep() external {
        // check to see if enough time has passed
        (bool upkeepNeeded, ) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpKeepNotNeeded(address(this).balance, 
                s_players.length, 
                uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        s_vrfCoordinator.requestRandomWords(request);
    }

    //CEi: Checks, Effects, Interactions pattern
    function fulfillRandomWords(
        uint256, /*requestId*/
        uint256[] calldata randomWords
    ) internal override {
        // Checks
        // Effects
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);
        
        // Interactions
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if(!success) {
            revert Raffle__TransferFailed();
        }

    }

    /* getter functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
