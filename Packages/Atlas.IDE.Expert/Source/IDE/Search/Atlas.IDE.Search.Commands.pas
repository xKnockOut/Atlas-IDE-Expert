unit Atlas.IDE.Search.Commands;

// Atlas-Suche im Editor (#877, #878):
// - Show: Suchleiste (Atlas.UI.Search.Bar) am unteren Rand des obersten
//   Editorfensters (alBottom im Eltern-Steuerelement des Editors „Editor“, wie
//   die Brotkrumenleiste oben). Jedes Editorfenster bekommt beim ersten Öffnen
//   seine eigene Leiste. Vorschlag ist die einzeilige Markierung, sonst der
//   Bezeichner am Cursor, sonst die letzte Suche. Bereich ist immer die Unit
//   (mehrzeilige Markierung: Auswahl); ShowInMethod („In Methode suchen“,
//   #877) stellt ihn auf Methode und die Stufe auf die innerste Routine.
//   Sonst gilt Methode nur, wenn der Anwender sie in der Leiste wählt.
// - Jede Änderung in der Leiste sucht neu: Treffer im Editor gerahmt, Sprung
//   zum nächsten Treffer ab der Stelle, an der die Leiste geöffnet wurde,
//   Zähler „n von m“. Bei Bereich Auswahl und Methode gelten Auswahl und
//   Cursor beim Öffnen; die Auswahl wandert nicht mit den Treffern.
// - Enter bzw. „In Meldungen“ listet alle Treffer im Reiter „Atlas-Suche“ des
//   Fensters Meldungen (Atlas.IDE.Search.MessageList, search.resultsInMessages);
//   dieselbe Suche wird nicht erneut aufgebaut. Der Fokus bleibt in der Leiste.
// - TryNext (F3/Umschalt+F3, in der Leiste auch Enter/Umschalt+Enter):
//   nächster bzw. voriger Treffer der letzten Suche mit Umlauf (Meldung in
//   der Meldungsansicht), auch bei geschlossener Leiste. Ohne letzte Suche
//   False: die Taste geht weiter (Markierung suchen bzw. „Erneut suchen“ der
//   IDE). Ist ein anderer Text einzeilig markiert als zuletzt gesucht, sucht
//   F3 nach der Markierung. Bei Bereich Methode und Cursor außerhalb jeder
//   Routine sucht F3 in der ganzen Unit (Meldung).
// - Esc bzw. × schließt die Leiste, gibt den Fokus an den Editor zurück und
//   beendet die Hervorhebung; F3 sucht weiter mit der letzten Suche.
// - Solange die Leiste offen ist, prüft ein Takt (Probe): Holt die IDE den
//   Fokus kurz nach dem Klick in die Leiste wieder in den Editor, kommt er
//   einmal zurück; liegt über der Leiste ein anderes Fenster, wird sie nach
//   vorn geholt. Beides steht mit Fensterklasse im Diagnoseprotokoll, ebenso
//   beim ersten Öffnen je Fenster die Lage von Editor und Leiste.
// Tasten: Strg+F/F3/Umschalt+F3 nur mit search.replaceIdeSearch
// (Atlas.IDE.Commands.Bindings), „In Methode suchen“ immer. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Search.Matching,
  Atlas.UI.Search.Bar;

type
  TAtlasIdeSearch = class
  private type
    TPainter = class
    private type
      TEvents = class(TNTACodeEditorNotifier)
      protected
        function AllowedEvents: TCodeEditorEvents; override;
        function AllowedLineStages: TPaintLineStages; override;
      end;
    private
      FEvents: TEvents;
      FEventsRef: INTACodeEditorEvents;
      FIndex: Integer;
      FCheck: Boolean;
      FKey: string;
      FLines: TArray<string>;
      FTabWidth: Integer;
      // Je 0-basierter Zeile die Treffer.
      FHits: TArray<TArray<TAtlasSearchHit>>;
      procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
      procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
        var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
      procedure Refresh(const Context: INTACodeEditorPaintContext);
    public
      constructor Create;
      destructor Destroy; override;
    end;

    /// <summary>Erfährt, wenn die IDE eine Leiste mit ihrem Editorfenster freigibt.</summary>
    TBarWatcher = class(TComponent)
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    public
      procedure Tick(Sender: TObject);
    end;
  private class var
    FLast: TAtlasSearchQuery;
    FVersion: Integer;
    FPainter: TPainter;
    FMessage: TProc<string>;
    FBars: TList<TAtlasSearchBar>;
    FWatcher: TBarWatcher;
    // Leiste der laufenden Suche und Stand beim Öffnen.
    FBar: TAtlasSearchBar;
    FOrigin: TAtlasSearchPos;
    FSelection: TAtlasSearchArea;
    FFileName: string;
    FHighlight: Boolean;
    FListedKey: string;
    // Takt bei offener Leiste: Fokus und Fenster unter der Maus (Probe).
    FProbe: TTimer;
    FProbed: HWND;
    FEntered: TWinControl;
    FEnteredAt: UInt64;
  private
    class procedure Say(const AText: string); static;
    class function TopView(out AView: IOTAEditView): Boolean; static;
    class function CursorOf(const AView: IOTAEditView; const ALines: TArray<string>): TAtlasSearchPos; static;
    class function SelectionOf(const AView: IOTAEditView; const ALines: TArray<string>;
      out AArea: TAtlasSearchArea): Boolean; static;
    /// <summary>Bereich der Suche im Text: Auswahl wie gemerkt, Methode an ACursor, sonst ganzer Text.</summary>
    class function AreaOf(const AText: string; const AQuery: TAtlasSearchQuery; const ACursor: TAtlasSearchPos;
      out AArea: TAtlasSearchArea): Boolean; static;
    class procedure SelectHit(const AView: IOTAEditView; const ALines: TArray<string>;
      const AHit: TAtlasSearchHit); static;
    class procedure Repaint; static;
    class procedure Open(AInMethod: Boolean); static;
    // Leisten.
    class function EditorOf(const AWindow: INTAEditWindow): TWinControl; static;
    class function BarFor(const AWindow: INTAEditWindow): TAtlasSearchBar; static;
    class procedure CreateBar(AParent: TWinControl; out ABar: TAtlasSearchBar); static;
    class procedure Removed(ABar: TAtlasSearchBar); static;
    class procedure ThemeBar(ABar: TAtlasSearchBar); static;
    /// <summary>Suche der Leiste übernehmen; AJump: zum nächsten Treffer ab dem Ursprung springen.</summary>
    class procedure Sync(AJump: Boolean); static;
    class procedure UpdateCounter; static;
    class procedure BarStep(ABackward: Boolean); static;
    class procedure BarList; static;
    class procedure CloseBar; static;
    class procedure Probe; static;
    class procedure LogLayout(ABar: TAtlasSearchBar); static;
    class procedure StopProbe; static;
  public
    /// <summary>Zeichner anmelden; AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>search.resultsInMessages aus: Reiter entfernen und Schaltfläche ausblenden.</summary>
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Suchleiste (Strg+F, Befehl Atlas.Search).</summary>
    class procedure Show; static;
    /// <summary>Suchleiste mit Bereich Methode (#877, Befehl Atlas.SearchInMethod).</summary>
    class procedure ShowInMethod; static;
    /// <summary>F3/Umschalt+F3: False ohne letzte Atlas-Suche oder ohne Editor.</summary>
    class function TryNext(ABackward: Boolean): Boolean; static;
    /// <summary>Für Palette und Menü: wie TryNext, ohne letzte Suche öffnet sich die Leiste.</summary>
    class procedure FindNext; static;
    class procedure FindPrevious; static;
    class procedure ClearHighlights; static;
  end;

implementation

uses
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Search.Scopes,
  Atlas.Core.Search.Results,
  Atlas.Text.Lines,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Search.MessageList;

const
  // Takt bei offener Leiste und Frist, in der ein Fokusverlust nach dem Klick als zurückgeholt gilt.
  ProbeMs = 100;
  FocusGraceMs = 400;

{ TAtlasIdeSearch.TPainter.TEvents }

function TAtlasIdeSearch.TPainter.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevBeginEndPaintEvents, cevPaintLineEvents];
end;

function TAtlasIdeSearch.TPainter.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeSearch.TPainter }

constructor TAtlasIdeSearch.TPainter.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorBeginPaint := BeginPaint;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasIdeSearch.TPainter.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorBeginPaint := nil;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TAtlasIdeSearch.TPainter.BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
begin
  FCheck := True;
end;

procedure TAtlasIdeSearch.TPainter.Refresh(const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Text, Key: string;
  Area: TAtlasSearchArea;
  Hit: TAtlasSearchHit;
begin
  FCheck := False;
  View := Context.EditView;
  if (View = nil) or (View.Buffer = nil) or TAtlasIdeSearch.FLast.IsEmpty then
  begin
    FHits := nil;
    FKey := '';
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  FLines := TTextLines.SplitLines(Text);
  // Bei Bereich Methode hängt die Hervorhebung am Cursor; der wandert, also gehört er zum Schlüssel.
  Key := Context.FileName + #0 + IntToStr(TAtlasIdeSearch.FVersion) + #0 + IntToStr(View.CursorPos.Line) + #0 + Text;
  if Key = FKey then
    Exit;
  FKey := Key;
  FHits := nil;
  SetLength(FHits, Length(FLines));
  FTabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  if not TAtlasIdeSearch.AreaOf(Text, TAtlasIdeSearch.FLast, TAtlasIdeSearch.CursorOf(View, FLines), Area) then
    Exit;
  for Hit in TAtlasTextSearch.FindAll(FLines, TAtlasIdeSearch.FLast.Text, TAtlasIdeSearch.FLast.Options, Area) do
    if Hit.Line <= High(FHits) then
      FHits[Hit.Line] := FHits[Hit.Line] + [Hit];
end;

procedure TAtlasIdeSearch.TPainter.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Line, First, Last: Integer;
  Hit: TAtlasSearchHit;
  LineState: INTACodeEditorLineState;
  Cell, LastCell, Frame: TRect;
  DC: HDC;
  Saved: Integer;
  Pen, Old: HGDIOBJ;
  Brush: HGDIOBJ;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.EditorCommands) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not TAtlasIdeSearch.FHighlight or
    TAtlasIdeSearch.FLast.IsEmpty then
    Exit;
  try
    if FCheck then
      Refresh(Context);
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line > High(FHits)) or (Length(FHits[Line]) = 0) then
      Exit;
    // Nur, wenn die gezeichnete Zeile zum berechneten Text passt.
    LineState := Context.LineState;
    if (LineState = nil) or (TrimRight(LineState.Text) <> TrimRight(FLines[Line])) then
      Exit;
    DC := Context.Canvas.Handle;
    Saved := SaveDC(DC);
    try
      Pen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(TAtlasIdeStyle.Colors.Warn)));
      Old := SelectObject(DC, Pen);
      Brush := SelectObject(DC, GetStockObject(NULL_BRUSH));
      try
        for Hit in FHits[Line] do
        begin
          First := TAtlasPairs.ColumnOf(FLines[Line], Hit.Character, FTabWidth);
          Last := TAtlasPairs.ColumnOf(FLines[Line], Hit.Character + Hit.Length - 1, FTabWidth);
          Cell := Context.EditorState.GetCharacterPosPx(First, Context.EditorLineNum);
          LastCell := Context.EditorState.GetCharacterPosPx(Last, Context.EditorLineNum);
          Frame := TRect.Create(Cell.Left, Rect.Top, LastCell.Right, Rect.Bottom);
          Winapi.Windows.Rectangle(DC, Frame.Left, Frame.Top, Frame.Right, Frame.Bottom);
        end;
      finally
        SelectObject(DC, Brush);
        SelectObject(DC, Old);
        DeleteObject(Pen);
      end;
    finally
      RestoreDC(DC, Saved);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
    begin
      FHits := nil;
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
    end;
  end;
end;

{ TAtlasIdeSearch.TBarWatcher }

procedure TAtlasIdeSearch.TBarWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TAtlasSearchBar) then
    TAtlasIdeSearch.Removed(TAtlasSearchBar(AComponent));
end;

procedure TAtlasIdeSearch.TBarWatcher.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.EditorCommands, TAtlasIdeSearch.Probe);
end;

{ TAtlasIdeSearch }

class procedure TAtlasIdeSearch.Install(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FPainter = nil then
    FPainter := TPainter.Create;
  if FBars = nil then
    FBars := TList<TAtlasSearchBar>.Create;
  if FWatcher = nil then
    FWatcher := TBarWatcher.Create(nil);
  if FProbe = nil then
  begin
    FProbe := TTimer.Create(FWatcher);
    FProbe.Enabled := False;
    FProbe.Interval := ProbeMs;
    FProbe.OnTimer := FWatcher.Tick;
  end;
end;

class procedure TAtlasIdeSearch.Uninstall;
var
  Bar: TAtlasSearchBar;
begin
  FreeAndNil(FPainter);
  // Leisten selbst freigeben; der Wächter darf dabei nicht mehr zurückschreiben.
  if FBars <> nil then
  begin
    for Bar in FBars.ToArray do
    begin
      Bar.RemoveFreeNotification(FWatcher);
      Bar.Free;
    end;
    FreeAndNil(FBars);
  end;
  // Der Takt gehört dem Wächter.
  FProbe := nil;
  FEntered := nil;
  FreeAndNil(FWatcher);
  FBar := nil;
  FMessage := nil;
  FHighlight := False;
  FListedKey := '';
  FLast := Default(TAtlasSearchQuery);
end;

class procedure TAtlasIdeSearch.ApplySettings;
var
  Bar: TAtlasSearchBar;
  Listed: Boolean;
begin
  Listed := TAtlasIdeSettings.Current.SearchResultsInMessages;
  if not Listed then
  begin
    TAtlasIdeSearchMessages.Clear;
    FListedKey := '';
  end;
  if FBars <> nil then
    for Bar in FBars do
      Bar.ListVisible := Listed;
end;

class procedure TAtlasIdeSearch.ThemeChanged;
var
  Bar: TAtlasSearchBar;
begin
  if FBars <> nil then
    for Bar in FBars do
      ThemeBar(Bar);
end;

class procedure TAtlasIdeSearch.ThemeBar(ABar: TAtlasSearchBar);
var
  Theming: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and Theming.IDEThemingEnabled then
    Theming.ApplyTheme(ABar);
end;

class procedure TAtlasIdeSearch.Say(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class function TAtlasIdeSearch.TopView(out AView: IOTAEditView): Boolean;
var
  Editors: IOTAEditorServices;
begin
  AView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    AView := Editors.TopView;
  Result := (AView <> nil) and (AView.Buffer <> nil);
end;

class function TAtlasIdeSearch.CursorOf(const AView: IOTAEditView; const ALines: TArray<string>): TAtlasSearchPos;
var
  Cursor: TOTAEditPos;
  Row: Integer;
  LineText: string;
begin
  Cursor := AView.CursorPos;
  Row := Cursor.Line - 1;
  LineText := '';
  if (Row >= 0) and (Row <= High(ALines)) then
    LineText := ALines[Row];
  Result := TAtlasSearchPos.Create(Row, TLspSession.ColumnToIndex(LineText, Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer)));
end;

class function TAtlasIdeSearch.SelectionOf(const AView: IOTAEditView; const ALines: TArray<string>;
  out AArea: TAtlasSearchArea): Boolean;
var
  Block: IOTAEditBlock;
  TabWidth: Integer;

  function Index(ARow, AColumn: Integer): Integer;
  var
    LineText: string;
  begin
    LineText := '';
    if (ARow >= 1) and (ARow <= Length(ALines)) then
      LineText := ALines[ARow - 1];
    Result := TLspSession.ColumnToIndex(LineText, AColumn, TabWidth);
  end;

begin
  AArea := TAtlasSearchArea.Create(0, 0, 0, 0);
  Block := AView.Block;
  Result := (Block <> nil) and Block.IsValid and (Block.Size > 0);
  if not Result then
    Exit;
  TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  AArea := TAtlasSearchArea.Create(Block.StartingRow - 1, Index(Block.StartingRow, Block.StartingColumn),
    Block.EndingRow - 1, Index(Block.EndingRow, Block.EndingColumn));
end;

class function TAtlasIdeSearch.AreaOf(const AText: string; const AQuery: TAtlasSearchQuery;
  const ACursor: TAtlasSearchPos; out AArea: TAtlasSearchArea): Boolean;
begin
  Result := TAtlasSearchScopes.AreaFor(AText, AQuery.Scope, ACursor, AQuery.Area, AQuery.Level, AArea);
  // Methode: Steht der Cursor (etwa nach einem Sprung) außerhalb jeder Routine, gilt die Routine beim Suchen.
  if not Result and (AQuery.Scope = TAtlasSearchScope.Method) and not AQuery.Area.IsEmpty then
  begin
    AArea := AQuery.Area;
    Result := True;
  end;
end;

class procedure TAtlasIdeSearch.SelectHit(const AView: IOTAEditView; const ALines: TArray<string>;
  const AHit: TAtlasSearchHit);
var
  TabWidth: Integer;
  LineText: string;
  Target: TOTAEditPos;
begin
  TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  LineText := '';
  if (AHit.Line >= 0) and (AHit.Line <= High(ALines)) then
    LineText := ALines[AHit.Line];
  AView.Block.Style := btNonInclusive;
  Target.Line := AHit.Line + 1;
  Target.Col := TLspSession.IndexToColumn(LineText, AHit.Character, TabWidth);
  AView.CursorPos := Target;
  // Anfang markieren, Cursor ans Ende, Ende markieren: Der Cursor steht danach hinter dem Treffer.
  AView.Block.BeginBlock;
  Target.Col := TLspSession.IndexToColumn(LineText, AHit.Character + AHit.Length, TabWidth);
  AView.CursorPos := Target;
  AView.Block.EndBlock;
  AView.MoveViewToCursor;
  AView.Paint;
end;

class procedure TAtlasIdeSearch.Repaint;
var
  View: IOTAEditView;
begin
  Inc(FVersion);
  if TopView(View) then
    View.Paint;
end;

class function TAtlasIdeSearch.EditorOf(const AWindow: INTAEditWindow): TWinControl;
var
  Editor: TComponent;
begin
  Result := nil;
  if (AWindow = nil) or (AWindow.Form = nil) then
    Exit;
  Editor := AWindow.Form.FindComponent('Editor');
  if (Editor is TWinControl) and (TWinControl(Editor).Parent <> nil) then
    Result := TWinControl(Editor);
end;

class function TAtlasIdeSearch.BarFor(const AWindow: INTAEditWindow): TAtlasSearchBar;
var
  Editor: TWinControl;
  Bar: TAtlasSearchBar;
begin
  Result := nil;
  Editor := EditorOf(AWindow);
  if (Editor = nil) or (FBars = nil) then
    Exit;
  for Bar in FBars do
    if Bar.Parent = Editor.Parent then
      Exit(Bar);
  CreateBar(Editor.Parent, Result);
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable.</summary>
class procedure TAtlasIdeSearch.CreateBar(AParent: TWinControl; out ABar: TAtlasSearchBar);
var
  Bar: TAtlasSearchBar;
begin
  Bar := TAtlasSearchBar.Create(nil);
  Bar.FreeNotification(FWatcher);
  FBars.Add(Bar);
  Bar.Visible := False;
  Bar.OnQueryChanged :=
    procedure
    begin
      if Bar = FBar then
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            Sync(True);
          end);
    end;
  Bar.OnStep :=
    procedure(ABackward: Boolean)
    begin
      if Bar = FBar then
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            BarStep(ABackward);
          end);
    end;
  Bar.OnList :=
    procedure
    begin
      if Bar = FBar then
        TAtlasGuard.Run(TAtlasFeature.EditorCommands, BarList);
    end;
  Bar.OnClose :=
    procedure
    begin
      if Bar = FBar then
        TAtlasGuard.Run(TAtlasFeature.EditorCommands, CloseBar);
    end;
  Bar.OnControlEnter :=
    procedure(AControl: TWinControl)
    begin
      if Bar = FBar then
      begin
        FEntered := AControl;
        FEnteredAt := TThread.GetTickCount64;
      end;
    end;
  // Unter dem Editor: zuerst ganz unten einhängen, dann unten ausrichten.
  Bar.Top := AParent.ClientHeight;
  Bar.Align := alBottom;
  Bar.Parent := AParent;
  ThemeBar(Bar);
  ABar := Bar;
end;

class procedure TAtlasIdeSearch.Removed(ABar: TAtlasSearchBar);
begin
  if FBars <> nil then
    FBars.Remove(ABar);
  if FBar = ABar then
  begin
    FBar := nil;
    StopProbe;
  end;
end;

class procedure TAtlasIdeSearch.Open(AInMethod: Boolean);
var
  View: IOTAEditView;
  Editors: INTAEditorServices;
  Bar: TAtlasSearchBar;
  Text, Proposal: string;
  Lines, Levels: TArray<string>;
  Cursor: TAtlasSearchPos;
  Selection: TAtlasSearchArea;
  HasSelection: Boolean;
  Query: TAtlasSearchQuery;
  Routine: TAtlasSearchRoutine;
begin
  if not TopView(View) or not Supports(BorlandIDEServices, INTAEditorServices, Editors) then
    Exit;
  Bar := BarFor(Editors.TopEditWindow);
  if Bar = nil then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  Cursor := CursorOf(View, Lines);
  HasSelection := SelectionOf(View, Lines, Selection);
  // Vorschlag: einzeilige Markierung, sonst Bezeichner am Cursor, sonst die letzte Suche.
  Proposal := '';
  if HasSelection and (Selection.Start.Line = Selection.Stop.Line) and (Selection.Start.Line <= High(Lines)) then
    Proposal := Copy(Lines[Selection.Start.Line], Selection.Start.Character + 1,
      Selection.Stop.Character - Selection.Start.Character);
  if (Proposal = '') and (Cursor.Line >= 0) and (Cursor.Line <= High(Lines)) then
    Proposal := TAtlasTextSearch.WordAt(Lines[Cursor.Line], Cursor.Character);
  if Proposal = '' then
    Proposal := FLast.Text;
  // Bereich Unit; Methode nur mit „In Methode suchen“, mehrzeilige Markierung als Auswahl.
  Query := TAtlasSearchResults.StartQuery(FLast, Proposal,
    HasSelection and (Selection.Start.Line <> Selection.Stop.Line), AInMethod);
  Levels := nil;
  for Routine in TAtlasSearchScopes.RoutinesAt(Text, Cursor) do
    Levels := Levels + [Routine.Caption];
  // Ursprung der Suche: Anfang einer Markierung, sonst der Cursor.
  FOrigin := Cursor;
  if HasSelection then
    FOrigin := Selection.Start;
  FSelection := Selection;
  FFileName := View.Buffer.FileName;
  // Eine andere Leiste (anderes Editorfenster) beenden.
  if (FBar <> nil) and (FBar <> Bar) then
    FBar.Visible := False;
  FBar := Bar;
  Bar.ListVisible := TAtlasIdeSettings.Current.SearchResultsInMessages;
  Bar.Prepare(Query, Levels, HasSelection);
  Bar.Visible := True;
  // Vor alle Geschwister: Kein Fenster der IDE soll über der Leiste liegen.
  Bar.BringToFront;
  LogLayout(Bar);
  Bar.FocusText;
  FProbed := 0;
  FEntered := nil;
  if FProbe <> nil then
    FProbe.Enabled := True;
  // Hervorheben und zählen, ohne zu springen: Der Vorschlag steht meist schon am Cursor.
  Sync(False);
end;

class procedure TAtlasIdeSearch.Sync(AJump: Boolean);
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Query: TAtlasSearchQuery;
  Area: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  Index: Integer;
  Wrapped: Boolean;
begin
  if (FBar = nil) or not TopView(View) then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  // Anderes Dokument im selben Fenster: neuer Ursprung am Cursor, Auswahl gilt nicht mehr.
  if not SameText(FFileName, View.Buffer.FileName) then
  begin
    FFileName := View.Buffer.FileName;
    FOrigin := CursorOf(View, Lines);
    FSelection := TAtlasSearchArea.Create(0, 0, 0, 0);
  end;
  Query := FBar.Query;
  Query.FileName := FFileName;
  if not TAtlasSearchScopes.AreaFor(Text, Query.Scope, FOrigin, FSelection, Query.Level, Area) then
  begin
    Query.Area := TAtlasSearchArea.Create(0, 0, 0, 0);
    FLast := Query;
    FHighlight := False;
    Repaint;
    if Query.Scope = TAtlasSearchScope.Method then
      FBar.SetCounter(TAtlasStrings.Text(TAtlasTextId.SearchNoMethod))
    else
      FBar.SetCounter(TAtlasStrings.Text(TAtlasTextId.SearchNoSelection));
    Exit;
  end;
  // Gemerkt wird der Bereich beim Suchen (Auswahl; Methode als Rückfall außerhalb jeder Routine).
  Query.Area := Area;
  FLast := Query;
  FHighlight := True;
  Repaint;
  Hits := TAtlasTextSearch.FindAll(Lines, Query.Text, Query.Options, Area);
  if AJump and (Length(Hits) > 0) then
  begin
    Index := TAtlasTextSearch.Next(Hits, FOrigin, False, Wrapped);
    SelectHit(View, Lines, Hits[Index]);
  end;
  UpdateCounter;
end;

class procedure TAtlasIdeSearch.UpdateCounter;
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Area, Selection: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  Index: Integer;
  At: TAtlasSearchPos;
begin
  if (FBar = nil) or not FBar.Visible or not TopView(View) then
    Exit;
  if FLast.Text = '' then
  begin
    FBar.SetCounter('');
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  At := CursorOf(View, Lines);
  if SelectionOf(View, Lines, Selection) then
    At := Selection.Start;
  Hits := nil;
  if AreaOf(Text, FLast, At, Area) then
    Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  if Length(Hits) = 0 then
  begin
    FBar.SetCounter(TAtlasStrings.Text(TAtlasTextId.SearchNoHits));
    Exit;
  end;
  Index := TAtlasSearchResults.IndexAt(Hits, At);
  if Index >= 0 then
    FBar.SetCounter(TAtlasStrings.Fmt(TAtlasTextId.SearchHitPosition, [Index + 1, Length(Hits)]))
  else
    FBar.SetCounter(TAtlasStrings.Fmt(TAtlasTextId.SearchHitCount, [Length(Hits)]));
end;

class procedure TAtlasIdeSearch.BarStep(ABackward: Boolean);
begin
  Sync(False);
  TryNext(ABackward);
end;

class procedure TAtlasIdeSearch.BarList;
var
  View: IOTAEditView;
  Text, Key, Mode, Place: string;
  Lines: TArray<string>;
  Area: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  Routines: TArray<TAtlasSearchRoutine>;
begin
  if (FBar = nil) or not TAtlasIdeSettings.Current.SearchResultsInMessages or not TopView(View) then
    Exit;
  Sync(False);
  if FLast.IsEmpty or FLast.Area.IsEmpty then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  // Dieselbe Suche im selben Text nicht erneut aufbauen (Enter springt auch nur weiter).
  Key := FFileName + #0 + FLast.Text + #0 + BoolToStr(FLast.Options.CaseSensitive) +
    BoolToStr(FLast.Options.WholeWord) + BoolToStr(FLast.Options.Identifier) + #0 + IntToStr(Ord(FLast.Scope)) + #0 +
    IntToStr(FLast.Area.Start.Line) + ':' + IntToStr(FLast.Area.Start.Character) + '-' +
    IntToStr(FLast.Area.Stop.Line) + ':' + IntToStr(FLast.Area.Stop.Character) + #0 + Text;
  if Key = FListedKey then
    Exit;
  FListedKey := Key;
  Lines := TTextLines.SplitLines(Text);
  Area := FLast.Area;
  Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  Mode := '';
  if FLast.Options.Identifier then
    Mode := TAtlasStrings.Text(TAtlasTextId.SearchListIdentifier);
  Place := '';
  case FLast.Scope of
    TAtlasSearchScope.Method:
      begin
        Routines := TAtlasSearchScopes.RoutinesAt(Text, Area.Start);
        if Length(Routines) > 0 then
          Place := TAtlasStrings.Fmt(TAtlasTextId.SearchListScopeMethod,
            [TAtlasSearchResults.RoutineName(Routines[0].Caption)]);
      end;
    TAtlasSearchScope.Selection:
      Place := ', ' + TAtlasStrings.Text(TAtlasTextId.SearchScopeSelection);
  end;
  TAtlasIdeSearchMessages.Show(FFileName, TAtlasStrings.Fmt(TAtlasTextId.SearchListTitle,
    [FLast.Text, Mode, ExtractFileName(FFileName), Place, Length(Hits)]),
    TAtlasSearchResults.Entries(Lines, Hits, TAtlasEditorBuffer.TabWidth(View.Buffer)), Length(Hits));
  // Das Meldungsfenster nimmt beim Zeigen den Fokus; zurück in die Leiste.
  if FBar <> nil then
    FBar.FocusText;
end;

class procedure TAtlasIdeSearch.CloseBar;
var
  Form: TCustomForm;
  Editor: TComponent;
begin
  if FBar = nil then
    Exit;
  Form := GetParentForm(FBar);
  StopProbe;
  FBar.Visible := False;
  FHighlight := False;
  Repaint;
  if Form = nil then
    Exit;
  Editor := Form.FindComponent('Editor');
  if (Editor is TWinControl) and TWinControl(Editor).CanFocus then
    TWinControl(Editor).SetFocus;
end;

class procedure TAtlasIdeSearch.StopProbe;
begin
  if FProbe <> nil then
    FProbe.Enabled := False;
  FEntered := nil;
  FProbed := 0;
end;

function WindowName(AWindow: HWND): string;
var
  WindowClass: array[0..255] of Char;
  Control: TWinControl;
begin
  if AWindow = 0 then
    Exit('kein Fenster');
  WindowClass[0] := #0;
  GetClassName(AWindow, WindowClass, Length(WindowClass));
  Result := string(WindowClass);
  Control := FindControl(AWindow);
  if Control <> nil then
    Result := Result + ', ' + Control.ClassName + ' ' + Control.Name;
end;

/// <summary>Einmal je Leiste: Lage von Editor und Leiste im gemeinsamen Eltern-Steuerelement (Diagnose).</summary>
class procedure TAtlasIdeSearch.LogLayout(ABar: TAtlasSearchBar);
var
  Parent: TWinControl;
  Index: Integer;
  Child: TControl;
  Parts: string;
begin
  if ABar.Tag <> 0 then
    Exit;
  ABar.Tag := 1;
  Parent := ABar.Parent;
  if Parent = nil then
    Exit;
  Parts := '';
  for Index := 0 to Parent.ControlCount - 1 do
  begin
    Child := Parent.Controls[Index];
    Parts := Parts + Format(' [%s %s Align %d, %d,%d %dx%d, sichtbar %s]', [Child.ClassName, Child.Name,
      Ord(Child.Align), Child.Left, Child.Top, Child.Width, Child.Height, BoolToStr(Child.Visible, True)]);
  end;
  TAtlasGuard.Log(Format('Suchleiste: in %s %s (%dx%d):%s', [Parent.ClassName, Parent.Name, Parent.ClientWidth,
    Parent.ClientHeight, Parts]));
end;

class procedure TAtlasIdeSearch.Probe;
var
  Bar: TAtlasSearchBar;
  Cursor: TPoint;
  Window: HWND;
begin
  Bar := FBar;
  if (Bar = nil) or not Bar.HandleAllocated or not Bar.Showing then
    Exit;
  // Kurz nach dem Klick in die Leiste wieder im Editor: Die IDE hat den Fokus zurückgeholt; einmal zurück.
  if (FEntered <> nil) and not Bar.HasFocus then
  begin
    if TThread.GetTickCount64 - FEnteredAt <= FocusGraceMs then
    begin
      TAtlasGuard.Log(Format('Suchleiste: Fokus nach dem Klick an %s %s verloren (an %s); hole ihn zurück',
        [FEntered.ClassName, FEntered.Name, WindowName(Winapi.Windows.GetFocus)]));
      if FEntered.CanFocus then
        FEntered.SetFocus;
    end;
    FEntered := nil;
  end;
  // Liegt über der Leiste ein anderes Fenster, bekommt sie keine Klicks: protokollieren, nach vorn holen.
  if not GetCursorPos(Cursor) or not PtInRect(Bar.ClientRect, Bar.ScreenToClient(Cursor)) then
    Exit;
  Window := WindowFromPoint(Cursor);
  if Window = FProbed then
    Exit;
  FProbed := Window;
  if (Window = Bar.Handle) or IsChild(Bar.Handle, Window) then
    Exit;
  TAtlasGuard.Log(Format('Suchleiste: Über der Leiste liegt ein anderes Fenster (%s); hole die Leiste nach vorn',
    [WindowName(Window)]));
  Bar.BringToFront;
end;

class procedure TAtlasIdeSearch.Show;
begin
  Open(False);
end;

class procedure TAtlasIdeSearch.ShowInMethod;
begin
  Open(True);
end;

class function TAtlasIdeSearch.TryNext(ABackward: Boolean): Boolean;
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Area, Selection: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  From: TAtlasSearchPos;
  Index: Integer;
  Wrapped, HasSelection, Changed: Boolean;
begin
  Result := False;
  if FLast.IsEmpty or not TopView(View) then
    Exit;
  // Auswahl gilt nur in der Datei, in der gesucht wurde; in anderen Dateien die ganze Unit.
  if (FLast.Scope = TAtlasSearchScope.Selection) and not SameText(FLast.FileName, View.Buffer.FileName) then
    FLast.Scope := TAtlasSearchScope.UnitFile;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  From := CursorOf(View, Lines);
  HasSelection := SelectionOf(View, Lines, Selection);
  // Anderer Text markiert als zuletzt gesucht: nach der Markierung suchen.
  if HasSelection and (Selection.Start.Line = Selection.Stop.Line) and (Selection.Start.Line <= High(Lines)) then
  begin
    FLast := TAtlasSearchResults.FollowSelection(FLast, Copy(Lines[Selection.Start.Line],
      Selection.Start.Character + 1, Selection.Stop.Character - Selection.Start.Character), Changed);
    if Changed then
    begin
      FLast.FileName := View.Buffer.FileName;
      Repaint;
    end;
  end;
  // Vorwärts ab dem Ende der Markierung (dem Cursor), rückwärts ab ihrem Anfang.
  if ABackward and HasSelection then
    From := Selection.Start;
  if not AreaOf(Text, FLast, From, Area) then
  begin
    if FLast.Scope <> TAtlasSearchScope.Method then
    begin
      Say(TAtlasStrings.Text(TAtlasTextId.SearchNoSelection));
      Exit(True);
    end;
    // Außerhalb jeder Routine: die ganze Unit statt gar nichts.
    Say(TAtlasStrings.Text(TAtlasTextId.SearchOutsideMethod));
    Area := TAtlasSearchArea.Whole(Lines);
  end;
  Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  Result := True;
  if Length(Hits) = 0 then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.SearchNothing, [FLast.Text]));
    Exit;
  end;
  Index := TAtlasTextSearch.Next(Hits, From, ABackward, Wrapped);
  if Wrapped then
    Say(TAtlasStrings.Text(TAtlasTextId.SearchWrapped));
  SelectHit(View, Lines, Hits[Index]);
  UpdateCounter;
end;

class procedure TAtlasIdeSearch.FindNext;
begin
  if not TryNext(False) then
    Show;
end;

class procedure TAtlasIdeSearch.FindPrevious;
begin
  if not TryNext(True) then
    Show;
end;

class procedure TAtlasIdeSearch.ClearHighlights;
begin
  if (FBar <> nil) and FBar.Visible then
    CloseBar
  else
  begin
    FHighlight := False;
    Repaint;
  end;
end;

end.
