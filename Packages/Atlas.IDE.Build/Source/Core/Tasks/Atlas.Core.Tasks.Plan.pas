unit Atlas.Core.Tasks.Plan;

// Entscheidungen des Aufgabenläufers (#900), ohne VCL und Open Tools API.
// Atlas.IDE.Tasks.Runner startet Threads, liest Einstellungen und schreibt
// Meldungen; was dabei zu entscheiden ist, steht hier:
// - Vor dem Build: Verhalten je Aufgabe (eigenes beforeBuild vor dem
//   globalen tasks.beforeBuild), ob eine Aufgabe blockiert bzw. nur warnt,
//   und die Namen für die Meldung „Prüfungen laufen: …“.
// - Ob die Entscheidung von TAtlasTaskPreBuild den Compile abbricht und ob
//   sie einen Lauf startet.
// - Farbe des Statusfelds einer Aufgabe nach dem letzten Lauf (laufend und
//   ohne Lauf neutral).
// - Text des Eintrags im Untermenü Atlas › Aufgaben („Gruppe: Name (letzter
//   Lauf)“, Taste nach einem Tabulator).
// - Ende eines Laufs: Gehört er zum aktiven Projekt (Statusfeld), und wie
//   heißt sein Projekt für die Hörer ('' ohne Projekt)?

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Status.Contract,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.PreBuild,
  Atlas.Core.Tasks.Runs;

type
  /// <summary>Plan der Aufgaben vor dem Build.</summary>
  TAtlasTaskPreBuildPlan = record
    /// <summary>Verhalten je Aufgabe, in der Reihenfolge der Aufgaben.</summary>
    Modes: TArray<TAtlasTaskBeforeBuild>;
    /// <summary>Mindestens eine Aufgabe mit block.</summary>
    HasBlock: Boolean;
    /// <summary>Mindestens eine Aufgabe ohne block (warn).</summary>
    HasWarn: Boolean;
    /// <summary>Namen der Aufgaben, mit „, “ getrennt.</summary>
    Names: string;
  end;

  TAtlasTaskPlan = record
  public
    /// <summary>Verhalten vor dem Build je Aufgabe aus ATasks; AGlobal gilt, wo eine Aufgabe nichts sagt.</summary>
    class function PreBuild(const ATasks: TAtlasTaskDefinitions; AGlobal: TAtlasTaskBeforeBuild):
      TAtlasTaskPreBuildPlan; static;
    /// <summary>ACount-mal Off: „Alle Prüfungen ausführen“ ohne Build danach.</summary>
    class function OffModes(ACount: Integer): TArray<TAtlasTaskBeforeBuild>; static;
    /// <summary>Bricht die Entscheidung den Compile ab (block startet bzw. läuft noch)?</summary>
    class function CancelsCompile(AAction: TAtlasTaskPreBuildAction): Boolean; static;
    /// <summary>Startet die Entscheidung die Aufgaben?</summary>
    class function StartsRun(AAction: TAtlasTaskPreBuildAction): Boolean; static;
    /// <summary>Farbe des Statusfelds: neutral, solange die Aufgabe läuft oder nie lief; sonst grün bzw. rot nach
    /// dem letzten Lauf.</summary>
    class function StatusState(ARunning, AHasLast: Boolean; const ALast: TAtlasTaskLastRun): TAtlasStatusState;
      static;
    /// <summary>Text im Untermenü: „AGroup: AName (ALast)“, mit Taste AKeyText nach einem Tabulator.</summary>
    class function MenuCaption(const AGroup, AName, ALast, AKeyText: string): string; static;
    /// <summary>Gehört ein Lauf im Projekt AJobProject zum geladenen Projekt ALoaded? ANoProject ist der
    /// Schlüssel der Läufe ohne Projekt (ALoaded '').</summary>
    class function IsLoadedProject(const AJobProject, ALoaded, ANoProject: string): Boolean; static;
    /// <summary>Projekt eines Laufs für die Hörer: '' statt ANoProject.</summary>
    class function ReportedProject(const AJobProject, ANoProject: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasTaskPlan }

class function TAtlasTaskPlan.PreBuild(const ATasks: TAtlasTaskDefinitions; AGlobal: TAtlasTaskBeforeBuild):
  TAtlasTaskPreBuildPlan;
var
  mTask: TAtlasTaskDefinition;
  mMode: TAtlasTaskBeforeBuild;
begin
  Result := Default(TAtlasTaskPreBuildPlan);
  for mTask in ATasks do
  begin
    mMode := mTask.BeforeBuildFor(AGlobal);
    Result.Modes := Result.Modes + [mMode];
    if mMode = TAtlasTaskBeforeBuild.Block then
    begin
      Result.HasBlock := True;
    end
    else
    begin
      Result.HasWarn := True;
    end;
    if Result.Names <> '' then
    begin
      Result.Names := Result.Names + ', ';
    end;
    Result.Names := Result.Names + mTask.Name;
  end;
end;

class function TAtlasTaskPlan.OffModes(ACount: Integer): TArray<TAtlasTaskBeforeBuild>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, ACount);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := TAtlasTaskBeforeBuild.Off;
  end;
end;

class function TAtlasTaskPlan.CancelsCompile(AAction: TAtlasTaskPreBuildAction): Boolean;
begin
  Result := AAction in [TAtlasTaskPreBuildAction.StartAndCancel, TAtlasTaskPreBuildAction.Busy];
end;

class function TAtlasTaskPlan.StartsRun(AAction: TAtlasTaskPreBuildAction): Boolean;
begin
  Result := AAction in [TAtlasTaskPreBuildAction.StartWarn, TAtlasTaskPreBuildAction.StartAndCancel];
end;

class function TAtlasTaskPlan.StatusState(ARunning, AHasLast: Boolean; const ALast: TAtlasTaskLastRun):
  TAtlasStatusState;
begin
  Result := TAtlasStatusState.Neutral;
  if ARunning or not AHasLast then
  begin
    Exit;
  end;
  if ALast.Passed then
  begin
    Result := TAtlasStatusState.Green;
  end
  else
  begin
    Result := TAtlasStatusState.Red;
  end;
end;

class function TAtlasTaskPlan.MenuCaption(const AGroup, AName, ALast, AKeyText: string): string;
begin
  Result := AGroup + ': ' + AName + ' (' + ALast + ')';
  if AKeyText <> '' then
  begin
    Result := Result + #9 + AKeyText;
  end;
end;

class function TAtlasTaskPlan.IsLoadedProject(const AJobProject, ALoaded, ANoProject: string): Boolean;
begin
  Result := SameText(AJobProject, ALoaded) or ((ALoaded = '') and (AJobProject = ANoProject));
end;

class function TAtlasTaskPlan.ReportedProject(const AJobProject, ANoProject: string): string;
begin
  Result := AJobProject;
  if Result = ANoProject then
  begin
    Result := '';
  end;
end;

end.
