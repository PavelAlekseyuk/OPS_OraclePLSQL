CREATE OR REPLACE package OPCL.opsOnline as 
-- данный пакет используется Online-сервером. Если не будет валидным - сервер работать не будет. Beware!
-- (C) Pavel Alekseyuk, 2012-2015
-- В ПАКЕТЕ НЕЛЬЗЯ СОЗДАВАТЬ ПЕРЕМЕННЫЕ ИЛИ КОНСТАНТЫ ДЛЯ ПРЕДОТВРАЩЕНИЯ ПОЯВЛЕНИЯ ОШИБКИ ORA-04068 ПОСЛЕ ПЕРЕКОМПИЛЯЦИИ В СОЕДИНЕНИЯХ ПУЛА

-- выделяет из ID транзакции компоненты, её составляющие
procedure ExtractFromTransactionID(pID number, pSource out number, pPCOwnerID out number, pUniqueNumber out number);

-- строит ID транзакции из компонентов
function BuildTransactionID(pSource number, pPCOwnerID number, pUniqueNumber number) return number;

-- Получить уникальный ID транзакции. TerminalID - ID терминала, на котором генерируется транзакция, Source - источник транзакции (Srvc_TransactionSources)
-- PCOwnerID - ID владельца процессингового центра текущей инсталляции
-- Параметры не верифицируется. Если PCOwnerID не передан, он будет получен из конфигурации системы
function GetTransactionID(pSource number default 1, pPCOwnerID number default null) return number;

-- Создаёт карту в системе (в АВТОНОМНОЙ транзакции. По завершении коммитит результат)
-- 01.07.2012. Поле pContractOwnerID не используется. Владелец карты берется из поля CardRanges.ContractOwnerID
-- pRegionID заменено на pCurrencyID 
-- 08.08.2014 параметр pCurrencyID удален - настройки берутся из диапазона карты
-- 19.01.2015 добавлен параметр pTryAutoAcceptQuest: если 1, то функция пытается автоматически принять анкету, если это задано в параметрах диапзаона карт
function CreateCard(pCardNumber number,  pTerminalID number default null, pTerminalDateTime date default sysdate, pRegisterActivation number default 0, 
                    pContractID number default null, pTryAutoAcceptQuest number default 1) return number;

-- Создаёт счётчик карты в АВТОНОМНОЙ транзакции. Коммитит результат
function CreateCardCounter(pName varchar2, pDescription varchar2, pType number, pSubType number, pPeriod number) return number;

-- Возвращает ID товара на ТО. Если переданного товара ещё нет в справочнике товаров - создаёт его в основной транзакции без коммита
function GetArticleID(pGoodsCode varchar2, pGoodsName varchar2, pRetailSystemID number) return number;
function GetArticleID2(pGoodsCode varchar2, pGoodsName varchar2, pRetailSystemID number, pNetwordOwnerID number) return number;

-- возвращает дату/время счётчика, за которую он хранит свои данные. Дата вычисляется из периода счётчика и текущей транзакции. 
-- pPeriodsAgo - сколько периодов счётчика нужно отступить назад: 0 - вернуть начало периода на основе даты транзакции, 1 - найти начало текущего периода и вычислить начало предыдущего периода 
function GetCounterDate(pCounterPeriod number, pTransactionDate date, pPeriodsAgo number default 0) return date deterministic;

-- Аналог GetCounterDate, но работает по ID счетчика, выбирая период из справочника
function GetCounterDateByID(pCounterID number, pTransactionDate date, pPeriodsAgo number default 0) return date deterministic;

-- возвращает ID единицы измерения. Если единицы измерения нет в справочнике - регистрирует её
function GetMeasureUnitID(pMeasureUnitName varchar2) return number;

-- Проверяет корректность Luhn-кода карты (последняя цифра номера)
function IsCorrectLuhn(pCardNumber number) return number;

-- Отменяет транзакцию с корректировкой счётчиков. Поднимает эксепшен в случае ошибки
--   pOriginalID: ID оригинальной транзакции для отмены, pRSDateTime: дата ККМ для тразакции отмены pSerialNumber: серийный номер устройства, на котором проведена операция отмены
--   pCancelID: если передаётся, то используется переданный ID транзакции отмены. Если null, то ID транзакции будет сгенерирован из данных оригинальной транзакции
--   pNeedLockCard: нужно или нет блокировать карту для изменения таблиц CounterValues (обычно 1 если функция вызывается сама по себе и 0 - если в составе ПО, которое само блокируем карту)
--   pCancelSource: источник транзакции отмены. Если null, то берётся источник оригинальной транзакции
-- Возвращает ID транзакции отмены
-- Функция не коммитит результат
-- Дата и время транзакции отмены ДОЛЖНА СОВПАДАТЬ с датой оригинальной транзакции для корректной обработки счетчиков
function CancelTransaction(pOriginalID number, pCancelID number default null, pNeedLockCard number default 0, pRSDateTime date default null, 
                           pSerialNumber varchar2 default null, pCancelSource number default null) return number;
function CancelTransaction2(pOriginalID number, pCancelID number, pNeedLockCard number, pRSDateTime date, pSerialNumber varchar2, pCancelSource number, 
                            pSignature raw, pAppSign number) return number;

-- Регистрация транзакции приёма анкеты: в текущй сессии без коммита и в автономной транзакции
procedure RegisterQuestTransaction(pCardNumber number, pTerminalID number, pDateTime date, pDeadLineTime date, pID number default null);
procedure RegisterQuestTransactionA(pCardNumber number, pTerminalID number, pDateTime date, pDeadLineTime date, pID number default null);

-- Регистрация транзакции по карте: в текущй сессии без коммита
procedure RegisterCardTransaction(pCardNumber number, pTerminalID number, pDateTime date, pTransactionType number, pOldNData number default null, pNewNData number default null, pOldVCData varchar2 default null, pNewVCData varchar2 default null);

-- Регистрация транзакции активации карты
procedure RegisterActivationTransaction(pCardNumber number, pTerminalID number, pDateTime date);

-- Обработать таблицу Cards_Postbox для применения содержащихся в ней изменений. Процедура должна запускаться периодичеки.
-- Коммитит результат после каждой записи
procedure ProcessCardsPostbox;

-- Обработать таблицу ContractAccounts_Postbox для применения изменений счёта договора. Процедура должна запускаться периодичеки.
-- Коммитит результат после каждой записи
procedure ProcessContractAccountsPostbox;

-- Обработать таблицу OwnerAccounts_Postbox для применения изменений счёта владельца. Процедура должна запускаться периодичеки.
-- Коммитит результат после каждой записи
procedure ProcessOwnerAccountsPostbox;

-- Обработать таблицу CounterValues_Postbox для применения изменений счётчиков карты. Процедура должна запускаться периодичеки.
-- Коммитит результат после каждой записи
procedure ProcessCounterValuesPostbox;

-- Обработать таблицу CounterValues_Postbox для применения изменений счётчиков карты на ТО. Процедура должна запускаться периодичеки.
-- Коммитит результат после каждой записи
procedure ProcessCounterValuesSPPostbox;

-- записывает сообщение в служебный лог
procedure Log(pMessage varchar2);

-- Запускает все функции, которые требуют периодического запуска с минимальным интервалом времени
procedure PeriodicalFast;

-- Запускает тяжелые функции, которые требуют периодического запуска примерно раз в сутки
procedure PeriodicalSlow;

-- возвращает кросс-курс, действующий на переданную дату. Генерирует эксепшен, если кросс-курс не найден
function GetCrossRate(pIDFrom number, pIDTo number, pCurrentDate date) return number;

-- Получить активный период тарифа, действующий в момент pCurrentDate
function GetValidTariffPeriodID(pTariffID number, pCurrentDate date) return number deterministic;

-- Возвращает 0, если переданная дата не входит ни в один из закрытых периодов. В противном случае возвращает количество закрытых периодов в которые входит переданная дата (обычно 1)
function IsClosedDateTime(pDateTime date) return number;

-- Проверяет, существует ли переданная транзакция. Если не существует, то перебирает все TransactionSources и все PC.Owners для её поиска. Возвращает ID найденной транзакции или генерирует Exception, если транзакция не найдена
function AdjustTransactionID(pID number) return number;

-- Потокобезопасно создаёт СУ ККМ в автономной транзакции и возвращает его идентификатор. Если СУ ККМ уже создан, просто возвращает идентификатор
function CreateRetailSystem(pOwnerID number, pGlobalID number, pName varchar2, pEncoding varchar2) return number;

-- Потокобезопасно создаёт сеть ТО в автономной транзакции и возвращает его идентификатор. Если сеть ТО уже создана, просто возвращает идентификатор
function CreateNetwork(pOwnerID number, pGlobalID number, pName varchar2) return number;

-- Потокобезопасно создаёт регион в автономной транзакции и возвращает его идентификатор. Если регион уже создан, просто возвращает идентификатор.
function CreateRegion(pOwnerID number, pGlobalID number, pName varchar2, pTimeOffset number, pCurrencyID number, pCultureName varchar2) return number;

-- Потокобезопасно создаёт ТО в автономной транзакции и возвращает его идентификатор. Если ТО уже создана, просто возвращает идентификатор.
function CreateServicePoint(pOwnerID number, pGlobalID number, pName varchar2, pAddress varchar2, pTimeOffset number, pRegionID number, pNetworkID number, pRSID number) return number;

-- Потокобезопасно создаёт терминал в автономной транзакции и возвращает его идентификатор. Если терминал уже создан, просто возвращает идентификатор
function CreateTerminal(pOwnerID number, pGlobalID number, pName varchar2, pServicePointID number) return number;

-- Возвращает ID диапазона для переданного номера карты
function GetCardRangeID(pCardNumber number) return number;

-- Создаёт задание на отправку email в автономной транзакции и коммитит результат. Возвращает ID созданного задания
function CreateEmail(pCardNumber number, pSMTPProviderID number, pAddress varchar2, pSubject varchar2, pBody varchar2) return number;

-- Создаёт задание на отправку SMS в автономной транзакции и коммитит результат. Возвращает ID созданного задания
function CreateSMS(pCardNumber number, pSMSProviderID number, pPhone varchar2, pMessage varchar2) return number;

-- Возвращает количество событий системы, сконфигурированных для переданной карты, договора и владельца. Все параметры должны быть not null
function GetCardEventsCount(pCardNumber number, pCardContractID number, pCardOwnerID number) return number;

-- Возвращает последний добавленный ID из таблицы Cards_Postbox для переданной карты или null, если нет записей
function GetLastIDInCardsPostBox(pCardNumber number) return number;

-- Изменяет значение счётчика карты. pTransactionDate - это базовая дата транзакции, на которую изменяется счётчик. Изменение счётчика никак не привязано к транзакции покупки.
-- Если pProcessCopyTo = 1, то значеня связанных счётчиков также будут изменены.
procedure ChangeCardCounterValue(pCardNumber number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);
-- A - тоже самое в автономной транзакции
procedure ChangeCardCounterValueA(pCardNumber number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);

-- Аналогично для счётчиков карты на ТО
procedure ChangeCardCounterSPValue(pCardNumber number, pServicePointID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);
procedure ChangeCardCounterSPValueA(pCardNumber number, pServicePointID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);

-- Аналогично для счётчиков договора
procedure ChangeContractCounterValue(pContractID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);
procedure ChangeContractCounterValueA(pContractID number, pCounterID number, pTransactionDate date, pChangeValue number, pReasonID number, pReasonText varchar2, pProcessCopyTo binary_integer default 1);

-- Функция-обёртка для вызова блокировки карты в SQL-запросе
function CardLockRequest(pLockID integer, pTimeout integer) return integer;

-- Функция возвращает количество акций, активных на дату pTransactionDate, поддерживаемых скриптом pCardScriptID, для карты pCardNumber 
function GetCardActiveActionsCount(pCardNumber number, pCardScriptID number, pTransactionDate date, pCardOwnerID number default null) return number;

-- Функция, возвращающая актуальные параметры карты с учётом изменений в Cards_Postbox
function GetCardActualParameters(pCardNumber number, pInStatusID number, pInCardState number, pInLastServiceDate date, pInFirstServiceDate date, pInPINBlock raw, pInPINMethod number) return sys_refcursor;
-- Процедура аналогична функции GetCardActualParameters, но работает через изменение параметров 
procedure GetCardActualParameters2(pCardNumber number, pStatusID in out number, pCardState in out number, pLastServiceDate in out date, pFirstServiceDate in out date, pPINBlock in out raw, pPINMethod in out number);

end;
/