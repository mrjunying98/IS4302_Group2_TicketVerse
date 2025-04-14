const hre = require("hardhat");

async function main() {
  // Get the deployer account.
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // --------------------------
  // Deploy LoyaltySystem
  // --------------------------
  console.log("Deploying LoyaltySystem...");
  const LoyaltySystem = await hre.ethers.getContractFactory("LoyaltySystem");
  const loyaltySystem = await LoyaltySystem.deploy();
  await loyaltySystem.deployed();
  console.log("LoyaltySystem deployed at:", loyaltySystem.address);

  // --------------------------
  // Deploy TicketSalesFactory
  // --------------------------
  console.log("Deploying TicketSalesFactory...");
  const TicketSalesFactory = await hre.ethers.getContractFactory("TicketSalesFactory");
  const factory = await TicketSalesFactory.deploy(loyaltySystem.address);
  await factory.deployed();
  console.log("TicketSalesFactory deployed at:", factory.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });