const { Console } = require('console');
const Web3 = require('web3');
const helper = require('./utils/utils.js');
const Vesting = artifacts.require('Vesting');
const Token = artifacts.require('MFToken');

contract('Vesting', async (accounts) => {

    let vesting;
    let token;
    let vestingAddr;    
    const [trader0, trader1, trader2, trader3, trader4, trader5, trader6, trader7, trader8, trader9] = 
    [accounts[0], accounts[1], accounts[2], accounts[3], accounts[4], accounts[5], accounts[6], accounts[7], accounts[8], accounts[9]];
    const fs = require('fs');
    const seedRoundArray = fs.readFileSync('./test/IDO.txt').toString().split("\n");
    const investorsArray = seedRoundArray.map(inves => inves.split(", ")[0]);

    // SEED ROUND  
    let seedStart;        
    const seedPhaseId       = 1;
    const seedCliff         = 60*10;  
    const seedCliffPercent  = 50; // multiply by 10, because could be fractional percentage, like - 7,5
    const seedDuratin       = 60*60; // duration of the vesting period arter cliff in seconds (total duration - cliff)         
    const seedSlice         = 60*5;   
    const seedPhaseName     = 'SEED';

    beforeEach(async() => {
        token = await Token.deployed();
        vesting = await Vesting.deployed();
        vestingAddr = vesting.address; 
        seedStart = await web3.eth.getBlock('latest').then(t=>t.timestamp);
    });

    const changeTime = async (sec) => {
        const originalBlock = await web3.eth.getBlock('latest');
        await helper.advanceTimeAndBlock(sec); // 
        const newBlock = await web3.eth.getBlock('latest');

        console.log('---------------TIME CHANGING---------------');
        console.log('  before: ', originalBlock.timestamp);
        console.log('  after: ', newBlock.timestamp);
    }

    it('Read test variables', async () => {
        const tokenAddr = await vesting.getToken();
        console.log('token addr: ', tokenAddr);
    });

    it('Ballance of Token', async () => {
        const balance = await token.balanceOf(trader0);
        const totalSupply = await token.totalSupply();
        console.log('total supply: ', BigInt(totalSupply));
        console.log('owner balance: ', BigInt(balance));
        console.log('owner of token: ', await token.owner());
    });

    it('Fill balance of vesting contract', async () => {
        const amount = web3.utils.toWei('170000000');
        await token.transfer(vestingAddr, amount, { from: trader0 });
        const vestBalance = await token.balanceOf(vestingAddr);
        const ownerBalance = await token.balanceOf(trader0);
        console.log('vesting balance: ', BigInt(vestBalance));
        console.log('owner balance: ', BigInt(ownerBalance));
    });

    // it('Withdrawing from vesting balance to admin', async () => {
    //     const amount = web3.utils.toWei('170000000');
    //     await vesting.withdraw(amount, { from: trader0 });
    //     const vestBalance = await token.balanceOf(vestingAddr);
    //     const ownerBalance = await token.balanceOf(trader0);
    //     console.log('vesting balance after withdraw: ', BigInt(vestBalance));
    //     console.log('owner balance after withdraw: ', BigInt(ownerBalance));
    // });

    // it('Granting SA role', async () => {
    //     await vesting.grantSARole(trader1, { from: trader0 });
    // });
    
    it('Create vesting schedules IDO', async () => {    

        // IDO ROUND  
        let idoStart = await web3.eth.getBlock('latest').then(t=>t.timestamp);        
        const idoPhaseId       = 1;
        const idoCliff         = 0;  
        const idoCliffPercent  = 200; // multiply by 10, because could be fractional percentage, like - 7,5
        const idoSlice         = 60*10;   
        const idoDuratin       = idoSlice*8; // duration of the vesting period arter cliff in seconds (total duration - cliff)         
        const idoPhaseName     = 'IDO';

        console.log('idoStart: ', idoStart);
        await vesting.createVestingPhase(
            idoPhaseId,
            idoStart,
            idoDuratin,
            idoCliff,
            idoCliffPercent,
            idoSlice,
            idoPhaseName
            , { from: trader0 }
        );
        console.log('new vesting phase created');

        let amount;
        let investor;
        for(i in seedRoundArray) {
            investArray = seedRoundArray[i].split(", ");
            amount = parseFloat(investArray[1]);
            amount = web3.utils.toWei(String(amount));
            investor = investArray[0];
            await vesting.addInvestor(
                investor,                   
                amount,     
                idoCliffPercent,    
                idoPhaseId
                , { from: trader0 } 
            );
            console.log('added new investor: ' + investor + ' - ' + amount + ' MFT');
        };  

    });


    it('Get vesting schedule by address and index', async () => {
               
        // Info block
        const VestingTotalAmount = await vesting.getvestingTotalAmount();
        console.log('vesting total amount: ', BigInt(VestingTotalAmount));

        //
        for(i in investorsArray) {
            investor = investorsArray[i];
            const VScount = await vesting.getVestingSchedulesCountByInvestor(investor);
            let ind;
            for (ind = 0; ind < VScount.toNumber(); ind++) {
                vestingSchedule = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
                console.log(`${i}). Vesting schedule N${ind} of beneficiary: ${investor} - `, BigInt(vestingSchedule.amount));
            }
        }; 

    });

    it('Get vesting schedule array by address', async () => {
        vestingScheduleArray = await vesting.getScheduleArrayByInvestor(investorsArray[0]);
        console.log('vestingScheduleArray', vestingScheduleArray);
    });

    it('Release to investors accounts. Before cliff', async () => {
        
        console.log('Balance of investor must be 20%');
        let balanceOfInvestor;
        for(i in investorsArray) {
            investor = investorsArray[i];
            balanceOfInvestor = await token.balanceOf(investor);
            console.log('Balance of investor: ' + investor + ' - ' + BigInt(balanceOfInvestor));
        };

        for(i in investorsArray) {
            investor = investorsArray[i];
            const VScount = await vesting.getVestingSchedulesCountByInvestor(investor);
            let ind;
            for (ind = 0; ind < VScount.toNumber(); ind++) {
                vestingScheduleId = await vesting.computeInvestorDataIdForAddressAndIndex(investor, ind);
                vestingSchedule = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
                //console.log('vestingSchedule: ', vestingSchedule);
                ReleasableAmount = await vesting.computeReleasableAmount(vestingScheduleId);
                console.log('  - ReleasableAmount: ', BigInt(ReleasableAmount));
                await vesting.release(vestingScheduleId, BigInt(ReleasableAmount));
                console.log(`${i}). Released schedule ID ${vestingScheduleId} for investor: ${investor}. Amount = `, BigInt(ReleasableAmount));  

                // vestingSchedule2 = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
                // console.log(vestingSchedule);
                // console.log(vestingSchedule2);

            }
        }; 

        console.log('Balance of investor must be 0. because cliff');
        for(i in investorsArray) {
            investor = investorsArray[i];
            balanceOfInvestor = await token.balanceOf(investor);
            console.log('Balance of investor: ' + investor + ' - ' + balanceOfInvestor);
        };

    });

    // it('Next release. After cliff', async () => {

    //     await changeTime(seedCliff); // проматываем клиф

    //     for(i in investorsArray) {
    //         investor = investorsArray[i];
    //         const VScount = await vesting.getVestingSchedulesCountByInvestor(investor);
    //         let ind;
    //         for (ind = 0; ind < VScount.toNumber(); ind++) {
    //             vestingScheduleId = await vesting.computeInvestorDataIdForAddressAndIndex(investor, ind);
    //             vestingSchedule = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
    //             ReleasableAmount = await vesting.computeReleasableAmount(vestingScheduleId);
    //             console.log('  - ReleasableAmount: ', BigInt(ReleasableAmount));
    //             await vesting.release(vestingScheduleId, BigInt(ReleasableAmount));
    //             console.log(`${i}). Released schedule ID ${vestingScheduleId} for investor: ${investor}. Amount = `, BigInt(ReleasableAmount));
                
    //             // vestingSchedule2 = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
    //             // console.log(vestingSchedule2);
    //         }
    //     }; 

    //     console.log('Balance of investor must be % of cliff');
    //     for(i in investorsArray) {
    //         investor = investorsArray[i];
    //         balanceOfInvestor = await token.balanceOf(investor);
    //         console.log('Balance of investor: ' + investor + ' - ' + BigInt(balanceOfInvestor));
    //     };

    //     const VestingTotalAmount = await vesting.getvestingTotalAmount();
    //     console.log('vesting total amount: ', BigInt(VestingTotalAmount));

    // });

    it('Next release. First slice', async () => {

        const idoSlice = 60*10;
        await changeTime(idoSlice); // проматываем первый слайс

        for(i in investorsArray) {
            investor = investorsArray[i];
            const VScount = await vesting.getVestingSchedulesCountByInvestor(investor);
            let ind;
            for (ind = 0; ind < VScount.toNumber(); ind++) {
                vestingScheduleId = await vesting.computeInvestorDataIdForAddressAndIndex(investor, ind);
                vestingSchedule = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
                ReleasableAmount = await vesting.computeReleasableAmount(vestingScheduleId);
                await vesting.release(vestingScheduleId, BigInt(ReleasableAmount));
                console.log(`${i}). Released schedule ID ${vestingScheduleId} for investor: ${investor}. Amount = `, BigInt(ReleasableAmount)); 

                // vestingSchedule2 = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
                // console.log(vestingSchedule2);
            }
        }; 

        console.log('Balance of investor must be amount of slice');
        for(i in investorsArray) {
            investor = investorsArray[i];
            balanceOfInvestor = await token.balanceOf(investor);
            console.log('Balance of investor: ' + investor + ' - ' + BigInt(balanceOfInvestor));
        };

        const VestingTotalAmount = await vesting.getvestingTotalAmount();
        console.log('vesting total amount: ', BigInt(VestingTotalAmount));

    });

    it('Release for all next slices', async () => {
        
        const idoSlice = 60*10;
        for (let j = 0; j < 8; j++) {

            await changeTime(idoSlice); // проматываем следующий слайс

            for(i in investorsArray) {
                investor = investorsArray[i];
                const VScount = await vesting.getVestingSchedulesCountByInvestor(investor);
                let ind;
                for (ind = 0; ind < VScount.toNumber(); ind++) {

                    vestingScheduleId = await vesting.computeInvestorDataIdForAddressAndIndex(investor, ind);
                    vestingSchedule = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
                    ReleasableAmount = await vesting.computeReleasableAmount(vestingScheduleId);
                    console.log('  - ReleasableAmount: ', BigInt(ReleasableAmount));
                    await vesting.release(vestingScheduleId, BigInt(ReleasableAmount));
                    console.log(`${i}). Released schedule ID ${vestingScheduleId} for investor: ${investor}. Amount = `, BigInt(ReleasableAmount));  

                    // vestingSchedule2 = await vesting.getVestingScheduleByAddressAndIndex(investor, ind);
                    // console.log(vestingSchedule2);

                    const VestingTotalAmount = await vesting.getvestingTotalAmount();
                    console.log('vesting total amount: ', BigInt(VestingTotalAmount));

                }
            }; 
        };

        console.log('Balance of investor must be full');
        for(i in investorsArray) {
            investor = investorsArray[i];
            balanceOfInvestor = await token.balanceOf(investor);
            console.log('Balance of investor: ' + investor + ' - ' + balanceOfInvestor);
        };

        const VestingTotalAmount = await vesting.getvestingTotalAmount();
        console.log('vesting total amount: ', BigInt(VestingTotalAmount));

    });




    // !!! После юнит тестов нужно перезапустить ганаш. т.к. время остается смещеным. 

    // Что бы проверить релиз через акаунт инвестора. нужен список адресов инвесторо в тхт файле совпадающий с акаунтами ганаша.
    // Пример: release(vestingScheduleId, amount, { from: investor });





    // Проверить фазу seed
    // 1. снять все после окончания вестинга
    // 2. снять до окончания клифа (0)
    // 3. снять все этапы вовремя (сравнить итоговые суммы что бы сошлись с тотал эмаунтом)
    // 4. снять после первого слайса (с процентами после клифа), потом все вовремя (сравнить итоговые суммы что бы сошлись с тотал эмаунтом)
    // 5. снять после половины слайсов, потом после окончания вестинга (сравнить итоговые суммы что бы сошлись с тотал эмаунтом)
    // 6. снять после половины слайсов, потом все вовремя (сравнить итоговые суммы что бы сошлись с тотал эмаунтом)
    // 7. снять после половины слайсов, потом рандомно (сравнить итоговые суммы что бы сошлись с тотал эмаунтом)
    // 8. снять после клифа, потом рандомно (сравнить итоговые суммы что бы сошлись с тотал эмаунтом)
    // 9. снимать все рандомно (сравнить итоговые суммы что бы сошлись с тотал эмаунтом)
    // 10.снять после клифа и первого слайса, и пробовать снимать до второго слайса

    // 10. Проверить этапы с % после клифа = 0 (Team, Operations and Legal, Development). 
    // В таких нужно задавать клиф - слайс. т.к. выплаты после клифа не будет (если % = 0) до следующего периода. 
    // Либо дату начала с учетом клифа, а клиф = 0 (1сек).

    // 11. Проверить этапы с % после клифа, но без клифа (IDO)

    // 12. Этапы (community/airdrop) вообще не понятно как работают

    // 13. Этап (Rewards) нужно разбить на 2: этап с клифом и сразу выплата и второй этап через 48 мес. но там не понятно что делать

    // 14. Этап (Operations and Legal) похоже нужно задать как: клиф 3 мес, % на квартал

    // 15. Проверить случаи когда инвестор участвует в нескольких фазах вестинга. Причем тут могут быть разные комбинации.
    // Когда инвстор заберет токены вовремя после каждой фазы и когда будет забирать после прошествия одной или нескольких фаз

});
