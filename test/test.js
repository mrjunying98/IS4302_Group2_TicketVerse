const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Concert Ticket Sales and Market Place", function () {
  let deployer, eventOrganiser;
  let vrfCoordinatorMock;
  let loyaltySystem, concertTicket, ticketLotterySale;
  let newConcertTicket, newTicketLotterySale, newTicketMarketPlace;
  
  // VRF parameters 
  let subscriptionId = 1;
  let baseFee, gasPriceLink;
  const keyHash = "0x6c3699283bda56ad74f6b855546325b68d482e983852a5edbffde6f5f07a57a4";

  before(async function () {
    [deployer, eventOrganiser, user1, user2, user3, user4, user5, user6] = await ethers.getSigners();

    // --- Deploy VRFCoordinatorV2Mock ---
    baseFee = ethers.parseEther("0.1");
    gasPriceLink = 1e9; // 1e9 wei per gas unit
    const VRFCoordinatorV2Mock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
    vrfCoordinatorMock = await VRFCoordinatorV2Mock.deploy(baseFee, gasPriceLink);
    await vrfCoordinatorMock.waitForDeployment();
    console.log("VRFCoordinatorV2Mock deployed at:", await vrfCoordinatorMock.getAddress());
    
    // Create subscription (assume subscriptionId = 1)
    const txSub = await vrfCoordinatorMock.createSubscription();
    await txSub.wait();

    // Fund subscription with 10 LINK (for testing)
    await vrfCoordinatorMock.fundSubscription(subscriptionId, ethers.parseEther("10"));
    console.log("Subscription funded with ID:", subscriptionId);

    // --- Deploy VRFv2Consumer ---
    const VRFv2Consumer = await ethers.getContractFactory("RandomNumberConsumerV2");
    vrfv2consumer = await VRFv2Consumer.deploy(subscriptionId, await vrfCoordinatorMock.getAddress(), keyHash);
    await vrfv2consumer.waitForDeployment(); 
    console.log("VRFv2Consumer deployed at:", await vrfv2consumer.getAddress());

    // --- Deploy LoyaltySystem ---
    const LoyaltySystem = await ethers.getContractFactory("LoyaltySystem");
    loyaltySystem = await LoyaltySystem.deploy();
    await loyaltySystem.waitForDeployment();
    console.log("LoyaltySystem deployed at:", await loyaltySystem.getAddress());

    // --- Deploy Concert Tickets ---
    const ConcertTicket = await ethers.getContractFactory("ConcertTicket");
    concertTicket = await ConcertTicket.deploy();
    await concertTicket.waitForDeployment();
    console.log("ConcertTicket deployed at:", await concertTicket.getAddress());

    // --- Deploy MarketPlace Tickets ---
    const TicketMarketPlace = await ethers.getContractFactory("TicketMarketPlace");
    ticketMarketPlace = await TicketMarketPlace.deploy();
    await ticketMarketPlace.waitForDeployment();
    console.log("TicketMarketPlace deployed at:", await ticketMarketPlace.getAddress());

    // --- Deploy TicketSalesFactory ---
    const TicketSalesFactory = await ethers.getContractFactory("TicketSalesFactory");
    const cordAddress = await vrfCoordinatorMock.getAddress(); 
    const loyaltyAddress = await loyaltySystem.getAddress();
    ticketSalesFactory = await TicketSalesFactory.deploy(
        loyaltyAddress, 
        subscriptionId, 
        cordAddress, 
        await concertTicket.getAddress(), 
        await ticketMarketPlace.getAddress());
        
    await ticketSalesFactory.waitForDeployment();
    console.log("TicketSalesFactory deployed at:", await loyaltySystem.getAddress());
  });

  // Check if LoyaltySystem, TicketSalesFactory, ConcertTicket and TicketMarketPlace are deployed
  it('Should deploy LoyaltySystem Contract', async function() {
    expect(await loyaltySystem.getAddress()).to.be.properAddress;
  })

  it('Should deploy TicketSalesFactory Contract', async function() {
    expect(await ticketSalesFactory.getAddress()).to.be.properAddress;
  })

  it('Should deploy ConcertTicket Contract', async function() {
    expect(await concertTicket.getAddress()).to.be.properAddress;
  })

  it('Should deploy TicketMarketPlace Contract', async function() {
    expect(await ticketMarketPlace.getAddress()).to.be.properAddress;
  })

  // Create New Concert Using TicketSalesFactory
  // Create New Instance of ConcertTicket, TicketLotterySale and TicketMarketPlace
  it("Should create and setup a new event correctly", async function () {

    // Set up event parameters
    const eventName = "IS4302 Concert";
    const eventSymbol = "IS4302";

    // Set up concert start date and registration period
    const currentTime = Math.floor(Date.now() / 1000);
    const concertStartDate = currentTime + 86400; // Concert starts in 24 hours.
    const registrationStart = currentTime + 60;   // Registration starts in 1 minute.
    const registrationEnd = currentTime + 3600;     // Registration ends in 1 hour.

    // Call createEvent on the TicketSalesFactory.
    const tx = await ticketSalesFactory.connect(deployer).createEvent(
      eventName,
      eventSymbol,
      concertStartDate,
      registrationStart,
      registrationEnd,
      keyHash,
      await eventOrganiser.getAddress()
    );
    
    await tx.wait();

    // Retrieve the EventInfo struct for eventId 0.
    const eventInfo = await ticketSalesFactory.events(0);

    // Check that eventOrganiser is correct.
    expect(eventInfo.eventOrganiser).to.equal(eventOrganiser);

    // Check that deployed addresses are nonzero.
    expect(eventInfo.concertTicket).to.properAddress;
    expect(eventInfo.ticketLotterySale).to.properAddress;
    expect(eventInfo.ticketMarketPlace).to.properAddress;

    console.log("IS4302 Concert Ticket Address: ", eventInfo.concertTicket);
    console.log("IS4302 Ticket Lottery Sale Address: ", eventInfo.ticketLotterySale);
    console.log("IS4302 Ticket Market Place Address: ", eventInfo.ticketMarketPlace);

    newConcertTicket = await ethers.getContractAt("ConcertTicket", eventInfo.concertTicket);
    newTicketLotterySale = await ethers.getContractAt("TicketLotterySale", eventInfo.ticketLotterySale);  
    newTicketMarketPlace = await ethers.getContractAt("TicketMarketPlace", eventInfo.ticketMarketPlace);

    // Set TicketLotterySale and TicketMarketPlace as authorized operators in the LoyaltySystem
    loyaltySystem.connect(deployer).setAuthorizedOperator(eventInfo.ticketLotterySale, true);
    loyaltySystem.connect(deployer).setAuthorizedOperator(eventInfo.ticketMarketPlace, true);

  });

  it("Should update seating details for concert", async function () {

    // Define the new prices for each category.
    // Our enum ordering in ConcertTicket is { A, B, C, D, E } corresponding to indices 0 through 4.
    // The prices (in ETH) are:
    // CAT.A: 0.25 ETH, CAT.B: 0.2 ETH, CAT.C: 0.15 ETH, CAT.D: 0.1 ETH, CAT.E: 0.05 ETH.
    const newPrices = [
      ethers.parseEther("0.25"), // Category A (index 0)
      ethers.parseEther("0.2"),  // Category B (index 1)
      ethers.parseEther("0.15"), // Category C (index 2)
      ethers.parseEther("0.1"),  // Category D (index 3)
      ethers.parseEther("0.05")  // Category E (index 4)
    ];
    const newAvailable = 100; // Assume 100 tickets available for each category
 
    // Loop over each category (0 to 4) and update seating details.
    for (let i = 0; i < 5; i++) {
      // Calling updateSeatingDetails. 
      await newConcertTicket.connect(eventOrganiser).setSeatingDetails(i, newAvailable, newPrices[i]);
    }

    // Verify the seating details are updated.
    for (let i = 0; i < 5; i++) {
      const details = await newConcertTicket.seatingDetails(i);
      // details returns a tuple [available, price]
      expect(details[0]).to.equal(newAvailable);
      expect(details[1]).to.equal(newPrices[i]);
    }

  });

  it("Should not allow non-event organiser to update seating details for concert", async function () {
    expect(await newConcertTicket.connect(eventOrganiser)
        .setSeatingDetails(0, 100, ethers.parseEther("0.25")))
        .to.be.revertedWith("Only Event Organiser Authorised");
  });

  it("Should not allow registration before ticket sales start", async function () {
    // Attempt to register for tickets immediately after deployment (sales start in 1 minute)
    await expect(newTicketLotterySale.connect(user1)
        .register(0, 1, { value: ethers.parseEther("0.25") }))
        .to.be.revertedWith("Registration not active");
  });

  // User should be able to register for 4 tickets and below (after 5mins have passed)
  it("Should allow registration for 1-4 tickets after sales start", async function () {
    // Fast-forward time by 5 minutes (300 seconds)
    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine");

    // User1 registers for 1 Cat A ticket
    await expect(newTicketLotterySale.connect(user1)
        .register(0, 1, { value: ethers.parseEther("0.2525") }))
        .to.not.be.reverted;

    // User2 registers for 2 Cat B tickets
    await expect(newTicketLotterySale.connect(user2)
        .register(1, 2, { value: ethers.parseEther("0.404") }))
        .to.not.be.reverted;

    // User3 registers for 3 Cat C tickets
    await expect(newTicketLotterySale.connect(user3)
        .register(2, 3, { value: ethers.parseEther("0.4545") }))
        .to.not.be.reverted;

    // User4 registers for 4 Cat D tickets
    await expect(newTicketLotterySale.connect(user4)
        .register(3, 4, { value: ethers.parseEther("0.404") }))
        .to.not.be.reverted;
  
    // Check that the tickets have been registered for User1
    const [exist1, category1, numberOfTickets1] = await newTicketLotterySale.getUserRegisteration(user1.getAddress());
    expect(exist1).to.be.true;   
    expect(category1).to.equal(0); // Category A
    expect(numberOfTickets1).to.equal(1); // 1 ticket

    // Check that the tickets have been registered for User2
    const [exist2, category2, numberOfTickets2] = await newTicketLotterySale.getUserRegisteration(user2.getAddress());
    expect(exist2).to.be.true;   
    expect(category2).to.equal(1); // Category B
    expect(numberOfTickets2).to.equal(2); // 1 ticket

    // Check that the tickets have been registered for User3
    const [exist3, category3, numberOfTickets3] = await newTicketLotterySale.getUserRegisteration(user3.getAddress());
    expect(exist3).to.be.true;   
    expect(category3).to.equal(2); // Category C
    expect(numberOfTickets3).to.equal(3); // 1 ticket

    // Check that the tickets have been registered for User3
    const [exist4, category4, numberOfTickets4] = await newTicketLotterySale.getUserRegisteration(user4.getAddress());
    expect(exist4).to.be.true;   
    expect(category4).to.equal(3); // Category C
    expect(numberOfTickets4).to.equal(4); // 1 ticket

    // Check Loyalty Points have been awarded for Pregistering
    const points1 = await loyaltySystem.getPoints(await user1.getAddress());
    const points2 = await loyaltySystem.getPoints(await user2.getAddress()); 
    const points3 = await loyaltySystem.getPoints(await user3.getAddress());
    const points4 = await loyaltySystem.getPoints(await user4.getAddress());

    // 1 ticket: 20 points for Registering
    expect(points1).to.equal(20); // 1 ticket
    expect(points2).to.equal(40); // 2 tickets
    expect(points3).to.equal(60); // 3 tickets
    expect(points4).to.equal(80); // 4 tickets
});

  // User should not be able to register when they want 5 tickets
  it("Should not allow registration for 5 tickets", async function () {
    await expect(newTicketLotterySale.connect(user1)
        .register(0, 5, { value: ethers.parseEther("1.2625") })) // 0.25 * 5 * 1.01 (fee)
        .to.be.revertedWith("Can only register 1 to 4 tickets");
  });

  // User should not be able to register if they don't send sufficient msg.value
  it("Should not allow registration with insufficient payment", async function () {
    // User5 attempts to buy 2 tickets but doesn't send enough ETH
    await expect(newTicketLotterySale.connect(user5)
        .register(1, 2, { value: ethers.parseEther("0.3") })) // Should be 0.4 (0.2 * 2)
        .to.be.revertedWith("Incorrect ETH amount sent");
  });

  // User should not be able to register in different category
  it("Should not allow registration in different category", async function () {
    await expect(newTicketLotterySale.connect(user4)
        .register(1, 1, { value: ethers.parseEther("0.202") })) // User 4 already registered in CAT D
        .to.be.revertedWith("Cannot register for multiple categories");
  });

  // Lottery can only be run after registration period ends
  it("Should not to run lottery before registration ends", async function () {
    await expect(newTicketLotterySale.connect(deployer).runLottery())
        .to.be.revertedWith("Registration still active");
  });

  it("Allow User 3 to withdraw Registration", async function () {
    // User 3 to withdraw registration
    await newTicketLotterySale.connect(user3).withdrawRegistration(2);

    // Check for User 3 Registration
    const reg = await newTicketLotterySale.getUserRegisteration(await user3.getAddress());
    const regExist = reg[0];

    // User 3 Registration should be removed
    expect(regExist).to.be.equal(false);

  });

  // User should not be able to register for tickets after 1hr has passed
  it("Should not allow registration after sales period ends", async function () {
    // Fast-forward time to 1 hour after registration start (registration period is 1 hour)
    // Need to go 55 more minutes (3300 seconds)
    await ethers.provider.send("evm_increaseTime", [3300]);
    await ethers.provider.send("evm_mine");

    // User6 attempts to register after sales period
    await expect(newTicketLotterySale.connect(user6).register(0, 1, { value: ethers.parseEther("0.25") }))
        .to.be.revertedWith("Registration period has ended");
  });

  it("Should run the lottery successfully", async function () {

    // 1. Add Consumers to the VRF Subscription
    await vrfCoordinatorMock.addConsumer(subscriptionId, await newTicketLotterySale.getAddress());
    
    // 2. Run lottery.
    await expect(newTicketLotterySale.connect(deployer).runLottery())
        .to.emit(newTicketLotterySale, "LotteryRequested");
    
    // 3. Get requestId from contract.
    const requestId = await newTicketLotterySale.s_requestId();
    expect(requestId).to.be.gt(0);

    // 4. Verify lottery was requested but not executed yet
    expect(await newTicketLotterySale.lotteryRequested()).to.be.true;
    expect(await newTicketLotterySale.lotteryExecuted()).to.be.false;
    
    // 5. Fulfill the random words request
    // Simulate VRF callback by calling fulfillRandomWords on the mock.
    await vrfCoordinatorMock.fulfillRandomWords(requestId, await newTicketLotterySale.getAddress());
 
    expect(await newTicketLotterySale.lotteryExecuted()).to.be.true;
  });

  it("Should update concert ticket on new availability after lottery run", async function () {
    
    // After the lottery, check the availability of tickets in each category.
    // Availability should be updated based on the lottery results.
    const catAAvailable = await newConcertTicket.getTicketAvailability(0);
    const catBAvailable = await newConcertTicket.getTicketAvailability(1);
    const catCAvailable = await newConcertTicket.getTicketAvailability(2);
    const catDAvailable = await newConcertTicket.getTicketAvailability(3);
    const catEAvailable = await newConcertTicket.getTicketAvailability(4);

    // All users won all tickets registered for as number of available tickets exceeds number of tickets registered
    expect(catAAvailable).to.equal(99);  // User 1 Registered for 1 ticket in CAT A
    expect(catBAvailable).to.equal(98);  // User 2 Registered for 2 tickets in CAT B
    expect(catCAvailable).to.equal(100); // User 3 Registered for 3 tickets in CAT C
    expect(catDAvailable).to.equal(96);  // User 4 Registered for 4 tickets in CAT D
    expect(catEAvailable).to.equal(100); // No one registered for CAT E

  });

  it("Should allow users to mint the tickets and event organiser to receive ETH", async function () {

    // Check the event organiser's balance before minting
    // The event organiser should receive the ETH from ticket sales.
    const eventOrganiserBalanceBefore = await ethers.provider.getBalance(eventOrganiser.getAddress());

    // User1 mints their ticket
    await expect(newTicketLotterySale.connect(user1).claimLotteryTicket(0))
        .to.emit(newTicketLotterySale, "TicketMinted")
        .withArgs(user1.getAddress(), 0);

    // User2 mints their ticket
    await expect(newTicketLotterySale.connect(user2).claimLotteryTicket(1))
        .to.emit(newTicketLotterySale, "TicketMinted")
        .withArgs(user2.getAddress(), 1);

    const eventOrganiserBalanceAfter = await ethers.provider.getBalance(eventOrganiser.getAddress());

    // Check that the event organiser's balance has increased by the correct amount.
    // User1 bought 1 ticket at 0.2525 ETH
    // User2 bought 2 tickets at 0.404 ETH
    // Total = 0.25+ 0.40 = 0.65 ETH
    // Total = 3 Tickets

    // Check if Event Organiser Received ETH
    expect(eventOrganiserBalanceBefore).to.be.equal(eventOrganiserBalanceAfter - ethers.parseEther("0.65"));

    // Check if Number of Tickets Minted is Correct
    expect(await newConcertTicket.ticketIdCounter()).to.equal(3);

    // Check for User Loyalty Points System 
    const points1 = await loyaltySystem.getPoints(await user1.getAddress());
    const points2 = await loyaltySystem.getPoints(await user2.getAddress());
    expect(points1).to.equal(120); // 1 ticket: (20 * 1) + (1 * 100) = 120
    expect(points2).to.equal(240); // 2 tickets: (20 * 2) + (2 * 100) = 240

  });

  it("Should allow user to buy tickets (Excess Ticket Remaining)", async function () {

    // Check the event organiser's balance before minting
    // The event organiser should receive the ETH from ticket sales.
    const eventOrganiserBalanceBefore = await ethers.provider.getBalance(eventOrganiser.getAddress());

    // User5 Buy 1 ticket in CAT A
    await expect(newTicketLotterySale.connect(user5).buyTicket(0, {value: ethers.parseEther("0.2525")}))
        .to.emit(newTicketLotterySale, "TicketMinted")
        .withArgs(user5.getAddress(), 0);

    // Get the event organiser's balance after minting
    const eventOrganiserBalanceAfter = await ethers.provider.getBalance(eventOrganiser.getAddress());

    // Check that the event organiser's balance has increased by the correct amount.
    expect(eventOrganiserBalanceBefore).to.be.equal(eventOrganiserBalanceAfter - ethers.parseEther("0.25"));

    // Check if Number of Tickets Minted is Correct
    expect(await newConcertTicket.ticketIdCounter()).to.equal(4);
    
    // Check CAT A Availablility
    const catAAvailable = await newConcertTicket.getTicketAvailability(0);
    expect(catAAvailable).to.equal(98); // Available tickets should be 98 after User 5 buys 1 ticket

    // Check User 5 Tickets Owned
    const ticketOwned = await newConcertTicket.getTicketsOwnedByAddress(await user5.getAddress());
    expect(ticketOwned.length).to.equal(1);

    // Check User 5 Ticket Ownership 
    const ticketId = ticketOwned[0];
    const ticketOwner = await newConcertTicket.getTicketOwner(ticketId);
    expect(ticketOwner).to.equal(await user5.getAddress());

    // Check if User 5 has been awarded Loyalty Points
    const points5 = await loyaltySystem.getPoints(await user5.getAddress());
    expect(points5).to.equal(100); // 1 ticket: 100

  });

  it("Should not allow User 5 to buy (Excess Ticket Remaining) tickets with incorrect ETH sent ", async function () {
    // User5 tries to buy ticket
    await expect(newTicketLotterySale.connect(user5).buyTicket(0, {value: ethers.parseEther("0.25")}))
        .to.be.revertedWith("Incorrect ETH amount sent");
  });

  it("Should not allow User 4 to withdraw their registration (After Registration Has Ended)", async function () {
    // User5 tries to withdraw their registration after the registration period has ended
    await expect(newTicketLotterySale.connect(user4).withdrawRegistration(3))
        .to.be.revertedWith("Registration period ended. Withdrawal not allowed");
  });


  it("Should revert if User 5 tries to transfer their concert ticket to user6", async function () {
    // oncertTicket is non-transferable (only marketplace can transfer)
    // safeTransferFrom should revert.
    const ticketOwned = await newConcertTicket.getTicketsOwnedByAddress(await user5.getAddress());
    
    // Assume he wants to transfer the first ticket
    const ticketId = ticketOwned[0]; 

    // shiould fail
    await expect(newConcertTicket.connect(user5)
        .safeTransferFrom(await user5.getAddress(), await user6.getAddress(), ticketId))
        .to.be.revertedWith("ERC721: caller is not token owner or approved");

  });
  
  it("Should fail when User 5 lists their ticket at a price higher than the maximum sale price", async function () {
    
    const ticketOwned = await newConcertTicket.getTicketsOwnedByAddress(await user5.getAddress());
    
    // Assume he wants to list the first ticket
    const ticketId = ticketOwned[0]; 

    // Get the original price from ConcertTicket seatingDetails for category 0 (CAT.A)
    const seating = await newConcertTicket.seatingDetails(0);
    const originalPrice = seating[1];

    // Maximum allowed sale price is 1.5× originalPrice.
    const maxPrice = originalPrice * BigInt(15); 
    const maxPrice2 = maxPrice / BigInt(10);

    // Set a listing price that is slightly higher than maxPrice.
    const highPrice = maxPrice2 + ethers.parseEther("0.01");
    
    await expect(newTicketMarketPlace.connect(user5).listTicketForSale(ticketId, highPrice))
        .to.be.revertedWith("Sale price exceeds maximum allowed");
  });

  it("Should Allow User 5 to List their Ticket on Market Place", async function () {
    
    const ticketOwned = await newConcertTicket.getTicketsOwnedByAddress(await user5.getAddress());
    
    // Assume he wants to list the first ticket
    const ticketId = ticketOwned[0]; 

    // Get the original price from ConcertTicket seatingDetails for category 0 (CAT.A)
    const seating = await newConcertTicket.seatingDetails(0);
    const originalPrice = seating[1];

    // Maximum allowed sale price is 1.5× originalPrice.
    const maxPrice = originalPrice * BigInt(15); 
    const maxPrice2 = maxPrice / BigInt(10);
    
    // List ticket for Sale
    await newTicketMarketPlace.connect(user5).listTicketForSale(ticketId, maxPrice2); 

    // Check if Listing is Active on Market Place
    const listing = await newTicketMarketPlace.getListing(ticketId);
    const isActive = listing.active;
    const salePrice = listing.salePrice;
    const seller = listing.seller; 

    // Check if Listing Information is Correct
    expect(isActive).to.be.equal(true);
    expect(salePrice).to.be.equal(maxPrice2);
    expect(seller).to.be.equal(await user5.getAddress());

  });

  it("Should fail when User 5 tries to Double List", async function () {
    
    const ticketOwned = await newConcertTicket.getTicketsOwnedByAddress(await user5.getAddress());
    
    // Assume he wants to list the first ticket
    const ticketId = ticketOwned[0]; 

    // Get the original price from ConcertTicket seatingDetails for category 0 (CAT.A)
    const seating = await newConcertTicket.seatingDetails(0);
    const originalPrice = seating[1];
    // Maximum allowed sale price is 1.5× originalPrice.

    const maxPrice = originalPrice * BigInt(15); 
    const maxPrice2 = maxPrice / BigInt(10);
    
    await expect(newTicketMarketPlace.connect(user5).listTicketForSale(ticketId, maxPrice2))
        .to.be.revertedWith("Ticket already listed");
  });
  
  it("Should allow User 5 to remove their listing, and the listing should no longer exist", async function () {

    const ticketOwned = await newConcertTicket.getTicketsOwnedByAddress(await user5.getAddress());
    
    // Assume he wants to unlist his first ticket that was listed
    const ticketId = ticketOwned[0]; 

    // User5 cancels their listing.
    await expect(newTicketMarketPlace.connect(user5).cancelListing(ticketId))
      .to.emit(newTicketMarketPlace, "ListingCancelled");
  
    // After cancellation, trying to get the listing should revert as listing is no longer active.
    await expect(newTicketMarketPlace.getListing(ticketId))
      .to.be.revertedWith("Listing not active");

  });
  
  it("should revert when User 6 attempts to buy a listed ticket with insufficient ETH", async function () {

    // User 5 To List Ticket for Sale Again
    const ticketOwned = await newConcertTicket.getTicketsOwnedByAddress(await user5.getAddress());
    
    // Assume he wants to list the first ticket
    const ticketId = ticketOwned[0]; 

    // Get the original price from ConcertTicket seatingDetails for category 0 (CAT.A)
    const seating = await newConcertTicket.seatingDetails(0);
    const originalPrice = seating[1];
    
    // Maximum allowed sale price is 1.5× originalPrice.
    const maxPrice = originalPrice * BigInt(15); 
    const maxPrice2 = maxPrice / BigInt(10);
    
    // List ticket for Sale    
    await newTicketMarketPlace.connect(user5).listTicketForSale(ticketId, maxPrice2);

    // Check if Listing is Active on Market Place
    const listing = await newTicketMarketPlace.getListing(ticketId);
    const isActive = listing.active;
    const salePrice = listing.salePrice;
    const seller = listing.seller; 

    expect(isActive).to.be.equal(true);
    expect(salePrice).to.be.equal(maxPrice2);
    expect(seller).to.be.equal(await user5.getAddress());
  
    // Now, user6 attempts to buy the ticket but sends less ETH than required.
    await expect(newTicketMarketPlace.connect(user6).buyTicket(ticketId, { value: ethers.parseEther("0.001") }))
        .to.be.revertedWith("Incorrect ETH sent");
  });
  
  it("should allow User 6 to buy a listed ticket successfully and update the ticket's originalOwner to user6", async function () {
    
    // Assume he wants to buy user5 ticket
    const ticketId = 4; 
    
    // Get Sale Price of Ticket 
    const listing = await newTicketMarketPlace.getListing(ticketId);
    const salePrice = listing.salePrice;
    
    // user6 buys the ticket.
    await expect(newTicketMarketPlace.connect(user6).buyTicket(ticketId, { value: salePrice }))
        .to.emit(newTicketMarketPlace, "TicketSold");
    
    // Check that the ticket's original owner has been updated to user6.
    const newOwner = await newConcertTicket.getTicketOwner(ticketId);
    expect(newOwner).to.be.equal(await user6.getAddress());

    // Check if Listing is No Longer on MarketPlace
    await expect(newTicketMarketPlace.getListing(ticketId))
      .to.be.revertedWith("Listing not active");

    // Check if User 5 has been awarded Loyalty Points for Successful Sale
    const points5 = await loyaltySystem.getPoints(await user5.getAddress());
    const points6 = await loyaltySystem.getPoints(await user6.getAddress());
    expect(points5).to.equal(150); // 100 for Buying + 50 for Selling
    expect(points6).to.equal(100); // 1 ticket: 100 for Buying
  });

  it("Should not allow deployer to reassign lottery winners if time is not right", async function () {
    await expect(newTicketLotterySale.connect(deployer).updateExpiredWinners(1))
      .to.be.revertedWith("Not yet time to update expired winners");
  });

  it("Should allow Deployer to Reassign Lottery Winners if they have not claimed their tickets", async function () {

    const catAAvailableBefore = await newConcertTicket.getTicketAvailability(0);
    const catBAvailableBefore = await newConcertTicket.getTicketAvailability(1);
    const catCAvailableBefore = await newConcertTicket.getTicketAvailability(2);
    const catDAvailableBefore  = await newConcertTicket.getTicketAvailability(3);
    const catEAvailableBefore = await newConcertTicket.getTicketAvailability(4);

    expect(catAAvailableBefore).to.equal(98);  // User 1 and User 5 bought 1 ticket each
    expect(catBAvailableBefore).to.equal(98);  // User 2 bought 2 tickets
    expect(catCAvailableBefore).to.equal(100); // 100 Because User 3 Withdraw their Registration
    expect(catDAvailableBefore).to.equal(96);  // 96 Because User 4 registered for 4 tickets
    expect(catEAvailableBefore).to.equal(100); // No one registered for CAT E

    // --- Fast-forward time to 1.5 hours before concert start ---
    // Claim window is open until concertStart - 2 hours, so at 1.5 hours before, winners have expired.
    // Compute target time: concertStart - 1.5 hours.
    const targetTime = Number(await newConcertTicket.concertStartDate()) - Number(5400); // 5400 seconds = 1.5 hours
    await ethers.provider.send("evm_setNextBlockTimestamp", [targetTime]);
    await ethers.provider.send("evm_mine", []);

    // For Expired Lottery Winners, their Tickets will be foreited and be Open for Sale
    // Deployer will reassign the winners for the expired tickets.
    const nunberOfCAT = 5; 
    for (i = 0; i < nunberOfCAT; i++) {
      await newTicketLotterySale.connect(deployer).updateExpiredWinners(i);
    }
    
    // User 4 Losses their Lottery Rights: All 4 Ticket Forfeited
    const catDAvailableAfter  = await newConcertTicket.getTicketAvailability(3);
    expect(catDAvailableAfter).to.equal(100); // 100 Because User 4 Losses it Lottery Rights
  });

  it("should allow only eventOrganiser to mark a ticket as used after concert start", async function () {
    
    // Get the concert start timestamp from the ConcertTicket contract.
    const concertStart = await newConcertTicket.concertStartDate();
    
    // Fast-forward time to a moment after the concert start.
    // Set concertStart + 10 seconds.
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(concertStart) + 10]);
    await ethers.provider.send("evm_mine", []);
    
    // Attempt to mark the ticket as used by a non-authorized account (user1).
    await expect(newConcertTicket.connect(user1).markAsUsed(1))
        .to.be.revertedWith("Only Event Organiser Authorised");
    
    // Now mark the ticket as used by the eventOrganiser.
    await expect(newConcertTicket.connect(eventOrganiser).markAsUsed(1))
        .to.emit(newConcertTicket, "TicketUsed").withArgs(1);
  });

  it("Should not allow non-event organiser to withdraw fees from TicketLotterySale", async function () {
    // Attempt to withdraw fees by a non-authorized account (user1).
    await expect(newTicketLotterySale.connect(user1).withdrawFees())
        .to.be.revertedWith("Not authorized");
  });

  it("Should allow Deployer to withdraw Fees Collected from LotterySales", async function () {
    // Get the deployer's balance before withdrawal
    const deployerBalanceBefore = await ethers.provider.getBalance(deployer.getAddress());

    // Manually Calculating the Fees
    const totalFees = ethers.parseEther("0.0175");

    // Check the total fees collected is correct
    expect(await newTicketLotterySale.feePool()).to.equal(totalFees);

    // Withdraw fees from the TicketLotterySale contract
    await expect(newTicketLotterySale.connect(deployer).withdrawFees())
      .to.emit(newTicketLotterySale, "FeeWithdrawn");

    // Get the deployer's balance after withdrawal
    const deployerBalanceAfter = await ethers.provider.getBalance(deployer.getAddress());

    // Check that the deployer's balance has increased by the correct amount.
    expect(deployerBalanceAfter).to.be.lt(deployerBalanceBefore + BigInt(totalFees));
  }
  );


});