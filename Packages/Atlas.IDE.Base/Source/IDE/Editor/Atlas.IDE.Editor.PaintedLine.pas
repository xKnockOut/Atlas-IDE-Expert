unit Atlas.IDE.Editor.PaintedLine;

// Gemeinsame Vorprüfung für Markierungen im Editor, die auf einem gemerkten
// Stand der Datei beruhen (Austrittspunkte, Neuzuweisungen, Treffer der
// Markierung, Ausdruckstyp, Entpacken): gezeichnet wird nur nach dem Zeichnen
// der Zeile (plsEndPaint), in der gemerkten Datei und nur, wenn die Zeile im
// Editor noch dem gemerkten Stand entspricht (sonst kommt gleich ein neuer
// Takt). Nur im Hauptthread.

interface

uses
  ToolsAPI.Editor;

type
  TAtlasPaintedLine = record
  public
    /// <summary>True, wenn AContext nach dem Zeichnen eine Zeile von AFileName zeigt, die in ALines liegt und im
    /// Editor (ohne Leerzeichen am Ende) gleich lautet; ALine ist dann die Zeile ab 0, sonst -1.</summary>
    class function Resolve(AStage: TPaintLineStage; ABeforeEvent: Boolean; const AContext: INTACodeEditorPaintContext;
      const AFileName: string; const ALines: TArray<string>; out ALine: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasPaintedLine.Resolve(AStage: TPaintLineStage; ABeforeEvent: Boolean;
  const AContext: INTACodeEditorPaintContext; const AFileName: string; const ALines: TArray<string>;
  out ALine: Integer): Boolean;
var
  mLineState: INTACodeEditorLineState;
begin
  ALine := -1;
  Result := not ABeforeEvent and (AStage = plsEndPaint) and (AContext <> nil) and
    SameText(AContext.FileName, AFileName);
  if not Result then
  begin
    Exit;
  end;
  mLineState := AContext.LineState;
  ALine := AContext.LogicalLineNum - 1;
  Result := (mLineState <> nil) and (ALine >= 0) and (ALine < Length(ALines)) and
    (TrimRight(mLineState.Text) = TrimRight(ALines[ALine]));
  if not Result then
  begin
    ALine := -1;
  end;
end;

end.
