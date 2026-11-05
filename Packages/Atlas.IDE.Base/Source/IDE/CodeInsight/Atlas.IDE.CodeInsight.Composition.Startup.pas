unit Atlas.IDE.CodeInsight.Composition.Startup;

// Abgesicherter Start nach einem Absturz (#722) mit Stufe und Startmarke, Startanteile bis zur freien
// Nachrichtenschleife (Bericht N4) und die Sprache der IDE (#446).

interface

uses
  Atlas.Core.Localization.Language,
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
/// <summary>Sprache der IDE (#446) wie TAtlasIdeLanguage.Decide: geladene Ressourcen-DLLs der IDE, Eintrag für
/// bds.exe unter Software\Embarcadero\Locales, Sprache der Windows-Oberfläche; Rückfall Englisch.</summary>
function IdeLanguage: TAtlasIdeLanguage;

implementation

uses
  Winapi.Windows,
  Winapi.PsAPI,
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

/// <summary>Sprachkennung für bds.exe unter Software\Embarcadero\Locales; '' ohne Eintrag. Wie die RTL beim
/// Laden der Ressourcen: zuerst HKCU, dann HKLM.</summary>
function RegisteredLanguage: string;
const
  cRoots: array[0..1] of HKEY = (HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE);
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mName: string;
  mRoot: HKEY;
begin
  Result := '';
  mRegistry := TRegistry.Create(KEY_READ);
  mNames := TStringList.Create;
  try
    for mRoot in cRoots do
    begin
      mRegistry.RootKey := mRoot;
      if mRegistry.OpenKeyReadOnly('Software\Embarcadero\Locales') then
      begin
        mNames.Clear;
        mRegistry.GetValueNames(mNames);
        for mName in mNames do
        begin
          if SameText(mName, ParamStr(0)) and (mRegistry.GetDataType(mName) = rdString) then
          begin
            Result := mRegistry.ReadString(mName);
          end;
        end;
        mRegistry.CloseKey;
      end;
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

/// <summary>Datei einer Ressourcen-DLL. Die RTL lädt sie als Datendatei (LOAD_LIBRARY_AS_DATAFILE); für solche
/// Handles liefert GetModuleFileName nichts, der Name der eingeblendeten Datei steht dann bei GetMappedFileName.
/// </summary>
function ResourceFileName(AInstance: HINST): string;
var
  mBuffer: array[0..MAX_PATH] of Char;
  mLength: DWORD;
begin
  Result := GetModuleName(AInstance);
  if Result = '' then
  begin
    mLength := GetMappedFileName(GetCurrentProcess, Pointer(AInstance and not HINST(3)), @mBuffer[0], MAX_PATH);
    SetString(Result, mBuffer, mLength);
  end;
end;

/// <summary>Endungen der Ressourcen-DLLs, die die RTL für die geladenen Module der IDE gewählt hat
/// (coreide370.de → „de“): Das ist die Sprache, die die IDE tatsächlich zeigt. Leer, wenn kein Modul eine
/// eigene Ressourcen-DLL hat (englische IDE).</summary>
function ResourceCodes: TArray<string>;
var
  mModule: PLibModule;
  mCode: string;
begin
  Result := nil;
  mModule := LibModuleList;
  while mModule <> nil do
  begin
    if (mModule.ResInstance <> 0) and (mModule.ResInstance <> mModule.Instance) then
    begin
      mCode := Copy(ExtractFileExt(ResourceFileName(mModule.ResInstance)), 2, MaxInt);
      if mCode <> '' then
      begin
        Result := Result + [mCode];
      end;
    end;
    mModule := mModule.Next;
  end;
end;

function IdeLanguage: TAtlasIdeLanguage;
begin
  Result := TAtlasIdeLanguage.Decide(ResourceCodes, RegisteredLanguage,
    (GetUserDefaultUILanguage and $3FF) = LANG_GERMAN);
end;

end.
