// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import the required contracts and libraries.
import "./ConcertTicket.sol";
import "./TicketLotterySale.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./TicketMarketPlace.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TicketSalesFactory
 * @notice This factory contract deploys new event-specific contracts using the clone pattern.
 * For each new event, it creates a ConcertTicket clone, a TicketMarketPlace clone, and deploys
 * a new TicketLotterySale contract. It then links these components together.
 */
contract TicketSalesFactory is Ownable {

    // ------------------------------------------------------
    // DATA STRUCTURES
    // ------------------------------------------------------
    
    /**
     * @dev EventInfo holds the addresses of the event-specific contracts.
     * @param eventOrganiser The address of the event organiser.
     * @param concertTicket The ConcertTicket contract instance for the event.
     * @param ticketLotterySale The TicketLotterySale contract instance handling lottery sales.
     * @param ticketMarketPlace The TicketMarketPlace contract instance for secondary ticket sales.
     */
    struct EventInfo {
        address eventOrganiser;
        ConcertTicket concertTicket;
        TicketLotterySale ticketLotterySale;
        TicketMarketPlace ticketMarketPlace;
    }

    // Mapping to store events by eventId.
    mapping(uint256 => EventInfo) public events;
    // Event counter.
    uint256 public nextEventId;

    // Address of the deployed LoyaltySystem contract.
    address public loyaltySystem;
    // Implementation addresses for cloning ConcertTicket and TicketMarketPlace.
    address public concertTicketImplementation;
    address public ticketMarketPlaceImplementation;
    
    // VRF parameters to be passed to the TicketLotterySale contract.
    uint64 public subscriptionId;
    address public vrfCoordinator; 

    // ------------------------------------------------------
    // CONSTRUCTOR
    // ------------------------------------------------------
    
    /**
     * @notice Constructor initializes the factory with core parameters.
     * @param _loyaltySystem Address of the deployed LoyaltySystem contract.
     * @param _subscriptionId Subscription ID for Chainlink VRF.
     * @param _vrfCoordinator Address of the VRFCoordinator contract.
     * @param _concertTicketImplementation Address of the ConcertTicket implementation (for cloning).
     * @param _ticketMarketPlaceImplementation Address of the TicketMarketPlace implementation (for cloning).
     */
    constructor(
        address _loyaltySystem,
        uint64 _subscriptionId,
        address _vrfCoordinator,
        address _concertTicketImplementation,
        address _ticketMarketPlaceImplementation
    ) {
        // Validate provided addresses.
        require(_loyaltySystem != address(0), "Invalid LoyaltySystem address");
        require(_ticketMarketPlaceImplementation != address(0), "Invalid TicketMarketPlace implementation address");
        require(_concertTicketImplementation != address(0), "Invalid ConcertTicket implementation address");
        
        loyaltySystem = _loyaltySystem;
        subscriptionId = _subscriptionId;
        vrfCoordinator = _vrfCoordinator;
        concertTicketImplementation = _concertTicketImplementation;
        ticketMarketPlaceImplementation = _ticketMarketPlaceImplementation;
    }

    // ------------------------------------------------------
    // ADMIN FUNCTIONS
    // ------------------------------------------------------
    
    /**
     * @notice Sets the VRFCoordinator address.
     * @param _vrfCoordinator The new VRFCoordinator address.
     */
    function setVRFCoordinator(address _vrfCoordinator) public onlyOwner { 
        vrfCoordinator = _vrfCoordinator;
    }
    
    // ------------------------------------------------------
    // EVENT CREATION FUNCTION
    // ------------------------------------------------------
    
    /**
     * @notice Creates a new event by deploying the required contracts and linking them.
     * @param eventName The name of the event (used for the ConcertTicket).
     * @param eventSymbol The token symbol for the ConcertTicket.
     * @param concertStartDate The timestamp when the concert starts.
     * @param registrationStart The registration start timestamp.
     * @param registrationEnd The registration end timestamp.
     * @param keyHash The Chainlink VRF key hash.
     * @param eventOrganiser The address of the event organiser.
     * @return eventId The ID assigned to the newly created event.
     *
     * Steps:
     * 1. Create a clone of the ConcertTicket implementation and initialize it.
     * 2. Create a clone of the TicketMarketPlace implementation and initialize it.
     * 3. Deploy a new TicketLotterySale contract using the cloned ConcertTicket and TicketMarketPlace.
     * 4. Update the ConcertTicket contract with the correct marketplace and ticket sale contract addresses.
     * 5. Store the event information and increment the event counter.
     */
    function createEvent(
        string memory eventName,
        string memory eventSymbol,
        uint256 concertStartDate,
        uint256 registrationStart,
        uint256 registrationEnd,
        bytes32 keyHash,
        address eventOrganiser
    ) external returns (uint256 eventId) {
        // ---------------------------
        // Step 1: Deploy ConcertTicket Clone
        // ---------------------------
        // Create a clone of the ConcertTicket implementation.
        address ctClone = Clones.clone(concertTicketImplementation);
        // Initialize the ConcertTicket clone.
        // Note: The third parameter (marketplace) is set to address(0) for now.
        ConcertTicket(ctClone).initialize(eventName, eventSymbol, address(0), concertStartDate, eventOrganiser);
        
        // ---------------------------
        // Step 2: Deploy TicketMarketPlace Clone
        // ---------------------------
        // Create a clone of the TicketMarketPlace implementation.
        address tmpClone = Clones.clone(ticketMarketPlaceImplementation);
        // Initialize the TicketMarketPlace clone with the ConcertTicket clone and LoyaltySystem.
        TicketMarketPlace(tmpClone).initialize(address(ctClone), loyaltySystem);

        // ---------------------------
        // Step 3: Deploy TicketLotterySale Contract
        // ---------------------------
        // Deploy a new TicketLotterySale contract with event-specific parameters.
        TicketLotterySale tls = new TicketLotterySale(
            address(ctClone),             // ConcertTicket address.
            registrationStart,            // Registration start timestamp.
            registrationEnd,              // Registration end timestamp.
            eventOrganiser,               // Event organiser address.
            address(tmpClone),            // Marketplace address (TicketMarketPlace clone).
            loyaltySystem,                // LoyaltySystem address.
            vrfCoordinator,               // VRFCoordinator address.
            subscriptionId,               // VRF subscription ID.
            keyHash,                      // VRF key hash.
            msg.sender                    // Deployer address.
        );

        // ---------------------------
        // Step 4: Update the ConcertTicket Contract
        // ---------------------------
        // Update the ConcertTicket clone to use the correct marketplace.
        ConcertTicket(ctClone).updateMarketplace(address(tmpClone));
        
        // Set the TicketLotterySale contract as the authorized sales contract.
        ConcertTicket(ctClone).setTicketSaleContract(address(tls));

        // ---------------------------
        // Step 5: Record Event Information
        // ---------------------------
        eventId = nextEventId;
        events[eventId] = EventInfo({
            eventOrganiser: eventOrganiser,
            concertTicket: ConcertTicket(ctClone),
            ticketLotterySale: tls,
            ticketMarketPlace: TicketMarketPlace(tmpClone)
        });
        nextEventId++;
        return eventId;
    }
}