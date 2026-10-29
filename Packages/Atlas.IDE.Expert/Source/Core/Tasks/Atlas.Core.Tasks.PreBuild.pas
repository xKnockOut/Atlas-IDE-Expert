unit Atlas.Core.Tasks.PreBuild;

// Projektaufgaben vor dem Build (#900, tasks.beforeBuild), ohne Open Tools
// API: entscheidet je Compile, was geschieht. Die IDE-Schicht startet die
// Läufe und baut danach neu.
// - Nur Make, Build und Check des Benutzers (RequestedBy '', kein
//   Hintergrund); Builds für Claude Code, Tests und Atlas-Prüfungen laufen
//   ohne Aufgaben.
// - Nur warn-Aufgaben: StartWarn, der Build läuft gleich weiter.
// - Mit einer block-Aufgabe: StartAndCancel. Der Build wird abgebrochen,
//   weil die IDE sonst bis zum Ende der Skripte stünde; die Aufgaben laufen
//   im Hintergrund. Bestehen sie (Finish mit APassed), gilt für dieses
//   Projekt ein Freischein für PassMs: Der erneute Build (von Atlas über den
//   Build-Läufer oder vom Benutzer) läuft ohne zweiten Lauf durch.
// - Laufen die Aufgaben noch, bricht ein weiterer Build mit block ab (Busy);
//   mit nur warn läuft er ohne zweiten Lauf.

interface

uses
  System.SysUtils,
  Atlas.Core.Build.Events;

type
{$SCOPEDENUMS ON}
  TAtlasTaskPreBuildAction = (None, StartWarn, StartAndCancel, Busy);
{$SCOPEDENUMS OFF}

  TAtlasTaskPreBuild = class
  public const
    PassMs = 60000;
  private
    FRunning: Boolean;
    FBlocking: Boolean;
    FProject: TAtlasCompileProject;
    FPassFile: string;
    FPassUntil: Int64;
  public
    /// <summary>Was vor dem Compile von AProject geschieht; AHasBlock/AHasWarn: es gibt check-Aufgaben mit block
    /// bzw. warn. Ein gültiger Freischein wird dabei verbraucht. Bei StartWarn und StartAndCancel gilt der Lauf als
    /// begonnen.</summary>
    function Decide(const AProject: TAtlasCompileProject; AHasBlock, AHasWarn: Boolean; ANowMs: Int64):
      TAtlasTaskPreBuildAction;
    /// <summary>Ende des Laufs; True = neu bauen (block-Lauf bestanden, Freischein gesetzt).</summary>
    function Finish(APassed: Boolean; ANowMs: Int64): Boolean;
    /// <summary>Lauf aufgegeben (Abbruch, Entladen): kein Neubau, kein Freischein.</summary>
    procedure Abandon;
    class function Applies(const AProject: TAtlasCompileProject): Boolean; static;
    property Running: Boolean read FRunning;
    property Blocking: Boolean read FBlocking;
    /// <summary>Projekt des laufenden bzw. letzten Laufs.</summary>
    property Project: TAtlasCompileProject read FProject;
  end;

implementation

{ TAtlasTaskPreBuild }

class function TAtlasTaskPreBuild.Applies(const AProject: TAtlasCompileProject): Boolean;
begin
  Result := not AProject.Background and (AProject.RequestedBy = '') and (AProject.FileName <> '') and
    (AProject.Kind in [TAtlasCompileKind.Make, TAtlasCompileKind.Build, TAtlasCompileKind.Check]);
end;

function TAtlasTaskPreBuild.Decide(const AProject: TAtlasCompileProject; AHasBlock, AHasWarn: Boolean;
  ANowMs: Int64): TAtlasTaskPreBuildAction;
begin
  Result := TAtlasTaskPreBuildAction.None;
  if not Applies(AProject) or not (AHasBlock or AHasWarn) then
    Exit;
  if FRunning then
  begin
    if AHasBlock then
      Result := TAtlasTaskPreBuildAction.Busy;
    Exit;
  end;
  if AHasBlock and SameText(FPassFile, AProject.FileName) and (ANowMs <= FPassUntil) then
  begin
    // Bestanden: Dieser Build läuft durch; die warn-Aufgaben liefen im selben Lauf.
    FPassFile := '';
    Exit;
  end;
  FRunning := True;
  FBlocking := AHasBlock;
  FProject := AProject;
  if AHasBlock then
    Result := TAtlasTaskPreBuildAction.StartAndCancel
  else
    Result := TAtlasTaskPreBuildAction.StartWarn;
end;

function TAtlasTaskPreBuild.Finish(APassed: Boolean; ANowMs: Int64): Boolean;
begin
  Result := FRunning and FBlocking and APassed;
  FRunning := False;
  if Result then
  begin
    FPassFile := FProject.FileName;
    FPassUntil := ANowMs + PassMs;
  end;
  FBlocking := False;
end;

procedure TAtlasTaskPreBuild.Abandon;
begin
  FRunning := False;
  FBlocking := False;
end;

end.
