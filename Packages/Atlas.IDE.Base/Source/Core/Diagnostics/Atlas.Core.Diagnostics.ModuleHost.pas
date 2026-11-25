unit Atlas.Core.Diagnostics.ModuleHost;

// Gemeinsame Kleinteile der Kompositions-Units der Module (#1455): die
// Beschreibung des Moduls (Info), die Zulassung vor dem Anmelden (Admit) und
// das Abmelden in der Finalisierung. Sie standen vorher wortgleich in jedem
// Modul.
// Admit: Base läuft, das Modul ist noch nicht angemeldet und die
// Vertragsversion von Base passt (Regel 7). Die erwartete Version übergibt das
// Modul (seine übersetzte cAtlasCoreContractVersion), sonst verglichen Base
// und Base. Ebenso seine übersetzte Produktversion (TAtlasVersion.cVersion):
// Weicht sie von der von Base ab, meldet sich das Modul nicht an (#2372).
// Unregister hält die Reihenfolge des Abbaus an einer Stelle:
// 1. Scope des Moduls vergessen (danach stellt das Modul nichts mehr bereit),
// 2. nur solange Base läuft (Regel 5) das Modul bei der Registry abmelden:
//    stoppen und seine Anmeldungen rückwärts lösen (Regel 4); Fehler
//    protokollieren, nicht abbrechen,
// 3. die modulspezifischen Schritte (ARelease), auch wenn Base schon abgebaut
//    ist: Danach erreicht nichts mehr das Modul (Regel 3),
// 4. OnModuleReleased mit dem HInstance des Moduls, solange sein Code noch
//    geladen ist: Base nimmt Aktionen, Zeilen und Rückrufe mit Code des Moduls
//    aus seinen eigenen Listen (Benachrichtigungen, Statusfeld), auch die, die
//    das Modul nicht selbst abgemeldet hat. Sonst gäbe Base sie erst beim
//    eigenen Abbau frei, nach dem Entladen des Moduls (Zugriffsverletzung),
// 5. zuletzt, auch ohne Scope: Laufen noch überfällige Threads aus dem Package
//    des Moduls, wartet TAtlasOverdueThreads.SettleBeforeUnload kurz und hält
//    das Package sonst im Speicher. Das wirkt nur hier, vor FreeLibrary; der
//    Rückruf beim Entladen käme zu spät.
// Base kennt dabei keine Modulnamen (Regel 9): Kennung, Name und Handle gibt
// das Modul. Das Handle ist das HInstance des Moduls, nie das von Base
// (Regel 8); deshalb übergibt das Modul es.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Handshake;

type
  TAtlasModuleHost = class
  public
    /// <summary>Beschreibung eines Moduls. AVersion und AHandle (sein HInstance) gibt das Modul, damit sie zu
    /// seinem Package gehören und nicht zu Base.</summary>
    class function Info(const AId, AName, AVersion: string; AHandle: NativeUInt; AMinLevel: TAtlasSafeLevel;
      const ASwitch: string): TAtlasModuleInfo; static;
    /// <summary>Darf sich Modul AId anmelden? True mit ARegistry, wenn Base läuft, AScope noch nil ist, die
    /// Vertragsversion von Base AExpected ist und Base dieselbe Produktversion AVersion hat (Regel 7, protokolliert,
    /// wenn nicht). AExpected und AVersion sind die Konstanten, gegen die das Modul übersetzt ist.</summary>
    class function Admit(const AId: string; AExpected: Integer; const AVersion: string;
      const AScope: IAtlasModuleScope; out ARegistry: IAtlasModuleRegistry): Boolean; static;
    /// <summary>Wie Admit mit ARegistry (nil: Base ist abgebaut), dem Ergebnis ACheck des Handschlags und ALog.
    /// </summary>
    class function AdmitTo(const ARegistry: IAtlasModuleRegistry; const AId: string; ACheck: TAtlasContractCheck;
      const AScope: IAtlasModuleScope; const ALog: TProc<string>): Boolean; static;
    /// <summary>Modul AId abmelden (Finalisierung seiner Kompositions-Unit): AScope vergessen, bei der Registry
    /// abmelden, solange Base läuft, dann ARelease (darf nil sein). Ohne AScope (nie angemeldet oder schon
    /// abgemeldet) entfallen diese Schritte. Dann löst Base über OnModuleReleased, was es noch mit Code des Packages
    /// AInstance (das HInstance des Moduls; 0 = keins) hält, und zuletzt werden dessen überfällige Threads
    /// abgewartet bzw. wird das Package festgehalten.</summary>
    class procedure Unregister(var AScope: IAtlasModuleScope; const AId: string; AInstance: HMODULE;
      const ARelease: TProc); static;
    /// <summary>Wie Unregister mit ARegistry (nil: Base ist abgebaut) und ALog für die Fehler des Abbaus.</summary>
    class procedure UnregisterFrom(const ARegistry: IAtlasModuleRegistry; var AScope: IAtlasModuleScope;
      const AId: string; AInstance: HMODULE; const ARelease: TProc; const ALog: TProc<string>); static;
  public class var
    /// <summary>Schritt 4 der Abmeldung: mit dem HInstance des Moduls, nach ARelease und vor dem Entladen. Setzt
    /// die Komposition von Base; nil vorher und nach ihrem Abbau.</summary>
    OnModuleReleased: TProc<NativeUInt>;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Modules.Registry;

const
  cLogContractMismatch = 'Module %s: contract version of Base does not match, not registered';
  cLogProductMismatch = 'Module %s: built for another Atlas version than Base, not registered';
  cLogUnregisterFailed = 'Module %s not unregistered cleanly: %s';
  cLogReleaseFailed = 'Module $%x: releasing its callbacks in Base failed: %s';

procedure LogToGuard(AText: string);
begin
  TAtlasGuard.Log(AText);
end;

{ TAtlasModuleHost }

class function TAtlasModuleHost.Info(const AId, AName, AVersion: string; AHandle: NativeUInt;
  AMinLevel: TAtlasSafeLevel; const ASwitch: string): TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := AId;
  Result.Name := AName;
  Result.Version := AVersion;
  Result.Handle := AHandle;
  Result.MinLevel := AMinLevel;
  Result.Switch := ASwitch;
end;

class function TAtlasModuleHost.Admit(const AId: string; AExpected: Integer; const AVersion: string;
  const AScope: IAtlasModuleScope; out ARegistry: IAtlasModuleRegistry): Boolean;
var
  mLog: TProc<string>;
  mCheck: TAtlasContractCheck;
begin
  ARegistry := AtlasModuleRegistry;
  if (ARegistry = nil) or (AScope <> nil) then
  begin
    Exit(False);
  end;
  mLog := LogToGuard;
  // Regel 8: Base über FindClassHInstance einer Base-Klasse, nicht über HInstance.
  mCheck := TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), AExpected);
  // TAtlasVersion.cVersion ist hier die Version von Base, AVersion die des Moduls.
  mCheck := TAtlasContractHandshake.WithProduct(mCheck, TAtlasVersion.cVersion, AVersion);
  Result := AdmitTo(ARegistry, AId, mCheck, AScope, mLog);
end;

class function TAtlasModuleHost.AdmitTo(const ARegistry: IAtlasModuleRegistry; const AId: string;
  ACheck: TAtlasContractCheck; const AScope: IAtlasModuleScope; const ALog: TProc<string>): Boolean;
begin
  if (ARegistry = nil) or (AScope <> nil) then
  begin
    Exit(False);
  end;
  Result := ACheck = ccMatch;
  if ACheck = ccProductMismatch then
  begin
    ALog(Format(cLogProductMismatch, [AId], TFormatSettings.Invariant));
  end
  else if not Result then
  begin
    ALog(Format(cLogContractMismatch, [AId], TFormatSettings.Invariant));
  end;
end;

class procedure TAtlasModuleHost.Unregister(var AScope: IAtlasModuleScope; const AId: string; AInstance: HMODULE;
  const ARelease: TProc);
var
  mLog: TProc<string>;
begin
  mLog := LogToGuard;
  // Regel 5: AtlasModuleRegistry ist nil, wenn Base das Modul in seiner Finalisierung schon abgemeldet hat.
  UnregisterFrom(AtlasModuleRegistry, AScope, AId, AInstance, ARelease, mLog);
end;

/// <summary>Schritte 1 bis 3 der Abmeldung (siehe Unit-Kopf); AScope ist zugewiesen.</summary>
procedure ReleaseScope(const ARegistry: IAtlasModuleRegistry; var AScope: IAtlasModuleScope; const AId: string;
  const ARelease: TProc; const ALog: TProc<string>);
var
  mFailure: string;
begin
  AScope := nil;
  if ARegistry <> nil then
  begin
    for mFailure in ARegistry.UnregisterModule(AId) do
    begin
      ALog(Format(cLogUnregisterFailed, [AId, mFailure], TFormatSettings.Invariant));
    end;
  end;
  if Assigned(ARelease) then
  begin
    ARelease;
  end;
end;

/// <summary>Schritt 4 der Abmeldung über OnModuleReleased; ein Fehler darf das Entladen nicht aufhalten.</summary>
procedure ReleaseModuleCode(AInstance: HMODULE; const ALog: TProc<string>);
var
  mReleased: TProc<NativeUInt>;
begin
  mReleased := TAtlasModuleHost.OnModuleReleased;
  if not Assigned(mReleased) then
  begin
    Exit;
  end;
  try
    mReleased(NativeUInt(AInstance));
  except
    on E: Exception do
      ALog(Format(cLogReleaseFailed, [NativeUInt(AInstance), E.ClassName], TFormatSettings.Invariant));
  end;
end;

class procedure TAtlasModuleHost.UnregisterFrom(const ARegistry: IAtlasModuleRegistry;
  var AScope: IAtlasModuleScope; const AId: string; AInstance: HMODULE; const ARelease: TProc;
  const ALog: TProc<string>);
begin
  if AScope <> nil then
  begin
    ReleaseScope(ARegistry, AScope, AId, ARelease, ALog);
  end;
  if AInstance = 0 then
  begin
    Exit;
  end;
  // Schritt 4: Was Base noch vom Modul hält, jetzt lösen, solange sein Code geladen ist.
  ReleaseModuleCode(AInstance, ALog);
  // Schritt 5, auch ohne Scope: ARelease kann eben noch Threads an TAtlasOverdueThreads übergeben haben.
  TAtlasOverdueThreads.SettleBeforeUnload(AInstance);
end;

end.
