unit Atlas.UI.Undo.Messages;

// Texte zum dateiübergreifenden Zurücknehmen (#721) für Meldungsansicht und
// Ergebnisfenster: Ergebnis eines Zurücknehmens bzw. Wiederherstellens mit
// den Konflikten je Datei, Beschriftung der Sätze und Dateien in der Liste
// „Atlas-Änderungen“ und der Unterschied eines Satzes oder einer Datei.
// Die Meldungsansicht ist kein Protokoll: Hier stehen Dateinamen, damit der
// Benutzer die Konflikte findet; das Plugin-Protokoll bekommt sie nie (#647).

interface

uses
  System.SysUtils,
  Atlas.Core.Undo.Contract;

type
  TAtlasUndoMessages = class
  public
    /// <summary>Zeilen für die Meldungsansicht: Ergebnis und darunter je Datei, warum sie blieb.</summary>
    class function Report(const AReport: TAtlasUndoReport): TArray<string>; static;
    /// <summary>„Umbenennen: A → B · 4 Dateien · 14:03 · zurückgenommen“; die Uhrzeit mit Datum, wenn der
    /// Satz nicht von ANow (Tag) ist.</summary>
    class function SetCaption(const ASet: TAtlasChangeSet; ANow: TDateTime): string; static;
    /// <summary>„Unit1.pas (C:\Projekt) · neu · zurückgenommen“.</summary>
    class function FileCaption(const AChange: TAtlasFileChange): string; static;
    class function StateText(AState: TAtlasChangeSetState): string; static;
    /// <summary>Unterschied vorher → nachher; AFileName = '' für alle Dateien des Satzes, je Datei mit
    /// Überschrift.</summary>
    class function DiffLines(const ASet: TAtlasChangeSet; const AFileName: string): TArray<string>; static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Undo.Journal,
  Atlas.UI.Strings;

/// <summary>Kopfzeile des Berichts für ein abgebrochenes oder ausgeführtes Zurücknehmen bzw. Wiederherstellen
/// mit ACount Problemen.</summary>
function OutcomeLine(const AReport: TAtlasUndoReport; ACount: Integer): string;
const
  cAborted: array[Boolean] of TAtlasTextId = (TAtlasTextId.UndoAborted, TAtlasTextId.RedoAborted);
  cDone: array[Boolean] of TAtlasTextId = (TAtlasTextId.UndoDone, TAtlasTextId.RedoDone);
  cPartial: array[Boolean] of TAtlasTextId = (TAtlasTextId.UndoPartial, TAtlasTextId.RedoPartial);
begin
  if AReport.Aborted then
  begin
    Result := TAtlasStrings.Fmt(cAborted[AReport.Redo], [AReport.Action, ACount]);
  end
  else if ACount = 0 then
  begin
    Result := TAtlasStrings.Fmt(cDone[AReport.Redo], [AReport.Action, Length(AReport.Done)]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(cPartial[AReport.Redo], [AReport.Action, Length(AReport.Done), ACount]);
  end;
end;

/// <summary>Erste Zeile des Berichts: abgeschaltet, nichts gefunden oder das Ergebnis.</summary>
function HeadLine(const AReport: TAtlasUndoReport; ACount: Integer): string;
const
  cNothing: array[Boolean] of TAtlasTextId = (TAtlasTextId.UndoNothing, TAtlasTextId.RedoNothing);
begin
  if AReport.Disabled then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UndoDisabled);
  end
  else if AReport.NotFound then
  begin
    Result := TAtlasStrings.Text(cNothing[AReport.Redo]);
  end
  else
  begin
    Result := OutcomeLine(AReport, ACount);
  end;
end;

/// <summary>Zeile zu einer Datei, die blieb, mit dem Grund.</summary>
function ProblemLine(const AProblem: TAtlasUndoProblem): string;
begin
  case AProblem.Kind of
    TAtlasUndoProblemKind.ChangedSince:
      Result := TAtlasStrings.Fmt(TAtlasTextId.UndoConflictChanged, [AProblem.FileName]);
    TAtlasUndoProblemKind.Exists:
      Result := TAtlasStrings.Fmt(TAtlasTextId.UndoConflictExists, [AProblem.FileName]);
    TAtlasUndoProblemKind.Missing:
      Result := TAtlasStrings.Fmt(TAtlasTextId.UndoConflictMissing, [AProblem.FileName]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.UndoFailed, [AProblem.FileName, AProblem.Message]);
  end;
end;

class function TAtlasUndoMessages.Report(const AReport: TAtlasUndoReport): TArray<string>;
var
  mProblem: TAtlasUndoProblem;
  mProblems: TArray<TAtlasUndoProblem>;
begin
  // Ohne verschachtelte Array-Literale ([Fmt(…, […])]): An solchen hing dcc64 (Delphi 13) beim Übersetzen.
  mProblems := AReport.Conflicts + AReport.Errors;
  Result := nil;
  Result := Result + [HeadLine(AReport, Length(mProblems))];
  if AReport.Disabled or AReport.NotFound then
  begin
    Exit;
  end;
  for mProblem in mProblems do
  begin
    Result := Result + [ProblemLine(mProblem)];
  end;
end;

class function TAtlasUndoMessages.StateText(AState: TAtlasChangeSetState): string;
begin
  case AState of
    TAtlasChangeSetState.PartlyUndone:
      Result := TAtlasStrings.Text(TAtlasTextId.UndoStatePartly);
    TAtlasChangeSetState.Undone:
      Result := TAtlasStrings.Text(TAtlasTextId.UndoStateUndone);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.UndoStateApplied);
  end;
end;

class function TAtlasUndoMessages.SetCaption(const ASet: TAtlasChangeSet; ANow: TDateTime): string;
var
  Time: string;
begin
  if SameDate(ASet.Time, ANow) then
  begin
    Time := FormatDateTime('hh":"nn', ASet.Time);
  end
  else
  begin
    Time := FormatDateTime('dd.mm. hh":"nn', ASet.Time);
  end;
  Result := TAtlasStrings.Fmt(TAtlasTextId.UndoSetCaption, [ASet.Action, Length(ASet.Files), Time,
    StateText(ASet.State)]);
end;

class function TAtlasUndoMessages.FileCaption(const AChange: TAtlasFileChange): string;
begin
  Result := ExtractFileName(AChange.FileName);
  if ExtractFileDir(AChange.FileName) <> '' then
  begin
    Result := Result + ' (' + ExtractFileDir(AChange.FileName) + ')';
  end;
  case AChange.Kind of
    TAtlasFileChangeKind.Created:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UndoKindCreated);
    TAtlasFileChangeKind.Deleted:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UndoKindDeleted);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  if AChange.Undone then
  begin
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UndoStateUndone);
  end;
end;

class function TAtlasUndoMessages.DiffLines(const ASet: TAtlasChangeSet; const AFileName: string): TArray<string>;
var
  Change: TAtlasFileChange;
  Lines: TArray<string>;
begin
  Result := nil;
  for Change in ASet.Files do
  begin
    if (AFileName <> '') and not SameText(Change.FileName, AFileName) then
    begin
      Continue;
    end;
    Lines := TAtlasUndoJournal.Diff(Change);
    if Length(Lines) = 0 then
    begin
      Lines := [TAtlasStrings.Text(TAtlasTextId.UndoNoDiff)];
    end;
    if AFileName = '' then
    begin
      if Length(Result) > 0 then
      begin
        Result := Result + [''];
      end;
      Result := Result + ['=== ' + FileCaption(Change) + ' ==='];
    end;
    Result := Result + Lines;
  end;
end;

end.
