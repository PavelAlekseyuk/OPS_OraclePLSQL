CREATE OR REPLACE package body OPCL.opsOnlineRestrictions as

-- ����� execute immediate �� 20% ���� ���������, ��� ������� sql
-- ��������� ���������� ����� �� ������������ � ����� ��������� �� ������ pTerminalID ��� pContractID. ��� ���������� ������ ��� ��������. �� 10000 ������������ ������� ��� ������� � 1,5 �������
-- ���� pContractID �� ������� ��� null, �� ������ �� ������� �� ������������
-- pContractType: 1 ��� �������, 2 ��� ������
function CheckRestriction(pRestrictionsTable varchar2, pCondition varchar2, pConditionValue number, pTerminalID number, pServicePointID number default null, 
                          pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                          pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
  lServicePointID Terminals.SPID%type := pServicePointID;
  lRegionID ServicePoints.RegionID%type := pRegionID;
  lNetworkID ServicePoints.NetworkID%type := pNetworkID;
  lNetworkOwnerID Networks.GlobalOwnerID%type := pNetworkOwnerID;
  lClientID Contracts.ClientID%type := pClientID; 
  lContractOwnerID Contracts.OwnerID%type := pContractOwnerID; 
  lContractType Contracts.Type%type := pContractType;         

  -- �������������� ��������� ������ (������� � �������, ����� �������� ORA-04068 ����� ��������������)
  srtTerminals constant binary_integer := 1;
  srtServicePoints constant binary_integer := 2;
  srtRegions constant binary_integer := 3;
  srtNetworks constant binary_integer := 4;
  srtNetworkOwners constant binary_integer := 5;
  srtLoyaltyClients constant binary_integer := 6;
  srtLoyaltyGroups constant binary_integer := 7;
  srtCorporateClients constant binary_integer := 8;
  srtCorporateGroups constant binary_integer := 9;
  srtContractOwners constant binary_integer := 10;
  srtContracts constant binary_integer := 11;

  lTotalAllows number := 0; -- ����� ���������� ����������  
  lTotalForbids number := 0; -- ����� ���������� ��������
  lAllowsRank number := 0; -- ��������� ���� ���������� �� ���������� ������
  lForbidsRank number := 0; -- ��������� ���� �������� �� ���������� ������
        
  type tGroupInfo is record (GroupID number);
  type tGroupsInfo is table of tGroupInfo;
  lClientGroups tGroupsInfo := tGroupsInfo(); 
  
  type tSumRestrictionInfo is record (TableID binary_integer, Allows number, Forbids number);
  type tSumRestrictionsInfo is table of tSumRestrictionInfo; 
  lSumRestrictions tSumRestrictionsInfo := tSumRestrictionsInfo();

  type tRestrictionInfo is record (TableID binary_integer, ID number, Sign binary_integer); 
  type tRestrictionsInfo is table of tRestrictionInfo;
  lRestrictions tRestrictionsInfo := null;
  lLastTableID number := null;
    
  function AnalyzeRestrictionsByTable return binary_integer is
    lResult binary_integer := null;        
    lRecord tSumRestrictionInfo;
  begin
    if lSumRestrictions.Count > 0 then 
      for i in lSumRestrictions.First..lSumRestrictions.Last loop
        if lResult is null then 
          lRecord := lSumRestrictions(i); 
          if lRecord.Allows != 0 or lRecord.Forbids != 0 then
            if lRecord.Allows >= 0 and lRecord.Forbids > 0 then
              -- ���� ���� � ���������� � �������, � �� �� �������� �� � ���� �� ���, ���������� 2, �.�. ��������� �� �������� �� � ���� ������ 
              lResult := 2;
            elsif lRecord.Allows > 0 and lRecord.Forbids = 0 then
              -- ���� ���� ������ �����-�� ���������� � ��� ��� ���, �� ��������� 
              lResult := 0; 
            end if; 
          end if;       
        end if;
        exit when lResult is not null; 
      end loop;
    end if;

    return nvl(lResult, 2);
  end;

  function GetRankByTableID(pServiceTableID binary_integer) return binary_integer as
  begin
    case pServiceTableID
      when srtTerminals then return 10000;  
      when srtServicePoints then return 1000;
      when srtRegions then return 100; 
      when srtNetworks then return 10; 
      when srtNetworkOwners then return 1; 
      when srtContracts then return 1000;
      when srtLoyaltyClients then return 100; 
      when srtCorporateClients then return 100; 
      when srtLoyaltyGroups then return 10; 
      when srtCorporateGroups then return 10; 
      when srtContractOwners then return 1; 
      else raise_application_error(-20001, '����������� ������������� ��������� �������: '||pServiceTableID);
    end case;     
  end;

  function IsCurrentIDInTheLocation(pServiceTableID binary_integer, pID number) return binary_integer as
  begin
    case pServiceTableID
      when srtTerminals then return case when pID = pTerminalID then 1 else 0 end;  
      when srtServicePoints then return case when pID = lServicePointID then 1 else 0 end;
      when srtRegions then return case when pID = lRegionID then 1 else 0 end; 
      when srtNetworks then return case when pID = lNetworkID then 1 else 0 end; 
      when srtNetworkOwners then return case when pID = lNetworkOwnerID then 1 else 0 end; 
      when srtContracts then return case when pID = pContractID then 1 else 0 end; 
      when srtLoyaltyClients then return case when lContractType = 1 and pID = lClientID then 1 else 0 end; 
      when srtCorporateClients then return case when lContractType = 2 and pID = lClientID then 1 else 0 end; 
      when srtContractOwners then return case when pID = lContractOwnerID then 1 else 0 end;
      when srtLoyaltyGroups then 
        if lContractType = 1 and lClientGroups.Count > 0 then
          for i in lClientGroups.First..lClientGroups.Last loop
            if lClientGroups(i).GroupID = pID then return 1; end if; 
          end loop; 
        end if;
        return 0;
      when srtCorporateGroups then 
        if lContractType = 2 and lClientGroups.Count > 0 then
          for i in lClientGroups.First..lClientGroups.Last loop
            if lClientGroups(i).GroupID = pID then return 1; end if; 
          end loop; 
        end if;
        return 0;       
      else raise_application_error(-20001, '����������� ������������� ��������� �������: '||pServiceTableID);
    end case;    
  end;

  
begin  
  execute immediate 'select ServiceTableID, ID, Sign from '||pRestrictionsTable||' where '||pCondition
                  ||' order by decode(ServiceTableID, 5, 10,  4, 20,  3, 30,  2, 40,  1, 50,  10, 60,  7, 70,  9, 80,  6, 90,  8, 100,  11, 110, null) nulls last' 
    bulk collect into lRestrictions using pConditionValue; 
  if lRestrictions.Count = 0 then return 2; end if; -- �� ����� ���������� ��� ��������, ����������� � �������� �������

  -- ��������� � �������������� ������ ��� �������
  if pTerminalID is not null then
    begin
      if lServicePointID is null then select SPID into lServicePointID from Terminals where ID = pTerminalID; end if;
      if lRegionID is null or lNetworkID is null or lNetworkOwnerID is null then 
        select RegionID, NetworkID, GlobalOwnerID into lRegionID, lNetworkID, lNetworkOwnerID from ServicePoints where ID = lServicePointID; 
      end if;
    exception
      when no_data_found then raise_application_error(-20001, '������� ������������ TeminalID');
    end;
  end if; 
  
  if pContractID is not null then
    if lContractType is null or lClientID is null or lContractOwnerID is null then begin  
      select Type, ClientID, OwnerID into lContractType, lClientID, lContractOwnerID from Contracts where ID = pContractID;
    exception when no_data_found then raise_application_error(-20001, '������� ������������ ContractID'); end;  
    end if; 
  
    case lContractType
      when 1 then select GroupID bulk collect into lClientGroups from LoyaltyGroupDetails where LoyaltyClientID = lClientID;
      when 2 then select GroupID bulk collect into lClientGroups from CorporateGroupDetails where CorporateClientID = lClientID;
      else raise_application_error(-20001, '����������� ��� ��������: '||lContractType);
    end case;      
  end if;

  -- �������� ����� ���������� �������� � ����������, ������������� �� �������������� ������, � ����� ��������� ���������� ����������� ��� ��������� ������ 
  lLastTableID := null;
  for i in lRestrictions.First..lRestrictions.Last loop
    if lLastTableID is null or lLastTableID != lRestrictions(i).TableID then
      lSumRestrictions.Extend;
      lLastTableID := lRestrictions(i).TableID;
      lSumRestrictions(lSumRestrictions.Count).TableID := lLastTableID;
      lSumRestrictions(lSumRestrictions.Count).Allows := 0;
      lSumRestrictions(lSumRestrictions.Count).Forbids := 0;  
    end if; 
    if lRestrictions(i).Sign = 1 then lSumRestrictions(lSumRestrictions.Count).Allows := lSumRestrictions(lSumRestrictions.Count).Allows + 1; lTotalAllows := lTotalAllows + 1;
                                 else lSumRestrictions(lSumRestrictions.Count).Forbids := lSumRestrictions(lSumRestrictions.Count).Forbids + 1; lTotalForbids := lTotalForbids + 1;
    end if; 
  
    if IsCurrentIDInTheLocation(lRestrictions(i).TableID, lRestrictions(i).ID) = 1 then 
      if lRestrictions(i).Sign = 1 then lAllowsRank := lAllowsRank + GetRankByTableID(lRestrictions(i).TableID);
                                   else lForbidsRank := lForbidsRank + GetRankByTableID(lRestrictions(i).TableID);
      end if; 
    end if;
  end loop;
  
  -- ��������� ������
  if lTotalAllows = 0 and lTotalForbids = 0 then return 2; -- ���� ��� �� ���������� �� ��������, �������� ��� ������ �� ����������������)
  elsif lAllowsRank = 0 and lForbidsRank = 0 then return AnalyzeRestrictionsByTable; -- ��� �������, ����������� � �������� ��������������
  elsif lTotalAllows > 0 and lTotalForbids = 0 then return case when lAllowsRank > 0 then 1 else 0 end; -- ���� ���� ������ ����������, ������� ����� ������ ��� �������� 
  elsif lTotalForbids > 0 then return case when lAllowsRank >= lForbidsRank then 1 else 0 end; -- ���� ���� � ���������� � �������, ������� ����� ������� ������ �� ��� ��������
  else return 0;
  end if;
end;

/*
function CheckRestriction(pRestrictionsTable varchar2, pCondition varchar2, pConditionValue number, pTerminalID number, pServicePointID number default null, 
                          pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                          pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
  lServicePointID Terminals.SPID%type := pServicePointID;
  lRegionID ServicePoints.RegionID%type := pRegionID;
  lNetworkID ServicePoints.NetworkID%type := pNetworkID;
  lNetworkOwnerID Networks.GlobalOwnerID%type := pNetworkOwnerID;
  lClientID Contracts.ClientID%type := pClientID; 
  lContractOwnerID Contracts.OwnerID%type := pContractOwnerID; 
  lContractType Contracts.Type%type := pContractType;
  lNotConfiguredCounter number(10) := 0;
     
  lTables ListOfValues := ListOfValues();
  lValues ListOfValues := ListOfValues();  
  lResult number(1) := 0;
  
  function CheckID(pTableID number, pID number) return number as
    lAllows number := 0; -- ���������� ����������  
    lForbids number := 0; -- ���������� ��������
    lObjectAllows number := 0; -- ���������� ���������� �� ���������� ������
    lObjectForbids number := 0; -- ���������� �������� �� ���������� ������
    lResult number(1) := 0;
  begin
    execute immediate 
      'select nvl(sum(decode(sign, 1, 1, 0)), 0) Allows, nvl(sum(decode(sign, 0, 1, 0)), 0) Forbids, nvl(sum(case when sign = 1 and ID = :ID then 1 else 0 end), 0) ObjectAllows, nvl(sum(case when sign = 0 and ID = :ID then 1 else 0 end), 0) ObjectForbids from '||pRestrictionsTable||' where '||pCondition||' and ServiceTableID = :TableID' 
      into lAllows, lForbids, lObjectAllows, lObjectForbids using pID, pID, pConditionValue, pTableID;
    
    if lAllows = 0 and lForbids = 0 then lResult := 2; -- ���� ��� �� ���������� �� ��������, ��������� ������� ������ (������������ �������, ��� ������ �� ����������������)
    elsif lAllows > 0 and lForbids = 0 then lResult := case when lObjectAllows > 0 then 1 else 0 end; -- ���� ���� ������ ����������, ������� ����� ������ ��� �������� 
    elsif lForbids > 0 then lResult := case when lObjectForbids = 0 then 1 else 0 end; -- ���� ���� � ���������� � �������, ������� ����� ������� ������ �� ��� ��������
    end if;
    
    return lResult;
  end;
       
begin
  -- ��������� � �������������� ������ ��� ������� 
  --if pTerminalID is null then raise_application_error(-20001, 'TeminalID �� �������'); end if; ������
  if pTerminalID is not null then
    begin
      if lServicePointID is null then select SPID into lServicePointID from Terminals where ID = pTerminalID; end if;
      if lRegionID is null then select RegionID into lRegionID from ServicePoints where ID = lServicePointID; end if;
      if lNetworkID is null then select NetworkID into lNetworkID from ServicePoints where ID = lServicePointID; end if;
      if lNetworkOwnerID is null then select GlobalOwnerID into lNetworkOwnerID from Networks where ID = lNetworkID; end if;
    exception
      when no_data_found then raise_application_error(-20001, '������� ������������ TeminalID');
    end;
    
    lTables.Extend(5); lValues.Extend(5);
    lTables(1) := srtTerminals; lValues(1) := pTerminalID; 
    lTables(2) := srtServicePoints; lValues(2) := lServicePointID; 
    lTables(3) := srtRegions; lValues(3) := lRegionID; 
    lTables(4) := srtNetworks; lValues(4) := lNetworkID; 
    lTables(5) := srtNetworkOwners; lValues(5) := lNetworkOwnerID; 
  end if; 
  
  if pContractID is not null and (lContractType is null or lClientID is null or lContractOwnerID is null) then 
    begin  
      select Type, ClientID, OwnerID into lContractType, lClientID, lContractOwnerID from Contracts where ID = pContractID;
    exception
      when no_data_found then raise_application_error(-20001, '������� ������������ ContractID');
    end;  
  end if;

  if pContractID is not null then  
    lTables.Extend(4); -- ��������� ������ ��� �������� ��������
    lValues.Extend(4);
    lTables(lTables.Count-3) := srtContracts; -- ���� ��� ������� ID ��������
    lValues(lValues.Count-3) := pContractID;
    lTables(lTables.Count-2) := srtContractOwners; -- ���� ��� ������� ��������� ���������
    lValues(lValues.Count-2) := lContractOwnerID;
    lValues(lValues.Count-1) := lClientID; -- ���� ��� ������� �������
    lValues(lValues.Count) := 1; -- ���� �������� ������� �����
    if lContractType = 1 then -- ������� � �������
      lTables(lTables.Count-1) := srtLoyaltyClients; -- ���� ��� ������� �������
      lTables(lTables.Count) := srtLoyaltyGroups; -- ���� ��� ������� ����� �������� 
    elsif lContractType = 2 then  -- ������� � ������
      lTables(lTables.Count-1) := srtCorporateClients; -- ���� ��� ������� �������
      lTables(lTables.Count) := srtCorporateGroups; -- ���� ��� ������� ����� ��������
    end if; 
  end if;
  
  -- ���������� �������� �������������� ������
  lNotConfiguredCounter := 0;
  for i in 1..lTables.Count loop
    if lTables(i) = srtLoyaltyGroups and lValues(i) = 1 then -- ��� ����� ���������� ���� ������, ����� ����������
      for Rec in (select GroupID from LoyaltyGroupDetails where LoyaltyClientID = lClientID) loop
        lResult := CheckID(lTables(i), Rec.GroupID);
        if lResult = 0 then exit; end if;
      end loop;
    elsif lTables(i) = srtCorporateGroups and lValues(i) = 1 then -- ��� ������������� ����� ���� ������, ����� ����������
      for Rec in (select GroupID from CorporateGroupDetails where CorporateClientID = lClientID) loop
        lResult := CheckID(lTables(i), Rec.GroupID);
        if lResult = 0 then exit; end if;
      end loop;
    else
      lResult := CheckID(lTables(i), lValues(i)); -- ��������� ��� ��������� ����������� 
    end if;
      
    if lResult = 0 then exit;
    elsif lResult = 2 then lNotConfiguredCounter := lNotConfiguredCounter + 1; 
    end if;
  end loop; 

  -- ���� ������� �������������������� ����������� �� ������ ���������� ����� � ������ �������� (����� ���� ������ ��-�� �����) - ���������� "�� ����������������", ����� ���������� "���������"
  if lResult > 0 then 
    if lNotConfiguredCounter >= lTables.Count then lResult := 2; else lResult := 1; end if; 
  end if;

  return lResult;
end;

*/

function CheckTariffPeriod(pPeriodID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                           pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
begin
  return CheckRestriction('PeriodRestrictions', 'PeriodID = :PeriodID', pPeriodID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function CheckContract(pContractID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                       pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
begin
  return CheckRestriction('ContractRestrictions', 'ContractID = :ContractID', pContractID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function CheckCard(pCardNumber number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                   pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
begin
  return CheckRestriction('CardRestrictions', 'CardNumber = :CardNumber', pCardNumber, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function CheckParamSet(pSetID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                       pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
begin
  return CheckRestriction('ParamSetRestrictions', 'SetID = :SetID', pSetID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function CheckGraduation(pGraduationID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                         pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
begin
  return CheckRestriction('GraduationRestrictions', 'GraduationID = :GraduationID', pGraduationID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function CheckCardRange(pRangeID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                         pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
begin
  return CheckRestriction('CardRangeRestrictions', 'RangeID = :RangeID', pRangeID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function CheckContractOwner(pContractOwnerID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                            pContractID number default null, pContractType number default null, pClientID number default null) return number deterministic as
begin
  return CheckRestriction('ContractOwnerRestrictions', 'ContractOwnerID = :ContractOwnerID', pContractOwnerID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function CheckNetworkOwner(pNetworkOwnerID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null,  
                            pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
begin
  return CheckRestriction('NetworkOwnerRestrictions', 'NetworkOwnerID = :NetworkOwnerID', pNetworkOwnerID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function CheckOwnerAccount(pOwnerAccountID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null,
                            pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic as
begin
  return CheckRestriction('OwnerAccountRestrictions', 'OwnerAccountID = :OwnerAccountID', pOwnerAccountID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractID, pContractType, pClientID, pContractOwnerID);
end;

function GetOwnerID(pServiceTableID number, pID number) return number as
  lOwnerID Owners.ID%type := null;
  
  -- �������������� ��������� ������ (������� � �������, ����� �������� ORA-04068 ����� ��������������)
  srtTerminals constant binary_integer := 1;
  srtServicePoints constant binary_integer := 2;
  srtRegions constant binary_integer := 3;
  srtNetworks constant binary_integer := 4;
  srtNetworkOwners constant binary_integer := 5;
  srtLoyaltyClients constant binary_integer := 6;
  srtLoyaltyGroups constant binary_integer := 7;
  srtCorporateClients constant binary_integer := 8;
  srtCorporateGroups constant binary_integer := 9;
  srtContractOwners constant binary_integer := 10;
  srtContracts constant binary_integer := 11;
  
begin
  case pServiceTableID
    when srtTerminals then select GlobalOwnerID into lOwnerID from Terminals where ID = pID;
    when srtServicePoints then select GlobalOwnerID into lOwnerID from ServicePoints where ID = pID;
    when srtRegions then select GlobalOwnerID into lOwnerID from Regions where ID = pID;
    when srtNetworks then select GlobalOwnerID into lOwnerID from Networks where ID = pID;
    when srtNetworkOwners then lOwnerID := pID;
    when srtLoyaltyClients then select OwnerID into lOwnerID from LoyaltyClients where ID = pID;
    when srtLoyaltyGroups then select OwnerID into lOwnerID from LoyaltyGroups where ID = pID;
    when srtCorporateClients then select OwnerID into lOwnerID from CorporateClients where ID = pID;
    when srtCorporateGroups then select OwnerID into lOwnerID from CorporateGroups where ID = pID;
    when srtContracts then select OwnerID into lOwnerID from Contracts where ID = pID;
    when srtContractOwners then lOwnerID := pID;
    else raise_application_error(-20001, '����������� ID ��������� �������: '||pServiceTableID);
  end case;
  return lOwnerID;
exception
  when no_data_found then raise_application_error(-20001, '������� �������� ID: '||pID||' ��� ��������� ������� '||pServiceTableID);
end;

function GetCardPurseRestrictionsCount(pCardNumber number, pCardContractID number, pCardOwnerID number) return number as
  lCount number;
begin
  select sum(c) into lCount from
  (
    select count(1) c from ContractPurseRestrictions where ContractID = pCardContractID
    union all
    select count(1) c from COwnerPurseRestrictions where OwnerID = pCardOwnerID
    union all
    select count(1) c from CardPurseRestrictions where CardNumber = pCardNumber
  );
  return lCount;
end;

-- ����� execute immediate � 1,2 ���� ���������, ��� ������� sql
-- ��������� ���������� ����� �� ������������ � ����� ��������� �� ������ TerminalID. ��� ���������� ������ ��� ��������. �� 10000 ������������ ������� ��� ������� � 1,5 �������
-- pClientType: 1 ��� �������, 2 ��� ������
/*function CheckRestriction(pRestrictionsTable varchar2, pCondition varchar2, pConditionValue number, pTerminalID number, pServicePointID number default null, 
                          pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null) return number as
  lAllowedWeight number := 0; -- ��������� ��� ����������  
  lForbiddenWeight number := 0; -- ��������� ��� ��������
  lServicePointID Terminals.SPID%type := pServicePointID;
  lRegionID ServicePoints.RegionID%type := pRegionID;
  lNetworkID ServicePoints.NetworkID%type := pNetworkID;
  lNetworkOwnerID Networks.OwnerID%type := pNetworkOwnerID;      
begin
  -- ��������� � �������������� ������ ��� ������� 
  if pTerminalID is null then raise_application_error(-20001, 'TeminalID �� �������'); end if;
  if lServicePointID is null then select SPID into lServicePointID from Terminals where ID = pTerminalID; end if;
  if lRegionID is null then select RegionID into lRegionID from ServicePoints where ID = lServicePointID; end if;
  if lNetworkID is null then select NetworkID into lNetworkID from ServicePoints where ID = lServicePointID; end if;
  if lNetworkOwnerID is null then select OwnerID into lNetworkOwnerID from Networks where ID = lNetworkID; end if;

  -- �������� ������ �� ������� ������������ ������ ������� � �������� ������� �������������
  -- �������� ������ ������ �� ������ ��������
  execute immediate 
  'select nvl(sum(case when Sign = 1 then Weight else 0 end), 0), nvl(sum(case when Sign = 0 then Weight else 0 end), 0) from
  (
      select Sign, decode(ServiceTableID, '||srtTerminals||', 10000, '||srtServicePoints||', 1000, '||srtRegions||', 100, '||srtNetworks||', 10, '||srtNetworkOwners||', 1, 0) Weight 
        from '||pRestrictionsTable||' where '||pCondition||' and (ServiceTableID, ID) in
        ( 
          select '||srtTerminals||', :pTerminalID from dual 
          union all 
          select '||srtServicePoints||', :lServicePointID from dual 
          union all 
          select '||srtRegions||', :lRegionID from dual 
          union all  
          select '||srtNetworks||', :lNetworkID from dual 
          union all 
          select '||srtNetworkOwners||', :lNetworkOwnerID from dual 
        )
  )' into lAllowedWeight, lForbiddenWeight using pConditionValue, pTerminalID, lServicePointID, lRegionID, lNetworkID, lNetworkOwnerID;
  -- ������ �����. ���� ��� ���������� ����� ����� ���� ������� - ���������. ��! ���� ������ �� ����������� - ��������� ��   
  if lAllowedWeight = 0 and lForbiddenWeight = 0 then return 2; end if; -- ���� ����������� �� �����������    
  if lAllowedWeight > lForbiddenWeight then return 1; else return 0; end if; -- ���� ����������� �����������
end;*/


end;
/