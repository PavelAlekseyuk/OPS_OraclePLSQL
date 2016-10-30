CREATE OR REPLACE package body OPCL.opsOnlineLoadData as

procedure LoadCardData_v1(pCardNumber number, pTerminalID number, pTerminalCurrencyID number, pServicePointID number, pRegionID number, pNetworkID number, pNetworkOwnerID number, 
                          pCardScriptID number, pTransactionDate date, pCentralDate date,
                          pCardData out opsTypeCardData_v1, 
                          pContractID number, pContractData out opsTypeContractData_v1, 
                          pCardCounters out sys_refcursor, pCardCountersSP out sys_refcursor, pContractCounters out sys_refcursor,
                          pCardLimits out sys_refcursor, pCardEvents out sys_refcursor, pCardPurseRestrictions out sys_refcursor, pCardActions out sys_refcursor, 
                          pContractTariffPeriods out sys_refcursor, pContractLimits out sys_refcursor, pContractAccounts out sys_refcursor, pOwnerAccounts out sys_refcursor) is
begin
  pCardData := opsTypeCardData_v1();

  -- Загружаем данные карты
  pCardData.CardNumber := pCardNumber;
  select c.Message, c.RangeID, c.CardType, c.DefaultDiscount, c.ContractID, c.LockID, 
         opsOnlineRestrictions.CheckCard(c.CardNumber, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, null, null, null, null) as CardRestriction,
         opsOnlineRestrictions.CheckCardRange(c.RangeID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, null, null, null, null) as RangeRestriction,
         qt.DeadLineTime as QuestDeadLine, qt.TerminalDateTime as QuestDateTime, at.TerminalDateTime as ActivationDateTime, at.TerminalID as ActivationTerminalID,
         c.ValidityDate, c.Signature, c.MobilePhone, c.Email, ch.Email as HolderEmail, ch.MobilePhone as HolderMobilePhone, c.OwnerID,
         c.StatusID, c.CardState, c.LastServiceDate, c.FirstServiceDate, c.PINBlock, c.PINMethod, 
         opsOnline.CardLockRequest(c.LockID, 2) LockResult,
         (select count(1) from CardLimits z where z.CardNumber = c.CardNumber) LimitsCount, 
         opsOnline.GetCardEventsCount(c.CardNumber, c.ContractID, c.OwnerID) EventsCount, 
         opsOnlineRestrictions.GetCardPurseRestrictionsCount(c.CardNumber, c.ContractID, c.OwnerID) PurseRestrictionsCount,
         opsOnline.GetCardActiveActionsCount(c.CardNumber, pCardScriptID, pTransactionDate, c.OwnerID) ActionsCount                  
   into pCardData.Message, pCardData.RangeID, pCardData.CardType, pCardData.DefaultDiscount, pCardData.ContractID, pCardData.LockID, pCardData.CardRestriction,
        pCardData.RangeRestriction, pCardData.QuestDeadLine, pCardData.QuestDateTime, pCardData.ActivationDateTime, pCardData.ActivationTerminalID, 
        pCardData.ValidityDate, pCardData.Signature, pCardData.MobilePhone, pCardData.Email, pCardData.HolderEmail, pCardData.HolderMobilePhone, 
        pCardData.OwnerID, pCardData.StatusID, pCardData.CardState, pCardData.LastServiceDate, pCardData.FirstServiceDate, pCardData.PINBlock, pCardData.PINMethod, 
        pCardData.LockResult, pCardData.LimitsCount, pCardData.EventsCount, pCardData.PurseRestrictionsCount, pCardData.ActionsCount
   from Cards c, QuestTransactions qt, ActivationTransactions at, CardHolders ch
  where c.CardNumber = pCardNumber and c.CardNumber = qt.CardNumber(+) and c.CardNumber = at.CardNumber(+) and c.HolderID = ch.ID(+);

  -- Актуализируем параметры карты функцией
  opsOnline.GetCardActualParameters2(pCardNumber, pCardData.StatusID, pCardData.CardState, pCardData.LastServiceDate, pCardData.FirstServiceDate, 
    pCardData.PINBlock, pCardData.PINMethod);

  -- Загружаем счётчики карты
  open pCardCounters for 
    select nvl(c.CounterID, p.CounterID) ID, 
        c.CounterValue as CurrentValue, nvl(c.CounterDate, opsOnline.GetCounterDateByID(nvl(c.CounterID, p.CounterID), pTransactionDate, 0)) as CurrentDate, 
        p.CounterValue as PreviousValue, nvl(p.CounterDate, opsOnline.GetCounterDateByID(nvl(p.CounterID, c.CounterID), pCardData.LastServiceDate, 0)) as PreviousDate
    from
        (select * from RealCounterValuesView where CardNumber = pCardNumber and CounterDate = opsOnline.GetCounterDateByID(CounterID, pTransactionDate, 0)) c
        full outer join
        (select * from RealCounterValuesView where CardNumber = pCardNumber and CounterDate = opsOnline.GetCounterDateByID(CounterID, pCardData.LastServiceDate, 0)) p
        on c.counterid = p.counterid; 

  -- Загружаем счётчики карты в разрезе ТО
  open pCardCountersSP for 
    select nvl(c.CounterID, p.CounterID) ID, 
        c.CounterValue as CurrentValue, nvl(c.CounterDate, opsOnline.GetCounterDateByID(nvl(c.CounterID, p.CounterID), pTransactionDate, 0)) as CurrentDate, 
        p.CounterValue as PreviousValue, nvl(p.CounterDate, opsOnline.GetCounterDateByID(nvl(p.CounterID, c.CounterID), pCardData.LastServiceDate, 0)) as PreviousDate
    from
        (select * from RealCounterValuesSPView where CardNumber = pCardNumber and SPID = pServicePointID and CounterDate = opsOnline.GetCounterDateByID(CounterID, pTransactionDate, 0)) c
        full outer join
        (select * from RealCounterValuesSPView where CardNumber = pCardNumber and SPID = pServicePointID and CounterDate = opsOnline.GetCounterDateByID(CounterID, pCardData.LastServiceDate, 0)) p
        on c.counterid = p.counterid;
        
  -- Загружаем лимиты карты
  if pCardData.LimitsCount > 0 then
    open pCardLimits for 
      select cl.ID, cl.Limit, cl.Duration, cl.IsVisible, cl.Type, cl.PurseID, p.Name as PurseName, p.Type as PurseType 
        from CardLimits cl, Purses p 
       where cl.PurseID = p.ID and cl.CardNumber = pCardNumber 
      order by PurseType, PurseID, Duration;
  else
    pCardLimits := null;
  end if;        
  
  -- Загружаем события карты
  if pCardData.EventsCount > 0 then
    open pCardEvents for 
      select EventID from
      (
        select EventID, Sequence from ContractOwnerEvents where OwnerID = pCardData.OwnerID
        union 
        select EventID, Sequence from ContractEvents where ContractID = pCardData.ContractID
        union 
        select EventID, Sequence from CardEvents where CardNumber = pCardNumber 
      )
      group by EventID
      order by avg(Sequence);     
  else
    pCardEvents := null;
  end if;
  
  -- Загружаем ограничения на кошельки, установленные для карты, договора, владельца договора
  if pCardData.PurseRestrictionsCount > 0 then
    open pCardPurseRestrictions for 
      select 1 as Scope, PurseID, Sign from ContractPurseRestrictions where ContractID = pCardData.ContractID
      union all
      select 2 as Scope, PurseID, Sign from COwnerPurseRestrictions where OwnerID = pCardData.OwnerID
      union all
      select 3 as Scope, PurseID, Sign from CardPurseRestrictions where CardNumber = pCardNumber;      
  else 
    pCardPurseRestrictions := null;  
  end if;
  
  -- Загружаем акции, в которых участвует карта на момент транзакции
  if pCardData.ActionsCount > 0 then
    open pCardActions for
      select a.ID, a.CardScriptID, a.Code, a.NameForTerminal from PCCSActionCards ac, PCCSActions a 
       where a.ID = ac.PCCSActionID 
         and pTransactionDate between a.StartDate and a.EndDate 
         and pTransactionDate between ac.StartSubscriptionDate and ac.EndSubscriptionDate
         and ac.CardNumber = pCardNumber
         and pCardData.OwnerID in (select CardOwnerID from PCCSActionOwners z where z.PCCSActionID = a.ID)
         and a.CardScriptID = pCardScriptID;  
  else 
    pCardActions := null;  
  end if;
  
  -- Загружаем договор  
  pContractData := opsTypeContractData_v1();
  pContractData.ID := nvl(pContractID, pCardData.ContractID);
  
  if pContractData.ID is not null then
    select ClientID, ContractNumber, Name, ContractComment, DateStart, DateFinish, Type, State, CurrencyID, OwnerID, 
           opsOnlineRestrictions.CheckContract(c.ID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, Type, ClientID, OwnerID) ContractRestriction,
           opsOnlineRestrictions.CheckContractOwner(OwnerID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, c.ID, Type, ClientID) ContractOwnerRestriction,
           opsOnlineRestrictions.CheckNetworkOwner(pNetworkOwnerID, pTerminalID, pServicePointID, pRegionID, pNetworkID, c.ID, Type, ClientID, OwnerID) NetworkOwnerRestriction,
           (select count(1) from ContractTariffs z where z.ContractID = c.id) TariffsCount,
           (select count(1) from ContractLimits z where z.ContractID = c.id) LimitsCount,
           (select count(1) from ContractAccounts z where z.ContractID = c.id) AccountsCount,
           (select count(1) from OwnerAccounts z where z.OwnerID = c.OwnerID) OwnerAccountsCount
      into pContractData.ClientID, pContractData.ContractNumber, pContractData.Name, pContractData.ContractComment, pContractData.DateStart, pContractData.DateFinish, 
           pContractData.Type, pContractData.State, pContractData.CurrencyID, pContractData.OwnerID, pContractData.ContractRestriction, 
           pContractData.ContractOwnerRestriction, pContractData.NetworkOwnerRestriction, pContractData.TariffsCount, pContractData.LimitsCount, 
           pContractData.AccountsCount, pContractData.OwnerAccountsCount
      from Contracts c where c.id = pContractData.ID;
       
    -- Загружаем счётчики договора
    open pContractCounters for 
      select nvl(c.CounterID, p.CounterID) ID, 
          c.CounterValue as CurrentValue, nvl(c.CounterDate, opsOnline.GetCounterDateByID(nvl(c.CounterID, p.CounterID), pTransactionDate, 0)) as CurrentDate, 
          p.CounterValue as PreviousValue, nvl(p.CounterDate, opsOnline.GetCounterDateByID(nvl(p.CounterID, c.CounterID), pCardData.LastServiceDate, 0)) as PreviousDate
      from
          (select * from RealContractCounterValuesView where ContractID = pContractData.ID and CounterDate = opsOnline.GetCounterDateByID(CounterID, pTransactionDate, 0)) c
          full outer join
          (select * from RealContractCounterValuesView where ContractID = pContractData.ID and CounterDate = opsOnline.GetCounterDateByID(CounterID, pCardData.LastServiceDate, 0)) p
          on c.counterid = p.counterid;      
    
    -- Загружаем тарифы договора
    if pContractData.TariffsCount > 0 then
      open pContractTariffPeriods for
        select ct.TariffID, tp.ID PeriodID from ContractTariffs ct, TariffPeriods tp 
         where ct.ContractID = pContractData.ID and ct.TariffID = tp.TariffID
           and tp.ID = opsOnline.GetValidTariffPeriodID(ct.TariffID, pTransactionDate)
           and opsOnlineRestrictions.CheckTariffPeriod(tp.ID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractData.ID, pContractData.Type, pContractData.ClientID, pContractData.OwnerID) != 0 
         order by ct.Sequence;
    else
      pContractTariffPeriods := null;       
    end if;    
    
    -- Загружаем лимиты договора
    if pContractData.LimitsCount > 0 then
      open pContractLimits for
        select cl.ID, cl.Limit, cl.Duration, cl.PurseID, p.Name as PurseName, p.Type as PurseType 
          from ContractLimits cl, Purses p where cl.PurseID = p.ID and cl.ContractID = pContractData.ID 
        order by PurseType, PurseID, Duration;
    else     
      pContractLimits := null;
    end if;  
    
    -- Загружаем счета договора
    if pContractData.AccountsCount > 0 then 
      open pContractAccounts for
        select ca.ID, ca.CurrencyID, ca.Amount, ca.Overdraft, ca.MinimalAmount,
               (select nvl(sum(Amount), 0) from ContractAccountCredits z where ContractAccountID = ca.id and pTransactionDate between DateStart and DateFinish) AmountCredits,
               (select nvl(sum(z.AmountChange), 0) from ContractAccounts_PostBox z where z.ContractAccountID = ca.id) AmountFrozen,
               opsOnline.GetCrossRate(ca.CurrencyID, pTerminalCurrencyID, pCentralDate) as CrossRateToTerminal,
               opsOnline.GetCrossRate(pTerminalCurrencyID, ca.CurrencyID, pCentralDate) as CrossRateFromTerminal
          from ContractAccounts ca 
         where ca.ContractID in (select pContractData.ID from dual union all select FriendContractID from ContractFriends where ContractID = pContractData.ID);
    else 
      pContractAccounts := null;     
    end if;   
   
    -- Загружаем счета владельца договора
    if pContractData.OwnerAccountsCount > 0 then 
      open pOwnerAccounts for 
        select oa.ID, oa.CurrencyID, oa.Amount, oa.Overdraft, oa.MinimalAmount, oa.IsControlEnabled,
               (select nvl(sum(Amount), 0) from OwnerAccountCredits z where OwnerAccountID = oa.id and pTransactionDate between DateStart and DateFinish) AmountCredits,
               (select nvl(sum(z.AmountChange), 0) from OwnerAccounts_PostBox z where z.OwnerAccountID = oa.id) AmountFrozen,
               opsOnline.GetCrossRate(oa.CurrencyID, pTerminalCurrencyID, pCentralDate) as CrossRateToTerminal,
               opsOnline.GetCrossRate(pTerminalCurrencyID, oa.CurrencyID, pCentralDate) as CrossRateFromTerminal,
               opsOnlineRestrictions.CheckOwnerAccount(oa.ID, pTerminalID, pServicePointID, pRegionID, pNetworkID, pNetworkOwnerID, pContractData.ID, pContractData.Type, 
                                                       pContractData.ClientID, oa.OwnerID) AccountRestriction
          from OwnerAccounts oa where oa.OwnerID = pContractData.OwnerID;
    else 
      pOwnerAccounts := null;     
    end if;   
    
  end if;
  
end;

procedure PrepareTransaction_v1(pSource number, pPCOwnerID number, pTerminalDate date, pTransactionID out number, pIsClosed out number) is
begin
  pTransactionID := opsOnline.GetTransactionID(pSource, pPCOwnerID);
  pIsClosed := opsOnline.IsClosedDateTime(pTerminalDate);
end;   
   
end;
/