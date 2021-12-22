import { ethers } from "hardhat";
import { BigNumber } from 'ethers'

import {
    ShyftLpStaking,
    TestErc20
  } from '../../typechain'

interface TokensFixture {
    token0: TestErc20,
    lpToken: TestErc20,
    rewardToken: TestErc20
}

async function tokensFixture(): Promise<TokensFixture> {
    const tokenFactory = await ethers.getContractFactory('TestERC20')
    const token0 = (await tokenFactory.deploy(BigNumber.from(2).pow(255))) as TestErc20
    const lpToken = (await tokenFactory.deploy(BigNumber.from(2).pow(255))) as TestErc20
    const rewardToken = (await tokenFactory.deploy(BigNumber.from(2).pow(255))) as TestErc20
    return { token0, lpToken, rewardToken }
}

export const shyftLPStakingTestFixture = async function() {
    const shyftLPStakingFactory = await ethers.getContractFactory('ShyftLPStaking')
    const { token0: shyftContract, lpToken, rewardToken } = await tokensFixture()
    const currentBlockNumber = ethers.provider.getBlockNumber()
    const shyftLpStaking = (await shyftLPStakingFactory.deploy(shyftContract.address, 100, currentBlockNumber)) as ShyftLpStaking
    return { shyftLpStaking, lpToken, rewardToken, shyftContract }
}