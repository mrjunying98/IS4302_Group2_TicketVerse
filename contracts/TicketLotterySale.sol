// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import required contracts and interfaces.
// ConcertTicket provides functions for ticket management.
// VRFConsumerBaseV2 and VRFCoordinatorV2Interface are used for Chainlink VRF integration.
// Ownable is used to restrict access to certain administrative functions.
// ILoyaltySystem is the interface for the loyalty points system.
import "./ConcertTicket.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ILoyaltySystem} from "./LoyaltySystem.sol";

/**
 * @title TicketLotterySale
 * @notice This contract manages the lottery-based ticket sale process.
 * Users register for tickets by paying the ticket price plus fee. After the registration
 * period, a lottery is run (via Chainlink VRF) to determine winners. Winners can later claim
 * (mint) their tickets before the claim deadline (concert start time minus a buffer).
 * Unclaimed lottery slots can be updated (reassigned) so that the corresponding tickets become
 * available for normal purchase.
 */
contract TicketLotterySale is Ownable, VRFConsumerBaseV2 {

    // -------------------------------------------------
    // DATA STRUCTURES
    // -------------------------------------------------

    // Enumeration representing seating categories.
    enum CAT { A, B, C, D, E }
    
    /**
     * @dev Stores details of a single registration entry.
     * @param registrant The address that registered.
     * @param amount The ticket price paid (excluding fee).
     * @param category The seating category chosen.
     */
    struct Registration {
        address registrant;
        uint256 amount;
        CAT category;
    }
    
    /**
     * @dev Aggregates a user's overall registration details.
     * @param exists Indicates if the user has registered.
     * @param category The seating category for which the user registered.
     * @param totalTickets The total number of tickets the user registered for.
     */
    struct UserRegistration {
        bool exists;
        CAT category;
        uint256 totalTickets;
    }

    /**
     * @dev Stores details for a lottery winner.
     * @param winner The address of the lottery winner.
     * @param winTimestamp The timestamp when the lottery result was recorded.
     * @param claimed Flag indicating if the ticket has been claimed.
     * @param ticketPrice The ticket price associated with this lottery entry.
     */
    struct LotteryWinner {
        address winner;
        uint256 winTimestamp;
        bool claimed;
        uint256 ticketPrice;
    }
    
    // -------------------------------------------------
    // STATE VARIABLES
    // -------------------------------------------------
    
    // Mappings for registration data.
    mapping(address => UserRegistration) public userRegistrations;
    mapping(CAT => Registration[]) public registrations;
    
    // Mapping for lottery winners per seating category.
    mapping(CAT => LotteryWinner[]) public lotteryWinners;
    
    // Registration period timestamps.
    uint256 public registrationStart;
    uint256 public registrationEnd;
    
    // ConcertTicket contract instance.
    ConcertTicket public concertTicket;
    
    // Accumulated fee pool from registrations and purchases.
    uint256 public feePool;
    // Fee rate in basis points (FEE_RATE_BP = 100 means 1% fee).
    uint256 public constant FEE_RATE_BP = 100;
    
    // Addresses for event organiser, deployer, and marketplace.
    address public eventOrganiser;
    address public deployer;
    address public marketplace;
    
    // Loyalty system interface instance.
    ILoyaltySystem public loyaltySystem;
    
    // -------------------------------------------------
    // CHAINLINK VRF VARIABLES
    // -------------------------------------------------
    
    // VRF Coordinator interface instance.
    VRFCoordinatorV2Interface public COORDINATOR;
    // VRF subscription ID.
    uint64 public subscriptionId;
    // VRF key hash.
    bytes32 public keyHash;
    // Callback gas limit.
    uint32 public constant callbackGasLimit = 1000000;
    // Confirmations required.
    uint16 public constant requestConfirmations = 3;
    // Number of random words requested.
    uint32 public constant numWords = 1;
    // VRF request ID.
    uint256 public s_requestId;
    // Random number result from VRF.
    uint256 public randomResult;
    // Flags to indicate if the lottery has been requested and executed.
    bool public lotteryRequested;
    bool public lotteryExecuted;
    
    // Counter for minted tickets.
    uint256 public ticketCounter = 0;
    // Claim buffer: winners can claim until 2 hours before concert start.
    uint256 public constant CLAIM_BUFFER = 2 hours;
    
    // Blacklist mapping.
    mapping(address => bool) public blacklist;
    
    // -------------------------------------------------
    // EVENTS
    // -------------------------------------------------
    
    event RegistrationReceived(address indexed registrant, CAT category, uint256 numTickets, uint256 totalAmount);
    event LotteryRequested(uint256 requestId);
    event LotteryExecuted();
    event TicketMinted(address indexed to, CAT category);
    event RefundIssued(address indexed registrant, uint256 amount);
    event FeeWithdrawn(uint256 amount);
    event LotteryWinnerUpdated(CAT category, uint256 index, address newWinner);
    
    // -------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------
    
    /**
     * @notice Constructor sets initial parameters for the lottery sale.
     * @param _concertTicketAddress Address of the deployed ConcertTicket contract.
     * @param _registrationStart Timestamp when registration starts.
     * @param _registrationEnd Timestamp when registration ends.
     * @param _eventOrganiser Address of the event organiser.
     * @param _marketplace Address of the marketplace.
     * @param _loyaltySystem Address of the deployed LoyaltySystem contract.
     * @param _vrfCoordinator Address of the VRFCoordinator.
     * @param _subscriptionId VRF subscription ID.
     * @param _keyHash VRF key hash.
     * @param _deployer Address of the deployer.
     */
    constructor(
        address _concertTicketAddress,
        uint256 _registrationStart,
        uint256 _registrationEnd,
        address _eventOrganiser,
        address _marketplace,
        address _loyaltySystem,
        address _vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _keyHash,
        address _deployer
    )
        VRFConsumerBaseV2(_vrfCoordinator)
        Ownable()
    {
        require(_registrationStart < _registrationEnd, "Invalid registration period");
        require(_concertTicketAddress != address(0), "Invalid ConcertTicket address");
        require(_eventOrganiser != address(0), "Invalid event organiser address");
        require(_marketplace != address(0), "Invalid marketplace address");
        require(_loyaltySystem != address(0), "Invalid loyalty system address");
        
        registrationStart = _registrationStart;
        registrationEnd = _registrationEnd;
        concertTicket = ConcertTicket(_concertTicketAddress);
        eventOrganiser = _eventOrganiser;
        marketplace = _marketplace;
        loyaltySystem = ILoyaltySystem(_loyaltySystem);
        
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        deployer = _deployer;
    }
    
    // -------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------
    
    /**
     * @dev Restricts access to only the deployer.
     */
    modifier onlyDeployer() { 
        require(msg.sender == deployer, "Not authorized");
        _;
    }
    
    // -------------------------------------------------
    // BLACKLIST MANAGEMENT
    // -------------------------------------------------
    
    /**
     * @notice Adds an address to the blacklist.
     * @param addr The address to add.
     */
    function addToBlacklist(address addr) external onlyDeployer {
        blacklist[addr] = true;
    }
    
    /**
     * @notice Removes an address from the blacklist.
     * @param addr The address to remove.
     */
    function removeFromBlacklist(address addr) external onlyDeployer {
        blacklist[addr] = false;
    }
    
    // -------------------------------------------------
    // REGISTRATION FUNCTIONALITY
    // -------------------------------------------------
    
    /**
     * @notice Allows a user to register for tickets by paying the required amount.
     * Each registration entry includes the ticket price (without fee).
     * Loyalty points are added for each ticket registered.
     * @param category The seating category (A, B, C, D, or E).
     * @param numTickets Number of tickets to register for.
     */
    function register(CAT category, uint256 numTickets) external payable {
        require(block.timestamp >= registrationStart, "Registration not active");
        require(block.timestamp <= registrationEnd, "Registration period has ended");
        require(!blacklist[msg.sender], "Address is blacklisted");
        require(numTickets >= 1 && numTickets <= 4, "Can only register 1 to 4 tickets");
        
        // Retrieve ticket price from ConcertTicket.
        ( , uint256 ticketPrice) = concertTicket.seatingDetails(ConcertTicket.CAT(uint8(category)));
        require(ticketPrice > 0, "Ticket price not set");
        
        // Calculate fee and required payment.
        uint256 fee = (ticketPrice * FEE_RATE_BP) / 10000;
        uint256 requiredAmount = numTickets * (ticketPrice + fee);
        require(msg.value == requiredAmount, "Incorrect ETH amount sent");

        // Update fee pool.
        feePool += (fee * numTickets);
        
        // Update user's registration record.
        UserRegistration storage userReg = userRegistrations[msg.sender];
        if (!userReg.exists) {
            userReg.exists = true;
            userReg.category = category;
            userReg.totalTickets = numTickets;
        } else {
            require(uint8(userReg.category) == uint8(category), "Cannot register for multiple categories");
            require(userReg.totalTickets + numTickets <= 4, "Exceeds maximum of 4 tickets per address");
            userReg.totalTickets += numTickets;
        }
        
        // Store each registration entry and add loyalty points.
        for (uint256 i = 0; i < numTickets; i++) {
            registrations[category].push(Registration({
                registrant: msg.sender,
                amount: ticketPrice,
                category: category
            }));
            loyaltySystem.addPoints(msg.sender, 20);
        }
        
        emit RegistrationReceived(msg.sender, category, numTickets, msg.value);
    }
    
    /**
     * @notice Returns the number of registration entries for a specific category.
     * @param category The seating category.
     * @return The count of registrations.
     */
    function getRegistrationCountByCategory(CAT category) external view returns (uint256) {
        return registrations[category].length;
    }
    
    /**
     * @notice Returns the total number of registration entries across all categories.
     * @return The total count.
     */
    function getTotalRegistrationCount() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < 5; i++) {
            total += registrations[CAT(i)].length;
        }

        return total;
    }
    
    // -------------------------------------------------
    // LOTTERY PROCESSING
    // -------------------------------------------------
    
    /**
     * @notice Initiates the lottery process by requesting randomness from Chainlink VRF.
     * Can only be called by the deployer after the registration period has ended.
     */
    function runLottery() external onlyDeployer {
        require(block.timestamp > registrationEnd, "Registration still active");
        require(!lotteryRequested, "Lottery already requested");
        
        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        lotteryRequested = true;
        emit LotteryRequested(s_requestId);
    }
    
    /**
     * @notice Callback function for Chainlink VRF.
     * Processes randomness by shuffling registrations for each category and recording lottery winners.
     * Also updates the available ticket count in the ConcertTicket contract.
     */
    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override {
        require(lotteryRequested, "Lottery not requested");
        randomResult = randomWords[0];
        
        // Process each seating category.
        for (uint256 i = 0; i < 5; i++) {
            CAT category = CAT(i);
            Registration[] storage regs = registrations[category];
            uint256 numRegs = regs.length;
            (uint256 available, uint256 ticketPrice) = concertTicket.seatingDetails(ConcertTicket.CAT(uint8(category)));
            // Calculate number of winners (up to the available ticket count).
            uint256 winnersCount = numRegs > 0 ? (numRegs < available ? numRegs : available) : 0;
            
            // If there are registrations, shuffle them.
            // Shuffle using Fisher-Yates algorithm.
            if (numRegs > 0) {
                uint256 seed = randomResult;
                seed = uint256(keccak256(abi.encode(seed, i)));
                for (uint256 j = numRegs - 1; j > 0; j--) {
                    // Generate a random index for swapping.
                    // Use the seed to ensure randomness.
                    seed = uint256(keccak256(abi.encode(seed, j)));
                    // Ensure the random index is within bounds.
                    uint256 randIndex = seed % (j + 1);
                    // Swap the current element with the random element.
                    Registration memory temp = regs[j];
                    // Swap the elements.
                    regs[j] = regs[randIndex];
                    // Assign the random element to the current position.
                    regs[randIndex] = temp;
                }
                // Record lottery winners.
                for (uint256 j = 0; j < winnersCount; j++) {
                    Registration memory regEntry = regs[j];
                    lotteryWinners[category].push(LotteryWinner({
                        winner: regEntry.registrant,
                        winTimestamp: block.timestamp,
                        claimed: false,
                        ticketPrice: ticketPrice
                    }));
                }
                // Update available ticket count in ConcertTicket.
                uint256 currentAvailable = concertTicket.getTicketAvailability(ConcertTicket.CAT(uint8(category)));
                uint256 newAvailability = currentAvailable - winnersCount;
                concertTicket.updateTicketAvailability(ConcertTicket.CAT(uint8(category)), newAvailability);
            }
        }
        lotteryExecuted = true;
        emit LotteryExecuted();
    }
    
    // -------------------------------------------------
    // CLAIMING LOTTERY TICKETS
    // -------------------------------------------------
    
    /**
     * @notice Allows a lottery winner to claim (mint) their ticket.
     * The winner must claim before the claim deadline (concertStartDate - CLAIM_BUFFER).
     * The ticket price (without fee) is transferred to the event organiser,
     * and loyalty points are awarded.
     * @param category The seating category of the lottery ticket.
     */
    function claimLotteryTicket(CAT category) external {
        uint256 concertStart = concertTicket.concertStartDate();
        require(block.timestamp <= concertStart - CLAIM_BUFFER, "Claim period closed");
        
        LotteryWinner[] storage winners = lotteryWinners[category];
        bool found = false;
        uint256 count = 0;
        uint256 index;
        for (uint256 i = 0; i < winners.length; i++) {
            if (winners[i].winner == msg.sender && !winners[i].claimed) {
                count++; // Count how many lottery entries belong to this user.
                index = i;
                winners[i].claimed = true;
                // Mint one ticket per lottery entry.
                concertTicket.mint(msg.sender, uint256(category));
                emit TicketMinted(msg.sender, category);
                found = true;
            }
        }
        require(found, "No lottery win found for caller");
        
        // Calculate total ticket price for all claimed lottery entries.
        uint256 ticketPrice = winners[index].ticketPrice;
        uint256 totalAmount = ticketPrice * count;
        // Transfer the total ticket price to the event organiser.
        (bool sent, ) = eventOrganiser.call{value: totalAmount}("");
        require(sent, "Payment transfer failed");
        
        // Award additional loyalty points for claimed tickets.
        loyaltySystem.addPoints(msg.sender, 100 * count);
    }

    // -------------------------------------------------
    // WITHDRAW PREPAID ETH FOR FAILED LOTTERY
    // -------------------------------------------------

    /**
    * @notice Allows users to withdraw funds for their lottery registrations that did not win.
    *         This can only be called after the lottery has been executed.
    * @param category The seating category for which the user registered.
    */
    function withdrawFailedLotteryFunds(CAT category) external {
        require(lotteryExecuted, "Lottery not executed yet");

        // Retrieve the user's registration record.
        UserRegistration storage userReg = userRegistrations[msg.sender];
        require(userReg.exists, "No registration found");
        require(uint8(userReg.category) == uint8(category), "Registration not for this category");

        // Count the number of winning entries for the user in this category.
        uint256 winningCount = 0;
        LotteryWinner[] storage winners = lotteryWinners[category];
        for (uint256 i = 0; i < winners.length; i++) {
            if (winners[i].winner == msg.sender) {
                winningCount++;
            }
        }
        
        // Ensure that there is at least one registration that did not win.
        require(userReg.totalTickets > winningCount, "All registrations resulted in a win; nothing to withdraw");

        // Calculate the refund: refund for each ticket that did not win.
        uint256 refundCount = userReg.totalTickets - winningCount;
        (, uint256 ticketPrice) = concertTicket.seatingDetails(ConcertTicket.CAT(uint8(category)));
        uint256 refundAmount = refundCount * ticketPrice;
        
        // Clear the user's registration record to prevent multiple withdrawals.
        delete userRegistrations[msg.sender];
        
        // Transfer the refund back to the user.
        payable(msg.sender).transfer(refundAmount);
    }
    
    // -------------------------------------------------
    // NORMAL TICKET PURCHASE
    // -------------------------------------------------
    
    /**
     * @notice Allows a user to purchase a ticket normally if they did not win the lottery.
     * Purchases can be made after the registration period and before the concert starts.
     * @param category The seating category for the ticket.
     */
    function buyTicket(CAT category) external payable {
        require(block.timestamp > registrationEnd, "Registration still active");
        require(block.timestamp < concertTicket.concertStartDate(), "Concert started");
        (, uint256 ticketPrice) = concertTicket.seatingDetails(ConcertTicket.CAT(uint8(category)));
        uint256 fee = (ticketPrice * FEE_RATE_BP) / 10000;
        uint256 requiredAmount = ticketPrice + fee;
        require(msg.value == requiredAmount, "Incorrect ETH amount sent");
        
        // Transfer the ticket price to the event organiser.
        payable(eventOrganiser).transfer(ticketPrice);
        // Update fee pool.
        feePool += fee;

        // Mint the ticket NFT to the buyer.
        concertTicket.mint(msg.sender, uint256(category));
        
        // Update available ticket count.
        uint256 currentAvailable = concertTicket.getTicketAvailability(ConcertTicket.CAT(uint8(category)));
        uint256 newAvailability = currentAvailable - 1;
        concertTicket.updateTicketAvailability(ConcertTicket.CAT(uint8(category)), newAvailability);

        // Award loyalty points for the purchase.
        loyaltySystem.addPoints(msg.sender, 100);

        emit TicketMinted(msg.sender, category);
    }
    
    // -------------------------------------------------
    // WITHDRAW REGISTRATION FUNDS
    // -------------------------------------------------
    
    /**
     * @notice Allows non-winning registrants to withdraw their registration funds.
     * Withdrawals are allowed only during the registration period.
     * @param category The seating category for which the user registered.
     */
    function withdrawRegistration(CAT category) external {
        require(block.timestamp < registrationEnd, "Registration period ended. Withdrawal not allowed");

        UserRegistration storage userReg = userRegistrations[msg.sender];
        require(userReg.exists, "No registration found");
        require(uint8(userReg.category) == uint8(category), "Registration not for this category");
        
        Registration[] storage regs = registrations[category];
        uint256 refundAmount = 0;
        for (uint256 i = 0; i < regs.length; ) {
            if (regs[i].registrant == msg.sender) {
                refundAmount += regs[i].amount;
                regs[i] = regs[regs.length - 1];
                regs.pop();
            } else {
                i++;
            }
        }
        require(refundAmount > 0, "Nothing to withdraw");
        delete userRegistrations[msg.sender];
        payable(msg.sender).transfer(refundAmount);
    }
    
    // -------------------------------------------------
    // FEE WITHDRAWAL
    // -------------------------------------------------
    
    /**
     * @notice Allows the deployer to withdraw the collected fees.
     */
    function withdrawFees() external onlyDeployer {
        uint256 amount = feePool;
        feePool = 0;
        payable(deployer).transfer(amount);
        emit FeeWithdrawn(amount);
    }
    
    // -------------------------------------------------
    // ADMIN UPDATE FUNCTIONS
    // -------------------------------------------------
    
    /**
     * @notice Updates the event organiser address.
     * @param _newOrganiser The new event organiser.
     */
    function updateEventOrganiser(address _newOrganiser) external onlyDeployer {
        require(_newOrganiser != address(0), "Invalid organiser address");
        eventOrganiser = _newOrganiser;
    }
    
    /**
     * @notice Updates the marketplace address.
     * @param _newMarketplace The new marketplace address.
     */
    function updateMarketplace(address _newMarketplace) external onlyDeployer {
        require(_newMarketplace != address(0), "Invalid marketplace address");
        marketplace = _newMarketplace;
    }
    
    /**
     * @notice Updates the LoyaltySystem contract address.
     * @param _newLoyalty The new LoyaltySystem address.
     */
    function updateLoyaltySystem(address _newLoyalty) external onlyDeployer {
        require(_newLoyalty != address(0), "Invalid loyalty system address");
        loyaltySystem = ILoyaltySystem(_newLoyalty);
    }
    
    // -------------------------------------------------
    // GETTER FUNCTIONS
    // -------------------------------------------------
    
    /**
     * @notice Returns the registration details for a given user.
     * @param user The address of the user.
     * @return The UserRegistration struct for that user.
     */
    function getUserRegisteration(address user) external view returns (UserRegistration memory) {
        return userRegistrations[user];
    }
    
    // -------------------------------------------------
    // UPDATE EXPIRED LOTTERY WINNERS
    // -------------------------------------------------
    
    /**
     * @notice Reassigns expired lottery winners.
     * This function is called after the claim window has closed (i.e., 2 hours before concert start)
     * to remove unclaimed lottery winners and update ticket availability in the ConcertTicket contract.
     * @param category The seating category to update.
     */
    function updateExpiredWinners(CAT category) external onlyDeployer {
        uint256 concertStart = concertTicket.concertStartDate();
        // Ensure it's time to update expired winners: after (concertStart - CLAIM_BUFFER).
        require(block.timestamp > concertStart - CLAIM_BUFFER, "Not yet time to update expired winners");
        
        LotteryWinner[] storage winners = lotteryWinners[category];
        uint256 expiredCount = 0;
        for (uint256 i = 0; i < winners.length; ) {
            if (!winners[i].claimed) {
                expiredCount++;
                // Remove expired winner entry by swapping with the last element and popping.
                winners[i] = winners[winners.length - 1];
                winners.pop();
            } else {
                i++;
            }
        }
        // Update ticket availability in ConcertTicket by adding back the expired winners.
        if (expiredCount > 0) {
            uint256 currentAvailable = concertTicket.getTicketAvailability(ConcertTicket.CAT(uint8(category)));
            uint256 newAvailability = currentAvailable + expiredCount;
            concertTicket.updateTicketAvailability(ConcertTicket.CAT(uint8(category)), newAvailability);
        }
    }
}