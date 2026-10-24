unit Atlas.UI.Tasks.Texts;

// Texte der Projektaufgaben (#900) in der Sprache der Oberfläche, ohne
// Fenster prüfbar:
// - Kopfzeile je Lauf im Register „Atlas-Aufgaben“: Name, Exit-Code, Dauer,
//   Zahl der Befunde; bei Zeitlimit, Abbruch, fehlendem Programm (mit dem
//   Ordner, in dem gesucht wurde) und Startfehler ein eigener Text.
// - Meldung der Prüfung vor dem Build („Delphi-12-Prüfung: 2 Fehler, Build
//   abgebrochen“).
// - Letztes Ergebnis für Statusfeld, Befehlspalette und Menü.

interface

uses
  System.SysUtils,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Runs;

type
  TAtlasTaskTexts = class
  public
    /// <summary>„0,4 s“, „12,3 s“, „2:05 min“.</summary>
    class function Duration(AMs: Int64): string; static;
    class function GroupName(AGroup: TAtlasTaskGroup): string; static;
    /// <summary>„keine Befunde“, „1 Befund“, „3 Befunde“.</summary>
    class function Findings(ACount: Integer): string; static;
    /// <summary>Kopfzeile eines laufenden Laufs.</summary>
    class function Running(const AName, ACommandLine: string): string; static;
    /// <summary>Kopfzeile eines fertigen Laufs; ATimeoutSec für den Text beim Zeitlimit.</summary>
    class function Header(const ARun: TAtlasTaskRun; ATimeoutSec: Integer): string; static;
    /// <summary>Grund des Abbruchs vor dem Build durch ARun.</summary>
    class function Blocked(const ARun: TAtlasTaskRun): string; static;
    /// <summary>Kurzes letztes Ergebnis („bestanden 14:03“, „2 Fehler 14:03“); ohne Lauf „noch nicht gelaufen“.
    /// </summary>
    class function LastResult(const ALast: TAtlasTaskLastRun; AHas: Boolean): string; static;
    /// <summary>Beschreibung in der Befehlspalette: Gruppe · Befehl · letztes Ergebnis.</summary>
    class function Description(const ATask: TAtlasTaskDefinition; const ALastText: string): string; static;
  end;

implementation

uses
  Atlas.UI.Strings;

{ TAtlasTaskTexts }

class function TAtlasTaskTexts.Duration(AMs: Int64): string;
var
  Seconds: Int64;
begin
  if AMs < 0 then
    AMs := 0;
  Seconds := AMs div 1000;
  if Seconds < 60 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksSeconds, [Seconds, (AMs mod 1000) div 100])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksMinutes, [Seconds div 60, Seconds mod 60]);
end;

class function TAtlasTaskTexts.GroupName(AGroup: TAtlasTaskGroup): string;
begin
  case AGroup of
    TAtlasTaskGroup.Check:
      Result := TAtlasStrings.Text(TAtlasTextId.TasksGroupCheck);
    TAtlasTaskGroup.Build:
      Result := TAtlasStrings.Text(TAtlasTextId.TasksGroupBuild);
    TAtlasTaskGroup.Test:
      Result := TAtlasStrings.Text(TAtlasTextId.TasksGroupTest);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.TasksGroupOther);
  end;
end;

class function TAtlasTaskTexts.Findings(ACount: Integer): string;
begin
  if ACount <= 0 then
    Result := TAtlasStrings.Text(TAtlasTextId.TasksFindingsNone)
  else if ACount = 1 then
    Result := TAtlasStrings.Text(TAtlasTextId.TasksFindingsOne)
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksFindingsMany, [ACount]);
end;

class function TAtlasTaskTexts.Running(const AName, ACommandLine: string): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.TasksHeaderRunning, [AName, ACommandLine]);
end;

class function TAtlasTaskTexts.Header(const ARun: TAtlasTaskRun; ATimeoutSec: Integer): string;
begin
  case ARun.Outcome of
    TAtlasTaskOutcome.TimedOut:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TasksHeaderTimedOut, [ARun.Name, ATimeoutSec,
        Findings(ARun.Counts.Total)]);
    TAtlasTaskOutcome.Cancelled:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TasksHeaderCancelled, [ARun.Name, Findings(ARun.Counts.Total)]);
    TAtlasTaskOutcome.ProgramMissing:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TasksHeaderMissing, [ARun.Name, ARun.Error, ARun.Cwd]);
    TAtlasTaskOutcome.StartFailed:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TasksHeaderStartFailed, [ARun.Name, ARun.Error]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksHeaderFinished, [ARun.Name, ARun.ExitCode,
      Duration(ARun.DurationMs), Findings(ARun.Counts.Total)]);
  end;
end;

class function TAtlasTaskTexts.Blocked(const ARun: TAtlasTaskRun): string;
begin
  if ARun.Counts.Errors > 0 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksGateErrors, [ARun.Name, ARun.Counts.Errors])
  else if ARun.Outcome = TAtlasTaskOutcome.Finished then
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksGateExit, [ARun.Name, ARun.ExitCode])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksGateNotRun, [ARun.Name]);
end;

class function TAtlasTaskTexts.LastResult(const ALast: TAtlasTaskLastRun; AHas: Boolean): string;
var
  Time: string;
begin
  if not AHas then
    Exit(TAtlasStrings.Text(TAtlasTextId.TasksNever));
  Time := FormatDateTime('hh:nn', ALast.FinishedAt);
  if ALast.Outcome <> TAtlasTaskOutcome.Finished then
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksNotRun, [Time])
  else if ALast.Counts.Errors > 0 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksErrors, [ALast.Counts.Errors, Time])
  else if ALast.ExitCode <> 0 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksExitCode, [ALast.ExitCode, Time])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.TasksPassed, [Time]);
end;

class function TAtlasTaskTexts.Description(const ATask: TAtlasTaskDefinition; const ALastText: string): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.TasksItemDescription, [GroupName(ATask.Group), ATask.CommandLine,
    ALastText]);
end;

end.
