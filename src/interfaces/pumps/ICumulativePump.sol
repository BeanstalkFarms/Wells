// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

/**
 * @title Cumulative Pumps provide an Oracle for time weighted average reserves through the use of a cumulative reserve.
 */
interface ICumulativePump {
    /**
     * @notice Reads the current cumulative reserves from the Pump
     * @param well The address of the Well
     * @return cumulativeReserves The cumulative reserves from the Pump
     */
    function readCumulativeReserves(address well) external view returns (bytes memory cumulativeReserves);

    /**
     * @notice Reads the current cumulative reserves from the Pump
     * @param well The address of the Well
     * @param startCumulativeReserves The cumulative reserves to start the TWA from
     * @param startTimestamp The timestamp to start the TWA from
     * @return twaReserves The time weighted average reserves from start timestamp to now
     * @return cumulativeReserves The current cumulative reserves from the Pump at the current timestamp
     */
    function readTwaReserves(
        address well,
        bytes calldata startCumulativeReserves,
        uint startTimestamp
    ) external view returns (uint[] memory twaReserves, bytes memory cumulativeReserves);
}
