'use client';

import { useState, useEffect } from 'react';
import { useAccount } from 'wagmi';
import { parseEther, formatEther } from 'viem';
import { useAppFactory } from '../hooks/useAppFactory';
import { useELTA } from '../hooks/useELTA';
import type { CreateAppForm as CreateAppFormType } from '../types';
import { IoApps, IoCheckmarkCircle, IoWallet, IoCash } from 'react-icons/io5';

export function CreateAppForm() {
  const { address } = useAccount();
  const { 
    createApp, 
    isCreatingApp, 
    createAppError, 
    createAppTx,
    useSeedElta,
    useCreationFee,
    useDefaultSupply,
    appFactoryAddress 
  } = useAppFactory();
  
  const { 
    useBalance, 
    useAllowance, 
    approve, 
    isApproving, 
    approveTx 
  } = useELTA();

  // Contract parameters
  const { data: seedElta } = useSeedElta();
  const { data: creationFee } = useCreationFee();
  const { data: defaultSupply } = useDefaultSupply();
  
  // User balances and allowances
  const { data: eltaBalance } = useBalance();
  const { data: allowance } = useAllowance(appFactoryAddress as `0x${string}`);

  const [formData, setFormData] = useState<CreateAppFormType>({
    name: '',
    symbol: '',
    supply: '',
    description: '',
    imageURI: '',
    website: '',
  });

  const [step, setStep] = useState<'form' | 'approve' | 'create' | 'success'>('form');
  const [errors, setErrors] = useState<Partial<CreateAppFormType>>({});

  // Calculate total cost
  const totalCost = seedElta && creationFee ? seedElta + creationFee : 0n;
  const needsApproval = allowance !== undefined && totalCost > 0n && allowance < totalCost;
  const hasInsufficientBalance = eltaBalance !== undefined && totalCost > 0n && eltaBalance < totalCost;

  // Step status tracking
  const stepStatus = {
    1: formData.name && formData.symbol && formData.description,
    2: !hasInsufficientBalance && eltaBalance !== undefined,
    3: !needsApproval || approveTx.isSuccess,
  };

  // Handle form submission
  const validateForm = (): boolean => {
    const newErrors: Partial<CreateAppFormType> = {};

    if (!formData.name.trim()) newErrors.name = 'App name is required';
    if (!formData.symbol.trim()) newErrors.symbol = 'Symbol is required';
    if (formData.symbol.length > 10) newErrors.symbol = 'Symbol must be 10 characters or less';
    if (!formData.description.trim()) newErrors.description = 'Description is required';
    
    // Validate supply if provided
    if (formData.supply) {
      try {
        const supply = parseEther(formData.supply);
        if (supply <= 0n) newErrors.supply = 'Supply must be greater than 0';
      } catch {
        newErrors.supply = 'Invalid supply amount';
      }
    }

    // Validate URL if provided
    if (formData.website && !isValidUrl(formData.website)) {
      newErrors.website = 'Please enter a valid URL';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const isValidUrl = (string: string): boolean => {
    try {
      new URL(string);
      return true;
    } catch {
      return false;
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) return;
    
    if (hasInsufficientBalance) {
      alert(`Insufficient ELTA balance. You need ${formatEther(totalCost)} ELTA but only have ${formatEther(eltaBalance || 0n)} ELTA.`);
      return;
    }

    if (needsApproval) {
      setStep('approve');
      approve(appFactoryAddress as `0x${string}`, totalCost);
    } else {
      setStep('create');
      handleCreateApp();
    }
  };

  const handleCreateApp = () => {
    const supply = formData.supply ? parseEther(formData.supply) : 0n;
    
    createApp(
      formData.name,
      formData.symbol,
      supply,
      formData.description,
      formData.imageURI,
      formData.website
    );
  };

  // Handle transaction success
  useEffect(() => {
    if (approveTx.isSuccess && step === 'approve') {
      setStep('create');
      handleCreateApp();
    }
  }, [approveTx.isSuccess, step]);

  useEffect(() => {
    if (createAppTx.isSuccess && step === 'create') {
      setStep('success');
    }
  }, [createAppTx.isSuccess, step]);

  const handleInputChange = (field: keyof CreateAppFormType, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (errors[field]) {
      setErrors(prev => ({ ...prev, [field]: undefined }));
    }
  };

  // Success state
  if (step === 'success') {
    return (
      <div className="bg-white rounded-xl sm:rounded-2xl shadow-xl p-6 sm:p-10 text-center">
        <div className="w-16 h-16 bg-success/10 rounded-full flex items-center justify-center mx-auto mb-4">
          <IoCheckmarkCircle className="w-8 h-8 text-success" />
        </div>
        <h3 className="font-montserrat font-bold text-xl text-offBlack mb-2">
          App Successfully Created!
        </h3>
        <p className="text-gray3 mb-6 font-sf-pro">
          Your app "{formData.name}" has been deployed and is now live on the bonding curve.
        </p>
        <div className="flex flex-col sm:flex-row gap-4 justify-center">
          <button
            onClick={() => window.location.href = '/'}
            className="inline-flex items-center justify-center px-8 py-4 font-sf-pro font-medium rounded-xl sm:rounded-none shadow-lg hover:shadow-xl transform hover:scale-105 hover:-translate-y-1 transition-all duration-300"
            style={{ backgroundColor: '#171717', color: '#FDFDFD' }}
          >
            View Protocol
          </button>
          <button
            onClick={() => window.location.href = '/my-apps'}
            className="inline-flex items-center justify-center px-8 py-4 bg-white text-offBlack font-sf-pro font-medium rounded-full shadow-lg hover:shadow-xl hover:bg-gray1/20 transform hover:scale-105 hover:-translate-y-1 transition-all duration-300"
          >
            Manage My Apps
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-xl sm:rounded-2xl shadow-xl overflow-hidden">
      
      {/* Step 1: Basic Information */}
      <div className="p-4 sm:p-8 border-b border-gray2/30">
        <div className="flex items-start space-x-3 sm:space-x-4 mb-4 sm:mb-6">
          <div className={`flex items-center justify-center w-10 h-10 sm:w-12 sm:h-12 rounded-xl transition-all duration-300 flex-shrink-0 ${
            stepStatus[1] ? 'bg-elataGreen text-white' : 'bg-elataGreen/10 text-elataGreen'
          }`}>
            <IoApps className="w-5 h-5 sm:w-6 sm:h-6" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="text-lg sm:text-xl font-semibold font-montserrat text-offBlack">
              App Information
            </h3>
            <p className="text-gray3 font-sf-pro text-sm sm:text-base">
              Provide basic details about your EEG/BCI application
            </p>
          </div>
        </div>
        
        <div className="bg-gray1/20 rounded-xl p-4 sm:p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-offBlack mb-2 font-sf-pro">
              App Name *
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => handleInputChange('name', e.target.value)}
              className={`w-full px-4 py-3 border-2 rounded-xl bg-white transition-all duration-200 font-sf-pro ${
                errors.name 
                  ? 'border-accentRed focus:border-accentRed focus:ring-2 focus:ring-accentRed/20' 
                  : 'border-gray2 focus:border-elataGreen focus:ring-2 focus:ring-elataGreen/20'
              }`}
              placeholder="e.g., NeuroFocus"
              maxLength={50}
            />
            {errors.name && (
              <p className="text-accentRed text-sm mt-1 font-sf-pro">{errors.name}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-offBlack mb-2 font-sf-pro">
              Token Symbol *
            </label>
            <input
              type="text"
              value={formData.symbol}
              onChange={(e) => handleInputChange('symbol', e.target.value.toUpperCase())}
              className={`w-full px-4 py-3 border-2 rounded-xl bg-white transition-all duration-200 font-sf-pro ${
                errors.symbol 
                  ? 'border-accentRed focus:border-accentRed focus:ring-2 focus:ring-accentRed/20' 
                  : 'border-gray2 focus:border-elataGreen focus:ring-2 focus:ring-elataGreen/20'
              }`}
              placeholder="e.g., NFT"
              maxLength={10}
            />
            {errors.symbol && (
              <p className="text-accentRed text-sm mt-1 font-sf-pro">{errors.symbol}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-offBlack mb-2 font-sf-pro">
              Description *
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => handleInputChange('description', e.target.value)}
              className={`w-full px-4 py-3 border-2 rounded-xl bg-white transition-all duration-200 font-sf-pro min-h-24 resize-y ${
                errors.description 
                  ? 'border-accentRed focus:border-accentRed focus:ring-2 focus:ring-accentRed/20' 
                  : 'border-gray2 focus:border-elataGreen focus:ring-2 focus:ring-elataGreen/20'
              }`}
              placeholder="Describe your EEG/BCI application and its scientific purpose..."
              maxLength={500}
            />
            {errors.description && (
              <p className="text-accentRed text-sm mt-1 font-sf-pro">{errors.description}</p>
            )}
            <p className="text-xs text-gray3 mt-1 font-sf-pro">
              {formData.description.length}/500 characters
            </p>
          </div>

          {stepStatus[1] && (
            <div className="flex items-center text-elataGreen">
              <IoCheckmarkCircle className="w-4 h-4 mr-2 flex-shrink-0" />
              <span className="text-sm font-medium">Basic information completed</span>
            </div>
          )}
        </div>
      </div>

      {/* Step 2: Optional Details */}
      <div className="p-4 sm:p-8 border-b border-gray2/30">
        <div className="flex items-start space-x-3 sm:space-x-4 mb-4 sm:mb-6">
          <div className="flex items-center justify-center w-10 h-10 sm:w-12 sm:h-12 rounded-xl bg-elataGreen/10 text-elataGreen flex-shrink-0">
            <IoWallet className="w-5 h-5 sm:w-6 sm:h-6" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="text-lg sm:text-xl font-semibold font-montserrat text-offBlack">
              Optional Configuration
            </h3>
            <p className="text-gray3 font-sf-pro text-sm sm:text-base">
              Additional settings for your token and application
            </p>
          </div>
        </div>
        
        <div className="bg-gray1/20 rounded-xl p-4 sm:p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-offBlack mb-2 font-sf-pro">
              Token Supply (optional)
            </label>
            <input
              type="text"
              value={formData.supply}
              onChange={(e) => handleInputChange('supply', e.target.value)}
              className={`w-full px-4 py-3 border-2 rounded-xl bg-white transition-all duration-200 font-sf-pro ${
                errors.supply 
                  ? 'border-accentRed focus:border-accentRed focus:ring-2 focus:ring-accentRed/20' 
                  : 'border-gray2 focus:border-elataGreen focus:ring-2 focus:ring-elataGreen/20'
              }`}
              placeholder={defaultSupply ? formatEther(defaultSupply) : '1000000000'}
            />
            {errors.supply && (
              <p className="text-accentRed text-sm mt-1 font-sf-pro">{errors.supply}</p>
            )}
            <p className="text-xs text-gray3 mt-1 font-sf-pro">
              Leave empty to use default (1B tokens)
            </p>
          </div>

          <div>
            <label className="block text-sm font-medium text-offBlack mb-2 font-sf-pro">
              Website (optional)
            </label>
            <input
              type="url"
              value={formData.website}
              onChange={(e) => handleInputChange('website', e.target.value)}
              className={`w-full px-4 py-3 border-2 rounded-xl bg-white transition-all duration-200 font-sf-pro ${
                errors.website 
                  ? 'border-accentRed focus:border-accentRed focus:ring-2 focus:ring-accentRed/20' 
                  : 'border-gray2 focus:border-elataGreen focus:ring-2 focus:ring-elataGreen/20'
              }`}
              placeholder="https://your-app.com"
            />
            {errors.website && (
              <p className="text-accentRed text-sm mt-1 font-sf-pro">{errors.website}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-offBlack mb-2 font-sf-pro">
              Image URL (optional)
            </label>
            <input
              type="url"
              value={formData.imageURI}
              onChange={(e) => handleInputChange('imageURI', e.target.value)}
              className="w-full px-4 py-3 border-2 border-gray2 rounded-xl bg-white focus:border-elataGreen focus:ring-2 focus:ring-elataGreen/20 transition-all duration-200 font-sf-pro"
              placeholder="https://your-image-url.com/logo.png"
            />
            <p className="text-xs text-gray3 mt-1 font-sf-pro">
              Logo or banner image for your app
            </p>
          </div>
        </div>
      </div>

      {/* Step 3: Cost & Launch */}
      <div className="p-4 sm:p-8">
        <div className="flex items-start space-x-3 sm:space-x-4 mb-4 sm:mb-6">
          <div className={`flex items-center justify-center w-10 h-10 sm:w-12 sm:h-12 rounded-xl transition-all duration-300 flex-shrink-0 ${
            stepStatus[2] ? 'bg-elataGreen text-white' : 'bg-elataGreen/10 text-elataGreen'
          }`}>
            <IoCash className="w-5 h-5 sm:w-6 sm:h-6" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="text-lg sm:text-xl font-semibold font-montserrat text-offBlack">
              Launch Configuration
            </h3>
            <p className="text-gray3 font-sf-pro text-sm sm:text-base">
              Review costs and launch your application
            </p>
          </div>
        </div>
        
        <div className="bg-gray1/20 rounded-xl p-4 sm:p-6 mb-6">
          <h4 className="font-medium text-offBlack mb-3 font-montserrat">Cost Breakdown</h4>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-gray3 font-sf-pro">Creation Fee:</span>
              <span className="text-offBlack font-sf-pro">
                {creationFee ? formatEther(creationFee) : '10'} ELTA
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray3 font-sf-pro">Seed Liquidity:</span>
              <span className="text-offBlack font-sf-pro">
                {seedElta ? formatEther(seedElta) : '100'} ELTA
              </span>
            </div>
            <hr className="border-gray2/30" />
            <div className="flex justify-between font-medium">
              <span className="text-offBlack font-sf-pro">Total Cost:</span>
              <span className="text-offBlack font-sf-pro">
                {totalCost ? formatEther(totalCost) : '110'} ELTA
              </span>
            </div>
          </div>
          
          <div className="mt-3 pt-3">
            <div className="flex justify-between text-sm">
              <span className="text-gray3 font-sf-pro">Your ELTA Balance:</span>
              <span className={`font-sf-pro ${hasInsufficientBalance ? 'text-accentRed' : 'text-offBlack'}`}>
                {eltaBalance ? formatEther(eltaBalance) : '0'} ELTA
              </span>
            </div>
            {hasInsufficientBalance && (
              <p className="text-accentRed text-xs mt-1 font-sf-pro">
                Insufficient balance to create app
              </p>
            )}
          </div>
        </div>

        {/* Submit Button */}
        <button
          type="submit"
          onClick={handleSubmit}
          disabled={isCreatingApp || isApproving || hasInsufficientBalance || step !== 'form'}
          className="w-full inline-flex items-center justify-center px-10 sm:px-16 py-4 sm:py-5 rounded-xl sm:rounded-none shadow-lg font-sf-pro font-medium text-base sm:text-lg transition-all duration-300 hover:shadow-xl transform hover:scale-105 hover:-translate-y-1 disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
          style={{ backgroundColor: '#171717', color: '#FDFDFD' }}
        >
          {step === 'approve' && isApproving && (
            <span className="flex items-center justify-center">
              <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Approving ELTA...
            </span>
          )}
          {step === 'create' && isCreatingApp && (
            <span className="flex items-center justify-center">
              <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Creating App...
            </span>
          )}
          {step === 'form' && needsApproval && 'Approve & Create App'}
          {step === 'form' && !needsApproval && 'Create App'}
        </button>

        {/* Error Display */}
        {(createAppError || approveTx.error) && (
          <div className="mt-4 bg-accentRed/10 border border-accentRed/20 rounded-lg p-4">
            <p className="text-accentRed text-sm font-sf-pro">
              {createAppError?.message || approveTx.error?.message || 'Transaction failed'}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}