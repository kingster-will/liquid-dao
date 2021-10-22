async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );
    console.log("Account balance:", (await deployer.getBalance()).toString());
    // We get the contract to deploy
    const ForcePad = await ethers.getContractFactory("ForcePad");
    const forcePad = await ForcePad.deploy();

    console.log("ForcePad deployed to:", forcePad.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
