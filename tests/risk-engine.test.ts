
import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;

describe("RiskShield Protocol - Risk Engine Tests", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("should create a new position successfully", () => {
    const { result } = simnet.callPublicFn(
      "risk-engine",
      "create-position",
      [
        simnet.types.uint(1), // position-id
        simnet.types.ascii("STX"), // asset
        simnet.types.uint(1000000), // amount (1 STX in microSTX)
        simnet.types.uint(1500000), // collateral (1.5 STX in microSTX)
      ],
      address1
    );
    expect(result).toBeOk(simnet.types.uint(1));
  });

  it("should get position details after creation", () => {
    // First create a position
    simnet.callPublicFn(
      "risk-engine",
      "create-position",
      [
        simnet.types.uint(2),
        simnet.types.ascii("sBTC"),
        simnet.types.uint(100000000), // 1 BTC in satoshi
        simnet.types.uint(200000000), // 2 BTC collateral
      ],
      address1
    );

    // Then get the position
    const { result } = simnet.callReadOnlyFn(
      "risk-engine",
      "get-position",
      [simnet.types.uint(2)],
      address1
    );
    
    expect(result).toBeSome();
    const position = result.expectSome();
    expect(position.owner).toBePrincipal(address1);
    expect(position.asset).toBeAscii("sBTC");
    expect(position.amount).toBeUint(100000000);
    expect(position.collateral).toBeUint(200000000);
  });

  it("should calculate position risk correctly", () => {
    // Create a position first
    simnet.callPublicFn(
      "risk-engine",
      "create-position",
      [
        simnet.types.uint(3),
        simnet.types.ascii("STX"),
        simnet.types.uint(1000000),
        simnet.types.uint(1200000), // Lower collateral ratio
      ],
      address1
    );

    // Calculate risk
    const { result } = simnet.callReadOnlyFn(
      "risk-engine",
      "calculate-position-risk",
      [simnet.types.uint(3)],
      address1
    );
    
    expect(result).toBeOk();
    const riskScore = result.expectOk();
    expect(riskScore).toBeUint();
    // Risk score should be greater than 0 for undercollateralized position
    expect(Number(riskScore)).toBeGreaterThan(0);
  });

  it("should get asset risk parameters", () => {
    const { result } = simnet.callReadOnlyFn(
      "risk-engine",
      "get-asset-risk-params",
      [simnet.types.ascii("STX")],
      address1
    );
    
    expect(result).toBeSome();
    const params = result.expectSome();
    expect(params["base-risk"]).toBeUint(2000); // 20%
    expect(params.volatility).toBeUint(3500); // 35%
    expect(params["liquidity-score"]).toBeUint(8000); // 80%
  });

  it("should update collateral ratio", () => {
    // Create position first
    simnet.callPublicFn(
      "risk-engine",
      "create-position",
      [
        simnet.types.uint(4),
        simnet.types.ascii("STX"),
        simnet.types.uint(1000000),
        simnet.types.uint(1500000),
      ],
      address1
    );

    // Update collateral ratio
    const { result } = simnet.callPublicFn(
      "risk-engine",
      "update-collateral-ratio",
      [
        simnet.types.uint(4),
        simnet.types.uint(2000000), // Increase collateral
      ],
      address1
    );
    
    expect(result).toBeOk();
    const newRatio = result.expectOk();
    expect(newRatio).toBeUint(20000000); // 200% ratio (2000000 * 10000 / 1000000)
  });

  it("should reject unauthorized collateral updates", () => {
    // Create position with address1
    simnet.callPublicFn(
      "risk-engine",
      "create-position",
      [
        simnet.types.uint(5),
        simnet.types.ascii("STX"),
        simnet.types.uint(1000000),
        simnet.types.uint(1500000),
      ],
      address1
    );

    // Try to update with address2 (unauthorized)
    const { result } = simnet.callPublicFn(
      "risk-engine",
      "update-collateral-ratio",
      [
        simnet.types.uint(5),
        simnet.types.uint(2000000),
      ],
      address2
    );
    
    expect(result).toBeErr(simnet.types.uint(100)); // ERR-UNAUTHORIZED
  });

  it("should get system risk metrics", () => {
    const { result } = simnet.callReadOnlyFn(
      "risk-engine",
      "get-system-risk-metrics",
      [],
      address1
    );
    
    expect(result).toBeTuple();
    const metrics = result.expectTuple();
    expect(metrics["total-positions"]).toBeUint();
    // Should have positions from previous tests
    expect(Number(metrics["total-positions"])).toBeGreaterThan(0);
  });

  it("should reject invalid amounts", () => {
    const { result } = simnet.callPublicFn(
      "risk-engine",
      "create-position",
      [
        simnet.types.uint(99),
        simnet.types.ascii("STX"),
        simnet.types.uint(0), // Invalid amount
        simnet.types.uint(1500000),
      ],
      address1
    );
    
    expect(result).toBeErr(simnet.types.uint(102)); // ERR-INVALID-AMOUNT
  });

  it("should reject duplicate position IDs", () => {
    // Create first position
    simnet.callPublicFn(
      "risk-engine",
      "create-position",
      [
        simnet.types.uint(100),
        simnet.types.ascii("STX"),
        simnet.types.uint(1000000),
        simnet.types.uint(1500000),
      ],
      address1
    );

    // Try to create position with same ID
    const { result } = simnet.callPublicFn(
      "risk-engine",
      "create-position",
      [
        simnet.types.uint(100),
        simnet.types.ascii("sBTC"),
        simnet.types.uint(2000000),
        simnet.types.uint(3000000),
      ],
      address1
    );
    
    expect(result).toBeErr(simnet.types.uint(101)); // ERR-POSITION-NOT-FOUND (used for duplicate check)
  });
});
