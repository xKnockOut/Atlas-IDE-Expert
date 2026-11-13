unit Atlas.IDE.Debug.LineEnd;

// Platz am Zeilenende für Debug-Anzeigen hinter den Werten im Editor (#508):
// „Warum bin ich hier?“ (#1878) und angeheftete Werte (#526) zeichnen dort
// nacheinander. Start sucht die Spalte zwei Zeichen hinter dem letzten Zeichen
// der Zeile (Tabs aufgelöst), reiht sich über TAtlasLineTail hinter das, was
// andere Zeichner in dieser Zeile schon gesetzt haben, und stellt Schrift und
// Farben des Zeichners auf den Hintergrund ein. Nur im Hauptthread verwenden.

interface

uses
  System.Types,
  ToolsAPI.Editor,
  Atlas.UI.Debug.InlineValuePainter;

type
  TAtlasDebugLineEnd = record
  public
    /// <summary>Linke Kante für AOwner in der Zeile von AContext; ALineText ist der Text, dessen Ende zählt.
    /// AKey für Finish.</summary>
    class function Start(AOwner: TObject; const AContext: INTACodeEditorPaintContext; const ARect: TRect;
      const ALineText: string; AStyle: TAtlasInlineValuePainter; out AKey: string): Integer; static;
    /// <summary>AOwner hat bis ARight gezeichnet; der nächste Zeichner beginnt dahinter.</summary>
    class procedure Finish(AOwner: TObject; const AKey: string; ARight: Integer); static;
    /// <summary>Tabweite des Puffers; 0 ohne.</summary>
    class function TabWidth(const AContext: INTACodeEditorPaintContext): Integer; static;
    /// <summary>Entspricht die Zeile im Editor AStored (Leerraum am Ende zählt nicht)?</summary>
    class function Matches(const AContext: INTACodeEditorPaintContext; const AStored: string): Boolean; static;
    /// <summary>Den obersten Editor neu zeichnen lassen.</summary>
    class procedure Invalidate; static;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.Graphics,
  ToolsAPI,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.LineTail,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorRefresh;

const
  /// <summary>Abstand in Zeichen hinter dem letzten Zeichen der Zeile.</summary>
  cGapColumns = 2;

class procedure TAtlasDebugLineEnd.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

class function TAtlasDebugLineEnd.TabWidth(const AContext: INTACodeEditorPaintContext): Integer;
begin
  Result := 0;
  if (AContext.EditView <> nil) and (AContext.EditView.Buffer <> nil) then
  begin
    Result := TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer);
  end;
end;

class function TAtlasDebugLineEnd.Matches(const AContext: INTACodeEditorPaintContext; const AStored: string): Boolean;
var
  mLineState: INTACodeEditorLineState;
  mTabWidth: Integer;
begin
  mLineState := AContext.LineState;
  Result := (mLineState <> nil) and (AContext.EditView <> nil) and (AContext.EditView.Buffer <> nil);
  if Result then
  begin
    mTabWidth := TabWidth(AContext);
    Result := TrimRight(TAtlasPairs.DisplayLine(mLineState.Text, mTabWidth)) =
      TrimRight(TAtlasPairs.DisplayLine(AStored, mTabWidth));
  end;
end;

class function TAtlasDebugLineEnd.Start(AOwner: TObject; const AContext: INTACodeEditorPaintContext;
  const ARect: TRect; const ALineText: string; AStyle: TAtlasInlineValuePainter; out AKey: string): Integer;
var
  mCell: TRect;
  mSample: COLORREF;
begin
  // Spalten 1-basiert: erste Spalte hinter dem letzten Zeichen plus Abstand.
  mCell := AContext.EditorState.GetCharacterPosPx(Length(TAtlasPairs.DisplayLine(TrimRight(ALineText),
    TabWidth(AContext))) + 1 + cGapColumns, AContext.EditorLineNum);
  AKey := TAtlasLineTail.KeyOf(AContext.FileName, AContext.LogicalLineNum, AContext.EditorLineNum, ARect.Top);
  Result := TAtlasLineTail.Start(AOwner, AKey, mCell.Left);
  mSample := GetPixel(AContext.Canvas.Handle, Result, ARect.Top + 1);
  if mSample = CLR_INVALID then
  begin
    mSample := COLORREF(ColorToRGB(AContext.Canvas.Brush.Color));
  end;
  AStyle.Ensure(mSample, AContext.Canvas.Font);
end;

class procedure TAtlasDebugLineEnd.Finish(AOwner: TObject; const AKey: string; ARight: Integer);
begin
  TAtlasLineTail.Finish(AOwner, AKey, ARight);
end;

end.
