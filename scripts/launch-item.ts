import 'dotenv/config';
import { ethers } from "hardhat";
import { BFFMarketplace } from "../build/typechain";

async function main() {
  let marketplace: BFFMarketplace;
  let addrs = await ethers.getSigners();
  
  //const wallet = new ethers.Wallet(`${process.env.PROJECT_PK}`, ethers.provider)
  
  console.log("Interacting contracts with the account:", addrs[0].address);
  console.log("Account balance:", (await addrs[0].getBalance()).toString());

  const BFFMarketplace = await ethers.getContractFactory("BFFMarketplace", addrs[0]);
  marketplace = BFFMarketplace.attach('0x93Fb5Bb78f5fD1c1e68f2ec01e30956D08710635');
  console.log("Contract address:", marketplace.address);

  const launch = await marketplace.launchItem(0, 0, "Test2", ethers.utils.parseEther("1"), 20, 10, 1)
  const receipt = await launch.wait();
  console.log(receipt.transactionHash);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
