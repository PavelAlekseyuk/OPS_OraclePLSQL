CREATE OR REPLACE package OPCL.opsOnlineSaveData as 
-- ѕакет дл€ быстрого сохранени€ данных в Ѕƒ
-- (C) Pavel Alekseyuk, 2015

type tNumbers is table of number index by binary_integer;
type tStrings4000 is table of varchar2(4000 char) index by binary_integer;
type tStrings17 is table of varchar2(17 char) index by binary_integer;
type tStrings127 is table of varchar2(127 char) index by binary_integer;
type tStrings50 is table of varchar2(50 char) index by binary_integer;
type tDates is table of date index by binary_integer;

-- —охран€ютс€ все данные транзакции
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

  mesSkipMessages boolean, mesTerminalPrinter varchar2, mesRetailScreen varchar2, mesRetailPrinter varchar2);

-- —охран€ютс€ все данные карты и договора
procedure SaveCard_v1(pSkipCard boolean, pCardNumber number, pUpdateFlags number, pStatusID number, pLastServiceDate date, pFirstServiceDate date, pCardState number, 
                      pPINBlock raw, pPINMethod number,
                      pTransactionDate date, pChangeReasonText varchar2, pServicePointID number, pContractID number,
                      crdcouID tNumbers, crdcouPeriod tNumbers, crdcouChangeValue tNumbers, crdcouReasonID number,  
                      crdcouspID tNumbers, crdcouspPeriod tNumbers, crdcouspChangeValue tNumbers, crdcouspReasonID number,
                      cntrcouID tNumbers, cntrcouPeriod tNumbers, cntrcouChangeValue tNumbers, cntrcouReasonID number, 
                      caID tNumbers, caAmountChange tNumbers, caReasonID number,
                      oaID tNumbers, oaAmountChange tNumbers, oaReasonID number);

end;
/