CREATE OR REPLACE package body OPCL.opsOnlineSaveData as

procedure SaveTransaction_v1(
  traSkipTransaction boolean, 
  traTransactionID number, traTerminalDateTime date, traRSDateTime date, traTransactionType number, traTerminalID number, traCardNumber number, traStatus number, 
  traCardStatus number, traSource number, traDiscount number, traDiscountInitial number, traSerialNumber varchar2, traParamSetPeriodID number, traContractID number, 
  traFiscalFlags number, traFiscalFlagsInitial number, traCentralDateTime date, traPCDateTime date, traSenderPCID number, traHandlerPCID number, traSignature raw, 
  traCardType number, traTransitType number, traHandlerPCOwnerID number, traIDUniquePart number, traFlags number, traFlagsInitial number, traCrossCardToTerminal number, 
  traCrossTerminalToCard number, traCardScriptID number, traBehaviorFlags number, traCardLastServiceDate date, traSelectedBehaviourID number, traCardReadingMethod number, 
  traShiftAuthID number, traApplicationSign number,
  
  trcpPosition tNumbers, trcpGoodsCode tStrings17, trcpGoodsName tStrings127, trcpRetailSystemID number, trcpNetworkOwnerID number, trcpPaymentType tNumbers, 
  trcpPriceWithoutDiscount tNumbers, trcpPriceWODiscountInitial tNumbers, trcpPrice tNumbers, trcpQuantity tNumbers, trcpQuantityInitial tNumbers, 
  trcpAmountWithoutDiscount tNumbers, trcpAmount tNumbers, trcpBonuses tNumbers, trcpDiscountForPrice tNumbers, trcpDiscountForPriceInitial tNumbers, 
  trcpAmountWODiscountRounded tNumbers, trcpAmountRounded tNumbers, trcpBonusesRounded tNumbers, trcpDiscountForAmount tNumbers, trcpDiscountForAmountInitial tNumbers,
  trcpMeasureUnit tStrings50, trcpQuantityPrecision tNumbers, trcpFlags tNumbers, trcpFlagsInitial tNumbers,
   
  payByCash number, payByBankingCard number, payByBonuses number, payByCredit number, payByPrepaidAccount number, payPaymentTypeForDiscount number, 
  payByCashInitial number, payByBankingCardInitial number, payByBonusesInitial number, payByCreditInitial number, payByPrepaidAccountInitial number,
  
  crdcouCounterID tNumbers, crdcouCounterInitial tNumbers, crdcouCounterChange tNumbers, crdcouCounterValue tNumbers, crdcouCounterDate tDates, 
  crdcouPreviousValue tNumbers, crdcouPreviousDate tDates,
  
  crdcouspCounterID tNumbers, crdcouspSPID number, crdcouspCounterInitial tNumbers, crdcouspCounterChange tNumbers, crdcouspCounterValue tNumbers, 
  crdcouspCounterDate tDates, crdcouspPreviousValue tNumbers, crdcouspPreviousDate tDates,
  
  cntrcouCounterID tNumbers, cntrcouCounterInitial tNumbers, cntrcouCounterChange tNumbers, cntrcouCounterValue tNumbers, cntrcouCounterDate tDates, 
  cntrcouPreviousValue tNumbers, cntrcouPreviousDate tDates,
  
  caContractAccountID tNumbers, caAmountInitial tNumbers, caAmountChange tNumbers, caAmountValue tNumbers, caCrossTerminalToAccount tNumbers, 
  caCrossAccountToTerminal tNumbers,

  oaOwnerAccountID tNumbers, oaAmountInitial tNumbers, oaAmountChange tNumbers, oaAmountValue tNumbers, oaCrossTerminalToAccount tNumbers, 
  oaCrossAccountToTerminal tNumbers,

  mesSkipMessages boolean, mesTerminalPrinter varchar2, mesRetailScreen varchar2, mesRetailPrinter varchar2) is
begin
  -- сохраняем транзакцию
  if not traSkipTransaction then 
    insert into Transactions (ID, TerminalDateTime, RSDateTime, TransactionType, TerminalID, CardNumber, Status, CardStatus, Source, Discount, DiscountInitial, 
      SerialNumber, ParamSetPeriodID, ContractID, FiscalFlags, FiscalFlagsInitial, CentralDateTime, PCDateTime, SenderPCID, HandlerPCID, Signature, CardType, TransitType, 
      HandlerPCOwnerID, IDUniquePart, Flags, FlagsInitial, CrossCardToTerminal, CrossTerminalToCard, CardScriptID, BehaviorFlags, CardLastServiceDate, 
      SelectedBehaviourID, CardReadingMethod, ShiftAuthID, ApplicationSign) 
    values (traTransactionID, traTerminalDateTime, traRSDateTime, traTransactionType, traTerminalID, traCardNumber, traStatus, traCardStatus, traSource, traDiscount, 
      traDiscountInitial, traSerialNumber, traParamSetPeriodID, traContractID, traFiscalFlags, traFiscalFlagsInitial, traCentralDateTime, traPCDateTime, traSenderPCID, 
      traHandlerPCID, traSignature, traCardType, traTransitType, traHandlerPCOwnerID, traIDUniquePart, traFlags, traFlagsInitial, traCrossCardToTerminal, 
      traCrossTerminalToCard, traCardScriptID, traBehaviorFlags, traCardLastServiceDate, traSelectedBehaviourID, traCardReadingMethod, traShiftAuthID, traApplicationSign);
  end if;
    
  -- сохраняем чек
  if trcpGoodsCode is not null then 
    forall i in trcpGoodsCode.First..trcpGoodsCode.Last 
      insert into TransactionReceipts (TransactionID, TerminalDateTime, Position, GoodsID, PaymentType, PriceWithoutDiscount, PriceWithoutDiscountInitial, Price, 
        Quantity, QuantityInitial, AmountWithoutDiscount, Amount, Bonuses, DiscountForPrice, DiscountForPriceInitial, AmountWithoutDiscountRounded, 
        AmountRounded, BonusesRounded, DiscountForAmount, DiscountForAmountInitial, 
        MeasureUnitID, QuantityPrecision, Flags, FlagsInitial)
      values (traTransactionID, traTerminalDateTime, trcpPosition(i), opsOnline.GetArticleID2(trcpGoodsCode(i), trcpGoodsName(i), trcpRetailSystemID, trcpNetworkOwnerID), 
        trcpPaymentType(i), trcpPriceWithoutDiscount(i), trcpPriceWODiscountInitial(i), trcpPrice(i), trcpQuantity(i), trcpQuantityInitial(i), 
        trcpAmountWithoutDiscount(i), trcpAmount(i), trcpBonuses(i), trcpDiscountForPrice(i), trcpDiscountForPriceInitial(i), trcpAmountWODiscountRounded(i), 
        trcpAmountRounded(i), trcpBonusesRounded(i), trcpDiscountForAmount(i), trcpDiscountForAmountInitial(i), opsOnline.GetMeasureUnitID(trcpMeasureUnit(i)), 
        trcpQuantityPrecision(i), trcpFlags(i), trcpFlagsInitial(i));
  end if;
      
  -- сохраняем платежи      
  insert into TransactionPayments (TransactionID, TerminalDateTime, ByCash, ByBankingCard, ByBonuses, ByCredit, ByPrepaidAccount, PaymentTypeForDiscount, 
                                   ByCashInitial, ByBankingCardInitial, ByBonusesInitial, ByCreditInitial, ByPrepaidAccountInitial) 
  values (traTransactionID, traTerminalDateTime, payByCash, payByBankingCard, payByBonuses, payByCredit, payByPrepaidAccount, payPaymentTypeForDiscount, 
          payByCashInitial, payByBankingCardInitial, payByBonusesInitial, payByCreditInitial, payByPrepaidAccountInitial);                                  

  -- сохраняем общие счётчики карты
  if crdcouCounterID is not null and crdcouCounterID.Count > 0 then 
    forall i in crdcouCounterID.First..crdcouCounterID.Last 
      insert into TransactionCounters (TransactionID, TerminalDateTime, CounterID, CounterInitial, CounterChange, CounterValue, CounterDate, PreviousValue, PreviousDate) 
      values (traTransactionID, traTerminalDateTime, crdcouCounterID(i), crdcouCounterInitial(i), crdcouCounterChange(i), crdcouCounterValue(i), crdcouCounterDate(i), 
              crdcouPreviousValue(i), crdcouPreviousDate(i));
  end if;
  
  -- сохраняем счётчики карты в разрезе ТО
  if crdcouspCounterID is not null and crdcouspCounterID.Count > 0 then 
    forall i in crdcouspCounterID.First..crdcouspCounterID.Last 
      insert into TransactionCountersSP (TransactionID, TerminalDateTime, CounterID, SPID, CounterInitial, CounterChange, CounterValue, CounterDate, PreviousValue, 
                                         PreviousDate) 
      values (traTransactionID, traTerminalDateTime, crdcouspCounterID(i), crdcouspSPID, crdcouspCounterInitial(i), crdcouspCounterChange(i), crdcouspCounterValue(i), 
              crdcouspCounterDate(i), crdcouspPreviousValue(i), crdcouspPreviousDate(i));
  end if;

  -- сохраняем общие счётчики договора
  if cntrcouCounterID is not null and cntrcouCounterID.Count > 0 then 
    forall i in cntrcouCounterID.First..cntrcouCounterID.Last 
      insert into TransactionContractCounters (TransactionID, TerminalDateTime, CounterID, CounterInitial, CounterChange, CounterValue, CounterDate, PreviousValue, 
                                               PreviousDate) 
      values (traTransactionID, traTerminalDateTime, cntrcouCounterID(i), cntrcouCounterInitial(i), cntrcouCounterChange(i), cntrcouCounterValue(i), cntrcouCounterDate(i), 
              cntrcouPreviousValue(i), cntrcouPreviousDate(i));
  end if;
            
  -- сохраняем счета договора    
  if caContractAccountID is not null and caContractAccountID.Count > 0 then       
    forall i in caContractAccountID.First..caContractAccountID.Last 
      insert into TransactionContractAccounts (TransactionID, TerminalDateTime, ContractAccountID, AmountInitial, AmountChange, AmountValue, CrossTerminalToAccount, 
        CrossAccountToTerminal) 
      values (traTransactionID, traTerminalDateTime, caContractAccountID(i), caAmountInitial(i), caAmountChange(i), caAmountValue(i), caCrossTerminalToAccount(i), 
        caCrossAccountToTerminal(i));       
  end if;           

  -- сохраняем счета владельца    
  if oaOwnerAccountID is not null and oaOwnerAccountID.Count > 0 then       
    forall i in oaOwnerAccountID.First..oaOwnerAccountID.Last 
      insert into TransactionOwnerAccounts (TransactionID, TerminalDateTime, OwnerAccountID, AmountInitial, AmountChange, AmountValue, CrossTerminalToAccount, 
        CrossAccountToTerminal) 
      values (traTransactionID, traTerminalDateTime, oaOwnerAccountID(i), oaAmountInitial(i), oaAmountChange(i), oaAmountValue(i), oaCrossTerminalToAccount(i), 
        oaCrossAccountToTerminal(i));
  end if;           

  -- сохраняем сообщения
  if not mesSkipMessages then 
    insert into TransactionMessages (TransactionID, TerminalDateTime, TerminalPrinter, RetailScreen, RetailPrinter) 
      values (traTransactionID, traTerminalDateTime, mesTerminalPrinter, mesRetailScreen, mesRetailPrinter);
  end if;
    
end;  
 
procedure SaveCard_v1(pSkipCard boolean, pCardNumber number, pUpdateFlags number, pStatusID number, pLastServiceDate date, pFirstServiceDate date, pCardState number, 
                      pPINBlock raw, pPINMethod number,
                      pTransactionDate date, pChangeReasonText varchar2, pServicePointID number, pContractID number,
                      crdcouID tNumbers, crdcouPeriod tNumbers, crdcouChangeValue tNumbers, crdcouReasonID number,  
                      crdcouspID tNumbers, crdcouspPeriod tNumbers, crdcouspChangeValue tNumbers, crdcouspReasonID number,
                      cntrcouID tNumbers, cntrcouPeriod tNumbers, cntrcouChangeValue tNumbers, cntrcouReasonID number, 
                      caID tNumbers, caAmountChange tNumbers, caReasonID number,
                      oaID tNumbers, oaAmountChange tNumbers, oaReasonID number) is
begin
  -- сохраняем данные карты
  if not pSkipCard then 
    insert into Cards_PostBox (CardNumber, UpdateFlags, StatusID, LastServiceDate, FirstServiceDate, CardState, PINBlock, PINMethod)
      values (pCardNumber, pUpdateFlags, pStatusID, pLastServiceDate, pFirstServiceDate, pCardState, pPINBlock, pPINMethod);
  end if;    


  -- сохраняем данные счётчиков карты
  if crdcouID is not null and crdcouID.Count > 0 then       
    forall i in crdcouID.First..crdcouID.Last 
      insert into CounterValues_PostBox (CardNumber, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText) values (pCardNumber, crdcouID(i), 
        opsOnline.GetCounterDate(crdcouPeriod(i), pTransactionDate), crdcouChangeValue(i), crdcouReasonID, pChangeReasonText);
  end if;           

  -- сохраняем данные счётчиков карты в разрезе ТО
  if crdcouspID is not null and crdcouspID.Count > 0 then       
    forall i in crdcouspID.First..crdcouspID.Last 
      insert into CounterValuesSP_PostBox (CardNumber, SPID, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText) values(pCardNumber, pServicePointID, 
        crdcouspID(i), opsOnline.GetCounterDate(crdcouspPeriod(i), pTransactionDate), crdcouspChangeValue(i), crdcouspReasonID, pChangeReasonText);
  end if;           

  -- сохраняем данные счётчиков договора 
  if cntrcouID is not null and cntrcouID.Count > 0 then       
    forall i in cntrcouID.First..cntrcouID.Last 
      insert into ContractCounterValues_PostBox (ContractID, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText) values (pContractID, cntrcouID(i), 
        opsOnline.GetCounterDate(cntrcouPeriod(i), pTransactionDate), cntrcouChangeValue(i), cntrcouReasonID, pChangeReasonText);
  end if;           
    
  -- сохраняем счета договора
  if caID is not null and caID.Count > 0 then
    forall i in caID.First..caID.Last
      insert into ContractAccounts_PostBox (ContractAccountID, ChangeDate, AmountChange, ReasonID, ReasonText) values (caID(i), pTransactionDate, caAmountChange(i), 
        caReasonID, pChangeReasonText);
  end if;       

  -- сохраняем счета владельца договора
  if oaID is not null and oaID.Count > 0 then
    forall i in oaID.First..oaID.Last
      insert into OwnerAccounts_PostBox (OwnerAccountID, ChangeDate, AmountChange, ReasonID, ReasonText) values (oaID(i), pTransactionDate, oaAmountChange(i), 
        oaReasonID, pChangeReasonText);
  end if;       
end;                       
  
end;
/