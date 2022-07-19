require('dotenv').config();

const Web3 = require('web3');
const Provider = require('@truffle/hdwallet-provider');
const { exec } = require('child_process');

const network = process.argv[2] || 'development';

if (network !== 'development' && network !== 'staging') {
    console.error('Network should be development or staging. Other networks are disabled for security reasons.');
    process.exit(1);
}

const testerPrivateKeys = [
    '0x1',
    '0x2',
    '0x3'
], testerNFTs = [ 5, 20, 50 ]

const maxCharacters = 3; // Maximum character types for this moment

let Token, NFT, tokenContractAddress, nftContractAddress, tokenOperationsAddress;

const showTesterBalances = async (amount) => {
    const provider = new Provider({
        privateKeys: [process.env.DEPLOYER_PRIVATE_KEY],
        providerOrUrl: process.env.NETWORK_URL
    });
    const web3 = new Web3(provider);
    const owner = (await web3.eth.getAccounts())[0];

    const token = new web3.eth.Contract(Token.abi, tokenContractAddress);

    for (const testerPrivateKey of testerPrivateKeys) {
        const testerAddress = web3.eth.accounts.privateKeyToAccount(testerPrivateKey).address;
        if (amount && amount !== 0) await token.methods.transfer(testerAddress, amount).send({ from: owner });
        testerBalance = await token.methods.balanceOf(testerAddress).call();
        console.log(`Tester \x1b[36m${testerAddress}\x1b[0m balance:`, BigInt(testerBalance));
    }
    ownerBalance = await token.methods.balanceOf(owner).call();
    console.log(`Owner \x1b[32m${owner}\x1b[0m balance:`, BigInt(ownerBalance));
    tokenOperationsBalance = await token.methods.balanceOf(tokenOperationsAddress).call();
    console.log(`Token operations \x1b[32m${tokenOperationsAddress}\x1b[0m balance:`, BigInt(tokenOperationstBalance));
}

const transferTokenBalance = async () => {
    const provider = new Provider({
        privateKeys: [process.env.DEPLOYER_PRIVATE_KEY],
        providerOrUrl: process.env.NETWORK_URL
    });
    const web3 = new Web3(provider);
    const owner = (await web3.eth.getAccounts())[0];

    const token = new web3.eth.Contract(Token.abi, tokenContractAddress);
    let ownerBalance = await token.methods.balanceOf(owner).call();

    console.log('Before - Token Owner balance:', BigInt(ownerBalance));
    const amount = web3.utils.toWei('1000000');

    await showTesterBalances(amount);

    ownerBalance = await token.methods.balanceOf(owner).call();
    console.log('After - Token Owner balance:', BigInt(ownerBalance));
};

const setCharParams = async () => {
    const provider = new Provider({
        privateKeys: [process.env.DEPLOYER_PRIVATE_KEY],
        providerOrUrl: process.env.NETWORK_URL
    });

    const web3 = new Web3(provider);
    const owner = (await web3.eth.getAccounts())[0];
    const nft = new web3.eth.Contract(NFT.abi, nftContractAddress);

    const charPrice = web3.utils.toWei('1000');

    // console.log('Update mint price to', charPrice);
    // await nft.methods.setCharacterPrice(charPrice).send({ from: owner });
    console.log('Update max character types to', maxCharacters);
    await nft.methods.setMaxCharacterId(maxCharacters).send({ from: owner });
    console.log('Update base URI to', 'https://megagame.com/nft/');
    await nft.methods.setBaseURI('https://megagame.com/nft/').send( { from: owner });
    console.log('Update max number of characters of the same type - 10 000');
    await nft.methods.setMaxCharNumSameType(10000).send({ from: owner });
    console.log('Update server address for NFT: ', owner);
    await nft.methods.setServerAddress(owner).send({ from: owner });
}

const mintNFTs = async () => {
    const mints = [];
    let web3;

    console.log('Minting...');

    for (let testerIndex = 0; testerIndex < testerPrivateKeys.length; testerIndex++) {
        const testerPrivateKey = testerPrivateKeys[testerIndex];

        const provider = new Provider({
            privateKeys: [testerPrivateKey],
            providerOrUrl: process.env.NETWORK_URL
        });
        web3 = new Web3(provider);
        const nft = new web3.eth.Contract(NFT.abi, nftContractAddress);
        const testerAddress = web3.eth.accounts.privateKeyToAccount(testerPrivateKey).address;

        // Approve amount of tokens for token operations contract.
        const token = new web3.eth.Contract(Token.abi, tokenContractAddress); 
        const approveAmount = web3.utils.toWei('1000000000000');
        await token.methods.approve(tokenOperationsAddress, approveAmount).send({ from: testerAddress });

        for (let index = 1; index <= testerNFTs[testerIndex]; index++) {
            result = nft.methods.safeMint(Math.floor(Math.random() * maxCharacters)).send({ from: testerAddress });
            mints.push(result);
        }
    }

    for await (const result of mints) console.log(`Minted NFT transaction hash for \x1b[36m${result.from}\x1b[0m: \x1b[1;35m${result.transactionHash}\x1b[0m`);
    console.log(`Total of \x1b[33m${mints.length}\x1b[0m NFTs generated over \x1b[33m${testerPrivateKeys.length}\x1b[0m addresses`);

    await showTesterBalances(0);
};

const deploy = () => {
    Token = require('../build/contracts/BEP20.json');
    NFT = require('../build/contracts/NFT.json');

    console.log('Uploading contracts...');
    exec(`truffle deploy --reset --network ${network}`, async (error, stdout, stderr) => {
        if (stderr) console.error(`Stderr: ${stderr}`);

        if (error) {
            console.error(`Error: ${error.message}`);
            return;
        }

        if (!stdout) {
            console.error('No stdout');
            return;
        }

        tokenContractAddress = stdout.match(/Token address: (\w+)\n/)[1];
        nftContractAddress = stdout.match(/NFT address: (\w+)\n/)[1];
        tokenOperationsAddress = stdout.match(/TokenOperations address: (\w+)\n/)[1];

        console.log(`Token address: \x1b[36m${tokenContractAddress}\x1b[0m`);
        console.log(`NFT address: \x1b[36m${nftContractAddress}\x1b[0m`);

        await transferTokenBalance();
        await setCharParams();
        await mintNFTs();

        console.log('Done');
        process.exit(0);
    });
}

console.log('Compiling contracts...');
exec(`truffle compile --all`, (error, stdout, stderr) => {
    if (stderr) console.error(`Stderr: ${stderr}`);

    if (error) {
        console.error(`Error: ${error.message}`);
        return;
    }

    if (!stdout) {
        console.error('No stdout');
        return;
    }

    console.log(`Result: ${stdout}`);
    deploy();
});
