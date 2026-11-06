unit Atlas.IDE.Diagnostics.KnownPackages;

// Module unter „Known Packages“ der IDE (Meldung vom 05.11.2026: zwischen 05:34
// und 06:31 stand dort nur noch Base, die 11 Module fehlten; Ursache offen):
// - Start: Die Liste der IDE (HKCU\<GetBaseRegistryKey>\Known Packages, die
//   64-Bit-IDE „… x64“) wird mit den Modul-BPLs im Ordner von Base verglichen
//   (TAtlasKnownPackages.Check). Das Ergebnis steht im Protokoll, dazu die Zahl
//   der übrigen laufenden bds.exe. Fehlen Module, meldet die
//   Benachrichtigungszentrale das mit „Wieder eintragen“ (Quelle packages).
//   Von selbst trägt Atlas nichts ein: Ein Modul kann absichtlich entfernt
//   sein (Komponente › Packages installieren, Auswahl im Updater).
// - Wieder eintragen schreibt die fehlenden Werte (Pfad, „Atlas <Name>“);
//   die IDE lädt die Module beim nächsten Start.
// - Beobachtung: Ein Thread wartet mit RegNotifyChangeKeyValue auf Änderungen
//   der Liste und protokolliert, welche Atlas-Einträge wegfallen oder
//   dazukommen, mit der Zahl der in dieser IDE angemeldeten Module und der
//   übrigen bds.exe. Fallen Einträge weg, während hier alle Module angemeldet
//   bleiben, hat ein anderer Prozess die Liste geschrieben.
// - Stop: Stand der Liste beim Entladen ins Protokoll. Fehlt beim nächsten
//   Start etwas, das hier noch stand, hat danach jemand geschrieben.
// Nur Modulnamen ins Protokoll, keine Pfade.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Modules.KnownPackages;

type
  TAtlasIdeKnownPackages = class
  private type
    /// <summary>Wartet auf Änderungen der Liste; schreibt nur ins Protokoll.</summary>
    TWatcher = class(TThread)
    private
      FKey: string;
      FStop: TEvent;
      FLast: TArray<string>;
      procedure Changed;
    protected
      procedure Execute; override;
    public
      constructor Create(const AKey: string; const AInitial: TArray<string>);
      destructor Destroy; override;
      procedure Shutdown;
    end;
  private
    FRegistryKey: string;
    FBaseFile: string;
    FState: TAtlasKnownPackagesState;
    FWatcher: TWatcher;
    function Input: TAtlasKnownPackagesInput;
    procedure Notify;
    /// <summary>Knopf „Wieder eintragen“: hängt nicht an dieser Instanz, der Eintrag der Zentrale kann sie
    /// überleben.</summary>
    class function RestoreAction(const AKey: string; const AMissing: TArray<string>): TProc; static;
    class procedure Restore(const AKey: string; const AMissing: TArray<string>); static;
    class function WriteMissing(const AKey: string; const AMissing: TArray<string>): Boolean; static;
    class function OtherIdes: Integer; static;
    class function ModuleCount: Integer; static;
  public
    /// <summary>ARegistryKey: IOTAServices.GetBaseRegistryKey; ABaseFile: Pfad der BPL von Base.</summary>
    constructor Create(const ARegistryKey, ABaseFile: string);
    destructor Destroy; override;
    /// <summary>Prüfen, protokollieren, bei fehlenden Modulen melden, Beobachtung starten.</summary>
    procedure Start;
    /// <summary>„Known Packages“ bzw. „Known Packages x64“ unter ARegistryKey, je nach IDE.</summary>
    class function KnownKey(const ARegistryKey: string): string; static;
    class function DisabledKey(const ARegistryKey: string): string; static;
    /// <summary>Wertnamen eines Schlüssels unter HKCU, Makros über die Umgebung aufgelöst; leer ohne Schlüssel.
    /// </summary>
    class function ValuesOf(const AKey: string): TArray<string>; static;
    property State: TAtlasKnownPackagesState read FState;
  end;

/// <summary>Für die Feature-Tabelle: Prüfung und Beobachtung starten bzw. beenden.</summary>
procedure StartKnownPackages;
procedure StopKnownPackages;
function KnownPackagesStarted: Boolean;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,
  System.Win.Registry,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Localization.Language,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Projects.PathCheck,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TKnownPackagesText = (Title, Text, Restore, DoneTitle, DoneText, Failed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TKnownPackagesText] of string = (
    ('Atlas-Module fehlen in der IDE',
     'Die Module %s stehen nicht mehr unter „Known Packages“ der IDE und werden nicht geladen.',
     'Wieder eintragen',
     'Atlas-Module wieder eingetragen',
     'Die IDE lädt %s beim nächsten Start.',
     'Eintragen fehlgeschlagen: %s'),
    ('Atlas modules missing from the IDE',
     'The modules %s are no longer listed under "Known Packages" of the IDE and are not loaded.',
     'Register again',
     'Atlas modules registered again',
     'The IDE loads %s on its next start.',
     'Registering failed: %s'));

  // Warten auf Änderungen der Liste (RegNotifyChangeKeyValue): Namen und Werte.
  cNotifyFilter = REG_NOTIFY_CHANGE_NAME or REG_NOTIFY_CHANGE_LAST_SET;

var
  Instance: TAtlasIdeKnownPackages;

function UiText(AId: TKnownPackagesText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

function EnvironmentValue(const AName: string): string;
begin
  Result := System.SysUtils.GetEnvironmentVariable(AName);
end;

/// <summary>Wertname mit aufgelösten Makros ($(BDSCOMMONDIR) setzt die IDE in ihre Umgebung); mit unbekanntem
/// Makro unverändert.</summary>
function Expanded(const AValue: string): string;
begin
  Result := TAtlasPathCheck.ExpandPath(AValue, '', EnvironmentValue);
  if Result = '' then
  begin
    Result := AValue;
  end;
end;

{ TAtlasIdeKnownPackages.TWatcher }

constructor TAtlasIdeKnownPackages.TWatcher.Create(const AKey: string; const AInitial: TArray<string>);
begin
  FKey := AKey;
  FLast := AInitial;
  FStop := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TAtlasIdeKnownPackages.TWatcher.Destroy;
begin
  FStop.Free;
  FLast := nil;
  inherited;
end;

procedure TAtlasIdeKnownPackages.TWatcher.Shutdown;
begin
  Terminate;
  FStop.SetEvent;
  WaitFor;
end;

procedure TAtlasIdeKnownPackages.TWatcher.Changed;
var
  mNow: TArray<string>;
  mChange: TAtlasKnownPackagesChange;
begin
  mNow := TAtlasIdeKnownPackages.ValuesOf(FKey);
  mChange := TAtlasKnownPackages.Compare(FLast, mNow);
  FLast := mNow;
  if mChange.IsEmpty then
  begin
    Exit;
  end;
  TAtlasGuard.Log(Format('Known Packages geändert: entfernt %s; neu %s; in dieser IDE %d Module angemeldet, ' + // german-ok Protokoll
    'andere bds.exe: %d', [TAtlasKnownPackages.Names(mChange.Removed), TAtlasKnownPackages.Names(mChange.Added),
    TAtlasIdeKnownPackages.ModuleCount, TAtlasIdeKnownPackages.OtherIdes]));
end;

procedure TAtlasIdeKnownPackages.TWatcher.Execute;
var
  mKey: HKEY;
  mChanged: TEvent;
  mHandles: array[0..1] of THandle;
begin
  if RegOpenKeyEx(HKEY_CURRENT_USER, PChar(FKey), 0, KEY_NOTIFY or KEY_READ, mKey) <> ERROR_SUCCESS then
  begin
    TAtlasGuard.Log('Known Packages: Schlüssel lässt sich nicht beobachten'); // german-ok Protokoll
    Exit;
  end;
  mChanged := TEvent.Create(nil, False, False, '');
  try
    mHandles[0] := FStop.Handle;
    mHandles[1] := mChanged.Handle;
    while not Terminated do
    begin
      if RegNotifyChangeKeyValue(mKey, False, cNotifyFilter, mChanged.Handle, True) <> ERROR_SUCCESS then
      begin
        Break;
      end;
      if WaitForMultipleObjects(2, @mHandles, False, INFINITE) <> WAIT_OBJECT_0 + 1 then
      begin
        Break;
      end;
      Changed;
    end;
  finally
    mChanged.Free;
    RegCloseKey(mKey);
  end;
end;

{ TAtlasIdeKnownPackages }

constructor TAtlasIdeKnownPackages.Create(const ARegistryKey, ABaseFile: string);
begin
  inherited Create;
  FRegistryKey := ARegistryKey;
  FBaseFile := ABaseFile;
end;

destructor TAtlasIdeKnownPackages.Destroy;
begin
  if FWatcher <> nil then
  begin
    FWatcher.Shutdown;
    FreeAndNil(FWatcher);
    TAtlasGuard.Log(TAtlasKnownPackages.Report(TAtlasKnownPackages.Check(Input)) + ' (beim Entladen)'); // german-ok Protokoll
  end;
  FState := Default(TAtlasKnownPackagesState);
  inherited;
end;

class function TAtlasIdeKnownPackages.KnownKey(const ARegistryKey: string): string;
begin
{$IFDEF WIN64}
  Result := ARegistryKey + '\Known Packages x64';
{$ELSE}
  Result := ARegistryKey + '\Known Packages';
{$ENDIF}
end;

class function TAtlasIdeKnownPackages.DisabledKey(const ARegistryKey: string): string;
begin
{$IFDEF WIN64}
  Result := ARegistryKey + '\Disabled Packages x64';
{$ELSE}
  Result := ARegistryKey + '\Disabled Packages';
{$ENDIF}
end;

class function TAtlasIdeKnownPackages.ValuesOf(const AKey: string): TArray<string>;
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mIndex: Integer;
begin
  Result := nil;
  mRegistry := TRegistry.Create(KEY_READ);
  mNames := TStringList.Create;
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if not mRegistry.OpenKeyReadOnly(AKey) then
    begin
      Exit;
    end;
    mRegistry.GetValueNames(mNames);
    SetLength(Result, mNames.Count);
    for mIndex := 0 to mNames.Count - 1 do
    begin
      Result[mIndex] := Expanded(mNames[mIndex]);
    end;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

function TAtlasIdeKnownPackages.Input: TAtlasKnownPackagesInput;
var
  mFolder: string;
begin
  Result := Default(TAtlasKnownPackagesInput);
  Result.BaseFile := FBaseFile;
  mFolder := ExtractFileDir(FBaseFile);
  if (mFolder <> '') and TDirectory.Exists(mFolder) then
  begin
    Result.Files := TDirectory.GetFiles(mFolder, '*.bpl');
  end;
  Result.Known := ValuesOf(KnownKey(FRegistryKey));
  Result.Disabled := ValuesOf(DisabledKey(FRegistryKey));
end;

class function TAtlasIdeKnownPackages.OtherIdes: Integer;
var
  mSnapshot: THandle;
  mEntry: TProcessEntry32;
begin
  Result := 0;
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    mEntry := Default(TProcessEntry32);
    mEntry.dwSize := SizeOf(mEntry);
    if not Process32First(mSnapshot, mEntry) then
    begin
      Exit;
    end;
    repeat
      if SameText(string(mEntry.szExeFile), 'bds.exe') and (mEntry.th32ProcessID <> GetCurrentProcessId) then
      begin
        Inc(Result);
      end;
    until not Process32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

class function TAtlasIdeKnownPackages.ModuleCount: Integer;
var
  mRegistry: IAtlasModuleRegistry;
begin
  mRegistry := AtlasModuleRegistry;
  Result := 0;
  if mRegistry <> nil then
  begin
    Result := Length(mRegistry.Modules);
  end;
end;

procedure TAtlasIdeKnownPackages.Start;
var
  mInput: TAtlasKnownPackagesInput;
begin
  mInput := Input;
  FState := TAtlasKnownPackages.Check(mInput);
  TAtlasGuard.Log(Format('%s; andere bds.exe: %d', [TAtlasKnownPackages.Report(FState), OtherIdes]));
  if not FState.IsComplete then
  begin
    Notify;
  end;
  FWatcher := TWatcher.Create(KnownKey(FRegistryKey), mInput.Known);
end;

procedure TAtlasIdeKnownPackages.Notify;
begin
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Packages, TAtlasNotificationSeverity.Warning,
    UiText(TKnownPackagesText.Title), Format(UiText(TKnownPackagesText.Text),
    [TAtlasKnownPackages.Names(FState.Missing)]), [TAtlasNotificationCenter.Action(UiText(TKnownPackagesText.Restore),
    RestoreAction(KnownKey(FRegistryKey), FState.Missing))]);
end;

class function TAtlasIdeKnownPackages.RestoreAction(const AKey: string; const AMissing: TArray<string>): TProc;
var
  mKey: string;
  mMissing: TArray<string>;
begin
  mKey := AKey;
  mMissing := AMissing;
  Result :=
    procedure
    begin
      Restore(mKey, mMissing);
    end;
end;

class function TAtlasIdeKnownPackages.WriteMissing(const AKey: string; const AMissing: TArray<string>): Boolean;
var
  mRegistry: TRegistry;
  mFile: string;
begin
  mRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    Result := mRegistry.OpenKey(AKey, False);
    if not Result then
    begin
      Exit;
    end;
    for mFile in AMissing do
    begin
      mRegistry.WriteString(mFile, TAtlasKnownPackages.Description(mFile));
    end;
  finally
    mRegistry.Free;
  end;
end;

class procedure TAtlasIdeKnownPackages.Restore(const AKey: string; const AMissing: TArray<string>);
var
  mNames, mError: string;
begin
  mNames := TAtlasKnownPackages.Names(AMissing);
  mError := '';
  try
    if not WriteMissing(AKey, AMissing) then
    begin
      mError := 'Known Packages';
    end;
  except
    on mFailure: Exception do
      mError := mFailure.Message;
  end;
  if mError <> '' then
  begin
    TAtlasGuard.Log('Known Packages: Wieder eintragen fehlgeschlagen: ' + TAtlasGuard.MessageText(mError));
    TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Packages, TAtlasNotificationSeverity.Error,
      UiText(TKnownPackagesText.Title), Format(UiText(TKnownPackagesText.Failed), [mError]));
    Exit;
  end;
  TAtlasGuard.Log('Known Packages: wieder eingetragen: ' + mNames);
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Packages, TAtlasNotificationSeverity.Info,
    UiText(TKnownPackagesText.DoneTitle), Format(UiText(TKnownPackagesText.DoneText), [mNames]));
end;

procedure StartKnownPackages;
var
  mServices: IOTAServices;
begin
  if (Instance <> nil) or not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  Instance := TAtlasIdeKnownPackages.Create(mServices.GetBaseRegistryKey, GetModuleName(HInstance));
  Instance.Start;
end;

procedure StopKnownPackages;
begin
  FreeAndNil(Instance);
end;

function KnownPackagesStarted: Boolean;
begin
  Result := Instance <> nil;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.Diagnostics.KnownPackages', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
