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
      when 0 then lResult := '�����������';  
      when 1 then lResult := '���� � �����';  
      when 2 then lResult := '������ ����';  
      when 3 then lResult := '�������';  
      when 4 then lResult := '�������� �����';  
      when 5 then lResult := '������';  
      when 6 then lResult := '�������� �����';  
      when 7 then lResult := '����������� ATR �����';  
      when 8 then lResult := '�������� ������';  
      when 9 then lResult := '������ ���������� �� ���������� ����������';  
      when 11 then lResult := '�������� PIN';  
      when 128 then lResult := '������ ������ ���������� �������';  
      when 129 then lResult := '������ ������ ������ ����������';  
      when 130 then lResult := '������ ��������';  
      when 131 then lResult := '������ ���������� �����';  
      when 132 then lResult := '������ ���� � �������';  
      when 133 then lResult := '������ ��������� ������������ ';  
      when 144 then lResult := '������ ������ ������';  
      when 145 then lResult := '������ ��������� �����/�����';  
      when 160 then lResult := '����������� �� ������';  
      when 161 then lResult := '����������� ���������� ��������';  
      when 162 then lResult := '����������� offline ����������';  
      when 164 then lResult := '������ ����� ����';  
      when 165 then lResult := '������ ������ �����';  
      when 166 then lResult := '����������� � ����� (���������� �� �����)';
      when 167 then lResult := '����������� PIN ���� �����';  
      when 255 then lResult := '����������� �� ������';
      else lResult := '����������� ����� '||pPackage;
    end case;
    return lResult;
  end;  
  
  
begin
  -- �������� ������� ��� ����������
  for R in (select RefusalID from RefusalNotifications_Postbox) loop
    -- �������� ���������� ����������� � ����������
    begin
      select * into lRefusal from RefusalNotifications_Postbox where RefusalID = R.RefusalID for update nowait; -- ��������� ������
    exception when no_data_found then continue; -- ���� �� ������ ����� ������ - ��������� � ���������
              when row_locked then continue; -- ���� �� ������ ������������� ������ - ��������� � ���������
    end;  

    lSendAttempts := lRefusal.SendAttempts + 1; -- ����������� ���������� ������� �������� ��������� 
  
    lLastError := null; lSuccessCount := 0; lFailedCount := 0; lTotalCount := 0;
    -- ��� ������� ������� �������� ������� �������� ����������, ������� ������������� ��������
    for Notif in (select * from RefusalNotificationsByEmail order by SMTPProviderID, ID) loop
      begin
        execute immediate 'select * from RefusalTransactions where ID = '||lRefusal.RefusalID||' '||Notif.SQLCondition into lRT;
      exception when no_data_found then continue; -- ���� �� ����� ���������� (��������, ������ ��� ��� ��� �� �������� - ��������� � ���������� ������ �����������
      end;
      lTotalCount := lTotalCount + 1;   
      
      if lLastProviderID is null or lLastProviderID != Notif.SMTPProviderID then
        lLastProviderID := Notif.SMTPProviderID; 
        select * into lProvider from SMTPProviders where ID = lLastProviderID;  
      end if;

      -- ������� ����� ����������
      lSum := lRT.PaymentCash + lRT.PaymentBankingCard + lRT.PaymentBonuses + lRT.PaymentCredit + lRT.PaymentPrepaidAccount;
      -- �������������� ���������
      lMessage := 'ID: '||lRT.ID||',  '||
                  '���� ����������: '||to_char(lRT.TerminalDateTime, 'dd.mm.yyyy hh24:mi:ss')||',  '||
                  '���� ��: '||to_char(lRT.SystemDateTime, 'dd.mm.yyyy hh24:mi:ss')||',  '||
                  lNewLine||
                  '��������: '||lRT.TerminalID||',  '||
                  '�����: '||lRT.CardNumber||',  '||
                  '�����: '||lSum||',  '||
                  '�����: '||lRT.PackageID||' ('||GetPackageName(lRT.PackageID)||')';
      if lRT.ApplicationSign is not null then lMessage := lMessage||', ��: '||lRT.ApplicationSign; end if;
      lMessage := lMessage||lNewLine||'���������:'||lNewLine||lRT.Message;
      lMessage := substr(lMessage, 1, 4000);
                         
      begin    
        send_mail(lProvider.Server, lProvider.Port, lProvider.AuthLogin, lProvider.AuthPassword, case when lProvider.RequireAuth = 1 then true else false end, 
                  case when lProvider.UseSSL = 1 then true else false end, lProvider.FromAddress, lProvider.FromName, Notif.ToEmail, Notif.Subject, lMessage);
        lSuccessCount := lSuccessCount + 1; -- �������� ������ �������   
      exception when others then
        lFailedCount := lFailedCount + 1; -- �� ������� ��������� ���������
        lLastError := substr(sqlerrm, 1, 4000);  
      end;
      
    end loop;
    
    if lTotalCount > 0 and (lSuccessCount < lTotalCount or lFailedCount > 0) and lSendAttempts < lMaxSendAttempts then
      -- ���� ���������� ����-�� ��������������, �� ������ �� ����� � ��� ���� ����� ������� �������� �� ���������, �� ��������� ���������� � �����, �� �� ������� � ���� 
      update RefusalNotifications_Postbox set SendAttempts = lSendAttempts, ProcessingDate = sysdate, ProcessingResult = 0, ProcessingMessage = lLastError where RefusalID = lRefusal.RefusalID;
    elsif lTotalCount = 0 or lSendAttempts >= lMaxSendAttempts or lSuccessCount = lTotalCount then
      -- ���� ���������� ������ �� ������������, ��������� ����� ������� �������� ��� ��� ���������� �������, �� ������� � �� ��������� ����� 
      if lSendAttempts >= lMaxSendAttempts then 
        opsOnline.Log(substr('�� ������� ��������� ����������� �� �������� ����������:'||lNewLine||lMessage, 1, 4000)); -- ����������� �� �������� ��������
      end if;  
      delete from RefusalNotifications_Postbox where RefusalID = lRefusal.RefusalID;     
    else
      opsOnline.Log(substr('����������� �������� ����������� �� ������. RefusalID: '||lRefusal.RefusalID||', TotalCount: '||lTotalCount||', SuccessCount: '||lSuccessCount||', FailedCount: '||lFailedCount||', SendAttempts: '||lSendAttempts, 1, 4000)); -- ����������� �� �������� �������� 
    end if;
    commit;  -- ������������ ������
    
  end loop;
exception when others then opsOnline.Log(substr('ProcessRefusalNotifications '||sqlerrm, 1, 4000)); -- ���������� � ��� ����� ������  
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
  for Rec in (select rowid from Emails_PostBox order by SMTPProviderID, ID) loop -- �������� ������ ��������� ��� ���������
    -- �������� ���������� ���������
    begin
      select * into lEmail from Emails_PostBox where rowid = Rec.rowid for update nowait; -- ��������� ������
    exception when no_data_found then continue; -- ���� �� ������ ����� ������ - ��������� � ���������
              when row_locked then continue; -- ���� �� ������ ������������� ������ - ��������� � ���������
    end;  
  
    if lLastProviderID is null or lLastProviderID != lEmail.SMTPProviderID then
      lLastProviderID := lEmail.SMTPProviderID; 
      select * into lProvider from SMTPProviders where ID = lLastProviderID;  
    end if;
    lSendAttempts := lEmail.SendAttempts + 1; -- ����������� ���������� ������� �������� ��������� 
    
    begin    
      send_mail(lProvider.Server, lProvider.Port, lProvider.AuthLogin, lProvider.AuthPassword, case when lProvider.RequireAuth = 1 then true else false end, 
                case when lProvider.UseSSL = 1 then true else false end, lProvider.FromAddress, lProvider.FromName, lEmail.Address, lEmail.Subject, lEmail.Body);
      lResult := 1; -- �������� ������ �������
      lMessage := null;
    exception when others then
      lResult := 0; -- �� ������� ��������� ���������
      lMessage := substr(sqlerrm, 1, 4000);  
    end;
        
    if lResult = 0 and lSendAttempts < lMaxSendAttempts then -- ���� �� ����� � ��� ���� ���������� ������� �������� �� ��������� ������������ 
      update Emails_PostBox set SendAttempts = lSendAttempts, ProcessingDate = sysdate, ProcessingResult = lResult, ProcessingMessage = lMessage where rowid = Rec.rowid;    
    else -- ���� �� �� ������ ��� ���������� ������� �������� ���������
      insert into Emails_Archive (id, creationdate, cardnumber, smtpproviderid, address, subject, body, sendattempts, processingresult, processingmessage)
        values (lEmail.ID, lEmail.CreationDate, lEmail.CardNumber, lEmail.SMTPProviderID, lEmail.Address, lEmail.Subject, lEmail.Body, lSendAttempts, lResult, lMessage);
      delete from Emails_PostBox where rowid = Rec.RowID;     
    end if;
    commit;    
  end loop;
exception when others then opsOnline.Log(substr('ProcessEmails '||sqlerrm, 1, 4000)); -- ���������� � ��� ����� ������  
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
  for Rec in (select rowid from SMS_PostBox order by SMSProviderID, ID) loop -- �������� ������ ��������� ��� ���������
    -- �������� ���������� ���������
    begin
      select * into lSMS from SMS_PostBox where rowid = Rec.rowid for update nowait; -- ��������� ������
    exception when no_data_found then continue; -- ���� �� ������ ����� ������ - ��������� � ���������
              when row_locked then continue; -- ���� �� ������ ������������� ������ - ��������� � ���������
    end;  
  
    if lLastProviderID is null or lLastProviderID != lSMS.SMSProviderID then
      lLastProviderID := lSMS.SMSProviderID; 
      select * into lProvider from SMSProviders where ID = lLastProviderID;  
    end if;
    lSendAttempts := lSMS.SendAttempts + 1; -- ����������� ���������� ������� �������� ��������� 
    
    -- ��� ���������� ���������
    begin    
      send_sms(lProvider.TypeID, lProvider.AuthLogin, lProvider.AuthPassword, lSMS.Phone, lSMS.Message, lProvider.FromName);
      lResult := 1; -- �������� ������ �������
      lMessage := null;
    exception when others then
      lResult := 0; -- �� ������� ��������� ���������
      lMessage := substr(sqlerrm, 1, 4000);  
    end;
    
    if lResult = 0 and lSendAttempts < lMaxSendAttempts then -- ���� �� ����� � ��� ���� ���������� ������� �������� �� ��������� ������������ 
      update SMS_PostBox set SendAttempts = lSendAttempts, ProcessingDate = sysdate, ProcessingResult = lResult, ProcessingMessage = lMessage where rowid = Rec.rowid;    
    else -- ���� �� �� ������ ��� ���������� ������� �������� ���������
      insert into SMS_Archive (id, creationdate, cardnumber, smsproviderid, phone, message, sendattempts, processingresult, processingmessage)
        values (lSMS.ID, lSMS.CreationDate, lSMS.CardNumber, lSMS.SMSProviderID, lSMS.Phone, lSMS.Message, lSendAttempts, lResult, lMessage);
      delete from SMS_PostBox where rowid = Rec.RowID;     
    end if;
    commit;    
  end loop;
exception when others then opsOnline.Log(substr('ProcessSMS '||sqlerrm, 1, 4000)); -- ���������� � ��� ����� ������  
end;


procedure Process is
begin
  ProcessRefusalNotifications;
  ProcessEmails;
  ProcessSMS; 
end;

end;
/