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
//   TAtlasIdeLineChanges (#507), Haltepunkte des Debuggers, die
//   Lesezeichen 0–9 der IDE (mit schnellen Lesezeichen, #1104, statt dessen
//   die Lesezeichen von Atlas über den Haken Bookmarks) und den Cursor. Die Treffer sucht er erst nach
//   einer Tipp-Pause neu; der Streifen zeichnet nur bei geänderten Marken.
//   Mit „Gleichen Text hervorheben“ (#709, highlight.selectionMatches) gelten
//   dessen Mindestlänge, Groß-/Kleinschreibung, ganze Wörter und Obergrenze.
// - Klick springt zur Marke bzw. zur Zeile; Überfahren zeigt nach kurzer
//   Zeit die Zeile und die Beschreibung der Marke (TAtlasNoteTip).
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
  /// <summary>Lesezeichen von Atlas für AFileName; False: keine eigenen, die Leiste zeigt die der IDE.</summary>
  TAtlasOverviewBookmarksFunc = reference to function(const AFileName: string; out AMarks: TAtlasOverviewMarks): Boolean;

  TAtlasIdeOverviewRuler = class
  private class var
    FState: TObject;
  public class var
    /// <summary>Kommt von der Komposition (#1104), damit Editor nicht von Bookmarks abhängt.</summary>
    Bookmarks: TAtlasOverviewBookmarksFunc;
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
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Editor.LineChanges,
  Atlas.Core.Editor.SelectionMatches,
  Atlas.UI.Strings,
  Atlas.UI.Notes.Tip,
  Atlas.UI.Editor.OverviewRuler,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Editor.LineChanges;

const
  TickMs = 200;
  /// <summary>Tipp-Pause, bevor die Treffer neu gesucht werden.</summary>
  QuietMs = 400;
  HoverMs = 250;
  /// <summary>Höchstlänge der Zeile in der Vorschau.</summary>
  MaxPreview = 160;
  BookmarkCount = 10;

type
  TOverviewState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FTip: TAtlasNoteTip;
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
    function CreateRuler(AParent: TWinControl): TAtlasOverviewRuler;
    procedure Place(ARuler: TAtlasOverviewRuler; AParent: TWinControl);
    procedure Update;
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
    Result := nil;
end;

{ TOverviewState }

constructor TOverviewState.Create;
begin
  inherited Create;
  FHost := TAtlasEditorBarHost.Create('Übersichtsleiste', TAtlasFeature.OverviewRuler,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateRuler(AEditorParent);
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
  FTip := TAtlasNoteTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.OverviewRuler;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
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
    HoverEnd;
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
function TOverviewState.CreateRuler(AParent: TWinControl): TAtlasOverviewRuler;
var
  Ruler: TAtlasOverviewRuler;
begin
  Ruler := TAtlasOverviewRuler.Create(nil);
  Result := Ruler;
  Ruler.SetColors(TAtlasIdeStyle.Colors);
  Ruler.OnJump :=
    procedure(ALine: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.OverviewRuler,
        procedure
        begin
          Jump(Ruler, ALine);
        end);
    end;
  Ruler.OnHover :=
    procedure(ALine, AMark: Integer; const APoint: TPoint)
    begin
      Hover(Ruler, ALine, AMark, APoint);
    end;
  Ruler.OnHoverEnd :=
    procedure
    begin
      HoverEnd;
    end;
end;

procedure TOverviewState.Place(ARuler: TAtlasOverviewRuler; AParent: TWinControl);
begin
  if ARuler.Parent = AParent then
    Exit;
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

class function TAtlasIdeOverviewRuler.CollectMarks(const AView: IOTAEditView; ALineCount: Integer;
  AKinds: TAtlasOverviewKinds; const ASearchTerm: string; const ASearchLines: TArray<Integer>): TAtlasOverviewMarks;
var
  Store: TAtlasProblemStore;
  Problem: TAtlasProblem;
  Kind: TAtlasOverviewMarkKind;
  Changes: TAtlasLineChangeList;
  Change: TAtlasLineChange;
  ChangeLines, Line, Index: Integer;
  Services: IOTADebuggerServices;
  Breakpoint: IOTASourceBreakpoint;
  Bookmark: TOTACharPos;
  FileName: string;
  Own: TAtlasOverviewMarks;
begin
  Result := nil;
  FileName := AView.Buffer.FileName;
  if TAtlasOverviewKind.Diagnostics in AKinds then
  begin
    Store := TAtlasProblemsController.Current;
    if Store <> nil then
      for Problem in Store.ForFile(FileName) do
      begin
        // Inaktive Zweige und uses-Einträge sind keine Befunde.
        if Problem.Unnecessary or (Problem.UsesUnit <> '') then
          Continue;
        case Problem.Severity of
          TAtlasProblemSeverity.Error:
            Kind := TAtlasOverviewMarkKind.Error;
          TAtlasProblemSeverity.Warning:
            Kind := TAtlasOverviewMarkKind.Warning;
        else
          Kind := TAtlasOverviewMarkKind.Info;
        end;
        Result := Result + [TAtlasOverviewMark.Create(Kind, Problem.StartLine,
          Max(1, Problem.EndLine - Problem.StartLine + 1), Problem.Message)];
      end;
  end;
  if (TAtlasOverviewKind.Search in AKinds) and (ASearchTerm <> '') then
    for Line in ASearchLines do
      Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, Line, 1,
        TAtlasStrings.Fmt(TAtlasTextId.OverviewSearch, [ASearchTerm]))];
  if (TAtlasOverviewKind.Changes in AKinds) and TAtlasIdeLineChanges.Snapshot(FileName, Changes, ChangeLines) and
    (ChangeLines = ALineCount) then
    for Change in Changes do
      case Change.Kind of
        TAtlasLineChangeKind.Added:
          Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Added, Change.Line, Change.Count,
            TAtlasStrings.Text(TAtlasTextId.ChangeAddedTitle))];
        TAtlasLineChangeKind.Modified:
          Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Modified, Change.Line, Change.Count,
            TAtlasStrings.Text(TAtlasTextId.OverviewModified))];
      else
        Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Deleted,
          Min(Change.Line, Max(0, ALineCount - 1)), 1, TAtlasStrings.Text(TAtlasTextId.OverviewDeleted))];
      end;
  if TAtlasOverviewKind.Breakpoints in AKinds then
  begin
    Services := Debugger;
    if Services <> nil then
      for Index := 0 to Services.SourceBkptCount - 1 do
      begin
        Breakpoint := Services.SourceBkpts[Index];
        if (Breakpoint <> nil) and SameText(Breakpoint.FileName, FileName) and (Breakpoint.LineNumber > 0) then
          Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Breakpoint, Breakpoint.LineNumber - 1,
            1, TAtlasStrings.Text(TAtlasTextId.OverviewBreakpoint))];
      end;
  end;
  if (TAtlasOverviewKind.Bookmarks in AKinds) and Assigned(Bookmarks) and Bookmarks(FileName, Own) then
    Result := Result + Own
  else if TAtlasOverviewKind.Bookmarks in AKinds then
    for Index := 0 to BookmarkCount - 1 do
    begin
      Bookmark := AView.BookmarkPos[Index];
      if Bookmark.Line > 0 then
        Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, Bookmark.Line - 1, 1,
          TAtlasStrings.Fmt(TAtlasTextId.OverviewBookmark, [Index]))];
    end;
  if TAtlasOverviewKind.Cursor in AKinds then
    Result := Result + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, AView.CursorPos.Line - 1, 1,
      TAtlasStrings.Text(TAtlasTextId.OverviewCursor))];
end;

procedure TOverviewState.Update;
var
  Ruler: TAtlasOverviewRuler;
  View: IOTAEditView;
  Block: IOTAEditBlock;
  Text, Term, Key: string;
  LineCount: Integer;
  Matching, NavigateF3: Boolean;
  Options: TAtlasSelectionMatchOptions;
begin
  FHost.Ensure;
  Ruler := ActiveRuler;
  View := TAtlasEditorBuffer.ActiveView;
  if (Ruler = nil) or (View = nil) or (View.Buffer = nil) then
    Exit;
  LineCount := View.Buffer.GetLinesInBuffer;
  // Suchtext aus der Markierung (einzeilig); nur dann kostet der Text des Puffers etwas.
  Term := '';
  Matching := TAtlasIdeSettings.SelectionMatchesOn(Options, NavigateF3);
  Key := '';
  if Matching then
    Key := Format('%d|%d|%d|%d', [Options.MinLength, Ord(Options.CaseSensitive), Ord(Options.WholeWord),
      Options.MaxMatches]);
  if TAtlasOverviewKind.Search in FKinds then
  begin
    Block := View.Block;
    if (Block <> nil) and Block.IsValid and (Block.Size > 0) and (Block.StartingRow = Block.EndingRow) then
    begin
      if Matching then
        TAtlasSelectionMatches.Term(Block.Text, Options, Term)
      else
        TAtlasOverview.SearchTerm(Block.Text, Term);
    end;
  end;
  if not SameText(FFileName, View.Buffer.FileName) then
  begin
    FFileName := View.Buffer.FileName;
    FText := '';
    FSearchText := '';
    FSearchLines := nil;
    FChangedAt := 0;
  end;
  if Term = '' then
  begin
    FSearchTerm := '';
    FSearchLines := nil;
  end
  else
  begin
    Text := TAtlasEditorBuffer.Text(View.Buffer);
    if Text <> FText then
    begin
      FText := Text;
      FChangedAt := TThread.GetTickCount64;
    end;
    // Neuer Suchtext sofort, geänderter Text erst nach der Tipp-Pause.
    if (Term <> FSearchTerm) or (Key <> FSearchOptions) or
      ((FText <> FSearchText) and (TThread.GetTickCount64 - FChangedAt >= QuietMs)) then
    begin
      FLines := TTextLines.SplitLines(FText);
      if Matching then
        FSearchLines := TAtlasSelectionMatches.Lines(TAtlasSelectionMatches.Find(FLines, Term, Options))
      else
        FSearchLines := TAtlasOverview.Occurrences(FLines, Term);
      FSearchOptions := Key;
      FSearchTerm := Term;
      FSearchText := FText;
    end;
  end;
  Ruler.SetMarks(Collect(View, LineCount), LineCount, View.TopRow - 1, View.BottomRow - 1);
  // Vorschau nach kurzer Zeit über der Marke.
  if (FHoverRuler <> nil) and (FHoverLine >= 0) and not FTip.IsShown and
    (TThread.GetTickCount64 - FHoverSince >= HoverMs) then
    ShowPreview;
end;

procedure TOverviewState.Jump(ARuler: TAtlasOverviewRuler; ALine: Integer);
var
  View: IOTAEditView;
begin
  HoverEnd;
  View := TAtlasEditorBuffer.ActiveView;
  if (ARuler <> ActiveRuler) or (View = nil) or (View.Buffer = nil) or (ALine < 0) then
    Exit;
  TAtlasIdeNavigation.GoToLocation(View.Buffer.FileName, ALine, 0);
end;

procedure TOverviewState.Hover(ARuler: TAtlasOverviewRuler; ALine, AMark: Integer; const APoint: TPoint);
begin
  if FTip.IsShown then
    FTip.HidePopup;
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
    FTip.HidePopup;
end;

procedure TOverviewState.ShowPreview;
var
  View: IOTAEditView;
  Title, Text: string;
  Width: Integer;
begin
  View := TAtlasEditorBuffer.ActiveView;
  if (FHoverRuler <> ActiveRuler) or (View = nil) or (View.Buffer = nil) then
  begin
    HoverEnd;
    Exit;
  end;
  Title := TAtlasStrings.Fmt(TAtlasTextId.OverviewLine, [FHoverLine + 1]);
  Text := Trim(TAtlasEditorBuffer.LineText(View, FHoverLine + 1));
  if Length(Text) > MaxPreview then
    Text := Copy(Text, 1, MaxPreview) + '…';
  if (FHoverMark >= 0) and (FHoverMark <= High(FHoverRuler.Marks)) and (FHoverRuler.Marks[FHoverMark].Text <> '') then
    Title := Title + ' · ' + FHoverRuler.Marks[FHoverMark].Text;
  if Text = '' then
    Text := ' ';
  TAtlasIdeStyle.Apply(FTip, TRect.Create(FHoverPoint, FHoverPoint));
  // Links neben dem Streifen, damit die Maus ihn nicht verdeckt.
  Width := FTip.Measure(Title, Text).cx;
  FTip.ShowNote(Title, Text, Point(FHoverPoint.X - Width - MulDiv(12, FHoverRuler.CurrentPPI, 96), FHoverPoint.Y));
end;

procedure TOverviewState.Tick(Sender: TObject);
begin
  // Löst die Sicherung aus, blendet Guard die Streifen aus und danach wieder ein.
  if not TAtlasIdeSettings.Current.OverviewRuler or not FHost.Guard then
    Exit;
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
    FState := TOverviewState.Create;
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
    FState := TOverviewState.Create
  else
    TOverviewState(FState).Reset;
end;

class procedure TAtlasIdeOverviewRuler.ThemeChanged;
begin
  if FState <> nil then
    TOverviewState(FState).ApplyTheme;
end;

end.
