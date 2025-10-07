import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { useChainId } from 'wagmi';
import { AppFactoryABI } from '../abi/AppFactory';
import { getContractAddress } from '../lib/wagmi';
import type { App, LaunchStats } from '../types';

export function useAppFactory() {
  const chainId = useChainId();
  
  const appFactoryAddress = getContractAddress(chainId, 'AppFactory');

  // Read functions
  const useAppCount = () => useReadContract({
    address: appFactoryAddress as `0x${string}`,
    abi: AppFactoryABI,
    functionName: 'appCount',
  });

  const useApp = (appId: number) => useReadContract({
    address: appFactoryAddress as `0x${string}`,
    abi: AppFactoryABI,
    functionName: 'getApp',
    args: [BigInt(appId)],
    query: {
      enabled: appId >= 0,
    },
  });

  const useCreatorApps = (creator: `0x${string}` | undefined) => useReadContract({
    address: appFactoryAddress as `0x${string}`,
    abi: AppFactoryABI,
    functionName: 'getCreatorApps',
    args: creator ? [creator] : undefined,
    query: {
      enabled: !!creator,
    },
  });

  const useLaunchStats = () => useReadContract({
    address: appFactoryAddress as `0x${string}`,
    abi: AppFactoryABI,
    functionName: 'getLaunchStats',
  });

  const useSeedElta = () => useReadContract({
    address: appFactoryAddress as `0x${string}`,
    abi: AppFactoryABI,
    functionName: 'seedElta',
  });

  const useTargetRaisedElta = () => useReadContract({
    address: appFactoryAddress as `0x${string}`,
    abi: AppFactoryABI,
    functionName: 'targetRaisedElta',
  });

  const useCreationFee = () => useReadContract({
    address: appFactoryAddress as `0x${string}`,
    abi: AppFactoryABI,
    functionName: 'creationFee',
  });

  const useDefaultSupply = () => useReadContract({
    address: appFactoryAddress as `0x${string}`,
    abi: AppFactoryABI,
    functionName: 'defaultSupply',
  });

  // Write functions
  const { writeContract: createApp, data: createAppHash, error: createAppError, isPending: isCreatingApp } = useWriteContract();
  
  const createAppTx = useWaitForTransactionReceipt({
    hash: createAppHash,
  });

  const handleCreateApp = (
    name: string,
    symbol: string,
    supply: bigint,
    description: string,
    imageURI: string,
    website: string
  ) => {
    createApp({
      address: appFactoryAddress as `0x${string}`,
      abi: AppFactoryABI,
      functionName: 'createApp',
      args: [name, symbol, supply, description, imageURI, website],
    });
  };

  return {
    // Contract address
    appFactoryAddress,
    
    // Read hooks
    useAppCount,
    useApp,
    useCreatorApps,
    useLaunchStats,
    useSeedElta,
    useTargetRaisedElta,
    useCreationFee,
    useDefaultSupply,
    
    // Write functions
    createApp: handleCreateApp,
    createAppHash,
    createAppError,
    isCreatingApp,
    createAppTx,
  };
}
