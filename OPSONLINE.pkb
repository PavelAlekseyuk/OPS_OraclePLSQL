CREATE OR REPLACE package body OPCL.opsOnline as 

procedure ExtractFromTransactionID(pID number, pSource out number, pPCOwnerID out number, pUniqueNumber out number) is
  IDLength constant integer := 27; -- длина идентификатора транзакции
  IDSourcePartLength constant integer := 1; -- длина части источника 
  IDOwnerPartLength constant integer := 6; -- длина части владельца 
  IDUniquePartLength constant integer := 20; -- длина уникальной части (внутри текущей инсталляции) идентификатора*/
begin
  if Length(pID) < IDLength then raise_application_error(-20001, 'Неверный размер идентификатора транзакции: '||Length(pID)||' ('||pID||')'); end if;
  pSource := to_number(substr(pID, 1, IDSourcePartLength));
  pPCOwnerID := to_number(substr(pID, IDSourcePartLength + 1, IDOwnerPartLength));
  pUniqueNumber := to_number(substr(pID, IDSourcePartLength + IDOwnerPartLength + 1, IDUniquePartLength));      
end;

function BuildTransactionID(pSource number, pPCOwnerID number, pUniqueNumber number) return number as
begin
  return to_number(to_char(pSource) || trim(to_char(pPCOwnerID, '000000')) || trim(to_char(pUniqueNumber, '00000000000000000000')));
end;

function GetTransactionID(pSource number default 1, pPCOwnerID number default null) return number as
  lPCOwnerID PC.OwnerID%type := pPCOwnerID;
begin
  if pSource <= 0 or pSource > 9 or pSource is null then raise_application_error(-20001, 'Передан неверный Source'); end if;
  if lPCOwnerID is null then
    begin
      select OwnerID into lPCOwnerID from PC where IsCurrentPC = 1;  
    exception
      when no_data_found then raise_application_error(-20001, 'В конфигурации системы не обнаружен текущий процессинговый центр'); 
      when too_many_rows then raise_application_error(-20001, 'В конфигурации системы обнаружены несколько текущих процессинговых центров'); 
      when others then raise_application_error(-20001, 'Неизвестная ошибка получения информации о ПЦ');
    end;   
  end if;
  --return to_number(to_char(pSource) || trim(to_char(lPCOwnerID, '000000')) || trim(to_char(TRANSACTION_SEQ.nextval, '00000000000000000000')));
  return BuildTransactionID(pSource, lPCOwnerID, Transaction_Seq.nextval);
end;

function CreateCard(pCardNumber number, pTerminalID number default null, pTerminalDateTime date default sysdate, pRegisterActivation number default 0, 
                    pContractID number default null, pTryAutoAcceptQuest number default 1) return number as
  pragma autonomous_transaction;
  lContractStartDate Contracts.DateStart%type := nvl(pTerminalDateTime, sysdate);  
  lActivationDate date := nvl(pTerminalDateTime, sysdate);
  lQuestDate date := nvl(pTerminalDateTime, sysdate);
  lClientID number;
  lContractID Contracts.ID%type := pContractID;  
  lPINBlock Cards.PINBlock%type := null;
  lPINMethod Cards.PINMethod%type := null;   
  lLockHandle varchar2(128);
  lLockResult integer;
  lRange CardRanges%rowtype;
  lContractOwnerID Contracts.OwnerID%type;  
begin  
  dbms_lock.allocate_unique(to_char(pCardNumber), lLockHandle, 60); -- запрашиваем ID блокировки на 60 секунд
  lLockResult := dbms_lock.request(lLockHandle, dbms_lock.x_mode, 0, TRUE); -- запрашиваем эксклюзивную блокировку
  if lLockResult != 0 then raise_application_error(-20001, 'Ошибка блокировки '||lLockResult||' при создании карты '||pCardNumber||' в системе'); end if;  
   
  select cr.* into lRange from CardRanges cr where ID = GetCardRangeID(pCardNumber); -- получаем данные по диапазону, которому принадлежит карта
 
  if lRange.CheckLuhn != 0 and IsCorrectLuhn(pCardNumber) <> 1 then raise_application_error(-20001, 'Неверный код Люна'); end if; -- если требуется, проверяем корректность luhn кода 

  if pTerminalID is not null then
     if opsOnlineRestrictions.CheckCardRange(lRange.ID, pTerminalID, null, null, null, null, /*c.ContractID*/null, null, null, null) = 0 then
       raise_application_error(-20001, 'Использование диапазона, которому принадлежит карта '||pCardNumber||', запрещено в данном окружении'); 
     end if;  
  end if;
  
  -- если требуется, генерируем PIN-код карты
  if lRange.PINRequired != 0 then
    opsCrypto.InitializePINKey(lRange.PCID);
    lPINMethod := opsCrypto.PINBlockMethodISO9564;
    lPINBlock := opsCrypto.GeneratePINBlockEx(pCardNumber, lPINMethod, 4);
  end if;

  if lContractID is null and lRange.AutoContract = 1 then -- если договор не передан и нам нужно создать договор, создаём нового клиента с одним договором 
    -- создаём клиента
    if lRange.ContractType = 1 then -- физик
      insert into LoyaltyClients (ID, OwnerID) values (NULL, lRange.ContractOwnerID) returning ID into lClientID;
    elsif lRange.ContractType = 2 then -- юрик
      insert into CorporateClients (ID, OwnerID) values (NULL, lRange.ContractOwnerID) returning ID into lClientID;
    else
      raise_application_error(-20001, 'Неизвестный ContractType: '||lRange.ContractType);  
    end if;

    -- валюта или терминал должны быть заполнены
    /*if lCurrencyID is null and pTerminalID is null then raise_application_error(-20001, 'Валюта или терминал должны быть переданы для создания договора'); end if;
  
    if pTerminalID is not null and lCurrencyID is null then -- находим валюту терминала, если валюта карты не передана
      begin
        select CurrencyID into lCurrencyID from Regions where ID in (select RegionID from ServicePoints where id in (select SPID from Terminals where ID = pTerminalID));
      exception
        when no_data_found then raise_application_error(-20001, 'Передан неверный ID терминала'); -- неверный терминал 
      end;  
    end if;*/

    -- создаём договор
    insert into Contracts (ClientID, CurrencyID, Name, DateStart, DateFinish, Type, State, OwnerID) 
      values (lClientID, lRange.ContractCurrencyID, 'Автоматически созданный договор', lContractStartDate, lContractStartDate + lRange.ContractDurationDays, lRange.ContractType, 
              lRange.ContractState, lRange.ContractOwnerID)
    returning ID into lContractID;
    
    -- создаём счёт договора с нулевыми балансами в валюте региона
    if lRange.AutoContractAccount = 1 then  
      insert into ContractAccounts (ContractID, CurrencyID) values (lContractID, lRange.ContractAccountCurrencyID);
    end if;  
  end if;
  
  if lContractID is not null then 
    -- проверяем соответствие владельца контракта и диапазона карт
    begin
      select OwnerID into lContractOwnerID from Contracts where ID = lContractID;
      if lContractOwnerID != lRange.ContractOwnerID then 
        raise_application_error(-20001, 'Владелец диапазона карт ('||lContractOwnerID||') не совпадает с владельцем договора ('||lRange.ContractOwnerID||')');
      end if; 
    exception when no_data_found then raise_application_error(-20001, 'Контракт ID='||lContractID||' не найден');
    end;
    
    -- добавляем тарифы контракта по умолчанию в список тарифов, кроме тех тарифов, которые были добавлены ранее
    insert into ContractTariffs (ContractID, TariffID, Sequence) 
      select lContractID, TariffID, Sequence from CardRangeContractTariffs ct where CardRangeID = lRange.ID 
        and ct.TariffID not in (select z.TariffID from ContractTariffs z where z.ContractID = lContractID);
      
    -- добавляем события контракта по умолчанию в список событий, кроме тех событий, которые были добавлены ранее
    insert into ContractEvents (ContractID, EventID, Sequence) 
      select lContractID, EventID, Sequence from CardRangeContractEvents ce where CardRangeID = lRange.ID      
        and ce.EventID not in (select z.EventID from ContractEvents z where z.ContractID = lContractID);
  end if;
  
  -- создаём карту в таблице Cards
  begin
    insert into Cards (CardNumber, CardState, CardType, StatusID, FirstServiceDate, LastServiceDate, ContractID, PINBlock, PINMethod, RangeID, DefaultDiscount) 
      values (pCardNumber, lRange.CardState, lRange.CardType, lRange.CardStatusID, null, pTerminalDateTime, lContractID, lPINBlock, lPINMethod, lRange.ID, lRange.OfflineDefaultDiscount);
  exception when dup_val_on_index then 
    raise_application_error(-20001, 'Карта '||pCardNumber||' уже создана в системе');   
  end;    
  
  -- добавляем события карты по умолчанию в список событий
  insert into CardEvents (CardNumber, EventID, Sequence) 
    select pCardNumber, EventID, Sequence from CardRangeCardEvents where CardRangeID = lRange.ID;      
  
  -- регистрируем транзакцию активации карты
  if nvl(pRegisterActivation, 0) > 0 and pTerminalID is not null then
    begin                                                       
      RegisterActivationTransaction(pCardNumber, pTerminalID, lActivationDate);
    exception
      when others then raise_application_error(-20001, 'Ошибка при регистрации транзакции активации');         
    end;  
  end if;
 
  if pTryAutoAcceptQuest > 0 and lRange.QuestAccepted > 0 and pTerminalID is not null then
    begin
      RegisterQuestTransaction(pCardNumber, pTerminalID, lQuestDate, null); 
    exception
      when others then null;  
    end;    
  end if;

  commit;        
  return 1;    
end;

-- создаёт счётчик в справочнике счётчиков в автономной транзакции и возвращает его id
function CreateCardCounter(pName varchar2, pDescription varchar2, pType number, pSubType number, pPeriod number) return number as 
  pragma autonomous_transaction;
  lID Counters.ID%type; 
  lName Counters.Name%type := upper(pName); 
begin
  begin   
    insert into Counters (Name, Description, Type, SubType, Period) values (lName, pDescription, pType, pSubType, pPeriod) returning ID into lID;
    commit;
  exception
    when dup_val_on_index then -- если счетчик с таким именем уже создан - возвращаем его ID
      select ID into lID from Counters where Name = lName;  
  end;
  return lID;    
end;

function GetArticleID(pGoodsCode varchar2, pGoodsName varchar2, pRetailSystemID number) return number as
  lNetwordOwnerID Goods.OwnerID%type; 
begin
  select GlobalOwnerID into lNetwordOwnerID from RetailSystems where ID = pRetailSystemID;
  return GetArticleID2(pGoodsCode, pGoodsName, pRetailSystemID, lNetwordOwnerID); 
end;

function GetArticleID2(pGoodsCode varchar2, pGoodsName varchar2, pRetailSystemID number, pNetwordOwnerID number) return number as
  lID Goods.ID%type; 
begin
  if pGoodsCode is null then raise_application_error(-20001, 'Код товара не может быть null'); end if;
  if pRetailSystemID is null then raise_application_error(-20001, 'ID системы управления не может быть null'); end if;
  if pNetwordOwnerID is null then raise_application_error(-20001, 'ID владельца системы управления не может быть null'); end if;
  
  begin
    select ID into lID from Goods where GoodsCode = pGoodsCode and RSID = pRetailSystemID;
  exception
    when no_data_found then 
      insert into Goods (goodscode, goodsname, rsid, ownerid) values (pGoodsCode, pGoodsName, pRetailSystemID, pNetwordOwnerID) returning id into lID;
  end;  
  
  return lID; 
end;

function GetCounterDate(pCounterPeriod number, pTransactionDate date, pPeriodsAgo number default 0) return date deterministic as
  lResult date := null;
  lDate date := pTransactionDate;
  lMonday varchar2(255) default to_char(to_date('20011231', 'yyyymmdd'), 'day');
  i number;
begin
  for i in 0..pPeriodsAgo loop
    if pCounterPeriod = 0 then -- forever
      lResult:=to_date('01.01.0001', 'dd.mm.yyyy');
      exit;
    elsif pCounterPeriod = 1 then -- decade
      raise_application_error(-20001, 'Decade calculation is not implemented now');
    elsif pCounterPeriod = 2 then -- day
      lResult:=trunc(lDate);
      lDate:=lResult-1;
    elsif pCounterPeriod = 3 then -- week
      lResult:=next_day(trunc(lDate) + -7, lMonday); 
      lDate:=lResult-1;
    elsif pCounterPeriod = 4 then -- month
      lResult:=trunc(lDate, 'month');
      lDate:=lResult-1;
    elsif pCounterPeriod = 5 then -- year
      lResult:=trunc(lDate, 'year');
      lDate:=lResult-1;
    elsif pCounterPeriod = 6 then -- quarter
      lResult:=trunc(lDate, 'q');
      lDate:=lResult-1;
    else
      raise_application_error(-20001, 'CounterPeriod = '||pCounterPeriod||' is not supported in GetCounterDate()'); 
    end if;
  end loop;
 return lResult;
end;

function GetCounterDateByID(pCounterID number, pTransactionDate date, pPeriodsAgo number default 0) return date deterministic as
  lCounterPeriod Counters.Period%type;
begin
  select Period into lCounterPeriod from Counters where ID = pCounterID;
  return GetCounterDate(lCounterPeriod, pTransactionDate, pPeriodsAgo);
exception
  when no_data_found then raise_application_error(-20001, 'Counter ID = '||pCounterID||' not founded in Counters dictionary');   
end; 

function GetMeasureUnitID(pMeasureUnitName varchar2) return number as
  lID MeasureUnits.ID%type := null; 
begin
  if trim(pMeasureUnitName) is not null then 
    begin
      select ID into lID from MeasureUnits where Name = pMeasureUnitName;
    exception
      when no_data_found then 
        insert into MeasureUnits (name) values (pMeasureUnitName) returning id into lID;
    end;  
  end if;
  
  return lID; 
end;

function IsCorrectLuhn(pCardNumber number) return number as
 lCardNumber varchar2(20) := to_char(pCardNumber);
 Len number(4) := length(lCardNumber);
 i number(4);
 s number(6) := 0;
 n number(2);
begin
 for i in 1..Len loop
   n := to_number(substr(lCardNumber, Len-i+1, 1));
   if mod(i-1, 2) <> 0 then n := n*2; end if;
   if n >= 10 then n := trunc(n/10) + mod(n, 10); end if;
   s := s + n;    
 end loop;
 if mod(s, 10) = 0 then return 1; else return 0; end if;
end;

function CancelTransaction(pOriginalID number, pCancelID number default null, pNeedLockCard number default 0, pRSDateTime date default null, 
                           pSerialNumber varchar2 default null, pCancelSource number default null) return number as
begin
  return CancelTransaction2(pOriginalID, pCancelID, pNeedLockCard, pRSDateTime, pSerialNumber, pCancelSource, null, null);
end;                           

function CancelTransaction2(pOriginalID number, pCancelID number, pNeedLockCard number, pRSDateTime date, pSerialNumber varchar2, pCancelSource number, 
                            pSignature raw, pAppSign number) return number as
  lCancelID Transactions.ID%type;  
  lTransaction Transactions%rowtype;
  lCancelDateTime Transactions.TerminalDateTime%type;
  lCancelSource Transactions.Source%type;
  lFlag number := 0; 
  lLockResult integer := 0;
  lLockID Cards.LockID%type;
  lServicePointID ServicePoints.ID%type;
  lReasonText varchar2(100);
  lCurrentPCID PC.ID%type;
  lDummy number;
  lHandlerPCOwnerID Transactions.HandlerPCOwnerID%type;
  lIDUniquePart Transactions.IDUniquePart%type;
begin
  begin -- получаем текущий ПЦ. Нельзя использовать функции из других пакетов
    select ID into lCurrentPCID from PC where IsCurrentPC = 1;  
  exception
    when no_data_found then raise_application_error(-20001, 'В конфигурации системы не обнаружен текущий процессинговый центр'); 
    when too_many_rows then raise_application_error(-20001, 'В конфигурации системы обнаружены несколько текущих процессинговых центров'); 
    when others then raise_application_error(-20001, 'Неизвестная ошибка получения информации о ПЦ');
  end;   

  -- проверка: если по транзакции уже был возврат, то дальнейшие действия не проводим
  select count(1) into lFlag from TransactionCancellation where TransactionID = pOriginalID;
  if lFlag != 0 then raise_application_error(-20001, 'Транзакция '||pOriginalID||' была отменена ранее'); end if;

  -- получаем данные по транзакции
  begin
    select * into lTransaction from Transactions where ID = pOriginalID and TransactionType = 0;
  exception
    when no_data_found then raise_application_error(-20001, 'Транзакция оплаты '||pOriginalID||' не найдена');
  end;

  -- транзакция должна принадлежать текущему ПЦ. УБРАНО 01/08/2013 т.к. транзитные транзакции отменяются так же 
  --if lTransaction.HandlerPCID != lCurrentPCID then raise_application_error(-20001, 'Транзакция '||pOriginalID||' обработана чужим ПЦ ID = '||lTransaction.HandlerPCID); end if;  

  -- транзакция должна быть открытой для отмены
  if lTransaction.AccountingPeriodID is not null then raise_application_error(-20001, 'Транзакция '||pOriginalID||' закрыта для изменений'); end if;
      
  -- Отменено. См. ниже!!! проверяем дату и время транзакции отмены: если не передана (null), то берём её из транзакции оплаты + 1 секунда
  --lCancelDateTime := nvl(lTerminalDateTime, lTransaction.TerminalDateTime + 1/(60*60*24));

  -- Дата и время отмены ДОЛЖНЫ СОВПАДАТЬ с датой/временем оригинальной транзакции для корректной обработки счётчиков (чтобы были отменены счётчики именно нужных периодов)
  lCancelDateTime := lTransaction.TerminalDateTime;
  
  -- генерируем ID транзакции отмены
  lCancelSource := nvl(pCancelSource, lTransaction.Source);
  if pCancelID is not null then lCancelID := pCancelID; else lCancelID := GetTransactionID(lCancelSource); end if;  
  opsOnline.ExtractFromTransactionID(lCancelID, lDummy, lHandlerPCOwnerID, lIDUniquePart);
  lReasonText := 'Cancellation #'||lCancelID;

  -- Transactions: сразу записываем транзакцию отмены
  insert into Transactions (ID, TerminalDateTime, RSDateTime, TransactionType, TerminalID, CardNumber, ContractID, Status, OriginalID, OriginalDateTime, 
                            CardStatus, Source, Discount, DiscountInitial, SerialNumber, ParamSetPeriodID, 
                            FiscalFlags, FiscalFlagsInitial, CentralDateTime, PCDateTime, Flags, FlagsInitial, 
                            SenderPCID, HandlerPCID, CardType, TransitType, CrossCardToTerminal, CrossTerminalToCard, 
                            CardScriptID, BehaviorFlags, CardLastServiceDate, SelectedBehaviourID, CardReadingMethod, ShiftAuthID, 
                            HandlerPCOwnerID, IDUniquePart, Signature, ApplicationSign)
    values (lCancelID, lCancelDateTime, pRSDateTime, 1, lTransaction.TerminalID, lTransaction.CardNumber, lTransaction.ContractID, lTransaction.Status, lTransaction.ID, lTransaction.TerminalDateTime,
            lTransaction.CardStatus, lCancelSource, -lTransaction.Discount, -lTransaction.DiscountInitial, nvl(pSerialNumber, lTransaction.SerialNumber), lTransaction.ParamSetPeriodID,
            lTransaction.FiscalFlags, lTransaction.FiscalFlagsInitial, lTransaction.CentralDateTime, sysdate, lTransaction.Flags, lTransaction.FlagsInitial,            
            lTransaction.SenderPCID, lTransaction.HandlerPCID, lTransaction.CardType, lTransaction.TransitType, lTransaction.CrossCardToTerminal, lTransaction.CrossTerminalToCard, 
            lTransaction.CardScriptID, lTransaction.BehaviorFlags, lTransaction.CardLastServiceDate, lTransaction.SelectedBehaviourID, lTransaction.CardReadingMethod, 
            lTransaction.ShiftAuthID, lHandlerPCOwnerID, lIDUniquePart, pSignature, pAppSign);
                            
  -- TransactionReceipts: записываем чек транзакции отмены      
  insert into TransactionReceipts (TransactionID, TerminalDateTime, Position, GoodsID, PaymentType, PriceWithoutDiscount, Price, Quantity, QuantityInitial, AmountWithoutDiscount, Amount, Bonuses, DiscountForPrice, DiscountForPriceInitial, AmountWithoutDiscountRounded, AmountRounded, BonusesRounded, DiscountForAmount, DiscountForAmountInitial, MeasureUnitID, QuantityPrecision, Flags, FlagsInitial, PriceWithoutDiscountInitial) 
    select lCancelID, lCancelDateTime, Position, GoodsID, PaymentType, PriceWithoutDiscount, Price, -Quantity, -QuantityInitial, -AmountWithoutDiscount, -Amount, -Bonuses, DiscountForPrice, DiscountForPriceInitial, -AmountWithoutDiscountRounded, -AmountRounded, -BonusesRounded, -DiscountForAmount, -DiscountForAmountInitial, MeasureUnitID, QuantityPrecision, Flags, FlagsInitial, PriceWithoutDiscountInitial from TransactionReceipts 
      where TransactionID = pOriginalID and TerminalDateTime = lTransaction.TerminalDateTime;  

  -- TransactionPayments: записываем отменяющие платежи по транзакции    
  insert into TransactionPayments (TransactionID, TerminalDateTime, ByCash, ByBankingCard, ByBonuses, ByCredit, ByPrepaidAccount, PaymentTypeForDiscount) 
    select lCancelID, lCancelDateTime, -ByCash, -ByBankingCard, -ByBonuses, -ByCredit, -ByPrepaidAccount, PaymentTypeForDiscount from TransactionPayments 
      where TransactionID = pOriginalID and TerminalDateTime = lTransaction.TerminalDateTime;  

  if pNeedLockCard != 0 then 
    -- выбираем ID блокировки по карте (не проверяем на существование карты - этим занимаются форейны)  
    select LockID into lLockID from Cards where CardNumber = lTransaction.CardNumber;
    lLockResult := dbms_lock.request(id => lLockID, lockmode => dbms_lock.x_mode, timeout => 5, release_on_commit => TRUE); -- немножко ждём окончания обработки карты, если есть конкуренты
    if lLockResult != 0 then raise_application_error(-20001, 'Ошибка "'||lLockResult||'" блокировки карты "'||lTransaction.CardNumber||'"'); end if;
  end if;  

  -- TransactionCounters && CardCounters: записываем изменения по счётчикам карты
  for Rec in (select tc.*, GetCounterDateByID(tc.CounterID, lCancelDateTime, 0) CancelCounterDate 
                from TransactionCounters tc 
               where TransactionID = pOriginalID and TerminalDateTime = lTransaction.TerminalDateTime) loop
    -- инвертируем запись в таблице TransactionCounters
    insert into TransactionCounters (TransactionID, TerminalDateTime, CounterID, CounterInitial, CounterChange, CounterValue, CounterDate, PreviousValue, PreviousDate)
      values (lCancelID, lCancelDateTime, Rec.CounterID, Rec.CounterValue /*initial*/, -Rec.CounterChange/*change*/, Rec.CounterInitial/*final value*/, Rec.CancelCounterDate, Rec.PreviousValue, Rec.PreviousDate);    
    
    -- вставляем записи для обновления таблицы CounterValues
    insert into CounterValues_PostBox (CardNumber, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText) 
      values (lTransaction.CardNumber, Rec.CounterID, Rec.CancelCounterDate, -Rec.CounterChange, 1, lReasonText); 
  end loop;  

  -- получаем идентификатор ТО (не нужно обрабатывать эксепшены - этим занимаются форейны)
  select SPID into lServicePointID from Terminals where ID = lTransaction.TerminalID; 

  -- TransactionCountersSP && CardCountersSP: записываем изменения по счётчикам карты в разрезе ТО
  for Rec in (select tc.*, GetCounterDateByID(tc.CounterID, lCancelDateTime, 0) CancelCounterDate 
                from TransactionCountersSP tc 
               where TransactionID = pOriginalID and TerminalDateTime = lTransaction.TerminalDateTime) loop
    -- инвертируем запись в таблице TransactionCounters
    insert into TransactionCountersSP (TransactionID, TerminalDateTime, CounterID, SPID, CounterInitial, CounterChange, CounterValue, CounterDate, PreviousValue, PreviousDate)
      values (lCancelID, lCancelDateTime, Rec.CounterID, lServicePointID, Rec.CounterValue /*initial*/, -Rec.CounterChange/*change*/, Rec.CounterInitial/*final value*/, Rec.CancelCounterDate, Rec.PreviousValue, Rec.PreviousDate);    
    
    -- вставляем записи для обновления таблицы CounterValuesSP 
    insert into CounterValuesSP_PostBox (CardNumber, SPID, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText) 
      values (lTransaction.CardNumber, lServicePointID, Rec.CounterID, Rec.CancelCounterDate, -Rec.CounterChange, 1, lReasonText);      
  end loop;  

  if pNeedLockCard != 0 then
    lLockResult := dbms_lock.release(id => lLockID);
    if lLockResult != 0 then raise_application_error(-20001, 'Ошибка "'||lLockResult||'" снятия блокировки карты "'||lTransaction.CardNumber||'"'); end if;
  end if; 
 
  -- TransactionActions не заполняется для транзакции отмены

  -- TransactionContractAccounts: корректируем счета договора, изменённые во время транзакции оплаты
  for Rec in (select * from TransactionContractAccounts where TransactionID = pOriginalID and TerminalDateTime = lTransaction.TerminalDateTime) loop
    -- инвертируем запись в таблице TransactionContractAccounts
    insert into TransactionContractAccounts (TransactionID, TerminalDateTime, ContractAccountID, AmountInitial, AmountChange, AmountValue, CrossTerminalToAccount, CrossAccountToTerminal)
      values (lCancelID, lCancelDateTime, Rec.ContractAccountID, Rec.AmountValue, -Rec.AmountChange, Rec.AmountInitial, Rec.CrossTerminalToAccount, Rec.CrossAccountToTerminal);    
    
    -- вставляем записи таблицу ContractAccounts_PostBox для последующей обработки 
    insert into ContractAccounts_PostBox (ContractAccountID, ChangeDate, AmountChange, ReasonID, ReasonText) 
      values (Rec.ContractAccountID, lCancelDateTime, -Rec.AmountChange, 1, lReasonText);
  end loop;  

  -- TransactionContractCounters && ContractCounters: записываем изменения по счётчикам договора
  for Rec in (select tc.*, GetCounterDateByID(tc.CounterID, lCancelDateTime, 0) CancelCounterDate 
                from TransactionContractCounters tc 
               where TransactionID = pOriginalID and TerminalDateTime = lTransaction.TerminalDateTime) loop
    -- инвертируем запись в таблице TransactionContractCounters
    insert into TransactionContractCounters (TransactionID, TerminalDateTime, CounterID, CounterInitial, CounterChange, CounterValue, CounterDate, PreviousValue, PreviousDate)
      values (lCancelID, lCancelDateTime, Rec.CounterID, Rec.CounterValue /*initial*/, -Rec.CounterChange/*change*/, Rec.CounterInitial/*final value*/, Rec.CancelCounterDate, Rec.PreviousValue, Rec.PreviousDate);    
    
    -- вставляем записи для обновления таблицы ContractCounterValues
    insert into ContractCounterValues_PostBox (ContractID, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText) 
      values (lTransaction.ContractID, Rec.CounterID, Rec.CancelCounterDate, -Rec.CounterChange, 1, lReasonText); 
  end loop;  

  -- TransactionOwnerAccounts: корректируем счета владельца, изменённые во время транзакции оплаты
  for Rec in (select * from TransactionOwnerAccounts where TransactionID = pOriginalID and TerminalDateTime = lTransaction.TerminalDateTime) loop
    -- инвертируем запись в таблице TransactionOwnerAccounts
    insert into TransactionOwnerAccounts (TransactionID, TerminalDateTime, OwnerAccountID, AmountInitial, AmountChange, AmountValue, CrossTerminalToAccount, CrossAccountToTerminal)
      values (lCancelID, lCancelDateTime, Rec.OwnerAccountID, Rec.AmountValue, -Rec.AmountChange, Rec.AmountInitial, Rec.CrossTerminalToAccount, Rec.CrossAccountToTerminal);    
    
    -- вставляем записи таблицу OwnerAccounts_PostBox для последующей обработки 
    insert into OwnerAccounts_PostBox (OwnerAccountID, ChangeDate, AmountChange, ReasonID, ReasonText) 
      values (Rec.OwnerAccountID, lCancelDateTime, -Rec.AmountChange, 1, lReasonText);
  end loop;  
  
  return lCancelID; 
end;

procedure RegisterQuestTransaction(pCardNumber number, pTerminalID number, pDateTime date, pDeadLineTime date, pID number default null) is 
begin 
  insert into QuestTransactions (ID, TERMINALDATETIME, CARDNUMBER, TERMINALID, DEADLINETIME)
    values (nvl(pID, GetTransactionID), pDateTime, pCardNumber, pTerminalID, pDeadLineTime);
exception
  when dup_val_on_index then raise_application_error(-20001, 'Анкета была принята ранее');    
end;

procedure RegisterQuestTransactionA(pCardNumber number, pTerminalID number, pDateTime date, pDeadLineTime date, pID number default null) is
  pragma autonomous_transaction;
begin
  RegisterQuestTransaction(pCardNumber, pTerminalID, pDateTime, pDeadLineTime, pID); 
  commit; -- коммитим результат
end;

procedure RegisterCardTransaction(pCardNumber number, pTerminalID number, pDateTime date, pTransactionType number, pOldNData number default null, pNewNData number default null, pOldVCData varchar2 default null, pNewVCData varchar2 default null) is 
 begin 
   insert into CardTransactions (ID, PCDATETIME, CARDNUMBER, TRANSACTIONTYPE, TERMINALID, OLDNUMBERDATA, NEWNUMBERDATA, OLDVARCHARDATA, NEWVARCHARDATA)
     values (GetTransactionID, pDateTime, pCardNumber, pTransactionType, pTerminalID, pOldNData, pNewNData, pOldVCData, pNewVCData);
 end;

procedure RegisterActivationTransaction(pCardNumber number, pTerminalID number, pDateTime date) is 
begin 
  insert into ActivationTransactions (ID, TERMINALDATETIME, CARDNUMBER, TERMINALID)
    values (GetTransactionID, pDateTime, pCardNumber, pTerminalID);
exception
  when dup_val_on_index then null; -- маскируем ошибки unique индекса
end;

procedure ProcessCardsPostbox is
  lCardRowID rowid;
begin
  for Rec in (select * from Cards_PostBox order by id) loop
    begin  
      select rowid into lCardRowID from Cards where CardNumber = Rec.CardNumber for update nowait; -- блокируем строку. Если она уже кем-то заблокирована - не ждём, а вылетаем с эксепшеном
      
      if Rec.UpdateFlags != 0 then
        if bitand(Rec.UpdateFlags, 1) != 0 then update Cards set StatusID = Rec.StatusID where CardNumber = Rec.CardNumber; end if;   
        if bitand(Rec.UpdateFlags, 2) != 0 then update Cards set LastServiceDate = Rec.LastServiceDate where CardNumber = Rec.CardNumber; end if;   
        if bitand(Rec.UpdateFlags, 4) != 0 then update Cards set FirstServiceDate = Rec.FirstServiceDate where CardNumber = Rec.CardNumber; end if;   
        if bitand(Rec.UpdateFlags, 8) != 0 then update Cards set CardState = Rec.CardState where CardNumber = Rec.CardNumber; end if;   
        if bitand(Rec.UpdateFlags, 16) != 0 then update Cards set PINBlock = Rec.PINBlock, PINMethod = Rec.PINMethod where CardNumber = Rec.CardNumber; end if;
      end if;
      delete from Cards_PostBox where ID = Rec.ID;
      commit;
    exception
      when others then Log(substr('CardsPostbox error while processing ID='||Rec.ID||': '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки
    end;  
  end loop;
  commit;         
end;

procedure ProcessContractAccountsPostbox is
  lrowid rowid;
begin
  for Rec in (select c.rowid, c.* from ContractAccounts_PostBox c order by id) loop
    begin  
      select rowid into lrowid from ContractAccounts where ID = Rec.ContractAccountID for update nowait; -- блокируем строку. Если она уже кем-то заблокирована - не ждём, а вылетаем с эксепшеном
      update ContractAccounts set Amount = Amount + Rec.AmountChange where rowid = lrowid; -- обновляем заблокированную строку
      insert into ContractAccounts_Changes (contractaccountid, changedate, amountchange, reasonid, reasontext) 
        values (Rec.ContractAccountID, Rec.ChangeDate, Rec.AmountChange, Rec.ReasonID, Rec.ReasonText); -- вставляем запись в историю изменений
      delete from ContractAccounts_PostBox where rowid = Rec.rowid; -- удаляем обработанную запись из почтового ящика
      commit; -- коммитим изменения и снимаем блокировки          
    exception
      when others then Log(substr('ContractAccountsPostbox '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки
    end;  
  end loop;
  commit;         
end;

procedure ProcessOwnerAccountsPostbox is
  lrowid rowid;
begin
  for Rec in (select c.rowid, c.* from OwnerAccounts_PostBox c order by id) loop
    begin  
      select rowid into lrowid from OwnerAccounts where ID = Rec.OwnerAccountID for update nowait; -- блокируем строку. Если она уже кем-то заблокирована - не ждём, а вылетаем с эксепшеном
      update OwnerAccounts set Amount = Amount + Rec.AmountChange where rowid = lrowid; -- обновляем заблокированную строку
      insert into OwnerAccounts_Changes (owneraccountid, changedate, amountchange, reasonid, reasontext) 
        values (Rec.OwnerAccountID, Rec.ChangeDate, Rec.AmountChange, Rec.ReasonID, Rec.ReasonText); -- вставляем запись в историю изменений
      delete from OwnerAccounts_PostBox where rowid = Rec.rowid; -- удаляем обработанную запись из почтового ящика
      commit; -- коммитим изменения и снимаем блокировки          
    exception
      when others then Log(substr('OwnerAccountsPostbox '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки
    end;  
  end loop;
  commit;         
end;

procedure ProcessCounterValuesPostbox is
  lRowID rowid;
begin
  for Rec in (select c.rowid, c.* from CounterValues_Postbox c order by id) loop
    begin  
      begin
        -- блокируем строку. Если она уже кем-то заблокирована - не ждём, а вылетаем с эксепшеном, а если её нет, то вставляем запись в таблицу        
        select rowid into lRowID from CounterValues where CardNumber = Rec.CardNumber and CounterID = Rec.CounterID and CounterDate = Rec.CounterDate for update nowait;
        update CounterValues set CounterValue = CounterValue + Rec.ChangeValue where rowid = lRowID; -- обновляем заблокированную строку
      exception
        when no_data_found then        
          insert into CounterValues (CardNumber, CounterID, CounterDate, CounterValue) 
            values (Rec.CardNumber, Rec.CounterID, Rec.CounterDate, (select nvl(z.DefaultValue, 0) from Counters z where z.ID = Rec.CounterID) + Rec.ChangeValue); 
      end;
      insert into CounterValues_Changes (CardNumber, CounterID, CounterDate, ChangeValue, ChangeDate, ReasonID, ReasonText)
        values (Rec.CardNumber, Rec.CounterID, Rec.CounterDate, Rec.ChangeValue, Rec.ChangeDate, Rec.ReasonID, Rec.ReasonText); -- вставляем запись в историю изменений
      delete from CounterValues_Postbox where rowid = Rec.rowid; -- удаляем обработанную запись из почтового ящика
      commit; -- коммитим изменения и снимаем блокировки          
    exception
      when others then Log(substr('CounterValuesPostbox '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки
    end;  
  end loop;
  commit;         
end;

procedure ProcessCounterValuesSPPostbox is
  lRowID rowid;
begin
  for Rec in (select c.rowid, c.* from CounterValuesSP_Postbox c order by id) loop
    begin  
      begin
        -- блокируем строку. Если она уже кем-то заблокирована - не ждём, а вылетаем с эксепшеном, а если её нет, то вставляем запись в таблицу        
        select rowid into lRowID from CounterValuesSP where CardNumber = Rec.CardNumber and SPID = Rec.SPID and CounterID = Rec.CounterID and CounterDate = Rec.CounterDate for update nowait;
        update CounterValuesSP set CounterValue = CounterValue + Rec.ChangeValue where rowid = lRowID; -- обновляем заблокированную строку
      exception
        when no_data_found then
          insert into CounterValuesSP (CardNumber, SPID, CounterID, CounterDate, CounterValue) 
            values (Rec.CardNumber, Rec.SPID, Rec.CounterID, Rec.CounterDate, (select nvl(z.DefaultValue, 0) from Counters z where z.ID = Rec.CounterID) + Rec.ChangeValue); 
      end;
      insert into CounterValuesSP_Changes (CardNumber, SPID, CounterID, CounterDate, ChangeValue, ChangeDate, ReasonID, ReasonText)
        values (Rec.CardNumber, Rec.SPID, Rec.CounterID, Rec.CounterDate, Rec.ChangeValue, Rec.ChangeDate, Rec.ReasonID, Rec.ReasonText); -- вставляем запись в историю изменений
      delete from CounterValuesSP_Postbox where rowid = Rec.rowid; -- удаляем обработанную запись из почтового ящика
      commit; -- коммитим изменения и снимаем блокировки          
    exception
      when others then Log(substr('CounterValuesSPPostbox '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки
    end;  
  end loop;
  commit;         
end;

procedure ProcessContractCounterValuesPb is
  lRowID rowid;
begin
  for Rec in (select c.rowid, c.* from ContractCounterValues_Postbox c order by id) loop
    begin  
      begin
        -- блокируем строку. Если она уже кем-то заблокирована - не ждём, а вылетаем с эксепшеном, а если её нет, то вставляем запись в таблицу        
        select rowid into lRowID from ContractCounterValues where ContractID = Rec.ContractID and CounterID = Rec.CounterID and CounterDate = Rec.CounterDate for update nowait;
        update ContractCounterValues set CounterValue = CounterValue + Rec.ChangeValue where rowid = lRowID; -- обновляем заблокированную строку
      exception
        when no_data_found then        
          insert into ContractCounterValues (ContractID, CounterID, CounterDate, CounterValue) 
            values (Rec.ContractID, Rec.CounterID, Rec.CounterDate, (select nvl(z.DefaultValue, 0) from Counters z where z.ID = Rec.CounterID) + Rec.ChangeValue); 
      end;
      insert into ContractCounterValues_Changes (ContractID, CounterID, CounterDate, ChangeValue, ChangeDate, ReasonID, ReasonText)
        values (Rec.ContractID, Rec.CounterID, Rec.CounterDate, Rec.ChangeValue, Rec.ChangeDate, Rec.ReasonID, Rec.ReasonText); -- вставляем запись в историю изменений
      delete from ContractCounterValues_Postbox where rowid = Rec.rowid; -- удаляем обработанную запись из почтового ящика
      commit; -- коммитим изменения и снимаем блокировки          
    exception
      when others then Log(substr('ProcessContractCounterValuesPb '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки
    end;  
  end loop;
  commit;         
end;

procedure Log(pMessage varchar2) is pragma autonomous_transaction;
begin
  insert into Srvc_Log (Message) values (substr(pMessage, 1, 4000));
  commit;
end;

procedure PeriodicalFast is
begin
  ProcessCardsPostbox;
  ProcessContractAccountsPostbox;
  ProcessOwnerAccountsPostbox;
  ProcessCounterValuesPostbox;
  ProcessCounterValuesSPPostbox;
  ProcessContractCounterValuesPb;
  
  if GetCounterDate(3, sysdate, 0) = to_date('07.01.2002', 'dd.mm.yyyy') then
    Log('СТРАТ: Ошибка GetCounterDate(week)'); 
  end if;
exception
  when others then Log('PeriodicalFast: '||sqlerrm);        
end;

procedure ArchiveTerminalsOnline is
  lLastOnlineID number;
  lRowID rowid;
  c sys_refcursor;
begin
  -- для каждого терминала оставляем только последнюю запись в TerminalsOnline
  for Trm in (select ID from Terminals) loop
    begin
      open c for select OnlineID from TerminalsOnline where TerminalID = Trm.ID order by SystemDateTime desc;
      fetch c into lLastOnlineID;
      close c;
    
      if lLastOnlineID is not null then -- если какие-то записи есть, то остальные переносим в архив
        for Rec in (select OnlineID, SystemDateTime, TerminalID, DateTime from TerminalsOnline where TerminalID = Trm.ID and OnlineID < lLastOnlineID) loop begin
          select RowID into lRowID from TerminalsOnline where OnlineID = Rec.OnlineID for update nowait;
          insert into TerminalsOnline_Archive (OnlineID, SystemDateTime, TerminalID, DateTime) values (Rec.OnlineID, Rec.SystemDateTime, Rec.TerminalID, Rec.DateTime);
          delete from TerminalsOnline where rowid = lRowID;
          commit; -- для каждой строки
        exception
          when others then Log(substr('ArchiveTerminalsOnline. Error for OnlineID='||Rec.OnlineID||': '||sqlerrm, 1, 4000)); 
        end; end loop;      
      
        /*insert into TerminalsOnline_Archive (OnlineID, SystemDateTime, TerminalID, DateTime) 
          select OnlineID, SystemDateTime, TerminalID, DateTime from TerminalsOnline where TerminalID = Trm.ID and OnlineID < lOnlineID;  
        delete from TerminalsOnline where TerminalID = Trm.ID and OnlineID < lOnlineID;*/
      end if;
    exception
      when others then Log(substr('ArchiveTerminalsOnline. Error for TerminalID='||Trm.ID||': '||sqlerrm, 1, 4000)); -- записываем в лог ошибки при обработке терминала
    end;  
  end loop;

/*for Rec in (select OnlineID, SystemDateTime, TerminalID, DateTime from TerminalsOnline where SystemDateTime < sysdate-30) loop
    begin
      select RowID into lRowID from TerminalsOnline where OnlineID = Rec.OnlineID for update nowait;
      insert into TerminalsOnline_Archive (OnlineID, SystemDateTime, TerminalID, DateTime) values (Rec.OnlineID, Rec.SystemDateTime, Rec.TerminalID, Rec.DateTime);
      delete from TerminalsOnline where rowid = lRowID;
      commit;
    exception
      when others then Log(substr('ArchiveTerminalsOnline. Error for OnlineID='||Rec.OnlineID||': '||sqlerrm, 1, 4000)); 
    end;  
  end loop;*/
exception
  when others then Log(substr('ArchiveTerminalsOnline '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки
end;

procedure PeriodicalSlow is
begin
  ArchiveTerminalsOnline;
exception
  when others then Log('PeriodicalSlow: '||sqlerrm);        
end;

function GetCrossRate(pIDFrom number, pIDTo number, pCurrentDate date) return number as
  c sys_refcursor;
  lRate float := null;
begin
  if pIDFrom = pIDTo then return 1; end if;
  open c for select /*+first_rows*/ Rate from CurrencyCrossRates where IDFrom = pIDFrom and IDTo = pIDTo and DateStart <= pCurrentDate order by DateStart desc;
  fetch c into lRate;
  close c;
  if lRate is null then
    raise_application_error(-20001, 'No cross rate for currencies IDFrom: '||pIDFrom||', IDTo: '||pIDTo||' at the date '||pCurrentDate);
  else
    return lRate; -- возвращаем первый кросс-курс
  end if;  
end;

function GetValidTariffPeriodID(pTariffID number, pCurrentDate date) return number deterministic as
  c sys_refcursor;
  lID number := null;
begin
  open c for select ID from TariffPeriods where TariffID = pTariffID and IsActive = 1 and DateStart <= pCurrentDate order by DateStart desc;
  fetch c into lID;
  close c;
  return lID; -- возвращаем первый ID (или null если %notfound)
end;

function IsClosedDateTime(pDateTime date) return number as
  lDummy number;
begin
  select count(1) into lDummy from AccountingPeriods where pDateTime between DateFrom and DateTo and IsClosed = 1;
  return lDummy;  
end;

function AdjustTransactionID(pID number) return number as
  lID Transactions.ID%type := pID;
  lInitialSource Transactions.Source%type;
  sID varchar2(30);
 
  function TraExists(pTraID number) return binary_integer as
    lCount number;
  begin
    select count(1) into lCount from Transactions where ID = pTraID;
    if lCount > 0 then return 1; else return 0; end if;  
  end;
  
begin
  if TraExists(lID) > 0 then return lID; end if;
  lInitialSource := substr(to_char(lID), 1, 1);
  for Rec in (select ID from Srvc_TransactionSources where ID != lInitialSource) loop
    if Rec.ID != lInitialSource then 
      sID := substr(to_char(lID), 2);
      sID := Rec.ID || sID;
      lID := to_number(sID);
      if TraExists(lID) > 0 then return lID; end if;
    end if;
  end loop;
  raise_application_error(-20001, 'Транзакция '||pID||' не найдена после перебора известных источников');
end;

function CreateRetailSystem(pOwnerID number, pGlobalID number, pName varchar2, pEncoding varchar2) return number is
  pragma autonomous_transaction;
  lLockHandle varchar2(38);
  lLockResult integer;
  lID number;
begin
  dbms_lock.allocate_unique('Online.CreateRetailSystem', lLockHandle, 60); -- запрашиваем ID блокировки на 60 секунд
  lLockResult := dbms_lock.request(lLockHandle, dbms_lock.x_mode, 60, TRUE); -- запрашиваем эксклюзивную блокировку с таймаутом 60 секунд
  if lLockResult != 0 then raise_application_error(-20001, 'Ошибка блокировки '||lLockResult||' при создании СУ ККМ '||pOwnerID||':'||pGlobalID||' ('||pName||')'); end if;    
  begin
    select ID into lID from RetailSystems where GlobalOwnerID = pOwnerID and GlobalID = pGlobalID;  
    lLockResult := dbms_lock.release(lLockHandle);
  exception when no_data_found then
    insert into RetailSystems (GlobalOwnerID, GlobalID, Name, Encoding) values (pOwnerID, pGlobalID, pName, pEncoding) returning ID into lID;
    commit;
  end;
  return lID;  
end;

function CreateNetwork(pOwnerID number, pGlobalID number, pName varchar2) return number is
  pragma autonomous_transaction;
  lLockHandle varchar2(38);
  lLockResult integer;
  lID number;
begin
  dbms_lock.allocate_unique('Online.CreateNetwork', lLockHandle, 60); -- запрашиваем ID блокировки на 60 секунд
  lLockResult := dbms_lock.request(lLockHandle, dbms_lock.x_mode, 60, TRUE); -- запрашиваем эксклюзивную блокировку с таймаутом 60 секунд
  if lLockResult != 0 then raise_application_error(-20001, 'Ошибка блокировки '||lLockResult||' при создании сети ТО '||pOwnerID||':'||pGlobalID||' ('||pName||')'); end if;    
  begin
    select ID into lID from Networks where GlobalOwnerID = pOwnerID and GlobalID = pGlobalID;  
    lLockResult := dbms_lock.release(lLockHandle);
  exception when no_data_found then
    insert into Networks (GlobalOwnerID, GlobalID, Name) values (pOwnerID, pGlobalID, pName) returning ID into lID;
    commit;
  end;
  return lID;  
end;

function CreateRegion(pOwnerID number, pGlobalID number, pName varchar2, pTimeOffset number, pCurrencyID number, pCultureName varchar2) return number is
  pragma autonomous_transaction;
  lLockHandle varchar2(38);
  lLockResult integer;
  lID number;
begin
  dbms_lock.allocate_unique('Online.CreateRegion', lLockHandle, 60); -- запрашиваем ID блокировки на 60 секунд
  lLockResult := dbms_lock.request(lLockHandle, dbms_lock.x_mode, 60, TRUE); -- запрашиваем эксклюзивную блокировку с таймаутом 60 секунд
  if lLockResult != 0 then raise_application_error(-20001, 'Ошибка блокировки '||lLockResult||' при создании региона '||pOwnerID||':'||pGlobalID||' ('||pName||')'); end if;    
  begin
    select ID into lID from Regions where GlobalOwnerID = pOwnerID and GlobalID = pGlobalID;  
    lLockResult := dbms_lock.release(lLockHandle);
  exception when no_data_found then
    insert into Regions (GlobalOwnerID, GlobalID, Name, TimeOffset, CurrencyID, CultureName) values (pOwnerID, pGlobalID, pName, pTimeOffset, pCurrencyID, pCultureName) returning ID into lID;
    commit;
  end;
  return lID;  
end;

function CreateServicePoint(pOwnerID number, pGlobalID number, pName varchar2, pAddress varchar2, pTimeOffset number, pRegionID number, pNetworkID number, pRSID number) return number is
  pragma autonomous_transaction;
  lLockHandle varchar2(38);
  lLockResult integer;
  lID number;
begin
  dbms_lock.allocate_unique('Online.CreateServicePoint', lLockHandle, 60); -- запрашиваем ID блокировки на 60 секунд
  lLockResult := dbms_lock.request(lLockHandle, dbms_lock.x_mode, 60, TRUE); -- запрашиваем эксклюзивную блокировку с таймаутом 60 секунд
  if lLockResult != 0 then raise_application_error(-20001, 'Ошибка блокировки '||lLockResult||' при создании ТО '||pOwnerID||':'||pGlobalID||' ('||pName||')'); end if;    
  begin
    select ID into lID from ServicePoints where GlobalOwnerID = pOwnerID and GlobalID = pGlobalID;  
    lLockResult := dbms_lock.release(lLockHandle);
  exception when no_data_found then
    insert into ServicePoints (GlobalOwnerID, GlobalID, Name, Address, TimeOffset, RegionID, NetworkID, RSID) values (pOwnerID, pGlobalID, pName, pAddress, pTimeOffset, pRegionID, pNetworkID, pRSID) returning ID into lID;
    commit;
  end;
  return lID;  
end;

function CreateTerminal(pOwnerID number, pGlobalID number, pName varchar2, pServicePointID number) return number is
  pragma autonomous_transaction;
  lLockHandle varchar2(38);
  lLockResult integer;
  lID number;
begin
  dbms_lock.allocate_unique('Online.CreateTerminal', lLockHandle, 60); -- запрашиваем ID блокировки на 60 секунд
  lLockResult := dbms_lock.request(lLockHandle, dbms_lock.x_mode, 60, TRUE); -- запрашиваем эксклюзивную блокировку с таймаутом 60 секунд
  if lLockResult != 0 then raise_application_error(-20001, 'Ошибка блокировки '||lLockResult||' при создании терминала '||pOwnerID||':'||pGlobalID||' ('||pName||')'); end if;    
  begin
    select ID into lID from Terminals where GlobalOwnerID = pOwnerID and GlobalID = pGlobalID;  
    lLockResult := dbms_lock.release(lLockHandle);
  exception when no_data_found then
    insert into Terminals (GlobalOwnerID, GlobalID, TerminalName, SPID) values (pOwnerID, pGlobalID, pName, pServicePointID) returning ID into lID;
    commit;
  end;
  return lID;  
end;

function GetCardRangeID(pCardNumber number) return number as
 lResult CardRanges.ID%type;
begin
  select ID into lResult from CardRanges where pCardNumber between CardNumberFrom and CardNumberTo and IsAllowed = 1;
  return lResult;            
exception
  when no_data_found then raise_application_error(-20001, 'Номера карты '||pCardNumber||' нет в активных диапазонах'); 
  when too_many_rows then raise_application_error(-20001, 'Номер карты '||pCardNumber||' присутствует в нескольких активных диапазонах');   
  when others then raise_application_error(-20001, 'Неизвестная ошибка');   
end;

function CreateEmail(pCardNumber number, pSMTPProviderID number, pAddress varchar2, pSubject varchar2, pBody varchar2) return number as
  pragma autonomous_transaction;
  lID Emails_PostBox.ID%type; 
begin
  insert into Emails_PostBox (CardNumber, SMTPProviderID, Address, Subject, Body) values (pCardNumber, pSMTPProviderID, pAddress, pSubject, pBody) returning ID into lID;
  commit;
  return lID;
end;  

function CreateSMS(pCardNumber number, pSMSProviderID number, pPhone varchar2, pMessage varchar2) return number as
  pragma autonomous_transaction;
  lID SMS_PostBox.ID%type; 
begin
  insert into SMS_PostBox (CardNumber, SMSProviderID, Phone, Message) values (pCardNumber, pSMSProviderID, pPhone, pMessage) returning ID into lID;
  commit;
  return lID;
end;  

function GetCardEventsCount(pCardNumber number, pCardContractID number, pCardOwnerID number) return number as
  lCount number;
begin
  select sum(c) into lCount from
  (
    select count(1) c from ContractOwnerEvents where OwnerID = pCardOwnerID
    union all
    select count(1) c from ContractEvents where ContractID = pCardContractID
    union all
    select count(1) c from CardEvents where CardNumber = pCardNumber
  );
  return lCount;
end;

function GetLastIDInCardsPostBox(pCardNumber number) return number as
  lResult Cards_PostBox.ID%type;
  c sys_refcursor;
begin
  open c for select /*+first_rows*/ ID from Cards_PostBox where CardNumber = pCardNumber order by ID desc;
  fetch c into lResult;
  close c;
  return lResult;  
end;

procedure ChangeCardCounterValue(pCardNumber number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1) is
  lCopyToID number := null;
begin
  insert into CounterValues_PostBox (CardNumber, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText)
    values (pCardNumber, pCounterID, GetCounterDateByID(pCounterID, pTransactionDate, 0), pChangeValue, pReasonID, pReasonText);

  if pProcessCopyTo != 0 then
    select CopyToID into lCopyToID from Counters where ID = pCounterID;
    if lCopyToID is not null then
      ChangeCardCounterValue(pCardNumber, lCopyToID, GetCounterDateByID(lCopyToID, pTransactionDate, 0), pChangeValue, pReasonID, pReasonText, pProcessCopyTo); -- изменяем связанные счётчики
    end if;     
  end if;  
end;

procedure ChangeCardCounterValueA(pCardNumber number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1) is
  pragma autonomous_transaction;
begin
  ChangeCardCounterValue(pCardNumber, pCounterID, pTransactionDate, pChangeValue, pReasonID, pReasonText, pProcessCopyTo); 
  commit; -- коммитим результат
end;

procedure ChangeCardCounterSPValue(pCardNumber number, pServicePointID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1) is
  lCopyToID number := null;
begin
  insert into CounterValuesSP_PostBox (CardNumber, SPID, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText)
    values (pCardNumber, pServicePointID, pCounterID, GetCounterDateByID(pCounterID, pTransactionDate, 0), pChangeValue, pReasonID, pReasonText);

  if pProcessCopyTo != 0 then
    select CopyToID into lCopyToID from Counters where ID = pCounterID;
    if lCopyToID is not null then
      ChangeCardCounterSPValue(pCardNumber, pServicePointID, lCopyToID, GetCounterDateByID(lCopyToID, pTransactionDate, 0), pChangeValue, pReasonID, pReasonText, pProcessCopyTo); -- изменяем связанные счётчики
    end if;     
  end if;  
end;

procedure ChangeCardCounterSPValueA(pCardNumber number, pServicePointID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1) is
  pragma autonomous_transaction;
begin
  ChangeCardCounterSPValue(pCardNumber, pServicePointID, pCounterID, pTransactionDate, pChangeValue, pReasonID, pReasonText, pProcessCopyTo); 
  commit; -- коммитим результат
end;

procedure ChangeContractCounterValue(pContractID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1) is
  lCopyToID number := null;
begin
  insert into ContractCounterValues_PostBox (ContractID, CounterID, CounterDate, ChangeValue, ReasonID, ReasonText)
    values (pContractID, pCounterID, GetCounterDateByID(pCounterID, pTransactionDate, 0), pChangeValue, pReasonID, pReasonText);

  if pProcessCopyTo != 0 then
    select CopyToID into lCopyToID from Counters where ID = pCounterID;
    if lCopyToID is not null then
      ChangeContractCounterValue(pContractID, lCopyToID, GetCounterDateByID(lCopyToID, pTransactionDate, 0), pChangeValue, pReasonID, pReasonText, pProcessCopyTo); -- изменяем связанные счётчики
    end if;     
  end if;  
end;

procedure ChangeContractCounterValueA(pContractID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1) is
  pragma autonomous_transaction;
begin
  ChangeContractCounterValue(pContractID, pCounterID, pTransactionDate, pChangeValue, pReasonID, pReasonText, pProcessCopyTo); 
  commit; -- коммитим результат
end;

function CardLockRequest(pLockID integer, pTimeout integer) return integer as
begin
  return dbms_lock.request(pLockID, dbms_lock.x_mode, pTimeout, TRUE);
end;

function GetCardActiveActionsCount(pCardNumber number, pCardScriptID number, pTransactionDate date, pCardOwnerID number default null) return number as
  lCount number;
  lCardOwnerID number := pCardOwnerID;
begin
  if lCardOwnerID is null then select OwnerID into lCardOwnerID from Cards where CardNumber = pCardNumber; end if;  
  select count(1) into lCount from PCCSActionCards ac, PCCSActions a 
   where a.ID = ac.PCCSActionID 
     and pTransactionDate between a.StartDate and a.EndDate 
     and pTransactionDate between ac.StartSubscriptionDate and ac.EndSubscriptionDate
     and ac.CardNumber = pCardNumber 
     and lCardOwnerID in (select CardOwnerID from PCCSActionOwners z where z.PCCSActionID = a.ID)
     and a.CardScriptID = pCardScriptID;         
  return lCount; 
end;

function GetCardActualParameters(pCardNumber number, pInStatusID number, pInCardState number, pInLastServiceDate date, pInFirstServiceDate date, pInPINBlock raw, pInPINMethod number) return sys_refcursor as
  lOutStatusID Cards.StatusID%type := pInStatusID; 
  lOutCardState Cards.CardState%type := pInCardState; 
  lOutLastServiceDate Cards.LastServiceDate%type := pInLastServiceDate; 
  lOutFirstServiceDate Cards.FirstServiceDate%type := pInFirstServiceDate; 
  lOutPINBlock Cards.PINBlock%type := pInPINBlock;   
  lOutPINMethod Cards.PINMethod%type := pInPINMethod;
  lCursor sys_refcursor;
begin
  for Rec in (select * from Cards_Postbox where CardNumber = pCardNumber and UpdateFlags != 0 order by ID) loop
    if bitand(Rec.UpdateFlags, 1) != 0 then lOutStatusID := Rec.StatusID; end if;   
    if bitand(Rec.UpdateFlags, 2) != 0 then lOutLastServiceDate := Rec.LastServiceDate; end if;   
    if bitand(Rec.UpdateFlags, 4) != 0 then lOutFirstServiceDate := Rec.FirstServiceDate; end if;   
    if bitand(Rec.UpdateFlags, 8) != 0 then lOutCardState := Rec.CardState; end if;   
    if bitand(Rec.UpdateFlags, 16) != 0 then lOutPINBlock := Rec.PINBlock; lOutPINMethod := Rec.PINMethod; end if;
  end loop;
  open lCursor for select lOutStatusID as StatusID, lOutCardState as CardState, lOutLastServiceDate as LastServiceDate, lOutFirstServiceDate as FirstServiceDate, lOutPINBlock as PINBlock, lOutPINMethod as PINMethod from dual;
  return lCursor;
end;

procedure GetCardActualParameters2(pCardNumber number, pStatusID in out number, pCardState in out number, pLastServiceDate in out date, pFirstServiceDate in out date, pPINBlock in out raw, pPINMethod in out number) is
begin
  for Rec in (select * from Cards_Postbox where CardNumber = pCardNumber and UpdateFlags != 0 order by ID) loop
    if bitand(Rec.UpdateFlags, 1) != 0 then pStatusID := Rec.StatusID; end if;   
    if bitand(Rec.UpdateFlags, 2) != 0 then pLastServiceDate := Rec.LastServiceDate; end if;   
    if bitand(Rec.UpdateFlags, 4) != 0 then pFirstServiceDate := Rec.FirstServiceDate; end if;   
    if bitand(Rec.UpdateFlags, 8) != 0 then pCardState := Rec.CardState; end if;   
    if bitand(Rec.UpdateFlags, 16) != 0 then pPINBlock := Rec.PINBlock; pPINMethod := Rec.PINMethod; end if;
  end loop;    
end;

end;
/