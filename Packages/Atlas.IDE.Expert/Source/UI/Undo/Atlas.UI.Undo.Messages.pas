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

class function TAtlasUndoMessages.Report(const AReport: TAtlasUndoReport): TArray<string>;
var
  Problem: TAtlasUndoProblem;
  Problems: TArray<TAtlasUndoProblem>;
  Line: string;
begin
  if AReport.Disabled then
    Exit([TAtlasStrings.Text(TAtlasTextId.UndoDisabled)]);
  if AReport.NotFound then
  begin
    if AReport.Redo then
      Exit([TAtlasStrings.Text(TAtlasTextId.RedoNothing)]);
    Exit([TAtlasStrings.Text(TAtlasTextId.UndoNothing)]);
  end;
  Problems := AReport.Conflicts + AReport.Errors;
  if AReport.Aborted then
  begin
    if AReport.Redo then
      Line := TAtlasStrings.Fmt(TAtlasTextId.RedoAborted, [AReport.Action, Length(Problems)])
    else
      Line := TAtlasStrings.Fmt(TAtlasTextId.UndoAborted, [AReport.Action, Length(Problems)]);
  end
  else if Length(Problems) = 0 then
  begin
    if AReport.Redo then
      Exit([TAtlasStrings.Fmt(TAtlasTextId.RedoDone, [AReport.Action, Length(AReport.Done)])]);
    Exit([TAtlasStrings.Fmt(TAtlasTextId.UndoDone, [AReport.Action, Length(AReport.Done)])]);
  end
  else if AReport.Redo then
    Line := TAtlasStrings.Fmt(TAtlasTextId.RedoPartial, [AReport.Action, Length(AReport.Done), Length(Problems)])
  else
    Line := TAtlasStrings.Fmt(TAtlasTextId.UndoPartial, [AReport.Action, Length(AReport.Done), Length(Problems)]);
  Result := [Line];
  for Problem in Problems do
    case Problem.Kind of
      TAtlasUndoProblemKind.ChangedSince:
        Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.UndoConflictChanged, [Problem.FileName])];
      TAtlasUndoProblemKind.Exists:
        Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.UndoConflictExists, [Problem.FileName])];
      TAtlasUndoProblemKind.Missing:
        Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.UndoConflictMissing, [Problem.FileName])];
    else
      Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.UndoFailed, [Problem.FileName, Problem.Message])];
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
    Time := FormatDateTime('hh:nn', ASet.Time)
  else
    Time := FormatDateTime('dd.mm. hh:nn', ASet.Time);
  Result := TAtlasStrings.Fmt(TAtlasTextId.UndoSetCaption, [ASet.Action, Length(ASet.Files), Time,
    StateText(ASet.State)]);
end;

class function TAtlasUndoMessages.FileCaption(const AChange: TAtlasFileChange): string;
begin
  Result := ExtractFileName(AChange.FileName);
  if ExtractFileDir(AChange.FileName) <> '' then
    Result := Result + ' (' + ExtractFileDir(AChange.FileName) + ')';
  case AChange.Kind of
    TAtlasFileChangeKind.Created:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UndoKindCreated);
    TAtlasFileChangeKind.Deleted:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UndoKindDeleted);
  end;
  if AChange.Undone then
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UndoStateUndone);
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
      Continue;
    Lines := TAtlasUndoJournal.Diff(Change);
    if Length(Lines) = 0 then
      Lines := [TAtlasStrings.Text(TAtlasTextId.UndoNoDiff)];
    if AFileName = '' then
    begin
      if Length(Result) > 0 then
        Result := Result + [''];
      Result := Result + ['=== ' + FileCaption(Change) + ' ==='];
    end;
    Result := Result + Lines;
  end;
end;

end.
