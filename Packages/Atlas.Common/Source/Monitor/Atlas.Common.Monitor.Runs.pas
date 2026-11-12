unit Atlas.Common.Monitor.Runs;

// Läufe des Prüffensters von AtlasMonitor (#1900): je Ziel ein Lauf von AtlasServer als Kindprozess, nacheinander,
// damit nicht mehrere Symbolindizes gleichzeitig Speicher belegen. Die Warteschlange hält Zustand, Fortschritt
// (aus der Statusdatei des Kindprozesses), Exit-Code und Befunde je Ziel und liefert die Texte für die Liste. Ohne
// VCL und Windows; den Prozess startet und beendet die Oberfläche über den Windows-Adapter.

interface

uses
  System.SysUtils,
  Atlas.Common.Monitor.Commands;

type
  {$SCOPEDENUMS ON}
  TMonitorRunState = (Waiting, Running, Done, Failed, Cancelled);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein Befund aus der SARIF-Ausgabe eines Laufs.</summary>
  TMonitorFinding = record
    Target: string;
    FileName: string;
    /// <summary>Ab 1; 0 = ohne Stelle.</summary>
    Line: Integer;
    Column: Integer;
    RuleId: string;
    /// <summary>error, warning, note (SARIF-Stufen).</summary>
    Level: string;
    Message: string;
  end;

  TMonitorRun = record
    Target: string;
    State: TMonitorRunState;
    ExitCode: Integer;
    /// <summary>Fortschritt aus der Statusdatei des Kindprozesses; Total = 0 ohne Angabe.</summary>
    Done: Integer;
    Total: Integer;
    OutputFile: string;
    /// <summary>Datei mit stderr des Kindprozesses.</summary>
    LogFile: string;
    Findings: TArray<TMonitorFinding>;
    /// <summary>Fehlertext (stderr oder Lesefehler der Ausgabe) für die Einzelheiten.</summary>
    ErrorText: string;
  end;

  TMonitorRunQueue = record
  public
    Command: TMonitorCommand;
    Runs: TArray<TMonitorRun>;
    /// <summary>Neue Warteschlange: ein Lauf je Ziel bzw. ein einziger ohne Ziel (Absturzfall).</summary>
    class function Create(ACommand: TMonitorCommand; const ATargets: TArray<string>): TMonitorRunQueue; static;
    /// <summary>Nächster wartender Lauf; -1, wenn keiner wartet oder einer läuft.</summary>
    function NextIndex: Integer;
    function RunningIndex: Integer;
    function Busy: Boolean;
    /// <summary>Wartende und laufende Läufe gelten als abgebrochen.</summary>
    procedure CancelAll;
    /// <summary>Beendet Lauf AIndex mit AExitCode: fertig oder gescheitert nach IsFailure.</summary>
    procedure Finish(AIndex, AExitCode: Integer);
    /// <summary>Alle Befunde aller Läufe in Zielreihenfolge.</summary>
    function AllFindings: TArray<TMonitorFinding>;
    /// <summary>Gescheitert? Prüfen läuft mit --fail-on never (jeder andere Code ist ein Fehler), Absturzfall kennt
    /// 0/1 als Ergebnis, die übrigen Befehle melden ab 3 einen Fehler.</summary>
    class function IsFailure(ACommand: TMonitorCommand; AExitCode: Integer): Boolean; static;
    /// <summary>Stand für die Liste: wartet, läuft (3 von 10), fertig: 12 Befunde, Fehler (Exit-Code 3), abgebrochen.
    /// </summary>
    class function StateText(ACommand: TMonitorCommand; const ARun: TMonitorRun): string; static;
    /// <summary>Zusammenfassung unter der Liste: Ziele fertig von gesamt und Zahl der Befunde.</summary>
    function Summary: string;
  end;

implementation

uses
  Atlas.Common.Localization.Texts;

type
  {$SCOPEDENUMS ON}
  TMonitorRunText = (Waiting, Running, RunningProgress, Done, DoneFindings, Failed, Cancelled, ReplayReproduced,
    ReplayNotReproduced, Summary, SummaryFindings);
  {$SCOPEDENUMS OFF}

const
  cTexts: array[TMonitorRunText] of TAtlasText = (
    (De: 'wartet'; En: 'waiting'),
    (De: 'läuft'; En: 'running'),
    (De: 'läuft (%d von %d)'; En: 'running (%d of %d)'),
    (De: 'fertig'; En: 'done'),
    (De: 'fertig: %d Befunde'; En: 'done: %d findings'),
    (De: 'Fehler (Exit-Code %d)'; En: 'failed (exit code %d)'),
    (De: 'abgebrochen'; En: 'cancelled'),
    (De: 'fertig: nachgestellt'; En: 'done: reproduced'),
    (De: 'fertig: nicht nachgestellt'; En: 'done: not reproduced'),
    (De: '%d von %d Zielen fertig'; En: '%d of %d targets done'),
    (De: '%d von %d Zielen fertig, %d Befunde'; En: '%d of %d targets done, %d findings'));

  cReplayReproduced = 1;
  cFirstFailureCode = 3;

class function TMonitorRunQueue.Create(ACommand: TMonitorCommand; const ATargets: TArray<string>): TMonitorRunQueue;
var
  I: Integer;
begin
  Result := Default(TMonitorRunQueue);
  Result.Command := ACommand;
  if not TMonitorCommands.NeedsTarget(ACommand) then
  begin
    SetLength(Result.Runs, 1);
    Result.Runs[0] := Default(TMonitorRun);
    Exit;
  end;
  SetLength(Result.Runs, Length(ATargets));
  for I := 0 to High(ATargets) do
  begin
    Result.Runs[I] := Default(TMonitorRun);
    Result.Runs[I].Target := ATargets[I];
  end;
end;

function TMonitorRunQueue.RunningIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(Runs) do
  begin
    if Runs[I].State = TMonitorRunState.Running then
    begin
      Exit(I);
    end;
  end;
  Result := -1;
end;

function TMonitorRunQueue.NextIndex: Integer;
var
  I: Integer;
begin
  Result := -1;
  if RunningIndex >= 0 then
  begin
    Exit;
  end;
  for I := 0 to High(Runs) do
  begin
    if Runs[I].State = TMonitorRunState.Waiting then
    begin
      Exit(I);
    end;
  end;
end;

function TMonitorRunQueue.Busy: Boolean;
var
  mRun: TMonitorRun;
begin
  for mRun in Runs do
  begin
    if mRun.State in [TMonitorRunState.Waiting, TMonitorRunState.Running] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TMonitorRunQueue.CancelAll;
var
  I: Integer;
begin
  for I := 0 to High(Runs) do
  begin
    if Runs[I].State in [TMonitorRunState.Waiting, TMonitorRunState.Running] then
    begin
      Runs[I].State := TMonitorRunState.Cancelled;
    end;
  end;
end;

class function TMonitorRunQueue.IsFailure(ACommand: TMonitorCommand; AExitCode: Integer): Boolean;
begin
  case ACommand of
    TMonitorCommand.Check:
      Result := AExitCode <> 0;
    TMonitorCommand.Replay:
      Result := (AExitCode < 0) or (AExitCode > cReplayReproduced);
  else
    Result := (AExitCode < 0) or (AExitCode >= cFirstFailureCode);
  end;
end;

procedure TMonitorRunQueue.Finish(AIndex, AExitCode: Integer);
begin
  if (AIndex < 0) or (AIndex > High(Runs)) then
  begin
    Exit;
  end;
  Runs[AIndex].ExitCode := AExitCode;
  if IsFailure(Command, AExitCode) then
  begin
    Runs[AIndex].State := TMonitorRunState.Failed;
  end
  else
  begin
    Runs[AIndex].State := TMonitorRunState.Done;
  end;
end;

function TMonitorRunQueue.AllFindings: TArray<TMonitorFinding>;
var
  mRun: TMonitorRun;
begin
  Result := nil;
  for mRun in Runs do
  begin
    Result := Result + mRun.Findings;
  end;
end;

/// <summary>Text eines fertigen Laufs: Befunde, Ergebnis des Absturzfalls oder nur „fertig“.</summary>
function DoneText(ACommand: TMonitorCommand; const ARun: TMonitorRun): string;
begin
  if TMonitorCommands.OutputKind(ACommand) = TMonitorOutputKind.Findings then
  begin
    Result := cTexts[TMonitorRunText.DoneFindings].Fmt([Length(ARun.Findings)]);
  end
  else if (ACommand = TMonitorCommand.Replay) and (ARun.ExitCode = cReplayReproduced) then
  begin
    Result := cTexts[TMonitorRunText.ReplayReproduced].Text;
  end
  else if ACommand = TMonitorCommand.Replay then
  begin
    Result := cTexts[TMonitorRunText.ReplayNotReproduced].Text;
  end
  else
  begin
    Result := cTexts[TMonitorRunText.Done].Text;
  end;
end;

class function TMonitorRunQueue.StateText(ACommand: TMonitorCommand; const ARun: TMonitorRun): string;
begin
  case ARun.State of
    TMonitorRunState.Waiting:
      Result := cTexts[TMonitorRunText.Waiting].Text;
    TMonitorRunState.Running:
      if ARun.Total > 0 then
      begin
        Result := cTexts[TMonitorRunText.RunningProgress].Fmt([ARun.Done, ARun.Total]);
      end
      else
      begin
        Result := cTexts[TMonitorRunText.Running].Text;
      end;
    TMonitorRunState.Done:
      Result := DoneText(ACommand, ARun);
    TMonitorRunState.Failed:
      Result := cTexts[TMonitorRunText.Failed].Fmt([ARun.ExitCode]);
  else
    Result := cTexts[TMonitorRunText.Cancelled].Text;
  end;
end;

function TMonitorRunQueue.Summary: string;
var
  mRun: TMonitorRun;
  mFinished: Integer;
begin
  mFinished := 0;
  for mRun in Runs do
  begin
    if mRun.State in [TMonitorRunState.Done, TMonitorRunState.Failed, TMonitorRunState.Cancelled] then
    begin
      Inc(mFinished);
    end;
  end;
  if TMonitorCommands.OutputKind(Command) = TMonitorOutputKind.Findings then
  begin
    Result := cTexts[TMonitorRunText.SummaryFindings].Fmt([mFinished, Length(Runs), Length(AllFindings)]);
  end
  else
  begin
    Result := cTexts[TMonitorRunText.Summary].Fmt([mFinished, Length(Runs)]);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Monitor.Runs', cTexts);

end.
