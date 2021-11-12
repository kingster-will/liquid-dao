async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // We get the contract to deploy
    const ApeClaimErc20 = await ethers.getContractFactory("ApeClaimErc20");
    const apeClaimErc20 = await ApeClaimErc20.deploy();
    await apeClaimErc20.initialize("0x2170ed0880ac9a755fd29b2688956bd959f933f8");
    console.log("ApeClaimErc20 deployed to:", apeClaimErc20.address);

}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
