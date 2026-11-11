unit Atlas.Core.Diagnostics.UnloadSafety;

// Kennzeichen „Entladen ohne Neustart nicht sicher“ je Package. Läuft nach
// dem Abmelden eines Moduls noch Code aus seinem Package (ein Arbeiter-Thread
// über seiner Zeitgrenze, ein Haken in fremder Kette), würde Windows den Code
// beim Entladen aus dem Speicher nehmen und der nächste Sprung dorthin wäre
// eine Zugriffsverletzung in der IDE. MarkUnsafe hält das Package deshalb bis
// zum Ende des Prozesses im Speicher (GetModuleHandleEx mit PIN): Die IDE
// entlädt es scheinbar, sein Code bleibt aber erreichbar. Das kostet nur
// Speicher; die Warnung bittet um einen Neustart der IDE, bevor das Package
// erneut geladen wird.

interface

uses
  System.SysUtils,
  System.SyncObjs;

type
  TAtlasUnloadSafety = class
  private class var
    FLock: TCriticalSection;
    FUnsafe: TArray<HMODULE>;
    FReasons: TArray<string>;
    FPin: TProc<HMODULE>;
    class procedure PinInMemory(AModule: HMODULE); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Package AModule darf nicht mehr aus dem Speicher: festhalten, protokollieren und um einen Neustart
    /// bitten. AReason nennt den Grund (Protokoll und Diagnose). AModule = 0 wird ignoriert.</summary>
    class procedure MarkUnsafe(AModule: HMODULE; const AReason: string); static;
    /// <summary>Wurde AModule nie als unsicher gekennzeichnet?</summary>
    class function IsSafe(AModule: HMODULE): Boolean; static;
    /// <summary>Alle Gründe in der Reihenfolge des Kennzeichnens.</summary>
    class function Reasons: TArray<string>; static;
    /// <summary>Nur für Tests: Festhalten ersetzen (nil = GetModuleHandleEx) und Kennzeichen vergessen.</summary>
    class procedure ResetForTests(const APin: TProc<HMODULE>); static;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TUnloadSafetyText = (RestartNeeded);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TUnloadSafetyText] of string = (
    ('Atlas: %s läuft nach dem Entladen weiter (%s). Das Package bleibt bis zum Neustart der IDE im Speicher; ' +
      'bitte die IDE neu starten, bevor es wieder geladen wird.'),
    ('Atlas: %s keeps running after unloading (%s). The package stays in memory until the IDE restarts; ' +
      'please restart the IDE before loading it again.'));
  /// <summary>GetModuleHandleEx: Modul bis zum Prozessende festhalten, Modul über eine Adresse darin finden.</summary>
  cGetModuleHandleExFlagPin = $00000001;
  cGetModuleHandleExFlagFromAddress = $00000004;

function AtlasGetModuleHandleEx(AFlags: DWORD; AModuleName: Pointer; var AModule: HMODULE): BOOL; stdcall;
  external kernel32 name 'GetModuleHandleExW';

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TUnloadSafetyText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasUnloadSafety }

class constructor TAtlasUnloadSafety.Create;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TAtlasUnloadSafety.Destroy;
begin
  FPin := nil;
  FUnsafe := nil;
  FReasons := nil;
  FreeAndNil(FLock);
end;

class procedure TAtlasUnloadSafety.PinInMemory(AModule: HMODULE);
var
  mHandle: HMODULE;
begin
  mHandle := 0;
  if not AtlasGetModuleHandleEx(cGetModuleHandleExFlagPin or cGetModuleHandleExFlagFromAddress, Pointer(AModule),
    mHandle) then
  begin
    TAtlasGuard.Log(Format('Atlas: could not pin package $%x in memory (error %d)', [AModule, GetLastError]));
  end;
end;

class procedure TAtlasUnloadSafety.MarkUnsafe(AModule: HMODULE; const AReason: string);
var
  mKnown: Boolean;
  mPin: TProc<HMODULE>;
  mName: string;
  mText: string;
  mWarn: TAtlasGuardMessage;
begin
  if (AModule = 0) or (FLock = nil) then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    mKnown := not IsSafe(AModule);
    if not mKnown then
    begin
      FUnsafe := FUnsafe + [AModule];
    end;
    FReasons := FReasons + [AReason];
    mPin := FPin;
  finally
    FLock.Leave;
  end;
  if mKnown then
  begin
    TAtlasGuard.Log('Atlas: package stays pinned, another reason: ' + AReason);
    Exit;
  end;
  if Assigned(mPin) then
  begin
    mPin(AModule);
  end
  else
  begin
    PinInMemory(AModule);
  end;
  mName := ExtractFileName(GetModuleName(AModule));
  mText := Format(UiText(TUnloadSafetyText.RestartNeeded), [mName, AReason]);
  TAtlasGuard.Log(mText);
  mWarn := TAtlasGuard.OnWarning;
  if Assigned(mWarn) then
    try
      mWarn(mText);
    except
      // Die Warnung darf das Entladen nicht aufhalten.
    end;
end;

class function TAtlasUnloadSafety.IsSafe(AModule: HMODULE): Boolean;
var
  mModule: HMODULE;
begin
  Result := True;
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    for mModule in FUnsafe do
    begin
      if mModule = AModule then
      begin
        Exit(False);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

class function TAtlasUnloadSafety.Reasons: TArray<string>;
begin
  Result := nil;
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    Result := Copy(FReasons);
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasUnloadSafety.ResetForTests(const APin: TProc<HMODULE>);
begin
  FLock.Enter;
  try
    FPin := APin;
    FUnsafe := nil;
    FReasons := nil;
  finally
    FLock.Leave;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Diagnostics.UnloadSafety', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
