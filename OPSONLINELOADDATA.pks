CREATE OR REPLACE package OPCL.opsOnlineLoadData as 
-- Пакет для быстрой загрузки данных в ПЦ
-- (C) Pavel Alekseyuk, 2015

-- Загружает данные карты. Результаты возвращаются или в виде объектов или в виде курсоров, подготовленных для фетчинга
-- pCentralDate: это pTransactionDate преобразованное в центральное время ПЦ
procedure LoadCardData_v1(pCardNumber number, pTerminalID number, pTerminalCurrencyID number, pServicePointID number, pRegionID number, pNetworkID number, pNetworkOwnerID number, 
                          pCardScriptID number, pTransactionDate date, pCentralDate date,
                          pCardData out opsTypeCardData_v1, 
                          pContractID number, pContractData out opsTypeContractData_v1, 
                          pCardCounters out sys_refcursor, pCardCountersSP out sys_refcursor, pContractCounters out sys_refcursor,
                          pCardLimits out sys_refcursor, pCardEvents out sys_refcursor, pCardPurseRestrictions out sys_refcursor, pCardActions out sys_refcursor, 
                          pContractTariffPeriods out sys_refcursor, pContractLimits out sys_refcursor, pContractAccounts out sys_refcursor, pOwnerAccounts out sys_refcursor);

-- Подготавливает новую транзакцию: формирует уникальный ID транзакции, проверяет дату транзакции на закрытость или открытость
procedure PrepareTransaction_v1(pSource number, pPCOwnerID number, pTerminalDate date, pTransactionID out number, pIsClosed out number);                          
                          
end;
/