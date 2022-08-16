// import

const { network, ethers } = require("hardhat")
const { developmentChains, networkConfig } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")

VRF_SUB_FUND_AMOUNT = ethers.utils.parseEther("30")
//main function

//calling of main function

module.exports = async function ({ getNamedAccounts, deployments }) {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    const chainId = network.config.chainId

    //Find out what blockchain we are deploying to - local, test or main
    // if local, use mock in constructor, if testnet or main, use actual address

    let vrfCoordinatorV2Address, subscriptionId

    if (developmentChains.includes(network.name)) {
        const vrfCoordinatorV2Mock = await ethers.getContract("VRFCoordinatorV2Mock")
        vrfCoordinatorV2Address = vrfCoordinatorV2Mock.address

        //create subscription
        const transactionResponse = await vrfCoordinatorV2Mock.createSubscription()
        const transactionReceipt = await transactionResponse.wait(1)
        subscriptionId = transactionReceipt.events[0].args.subId
        // fund the subscription, usually you need a real LINK token but not in a ock
        await vrfCoordinatorV2Mock.fundSubscription(subscriptionId, VRF_SUB_FUND_AMOUNT)
    } else {
        vrfCoordinatorV2 = networkConfig[chainId]["vrfCoordinatorV2"]

        subscriptionId = networkConfig[chainId]["subscriptionId"]
    }

    const entranceFee = networkConfig[chainId]["entranceFee"]
    const gasLane = networkConfig[chainId]["gasLane"]
    const callbackGasLimit = networkConfig[chainId]["callbackGasLimit"]
    const interval = networkConfig[chainId]["interval"]
    console.log("setting up the Args")
    const args = [
        vrfCoordinatorV2Address,
        entranceFee,
        gasLane,
        subscriptionId,
        callbackGasLimit,
        interval,
    ]
    console.log(`Args: ${args.length}`)
    const raffle = await deploy("Raffle", {
        from: deployer,
        args: args,
        log: true,
        waitConfirmations: network.config.blockConfirmations || 1,
    })
    console.log("deployed")
    //verify if not on a dev chain!
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        log("adding auto verify now")
        await verify(raffle.address, args)
    }

    log("Raffle Deployed completed")
    log("---------------------------------------------")
}

module.exports.tags = ["all", "raffle"]