const { expect } = require("chai");
const HRE = require('hardhat');
const { ethers, waffle } = require("hardhat");


const name = "PsPay";
const symbol = "PSPY";
const initialSupply = 750000000;

var BigNumber = require('big-number');
const bigNumber = require("big-number");

const digits = "000000000000000000"

const weiMultiplier = BigNumber(10).power(18);
const NULL_Address = "0x0000000000000000000000000000000000000000";


const provider = waffle.provider;


describe("Token Testing", function () {

  console.log("start testing")

  let Token, token, owner, addr1, addr2;

  const increaseDays = async (days) => {
    await ethers.provider.send('evm_increaseTime', [days * 24 * 60 * 60]);
    await ethers.provider.send('evm_mine');
  };

  const increaseHours = async (days) => {
    await ethers.provider.send('evm_increaseTime', [days * 60 * 60]);
    await ethers.provider.send('evm_mine');
  };

  const currentTime = async () => {
    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    return block.timestamp;
  }

  beforeEach(async () => {

    await HRE.network.provider.request({ method: 'hardhat_impersonateAccount', params: [NULL_Address] });
    nullAccount = await ethers.provider.getSigner(NULL_Address);

    Token = await ethers.getContractFactory("StakingBNB");
    token = await Token.deploy();
    await token.deployed();
    [owner, addr1, addr2, addr3, addr4, addr5, addr6, addr7, addr8, addr9] = await ethers.getSigners();

    await token.connect(addr1).registerUser(owner.address);

    await owner.sendTransaction({ to: token.address, value: ethers.utils.parseEther("100") });
    await addr6.sendTransaction({ to: token.address, value: ethers.utils.parseEther("100") });
    await addr7.sendTransaction({ to: token.address, value: ethers.utils.parseEther("100") });
    await addr8.sendTransaction({ to: token.address, value: ethers.utils.parseEther("100") });
    await addr9.sendTransaction({ to: token.address, value: ethers.utils.parseEther("100") });
  })


  describe("Max Referral Stack test",async()=>{
    
    it("Should return correct eligible referral stack,No stake",async()=>{
      expect((await token._getMaximumReferralStack(addr1.address)).toString()).to.equal(BigNumber(0).toString());
    });

    it("Should return correct eligible referral stack,.01 stake",async()=>{
      await token.connect(addr1).stakeBnb(({
        value:ethers.utils.parseEther("0.012")
      }))
      expect((await token._getMaximumReferralStack(addr1.address)).toString()).to.equal(BigNumber(1).toString());
    });

    it("Should return correct eligible referral stack,.1 stake",async()=>{
      await token.connect(addr1).stakeBnb(({
        value:ethers.utils.parseEther("0.12")
      }))
      expect((await token._getMaximumReferralStack(addr1.address)).toString()).to.equal(BigNumber(2).toString());
    });
    it("Should return correct eligible referral stack,1 stake",async()=>{
      await token.connect(addr1).stakeBnb(({
        value:ethers.utils.parseEther("1.2")
      }))
      expect((await token._getMaximumReferralStack(addr1.address)).toString()).to.equal(BigNumber(3).toString());
    });
    it("Should return correct eligible referral stack,5 stake",async()=>{
      await token.connect(addr1).stakeBnb(({
        value:ethers.utils.parseEther("5.6")
      }))
      expect((await token._getMaximumReferralStack(addr1.address)).toString()).to.equal(BigNumber(4).toString());
    }); 
    it("Should return correct eligible referral stack,10 BNB stake",async()=>{
      await token.connect(addr1).stakeBnb(({
        value:ethers.utils.parseEther("11.2")
      }))
      expect((await token._getMaximumReferralStack(addr1.address)).toString()).to.equal(BigNumber(5).toString());
    });

    it("Should return correct eligible referral stack,10 BNB stake, expired stake",async()=>{
      await token.connect(addr1).stakeBnb(({
        value:ethers.utils.parseEther("11.2")
      }))

      await increaseDays(1000);

      expect((await token._getMaximumReferralStack(addr1.address)).toString()).to.equal(BigNumber(0).toString());
    });



  });
  return;
  
  describe("whale Tax Test",async()=>{

    it("Shoud calculate AntiWhale Tax Correctly",async()=>{

      // <1 %
      let tax =await token._checkAntiWhaleTaxes(BigNumber(4).multiply(weiMultiplier).toString())
      expect(tax.toString(),"<1").to.equal(BigNumber(0).toString());

      tax =await token._checkAntiWhaleTaxes(BigNumber(5).multiply(weiMultiplier).toString())
      expect(tax.toString(),"=1").to.equal(BigNumber(5).multiply(weiMultiplier).multiply(5).divide(100).toString());

      tax =await token._checkAntiWhaleTaxes(BigNumber(95).multiply(weiMultiplier).divide(10).toString())
      expect(tax.toString(),"1.9").to.equal(BigNumber(95).multiply(weiMultiplier).div(10).multiply(5).divide(100).toString());
    });

  });

  describe("Own Earnings Test,single user, Multiple Stake",async()=>{

    it("Should calculate daily Earnings correctly with multiple stakes",async()=>{
      await token.connect(addr1).stakeBnb({
        value:ethers.utils.parseEther("100")
      });

      //Staking 100 BNB, daily earnings = 1%; ->  .9 BNB

      await increaseDays(5);
      await token.connect(addr1).calculateDailyEarnings();
      let stake = await token.stakedBalance(addr1.address);
      console.log("SingleStake",stake)
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 1").to.equal(BigNumber(9).multiply(weiMultiplier).div(10).multiply(5).toString());
      await token.connect(addr1).stakeBnb({value:ethers.utils.parseEther("100")})

      stake = await token.stakedBalance(addr1.address);
      console.log("---------------------------------------------------")
      console.log("2 stakes",stake)
      firstStake = stake[0];
      secondStake = stake[1]
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 1").to.equal(BigNumber(9).multiply(weiMultiplier).div(10).multiply(5).toString());
      
      expect(firstStake["ownEarnings"].add.secondStake["ownEarnings"].toString(),"Daily Earnings, Day 10").to.equal((BigNumber(9).multiply(weiMultiplier).div(10).multiply(10)).add(BigNumber(9).mult(weiMultiplier).div(10).multiply(5)).toString());
      
      });

  })

  describe("Own Earning Test, Single User, Single Stake, No Referral,Inbetween Withdrawals",async()=>{

    it("Should calculate daily Earning Correctly, Single Stake",async()=>{

      await token.connect(addr1).stakeBnb({
        value:ethers.utils.parseEther("100")
      });

      //Staking 100 BNB, daily earnings = 1%; ->  .9 BNB

      await increaseDays(1);
      await token.connect(addr1).calculateDailyEarnings();
      let stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 1").to.equal(BigNumber(9).multiply(weiMultiplier).div(10).toString());

      await increaseDays(9);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 10").to.equal(BigNumber(9).multiply(weiMultiplier).toString());

      await increaseDays(90);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 100").to.equal(BigNumber(90).multiply(weiMultiplier).toString());

      await token.connect(addr1).withdrawOwnBonus(BigNumber(50).multiply(weiMultiplier).toString())
      stake = await token.stakedBalance(addr1.address);
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 100,50 BNB wihdrawan,WITHDRAWOWN BALANCE").to.equal(BigNumber(40).multiply(weiMultiplier).toString());

      await increaseDays(10);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 110").to.equal(BigNumber(49).multiply(weiMultiplier).toString());

      await increaseDays(90);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 200").to.equal(BigNumber(180).multiply(weiMultiplier).toString());

      await increaseDays(50);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 250").to.equal(BigNumber(225).multiply(weiMultiplier).toString());

      await increaseDays(50);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 300").to.equal(BigNumber(225).multiply(weiMultiplier).toString());

      await increaseDays(100);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 400").to.equal(BigNumber(225).multiply(weiMultiplier).toString());

    })
  })

  describe("Staking GainsTest, Single User, Single Stake, No Referral,No Withdrawals",async()=>{

    it("Should calculate daily Earning Correctly, Single Stake",async()=>{

      await token.connect(addr1).stakeBnb({
        value:ethers.utils.parseEther("100")
      });

      //Staking 100 BNB, daily earnings = 1%; ->  .9 BNB

      await increaseDays(1);
      await token.connect(addr1).calculateDailyEarnings();
      let stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 1").to.equal(BigNumber(9).multiply(weiMultiplier).div(10).toString());

      await increaseDays(9);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 10").to.equal(BigNumber(9).multiply(weiMultiplier).toString());

      await increaseDays(90);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 100").to.equal(BigNumber(90).multiply(weiMultiplier).toString());

      await increaseDays(10);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 110").to.equal(BigNumber(99).multiply(weiMultiplier).toString());

      await increaseDays(90);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      // expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 200").to.equal(BigNumber(180).multiply(weiMultiplier).toString());

      await increaseDays(50);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 250").to.equal(BigNumber(225).multiply(weiMultiplier).toString());

      await increaseDays(50);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 300").to.equal(BigNumber(225).multiply(weiMultiplier).toString());

      await increaseDays(100);
      await token.connect(addr1).calculateDailyEarnings();
      stake = await token.stakedBalance(addr1.address);
      expect(stake["ownEarnings"].toString(),"Daily Earnings, Day 400").to.equal(BigNumber(225).multiply(weiMultiplier).toString());

    })
  })

  describe("Staking test, Single User, Single Stake, No referral", async () => {
    
    it("Should allow only registered user to add Stakes",async()=>{

      await expect(token.connect(addr2).stakeBnb({
        value:ethers.utils.parseEther("20")
      })).to.be.revertedWith("User not registered")
    })

    it("Should Handle Single Stake correctly => Update user details", async () => {
      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("100"),
      })
      let stake = await token.stakedBalance(addr1.address);
      expect(stake["totalBalance"].toString(),"Staked Total Balance").to.equal(BigNumber(100).multiply(weiMultiplier).toString());
      expect(stake["balance"].toString(),"Actual Stake").to.equal(BigNumber(100).multiply(weiMultiplier).multiply(90).divide(100).toString());
      expect((await token.connect(addr1).checkMaxEarnings()).toString(),"Max Earning Test").to.equal(BigNumber(100).multiply(weiMultiplier).multiply(90).divide(100).multiply(250).divide(100).toString())
    })

    it("Should increase maxWithdrawal limit when a total staked amount is increased",async()=>{

      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("10"),
      })

      let stake = await token.stakedBalance(addr1.address);
      let initialDailyLimit = stake["maxWithdrawal"].toString();

      expect(initialDailyLimit).to.equal(BigNumber(10).multiply(weiMultiplier).toString());

      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("10")
      })

      expect(initialDailyLimit).to.equal(BigNumber(20).multiply(weiMultiplier).toString());
    })

    it("Should distribute deposit Fee correctly",async()=>{

      const ownerInitialBalance = await provider.getBalance(owner.address);

      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("10"),
      })

      const ownerFinalBalance = await provider.getBalance(owner.address);

      expect(ownerFinalBalance.sub(ownerInitialBalance).toString()).to.equal(BigNumber(1).multiply(weiMultiplier).div(2).toString());
    })
  })
  
  describe("Staking limit Test", async () => {

    it("Should restrict less than minimum amount staking", async () => {

      await expect(token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther(
          ".009"
        )
      })).to.be.revertedWith("Staking amount should be greater than 0.01 BNB");

    })

    it("Should allow minimum amount staking", async () => {

      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("0.01")
      })
    })

    it("Should allow greater than minimum amount &  less than maximum staking", async () => {
      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther(
          "40"
        )
      });
    });

    it("Should Allow maximum amount staking", async () => {

      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther(
          "500"
        )
      });

      it("Should revert greater than maximum amount staking", async () => {

        await expect(token.connect(addr1).stakeBnb({
          value: ethers.utils.parseEther("500.1")
        })).to.be.revertedWith("Staking amount should be less than 500 BNB")
      });

    });


  })

  describe("Base setup", async () => {
    it('Should set the right Owner & MinStake amount', async () => {
      expect(await token.owner()).to.equal(owner.address);
      expect((await token.levelInfo(1)).toString(), "level 1").to.equal((BigNumber(1).multiply(weiMultiplier)).divide(100).toLocaleString());
      expect((await token.levelInfo(2)).toString(), "level 2").to.equal((BigNumber(1).multiply(weiMultiplier)).divide(10).toLocaleString());
      expect((await token.levelInfo(3)).toString(), "level 3").to.equal((BigNumber(1).multiply(weiMultiplier)).toLocaleString());
      expect((await token.levelInfo(4)).toString(), "level 4").to.equal((BigNumber(5).multiply(weiMultiplier)).toLocaleString());
      expect((await token.levelInfo(5)).toString(), "level 5").to.equal((BigNumber(10).multiply(weiMultiplier)).toLocaleString());
    });

  });

  describe("Max withdrawl test", async () => {

    it("Should limit daily max withdrawal correctly", async () => {
      await increaseDays(500);

      await expect(
        token.connect(addr1).withdrawOwnBonus(
          BigNumber(11).multiply(weiMultiplier).div.toString()
        )
      ).to.be.revertedWith("daily withdrawal limit reached");
    })

    it("Should increase daily withdrawal limit correctly", async () => {
      await increaseDays(10);
      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("1")
      })

      await increaseDays(500);
      const initial = await provider.getBalance(addr1.address);

      let tax = BigNumber(15).multiply(weiMultiplier).div(10).multiply(10).div(100);

      await token.connect(addr1).withdrawOwnBonus(BigNumber(15).multiply(weiMultiplier).divide(10).toString());

      const final = await provider.getBalance(addr1.address);
      // console.log("initial balance", initial)

      // console.log("final balance", final)
      expect(final - initial).to.equal(BigNumber(15).multiply(weiMultiplier).divide(10).subtract(tax).toString());

    })
  })

  describe("Eth transfer test", async () => {

    it("Should be able to transfer BNB to contract", async () => {
      console.log("************************************************")

      const initial = await provider.getBalance(token.address);
      console.log("initial Contract Balance", BigNumber(initial.toString()).div(weiMultiplier).toString());


      await owner.sendTransaction({ to: token.address, value: ethers.utils.parseEther("1") });


      const final = await provider.getBalance(token.address);
      console.log("final contract balance after transferring 1BNB", BigNumber(final.toString()).div(weiMultiplier).toString());

      console.log("**************************************")
    });

  })

  describe("Pause functionality Test", async () => {

    it("Only Owner should be able to Pause contract", async () => {
      await expect(token.connect(addr1).pauseContract()).to.be.reverted;
    });


    it("Should revert Token bonus withdrawl when contract is paused #Own Bonus", async () => {
      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("10")
      })
      await increaseDays(250);
      await token.pauseContract();
      await expect(token.connect(addr1).withdrawOwnBonus(BigNumber(1).multiply(weiMultiplier).toString())).to.be.revertedWith("Contract Paused");
    })

    it("Should revert Token bonus withdrawl when contract is paused #Referral Bonus", async () => {
      
      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("100")
      })

      await token.connect(addr2).registerUser(addr1.address);
      await token.connect(addr2).stakeBnb({
        value: ethers.utils.parseEther("100")
      })

      await increaseDays(250);
      await token.pauseContract();
      await expect(token.connect(addr1).withdrawReferralBonus(BigNumber(1).multiply(weiMultiplier).toString())).to.be.revertedWith("Contract Paused");
    })

    it("Should revert Token bonus withdrawl when contract is paused #Referral Commission", async () => {
      await token.connect(addr1).stakeBnb({
        value: ethers.utils.parseEther("10")
      })
      await increaseDays(250);
      await token.pauseContract();
      await expect(token.connect(addr1).withdrawReferralCommission(BigNumber(1).multiply(weiMultiplier).toString())).to.be.revertedWith("Contract Paused");
    })

  })

  describe("User Registration/Referral Registration Test", async () => {

    it("Should revert repeated registration", async () => {
      await expect(token.connect(addr1).registerUser(owner.address)).to.be.revertedWith("User already registered");
    })
    it("Should not allow to reffer self", async () => {
      await expect(token.connect(addr1).registerUser(addr1.address)).to.be.revertedWith("User already registered");
    });
  })

});
