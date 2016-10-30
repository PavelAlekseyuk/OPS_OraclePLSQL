CREATE OR REPLACE package OPCL.opsOnlineRestrictions as 
-- данный пакет используется Online-сервером. Если не будет валидным - сервер работать не будет. Be carefully!
-- (C) Pavel Alekseyuk, 2012-2015
-- В ПАКЕТЕ НЕЛЬЗЯ СОЗДАВАТЬ ПЕРЕМЕННЫЕ ИЛИ КОНСТАНТЫ ДЛЯ ПРЕДОТВРАЩЕНИЯ ПОЯВЛЕНИЯ ОШИБКИ ORA-04068 ПОСЛЕ ПЕРЕКОМПИЛЯЦИИ В СОЕДИНЕНИЯХ ПУЛА

/* 
   Принципы ограничений (для каждого типа объекта):  
     а) запрет приоритетнее разрешения
     б) если есть ТОЛЬКО разрешения и НЕТ запретов, то запрещено всё что не разрешено
     в) если есть (ТОЛЬКО запреты) ИЛИ (разрешения и запреты), то разрешено всё что не запрещено
     г) если нет ни разрешений ни запретов, то разрешено всё
   Ограничения бывают двух видов: 
     1. Территориальные: терминал, ТО, регион, сеть ТО, владелец сети ТО. 
     2. Клиентские: договор, клиент, группа клиентов, владелец контракта. Также расположены в порядке убывания приоритета, но анализ отличается.
          Если клиент разрешен - ставим признак разрешения и продолжаем анализ. Если клиент запрещён - выходим с запретом
          Если все группы, в которые входит клиент разрешены - ставим признак разрешения и продолжаем анализ. Если хотя бы одна группа запрещена - выходим с запретом
          Если владелец контракта разрешен - ставим признак разрешения и продолжаем анализ. Если владелец контракта запрещен - выходим с запретом.
          В результате получаем результат - разрешение или запрет
   Комбинированные ограничения анализируются последовательно (порядок задан нумерацией списка). 
*/

type ListOfValues is varray(300) of number;

-- Проанализировать ограничения на период тарифа и вернуть 1 - данный период РАЗРЕШЕН на указанных объектах, 0 - данный период ЗАПРЕЩЕН на указанных объектах, 2 - ограничения не сконфигурированы
-- дефолтные переменные могут не передаваться и будут вычислены на основе TerminalID. Они передаются только для скорости. На 10000 кэшированных вызовах даёт прирост в 1,5 секунды
function CheckTariffPeriod(pPeriodID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                           pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- Проанализировать ограничения на договор. См. ContractRestrictions 
function CheckContract(pContractID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                       pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- Проанализировать ограничения на карту. См. CardRestrictions. На момент загрузки информации по карте есть только pContractID, поэтому функция сама выберет остальное 
function CheckCard(pCardNumber number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                   pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- Проанализировать ограничения на набор параметров. См. ParamSetRestrictions 
function CheckParamSet(pSetID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                       pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- Проанализировать ограничения на градацию периода тарифа. См. GraduationRestrictions  
function CheckGraduation(pGraduationID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                         pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- Проанализировать ограничения на диапазон карт. См. CardRangeRestrictions
function CheckCardRange(pRangeID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                         pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- Проанализировать ограничения на владельца договора. См. ContractOwnerRestrictions
function CheckContractOwner(pContractOwnerID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null, 
                            pContractID number default null, pContractType number default null, pClientID number default null) return number deterministic;

-- Проанализировать ограничения на владельца сети ТО. См. NetworkOwnerRestrictions
function CheckNetworkOwner(pNetworkOwnerID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null,  
                            pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- Проанализировать ограничения на счёт владельца. См. OwnerAccountRestrictions
function CheckOwnerAccount(pOwnerAccountID number, pTerminalID number, pServicePointID number default null, pRegionID number default null, pNetworkID number default null, pNetworkOwnerID number default null,
                            pContractID number default null, pContractType number default null, pClientID number default null, pContractOwnerID number default null) return number deterministic;

-- Возвращает ID владельца (сети или договора) для переданного идентификатора
function GetOwnerID(pServiceTableID number, pID number) return number;

-- Возвращает количество ограничений на кошельки, сконфигурированных для карты, договора и владельца. Все параметры должны быть not null
function GetCardPurseRestrictionsCount(pCardNumber number, pCardContractID number, pCardOwnerID number) return number;

end;
/