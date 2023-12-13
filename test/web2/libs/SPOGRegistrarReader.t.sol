// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../../lib/forge-std/src/Test.sol";
import { SPOGRegistrarHarness } from "../util/SPOGRegistrarHarness.sol";
import { SPOGRegistrarReader } from "../../../src/libs/SPOGRegistrarReader.sol";
import { ISPOGRegistrar } from "../../../src/interfaces/ISPOGRegistrar.sol";


contract SPOGRegistrarReaderTest is Test {

    function test_getBaseEarnerRate() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.BASE_EARNER_RATE, 123);

        assertEq(123, SPOGRegistrarReader.getBaseEarnerRate(address(registrar)));
    }

    function test_getBaseMinterRate() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.BASE_MINTER_RATE, 123);

        assertEq(123, SPOGRegistrarReader.getBaseMinterRate(address(registrar)));
    }

    function test_getEarnerRateModel() public {

        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address rateModel = makeAddr("rateModel");
        registrar.__setValue(SPOGRegistrarReader.EARNER_RATE_MODEL, rateModel);

        assertEq(rateModel, SPOGRegistrarReader.getEarnerRateModel(address(registrar)));
    }

    function test_getMintDelay() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.MINT_DELAY, 123);

        assertEq(123, SPOGRegistrarReader.getMintDelay(address(registrar)));
    }

    function test_getMinterFreezeTime() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.MINTER_FREEZE_TIME, 123);

        assertEq(123, SPOGRegistrarReader.getMinterFreezeTime(address(registrar)));
    }

    function test_getMinterRate() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.MINTER_RATE, 123);

        assertEq(123, SPOGRegistrarReader.getMinterRate(address(registrar)));
    }

    function test_getMinterRateModel() public {

        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address rateModel = makeAddr("rateModel");
        registrar.__setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, rateModel);

        assertEq(rateModel, SPOGRegistrarReader.getMinterRateModel(address(registrar)));
    }

    function test_getMintTTL() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.MINT_TTL, 123);

        assertEq(123, SPOGRegistrarReader.getMintTTL(address(registrar)));
    }

    function test_getUpdateCollateralInterval() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 123);

        assertEq(123, SPOGRegistrarReader.getUpdateCollateralInterval(address(registrar)));
    }

    // TODO #1
    function test_getUpdateCollateralValidatorThreshold() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD, 123);

        assertEq(123, SPOGRegistrarReader.getUpdateCollateralValidatorThreshold(address(registrar)));
    }

    function test_isApprovedEarner_negative() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address account = makeAddr("account");

        assertFalse(SPOGRegistrarReader.isApprovedEarner(address(registrar), account));
    }

    function test_isApprovedEarner_positive() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address account = makeAddr("account");
        registrar.__setListValue(SPOGRegistrarReader.EARNERS_LIST, account);

        assertTrue(SPOGRegistrarReader.isApprovedEarner(address(registrar), account));
    }

    function test_isEarnersListIgnored_negative() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();

        assertFalse(SPOGRegistrarReader.isEarnersListIgnored(address(registrar)));
    }

    function test_isEarnersListIgnored_positive() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address earnersListIgnored = makeAddr("earnersListIgnored");
        registrar.__setValue(SPOGRegistrarReader.EARNERS_LIST_IGNORED, earnersListIgnored);

        assertTrue(SPOGRegistrarReader.isEarnersListIgnored(address(registrar)));
    }

    function test_isApprovedMinter_negative() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address account = makeAddr("account");

        assertFalse(SPOGRegistrarReader.isApprovedMinter(address(registrar), account));
    }

    function test_isApprovedMinter_positive() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address account = makeAddr("account");
        registrar.__setListValue(SPOGRegistrarReader.MINTERS_LIST, account);

        assertTrue(SPOGRegistrarReader.isApprovedMinter(address(registrar), account));
    }

    function test_isApprovedValidator_negative() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address account = makeAddr("account");

        assertFalse(SPOGRegistrarReader.isApprovedValidator(address(registrar), account));
    }

    function test_isApprovedValidator_positive() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address account = makeAddr("account");
        registrar.__setListValue(SPOGRegistrarReader.VALIDATORS_LIST, account);

        assertTrue(SPOGRegistrarReader.isApprovedValidator(address(registrar), account));
    }

    function test_getPenaltyRate() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        registrar.__setValue(SPOGRegistrarReader.PENALTY_RATE, 123);

        assertEq(123, SPOGRegistrarReader.getPenaltyRate(address(registrar)));
    }

    function test_getVault() public {
        SPOGRegistrarHarness registrar = new SPOGRegistrarHarness();
        address vault = makeAddr("vault");
        registrar.setVault(vault);

        assertEq(vault, SPOGRegistrarReader.getVault(address(registrar)));
    }

    // function test_toAddress() public {
    // }

    // function test_toBytes32() public {
    // }

}