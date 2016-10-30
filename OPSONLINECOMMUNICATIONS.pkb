CREATE OR REPLACE package body OPCL.opsOnlineCommunications as 

procedure ProcessRefusalNotifications is
  lMessage long;
  lLastError RefusalNotifications_Postbox.ProcessingMessage%type;
  lSendAttempts RefusalNotifications_Postbox.SendAttempts%type;
  lRefusal RefusalNotifications_Postbox%rowtype;
  lRT RefusalTransactions%rowtype;
  lLastProviderID SMTPProviders.ID%type := null;
  lSum number;
  lTotalCount number;
  lSuccessCount number;
  lFailedCount number;
  lProvider SMTPProviders%rowtype;
  lNewLine constant varchar2(3) := chr(13)||chr(10);
  lMaxSendAttempts constant number(2) := 10;
  row_locked exception;
  pragma Exception_init(row_locked, -54); 

  function GetPackageName(pPackage binary_integer) return varchar2 as
    lResult varchar2(50);
  begin
    case pPackage 
      when null then lResult := 'null';  
      when 0 then lResult := 'Неизвестный';  
      when 1 then lResult := 'Инфо о карте';  
      when 2 then lResult := 'Расчёт чека';  
      when 3 then lResult := 'Покупка';  
      when 4 then lResult := 'Открытие смены';  
      when 5 then lResult := 'Отмена';  
      when 6 then lResult := 'Закрытие смены';  
      when 7 then lResult := 'Неизвестный ATR карты';  
      when 8 then lResult := 'Принятие анкеты';  
      when 9 then lResult := 'Запрос соединения от стороннего приложения';  
      when 11 then lResult := 'Проверка PIN';  
      when 128 then lResult := 'Запрос списка автономных товаров';  
      when 129 then lResult := 'Запрос набора ключей шифрования';  
      when 130 then lResult := 'Запрос логотипа';  
      when 131 then lResult := 'Запрос пополнения счёта';  
      when 132 then lResult := 'Запрос даты и времени';  
      when 133 then lResult := 'Запрос аварийной конфигурации ';  
      when 144 then lResult := 'Запрос списка файлов';  
      when 145 then lResult := 'Запрос следующей части/файла';  
      when 160 then lResult := 'Уведомление об онлайн';  
      when 161 then lResult := 'Регистрация банковской операции';  
      when 162 then lResult := 'Регистрация offline транзакции';  
      when 164 then lResult := 'Запрос копии чека';  
      when 165 then lResult := 'Запрос списка акций';  
      when 166 then lResult := 'Подключение к акции (отключение от акции)';
      when 167 then lResult := 'Напоминание PIN кода карты';  
      when 255 then lResult := 'Уведомление об ошибке';
      else lResult := 'Неизвестный номер '||pPackage;
    end case;
    return lResult;
  end;  
  
  
begin
  -- получаем условие для подзапроса
  for R in (select RefusalID from RefusalNotifications_Postbox) loop
    -- пытаемся обработать уведомление о транзакции
    begin
      select * into lRefusal from RefusalNotifications_Postbox where RefusalID = R.RefusalID for update nowait; -- блокируем строку
    exception when no_data_found then continue; -- если не смогли найти строку - переходим к следующей
              when row_locked then continue; -- если не смогли заблокировать строку - переходим к следующей
    end;  

    lSendAttempts := lRefusal.SendAttempts + 1; -- увеличиваем количество попыток отправки сообщения 
  
    lLastError := null; lSuccessCount := 0; lFailedCount := 0; lTotalCount := 0;
    -- для каждого условия пытаемся выбрать отказные транзакции, которые удовлетворяют условиям
    for Notif in (select * from RefusalNotificationsByEmail order by SMTPProviderID, ID) loop
      begin
        execute immediate 'select * from RefusalTransactions where ID = '||lRefusal.RefusalID||' '||Notif.SQLCondition into lRT;
      exception when no_data_found then continue; -- если не нашли транзакцию (например, потому что она нам не подходит - переходим к следующему списку уведомлений
      end;
      lTotalCount := lTotalCount + 1;   
      
      if lLastProviderID is null or lLastProviderID != Notif.SMTPProviderID then
        lLastProviderID := Notif.SMTPProviderID; 
        select * into lProvider from SMTPProviders where ID = lLastProviderID;  
      end if;

      -- считаем сумму транзакции
      lSum := lRT.PaymentCash + lRT.PaymentBankingCard + lRT.PaymentBonuses + lRT.PaymentCredit + lRT.PaymentPrepaidAccount;
      -- подготавливаем сообщение
      lMessage := 'ID: '||lRT.ID||',  '||
                  'Дата транзакции: '||to_char(lRT.TerminalDateTime, 'dd.mm.yyyy hh24:mi:ss')||',  '||
                  'Дата БД: '||to_char(lRT.SystemDateTime, 'dd.mm.yyyy hh24:mi:ss')||',  '||
                  lNewLine||
                  'Терминал: '||lRT.TerminalID||',  '||
                  'Карта: '||lRT.CardNumber||',  '||
                  'Сумма: '||lSum||',  '||
                  'Пакет: '||lRT.PackageID||' ('||GetPackageName(lRT.PackageID)||')';
      if lRT.ApplicationSign is not null then lMessage := lMessage||', ПЦ: '||lRT.ApplicationSign; end if;
      lMessage := lMessage||lNewLine||'Сообщение:'||lNewLine||lRT.Message;
      lMessage := substr(lMessage, 1, 4000);
                         
      begin    
        send_mail(lProvider.Server, lProvider.Port, lProvider.AuthLogin, lProvider.AuthPassword, case when lProvider.RequireAuth = 1 then true else false end, 
                  case when lProvider.UseSSL = 1 then true else false end, lProvider.FromAddress, lProvider.FromName, Notif.ToEmail, Notif.Subject, lMessage);
        lSuccessCount := lSuccessCount + 1; -- отправка прошла успешно   
      exception when others then
        lFailedCount := lFailedCount + 1; -- не удалось отправить сообщение
        lLastError := substr(sqlerrm, 1, 4000);  
      end;
      
    end loop;
    
    if lTotalCount > 0 and (lSuccessCount < lTotalCount or lFailedCount > 0) and lSendAttempts < lMaxSendAttempts then
      -- Если транзакция кого-то заинтересовала, но ничего не вышло и при этом число попыток отправки не превышено, то обновляем транзакцию в ящике, но не удаляем её пока 
      update RefusalNotifications_Postbox set SendAttempts = lSendAttempts, ProcessingDate = sysdate, ProcessingResult = 0, ProcessingMessage = lLastError where RefusalID = lRefusal.RefusalID;
    elsif lTotalCount = 0 or lSendAttempts >= lMaxSendAttempts or lSuccessCount = lTotalCount then
      -- если транзакция никого не интересовала, превышено число попыток отправки или она отправлена успешно, то удаляем её из почтового ящика 
      if lSendAttempts >= lMaxSendAttempts then 
        opsOnline.Log(substr('Не удалось отправить уведомление об отказной транзакции:'||lNewLine||lMessage, 1, 4000)); -- уведомление об отказной теряется
      end if;  
      delete from RefusalNotifications_Postbox where RefusalID = lRefusal.RefusalID;     
    else
      opsOnline.Log(substr('Неизвестное отправки уведомления об отказе. RefusalID: '||lRefusal.RefusalID||', TotalCount: '||lTotalCount||', SuccessCount: '||lSuccessCount||', FailedCount: '||lFailedCount||', SendAttempts: '||lSendAttempts, 1, 4000)); -- уведомление об отказной теряется 
    end if;
    commit;  -- разблокируем строку
    
  end loop;
exception when others then opsOnline.Log(substr('ProcessRefusalNotifications '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки  
end;

procedure ProcessEmails is
  lResult number(1);
  lProvider SMTPProviders%rowtype;
  lEmail Emails_PostBox%rowtype;
  lLastProviderID SMTPProviders.ID%type := null;
  lSendAttempts Emails_PostBox.SendAttempts%type;
  lMaxSendAttempts constant number(2) := 3;
  lMessage Emails_PostBox.ProcessingMessage%type; 
  row_locked exception;
  pragma Exception_init(row_locked, -54); 
begin
  for Rec in (select rowid from Emails_PostBox order by SMTPProviderID, ID) loop -- получаем список сообщений для обработки
    -- пытаемся обработать сообщение
    begin
      select * into lEmail from Emails_PostBox where rowid = Rec.rowid for update nowait; -- блокируем строку
    exception when no_data_found then continue; -- если не смогли найти строку - переходим к следующей
              when row_locked then continue; -- если не смогли заблокировать строку - переходим к следующей
    end;  
  
    if lLastProviderID is null or lLastProviderID != lEmail.SMTPProviderID then
      lLastProviderID := lEmail.SMTPProviderID; 
      select * into lProvider from SMTPProviders where ID = lLastProviderID;  
    end if;
    lSendAttempts := lEmail.SendAttempts + 1; -- увеличиваем количество попыток отправки сообщения 
    
    begin    
      send_mail(lProvider.Server, lProvider.Port, lProvider.AuthLogin, lProvider.AuthPassword, case when lProvider.RequireAuth = 1 then true else false end, 
                case when lProvider.UseSSL = 1 then true else false end, lProvider.FromAddress, lProvider.FromName, lEmail.Address, lEmail.Subject, lEmail.Body);
      lResult := 1; -- отправка прошла успешно
      lMessage := null;
    exception when others then
      lResult := 0; -- не удалось отправить сообщение
      lMessage := substr(sqlerrm, 1, 4000);  
    end;
        
    if lResult = 0 and lSendAttempts < lMaxSendAttempts then -- если всё плохо и при этом количество попыток отправки не превысило максимальное 
      update Emails_PostBox set SendAttempts = lSendAttempts, ProcessingDate = sysdate, ProcessingResult = lResult, ProcessingMessage = lMessage where rowid = Rec.rowid;    
    else -- если же всё хорошо или количество попыток отправки превышено
      insert into Emails_Archive (id, creationdate, cardnumber, smtpproviderid, address, subject, body, sendattempts, processingresult, processingmessage)
        values (lEmail.ID, lEmail.CreationDate, lEmail.CardNumber, lEmail.SMTPProviderID, lEmail.Address, lEmail.Subject, lEmail.Body, lSendAttempts, lResult, lMessage);
      delete from Emails_PostBox where rowid = Rec.RowID;     
    end if;
    commit;    
  end loop;
exception when others then opsOnline.Log(substr('ProcessEmails '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки  
end;

procedure ProcessSMS is
  lResult number(1);
  lProvider SMSProviders%rowtype;
  lSMS SMS_PostBox%rowtype;
  lLastProviderID SMSProviders.ID%type := null;
  lSendAttempts SMS_PostBox.SendAttempts%type;
  lMaxSendAttempts constant number(2) := 10;
  lMessage SMS_PostBox.ProcessingMessage%type;
  row_locked exception;
  pragma Exception_init(row_locked, -54); 
begin
  for Rec in (select rowid from SMS_PostBox order by SMSProviderID, ID) loop -- получаем список сообщений для обработки
    -- пытаемся обработать сообщение
    begin
      select * into lSMS from SMS_PostBox where rowid = Rec.rowid for update nowait; -- блокируем строку
    exception when no_data_found then continue; -- если не смогли найти строку - переходим к следующей
              when row_locked then continue; -- если не смогли заблокировать строку - переходим к следующей
    end;  
  
    if lLastProviderID is null or lLastProviderID != lSMS.SMSProviderID then
      lLastProviderID := lSMS.SMSProviderID; 
      select * into lProvider from SMSProviders where ID = lLastProviderID;  
    end if;
    lSendAttempts := lSMS.SendAttempts + 1; -- увеличиваем количество попыток отправки сообщения 
    
    -- тут отправляем сообщение
    begin    
      send_sms(lProvider.TypeID, lProvider.AuthLogin, lProvider.AuthPassword, lSMS.Phone, lSMS.Message, lProvider.FromName);
      lResult := 1; -- отправка прошла успешно
      lMessage := null;
    exception when others then
      lResult := 0; -- не удалось отправить сообщение
      lMessage := substr(sqlerrm, 1, 4000);  
    end;
    
    if lResult = 0 and lSendAttempts < lMaxSendAttempts then -- если всё плохо и при этом количество попыток отправки не превысило максимальное 
      update SMS_PostBox set SendAttempts = lSendAttempts, ProcessingDate = sysdate, ProcessingResult = lResult, ProcessingMessage = lMessage where rowid = Rec.rowid;    
    else -- если же всё хорошо или количество попыток отправки превышено
      insert into SMS_Archive (id, creationdate, cardnumber, smsproviderid, phone, message, sendattempts, processingresult, processingmessage)
        values (lSMS.ID, lSMS.CreationDate, lSMS.CardNumber, lSMS.SMSProviderID, lSMS.Phone, lSMS.Message, lSendAttempts, lResult, lMessage);
      delete from SMS_PostBox where rowid = Rec.RowID;     
    end if;
    commit;    
  end loop;
exception when others then opsOnline.Log(substr('ProcessSMS '||sqlerrm, 1, 4000)); -- записываем в лог любые ошибки  
end;


procedure Process is
begin
  ProcessRefusalNotifications;
  ProcessEmails;
  ProcessSMS; 
end;

end;
/