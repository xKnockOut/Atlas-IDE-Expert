unit Atlas.Core.BuildPipeline.Gate;

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
  Atlas.Core.Build.PipelineSettings,
  Atlas.Core.BuildPipeline.ReleaseGuard;

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
    DefaultTimeoutMs = TAtlasBuildPipelineSettings.GateDefaultTimeoutMs;
    MinTimeoutMs = TAtlasBuildPipelineSettings.GateMinTimeoutMs;
    MaxTimeoutMs = TAtlasBuildPipelineSettings.GateMaxTimeoutMs;
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
    /// <summary>Ergebnis der Prüfung der geänderten Units vor einem Compile.</summary>
    TGateRun = record
      Findings: TAtlasGateFindings;
      Stamps: TArray<string>;
      Checked: Integer;
      TimedOut: Boolean;
      NotifyTimeout: Boolean;
      Outcome: TAtlasGateOutcome;
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
    procedure RememberPending(const AFileName: string; const AUnits: TAtlasGateUnits);
    function RunChecks(const ASettings: TAtlasGateSettings; const AChanged: TArray<string>;
      const AUnits: TAtlasGateUnits): TGateRun;
    function Decide(const AProject: string; const ASettings: TAtlasGateSettings; var ARun: TGateRun): Boolean;
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
  Result.Gate := TAtlasBuildPipelineSettings.GateOf(AGate);
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
    begin
      Continue;
    end;
    if (ARemembered <> nil) and ARemembered.TryGetValue(UpperCase(Item.FileName), Stamp) then
    begin
      if Stamp <> Item.Stamp then
      begin
        Result := Result + [Item.FileName];
      end;
    end
    else if (AOutputTime = 0) or (Item.ModifiedAt = 0) or (Item.ModifiedAt > AOutputTime) then
    begin
      Result := Result + [Item.FileName];
    end;
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
  begin
    Parts := Parts + [Format('%s:%d:%d:%s', [UpperCase(Finding.FileName), Finding.Problem.StartLine,
      Finding.Problem.StartCharacter, Finding.Problem.Code])];
  end;
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
  begin
    Result := FClock();
  end
  else
  begin
    Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
  end;
end;

function TAtlasBuildGateParticipant.PendingIndex(const AFileName: string): Integer;
begin
  for Result := 0 to FPending.Count - 1 do
  begin
    if SameText(FPending[Result].Project, AFileName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TAtlasBuildGateParticipant.RememberedOf(const AProject: string): TDictionary<string, string>;
begin
  if not FRemembered.TryGetValue(UpperCase(AProject), Result) then
  begin
    Result := nil;
  end;
end;

function TAtlasBuildGateParticipant.RememberedStamp(const AProject, AFileName: string): string;
var
  Stamps: TDictionary<string, string>;
begin
  Result := '';
  Stamps := RememberedOf(AProject);
  if Stamps <> nil then
  begin
    Stamps.TryGetValue(UpperCase(AFileName), Result);
  end;
end;

/// <summary>Stand vormerken: Gelingt der Compile, gilt er als letzter erfolgreicher.</summary>
procedure TAtlasBuildGateParticipant.RememberPending(const AFileName: string; const AUnits: TAtlasGateUnits);
var
  Pending: TPending;
  Index: Integer;
begin
  Pending.Project := AFileName;
  Pending.Units := AUnits;
  Index := PendingIndex(AFileName);
  if Index >= 0 then
  begin
    FPending[Index] := Pending;
  end
  else
  begin
    FPending.Add(Pending);
  end;
end;

/// <summary>Stände der Unit AFileName in AUnits.</summary>
function UnitStamps(const AUnits: TAtlasGateUnits; const AFileName: string): TArray<string>;
var
  Item: TAtlasGateUnit;
begin
  Result := nil;
  for Item in AUnits do
  begin
    if SameText(Item.FileName, AFileName) then
    begin
      Result := Result + [Item.Stamp];
    end;
  end;
end;

/// <summary>Probleme der Unit AFileName, die für das Gate zählen.</summary>
function CountedFindings(const AFileName: string; const AProblems: TArray<TAtlasProblem>): TAtlasGateFindings;
var
  Problem: TAtlasProblem;
  Finding: TAtlasGateFinding;
begin
  Result := nil;
  for Problem in AProblems do
  begin
    if TAtlasBuildGateCheck.Counts(Problem) then
    begin
      Finding.FileName := AFileName;
      Finding.Problem := Problem;
      Result := Result + [Finding];
    end;
  end;
end;

function TAtlasBuildGateParticipant.RunChecks(const ASettings: TAtlasGateSettings; const AChanged: TArray<string>;
  const AUnits: TAtlasGateUnits): TGateRun;
var
  Started, Remaining: Int64;
  FileName: string;
  Problems: TArray<TAtlasProblem>;
begin
  Result := Default(TGateRun);
  Started := Now_;
  for FileName in AChanged do
  begin
    Remaining := ASettings.TimeoutMs - (Now_ - Started);
    if (Remaining <= 0) or not FCheck(FileName, Integer(Remaining), Problems) or
      (Now_ - Started > ASettings.TimeoutMs) then
    begin
      Result.TimedOut := True;
      Break;
    end;
    Inc(Result.Checked);
    Result.Stamps := Result.Stamps + UnitStamps(AUnits, FileName);
    Result.Findings := Result.Findings + CountedFindings(FileName, Problems);
  end;
end;

/// <summary>Ausgang in ARun festlegen; False, wenn nichts zu melden ist.</summary>
function TAtlasBuildGateParticipant.Decide(const AProject: string; const ASettings: TAtlasGateSettings;
  var ARun: TGateRun): Boolean;
var
  CurrentKey: string;
begin
  Result := True;
  if ARun.TimedOut then
  begin
    // Zeitlimit: Der Compile läuft ungehindert; was bis dahin gefunden wurde, steht trotzdem da.
    ARun.Outcome := TAtlasGateOutcome.TimedOut;
    ARun.NotifyTimeout := not FTimeoutNotified;
    FTimeoutNotified := True;
    Result := (Length(ARun.Findings) > 0) or ARun.NotifyTimeout;
  end
  else if Length(ARun.Findings) = 0 then
  begin
    Result := False;
  end
  else if ASettings.Gate <> TAtlasBuildGate.Block then
  begin
    ARun.Outcome := TAtlasGateOutcome.Reported;
  end
  else
  begin
    CurrentKey := TAtlasBuildGateCheck.Key(AProject, ARun.Stamps, ARun.Findings);
    if (CurrentKey = FBlockedKey) and (Now_ - FBlockedAt <= TAtlasBuildGateCheck.OverrideMs) then
    begin
      ARun.Outcome := TAtlasGateOutcome.Overridden;
      FBlockedKey := '';
    end
    else
    begin
      ARun.Outcome := TAtlasGateOutcome.Blocked;
      FBlockedKey := CurrentKey;
      FBlockedAt := Now_;
    end;
  end;
end;

function TAtlasBuildGateParticipant.CancelCompile(const AProject: TAtlasCompileProject;
  out AReason: string): Boolean;
var
  Settings: TAtlasGateSettings;
  Units: TAtlasGateUnits;
  OutputTime: TDateTime;
  Changed: TArray<string>;
  Run: TGateRun;
  Reason: string;
begin
  AReason := '';
  Result := False;
  Settings := FSettings();
  if not TAtlasBuildGateCheck.Applies(Settings, AProject) or not FUnits(AProject, Units, OutputTime) then
  begin
    Exit;
  end;
  RememberPending(AProject.FileName, Units);
  Changed := TAtlasBuildGateCheck.Changed(Units, RememberedOf(AProject.FileName), OutputTime);
  if Length(Changed) = 0 then
  begin
    Exit;
  end;
  Run := RunChecks(Settings, Changed, Units);
  if not Decide(AProject.FileName, Settings, Run) then
  begin
    Exit;
  end;
  Reason := FReport(AProject, Run.Findings, Run.Checked, Run.Outcome, Run.NotifyTimeout);
  if Run.Outcome = TAtlasGateOutcome.Blocked then
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
  begin
    FPending.Delete(Index);
  end;
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
  begin
    Exit;
  end;
  Pending := FPending[Index];
  FPending.Delete(Index);
  if not ASucceeded then
  begin
    Exit;
  end;
  Stamps := TDictionary<string, string>.Create;
  for Item in Pending.Units do
  begin
    if Item.FileName <> '' then
    begin
      Stamps.AddOrSetValue(UpperCase(Item.FileName), Item.Stamp);
    end;
  end;
  FRemembered.AddOrSetValue(UpperCase(Pending.Project), Stamps);
end;

end.
