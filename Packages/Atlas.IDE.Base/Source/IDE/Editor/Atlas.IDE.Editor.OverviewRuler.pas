unit Atlas.IDE.Editor.OverviewRuler;

// Übersichtsleiste an der Scrollleiste (#519) in der IDE:
// - Jedes Editorfenster bekommt rechts neben dem Editor (und damit neben
//   seiner Scrollleiste) einen Streifen (TAtlasOverviewRuler, alRight im
//   Eltern-Steuerelement des Editors „Editor“). Fenster, die später aufgehen,
//   bekommen ihn beim nächsten Takt.
// - Ein Zeitgeber (200 ms) sammelt für die Ansicht vorn die Marken: Befunde
//   aus TAtlasProblemsController (#398; Fehler, Warnungen, Hinweise, ohne
//   inaktive Zweige und uses-Einträge), Treffer des markierten Texts (nach
//   einer Suche ist der Treffer markiert), Änderungen aus
//   TAtlasLineChangeMarks (#507, Modul Versionsverwaltung), Haltepunkte des Debuggers, die
//   Lesezeichen 0–9 der IDE (mit schnellen Lesezeichen, #1104, statt dessen
//   die Lesezeichen eines Moduls über IAtlasOverviewBookmarks, #1455) und den Cursor. Die Treffer sucht er erst nach
//   einer Tipp-Pause neu; der Streifen zeichnet nur bei geänderten Marken.
//   Mit „Gleichen Text hervorheben“ (#709, highlight.selectionMatches) gelten
//   dessen Mindestlänge, Groß-/Kleinschreibung, ganze Wörter und Obergrenze.
// - Klick springt zur Marke bzw. zur Zeile; Überfahren zeigt nach kurzer
//   Zeit die Zeile und die Beschreibung der Marke (TAtlasTitledTip).
// - editor.overviewRuler aus entfernt alle Streifen, editor.overviewRulerKinds
//   wählt die Arten.
// - Anlegen je Editorfenster, Wächter, Freigabe nach der Sperre durch die
//   IDE, Ausblenden bei ausgelöster Sicherung und Abbau übernimmt
//   TAtlasEditorBarHost (#1248).
// Minimap der IDE: Die Open Tools API bietet für sie keine Zeichen-Ereignisse,
// deshalb ein eigener Streifen (docs/Architektur.md). Die Minimap (#873)
// sammelt ihre Marken über CollectMarks. Nur im Hauptthread.

interface

uses
  ToolsAPI,
  Atlas.Core.Editor.Overview;

type
  TAtlasIdeOverviewRuler = class
  private class var
    FState: TObject;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Marken der Arten AKinds für AView (ALineCount Zeilen): Befunde, Treffer von ASearchTerm in den
    /// Zeilen ASearchLines, Änderungen, Haltepunkte, Lesezeichen, Cursor.</summary>
    class function CollectMarks(const AView: IOTAEditView; ALineCount: Integer; AKinds: TAtlasOverviewKinds;
      const ASearchTerm: string; const ASearchLines: TArray<Integer>): TAtlasOverviewMarks; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Math,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Editor.LineChanges,
  Atlas.Core.Editor.SelectionMatches,
  Atlas.UI.Strings,
  Atlas.UI.Popup.TitledTip,
  Atlas.UI.Editor.OverviewRuler,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Contracts.LineChanges;

const
  cTickMs = 200;
  /// <summary>Tipp-Pause, bevor die Treffer neu gesucht werden.</summary>
  cQuietMs = 400;
  cHoverMs = 250;
  /// <summary>Höchstlänge der Zeile in der Vorschau.</summary>
  cMaxPreview = 160;
  cBookmarkCount = 10;

type
  TOverviewState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FTip: TAtlasTitledTip;
    FKinds: TAtlasOverviewKinds;
    // Treffer: Text des Puffers und Suchtext, zu denen sie gehören.
    FFileName: string;
    FText: string;
    FChangedAt: UInt64;
    FLines: TArray<string>;
    FSearchText: string;
    FSearchTerm: string;
    /// <summary>Optionen von #709, mit denen die Treffer gesucht sind ('' = ohne #709).</summary>
    FSearchOptions: string;
    FSearchLines: TArray<Integer>;
    // Vorschau beim Überfahren.
    FHoverRuler: TAtlasOverviewRuler;
    FHoverLine: Integer;
    FHoverMark: Integer;
    FHoverPoint: TPoint;
    FHoverSince: UInt64;
    procedure Tick(Sender: TObject);
    function ActiveRuler: TAtlasOverviewRuler;
    function CreateRuler: TAtlasOverviewRuler;
    procedure Place(ARuler: TAtlasOverviewRuler; AParent: TWinControl);
    procedure Update;
    procedure RefreshSearch(const AView: IOTAEditView; const ATerm, AKey: string; AMatching: Boolean;
      const AOptions: TAtlasSelectionMatchOptions);
    function Collect(const AView: IOTAEditView; ALineCount: Integer): TAtlasOverviewMarks;
    procedure Jump(ARuler: TAtlasOverviewRuler; ALine: Integer);
    procedure Hover(ARuler: TAtlasOverviewRuler; ALine, AMark: Integer; const APoint: TPoint);
    procedure HoverEnd;
    procedure ShowPreview;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Removed(ARuler: TControl);
    procedure Reset;
    procedure ApplyTheme;
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.OverviewRuler and not TAtlasGuard.Disabled(TAtlasFeature.OverviewRuler);
end;

function Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
  begin
    Result := nil;
  end;
end;

{ TOverviewState }

constructor TOverviewState.Create;
begin
  inherited Create;
  FHost := TAtlasEditorBarHost.Create('Übersichtsleiste', TAtlasFeature.OverviewRuler,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateRuler;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      Place(TAtlasOverviewRuler(ABar), AEditorParent);
    end);
  FHost.OnRemoved :=
    procedure(ABar: TControl)
    begin
      Removed(ABar);
    end;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.OverviewRuler;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  Reset;
end;

destructor TOverviewState.Destroy;
begin
  FTimer.Free;
  FTip.Free;
  FHost.Free;
  inherited Destroy;
end;

procedure TOverviewState.Removed(ARuler: TControl);
begin
  if FHoverRuler = ARuler then
  begin
    HoverEnd;
  end;
end;

procedure TOverviewState.Reset;
begin
  FFileName := '';
  FText := '';
  FLines := nil;
  FSearchText := '';
  FSearchTerm := '';
  FSearchLines := nil;
  FKinds := TAtlasOverview.Kinds(TAtlasIdeSettings.Current.OverviewRulerKinds);
  HoverEnd;
end;

procedure TOverviewState.ApplyTheme;
begin
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasOverviewRuler(ABar).SetColors(TAtlasIdeStyle.Colors);
    end);
end;

/// <summary>Eigene Methode: Jeder Streifen braucht seine eigene gefangene Variable.</summary>
function TOverviewState.CreateRuler: TAtlasOverviewRuler;
var
  mRuler: TAtlasOverviewRuler;
begin
  mRuler := TAtlasOverviewRuler.Create(nil);
  Result := mRuler;
  mRuler.SetColors(TAtlasIdeStyle.Colors);
  mRuler.OnJump :=
    procedure(ALine: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.OverviewRuler,
        procedure
        begin
          Jump(mRuler, ALine);
        end);
    end;
  mRuler.OnHover :=
    procedure(ALine, AMark: Integer; const APoint: TPoint)
    begin
      Hover(mRuler, ALine, AMark, APoint);
    end;
  mRuler.OnHoverEnd :=
    procedure
    begin
      HoverEnd;
    end;
end;

procedure TOverviewState.Place(ARuler: TAtlasOverviewRuler; AParent: TWinControl);
begin
  if ARuler.Parent = AParent then
  begin
    Exit;
  end;
  // Rechts neben dem Editor: zuerst ganz rechts einhängen, dann rechts ausrichten.
  ARuler.Left := AParent.ClientWidth;
  ARuler.Align := alRight;
  ARuler.Parent := AParent;
end;

function TOverviewState.ActiveRuler: TAtlasOverviewRuler;
begin
  Result := TAtlasOverviewRuler(FHost.ActiveBar);
end;

function TOverviewState.Collect(const AView: IOTAEditView; ALineCount: Integer): TAtlasOverviewMarks;
begin
  Result := TAtlasIdeOverviewRuler.CollectMarks(AView, ALineCount, FKinds, FSearchTerm, FSearchLines);
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

function ProblemKind(ASeverity: TAtlasProblemSeverity): TAtlasOverviewMarkKind;
begin
  case ASeverity of
    TAtlasProblemSeverity.Error:
      Result := TAtlasOverviewMarkKind.Error;
    TAtlasProblemSeverity.Warning:
      Result := TAtlasOverviewMarkKind.Warning;
  else
    Result := TAtlasOverviewMarkKind.Info;
  end;
end;

/// <summary>Befunde der Datei ohne inaktive Zweige und uses-Einträge (die sind keine Befunde).</summary>
function DiagnosticMarks(const AFileName: string): TAtlasOverviewMarks;
var
  mStore: TAtlasProblemStore;
  mProblem: TAtlasProblem;
begin
  Result := nil;
  mStore := TAtlasProblemsController.Current;
  if mStore = nil then
  begin
    Exit;
  end;
  for mProblem in mStore.ForFile(AFileName) do
  begin
    if not mProblem.Unnecessary and (mProblem.UsesUnit = '') then
    begin
      Result := Result + [TAtlasOverviewMark.Create(ProblemKind(mProblem.Severity), mProblem.StartLine,
        Max(1, mProblem.EndLine - mProblem.StartLine + 1), mProblem.Message)];
    end;
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
      TAtlasStrings.Fmt(TAtlasTextId.OverviewSearch, [ASearchTerm]))];
  end;
end;

function ChangeMark(const AChange: TAtlasLineChange; ALineCount: Integer): TAtlasOverviewMark;
begin
  case AChange.Kind of
    TAtlasLineChangeKind.Added:
      Result := TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Added, AChange.Line, AChange.Count,
        TAtlasStrings.Text(TAtlasTextId.ChangeAddedTitle));
    TAtlasLineChangeKind.Modified:
      Result := TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Modified, AChange.Line, AChange.Count,
        TAtlasStrings.Text(TAtlasTextId.OverviewModified));
  else
    Result := TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Deleted, Min(AChange.Line, Max(0, ALineCount - 1)), 1,
      TAtlasStrings.Text(TAtlasTextId.OverviewDeleted));
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
      Result := Result + [ChangeMark(mChange, ALineCount)];
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
        1, TAtlasStrings.Text(TAtlasTextId.OverviewBreakpoint))];
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
        TAtlasStrings.Fmt(TAtlasTextId.OverviewBookmark, [mIndex]))];
    end;
  end;
end;

class function TAtlasIdeOverviewRuler.CollectMarks(const AView: IOTAEditView; ALineCount: Integer;
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
      TAtlasStrings.Text(TAtlasTextId.OverviewCursor))];
  end;
end;

/// <summary>Suchtext aus der einzeiligen Markierung von AView ('' ohne); mit „Gleichen Text hervorheben“
/// (AMatching) nach dessen Optionen AOptions, AKey beschreibt sie.</summary>
function SearchTermOf(const AView: IOTAEditView; AKinds: TAtlasOverviewKinds; out AMatching: Boolean;
  out AOptions: TAtlasSelectionMatchOptions; out AKey: string): string;
var
  mBlock: IOTAEditBlock;
  mNavigateF3: Boolean;
begin
  Result := '';
  AMatching := TAtlasIdeSettings.SelectionMatchesOn(AOptions, mNavigateF3);
  AKey := '';
  if AMatching then
  begin
    AKey := Format('%d|%d|%d|%d', [AOptions.MinLength, Ord(AOptions.CaseSensitive), Ord(AOptions.WholeWord),
      AOptions.MaxMatches]);
  end;
  if not (TAtlasOverviewKind.Search in AKinds) then
  begin
    Exit;
  end;
  mBlock := AView.Block;
  if (mBlock = nil) or not mBlock.IsValid or (mBlock.Size <= 0) or (mBlock.StartingRow <> mBlock.EndingRow) then
  begin
    Exit;
  end;
  if AMatching then
  begin
    TAtlasSelectionMatches.Term(mBlock.Text, AOptions, Result);
  end
  else
  begin
    TAtlasOverview.SearchTerm(mBlock.Text, Result);
  end;
end;

/// <summary>Treffer von ATerm neu suchen: neuer Suchtext sofort, geänderter Text erst nach der Tipp-Pause; nur
/// dann kostet der Text des Puffers etwas.</summary>
procedure TOverviewState.RefreshSearch(const AView: IOTAEditView; const ATerm, AKey: string; AMatching: Boolean;
  const AOptions: TAtlasSelectionMatchOptions);
var
  mText: string;
begin
  if not SameText(FFileName, AView.Buffer.FileName) then
  begin
    FFileName := AView.Buffer.FileName;
    FText := '';
    FSearchText := '';
    FSearchLines := nil;
    FChangedAt := 0;
  end;
  if ATerm = '' then
  begin
    FSearchTerm := '';
    FSearchLines := nil;
    Exit;
  end;
  mText := TAtlasEditorSnapshots.Get(AView).Text;
  if mText <> FText then
  begin
    FText := mText;
    FChangedAt := TThread.GetTickCount64;
  end;
  if (ATerm = FSearchTerm) and (AKey = FSearchOptions) and
    ((FText = FSearchText) or (TThread.GetTickCount64 - FChangedAt < cQuietMs)) then
  begin
    Exit;
  end;
  FLines := TTextLines.SplitLines(FText);
  if AMatching then
  begin
    FSearchLines := TAtlasSelectionMatches.Lines(TAtlasSelectionMatches.Find(FLines, ATerm, AOptions));
  end
  else
  begin
    FSearchLines := TAtlasOverview.Occurrences(FLines, ATerm);
  end;
  FSearchOptions := AKey;
  FSearchTerm := ATerm;
  FSearchText := FText;
end;

procedure TOverviewState.Update;
var
  mRuler: TAtlasOverviewRuler;
  mView: IOTAEditView;
  mTerm, mKey: string;
  mLineCount: Integer;
  mMatching: Boolean;
  mOptions: TAtlasSelectionMatchOptions;
begin
  FHost.Ensure;
  mRuler := ActiveRuler;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mRuler = nil) or (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mLineCount := mView.Buffer.GetLinesInBuffer;
  mTerm := SearchTermOf(mView, FKinds, mMatching, mOptions, mKey);
  RefreshSearch(mView, mTerm, mKey, mMatching, mOptions);
  mRuler.SetMarks(Collect(mView, mLineCount), mLineCount, mView.TopRow - 1, mView.BottomRow - 1);
  // Vorschau nach kurzer Zeit über der Marke.
  if (FHoverRuler <> nil) and (FHoverLine >= 0) and not FTip.IsShown and
    (TThread.GetTickCount64 - FHoverSince >= cHoverMs) then
  begin
    ShowPreview;
  end;
end;

procedure TOverviewState.Jump(ARuler: TAtlasOverviewRuler; ALine: Integer);
var
  mView: IOTAEditView;
begin
  HoverEnd;
  mView := TAtlasEditorBuffer.ActiveView;
  if (ARuler <> ActiveRuler) or (mView = nil) or (mView.Buffer = nil) or (ALine < 0) then
  begin
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(mView.Buffer.FileName, ALine, 0);
end;

procedure TOverviewState.Hover(ARuler: TAtlasOverviewRuler; ALine, AMark: Integer; const APoint: TPoint);
begin
  if FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
  FHoverRuler := ARuler;
  FHoverLine := ALine;
  FHoverMark := AMark;
  FHoverPoint := APoint;
  FHoverSince := TThread.GetTickCount64;
end;

procedure TOverviewState.HoverEnd;
begin
  FHoverRuler := nil;
  FHoverLine := -1;
  FHoverMark := -1;
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

procedure TOverviewState.ShowPreview;
var
  mView: IOTAEditView;
  mTitle, mText: string;
  mWidth: Integer;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if (FHoverRuler <> ActiveRuler) or (mView = nil) or (mView.Buffer = nil) then
  begin
    HoverEnd;
    Exit;
  end;
  mTitle := TAtlasStrings.Fmt(TAtlasTextId.OverviewLine, [FHoverLine + 1]);
  mText := Trim(TAtlasEditorBuffer.LineText(mView, FHoverLine + 1));
  if Length(mText) > cMaxPreview then
  begin
    mText := Copy(mText, 1, cMaxPreview) + '…';
  end;
  if (FHoverMark >= 0) and (FHoverMark <= High(FHoverRuler.Marks)) and (FHoverRuler.Marks[FHoverMark].Text <> '') then
  begin
    mTitle := mTitle + ' · ' + FHoverRuler.Marks[FHoverMark].Text;
  end;
  if mText = '' then
  begin
    mText := ' ';
  end;
  TAtlasIdeStyle.Apply(FTip, TRect.Create(FHoverPoint, FHoverPoint));
  // Links neben dem Streifen, damit die Maus ihn nicht verdeckt.
  mWidth := FTip.Measure(mTitle, mText).cx;
  FTip.ShowNote(mTitle, mText, Point(FHoverPoint.X - mWidth - MulDiv(12, FHoverRuler.CurrentPPI, 96), FHoverPoint.Y));
end;

procedure TOverviewState.Tick(Sender: TObject);
begin
  // Löst die Sicherung aus, blendet Guard die Streifen aus und danach wieder ein.
  if not TAtlasIdeSettings.Current.OverviewRuler or not FHost.Guard then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.OverviewRuler,
    procedure
    begin
      Update;
    end);
end;

{ TAtlasIdeOverviewRuler }

class procedure TAtlasIdeOverviewRuler.Install;
begin
  FreeAndNil(FState);
  if Active then
  begin
    FState := TOverviewState.Create;
  end;
end;

class procedure TAtlasIdeOverviewRuler.Uninstall;
begin
  FreeAndNil(FState);
end;

class procedure TAtlasIdeOverviewRuler.ApplySettings;
begin
  // Aus: alle Streifen weg, der Editor bekommt seine Breite zurück.
  if not Active then
  begin
    FreeAndNil(FState);
    Exit;
  end;
  if FState = nil then
  begin
    FState := TOverviewState.Create;
  end
  else
  begin
    TOverviewState(FState).Reset;
  end;
end;

class procedure TAtlasIdeOverviewRuler.ThemeChanged;
begin
  if FState <> nil then
  begin
    TOverviewState(FState).ApplyTheme;
  end;
end;

end.
