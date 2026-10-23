unit Atlas.IDE.Editor.LineChanges;

// Änderungsmarken und Zeilenhistorie (#507) im Editor:
// - Ein Zeitgeber (150 ms) beobachtet die Datei im oberen Editor. Liegt sie
//   in einer Arbeitskopie (TAtlasIdeVcs, #571; Git oder SVN), holt Atlas im
//   Hintergrund ihren Stand im Repository (FileAt, Git HEAD, SVN BASE) und
//   vergleicht ihn nach einer Tipp-Pause (QuietMs) ebenfalls im Hintergrund
//   zeilenweise mit dem Puffer (TAtlasLineChanges). Ein Commit (andere
//   ChangeMarker) lädt den Stand neu. Ohne Arbeitskopie, ohne git bzw. svn
//   oder bei einer nicht versionierten Datei bleibt alles still.
// - Rinne (editor.gitGutter): am rechten Rand ein Balken je Zeile, grün
//   hinzugefügt, blau geändert, ein rotes Dreieck an der Zeile unter einer
//   Löschung (am Dateiende an der letzten Zeile). Farben aus dem Grund der
//   Rinne (TAtlasColors.ForBackground, passt zu hellem und dunklem Thema).
// - Klick auf eine Marke zeigt den alten Stand in einem kleinen Fenster
//   (TAtlasNoteTip) mit „Zurücksetzen“: Die Änderung geht über
//   TAtlasIdeWorkspaceEdit (#397) in den Puffer, Strg+Z nimmt sie zurück.
// - GoToChange springt reihum zur nächsten bzw. vorigen Änderung
//   (keys.nextChange, keys.previousChange).
// - Zeilenhistorie (editor.gitBlame): blame der Datei auf der Platte im
//   Hintergrund, neu nach dem Speichern und nach einem Commit. Am Ende der
//   Cursorzeile gedimmt „Autor, vor 3 Tagen · Betreff“; ungespeicherte Zeilen
//   ordnet der Vergleich Platte → Puffer zu („Noch nicht gespeichert“).
//   Überfahren zeigt den Commit mit Revision, Autor, Datum und Betreff.
//   Den Platz hinter dem Zeilenende teilt der Text mit Inlay-Hints,
//   Blockende-Beschriftungen und Fehlertext (TAtlasLineTail).
// - Beide Elemente lassen sich je Datei in .atlas ausblenden (#628).
// Gesichert über TAtlasFeature.LineChanges. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.LineChanges;

type
  TAtlasIdeLineChanges = class
  private class var
    FState: TObject;
    FMessage: TProc<string>;
  public
    /// <summary>AMessage zeigt eine Zeile in der Meldungsansicht (etwa, wenn Zurücksetzen scheitert).</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Cursor auf die erste Zeile der nächsten (AForward) bzw. vorigen Änderung, reihum.</summary>
    class procedure GoToChange(AForward: Boolean); static;
    /// <summary>Sind die Änderungsmarken eingeschaltet (für Palette und Tastenkürzel)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Letzter Vergleich für AFileName (Übersichtsleiste #519); False ohne (aus, andere Datei, keine
    /// Arbeitskopie).</summary>
    class function Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList;
      out ALineCount: Integer): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Types,
  System.Math,
  System.DateUtils,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Text.Lines,
  Atlas.Text.Diff,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Vcs.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Notes.Tip,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Vcs.Service;

const
  TickMs = 150;
  /// <summary>Tipp-Pause vor dem Vergleich.</summary>
  QuietMs = 300;
  /// <summary>So oft prüft Atlas Commit (ChangeMarker) und Speichern (Zeitstempel der Datei).</summary>
  PollMs = 1000;
  HoverMs = 400;
  /// <summary>Höchstens so viele alte Zeilen im Fenster.</summary>
  MaxOldLines = 15;
  /// <summary>Deckkraft der Zeilenhistorie über dem Hintergrund.</summary>
  BlameStrength = 0.55;

type
  TEvents = class(TNTACodeEditorNotifier)
  protected
    function AllowedEvents: TCodeEditorEvents; override;
    function AllowedGutterStages: TPaintGutterStages; override;
    function AllowedLineStages: TPaintLineStages; override;
  end;

  /// <summary>Gezeichnete Marke einer Rinnenzeile (Koordinaten des Editors).</summary>
  TMarkRow = record
    FileName: string;
    Line: Integer;
    Change: Integer;
    Rect: TRect;
    TopRow: Integer;
  end;

  TLineChangesState = class
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FTip: TAtlasNoteTip;
    FFont: TFont;
    FFontKey: string;
    FGutterOn: Boolean;
    FBlameOn: Boolean;
    // Datei vorn und ihr Stand.
    FFileName: string;
    FVcs: IAtlasVersionControl;
    FText: string;
    FChangedAt: UInt64;
    FPolledAt: UInt64;
    FMarker: string;
    FDiskAge: TDateTime;
    // Stand im Repository; FHeadOk erst nach erfolgreichem FileAt.
    FHead: TArray<string>;
    FHeadOk: Boolean;
    FHeadWanted: Boolean;
    FHeadBusy: Boolean;
    // Ergebnis des letzten Vergleichs und der Text, zu dem es gehört.
    FDiffText: string;
    FDiffBusy: Boolean;
    FLines: TArray<string>;
    FLineBreak: string;
    FChanges: TAtlasLineChangeList;
    FShown: Boolean;
    // Zeilenhistorie der Datei auf der Platte.
    FBlame: TArray<TAtlasVcsBlameLine>;
    FDisk: TArray<string>;
    FDiskHunks: TArray<TTextLineHunk>;
    FBlameOk: Boolean;
    FBlameWanted: Boolean;
    FBlameBusy: Boolean;
    // Gezeichnete Marken je Bildschirmzeile und der Text der Historie.
    FRows: TDictionary<Integer, TMarkRow>;
    FBlameRect: TRect;
    FBlameTopRow: Integer;
    FBlameEntry: Integer;
    FBlameUnsaved: Boolean;
    // Überfahren der Historie.
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    // Fenster „alter Stand“: offen für diesen Block.
    FTipChange: Integer;
    FTipEntered: Boolean;
    procedure Tick(Sender: TObject);
    procedure Reset;
    procedure Track(const AView: IOTAEditView);
    procedure Poll;
    procedure LoadHead;
    procedure LoadBlame;
    procedure Compare;
    procedure CheckHover;
    procedure ShowChange(AChange: Integer; const AScreen: TRect);
    procedure ShowCommit;
    procedure HideTip;
    procedure RevertChange(AChange: Integer);
    function Fresh: Boolean;
    function BlameCaption(ABufferLine: Integer; out AEntry: Integer; out AUnsaved: Boolean): string;
    procedure EnsureFont(const AEditorFont: TFont);
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure GoToChange(AForward: Boolean);
  end;

var
  // Jede Hintergrundarbeit merkt sich die Generation; nach Reset oder Freigabe verfällt ihr Ergebnis.
  Generation: Integer;

function Active: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := (Settings.GitGutter or Settings.GitBlame) and not TAtlasGuard.Disabled(TAtlasFeature.LineChanges);
end;

function Current: TLineChangesState;
begin
  Result := TLineChangesState(TAtlasIdeLineChanges.FState);
end;

procedure Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

function TopView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Result := Editors.TopView;
end;

/// <summary>Editorspalte (1-basiert) hinter dem letzten Zeichen von ALine; Tabs aufgelöst.</summary>
function EndColumn(const ALine: string; ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(TrimRight(ALine), ATabWidth)) + 1;
end;

function AgeText(const AAge: TAtlasAge): string;
begin
  case AAge.Unit_ of
    TAtlasAgeUnit.Minutes:
      Result := TAtlasStrings.Fmt(TAtlasTextId.BlameMinutes, [AAge.Count]);
    TAtlasAgeUnit.Hours:
      Result := TAtlasStrings.Fmt(TAtlasTextId.BlameHours, [AAge.Count]);
    TAtlasAgeUnit.Yesterday:
      Result := TAtlasStrings.Text(TAtlasTextId.BlameYesterday);
    TAtlasAgeUnit.Days:
      Result := TAtlasStrings.Fmt(TAtlasTextId.BlameDays, [AAge.Count]);
    TAtlasAgeUnit.Months:
      if AAge.Count = 1 then
        Result := TAtlasStrings.Text(TAtlasTextId.BlameMonth)
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.BlameMonths, [AAge.Count]);
    TAtlasAgeUnit.Years:
      if AAge.Count = 1 then
        Result := TAtlasStrings.Text(TAtlasTextId.BlameYear)
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.BlameYears, [AAge.Count]);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.BlameJustNow);
  end;
end;

{ TEvents }

function TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevPaintLineEvents, cevMouseEvents];
end;

function TEvents.AllowedGutterStages: TPaintGutterStages;
begin
  // Nur die letzte Stufe: Die Marken liegen über dem, was die IDE gezeichnet hat.
  Result := [High(TPaintGutterStage)];
end;

function TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TLineChangesState }

constructor TLineChangesState.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  Inc(Generation);
  FIndex := -1;
  FTipChange := -1;
  FBlameEntry := -1;
  FRows := TDictionary<Integer, TMarkRow>.Create;
  FFont := TFont.Create;
  FTip := TAtlasNoteTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.LineChanges;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TLineChangesState.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Ergebnisse, die noch unterwegs sind, verfallen.
  Inc(Generation);
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintGutter := nil;
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseMove := nil;
  FEvents.OnEditorMouseDown := nil;
  FEventsRef := nil;
  FTip.OnLink := nil;
  FTip.Free;
  FFont.Free;
  FRows.Free;
  Invalidate;
  inherited Destroy;
end;

procedure TLineChangesState.Reset;
begin
  Inc(Generation);
  HideTip;
  FHovering := False;
  FFileName := '';
  FVcs := nil;
  FText := '';
  FMarker := '';
  FDiskAge := 0;
  FHead := nil;
  FHeadOk := False;
  FHeadWanted := False;
  FHeadBusy := False;
  FDiffText := '';
  FDiffBusy := False;
  FLines := nil;
  FChanges := nil;
  FBlame := nil;
  FDisk := nil;
  FDiskHunks := nil;
  FBlameOk := False;
  FBlameWanted := False;
  FBlameBusy := False;
  FBlameEntry := -1;
  FRows.Clear;
  if FShown then
  begin
    FShown := False;
    Invalidate;
  end;
end;

function TLineChangesState.Fresh: Boolean;
begin
  // Der letzte Vergleich gehört zum Text im Puffer.
  Result := FHeadOk and (FDiffText = FText) and (FLines <> nil);
end;

procedure TLineChangesState.Tick(Sender: TObject);
var
  Settings: TAtlasPluginSettings;
  View: IOTAEditView;
begin
  try
    Settings := TAtlasIdeSettings.Current;
    FGutterOn := Settings.GitGutter;
    FBlameOn := Settings.GitBlame;
    View := TopView;
    if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
      Exit;
    Track(View);
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

procedure TLineChangesState.Track(const AView: IOTAEditView);
var
  Text: string;
begin
  if not SameText(FFileName, AView.Buffer.FileName) then
  begin
    // Andere Datei vorn: neu beginnen; ohne Arbeitskopie bleibt FVcs leer und alles still.
    Reset;
    FFileName := AView.Buffer.FileName;
    FText := TAtlasEditorBuffer.Text(AView.Buffer);
    FChangedAt := 0;
    FPolledAt := 0;
  end;
  if FVcs = nil then
  begin
    // Prüft nur Dateien; einmal je PollMs, damit ein späteres git init oder der Start der Versionsverwaltung greift.
    if TThread.GetTickCount64 - FPolledAt < PollMs then
      Exit;
    FPolledAt := TThread.GetTickCount64;
    FVcs := TAtlasIdeVcs.ForFolder(ExtractFileDir(FFileName));
    if (FVcs <> nil) and (FVcs.Kind = TAtlasVcsKind.None) then
      FVcs := nil;
    if FVcs = nil then
      Exit;
    FMarker := FVcs.ChangeMarker;
    if not FileAge(FFileName, FDiskAge) then
      FDiskAge := 0;
    FHeadWanted := True;
    FBlameWanted := True;
  end;
  Text := TAtlasEditorBuffer.Text(AView.Buffer);
  if Text <> FText then
  begin
    FText := Text;
    FChangedAt := TThread.GetTickCount64;
    // Der alte Stand im Fenster passt nicht mehr zum Puffer.
    if FTipChange >= 0 then
      HideTip;
  end;
  if TThread.GetTickCount64 - FPolledAt >= PollMs then
    Poll;
  if FGutterOn or FBlameOn then
  begin
    if FHeadWanted and not FHeadBusy then
      LoadHead;
    if FBlameOn and FBlameWanted and not FBlameBusy then
      LoadBlame;
    if FHeadOk and not FDiffBusy and (FText <> FDiffText) and
      (TThread.GetTickCount64 - FChangedAt >= QuietMs) then
      Compare;
  end;
end;

procedure TLineChangesState.Poll;
var
  Marker: string;
  Age: TDateTime;
begin
  FPolledAt := TThread.GetTickCount64;
  // Commit, Pull oder Wechsel des Branchs: Stand im Repository und Historie neu.
  Marker := FVcs.ChangeMarker;
  if Marker <> FMarker then
  begin
    FMarker := Marker;
    FHeadWanted := True;
    FBlameWanted := True;
  end;
  // Gespeichert: blame liest die Platte.
  if not FileAge(FFileName, Age) then
    Age := 0;
  if Age <> FDiskAge then
  begin
    FDiskAge := Age;
    FBlameWanted := True;
  end;
end;

procedure TLineChangesState.LoadHead;
var
  Vcs: IAtlasVersionControl;
  FileName: string;
  Gen: Integer;
  Outcome: TAtlasVcsOutcome;
  Lines: TArray<string>;
begin
  FHeadWanted := False;
  FHeadBusy := True;
  Vcs := FVcs;
  FileName := FFileName;
  Gen := Generation;
  Outcome := TAtlasVcsOutcome.Failed;
  Lines := nil;
  if not TAtlasIdeVcs.Run(
    procedure
    var
      Bytes: TBytes;
    begin
      Outcome := Vcs.FileAt(FileName, '', Bytes);
      if Outcome = TAtlasVcsOutcome.Ok then
        Lines := TTextLines.SplitLines(TAtlasTextFile.Decode(Bytes).Text);
    end,
    procedure
    var
      State: TLineChangesState;
    begin
      State := Current;
      if (State = nil) or (Gen <> Generation) then
        Exit;
      State.FHeadBusy := False;
      // Nicht versioniert (oder git meldet einen Fehler): keine Marken.
      State.FHeadOk := Outcome = TAtlasVcsOutcome.Ok;
      State.FHead := Lines;
      State.FDiffText := '';
      State.FChanges := nil;
      if not State.FHeadOk and State.FShown then
        Invalidate;
    end) then
    FHeadBusy := False;
end;

procedure TLineChangesState.LoadBlame;
var
  Vcs: IAtlasVersionControl;
  FileName: string;
  Gen: Integer;
  Outcome: TAtlasVcsOutcome;
  Blame: TArray<TAtlasVcsBlameLine>;
  Disk: TArray<string>;
begin
  FBlameWanted := False;
  FBlameBusy := True;
  Vcs := FVcs;
  FileName := FFileName;
  Gen := Generation;
  Outcome := TAtlasVcsOutcome.Failed;
  Blame := nil;
  Disk := nil;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Outcome := Vcs.Blame(FileName, Blame);
      if Outcome = TAtlasVcsOutcome.Ok then
        Disk := TTextLines.SplitLines(TAtlasTextFile.Load(FileName).Text);
    end,
    procedure
    var
      State: TLineChangesState;
    begin
      State := Current;
      if (State = nil) or (Gen <> Generation) then
        Exit;
      State.FBlameBusy := False;
      State.FBlameOk := Outcome = TAtlasVcsOutcome.Ok;
      State.FBlame := Blame;
      State.FDisk := Disk;
      // Zuordnung Platte → Puffer beim nächsten Vergleich neu.
      State.FDiffText := '';
      State.FDiskHunks := nil;
    end) then
    FBlameBusy := False;
end;

procedure TLineChangesState.Compare;
var
  Head, Disk, Lines: TArray<string>;
  Text, LineBreak: string;
  Gen: Integer;
  Changes: TAtlasLineChangeList;
  Hunks: TArray<TTextLineHunk>;
begin
  FDiffBusy := True;
  Head := FHead;
  Disk := FDisk;
  Text := FText;
  Gen := Generation;
  Changes := nil;
  Hunks := nil;
  Lines := nil;
  LineBreak := sLineBreak;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Lines := TTextLines.SplitLines(Text, LineBreak);
      Changes := TAtlasLineChanges.Compute(Head, Lines);
      if Disk <> nil then
        Hunks := TTextDiff.Hunks(Disk, Lines);
    end,
    procedure
    var
      State: TLineChangesState;
    begin
      State := Current;
      if (State = nil) or (Gen <> Generation) then
        Exit;
      State.FDiffBusy := False;
      State.FDiffText := Text;
      State.FLines := Lines;
      if LineBreak = '' then
        LineBreak := sLineBreak;
      State.FLineBreak := LineBreak;
      State.FChanges := Changes;
      State.FDiskHunks := Hunks;
      State.FShown := True;
      Invalidate;
    end) then
    FDiffBusy := False;
end;

function TLineChangesState.BlameCaption(ABufferLine: Integer; out AEntry: Integer; out AUnsaved: Boolean): string;
var
  DiskLine: Integer;
  Entry: TAtlasVcsBlameLine;
  Age: string;
begin
  Result := '';
  AEntry := -1;
  AUnsaved := False;
  if not FBlameOk or (FDisk = nil) then
    Exit;
  DiskLine := TAtlasLineChanges.BlameLine(FDiskHunks, ABufferLine);
  if DiskLine < 0 then
  begin
    AUnsaved := True;
    Exit(TAtlasStrings.Text(TAtlasTextId.BlameUnsaved));
  end;
  // blame liefert die Zeilen der Reihe nach; sonst suchen.
  if (DiskLine <= High(FBlame)) and (FBlame[DiskLine].Line = DiskLine + 1) then
    AEntry := DiskLine
  else
    for Entry in FBlame do
    begin
      Inc(AEntry);
      if Entry.Line = DiskLine + 1 then
        Break;
    end;
  if (AEntry < 0) or (AEntry > High(FBlame)) or (FBlame[AEntry].Line <> DiskLine + 1) then
  begin
    AEntry := -1;
    Exit;
  end;
  Entry := FBlame[AEntry];
  if Entry.Uncommitted then
    Exit(TAtlasStrings.Text(TAtlasTextId.BlameUncommitted));
  Age := AgeText(TAtlasLineChanges.Age(TTimeZone.Local.ToUniversalTime(Now), Entry.Date));
  // SVN liefert keinen Betreff.
  if Entry.Summary = '' then
    Result := Entry.Author + ', ' + Age
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.BlameLine, [Entry.Author, Age, Entry.Summary]);
end;

procedure TLineChangesState.EnsureFont(const AEditorFont: TFont);
var
  Key: string;
begin
  Key := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if Key = FFontKey then
    Exit;
  FFont.Assign(AEditorFont);
  FFont.Style := [fsItalic];
  FFontKey := Key;
end;

procedure TLineChangesState.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Line, Index, Deleted, Width, Left, Size: Integer;
  Mark: TAtlasLineMark;
  Colors: TAtlasColors;
  Row: TMarkRow;
  Bar: TRect;
  DC: HDC;
  Saved: Integer;
  Brush, Pen: HGDIOBJ;
  OldBrush, OldPen: HGDIOBJ;
  Points: array[0..2] of TPoint;
  Color: TAtlasColor;
  LineText: string;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (Context = nil) or (Context.EditView = nil) then
    Exit;
  if not FGutterOn or (FChanges = nil) or TAtlasGuard.Disabled(TAtlasFeature.LineChanges) or
    not SameText(Context.FileName, FFileName) then
    Exit;
  try
    Line := Context.LogicalLineNum - 1;
    Mark := TAtlasLineChanges.MarkAt(FChanges, Line, Index);
    Deleted := TAtlasLineChanges.DeletedAt(FChanges, Line, Length(FLines));
    if (Mark = TAtlasLineMark.None) and (Deleted < 0) then
    begin
      FRows.Remove(Context.EditorLineNum);
      Exit;
    end;
    // In .atlas für diese Datei ausgeblendet (#628).
    if TAtlasIdeElements.FileHidden(TAtlasDrawnElement.GitGutter, Context.FileName) then
      Exit;
    Colors := TAtlasColors.ForBackground(TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Left + 1, Rect.Top + 1));
    Width := Max(3, MulDiv(3, Rect.Height, 16));
    // Rechts in der Rinne, mit einem Pixel Abstand zum Code.
    Left := Rect.Right - Width - 2;
    Bar := TRect.Create(Left, Rect.Top, Left + Width, Rect.Bottom);
    DC := Context.Canvas.Handle;
    Saved := SaveDC(DC);
    try
      if Mark <> TAtlasLineMark.None then
      begin
        if Mark = TAtlasLineMark.Added then
          Color := Colors.Add
        else
          Color := Colors.Accent;
        Brush := CreateSolidBrush(ColorToRGB(TColor(Color)));
        try
          FillRect(DC, Bar, Brush);
        finally
          DeleteObject(Brush);
        end;
      end;
      if Deleted >= 0 then
      begin
        // Dreieck nach rechts: über der Zeile, am Dateiende unter der letzten Zeile.
        Size := Max(4, Rect.Height div 3);
        if FChanges[Deleted].Line >= Length(FLines) then
        begin
          Points[0] := Point(Left, Rect.Bottom - 2 * Size);
          Points[1] := Point(Left, Rect.Bottom);
          Points[2] := Point(Left + Size, Rect.Bottom - Size);
        end
        else
        begin
          Points[0] := Point(Left, Rect.Top);
          Points[1] := Point(Left, Rect.Top + 2 * Size);
          Points[2] := Point(Left + Size, Rect.Top + Size);
        end;
        Brush := CreateSolidBrush(ColorToRGB(TColor(Colors.Error)));
        Pen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(Colors.Error)));
        OldBrush := SelectObject(DC, Brush);
        OldPen := SelectObject(DC, Pen);
        try
          Polygon(DC, Points, 3);
        finally
          SelectObject(DC, OldPen);
          SelectObject(DC, OldBrush);
          DeleteObject(Pen);
          DeleteObject(Brush);
        end;
        Bar.Right := Max(Bar.Right, Left + Size);
        if Mark = TAtlasLineMark.None then
          Index := Deleted;
      end;
    finally
      RestoreDC(DC, Saved);
    end;
    Row.FileName := Context.FileName;
    Row.Line := Line;
    Row.Change := Index;
    // Etwas breiter als gezeichnet, damit der Klick leicht trifft.
    Row.Rect := TRect.Create(Bar.Left - 2, Rect.Top, Bar.Right + 2, Rect.Bottom);
    Row.TopRow := Context.EditView.TopRow;
    FRows.AddOrSetValue(Context.EditorLineNum, Row);
    LineText := '';
    if Context.LineState <> nil then
      LineText := Context.LineState.Text;
    TAtlasIdeElements.Painted(TAtlasDrawnElement.GitGutter, Context.FileName, Line, LineText, Row.Rect, Row.TopRow,
      Rect.Height);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

procedure TLineChangesState.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Caption, Key, LineText: string;
  Entry, X, Top, Saved: Integer;
  Unsaved: Boolean;
  Cell: TRect;
  DC: HDC;
  Front: TAtlasColor;
  Back: TAtlasColor;
  Size: TSize;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (Context.EditView = nil) then
    Exit;
  // Nur die Cursorzeile, nur zum aktuellen Vergleich.
  if not FBlameOn or not FBlameOk or (Context.EditView.CursorPos.Line <> Context.LogicalLineNum) or
    TAtlasGuard.Disabled(TAtlasFeature.LineChanges) or not SameText(Context.FileName, FFileName) or not Fresh then
    Exit;
  try
    LineState := Context.LineState;
    if LineState = nil then
      Exit;
    LineText := LineState.Text;
    if TAtlasIdeElements.FileHidden(TAtlasDrawnElement.GitBlame, Context.FileName) then
      Exit;
    Caption := BlameCaption(Context.LogicalLineNum - 1, Entry, Unsaved);
    if Caption = '' then
      Exit;
    Cell := Context.EditorState.GetCharacterPosPx(
      EndColumn(LineText, TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer)) + 3, Context.EditorLineNum);
    Key := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
    X := TAtlasLineTail.Start(Self, Key, Cell.Left);
    DC := Context.Canvas.Handle;
    // Hintergrund des Editor-Farbschemas am rechten Rand (dort steht nichts).
    Back := TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1);
    Front := TAtlasColorMath.Mix(TAtlasColors.ForBackground(Back).Muted, Back, BlameStrength);
    EnsureFont(Context.Canvas.Font);
    Saved := SaveDC(DC);
    try
      SelectObject(DC, FFont.Handle);
      SetTextColor(DC, COLORREF(ColorToRGB(TColor(Front))));
      SetBkMode(DC, TRANSPARENT);
      GetTextExtentPoint32W(DC, PChar(Caption), Length(Caption), Size);
      Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Size.cy) div 2);
      TextOutW(DC, X, Top, PChar(Caption), Length(Caption));
    finally
      RestoreDC(DC, Saved);
    end;
    TAtlasLineTail.Finish(Self, Key, X + Size.cx);
    FBlameRect := TRect.Create(X, Top, X + Size.cx, Top + Size.cy);
    FBlameTopRow := Context.EditView.TopRow;
    FBlameEntry := Entry;
    FBlameUnsaved := Unsaved;
    TAtlasIdeElements.Painted(TAtlasDrawnElement.GitBlame, Context.FileName, Context.LogicalLineNum - 1, LineText,
      FBlameRect, FBlameTopRow, Rect.Height);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

procedure TLineChangesState.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  View: IOTAEditView;
  Inside: Boolean;
begin
  try
    View := TopView;
    Inside := FBlameOn and (FBlameEntry >= 0) and not FBlameRect.IsEmpty and PtInRect(FBlameRect, Point(X, Y)) and
      (View <> nil) and (View.TopRow = FBlameTopRow);
    if not Inside then
    begin
      if FHovering then
      begin
        FHovering := False;
        if FTipChange < 0 then
          HideTip;
      end;
      Exit;
    end;
    if FHovering then
      Exit;
    FHovering := True;
    FHoverSince := TThread.GetTickCount64;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(FBlameRect.TopLeft),
      Editor.ClientToScreen(FBlameRect.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

procedure TLineChangesState.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Row, Found: TMarkRow;
  Hit: Boolean;
  View: IOTAEditView;
  Screen: TRect;
  Gen, Change: Integer;
begin
  try
    HideTip;
    FHovering := False;
    if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FGutterOn or not Fresh then
      Exit;
    View := TopView;
    if (View = nil) or (View.Buffer = nil) then
      Exit;
    Found := Default(TMarkRow);
    Hit := False;
    for Row in FRows.Values do
      if PtInRect(Row.Rect, Point(X, Y)) then
      begin
        Found := Row;
        Hit := True;
        Break;
      end;
    // Nur, wenn die Marke noch dort steht: gleiche Datei, nicht gescrollt.
    if not Hit or not SameText(Found.FileName, View.Buffer.FileName) or (Found.TopRow <> View.TopRow) or
      (Found.Change < 0) or (Found.Change > High(FChanges)) then
      Exit;
    Screen := TRect.Create(Editor.ClientToScreen(Found.Rect.TopLeft), Editor.ClientToScreen(Found.Rect.BottomRight));
    Gen := Generation;
    Change := Found.Change;
    // Erst nach dem Mausereignis: Der Editor setzt sonst danach den Cursor und schließt das Fenster.
    TAtlasMainThread.ForceQueue(TAtlasFeature.LineChanges,
      procedure
      var
        State: TLineChangesState;
      begin
        State := Current;
        if (State <> nil) and (Gen = Generation) and State.Fresh and (Change <= High(State.FChanges)) then
          State.ShowChange(Change, Screen);
      end);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

procedure TLineChangesState.CheckHover;
var
  Inside: Boolean;
begin
  if FTip.IsShown and (FTipChange >= 0) then
  begin
    // Fenster „alter Stand“: zu, sobald die Maus es nach dem Betreten wieder verlässt.
    Inside := PtInRect(FTip.BoundsRect, Mouse.CursorPos);
    if Inside then
      FTipEntered := True
    else if FTipEntered then
      HideTip;
    Exit;
  end;
  if not FHovering then
    Exit;
  Inside := PtInRect(FHoverScreen, Mouse.CursorPos) or (FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos));
  if not Inside then
  begin
    FHovering := False;
    HideTip;
    Exit;
  end;
  if not FTip.IsShown and (TThread.GetTickCount64 - FHoverSince >= HoverMs) then
    ShowCommit;
end;

procedure TLineChangesState.ShowChange(AChange: Integer; const AScreen: TRect);
var
  Change: TAtlasLineChange;
  Text: string;
  Index, Shown: Integer;
  Gen: Integer;
begin
  Change := FChanges[AChange];
  if Change.Kind = TAtlasLineChangeKind.Added then
    Text := TAtlasStrings.Text(TAtlasTextId.ChangeAddedTitle)
  else
  begin
    Shown := Min(Length(Change.OldLines), MaxOldLines);
    Text := '';
    for Index := 0 to Shown - 1 do
    begin
      if Index > 0 then
        Text := Text + sLineBreak;
      // Leere Zeilen sichtbar halten.
      if Change.OldLines[Index] = '' then
        Text := Text + ' '
      else
        Text := Text + Change.OldLines[Index];
    end;
    if Length(Change.OldLines) > Shown then
      Text := Text + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.ChangeMoreLines, [Length(Change.OldLines) - Shown]);
  end;
  Gen := Generation;
  FTip.OnLink :=
    procedure(AIndex: Integer)
    var
      State: TLineChangesState;
    begin
      State := Current;
      if (State = nil) or (Gen <> Generation) then
        Exit;
      State.HideTip;
      State.RevertChange(AChange);
    end;
  FTipChange := AChange;
  FTipEntered := False;
  TAtlasIdeStyle.Apply(FTip, AScreen);
  FTip.ShowNote(TAtlasStrings.Text(TAtlasTextId.ChangeOldTitle), Text,
    [TAtlasStrings.Text(TAtlasTextId.ChangeRevert)], Point(AScreen.Right + 4, AScreen.Top));
end;

procedure TLineChangesState.ShowCommit;
var
  Entry: TAtlasVcsBlameLine;
  Title, Text: string;
begin
  if FBlameUnsaved or (FBlameEntry < 0) or (FBlameEntry > High(FBlame)) then
  begin
    FHovering := False;
    Exit;
  end;
  Entry := FBlame[FBlameEntry];
  if Entry.Uncommitted then
  begin
    FHovering := False;
    Exit;
  end;
  Title := TAtlasStrings.Fmt(TAtlasTextId.BlameCommitTitle, [Entry.Revision]);
  Text := TAtlasStrings.Fmt(TAtlasTextId.BlameCommitText,
    [Entry.Author, FormatDateTime('dd.mm.yyyy hh":"nn', TTimeZone.Local.ToLocalTime(Entry.Date)), Entry.Summary]);
  FTipChange := -1;
  FTip.OnLink := nil;
  TAtlasIdeStyle.Apply(FTip, FHoverScreen);
  FTip.ShowNote(Title, TrimRight(Text), Point(FHoverScreen.Left, FHoverScreen.Bottom + 2));
end;

procedure TLineChangesState.HideTip;
begin
  FTipChange := -1;
  FTipEntered := False;
  if (FTip <> nil) and FTip.IsShown then
    FTip.HidePopup;
end;

procedure TLineChangesState.RevertChange(AChange: Integer);
var
  Edit: TLspWorkspaceEdit;
  FileEdits: TLspFileEdits;
  LineEdit: TAtlasLineEdit;
  TextEdit: TLspTextEdit;
  Outcome: TAtlasWorkspaceEditResult;
begin
  // Nur zum Stand, den das Fenster gezeigt hat.
  if not Fresh or (AChange < 0) or (AChange > High(FChanges)) then
    Exit;
  LineEdit := TAtlasLineChanges.Revert(FChanges[AChange], FLines, FLineBreak);
  TextEdit := Default(TLspTextEdit);
  TextEdit.StartPos := TLspTextPosition.Create(LineEdit.StartLine, LineEdit.StartCharacter);
  TextEdit.EndPos := TLspTextPosition.Create(LineEdit.EndLine, LineEdit.EndCharacter);
  TextEdit.NewText := LineEdit.NewText;
  FileEdits := Default(TLspFileEdits);
  FileEdits.FileName := FFileName;
  FileEdits.Edits := [TextEdit];
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [FileEdits];
  // Ein Rückgängig-Schritt im Puffer (#397); Strg+Z stellt die Änderung wieder her.
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, TAtlasUnopenedPolicy.OpenInEditor,
    TAtlasStrings.Text(TAtlasTextId.ChangeRevertAction));
  if (Outcome.Error <> '') and Assigned(TAtlasIdeLineChanges.FMessage) then
    TAtlasIdeLineChanges.FMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
end;

procedure TLineChangesState.GoToChange(AForward: Boolean);
var
  View: IOTAEditView;
  Target: Integer;
begin
  View := TopView;
  if not FGutterOn or (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FFileName) or
    not Fresh then
    Exit;
  if TAtlasLineChanges.Next(FChanges, View.CursorPos.Line - 1, Length(FLines), AForward, Target) then
    TAtlasIdeNavigation.GoToLocation(FFileName, Min(Target, Max(0, High(FLines))), 0);
end;

{ TAtlasIdeLineChanges }

class function TAtlasIdeLineChanges.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.GitGutter;
end;

class procedure TAtlasIdeLineChanges.Install(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  FreeAndNil(FState);
  if Active then
    FState := TLineChangesState.Create;
end;

class procedure TAtlasIdeLineChanges.Uninstall;
begin
  FreeAndNil(FState);
  FMessage := nil;
end;

class procedure TAtlasIdeLineChanges.ApplySettings;
begin
  // Beide aus: kein Zeitgeber, kein Prozess, nichts gezeichnet.
  if not Active then
  begin
    FreeAndNil(FState);
    Exit;
  end;
  if FState = nil then
    FState := TLineChangesState.Create
  else
  begin
    TLineChangesState(FState).Reset;
    Invalidate;
  end;
end;

class procedure TAtlasIdeLineChanges.ThemeChanged;
begin
  // Die Farben kommen beim Zeichnen aus dem Grund der Rinne.
  if FState <> nil then
    Invalidate;
end;

class function TAtlasIdeLineChanges.Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList;
  out ALineCount: Integer): Boolean;
var
  State: TLineChangesState;
begin
  AChanges := nil;
  ALineCount := 0;
  State := Current;
  Result := (State <> nil) and State.FGutterOn and State.FHeadOk and (State.FLines <> nil) and
    SameText(State.FFileName, AFileName);
  if not Result then
    Exit;
  AChanges := State.FChanges;
  ALineCount := Length(State.FLines);
end;

class procedure TAtlasIdeLineChanges.GoToChange(AForward: Boolean);
begin
  if FState <> nil then
    TLineChangesState(FState).GoToChange(AForward);
end;

end.
