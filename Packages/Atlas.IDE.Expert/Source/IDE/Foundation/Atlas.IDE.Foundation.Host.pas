unit Atlas.IDE.Foundation.Host;

// Dienste von Base für die Module (#1455, ADR 0017): Serversitzung (laufend
// bzw. bei Bedarf gestartet), Befehle im Hintergrund an den Server,
// Meldungsansicht „Atlas“, Warnungen, Diagnoselog und Felder im
// Atlas-Statusfeld. Die Kompositionswurzel setzt die Quellen beim Start
// (Install) und nimmt sie beim Entladen zurück (Uninstall); danach liefern
// sie nil bzw. tun nichts. Ein Modul fragt die Sitzung bei jedem Aufruf
// neu, statt sie zu speichern: Der Server kann neu starten.
// Antworten des Servers erreichen das Modul nur, solange sein Scope offen
// ist (Regel 3, TAtlasModuleAnswer), und immer im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Lsp.Session;

type
  /// <summary>Befehl mit Argumenten (JSON-Array) im Hintergrund an den laufenden Server; ADone bekommt das
  /// Ergebnis als JSON ('' bei Fehler oder Zeitlimit) in einem beliebigen Thread. False = nicht gestartet (kein
  /// Server oder schon ein Befehl unterwegs).</summary>
  TAtlasHostCommandRunner = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  /// <summary>Quellen der Dienste; jedes Feld darf fehlen.</summary>
  TAtlasHostServices = record
    /// <summary>Laufende Sitzung, startet keinen Server.</summary>
    Session: TFunc<TLspSession>;
    /// <summary>Sitzung, Server bei Bedarf gestartet (Hauptthread).</summary>
    ActiveSession: TFunc<TLspSession>;
    Log: TProc<string>;
    /// <summary>Warnung an Benutzer (Meldungsansicht und Bericht des Managers).</summary>
    Warning: TProc<string>;
    RunCommand: TAtlasHostCommandRunner;
    /// <summary>Feld mit Id und Text im Atlas-Statusfeld; leerer Text entfernt es.</summary>
    StatusExtra: TProc<string, string>;
  end;

  TAtlasIdeHost = class
  private class var
    FServices: TAtlasHostServices;
  public
    class procedure Install(const AServices: TAtlasHostServices); static;
    class procedure Uninstall; static;
    /// <summary>Laufende Serversitzung; nil ohne Server oder nach Uninstall.</summary>
    class function RunningSession: TLspSession; static;
    /// <summary>Sitzung, Server bei Bedarf gestartet; nil, wenn er nicht startet. Nur im Hauptthread.</summary>
    class function ActiveSession: TLspSession; static;
    /// <summary>Zeile in der Meldungsansicht der IDE, Gruppe „Atlas“.</summary>
    class procedure Message(const AText: string); static;
    /// <summary>Warnung wie die der Sicherung: Meldungsansicht und Bericht; vor Install nur die Meldungsansicht.</summary>
    class procedure Warning(const AText: string); static;
    /// <summary>Zeile im Diagnoselog des Servers; ohne Server nichts.</summary>
    class procedure Log(const AText: string); static;
    /// <summary>Feld AId im Atlas-Statusfeld setzen; leerer Text entfernt es.</summary>
    class procedure SetStatusExtra(const AId, AText: string); static;
    /// <summary>Befehl im Hintergrund an den laufenden Server. ADone läuft im Hauptthread, gesichert über AFeature,
    /// und nur, solange AScope offen ist. False = nicht gestartet.</summary>
    class function RunCommandAsync(const AScope: IAtlasModuleScope; AFeature: TAtlasFeature;
      const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean; static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Modules.Answer;

class procedure TAtlasIdeHost.Install(const AServices: TAtlasHostServices);
begin
  FServices := AServices;
end;

class procedure TAtlasIdeHost.Uninstall;
begin
  FServices := Default(TAtlasHostServices);
end;

class function TAtlasIdeHost.RunningSession: TLspSession;
begin
  Result := nil;
  if Assigned(FServices.Session) then
    Result := FServices.Session();
end;

class function TAtlasIdeHost.ActiveSession: TLspSession;
begin
  Result := nil;
  if Assigned(FServices.ActiveSession) then
    Result := FServices.ActiveSession();
end;

class procedure TAtlasIdeHost.Message(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
    Exit;
  mGroup := mMessages.GetGroup('Atlas');
  if mGroup = nil then
    mGroup := mMessages.AddMessageGroup('Atlas');
  mMessages.AddTitleMessage(AText, mGroup);
end;

class procedure TAtlasIdeHost.Warning(const AText: string);
begin
  if Assigned(FServices.Warning) then
    FServices.Warning(AText)
  else
    Message(AText);
end;

class procedure TAtlasIdeHost.Log(const AText: string);
begin
  if Assigned(FServices.Log) then
    FServices.Log(AText);
end;

class procedure TAtlasIdeHost.SetStatusExtra(const AId, AText: string);
begin
  if Assigned(FServices.StatusExtra) then
    FServices.StatusExtra(AId, AText);
end;

/// <summary>Weiterreichen in den Hauptthread; eigene Routine, damit der Rahmen nur die Antwort hält.</summary>
function DeliverInMainThread(const AAnswer: IAtlasModuleAnswer; AFeature: TAtlasFeature): TProc<string>;
begin
  Result :=
    procedure(AText: string)
    var
      mText: string;
    begin
      mText := AText;
      TAtlasMainThread.Queue(AFeature,
        procedure
        begin
          AAnswer.Deliver(mText);
        end);
    end;
end;

class function TAtlasIdeHost.RunCommandAsync(const AScope: IAtlasModuleScope; AFeature: TAtlasFeature;
  const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean;
var
  mAnswer: IAtlasModuleAnswer;
begin
  Result := False;
  if not Assigned(FServices.RunCommand) or (AScope = nil) or not AScope.IsOpen then
    Exit;
  mAnswer := TAtlasModuleAnswer.Open(AScope, ADone);
  Result := FServices.RunCommand(ACommand, AArgumentsJson, ATimeoutMs, DeliverInMainThread(mAnswer, AFeature));
  // Nicht gestartet: Der Rückruf des Moduls kommt nie, also gleich lösen.
  if not Result then
    mAnswer.Revoke;
end;

end.
