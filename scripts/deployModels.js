const fs = require("fs");

async function main() {

    //npx hardhat run scripts/deployModels.js --network mainnet

    const [deployer] = await ethers.getSigners();

    console.log(
        "Starting Deployments from account:",
        deployer.address
    );

    console.log(
        "Deploying Models Contract"
    );

    const prices = [0.4, 0.5, 0.8, 1, 1.25, 1.8, 2.5];

    const modelPrices = prices.map(x => BigInt(Math.round(x * 10 ** 8)));

    const recipient = '0x92009a8A186066Af29F7831B8eC649c245A596BD';

    const quoter = '0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7';
    const swapRouter = '0xcaf681a66d020601342297493863e78c959e5cb2';
    const WETH = '0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73';
    const USDG = '0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168';

    const poolFee = 500;
    const USDGDecimals = 6;

    const models = await ethers.getContractFactory("Models");

    const modelsService = await models.deploy(modelPrices, recipient, quoter, swapRouter, WETH, USDG, poolFee, USDGDecimals);

    const modelsAddress = modelsService.address;

    console.log(
        "Successfully Deployed Models Contract:",
        modelsAddress
    );

}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });