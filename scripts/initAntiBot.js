require('dotenv').config();

const Web3 = require('web3');
const Provider = require('@truffle/hdwallet-provider');
const Token = require('./build/contracts/BEP20.json');

const tokenAddress = process.env.TOKEN_ADDRESS;
if (!tokenAddress || tokenAddress === '') throw new Error('Token address missing.');
const vestingAddress = process.env.VESTING_ADDRESS;
if (!vestingAddress || vestingAddress === '') throw new Error('Vesting address missing.');
const tradingStart = process.env.TRADING_START;
if (!tradingStart || tradingStart === '') throw new Error('Trading start missing.');
const maxTransferAmount = process.env.MAX_TRANSFER_AMOUNT;
if (!maxTransferAmount || maxTransferAmount === '') throw new Error('Max transfer amount missing.');

let web3, accounts, vesting;

const initBot = async () => {

    accounts = await web3.eth.getAccounts();
    token = new web3.eth.Contract(Token.abi, tokenAddress);

    await token.methods.initAntibot(tradingStart, maxTransferAmount).call({from: accounts[0], gasLimit: 300000});
    console.log('accounts[0]: ', accounts[0]);
    console.log('Anti bot initialised! Trading start from: ' + tradingStart + '. Max transfer amount: ' + maxTransferAmount);

    whitelisted = true;
    await token.methods.addToWhitelist(vestingAddress, whitelisted).call({from: accounts[0], gasLimit: 300000});
    console.log('Vesting contract address witelisted!');

    console.log('Done');
    process.kill(process.pid, 'SIGTERM');
    
};

(async () => {
    const provider = new Provider({
        privateKeys: [process.env.DEPLOYER_PRIVATE_KEY],
        providerOrUrl: `${ process.env.NETWORK_URL }:${ process.env.NETWORK_PORT }`
    });

    web3 = new Web3(provider);
    initBot();
})();