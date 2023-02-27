import 'dotenv/config';
import { ethers } from "hardhat";

async function main() {
  let addrs = await ethers.getSigners();
  
  //const wallet = new ethers.Wallet(`${process.env.PROJECT_PK}`, ethers.provider)
  
  console.log("Deploying contracts with the account:", addrs[0].address);
  console.log("Account balance:", (await addrs[0].getBalance()).toString());

  const BFFMarketplace = await ethers.getContractFactory("BFFMarketplace", addrs[0]);
  const marketplace = await BFFMarketplace.deploy("https://api.raibbithole.xyz/gallery/metadata/", `${process.env.BFFCOIN}`);
  await marketplace.deployed();
  console.log("Contract address:", marketplace.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
