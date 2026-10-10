unit Argus.IDE.CodeInsight.Composition;

// Meldet den Code Insight-Manager, die Optionsseite "Argus" (#227), die
// Compile-Ereignisse (#527) und den Einfrier-Wächter (#501) beim Laden des
// Packages an und beim Entladen in umgekehrter Reihenfolge wieder ab (ADR 0006).

interface

procedure Register;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  System.JSON,
  ToolsAPI,
  Argus.UI.Strings,
  Argus.Core.Build.Events,
  Argus.IDE.CodeInsight.Manager,
  Argus.IDE.Settings.Options,
  Argus.IDE.Completion.History,
  Argus.IDE.Build.Notifier,
  Argus.Core.Diagnostics.Hangs,
  Argus.IDE.Settings.Store,
  Argus.IDE.Diagnostics.Watchdog;

var
  ManagerIndex: Integer = -1;
  // Gehört der IDE (Schnittstellenzähler); gültig, solange er angemeldet ist.
  Manager: TArgusCodeInsightManager;
  Compile: TArgusIdeCompileEvents;
  Watchdog: TArgusWatchdog;
  Hangs: TArgusHangMonitor;

const
  // Ab dieser Dauer ein Hinweis im Meldungsfenster (#501).
  HangHintMs = 2000;

procedure ReportHang(const AHang: TArgusHang);
var
  Hang: TArgusHang;
  Text, Activity: string;
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if (Hangs = nil) or (Manager = nil) then
    Exit;
  Hang := AHang;
  if Compile <> nil then
  begin
    Hang.CodeInsightCount := Compile.Events.CodeInsightCount;
    Hang.CodeInsightMs := Compile.Events.CodeInsightMs;
  end;
  Hangs.ThresholdMs := TArgusIdeSettings.Current.HangThresholdMs;
  Text := Hangs.Finish(Hang);
  if Text = '' then
    Exit;
  Manager.Report(Text);
  if not TArgusIdeSettings.Current.HangHint or (Hang.DurationMs < HangHintMs) or
    not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Activity := '';
  if Hang.Activity <> '' then
    Activity := ' (' + Hang.Activity + ')';
  Group := Messages.GetGroup('Argus');
  if Group = nil then
    Group := Messages.AddMessageGroup('Argus');
  // Nie als Dialog und ohne das Meldungsfenster nach vorn zu holen.
  Messages.AddTitleMessage(TArgusStrings.Fmt(TArgusTextId.HangHint, [Hang.DurationMs, Activity]), Group);
end;

procedure RegisterWatchdog(ALoadedAt: Int64);
begin
  Hangs := TArgusHangMonitor.Create(TArgusIdeSettings.Current.HangThresholdMs);
  Watchdog := TArgusWatchdog.Create(ALoadedAt,
    function: Integer
    begin
      Result := TArgusIdeSettings.Current.HangThresholdMs;
    end);
  Watchdog.OnHang := ReportHang;
  Watchdog.OnStartup :=
    procedure(AMilliseconds: Int64)
    begin
      if Manager <> nil then
        Manager.Log(Format('Start: Laden des Packages bis zur freien Nachrichtenschleife %d ms', [AMilliseconds]));
    end;
end;

procedure UnregisterWatchdog;
begin
  FreeAndNil(Watchdog);
  if (Hangs <> nil) and (Hangs.Count > 0) and (Manager <> nil) then
    Manager.Report(Hangs.Summary);
  FreeAndNil(Hangs);
end;

procedure LogLine(const AText: string);
begin
  if Manager <> nil then
    Manager.Log(AText);
end;

procedure RegisterCompileEvents;
var
  Events: TArgusCompileEvents;
begin
  Events := TArgusCompileEvents.Create;
  Events.OnNotify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      if Manager <> nil then
        Manager.NotifyServer(AMethod, AParams)
      else
        AParams.Free;
    end;
  Events.OnLog := LogLine;
  Events.Add(TArgusCompileLog.Create(Events, LogLine));
  Compile := TArgusIdeCompileEvents.Create(Events);
end;

/// <summary>Sprache der IDE (#446): Eintrag für bds.exe unter HKCU\Software\Embarcadero\Locales (von
/// BDSSetLang), sonst Sprache der Windows-Oberfläche; Rückfall Englisch.</summary>
function IdeLanguage: TArgusLanguage;
var
  Registry: TRegistry;
  Names: TStringList;
  Name, Code: string;
begin
  Code := '';
  Registry := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKeyReadOnly('Software\Embarcadero\Locales') then
    begin
      Registry.GetValueNames(Names);
      for Name in Names do
        if SameText(Name, ParamStr(0)) and (Registry.GetDataType(Name) = rdString) then
          Code := Registry.ReadString(Name);
    end;
  finally
    Names.Free;
    Registry.Free;
  end;
  if Code = '' then
    if (GetUserDefaultUILanguage and $3FF) = LANG_GERMAN then
      Code := 'DE';
  if SameText(Code, 'DE') then
    Result := TArgusLanguage.German
  else
    Result := TArgusLanguage.English;
end;

procedure Register;
var
  Services: IOTACodeInsightServices;
  LoadedAt: Int64;
begin
  LoadedAt := TArgusWatchdog.Timestamp;
  TArgusStrings.Language := IdeLanguage;
  if (ManagerIndex < 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
  begin
    Manager := TArgusCodeInsightManager.Create;
    ManagerIndex := Services.AddCodeInsightManager(Manager);
  end;
  if Compile = nil then
    RegisterCompileEvents;
  if Watchdog = nil then
    RegisterWatchdog(LoadedAt);
  TArgusOptionsRegistration.Register(
    procedure
    begin
      TArgusIdeHistory.Reset;
    end);
end;

procedure Unregister;
var
  Services: IOTACodeInsightServices;
begin
  UnregisterWatchdog;
  FreeAndNil(Compile);
  TArgusOptionsRegistration.Unregister;
  TArgusIdeHistory.Release;
  if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.RemoveCodeInsightManager(ManagerIndex);
  ManagerIndex := -1;
  Manager := nil;
end;

initialization

finalization
  Unregister;

end.
