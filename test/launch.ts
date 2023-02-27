import { expect } from "chai";
import { ethers, network } from "hardhat";
import { BFFMarketplace, BFFCoin } from "../build/typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";

const baseURI = 'https://api.raibbithole.xyz/gallery/metadata/';
const coinAddr = `${process.env.BFFCOIN}`;
const coinHolder = "0xb66963Ff65f208c7e7E31bD23B0702EC3a840c08";

describe("BFFMarketplace", function () {
  let marketplace: BFFMarketplace;
  let coin: BFFCoin;
  let addrs: SignerWithAddress[];
  let holder: SignerWithAddress;

  before(async function () {
    addrs = await ethers.getSigners();

    const Coin = await ethers.getContractFactory("BFFCoin", addrs[0]);
    coin = Coin.attach(coinAddr);

    const BFFMarketplace = await ethers.getContractFactory("BFFMarketplace", addrs[0]);
    marketplace = await BFFMarketplace.deploy(baseURI, coinAddr);

    await helpers.impersonateAccount(coinHolder);
    holder = await ethers.getSigner(coinHolder);
  });

  describe("Launch Item", function () {
    it("Should launch the first item", async function () {
      const currentTime = await helpers.time.latest();
      await marketplace.launchItem(currentTime, currentTime+100, "Test1", ethers.utils.parseEther("1"), 20, 10, 1);
    });
  });

  describe("Mint Item", function () {
    it("Should let user mint item", async function () {
      await coin.connect(holder).approve(marketplace.address, ethers.utils.parseEther('100'));
      await marketplace.connect(holder).mintItem(0, 1, ethers.utils.parseEther('1'));
      const itemBalance = await marketplace.balanceOf(holder.address, 0);
      expect(itemBalance).to.be.equal(1);
      const uri = await marketplace.uri(0);
      expect(uri).to.be.equal(baseURI+'0');
      const coinBalance = await coin.balanceOf(marketplace.address);
      expect(coinBalance).to.be.equal(ethers.utils.parseEther('1'));
    });

    it("Should reject user to mint unlisted item", async function () {
      const res = marketplace.connect(holder).mintItem(1, 1, ethers.utils.parseEther('0'));
      await expect(res).to.be.rejectedWith('InvalidTime()');
    });

    it("Should reject user to mint with insufficient BFFCoin", async function () {
      const res = marketplace.connect(holder).mintItem(0, 1, ethers.utils.parseEther('0.5'));
      await expect(res).to.be.rejectedWith('InvalidPayment()');
    });

    it("Should reject owner to claim during mint time", async function () {
      const res = marketplace.ownerMint(0, addrs[0].address, 2);
      await expect(res).to.be.rejectedWith('InvalidTime()');
    });

    it("Should reject owner to claim unlisted item", async function () {
      const res = marketplace.ownerMint(1, addrs[0].address, 2);
      await expect(res).to.be.rejectedWith('Nonexistent()');
    });

    it("Should let owner claim item", async function () {
      const tokenInfo = await marketplace.tokenMetadata(0);
      await helpers.time.increaseTo(tokenInfo.endMintTime);
      await marketplace.ownerMint(0, addrs[0].address, 2);
    });

    it("Should reject owner to claim over maximum supply", async function () {
      await marketplace.ownerMint(0, addrs[0].address, 17);
      const res = marketplace.ownerMint(0, addrs[0].address, 1);
      await expect(res).to.be.rejectedWith('InvalidAmount()');
      const balance = await marketplace.balanceOf(addrs[0].address, 0);
      expect(balance).to.be.equal(19);
      const totalSupply0 = await marketplace.totalSupply(0);
      expect(totalSupply0).to.be.equal(20);

      const totalSupply1 = await marketplace.totalSupply(1);
      expect(totalSupply1).to.be.equal(0);
    });

    it("Should reject user to mint after mint time", async function () {
      const res = marketplace.connect(holder).mintItem(0, 1, ethers.utils.parseEther('1'));
      await expect(res).to.be.rejectedWith('InvalidTime()');
    });

    it("Should reject user to mint before mint time", async function () {
      const currentTime = await helpers.time.latest();
      await marketplace.launchItem(currentTime+10, currentTime+20, "Test2", ethers.utils.parseEther("2"), 10, 5, 1);

      const res = marketplace.connect(holder).mintItem(1, 2, ethers.utils.parseEther('4'));
      await expect(res).to.be.rejectedWith('InvalidTime()');

      await marketplace.ownerMint(1, addrs[0].address, 3);
    });

    it("Should reject user to mint over limitation per tx", async function () {
      const tokenInfo = await marketplace.tokenMetadata(1);
      await helpers.time.increaseTo(tokenInfo.startMintTime);
      const res = marketplace.connect(holder).mintItem(1, 2, ethers.utils.parseEther('4'));
      await expect(res).to.be.rejectedWith('InvalidAmount()');
    });

    it("Should reject user to mint over public supply", async function () {
      await marketplace.connect(holder).mintItem(1, 1, ethers.utils.parseEther('2'));
      await marketplace.connect(holder).mintItem(1, 1, ethers.utils.parseEther('2'));
      const res = marketplace.connect(holder).mintItem(1, 1, ethers.utils.parseEther('2'));
      await expect(res).to.be.rejectedWith('InvalidAmount()');
    });

    it("Should withdraw BFFCoin", async function () {
      const res = marketplace.connect(holder).withdraw(ethers.utils.parseEther('2'), addrs[0].address);
      await expect(res).to.be.rejected;
      await marketplace.withdraw(ethers.utils.parseEther('5'), addrs[0].address);
      const ownerBal = await coin.balanceOf(addrs[0].address);
      expect(ownerBal).to.be.equal(ethers.utils.parseEther('5'));
      const contractBal = await coin.balanceOf(marketplace.address);
      expect(contractBal).to.be.equal(0);
    });

    it("Should be able to update tokenMetadata", async function () {
      const currentTime = await helpers.time.latest();
      await marketplace.updateItem(0, currentTime, currentTime+20, "Test2.1", ethers.utils.parseEther("2"), 50, 30, 10);
      await marketplace.connect(holder).mintItem(0, 10, ethers.utils.parseEther('20'));
      const balance = await marketplace.balanceOf(holder.address, 0);
      expect(balance).to.be.equal(11);
    });

    it("Should be able to update uri", async function () {
      await marketplace.setURI('https://test/');
      const tokenURI = await marketplace.uri(0);
      expect(tokenURI).to.be.equal('https://test/0');
    });

    it("Should be able to update bffcoin address", async function () {
      await marketplace.setBFFCoin(ethers.constants.AddressZero);
      const bffcoin = await marketplace.bffCoin();
      expect(bffcoin).to.be.equal(ethers.constants.AddressZero);
    });
  });
});
