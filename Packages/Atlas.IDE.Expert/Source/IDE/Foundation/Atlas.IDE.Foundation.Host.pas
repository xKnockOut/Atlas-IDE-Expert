unit Atlas.IDE.Foundation.Host;

// Dienste von Base für die Module (#1455, ADR 0017): laufende Serversitzung,
// Meldungsansicht „Atlas“ und Diagnoselog. Die Kompositionswurzel setzt die
// Quellen beim Start (Install) und nimmt sie beim Entladen zurück
// (Uninstall); danach liefern sie nil bzw. tun nichts. Ein Modul fragt die
// Sitzung bei jedem Aufruf neu, statt sie zu speichern: Der Server kann
// neu starten.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session;

type
  TAtlasIdeHost = class
  private class var
    FSession: TFunc<TLspSession>;
    FLog: TProc<string>;
  public
    /// <summary>Quellen setzen; ASession liefert nil, solange kein Server läuft.</summary>
    class procedure Install(const ASession: TFunc<TLspSession>; const ALog: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Laufende Serversitzung; nil ohne Server oder nach Uninstall.</summary>
    class function RunningSession: TLspSession; static;
    /// <summary>Zeile in der Meldungsansicht der IDE, Gruppe „Atlas“.</summary>
    class procedure Message(const AText: string); static;
    /// <summary>Zeile im Diagnoselog des Servers; ohne Server nichts.</summary>
    class procedure Log(const AText: string); static;
  end;

implementation

uses
  ToolsAPI;

class procedure TAtlasIdeHost.Install(const ASession: TFunc<TLspSession>; const ALog: TProc<string>);
begin
  FSession := ASession;
  FLog := ALog;
end;

class procedure TAtlasIdeHost.Uninstall;
begin
  FSession := nil;
  FLog := nil;
end;

class function TAtlasIdeHost.RunningSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSession) then
    Result := FSession();
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

class procedure TAtlasIdeHost.Log(const AText: string);
begin
  if Assigned(FLog) then
    FLog(AText);
end;

end.
