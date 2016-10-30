CREATE OR REPLACE package OPCL.opsOnline as 
-- ������ ����� ������������ Online-��������. ���� �� ����� �������� - ������ �������� �� �����. Beware!
-- (C) Pavel Alekseyuk, 2012-2015
-- � ������ ������ ��������� ���������� ��� ��������� ��� �������������� ��������� ������ ORA-04068 ����� �������������� � ����������� ����

-- �������� �� ID ���������� ����������, � ������������
procedure ExtractFromTransactionID(pID number, pSource out number, pPCOwnerID out number, pUniqueNumber out number);

-- ������ ID ���������� �� �����������
function BuildTransactionID(pSource number, pPCOwnerID number, pUniqueNumber number) return number;

-- �������� ���������� ID ����������. TerminalID - ID ���������, �� ������� ������������ ����������, Source - �������� ���������� (Srvc_TransactionSources)
-- PCOwnerID - ID ��������� ��������������� ������ ������� �����������
-- ��������� �� ��������������. ���� PCOwnerID �� �������, �� ����� ������� �� ������������ �������
function GetTransactionID(pSource number default 1, pPCOwnerID number default null) return number;

-- ������ ����� � ������� (� ���������� ����������. �� ���������� �������� ���������)
-- 01.07.2012. ���� pContractOwnerID �� ������������. �������� ����� ������� �� ���� CardRanges.ContractOwnerID
-- pRegionID �������� �� pCurrencyID 
-- 08.08.2014 �������� pCurrencyID ������ - ��������� ������� �� ��������� �����
-- 19.01.2015 �������� �������� pTryAutoAcceptQuest: ���� 1, �� ������� �������� ������������� ������� ������, ���� ��� ������ � ���������� ��������� ����
function CreateCard(pCardNumber number,  pTerminalID number default null, pTerminalDateTime date default sysdate, pRegisterActivation number default 0, 
                    pContractID number default null, pTryAutoAcceptQuest number default 1) return number;

-- ������ ������� ����� � ���������� ����������. �������� ���������
function CreateCardCounter(pName varchar2, pDescription varchar2, pType number, pSubType number, pPeriod number) return number;

-- ���������� ID ������ �� ��. ���� ����������� ������ ��� ��� � ����������� ������� - ������ ��� � �������� ���������� ��� �������
function GetArticleID(pGoodsCode varchar2, pGoodsName varchar2, pRetailSystemID number) return number;
function GetArticleID2(pGoodsCode varchar2, pGoodsName varchar2, pRetailSystemID number, pNetwordOwnerID number) return number;

-- ���������� ����/����� ��������, �� ������� �� ������ ���� ������. ���� ����������� �� ������� �������� � ������� ����������. 
-- pPeriodsAgo - ������� �������� �������� ����� ��������� �����: 0 - ������� ������ ������� �� ������ ���� ����������, 1 - ����� ������ �������� ������� � ��������� ������ ����������� ������� 
function GetCounterDate(pCounterPeriod number, pTransactionDate date, pPeriodsAgo number default 0) return date deterministic;

-- ������ GetCounterDate, �� �������� �� ID ��������, ������� ������ �� �����������
function GetCounterDateByID(pCounterID number, pTransactionDate date, pPeriodsAgo number default 0) return date deterministic;

-- ���������� ID ������� ���������. ���� ������� ��������� ��� � ����������� - ������������ �
function GetMeasureUnitID(pMeasureUnitName varchar2) return number;

-- ��������� ������������ Luhn-���� ����� (��������� ����� ������)
function IsCorrectLuhn(pCardNumber number) return number;

-- �������� ���������� � �������������� ���������. ��������� �������� � ������ ������
--   pOriginalID: ID ������������ ���������� ��� ������, pRSDateTime: ���� ��� ��� ��������� ������ pSerialNumber: �������� ����� ����������, �� ������� ��������� �������� ������
--   pCancelID: ���� ���������, �� ������������ ���������� ID ���������� ������. ���� null, �� ID ���������� ����� ������������ �� ������ ������������ ����������
--   pNeedLockCard: ����� ��� ��� ����������� ����� ��� ��������� ������ CounterValues (������ 1 ���� ������� ���������� ���� �� ���� � 0 - ���� � ������� ��, ������� ���� ��������� �����)
--   pCancelSource: �������� ���������� ������. ���� null, �� ������ �������� ������������ ����������
-- ���������� ID ���������� ������
-- ������� �� �������� ���������
-- ���� � ����� ���������� ������ ������ ��������� � ����� ������������ ���������� ��� ���������� ��������� ���������
function CancelTransaction(pOriginalID number, pCancelID number default null, pNeedLockCard number default 0, pRSDateTime date default null, 
                           pSerialNumber varchar2 default null, pCancelSource number default null) return number;
function CancelTransaction2(pOriginalID number, pCancelID number, pNeedLockCard number, pRSDateTime date, pSerialNumber varchar2, pCancelSource number, 
                            pSignature raw, pAppSign number) return number;

-- ����������� ���������� ����� ������: � ������ ������ ��� ������� � � ���������� ����������
procedure RegisterQuestTransaction(pCardNumber number, pTerminalID number, pDateTime date, pDeadLineTime date, pID number default null);
procedure RegisterQuestTransactionA(pCardNumber number, pTerminalID number, pDateTime date, pDeadLineTime date, pID number default null);

-- ����������� ���������� �� �����: � ������ ������ ��� �������
procedure RegisterCardTransaction(pCardNumber number, pTerminalID number, pDateTime date, pTransactionType number, pOldNData number default null, pNewNData number default null, pOldVCData varchar2 default null, pNewVCData varchar2 default null);

-- ����������� ���������� ��������� �����
procedure RegisterActivationTransaction(pCardNumber number, pTerminalID number, pDateTime date);

-- ���������� ������� Cards_Postbox ��� ���������� ������������ � ��� ���������. ��������� ������ ����������� �����������.
-- �������� ��������� ����� ������ ������
procedure ProcessCardsPostbox;

-- ���������� ������� ContractAccounts_Postbox ��� ���������� ��������� ����� ��������. ��������� ������ ����������� �����������.
-- �������� ��������� ����� ������ ������
procedure ProcessContractAccountsPostbox;

-- ���������� ������� OwnerAccounts_Postbox ��� ���������� ��������� ����� ���������. ��������� ������ ����������� �����������.
-- �������� ��������� ����� ������ ������
procedure ProcessOwnerAccountsPostbox;

-- ���������� ������� CounterValues_Postbox ��� ���������� ��������� ��������� �����. ��������� ������ ����������� �����������.
-- �������� ��������� ����� ������ ������
procedure ProcessCounterValuesPostbox;

-- ���������� ������� CounterValues_Postbox ��� ���������� ��������� ��������� ����� �� ��. ��������� ������ ����������� �����������.
-- �������� ��������� ����� ������ ������
procedure ProcessCounterValuesSPPostbox;

-- ���������� ��������� � ��������� ���
procedure Log(pMessage varchar2);

-- ��������� ��� �������, ������� ������� �������������� ������� � ����������� ���������� �������
procedure PeriodicalFast;

-- ��������� ������� �������, ������� ������� �������������� ������� �������� ��� � �����
procedure PeriodicalSlow;

-- ���������� �����-����, ����������� �� ���������� ����. ���������� ��������, ���� �����-���� �� ������
function GetCrossRate(pIDFrom number, pIDTo number, pCurrentDate date) return number;

-- �������� �������� ������ ������, ����������� � ������ pCurrentDate
function GetValidTariffPeriodID(pTariffID number, pCurrentDate date) return number deterministic;

-- ���������� 0, ���� ���������� ���� �� ������ �� � ���� �� �������� ��������. � ��������� ������ ���������� ���������� �������� �������� � ������� ������ ���������� ���� (������ 1)
function IsClosedDateTime(pDateTime date) return number;

-- ���������, ���������� �� ���������� ����������. ���� �� ����������, �� ���������� ��� TransactionSources � ��� PC.Owners ��� � ������. ���������� ID ��������� ���������� ��� ���������� Exception, ���� ���������� �� �������
function AdjustTransactionID(pID number) return number;

-- ��������������� ������ �� ��� � ���������� ���������� � ���������� ��� �������������. ���� �� ��� ��� ������, ������ ���������� �������������
function CreateRetailSystem(pOwnerID number, pGlobalID number, pName varchar2, pEncoding varchar2) return number;

-- ��������������� ������ ���� �� � ���������� ���������� � ���������� ��� �������������. ���� ���� �� ��� �������, ������ ���������� �������������
function CreateNetwork(pOwnerID number, pGlobalID number, pName varchar2) return number;

-- ��������������� ������ ������ � ���������� ���������� � ���������� ��� �������������. ���� ������ ��� ������, ������ ���������� �������������.
function CreateRegion(pOwnerID number, pGlobalID number, pName varchar2, pTimeOffset number, pCurrencyID number, pCultureName varchar2) return number;

-- ��������������� ������ �� � ���������� ���������� � ���������� ��� �������������. ���� �� ��� �������, ������ ���������� �������������.
function CreateServicePoint(pOwnerID number, pGlobalID number, pName varchar2, pAddress varchar2, pTimeOffset number, pRegionID number, pNetworkID number, pRSID number) return number;

-- ��������������� ������ �������� � ���������� ���������� � ���������� ��� �������������. ���� �������� ��� ������, ������ ���������� �������������
function CreateTerminal(pOwnerID number, pGlobalID number, pName varchar2, pServicePointID number) return number;

-- ���������� ID ��������� ��� ����������� ������ �����
function GetCardRangeID(pCardNumber number) return number;

-- ������ ������� �� �������� email � ���������� ���������� � �������� ���������. ���������� ID ���������� �������
function CreateEmail(pCardNumber number, pSMTPProviderID number, pAddress varchar2, pSubject varchar2, pBody varchar2) return number;

-- ������ ������� �� �������� SMS � ���������� ���������� � �������� ���������. ���������� ID ���������� �������
function CreateSMS(pCardNumber number, pSMSProviderID number, pPhone varchar2, pMessage varchar2) return number;

-- ���������� ���������� ������� �������, ������������������ ��� ���������� �����, �������� � ���������. ��� ��������� ������ ���� not null
function GetCardEventsCount(pCardNumber number, pCardContractID number, pCardOwnerID number) return number;

-- ���������� ��������� ����������� ID �� ������� Cards_Postbox ��� ���������� ����� ��� null, ���� ��� �������
function GetLastIDInCardsPostBox(pCardNumber number) return number;

-- �������� �������� �������� �����. pTransactionDate - ��� ������� ���� ����������, �� ������� ���������� �������. ��������� �������� ����� �� ��������� � ���������� �������.
-- ���� pProcessCopyTo = 1, �� ������� ��������� ��������� ����� ����� ��������.
procedure ChangeCardCounterValue(pCardNumber number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);
-- A - ���� ����� � ���������� ����������
procedure ChangeCardCounterValueA(pCardNumber number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);

-- ���������� ��� ��������� ����� �� ��
procedure ChangeCardCounterSPValue(pCardNumber number, pServicePointID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);
procedure ChangeCardCounterSPValueA(pCardNumber number, pServicePointID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);

-- ���������� ��� ��������� ��������
procedure ChangeContractCounterValue(pContractID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);
procedure ChangeContractCounterValueA(pContractID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);

-- �������-������ ��� ������ ���������� ����� � SQL-�������
function CardLockRequest(pLockID integer, pTimeout integer) return integer;

-- ������� ���������� ���������� �����, �������� �� ���� pTransactionDate, �������������� �������� pCardScriptID, ��� ����� pCardNumber 
function GetCardActiveActionsCount(pCardNumber number, pCardScriptID number, pTransactionDate date, pCardOwnerID number default null) return number;

-- �������, ������������ ���������� ��������� ����� � ������ ��������� � Cards_Postbox
function GetCardActualParameters(pCardNumber number, pInStatusID number, pInCardState number, pInLastServiceDate date, pInFirstServiceDate date, pInPINBlock raw, pInPINMethod number) return sys_refcursor;
-- ��������� ���������� ������� GetCardActualParameters, �� �������� ����� ��������� ���������� 
procedure GetCardActualParameters2(pCardNumber number, pStatusID in out number, pCardState in out number, pLastServiceDate in out date, pFirstServiceDate in out date, pPINBlock in out raw, pPINMethod in out number);

end;
/