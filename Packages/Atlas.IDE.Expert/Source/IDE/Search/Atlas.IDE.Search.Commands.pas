unit Atlas.IDE.Search.Commands;

// Atlas-Suche im Editor (#877, #878):
// - Show: Suchdialog (Atlas.UI.Search.Dialog) für die oberste Ansicht. Vorschlag
//   ist die einzeilige Markierung, sonst der Bezeichner am Cursor, sonst die
//   letzte Suche. ShowInMethod („In Methode suchen“, #877) stellt den Bereich
//   auf Methode und die Stufe auf die innerste Routine.
// - Nach dem Dialog wird der gewählte Treffer markiert (sonst der nächste ab
//   dem Cursor) und die Suche als „letzte Suche“ gemerkt. Bei Bereich Auswahl
//   gilt die Auswahl beim Öffnen; sie wandert nicht mit den Treffern.
// - TryNext (F3/Umschalt+F3): nächster bzw. voriger Treffer der letzten Suche
//   mit Umlauf (Meldung in der Meldungsansicht). Ohne letzte Suche False: die
//   Taste geht weiter (Markierung suchen bzw. „Erneut suchen“ der IDE).
// - Hervorhebung: Solange eine Suche gemerkt ist, rahmt ein Editor-Zeichner
//   alle Treffer der Datei im Bereich (neu berechnet, wenn sich der Puffer
//   oder die Suche ändert). ClearHighlights bzw. ein leerer Suchtext beendet sie.
// Tasten: Strg+F/F3/Umschalt+F3 nur mit search.replaceIdeSearch
// (Atlas.IDE.Commands.Bindings), „In Methode suchen“ immer.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Search.Matching;

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
  private class var
    FLast: TAtlasSearchQuery;
    FVersion: Integer;
    FPainter: TPainter;
    FMessage: TProc<string>;
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
  public
    /// <summary>Zeichner anmelden; AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Suchdialog (Strg+F, Befehl Atlas.Search).</summary>
    class procedure Show; static;
    /// <summary>Suchdialog mit Bereich Methode (#877, Befehl Atlas.SearchInMethod).</summary>
    class procedure ShowInMethod; static;
    /// <summary>F3/Umschalt+F3: False ohne letzte Atlas-Suche oder ohne Editor.</summary>
    class function TryNext(ABackward: Boolean): Boolean; static;
    /// <summary>Für Palette und Menü: wie TryNext, ohne letzte Suche öffnet sich der Dialog.</summary>
    class procedure FindNext; static;
    class procedure FindPrevious; static;
    class procedure ClearHighlights; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Search.Scopes,
  Atlas.Text.Lines,
  Atlas.UI.Strings,
  Atlas.UI.Search.Dialog,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle;

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
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or TAtlasIdeSearch.FLast.IsEmpty then
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

{ TAtlasIdeSearch }

class procedure TAtlasIdeSearch.Install(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FPainter = nil then
    FPainter := TPainter.Create;
end;

class procedure TAtlasIdeSearch.Uninstall;
begin
  FreeAndNil(FPainter);
  FMessage := nil;
  FLast := Default(TAtlasSearchQuery);
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

class procedure TAtlasIdeSearch.Open(AInMethod: Boolean);
var
  View: IOTAEditView;
  Text, Proposal: string;
  Lines, Levels: TArray<string>;
  Cursor: TAtlasSearchPos;
  Selection, Area: TAtlasSearchArea;
  HasSelection: Boolean;
  Query: TAtlasSearchQuery;
  Routine: TAtlasSearchRoutine;
  Hits: TArray<TAtlasSearchHit>;
  Chosen, Index: Integer;
  Wrapped: Boolean;
  Run: TAtlasSearchRun;
begin
  if not TopView(View) then
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
  Query := FLast;
  Query.Text := Proposal;
  // Mehrzeilige Markierung: als Bereich vorschlagen.
  if HasSelection and (Selection.Start.Line <> Selection.Stop.Line) then
    Query.Scope := TAtlasSearchScope.Selection
  else if Query.Scope = TAtlasSearchScope.Selection then
    Query.Scope := TAtlasSearchScope.UnitFile;
  if AInMethod then
  begin
    Query.Scope := TAtlasSearchScope.Method;
    Query.Level := 0;
  end;
  Query.Area := Selection;
  Levels := nil;
  for Routine in TAtlasSearchScopes.RoutinesAt(Text, Cursor) do
    Levels := Levels + [Routine.Caption];
  Run :=
    procedure(const AQuery: TAtlasSearchQuery; out ACaptions: TArray<string>; out AMessage: string)
    var
      Found: TAtlasSearchArea;
      Hit: TAtlasSearchHit;
    begin
      ACaptions := nil;
      AMessage := '';
      if not TAtlasSearchScopes.AreaFor(Text, AQuery.Scope, Cursor, Selection, AQuery.Level, Found) then
      begin
        if AQuery.Scope = TAtlasSearchScope.Method then
          AMessage := TAtlasStrings.Text(TAtlasTextId.SearchNoMethod)
        else
          AMessage := TAtlasStrings.Text(TAtlasTextId.SearchNoSelection);
        Exit;
      end;
      for Hit in TAtlasTextSearch.FindAll(Lines, AQuery.Text, AQuery.Options, Found) do
        ACaptions := ACaptions + [TAtlasTextSearch.HitCaption(Lines, Hit)];
    end;
  if not TAtlasSearchDialog.Execute(Query, Levels, HasSelection, Run, Chosen) then
    Exit;
  if not TAtlasSearchScopes.AreaFor(Text, Query.Scope, Cursor, Selection, Query.Level, Area) then
    Exit;
  // Gemerkt wird der Bereich beim Suchen (Auswahl; Methode als Rückfall außerhalb jeder Routine).
  Query.Area := Area;
  Query.FileName := View.Buffer.FileName;
  FLast := Query;
  Repaint;
  Hits := TAtlasTextSearch.FindAll(Lines, Query.Text, Query.Options, Area);
  if Length(Hits) = 0 then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.SearchNothing, [Query.Text]));
    Exit;
  end;
  Index := Chosen;
  if (Index < 0) or (Index > High(Hits)) then
    Index := TAtlasTextSearch.Next(Hits, Cursor, False, Wrapped);
  SelectHit(View, Lines, Hits[Index]);
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
  Wrapped: Boolean;
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
  // Vorwärts ab dem Ende der Markierung (dem Cursor), rückwärts ab ihrem Anfang.
  if ABackward and SelectionOf(View, Lines, Selection) then
    From := Selection.Start;
  if not AreaOf(Text, FLast, From, Area) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.SearchNoMethod));
    Exit(True);
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
  FLast.Text := '';
  Repaint;
end;

end.
