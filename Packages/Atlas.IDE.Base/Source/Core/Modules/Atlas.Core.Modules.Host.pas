unit Atlas.Core.Modules.Host;

// Gemeinsame Kleinteile der Kompositions-Units der Module (#1455): die
// Beschreibung des Moduls (Info), die Zulassung vor dem Anmelden (Admit) und
// das Abmelden in der Finalisierung. Sie standen vorher wortgleich in jedem
// Modul.
// Admit: Base läuft, das Modul ist noch nicht angemeldet und die
// Vertragsversion von Base passt (Regel 7). Die erwartete Version übergibt das
// Modul (seine übersetzte cAtlasCoreContractVersion), sonst verglichen Base
// und Base.
// Unregister hält die Reihenfolge des Abbaus an einer Stelle:
// 1. Scope des Moduls vergessen (danach stellt das Modul nichts mehr bereit),
// 2. nur solange Base läuft (Regel 5) das Modul bei der Registry abmelden:
//    stoppen und seine Anmeldungen rückwärts lösen (Regel 4); Fehler
//    protokollieren, nicht abbrechen,
// 3. die modulspezifischen Schritte (ARelease), auch wenn Base schon abgebaut
//    ist: Danach erreicht nichts mehr das Modul (Regel 3).
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
    /// <summary>Darf sich Modul AId anmelden? True mit ARegistry, wenn Base läuft, AScope noch nil ist und die
    /// Vertragsversion von Base AExpected ist (Regel 7, protokolliert, wenn nicht).</summary>
    class function Admit(const AId: string; AExpected: Integer; const AScope: IAtlasModuleScope;
      out ARegistry: IAtlasModuleRegistry): Boolean; static;
    /// <summary>Wie Admit mit ARegistry (nil: Base ist abgebaut), dem Ergebnis ACheck des Handschlags und ALog.
    /// </summary>
    class function AdmitTo(const ARegistry: IAtlasModuleRegistry; const AId: string; ACheck: TAtlasContractCheck;
      const AScope: IAtlasModuleScope; const ALog: TProc<string>): Boolean; static;
    /// <summary>Modul AId abmelden (Finalisierung seiner Kompositions-Unit): AScope vergessen, bei der Registry
    /// abmelden, solange Base läuft, dann ARelease (darf nil sein). Ohne AScope (nie angemeldet oder schon
    /// abgemeldet) geschieht nichts.</summary>
    class procedure Unregister(var AScope: IAtlasModuleScope; const AId: string; const ARelease: TProc); static;
    /// <summary>Wie Unregister mit ARegistry (nil: Base ist abgebaut) und ALog für die Fehler des Abbaus.</summary>
    class procedure UnregisterFrom(const ARegistry: IAtlasModuleRegistry; var AScope: IAtlasModuleScope;
      const AId: string; const ARelease: TProc; const ALog: TProc<string>); static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry;

const
  cLogContractMismatch = 'Module %s: contract version of Base does not match, not registered';
  cLogUnregisterFailed = 'Module %s not unregistered cleanly: %s';

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

class function TAtlasModuleHost.Admit(const AId: string; AExpected: Integer; const AScope: IAtlasModuleScope;
  out ARegistry: IAtlasModuleRegistry): Boolean;
var
  mLog: TProc<string>;
begin
  ARegistry := AtlasModuleRegistry;
  if (ARegistry = nil) or (AScope <> nil) then
  begin
    Exit(False);
  end;
  mLog := LogToGuard;
  // Regel 8: Base über FindClassHInstance einer Base-Klasse, nicht über HInstance.
  Result := AdmitTo(ARegistry, AId, TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry),
    AExpected), AScope, mLog);
end;

class function TAtlasModuleHost.AdmitTo(const ARegistry: IAtlasModuleRegistry; const AId: string;
  ACheck: TAtlasContractCheck; const AScope: IAtlasModuleScope; const ALog: TProc<string>): Boolean;
begin
  if (ARegistry = nil) or (AScope <> nil) then
  begin
    Exit(False);
  end;
  Result := ACheck = ccMatch;
  if not Result then
  begin
    ALog(Format(cLogContractMismatch, [AId], TFormatSettings.Invariant));
  end;
end;

class procedure TAtlasModuleHost.Unregister(var AScope: IAtlasModuleScope; const AId: string;
  const ARelease: TProc);
var
  mLog: TProc<string>;
begin
  if AScope = nil then
  begin
    Exit;
  end;
  mLog := LogToGuard;
  // Regel 5: AtlasModuleRegistry ist nil, wenn Base das Modul in seiner Finalisierung schon abgemeldet hat.
  UnregisterFrom(AtlasModuleRegistry, AScope, AId, ARelease, mLog);
end;

class procedure TAtlasModuleHost.UnregisterFrom(const ARegistry: IAtlasModuleRegistry;
  var AScope: IAtlasModuleScope; const AId: string; const ARelease: TProc; const ALog: TProc<string>);
var
  mFailure: string;
begin
  if AScope = nil then
  begin
    Exit;
  end;
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

end.
