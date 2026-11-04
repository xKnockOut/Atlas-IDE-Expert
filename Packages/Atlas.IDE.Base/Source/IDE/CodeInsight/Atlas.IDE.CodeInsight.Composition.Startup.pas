unit Atlas.IDE.CodeInsight.Composition.Startup;

// Abgesicherter Start nach einem Absturz (#722) mit Stufe und Startmarke, Startanteile bis zur freien
// Nachrichtenschleife (Bericht N4) und die Sprache der IDE (#446).

interface

uses
  Atlas.UI.Strings,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Diagnostics.StartTimes,
  Atlas.IDE.Diagnostics.SafeMode;

/// <summary>Hinweis des abgesicherten Starts; nil vor StartSafeMode.</summary>
function SafeMode: TAtlasIdeSafeMode;
/// <summary>Stufe des abgesicherten Starts (#722); ohne Sicherung normal.</summary>
function Level: TAtlasSafeLevel;
/// <summary>Hinweis des abgesicherten Starts (#722) samt Statuszeile; die Stufe bestimmt RegisterFeatures.</summary>
procedure StartSafeMode;
/// <summary>Sauberes Ende: Startmarke löschen, Absturzzähler zurück (#722).</summary>
procedure StopSafeMode;
/// <summary>Startanteile von Atlas bis zur freien Nachrichtenschleife; nil davor und danach.</summary>
function StartTimes: TAtlasStartTimes;
/// <summary>Startanteile ab dem Laden zählen; Zeitpunkt des Ladens merken.</summary>
procedure StartStartTimes;
/// <summary>Startanteile freigeben (TAtlasActivity und Feature-Tabelle zählen dann schon nicht mehr mit).</summary>
procedure FreeStartTimes;
/// <summary>Zeitpunkt des Ladens (TAtlasWatchdog.Timestamp) für Ladezeit und Startanteile.</summary>
function LoadedAt: Int64;
/// <summary>Sprache der IDE (#446): Eintrag für bds.exe unter HKCU\Software\Embarcadero\Locales (von
/// BDSSetLang), sonst Sprache der Windows-Oberfläche; Rückfall Englisch.</summary>
function IdeLanguage: TAtlasLanguage;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Diagnostics.Watchdog,
  Atlas.IDE.Diagnostics.Export,
  Atlas.Core.Status.Registry,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status;

var
  // Abgesicherter Start nach einem Absturz (#722).
  SafeModeInstance: TAtlasIdeSafeMode;
  LoadedAtStamp: Int64;
  // Startanteile von Atlas bis zur freien Nachrichtenschleife (Bericht N4); danach nil.
  StartTimesInstance: TAtlasStartTimes;

function SafeMode: TAtlasIdeSafeMode;
begin
  Result := SafeModeInstance;
end;

function Level: TAtlasSafeLevel;
begin
  Result := TAtlasSafeLevel.Normal;
  if SafeModeInstance <> nil then
  begin
    Result := SafeModeInstance.Level;
  end;
end;

/// <summary>Fehler je Feature (#493) in die Startmarke.</summary>
procedure RecordFailure(AFeature: TAtlasFeature);
begin
  if SafeModeInstance <> nil then
  begin
    SafeModeInstance.RecordFailure(AFeature);
  end;
end;

procedure ShowToggles;
begin
  if QuickToggles <> nil then
  begin
    QuickToggles.Show;
  end;
end;

procedure ExportLog;
begin
  TAtlasIdeDiagnosticExport.Execute(Warnings());
end;

procedure StartSafeMode;
begin
  SafeModeInstance := TAtlasIdeSafeMode.Create(nil);
  SafeModeInstance.OnShowToggles := ShowToggles;
  SafeModeInstance.OnExportLog := ExportLog;
  SafeModeInstance.OnBugReport := CreateBugReport;
  SafeModeInstance.Start(TAtlasIdeSafeMode.DefaultFolder, TAtlasStatusRegistry.Default);
  TAtlasGuard.OnFailure := RecordFailure;
end;

procedure StopSafeMode;
begin
  if SafeModeInstance <> nil then
  begin
    SafeModeInstance.Stop;
  end;
  FreeAndNil(SafeModeInstance);
end;

function StartTimes: TAtlasStartTimes;
begin
  Result := StartTimesInstance;
end;

procedure StartStartTimes;
begin
  LoadedAtStamp := TAtlasWatchdog.Timestamp;
  StartTimesInstance := TAtlasStartTimes.Create;
end;

procedure FreeStartTimes;
begin
  FreeAndNil(StartTimesInstance);
end;

function LoadedAt: Int64;
begin
  Result := LoadedAtStamp;
end;

/// <summary>Sprachkennung für bds.exe aus HKCU\Software\Embarcadero\Locales; '' ohne Eintrag.</summary>
function RegisteredLanguage: string;
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mName: string;
begin
  Result := '';
  mRegistry := TRegistry.Create(KEY_READ);
  mNames := TStringList.Create;
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKeyReadOnly('Software\Embarcadero\Locales') then
    begin
      mRegistry.GetValueNames(mNames);
      for mName in mNames do
      begin
        if SameText(mName, ParamStr(0)) and (mRegistry.GetDataType(mName) = rdString) then
        begin
          Result := mRegistry.ReadString(mName);
        end;
      end;
    end;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

function IdeLanguage: TAtlasLanguage;
var
  mCode: string;
begin
  mCode := RegisteredLanguage;
  if (mCode = '') and ((GetUserDefaultUILanguage and $3FF) = LANG_GERMAN) then
  begin
    mCode := 'DE';
  end;
  if SameText(mCode, 'DE') then
  begin
    Result := TAtlasLanguage.German;
  end
  else
  begin
    Result := TAtlasLanguage.English;
  end;
end;

end.
