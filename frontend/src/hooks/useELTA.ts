import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { useChainId, useAccount } from 'wagmi';
import { ERC20ABI } from '../abi/ERC20';
import { getContractAddress } from '../lib/wagmi';

export function useELTA() {
  const chainId = useChainId();
  const { address } = useAccount();
  
  const eltaAddress = getContractAddress(chainId, 'ELTA');

  // Read functions
  const useBalance = (account?: `0x${string}`) => useReadContract({
    address: eltaAddress as `0x${string}`,
    abi: ERC20ABI,
    functionName: 'balanceOf',
    args: account ? [account] : address ? [address] : undefined,
    query: {
      enabled: !!(account || address),
    },
  });

  const useAllowance = (spender: `0x${string}`) => useReadContract({
    address: eltaAddress as `0x${string}`,
    abi: ERC20ABI,
    functionName: 'allowance',
    args: address && spender ? [address, spender] : undefined,
    query: {
      enabled: !!(address && spender),
    },
  });

  const useTokenInfo = () => {
    const name = useReadContract({
      address: eltaAddress as `0x${string}`,
      abi: ERC20ABI,
      functionName: 'name',
    });

    const symbol = useReadContract({
      address: eltaAddress as `0x${string}`,
      abi: ERC20ABI,
      functionName: 'symbol',
    });

    const decimals = useReadContract({
      address: eltaAddress as `0x${string}`,
      abi: ERC20ABI,
      functionName: 'decimals',
    });

    const totalSupply = useReadContract({
      address: eltaAddress as `0x${string}`,
      abi: ERC20ABI,
      functionName: 'totalSupply',
    });

    return {
      name: name.data,
      symbol: symbol.data,
      decimals: decimals.data,
      totalSupply: totalSupply.data,
      isLoading: name.isLoading || symbol.isLoading || decimals.isLoading || totalSupply.isLoading,
      error: name.error || symbol.error || decimals.error || totalSupply.error,
    };
  };

  // Write functions
  const { writeContract: approve, data: approveHash, error: approveError, isPending: isApproving } = useWriteContract();
  
  const approveTx = useWaitForTransactionReceipt({
    hash: approveHash,
  });

  const handleApprove = (spender: `0x${string}`, amount: bigint) => {
    approve({
      address: eltaAddress as `0x${string}`,
      abi: ERC20ABI,
      functionName: 'approve',
      args: [spender, amount],
    });
  };

  const { writeContract: transfer, data: transferHash, error: transferError, isPending: isTransferring } = useWriteContract();
  
  const transferTx = useWaitForTransactionReceipt({
    hash: transferHash,
  });

  const handleTransfer = (to: `0x${string}`, amount: bigint) => {
    transfer({
      address: eltaAddress as `0x${string}`,
      abi: ERC20ABI,
      functionName: 'transfer',
      args: [to, amount],
    });
  };

  return {
    // Contract address
    eltaAddress,
    
    // Read hooks
    useBalance,
    useAllowance,
    useTokenInfo,
    
    // Write functions
    approve: handleApprove,
    approveHash,
    approveError,
    isApproving,
    approveTx,
    
    transfer: handleTransfer,
    transferHash,
    transferError,
    isTransferring,
    transferTx,
  };
}
