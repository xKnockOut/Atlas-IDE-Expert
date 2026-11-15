unit Atlas.IDE.Editor.OverviewMarks;

// Marken der Übersichtsleiste (#519) und der Minimap (#873) aus der IDE einsammeln: Befunde aus
// TAtlasProblemsController (ohne inaktive Zweige und uses-Einträge), Treffer eines Suchtexts, Änderungen aus
// TAtlasLineChangeMarks (#507), Haltepunkte des Debuggers, Lesezeichen eines Moduls (IAtlasOverviewBookmarks,
// #1455) bzw. die Lesezeichen 0–9 der IDE und der Cursor. Eigene Unit, damit Atlas.IDE.Editor.OverviewRuler nur
// Streifen, Takt und Vorschau verwaltet. Nur im Hauptthread.

interface

uses
  ToolsAPI,
  Atlas.Core.Editor.Overview;

type
  TAtlasIdeOverviewMarks = class
  public
    /// <summary>Marken der Arten AKinds für AView (ALineCount Zeilen): Befunde, Treffer von ASearchTerm in den
    /// Zeilen ASearchLines, Änderungen, Haltepunkte, Lesezeichen, Cursor.</summary>
    class function Collect(const AView: IOTAEditView; ALineCount: Integer; AKinds: TAtlasOverviewKinds;
      const ASearchTerm: string; const ASearchLines: TArray<Integer>): TAtlasOverviewMarks; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Problems.Store,
  Atlas.Core.Editor.LineChanges,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Strings,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Contracts.LineChanges;

const
  cBookmarkCount = 10;

function Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
  begin
    Result := nil;
  end;
end;

/// <summary>Eigene Lesezeichen des ersten laufenden Moduls, das welche für AFileName hat (#1455); False ohne.</summary>
function ModuleBookmarks(const AFileName: string; out AMarks: TAtlasOverviewMarks): Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mItem: IInterface;
begin
  Result := False;
  AMarks := nil;
  mRegistry := AtlasModuleRegistry;
  if mRegistry = nil then
  begin
    Exit;
  end;
  for mItem in TAtlasModuleContributions.Active(mRegistry, IAtlasOverviewBookmarks) do
  begin
    if (mItem as IAtlasOverviewBookmarks).Marks(AFileName, AMarks) then
    begin
      Exit(True);
    end;
  end;
  AMarks := nil;
end;

/// <summary>Befunde der Datei ohne inaktive Zweige und uses-Einträge (die sind keine Befunde).</summary>
function DiagnosticMarks(const AFileName: string): TAtlasOverviewMarks;
var
  mStore: TAtlasProblemStore;
begin
  Result := nil;
  mStore := TAtlasProblemsController.Current;
  if mStore <> nil then
  begin
    Result := TAtlasOverview.ProblemMarks(mStore.ForFile(AFileName));
  end;
end;

function SearchMarks(const ASearchTerm: string; const ASearchLines: TArray<Integer>): TAtlasOverviewMarks;
var
  mLine: Integer;
begin
  Result := nil;
  for mLine in ASearchLines do
  begin
    Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, mLine, 1,
      TAtlasEditorStrings.Fmt(TAtlasEditorTextId.OverviewSearch, [ASearchTerm]))];
  end;
end;

/// <summary>Änderungen, wenn sie zum Stand mit ALineCount Zeilen gehören.</summary>
function ChangeMarks(const AFileName: string; ALineCount: Integer): TAtlasOverviewMarks;
var
  mChanges: TAtlasLineChangeList;
  mChange: TAtlasLineChange;
  mChangeLines: Integer;
begin
  Result := nil;
  if TAtlasLineChangeMarks.Current.Snapshot(AFileName, mChanges, mChangeLines) and (mChangeLines = ALineCount) then
  begin
    for mChange in mChanges do
    begin
      Result := Result + [TAtlasOverview.ChangeMark(mChange, ALineCount,
        TAtlasStrings.Text(TAtlasTextId.ChangeAddedTitle),
        TAtlasEditorStrings.Text(TAtlasEditorTextId.OverviewModified),
        TAtlasEditorStrings.Text(TAtlasEditorTextId.OverviewDeleted))];
    end;
  end;
end;

function BreakpointMarks(const AFileName: string): TAtlasOverviewMarks;
var
  mServices: IOTADebuggerServices;
  mBreakpoint: IOTASourceBreakpoint;
  mIndex: Integer;
begin
  Result := nil;
  mServices := Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint <> nil) and SameText(mBreakpoint.FileName, AFileName) and (mBreakpoint.LineNumber > 0) then
    begin
      Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Breakpoint, mBreakpoint.LineNumber - 1,
        1, TAtlasEditorStrings.Text(TAtlasEditorTextId.OverviewBreakpoint))];
    end;
  end;
end;

/// <summary>Lesezeichen eines Moduls (#1455), sonst die Lesezeichen 0–9 der IDE.</summary>
function BookmarkMarks(const AView: IOTAEditView; const AFileName: string): TAtlasOverviewMarks;
var
  mBookmark: TOTACharPos;
  mIndex: Integer;
begin
  if ModuleBookmarks(AFileName, Result) then
  begin
    Exit;
  end;
  Result := nil;
  for mIndex := 0 to cBookmarkCount - 1 do
  begin
    mBookmark := AView.BookmarkPos[mIndex];
    if mBookmark.Line > 0 then
    begin
      Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, mBookmark.Line - 1, 1,
        TAtlasEditorStrings.Fmt(TAtlasEditorTextId.OverviewBookmark, [mIndex]))];
    end;
  end;
end;

{ TAtlasIdeOverviewMarks }

class function TAtlasIdeOverviewMarks.Collect(const AView: IOTAEditView; ALineCount: Integer;
  AKinds: TAtlasOverviewKinds; const ASearchTerm: string; const ASearchLines: TArray<Integer>): TAtlasOverviewMarks;
var
  mFileName: string;
begin
  Result := nil;
  mFileName := AView.Buffer.FileName;
  if TAtlasOverviewKind.Diagnostics in AKinds then
  begin
    Result := Result + DiagnosticMarks(mFileName);
  end;
  if (TAtlasOverviewKind.Search in AKinds) and (ASearchTerm <> '') then
  begin
    Result := Result + SearchMarks(ASearchTerm, ASearchLines);
  end;
  if TAtlasOverviewKind.Changes in AKinds then
  begin
    Result := Result + ChangeMarks(mFileName, ALineCount);
  end;
  if TAtlasOverviewKind.Breakpoints in AKinds then
  begin
    Result := Result + BreakpointMarks(mFileName);
  end;
  if TAtlasOverviewKind.Bookmarks in AKinds then
  begin
    Result := Result + BookmarkMarks(AView, mFileName);
  end;
  if TAtlasOverviewKind.Cursor in AKinds then
  begin
    Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, AView.CursorPos.Line - 1, 1,
      TAtlasEditorStrings.Text(TAtlasEditorTextId.OverviewCursor))];
  end;
end;

end.
