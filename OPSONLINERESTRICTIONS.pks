CREATE OR REPLACE package OPCL.opsOnlineRestrictions as 
-- ������ ����� ������������ Online-��������. ���� �� ����� �������� - ������ �������� �� �����. Be carefully!
-- (C) Pavel Alekseyuk, 2012-2015
-- � ������ ������ ��������� ���������� ��� ��������� ��� �������������� ��������� ������ ORA-04068 ����� �������������� � ����������� ����

/* 
   �������� ����������� (��� ������� ���� �������):  
     �) ������ ������������ ����������
     �) ���� ���� ������ ���������� � ��� ��������, �� ��������� �� ��� �� ���������
     �) ���� ���� (������ �������) ��� (���������� � �������), �� ��������� �� ��� �� ���������
     �) ���� ��� �� ���������� �� ��������, �� ��������� ��
   ����������� ������ ���� �����: 
     1. ���������������: ��������, ��, ������, ���� ��, �������� ���� ��. 
     2. ����������: �������, ������, ������ ��������, �������� ���������. ����� ����������� � ������� �������� ����������, �� ������ ����������.
          ���� ������ �������� - ������ ������� ���������� � ���������� ������. ���� ������ �������� - ������� � ��������
          ���� ��� ������, � ������� ������ ������ ��������� - ������ ������� ���������� � ���������� ������. ���� ���� �� ���� ������ ��������� - ������� � ��������
          ���� �������� ��������� �������� - ������ ������� ���������� � ���������� ������. ���� �������� ��������� �������� - ������� � ��������.
          � ���������� �������� ��������� - ���������� ��� ������
   ��������������� ����������� ������������� ��������������� (������� ����� ���������� ������). 
*/

type ListOfValues is varray(300) of number;

-- ���������������� ����������� �� ������ ������ � ������� 1 - ������ ������ �������� �� ��������� ��������, 0 - ������ ������ �������� �� ��������� ��������, 2 - ����������� �� ����������������
-- ��������� ���������� ����� �� ������������ � ����� ��������� �� ������ TerminalID. ��� ���������� ������ ��� ��������. �� 10000 ������������ ������� ��� ������� � 1,5 �������
function CheckTariffPeriod(pPeriodID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                           pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- ���������������� ����������� �� �������. ��. ContractRestrictions 
function CheckContract(pContractID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                       pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- ���������������� ����������� �� �����. ��. CardRestrictions. �� ������ �������� ���������� �� ����� ���� ������ pContractID, ������� ������� ���� ������� ��������� 
function CheckCard(pCardNumber number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                   pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- ���������������� ����������� �� ����� ����������. ��. ParamSetRestrictions 
function CheckParamSet(pSetID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                       pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- ���������������� ����������� �� �������� ������� ������. ��. GraduationRestrictions  
function CheckGraduation(pGraduationID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                         pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- ���������������� ����������� �� �������� ����. ��. CardRangeRestrictions
function CheckCardRange(pRangeID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                         pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- ���������������� ����������� �� ��������� ��������. ��. ContractOwnerRestrictions
function CheckContractOwner(pContractOwnerID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                            pContractID number default null, pContractType number default null, pClientID number default null) return number deterministic;

-- ���������������� ����������� �� ��������� ���� ��. ��. NetworkOwnerRestrictions
function CheckNetworkOwner(pNetworkOwnerID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null,  
                            pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- ���������������� ����������� �� ���� ���������. ��. OwnerAccountRestrictions
function CheckOwnerAccount(pOwnerAccountID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null,
                            pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- ���������� ID ��������� (���� ��� ��������) ��� ����������� ��������������
function GetOwnerID(pServiceTableID number, pID number) return number;

-- ���������� ���������� ����������� �� ��������, ������������������ ��� �����, �������� � ���������. ��� ��������� ������ ���� not null
function GetCardPurseRestrictionsCount(pCardNumber number, pCardContractID number, pCardOwnerID number) return number;

end;
/