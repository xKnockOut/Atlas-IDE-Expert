unit Atlas.UI.Tasks.Texts;

// Texte der Projektaufgaben (#900) in der Sprache der Oberfläche, ohne
// Fenster prüfbar:
// - Kopfzeile je Lauf im Register „Atlas-Aufgaben“: Name, Exit-Code, Dauer,
//   Zahl der Befunde; bei Zeitlimit, Abbruch, fehlendem Programm (mit dem
//   Ordner, in dem gesucht wurde) und Startfehler ein eigener Text.
// - Meldung der Prüfung vor dem Build („Delphi-12-Prüfung: 2 Fehler, Build
//   abgebrochen“).
// - Letztes Ergebnis für Statusfeld, Befehlspalette und Menü.
// - Verworfene Einträge aus tasks (#1458: Core liefert Art, Stelle und Wert).

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
    /// <summary>„Lint: args muss eine Liste sein“.</summary>
    class function Issue(const AIssue: TAtlasTaskIssue): string; static;
  end;

implementation

uses
  Atlas.UI.Build.Strings;

const
  cIssueTexts: array[TAtlasTaskIssueKind] of TAtlasBuildTextId = (TAtlasBuildTextId.TasksIssueUnknownMatcher,
    TAtlasBuildTextId.TasksIssueSeverityMapValue, TAtlasBuildTextId.TasksIssueMatcherWithoutRegex,
    TAtlasBuildTextId.TasksIssueMatcherType, TAtlasBuildTextId.TasksIssueArgsValue,
    TAtlasBuildTextId.TasksIssueArgsType, TAtlasBuildTextId.TasksIssueKeyUnreadable,
    TAtlasBuildTextId.TasksIssueTimeoutValue, TAtlasBuildTextId.TasksIssueUnknownGroup,
    TAtlasBuildTextId.TasksIssueBeforeBuildValue, TAtlasBuildTextId.TasksIssueMissingName,
    TAtlasBuildTextId.TasksIssueMissingCommand, TAtlasBuildTextId.TasksIssueTasksType,
    TAtlasBuildTextId.TasksIssueTaskType, TAtlasBuildTextId.TasksIssueDuplicateName);

{ TAtlasTaskTexts }

class function TAtlasTaskTexts.Duration(AMs: Int64): string;
var
  mSeconds: Int64;
begin
  if AMs < 0 then
  begin
    AMs := 0;
  end;
  mSeconds := AMs div 1000;
  if mSeconds < 60 then
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksSeconds, [mSeconds, (AMs mod 1000) div 100]);
  end
  else
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksMinutes, [mSeconds div 60, mSeconds mod 60]);
  end;
end;

class function TAtlasTaskTexts.GroupName(AGroup: TAtlasTaskGroup): string;
begin
  case AGroup of
    TAtlasTaskGroup.Check:
      Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksGroupCheck);
    TAtlasTaskGroup.Build:
      Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksGroupBuild);
    TAtlasTaskGroup.Test:
      Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksGroupTest);
  else
    Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksGroupOther);
  end;
end;

class function TAtlasTaskTexts.Findings(ACount: Integer): string;
begin
  if ACount <= 0 then
  begin
    Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksFindingsNone);
  end
  else if ACount = 1 then
  begin
    Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksFindingsOne);
  end
  else
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksFindingsMany, [ACount]);
  end;
end;

class function TAtlasTaskTexts.Running(const AName, ACommandLine: string): string;
begin
  Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksHeaderRunning, [AName, ACommandLine]);
end;

class function TAtlasTaskTexts.Header(const ARun: TAtlasTaskRun; ATimeoutSec: Integer): string;
begin
  case ARun.Outcome of
    TAtlasTaskOutcome.TimedOut:
      Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksHeaderTimedOut, [ARun.Name, ATimeoutSec,
        Findings(ARun.Counts.Total)]);
    TAtlasTaskOutcome.Cancelled:
      Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksHeaderCancelled,
        [ARun.Name, Findings(ARun.Counts.Total)]);
    TAtlasTaskOutcome.ProgramMissing:
      Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksHeaderMissing, [ARun.Name, ARun.Error, ARun.Cwd]);
    TAtlasTaskOutcome.StartFailed:
      Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksHeaderStartFailed, [ARun.Name, ARun.Error]);
  else
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksHeaderFinished, [ARun.Name, ARun.ExitCode,
      Duration(ARun.DurationMs), Findings(ARun.Counts.Total)]);
  end;
end;

class function TAtlasTaskTexts.Blocked(const ARun: TAtlasTaskRun): string;
begin
  if ARun.Counts.Errors > 0 then
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGateErrors, [ARun.Name, ARun.Counts.Errors]);
  end
  else if ARun.Outcome = TAtlasTaskOutcome.Finished then
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGateExit, [ARun.Name, ARun.ExitCode]);
  end
  else
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGateNotRun, [ARun.Name]);
  end;
end;

class function TAtlasTaskTexts.LastResult(const ALast: TAtlasTaskLastRun; AHas: Boolean): string;
var
  mTime: string;
begin
  if not AHas then
  begin
    Exit(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNever));
  end;
  mTime := FormatDateTime('hh:nn', ALast.FinishedAt, FormatSettings);
  if ALast.Outcome <> TAtlasTaskOutcome.Finished then
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksNotRun, [mTime]);
  end
  else if ALast.Counts.Errors > 0 then
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksErrors, [ALast.Counts.Errors, mTime]);
  end
  else if ALast.ExitCode <> 0 then
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksExitCode, [ALast.ExitCode, mTime]);
  end
  else
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksPassed, [mTime]);
  end;
end;

class function TAtlasTaskTexts.Description(const ATask: TAtlasTaskDefinition; const ALastText: string): string;
begin
  Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksItemDescription, [GroupName(ATask.Group), ATask.CommandLine,
    ALastText]);
end;

class function TAtlasTaskTexts.Issue(const AIssue: TAtlasTaskIssue): string;
begin
  // Texte ohne Wert bzw. ohne Stelle lassen die überzähligen Argumente weg.
  Result := TAtlasBuildStrings.Fmt(cIssueTexts[AIssue.Kind], [AIssue.Where, AIssue.Value]);
end;

end.
