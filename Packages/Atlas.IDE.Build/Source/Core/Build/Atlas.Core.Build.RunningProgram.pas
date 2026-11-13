unit Atlas.Core.Build.RunningProgram;

// Laufendes Programm vor dem Build beenden (#551), ohne Windows und Open Tools API:
// Läuft die Ausgabedatei eines Projekts noch außerhalb des Debuggers, scheitert der
// Build erst am Ende mit F2039. TAtlasRunningProgram entscheidet vor dem Compile,
// was geschieht:
// - build.stopRunningProgram = never: nichts (die IDE wie bisher).
// - Prozesse im Debugger der IDE zählen nicht; deren Verhalten bleibt unverändert.
// - Programm (.exe): ask fragt, always beendet ohne Rückfrage. Hintergrundprüfungen
//   von Atlas fragen nie; Builds eines KI-Assistenten fragen nicht (niemand sieht die
//   Rückfrage) und beenden nur mit always.
// - Package (.bpl): Ist die BPL in einem anderen Prozess geladen, nennt ein Hinweis
//   den Prozess; beendet wird nie.
// - Syntaxprüfung und Bereinigen schreiben keine Ausgabe: nichts.
// Die Prozessliste kommt von außen (IDE-Schicht: Toolhelp), damit die Tests ohne IDE
// mit gefälschten Listen laufen.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Core.Build.Events;

type
  /// <summary>Wert von build.stopRunningProgram.</summary>
  TAtlasStopRunningMode = (Ask, Always, Never);

  /// <summary>Ein laufender Prozess mit vollständigem Pfad seines Programms bzw. der geladenen BPL.</summary>
  TAtlasRunningProcess = record
    Pid: Cardinal;
    /// <summary>Vollständiger Pfad des Programms (bei Packages: Pfad der geladenen BPL).</summary>
    Path: string;
    /// <summary>Name des Prozesses für Hinweise, z. B. "AtlasDemo.exe".</summary>
    Name: string;
    class function Create(APid: Cardinal; const APath, AName: string): TAtlasRunningProcess; static;
  end;

  /// <summary>Was vor dem Compile geschieht.</summary>
  TAtlasRunningProgramAction = (
    /// <summary>Nichts: kein passender Prozess, Einstellung never oder keine Ausgabe.</summary>
    None,
    /// <summary>Rückfrage „… läuft noch. Beenden und bauen?“.</summary>
    Ask,
    /// <summary>Ohne Rückfrage beenden.</summary>
    Stop,
    /// <summary>Package: Hinweis mit den Prozessen, kein Beenden.</summary>
    Notice);

  TAtlasRunningProgramPlan = record
    Action: TAtlasRunningProgramAction;
    /// <summary>Betroffene Prozesse (ohne die im Debugger und ohne die IDE selbst).</summary>
    Processes: TArray<TAtlasRunningProcess>;
    /// <summary>Dateiname der Ausgabe, z. B. "AtlasDemo.exe".</summary>
    ProgramName: string;
    /// <summary>Namen der Prozesse, durch Komma getrennt, jeder Name einmal.</summary>
    function ProcessNames: string;
  end;

  TAtlasRunningProgram = record
  public const
    /// <summary>Werte von build.stopRunningProgram in der Reihenfolge von TAtlasStopRunningMode.</summary>
    cModeNames: array[TAtlasStopRunningMode] of string = ('ask', 'always', 'never');
    /// <summary>So lange wartet das Beenden nach WM_CLOSE, bevor es hart beendet.</summary>
    cGraceMs = 2000;
  public
    /// <summary>Modus zum Text; Unbekanntes = Ask (Vorgabe).</summary>
    class function ModeOf(const AText: string): TAtlasStopRunningMode; static;
    /// <summary>Ist AFileName ein Package (.bpl)?</summary>
    class function IsPackage(const AFileName: string): Boolean; static;
    /// <summary>Gleicher Pfad: Groß- und Kleinschreibung egal, / und \ gleich, ohne Leerraum am Rand.</summary>
    class function SamePath(const A, B: string): Boolean; static;
    /// <summary>Prozesse aus ARunning, deren Pfad die Ausgabe AOutputFile ist, ohne ADebugged und AOwnPid.</summary>
    class function Matching(const AOutputFile: string; const ARunning: TArray<TAtlasRunningProcess>;
      const ADebugged: TArray<Cardinal>; AOwnPid: Cardinal): TArray<TAtlasRunningProcess>; static;
    /// <summary>Entscheidung vor dem Compile von AProject. ARunning: laufende Prozesse (bei Packages die mit der
    /// geladenen BPL), ADebugged: Prozesse im Debugger der IDE, AOwnPid: die IDE.</summary>
    class function Plan(const AProject: TAtlasCompileProject; AMode: TAtlasStopRunningMode;
      const ARunning: TArray<TAtlasRunningProcess>; const ADebugged: TArray<Cardinal>;
      AOwnPid: Cardinal): TAtlasRunningProgramPlan; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasRunningProcess }

class function TAtlasRunningProcess.Create(APid: Cardinal; const APath, AName: string): TAtlasRunningProcess;
begin
  Result.Pid := APid;
  Result.Path := APath;
  Result.Name := AName;
end;

{ TAtlasRunningProgramPlan }

function TAtlasRunningProgramPlan.ProcessNames: string;
var
  mProcess: TAtlasRunningProcess;
  mNames: TArray<string>;
  mName: string;
  mSeen: Boolean;
begin
  mNames := nil;
  for mProcess in Processes do
  begin
    mSeen := False;
    for mName in mNames do
    begin
      mSeen := mSeen or SameText(mName, mProcess.Name);
    end;
    if not mSeen then
    begin
      mNames := mNames + [mProcess.Name];
    end;
  end;
  Result := string.Join(', ', mNames);
end;

{ TAtlasRunningProgram }

class function TAtlasRunningProgram.ModeOf(const AText: string): TAtlasStopRunningMode;
var
  mMode: TAtlasStopRunningMode;
begin
  for mMode := Low(TAtlasStopRunningMode) to High(TAtlasStopRunningMode) do
  begin
    if SameText(Trim(AText), cModeNames[mMode]) then
    begin
      Exit(mMode);
    end;
  end;
  Result := TAtlasStopRunningMode.Ask;
end;

class function TAtlasRunningProgram.IsPackage(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(Trim(AFileName)), '.bpl');
end;

class function TAtlasRunningProgram.SamePath(const A, B: string): Boolean;
begin
  Result := (Trim(A) <> '') and SameText(Trim(A).Replace('/', '\'), Trim(B).Replace('/', '\'));
end;

function Contains(const AIds: TArray<Cardinal>; AId: Cardinal): Boolean;
var
  mId: Cardinal;
begin
  for mId in AIds do
  begin
    if mId = AId then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasRunningProgram.Matching(const AOutputFile: string; const ARunning: TArray<TAtlasRunningProcess>;
  const ADebugged: TArray<Cardinal>; AOwnPid: Cardinal): TArray<TAtlasRunningProcess>;
var
  mProcess: TAtlasRunningProcess;
begin
  Result := nil;
  for mProcess in ARunning do
  begin
    if SamePath(mProcess.Path, AOutputFile) and (mProcess.Pid <> AOwnPid) and not Contains(ADebugged, mProcess.Pid) then
    begin
      Result := Result + [mProcess];
    end;
  end;
end;

/// <summary>Schreibt der Compile eine Ausgabe? Syntaxprüfung und Bereinigen nicht.</summary>
function WritesOutput(AKind: TAtlasCompileKind): Boolean;
begin
  Result := not (AKind in [TAtlasCompileKind.Check, TAtlasCompileKind.Clean]);
end;

class function TAtlasRunningProgram.Plan(const AProject: TAtlasCompileProject; AMode: TAtlasStopRunningMode;
  const ARunning: TArray<TAtlasRunningProcess>; const ADebugged: TArray<Cardinal>;
  AOwnPid: Cardinal): TAtlasRunningProgramPlan;
begin
  Result := Default(TAtlasRunningProgramPlan);
  Result.ProgramName := ExtractFileName(Trim(AProject.OutputFile).Replace('/', '\'));
  if (AMode = TAtlasStopRunningMode.Never) or AProject.Background or not WritesOutput(AProject.Kind) then
  begin
    Exit;
  end;
  Result.Processes := Matching(AProject.OutputFile, ARunning, ADebugged, AOwnPid);
  if Length(Result.Processes) = 0 then
  begin
    Exit;
  end;
  if IsPackage(AProject.OutputFile) then
  begin
    Result.Action := TAtlasRunningProgramAction.Notice;
  end
  else if AMode = TAtlasStopRunningMode.Always then
  begin
    Result.Action := TAtlasRunningProgramAction.Stop;
  end
  else if AProject.RequestedBy = '' then
  begin
    Result.Action := TAtlasRunningProgramAction.Ask;
  end
  else
  begin
    // Auftrag eines KI-Assistenten: Niemand sieht die Rückfrage; der Build scheitert wie bisher.
    Result.Processes := nil;
  end;
end;

end.
