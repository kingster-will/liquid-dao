const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

describe("ApeClaim.sol: Unit Test", function () {
    let ApeClaim;
    let apeClaim;
    let owner;
    let yx;
    let addrs;

    beforeEach(async function () {
        // Get the ContractFactory and Signers here.
        ApeClaim = await ethers.getContractFactory("ApeClaim");
        [owner, ...addrs] = await ethers.getSigners();
        apeClaim = await ApeClaim.deploy();
    });

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            expect(await apeClaim.owner()).to.equal(owner.address);
        });

        it("Balance should be 0 ", async function () {
            const provider = waffle.provider;
            const balance0ETH = await provider.getBalance(apeClaim.address);
            expect(balance0ETH).to.equal(0);
        });

        it("Whitelist should be empty", async function() {
            expect(await apeClaim.lpsCount()).to.equal(0);
        })
    });

    describe("Whitelist", function () {
        it("Should be able add LP into whitelist", async function () {
            await apeClaim.addLP([addrs[0].address, addrs[1].address, addrs[2].address]);
            expect(await apeClaim.lpsCount()).to.equal(3);
        })

        it("Should be able remove LP from whitelist", async function () {
            await apeClaim.addLP([addrs[0].address, addrs[1].address, addrs[2].address]);
            expect(await apeClaim.lpsCount()).to.equal(3);

            await apeClaim.removeLP([addrs[0].address]);
            expect(await apeClaim.lpsCount()).to.equal(2);
        })

        it("Should NOT be able change whitelist after confirm and lock whitelist", async function () {
            for (const addr of addrs) {
                await apeClaim.addLP([addr.address]);
            }
            expect(await apeClaim.lpsCount()).to.equal(106);
            await apeClaim.confirmAndLockWhiteList();
            await expect(apeClaim.removeLP([addrs[0].address])).to.be.revertedWith("ApeClaim: whitelist has already been locked and finalized");
        })

    });

    describe("LP Claim", function () {
        it("LP should be able to claim ETH", async function () {
            for (const addr of addrs) {
                await apeClaim.addLP([addr.address]);
            }
            expect(await apeClaim.lpsCount()).to.equal(106);
            await apeClaim.confirmAndLockWhiteList();

            await expect(owner.sendTransaction({
                to: apeClaim.address,
                value: ethers.utils.parseEther("106"), // Sends exactly 106 ethers
            })).to.emit(apeClaim, "Received")
                .withArgs(owner.address, ethers.utils.parseEther("106"));

            const provider = waffle.provider;
            let balance = await provider.getBalance(apeClaim.address);
            expect(balance).to.equal(ethers.utils.parseEther("106"));

            expect(await apeClaim.getClaimable(addrs[0].address)).to.equal(ethers.utils.parseEther("1"));
            for (const addr of addrs) {
                expect(await apeClaim.getClaimable(addr.address)).to.equal(ethers.utils.parseEther("1"));
            }

            await expect(apeClaim.connect(addrs[0]).claim()).to
                .emit(apeClaim, "Claimed")
                .withArgs(addrs[0].address, ethers.utils.parseEther("1"));
            balance = await provider.getBalance(addrs[0].address);
            expect(balance).to.be.closeTo(ethers.utils.parseEther("10001"), ethers.utils.parseEther("0.01"));
        });

        it("LP can claim multiple times", async function() {
            let lp1 = addrs[3];
            let lp2 = addrs[4];
            const provider = waffle.provider;
            let balance;
            for (const addr of addrs) {
                await apeClaim.addLP([addr.address]);
            }
            expect(await apeClaim.lpsCount()).to.equal(106);
            await apeClaim.confirmAndLockWhiteList();

            await expect(owner.sendTransaction({
                to: apeClaim.address,
                value: ethers.utils.parseEther("106"), // Sends exactly 106 ethers
            })).to.emit(apeClaim, "Received")
                .withArgs(owner.address, ethers.utils.parseEther("106"));

            balance = await provider.getBalance(apeClaim.address);
            expect(balance).to.equal(ethers.utils.parseEther("106"));

            expect(await apeClaim.getClaimable(lp1.address)).to.equal(ethers.utils.parseEther("1"));

            await expect(apeClaim.connect(lp1).claim()).to
                .emit(apeClaim, "Claimed")
                .withArgs(lp1.address, ethers.utils.parseEther("1"));
            balance = await provider.getBalance(lp1.address);
            expect(balance).to.be.closeTo(ethers.utils.parseEther("10001"), ethers.utils.parseEther("0.01"));

            await expect(owner.sendTransaction({
                to: apeClaim.address,
                value: ethers.utils.parseEther("53"), // Sends exactly 106 ethers
            })).to.emit(apeClaim, "Received")
                .withArgs(owner.address, ethers.utils.parseEther("53"));
            balance = await provider.getBalance(apeClaim.address);
            expect(balance).to.equal(ethers.utils.parseEther("158"));

            // lp1 should claim 0.5 ETH
            await expect(apeClaim.connect(lp1).claim()).to
                .emit(apeClaim, "Claimed");
            balance = await provider.getBalance(lp1.address);
            expect(balance).to.be.closeTo(ethers.utils.parseEther("10001.5"), ethers.utils.parseEther("0.1"));
            // lp2 Should claim 1.5 ETH
            await expect(apeClaim.connect(lp2).claim()).to
                .emit(apeClaim, "Claimed");
            balance = await provider.getBalance(lp2.address);
            expect(balance).to.be.closeTo(ethers.utils.parseEther("10001.5"), ethers.utils.parseEther("0.02"));
            balance = await provider.getBalance(apeClaim.address);
            expect(balance).to.be.closeTo(ethers.utils.parseEther("156"), ethers.utils.parseEther("0.03") );
        });
    });
});
    