unit Atlas.IDE.Search.Editor;

// Atlas-Suche im Editor (#877, #893): Zugriff auf den obersten Editor der IDE. Cursor, Markierung und Bereich
// als Positionen im Text, Treffer markieren und die Treffer der letzten Suche an der Schreibmarke. Ohne Zustand;
// genutzt von Leiste, Zeichner, Zähler, Schritten und Ersetzen. Nur im Hauptthread.

interface

uses
  ToolsAPI,
  Atlas.Core.Search.Matching;

type
  TAtlasIdeSearchEditor = class
  public
    class function TopView(out AView: IOTAEditView): Boolean; static;
    class function CursorOf(const AView: IOTAEditView; const ALines: TArray<string>): TAtlasSearchPos; static;
    class function SelectionOf(const AView: IOTAEditView; const ALines: TArray<string>;
      out AArea: TAtlasSearchArea): Boolean; static;
    /// <summary>Text einer einzeiligen Markierung; '' ohne oder bei mehrzeiliger.</summary>
    class function LineSelection(const ALines: TArray<string>; const AArea: TAtlasSearchArea;
      AHasSelection: Boolean): string; static;
    /// <summary>Bereich der Suche im Text: Auswahl wie gemerkt, Methode an ACursor, sonst ganzer Text.</summary>
    class function AreaOf(const AText: string; const AQuery: TAtlasSearchQuery; const ACursor: TAtlasSearchPos;
      out AArea: TAtlasSearchArea): Boolean; static;
    /// <summary>Treffer von AQuery im Bereich an der Schreibmarke (Anfang einer Markierung, sonst Cursor).</summary>
    class function HitsAtCursor(const AView: IOTAEditView; const AQuery: TAtlasSearchQuery;
      out ALines: TArray<string>; out AAt: TAtlasSearchPos): TArray<TAtlasSearchHit>; static;
    class procedure SelectHit(const AView: IOTAEditView; const ALines: TArray<string>;
      const AHit: TAtlasSearchHit); static;
    /// <summary>Index des Treffers, der genau markiert ist; -1 ohne.</summary>
    class function MarkedHit(const AView: IOTAEditView; const ALines: TArray<string>;
      const AHits: TArray<TAtlasSearchHit>): Integer; static;
    /// <summary>Tabulatorweite des obersten Editors, ohne Editor 8.</summary>
    class function TabWidth: Integer; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Search.Scopes,
  Atlas.Text.Lines,
  Atlas.IDE.Foundation.EditorBuffer;

/// <summary>Zeile ARow (0-basiert) oder '' außerhalb.</summary>
function LineAt(const ALines: TArray<string>; ARow: Integer): string;
begin
  Result := '';
  if (ARow >= 0) and (ARow <= High(ALines)) then
  begin
    Result := ALines[ARow];
  end;
end;

class function TAtlasIdeSearchEditor.TopView(out AView: IOTAEditView): Boolean;
var
  mEditors: IOTAEditorServices;
begin
  AView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    AView := mEditors.TopView;
  end;
  Result := (AView <> nil) and (AView.Buffer <> nil);
end;

class function TAtlasIdeSearchEditor.CursorOf(const AView: IOTAEditView;
  const ALines: TArray<string>): TAtlasSearchPos;
var
  mCursor: TOTAEditPos;
  mRow: Integer;
begin
  mCursor := AView.CursorPos;
  mRow := mCursor.Line - 1;
  Result := TAtlasSearchPos.Create(mRow, TLspSession.ColumnToIndex(LineAt(ALines, mRow), mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer)));
end;

class function TAtlasIdeSearchEditor.SelectionOf(const AView: IOTAEditView; const ALines: TArray<string>;
  out AArea: TAtlasSearchArea): Boolean;
var
  mBlock: IOTAEditBlock;
  mTabWidth: Integer;
begin
  AArea := TAtlasSearchArea.Create(0, 0, 0, 0);
  mBlock := AView.Block;
  Result := (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0);
  if not Result then
  begin
    Exit;
  end;
  mTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  AArea := TAtlasSearchArea.Create(mBlock.StartingRow - 1,
    TLspSession.ColumnToIndex(LineAt(ALines, mBlock.StartingRow - 1), mBlock.StartingColumn, mTabWidth),
    mBlock.EndingRow - 1,
    TLspSession.ColumnToIndex(LineAt(ALines, mBlock.EndingRow - 1), mBlock.EndingColumn, mTabWidth));
end;

class function TAtlasIdeSearchEditor.LineSelection(const ALines: TArray<string>; const AArea: TAtlasSearchArea;
  AHasSelection: Boolean): string;
begin
  Result := '';
  if AHasSelection and (AArea.Start.Line = AArea.Stop.Line) and (AArea.Start.Line <= High(ALines)) then
  begin
    Result := Copy(ALines[AArea.Start.Line], AArea.Start.Character + 1, AArea.Stop.Character - AArea.Start.Character);
  end;
end;

class function TAtlasIdeSearchEditor.AreaOf(const AText: string; const AQuery: TAtlasSearchQuery;
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

class function TAtlasIdeSearchEditor.HitsAtCursor(const AView: IOTAEditView; const AQuery: TAtlasSearchQuery;
  out ALines: TArray<string>; out AAt: TAtlasSearchPos): TArray<TAtlasSearchHit>;
var
  mText: string;
  mArea, mSelection: TAtlasSearchArea;
begin
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  ALines := TTextLines.SplitLines(mText);
  AAt := CursorOf(AView, ALines);
  if SelectionOf(AView, ALines, mSelection) then
  begin
    AAt := mSelection.Start;
  end;
  Result := nil;
  if AreaOf(mText, AQuery, AAt, mArea) then
  begin
    Result := TAtlasTextSearch.FindAll(ALines, AQuery.Text, AQuery.Options, mArea);
  end;
end;

class procedure TAtlasIdeSearchEditor.SelectHit(const AView: IOTAEditView; const ALines: TArray<string>;
  const AHit: TAtlasSearchHit);
var
  mTabWidth: Integer;
  mLineText: string;
  mTarget: TOTAEditPos;
begin
  mTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  mLineText := LineAt(ALines, AHit.Line);
  AView.Block.Style := btNonInclusive;
  mTarget.Line := AHit.Line + 1;
  mTarget.Col := TLspSession.IndexToColumn(mLineText, AHit.Character, mTabWidth);
  AView.CursorPos := mTarget;
  // Anfang markieren, Cursor ans Ende, Ende markieren: Der Cursor steht danach hinter dem Treffer.
  AView.Block.BeginBlock;
  mTarget.Col := TLspSession.IndexToColumn(mLineText, AHit.Character + AHit.Length, mTabWidth);
  AView.CursorPos := mTarget;
  AView.Block.EndBlock;
  AView.MoveViewToCursor;
  AView.Paint;
end;

class function TAtlasIdeSearchEditor.MarkedHit(const AView: IOTAEditView; const ALines: TArray<string>;
  const AHits: TArray<TAtlasSearchHit>): Integer;
var
  mSelection: TAtlasSearchArea;
  mIndex: Integer;
begin
  Result := -1;
  if not SelectionOf(AView, ALines, mSelection) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AHits) do
  begin
    if (TAtlasSearchPos.Compare(AHits[mIndex].StartPos, mSelection.Start) = 0) and
      (TAtlasSearchPos.Compare(AHits[mIndex].StopPos, mSelection.Stop) = 0) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasIdeSearchEditor.TabWidth: Integer;
var
  mView: IOTAEditView;
begin
  Result := 8;
  if TopView(mView) then
  begin
    Result := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  end;
end;

end.
