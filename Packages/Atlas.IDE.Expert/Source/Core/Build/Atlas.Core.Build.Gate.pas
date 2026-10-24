unit Atlas.Core.Build.Gate;

// Prüfung vor dem Kompilieren (#529), ohne VCL und Open Tools API: Vor jedem
// make bzw. build, den der Benutzer startet, prüft Atlas die Units, die sich
// seit dem letzten erfolgreichen Compile des Projekts geändert haben, auf
// Syntaxfehler und Regeltreffer mit Schweregrad Fehler. Die IDE-Schicht liefert
// die Units mit ihrem Stand, prüft eine Unit über den Server (mit den Puffern
// der IDE, auch ungespeichert) und meldet im Meldungsfenster; hier liegen die
// Entscheidungen, testbar ohne IDE.
//
// - Nicht geprüft: build.gate = off, Code Insight (fragt die Ereignisse gar
//   nicht), Hintergrundprüfung (#548), Aufträge (Claude Code #261, „Öffnen und
//   bauen“ #764), Syntaxprüfung, Clean und Link.
// - Geändert ist eine Unit, deren Stand sich seit dem letzten erfolgreichen
//   Compile geändert hat. Ohne gemerkten Stand (erster Compile der Sitzung)
//   zählt die Änderungszeit: neuer als die Ausgabedatei des Projekts; ohne
//   Ausgabedatei ist jede Unit geändert. Den Stand jedes Compiles merkt der
//   Teilnehmer vor und übernimmt ihn erst, wenn der Compile gelingt.
// - Nur Fehler zählen: Schweregrad Fehler, nicht aus dem letzten Compilerlauf
//   (source "dcc", der ist vom vorigen Build und gleich überholt). Ein
//   Regeltreffer mit Schweregrad Warnung blockiert nie.
// - warn meldet und lässt den Compile laufen, block bricht ab. Ein zweiter
//   Compile mit denselben Treffern und unveränderten Units binnen OverrideMs
//   läuft trotzdem (bewusst übergehen, wie beim Release-Wächter #533).
// - Zeitlimit build.gateTimeoutMs für die ganze Prüfung: Jede Unit bekommt nur
//   die verbleibende Zeit; reicht sie nicht, läuft der Compile ungehindert, und
//   Atlas meldet das einmal je Sitzung.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.ReleaseGuard;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis der Prüfung vor dem Compile.</summary>
  TAtlasGateOutcome = (Passed, Reported, Blocked, Overridden, TimedOut);
{$SCOPEDENUMS OFF}

  /// <summary>Einstellungen der Prüfung, aus den Plugin-Einstellungen zusammengesetzt.</summary>
  TAtlasGateSettings = record
    Gate: TAtlasBuildGate;
    /// <summary>build.gateTimeoutMs: Zeitlimit der ganzen Prüfung.</summary>
    TimeoutMs: Integer;
    class function Create(const AGate: string; ATimeoutMs: Integer): TAtlasGateSettings; static;
  end;

  /// <summary>Unit des Projekts mit ihrem Stand, wie die IDE sie kennt.</summary>
  TAtlasGateUnit = record
    FileName: string;
    /// <summary>Stand der Unit: Prüfsumme des ungespeicherten Puffers bzw. Zeitstempel der Datei; gleicher Text,
    /// gleicher Stand.</summary>
    Stamp: string;
    /// <summary>Änderungszeit (Datei bzw. jetzt bei ungespeichertem Puffer); 0 = unbekannt.</summary>
    ModifiedAt: TDateTime;
  end;

  TAtlasGateUnits = TArray<TAtlasGateUnit>;

  /// <summary>Units eines Projekts zum Zeitpunkt des Compiles; AOutputTime = Änderungszeit der Ausgabedatei, 0 ohne.
  /// False, wenn das Projekt nicht lesbar ist (dann keine Prüfung).</summary>
  TAtlasGateUnitsFunc = reference to function(const AProject: TAtlasCompileProject; out AUnits: TAtlasGateUnits;
    out AOutputTime: TDateTime): Boolean;
  /// <summary>Befunde einer Unit, höchstens ATimeoutMs lang; False = Zeitlimit überschritten oder Server nicht
  /// erreichbar (dann gilt die Unit als nicht geprüft).</summary>
  TAtlasGateCheckFunc = reference to function(const AFileName: string; ATimeoutMs: Integer;
    out AProblems: TArray<TAtlasProblem>): Boolean;

  /// <summary>Treffer der Prüfung mit Datei.</summary>
  TAtlasGateFinding = record
    FileName: string;
    Problem: TAtlasProblem;
  end;

  TAtlasGateFindings = TArray<TAtlasGateFinding>;

  /// <summary>Meldet das Ergebnis im Meldungsfenster; liefert bei Blocked den Grund für den Abbruch.
  /// ACheckedUnits = Zahl der geprüften Units, ANotifyTimeout = Zeitlimit zum ersten Mal in dieser Sitzung.</summary>
  TAtlasGateReportFunc = reference to function(const AProject: TAtlasCompileProject;
    const AFindings: TAtlasGateFindings; ACheckedUnits: Integer; AOutcome: TAtlasGateOutcome;
    ANotifyTimeout: Boolean): string;
  TAtlasGateSettingsFunc = reference to function: TAtlasGateSettings;

  TAtlasBuildGateCheck = class
  public const
    /// <summary>Zweiter Compile mit denselben Treffern in dieser Zeit läuft trotz block.</summary>
    OverrideMs = TAtlasReleaseGuard.OverrideMs;
    DefaultTimeoutMs = 300;
    MinTimeoutMs = 50;
    MaxTimeoutMs = 10000;
  public
    /// <summary>Prüft Atlas diesen Lauf? Gate nicht off, make oder build, vom Benutzer, keine Hintergrundprüfung.
    /// </summary>
    class function Applies(const ASettings: TAtlasGateSettings; const AProject: TAtlasCompileProject): Boolean;
      static;
    /// <summary>Geänderte Units: Stand anders als in ARemembered; ohne gemerkten Stand neuer als AOutputTime (0 =
    /// keine Ausgabedatei: alle).</summary>
    class function Changed(const AUnits: TAtlasGateUnits; const ARemembered: TDictionary<string, string>;
      AOutputTime: TDateTime): TArray<string>; static;
    /// <summary>Zählt AProblem? Schweregrad Fehler und nicht aus dem letzten Compilerlauf.</summary>
    class function Counts(const AProblem: TAtlasProblem): Boolean; static;
    /// <summary>Schlüssel für „bewusst übergehen“: Projekt, Stände der geprüften Units und Treffer.</summary>
    class function Key(const AProject: string; const AStamps: TArray<string>;
      const AFindings: TAtlasGateFindings): string; static;
  end;

  /// <summary>Teilnehmer an den Compile-Ereignissen (#527): prüft vor dem Compile und merkt nach dem Erfolg die
  /// Stände der Units.</summary>
  TAtlasBuildGateParticipant = class(TAtlasCompileParticipant)
  private type
    TPending = record
      Project: string;
      Units: TAtlasGateUnits;
    end;
  private
    FSettings: TAtlasGateSettingsFunc;
    FUnits: TAtlasGateUnitsFunc;
    FCheck: TAtlasGateCheckFunc;
    FReport: TAtlasGateReportFunc;
    FClock: TAtlasClockFunc;
    // Stände des letzten erfolgreichen Compiles: Projekt (groß) -> (Datei (groß) -> Stand).
    FRemembered: TObjectDictionary<string, TDictionary<string, string>>;
    FPending: TList<TPending>;
    FBlockedKey: string;
    FBlockedAt: Int64;
    FTimeoutNotified: Boolean;
    function Now_: Int64;
    function PendingIndex(const AFileName: string): Integer;
    function RememberedOf(const AProject: string): TDictionary<string, string>;
  public
    /// <summary>AClock nil = Uhr des Systems (ms).</summary>
    constructor Create(const ASettings: TAtlasGateSettingsFunc; const AUnits: TAtlasGateUnitsFunc;
      const ACheck: TAtlasGateCheckFunc; const AReport: TAtlasGateReportFunc; const AClock: TAtlasClockFunc);
    destructor Destroy; override;
    function CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean; override;
    procedure CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string); override;
    procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64);
      override;
    /// <summary>Stand einer Unit nach dem letzten erfolgreichen Compile; '' ohne (für Tests).</summary>
    function RememberedStamp(const AProject, AFileName: string): string;
  end;

implementation

uses
  System.Math,
  System.Diagnostics;

{ TAtlasGateSettings }

class function TAtlasGateSettings.Create(const AGate: string; ATimeoutMs: Integer): TAtlasGateSettings;
begin
  Result.Gate := TAtlasReleaseGuard.GateOf(AGate);
  Result.TimeoutMs := EnsureRange(ATimeoutMs, TAtlasBuildGateCheck.MinTimeoutMs, TAtlasBuildGateCheck.MaxTimeoutMs);
end;

{ TAtlasBuildGateCheck }

class function TAtlasBuildGateCheck.Applies(const ASettings: TAtlasGateSettings;
  const AProject: TAtlasCompileProject): Boolean;
begin
  Result := (ASettings.Gate <> TAtlasBuildGate.Off) and (AProject.Kind in [TAtlasCompileKind.Make,
    TAtlasCompileKind.Build]) and not AProject.Background and (AProject.RequestedBy = '');
end;

class function TAtlasBuildGateCheck.Changed(const AUnits: TAtlasGateUnits;
  const ARemembered: TDictionary<string, string>; AOutputTime: TDateTime): TArray<string>;
var
  Item: TAtlasGateUnit;
  Stamp: string;
begin
  Result := nil;
  for Item in AUnits do
  begin
    if Item.FileName = '' then
      Continue;
    if (ARemembered <> nil) and ARemembered.TryGetValue(UpperCase(Item.FileName), Stamp) then
    begin
      if Stamp <> Item.Stamp then
        Result := Result + [Item.FileName];
    end
    else if (AOutputTime = 0) or (Item.ModifiedAt = 0) or (Item.ModifiedAt > AOutputTime) then
      Result := Result + [Item.FileName];
  end;
end;

class function TAtlasBuildGateCheck.Counts(const AProblem: TAtlasProblem): Boolean;
begin
  Result := (AProblem.Severity = TAtlasProblemSeverity.Error) and not AProblem.Unnecessary and
    not SameText(AProblem.Source, TAtlasProblem.CompilerSource);
end;

class function TAtlasBuildGateCheck.Key(const AProject: string; const AStamps: TArray<string>;
  const AFindings: TAtlasGateFindings): string;
var
  Parts: TArray<string>;
  Finding: TAtlasGateFinding;
begin
  Parts := nil;
  for Finding in AFindings do
    Parts := Parts + [Format('%s:%d:%d:%s', [UpperCase(Finding.FileName), Finding.Problem.StartLine,
      Finding.Problem.StartCharacter, Finding.Problem.Code])];
  TArray.Sort<string>(Parts);
  Result := UpperCase(AProject) + '|' + string.Join(';', AStamps) + '|' + string.Join(';', Parts);
end;

{ TAtlasBuildGateParticipant }

constructor TAtlasBuildGateParticipant.Create(const ASettings: TAtlasGateSettingsFunc;
  const AUnits: TAtlasGateUnitsFunc; const ACheck: TAtlasGateCheckFunc; const AReport: TAtlasGateReportFunc;
  const AClock: TAtlasClockFunc);
begin
  inherited Create;
  FSettings := ASettings;
  FUnits := AUnits;
  FCheck := ACheck;
  FReport := AReport;
  FClock := AClock;
  FRemembered := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);
  FPending := TList<TPending>.Create;
end;

destructor TAtlasBuildGateParticipant.Destroy;
begin
  FPending.Free;
  FRemembered.Free;
  inherited;
end;

function TAtlasBuildGateParticipant.Now_: Int64;
begin
  if Assigned(FClock) then
    Result := FClock()
  else
    Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
end;

function TAtlasBuildGateParticipant.PendingIndex(const AFileName: string): Integer;
begin
  for Result := 0 to FPending.Count - 1 do
    if SameText(FPending[Result].Project, AFileName) then
      Exit;
  Result := -1;
end;

function TAtlasBuildGateParticipant.RememberedOf(const AProject: string): TDictionary<string, string>;
begin
  if not FRemembered.TryGetValue(UpperCase(AProject), Result) then
    Result := nil;
end;

function TAtlasBuildGateParticipant.RememberedStamp(const AProject, AFileName: string): string;
var
  Stamps: TDictionary<string, string>;
begin
  Result := '';
  Stamps := RememberedOf(AProject);
  if Stamps <> nil then
    Stamps.TryGetValue(UpperCase(AFileName), Result);
end;

function TAtlasBuildGateParticipant.CancelCompile(const AProject: TAtlasCompileProject;
  out AReason: string): Boolean;
var
  Settings: TAtlasGateSettings;
  Units: TAtlasGateUnits;
  OutputTime: TDateTime;
  Changed, Stamps: TArray<string>;
  Problems: TArray<TAtlasProblem>;
  Problem: TAtlasProblem;
  Findings: TAtlasGateFindings;
  Finding: TAtlasGateFinding;
  Started, Remaining: Int64;
  FileName, Reason, CurrentKey: string;
  Item: TAtlasGateUnit;
  Checked, Index: Integer;
  TimedOut, NotifyTimeout: Boolean;
  Outcome: TAtlasGateOutcome;
  Pending: TPending;
begin
  AReason := '';
  Result := False;
  Settings := FSettings();
  if not TAtlasBuildGateCheck.Applies(Settings, AProject) or not FUnits(AProject, Units, OutputTime) then
    Exit;
  // Stand vormerken: Gelingt der Compile, gilt er als letzter erfolgreicher.
  Pending.Project := AProject.FileName;
  Pending.Units := Units;
  Index := PendingIndex(AProject.FileName);
  if Index >= 0 then
    FPending[Index] := Pending
  else
    FPending.Add(Pending);
  Changed := TAtlasBuildGateCheck.Changed(Units, RememberedOf(AProject.FileName), OutputTime);
  if Length(Changed) = 0 then
    Exit;
  Started := Now_;
  Findings := nil;
  Stamps := nil;
  Checked := 0;
  TimedOut := False;
  for FileName in Changed do
  begin
    Remaining := Settings.TimeoutMs - (Now_ - Started);
    if (Remaining <= 0) or not FCheck(FileName, Integer(Remaining), Problems) or
      (Now_ - Started > Settings.TimeoutMs) then
    begin
      TimedOut := True;
      Break;
    end;
    Inc(Checked);
    for Item in Units do
      if SameText(Item.FileName, FileName) then
        Stamps := Stamps + [Item.Stamp];
    for Problem in Problems do
      if TAtlasBuildGateCheck.Counts(Problem) then
      begin
        Finding.FileName := FileName;
        Finding.Problem := Problem;
        Findings := Findings + [Finding];
      end;
  end;
  NotifyTimeout := False;
  if TimedOut then
  begin
    // Zeitlimit: Der Compile läuft ungehindert; was bis dahin gefunden wurde, steht trotzdem da.
    Outcome := TAtlasGateOutcome.TimedOut;
    NotifyTimeout := not FTimeoutNotified;
    FTimeoutNotified := True;
    if (Length(Findings) = 0) and not NotifyTimeout then
      Exit;
  end
  else if Length(Findings) = 0 then
    Exit
  else if Settings.Gate <> TAtlasBuildGate.Block then
    Outcome := TAtlasGateOutcome.Reported
  else
  begin
    CurrentKey := TAtlasBuildGateCheck.Key(AProject.FileName, Stamps, Findings);
    if (CurrentKey = FBlockedKey) and (Now_ - FBlockedAt <= TAtlasBuildGateCheck.OverrideMs) then
    begin
      Outcome := TAtlasGateOutcome.Overridden;
      FBlockedKey := '';
    end
    else
    begin
      Outcome := TAtlasGateOutcome.Blocked;
      FBlockedKey := CurrentKey;
      FBlockedAt := Now_;
    end;
  end;
  Reason := FReport(AProject, Findings, Checked, Outcome, NotifyTimeout);
  if Outcome = TAtlasGateOutcome.Blocked then
  begin
    AReason := Reason;
    Result := True;
  end;
end;

procedure TAtlasBuildGateParticipant.CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string);
var
  Index: Integer;
begin
  // Abgebrochen (von uns oder einem anderen Teilnehmer): der vorgemerkte Stand gilt nicht.
  Index := PendingIndex(AProject.FileName);
  if Index >= 0 then
    FPending.Delete(Index);
end;

procedure TAtlasBuildGateParticipant.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
var
  Index: Integer;
  Pending: TPending;
  Stamps: TDictionary<string, string>;
  Item: TAtlasGateUnit;
begin
  Index := PendingIndex(AProject.FileName);
  if Index < 0 then
    Exit;
  Pending := FPending[Index];
  FPending.Delete(Index);
  if not ASucceeded then
    Exit;
  Stamps := TDictionary<string, string>.Create;
  for Item in Pending.Units do
    if Item.FileName <> '' then
      Stamps.AddOrSetValue(UpperCase(Item.FileName), Item.Stamp);
  FRemembered.AddOrSetValue(UpperCase(Pending.Project), Stamps);
end;

end.
