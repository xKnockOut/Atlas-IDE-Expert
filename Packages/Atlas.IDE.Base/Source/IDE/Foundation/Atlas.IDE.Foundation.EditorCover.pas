unit Atlas.IDE.Foundation.EditorCover;

// Oben im Editor überdeckte Zeilen (mitlaufender Kopf, #506): Alle Zeichner
// von Atlas malen in plsEndPaint, und die IDE ruft sie je Zeile in der
// Reihenfolge ihrer Anmeldung auf. Module melden sich nach Base an; ihre
// Zeichnungen (Werte beim Debuggen, Inlay-Hints, Code Lens, Markierungen,
// Fehlertexte, Besitzhinweise) lagen deshalb über dem Kopf, sobald eine
// Zeile hinter ihm verschwand. Statt einer Reihenfolge, die keiner in der Hand
// hat, fragt jeder Zeichner vor dem Malen Covers und lässt überdeckte Zeilen
// aus. Wer die Zeilen überdeckt, meldet sich mit SetRows an (nur einer, heute
// der mitlaufende Kopf); ohne Anmeldung ist nichts überdeckt.
// - Rows rechnet für die oberste Zeile der gerade gezeichneten Ansicht, nicht
//   aus dem letzten Bild: Nach einem Bildlauf ändert sich die Zahl der
//   Kopfzeilen schon mit der ersten neu gemalten Zeile, gleich ob der Kopf vor
//   oder nach dem fragenden Zeichner an der Reihe ist.
// - Ob eine Bildschirmzeile darunter liegt, entscheidet
//   TAtlasGuideStroke.UnderHeader (Atlas.Core.Editor.GuideStroke).
// Nur im Hauptthread.

interface

uses
  System.Types,
  ToolsAPI.Editor;

type
  /// <summary>Zahl der oben überdeckten Bildschirmzeilen für die Ansicht, die AContext gerade zeichnet; 0 ohne.
  /// </summary>
  TAtlasEditorCoverRows = reference to function(const AContext: INTACodeEditorPaintContext): Integer;

  TAtlasIdeEditorCover = class
  private class var
    FRows: TAtlasEditorCoverRows;
  public
    /// <summary>Meldet an, wer oben Zeilen überdeckt; nil meldet ab.</summary>
    class procedure SetRows(const ARows: TAtlasEditorCoverRows); static;
    /// <summary>Oben überdeckte Bildschirmzeilen der Ansicht von AContext; 0 ohne Anmeldung.</summary>
    class function Rows(const AContext: INTACodeEditorPaintContext): Integer; static;
    /// <summary>True, wenn die Zeile ARect (Koordinaten des Editors) von AContext überdeckt ist: Der Zeichner lässt
    /// sie aus.</summary>
    class function Covers(const ARect: TRect; const AContext: INTACodeEditorPaintContext): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Editor.GuideStroke;

{ TAtlasIdeEditorCover }

class procedure TAtlasIdeEditorCover.SetRows(const ARows: TAtlasEditorCoverRows);
begin
  FRows := ARows;
end;

class function TAtlasIdeEditorCover.Rows(const AContext: INTACodeEditorPaintContext): Integer;
begin
  Result := 0;
  if Assigned(FRows) and (AContext <> nil) then
  begin
    Result := FRows(AContext);
  end;
end;

class function TAtlasIdeEditorCover.Covers(const ARect: TRect; const AContext: INTACodeEditorPaintContext): Boolean;
var
  mRows: Integer;
begin
  mRows := Rows(AContext);
  Result := (mRows > 0) and TAtlasGuideStroke.UnderHeader(TAtlasGuideStroke.RowIndex(ARect.Top, ARect.Height),
    mRows);
end;

end.
