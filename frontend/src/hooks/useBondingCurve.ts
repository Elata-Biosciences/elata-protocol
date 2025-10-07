import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { AppBondingCurveABI } from '../abi/AppBondingCurve';
import type { CurveState } from '../types';

export function useBondingCurve(curveAddress: `0x${string}` | undefined) {
  // Read functions
  const useCurveState = () => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'getCurveState',
    query: {
      enabled: !!curveAddress,
    },
  });

  const useTokensOut = (eltaIn: bigint) => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'getTokensOut',
    args: [eltaIn],
    query: {
      enabled: !!curveAddress && eltaIn > 0n,
    },
  });

  const useEltaInForTokens = (tokensDesired: bigint) => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'getEltaInForTokens',
    args: [tokensDesired],
    query: {
      enabled: !!curveAddress && tokensDesired > 0n,
    },
  });

  const useCurrentPrice = () => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'getCurrentPrice',
    query: {
      enabled: !!curveAddress,
    },
  });

  const useReserveElta = () => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'reserveElta',
    query: {
      enabled: !!curveAddress,
    },
  });

  const useReserveToken = () => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'reserveToken',
    query: {
      enabled: !!curveAddress,
    },
  });

  const useTargetRaised = () => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'targetRaisedElta',
    query: {
      enabled: !!curveAddress,
    },
  });

  const useGraduated = () => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'graduated',
    query: {
      enabled: !!curveAddress,
    },
  });

  const usePair = () => useReadContract({
    address: curveAddress,
    abi: AppBondingCurveABI,
    functionName: 'pair',
    query: {
      enabled: !!curveAddress,
    },
  });

  // Write functions
  const { writeContract: buyTokens, data: buyHash, error: buyError, isPending: isBuying } = useWriteContract();
  
  const buyTx = useWaitForTransactionReceipt({
    hash: buyHash,
  });

  const handleBuy = (eltaIn: bigint, minTokensOut: bigint) => {
    if (!curveAddress) return;
    
    buyTokens({
      address: curveAddress,
      abi: AppBondingCurveABI,
      functionName: 'buy',
      args: [eltaIn, minTokensOut],
    });
  };

  const { writeContract: graduate, data: graduateHash, error: graduateError, isPending: isGraduating } = useWriteContract();
  
  const graduateTx = useWaitForTransactionReceipt({
    hash: graduateHash,
  });

  const handleGraduate = () => {
    if (!curveAddress) return;
    
    graduate({
      address: curveAddress,
      abi: AppBondingCurveABI,
      functionName: 'graduate',
    });
  };

  return {
    // Read hooks
    useCurveState,
    useTokensOut,
    useEltaInForTokens,
    useCurrentPrice,
    useReserveElta,
    useReserveToken,
    useTargetRaised,
    useGraduated,
    usePair,
    
    // Write functions
    buy: handleBuy,
    buyHash,
    buyError,
    isBuying,
    buyTx,
    
    graduate: handleGraduate,
    graduateHash,
    graduateError,
    isGraduating,
    graduateTx,
  };
}
