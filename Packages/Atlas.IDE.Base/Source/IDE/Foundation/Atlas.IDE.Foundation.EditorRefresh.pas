unit Atlas.IDE.Foundation.EditorRefresh;

// Den obersten Editor neu zeichnen lassen, ohne ein Editorfenster anzulegen
// (#1233): INTACodeEditorServices.InvalidateTopEditor legt ein neues
// Editorfenster an, wenn keins offen ist. Beim Beenden baut die IDE die
// Editorfenster vor den Packages ab; Funktionen, die beim Entladen den Editor
// neu zeichnen ließen (z. B. DebugAccessViolation, DebugInlineValues), legten
// so ein frisches EditWindow_0 an. Andere Experten hängen sich mit eigenen
// Komponenten hinein (Beyond Compare: TBcEditorTabMenu); die IDE gab das
// Fenster erst nach dem Entladen von deren DLL frei, Zugriffsverletzung in
// rtl370 (Offset 133BE4). Während der Arbeit öffnete ein Neuzeichnen ohne
// offenen Editor sonst ein leeres Editorfenster.
// - Neu gezeichnet wird nur, solange ein Editorfenster (TEditWindow) besteht
//   und die IDE nicht beendet wird.
// - Alle Dienste zeichnen den Editor nur hierüber neu;
//   Tools/Check-WindowHosts.ps1 prüft das.
// TAtlasIdeEditorCover: oben im Editor überdeckte Zeilen (mitlaufender Kopf,
// #506). Alle Zeichner malen in plsEndPaint, und die IDE ruft sie je Zeile in
// der Reihenfolge ihrer Anmeldung auf, Module nach Base. Ihre Zeichnungen
// (Werte beim Debuggen, Inlay-Hints, Code Lens, Markierungen, Fehlertexte,
// Besitzhinweise) lagen deshalb über dem Kopf, sobald eine Zeile hinter ihm
// verschwand. Statt einer Reihenfolge, die keiner in der Hand hat, fragt
// jeder Zeichner vor dem Malen Covers und lässt überdeckte Zeilen aus. Wer
// oben Zeilen überdeckt, meldet sich mit SetCovers an (heute nur der Kopf);
// ohne Anmeldung ist nichts überdeckt.
// Nur im Hauptthread.

interface

uses
  System.Types,
  ToolsAPI.Editor;

type
  /// <summary>True, wenn die Zeile ARect (Koordinaten des Editors) in der Ansicht, die AContext gerade zeichnet,
  /// überdeckt ist.</summary>
  TAtlasEditorCoverTest = reference to function(const ARect: TRect; const AContext: INTACodeEditorPaintContext):
    Boolean;

  TAtlasIdeEditorCover = class
  private class var
    FCovers: TAtlasEditorCoverTest;
  public
    /// <summary>Meldet an, wer oben Zeilen überdeckt; nil meldet ab.</summary>
    class procedure SetCovers(const ACovers: TAtlasEditorCoverTest); static;
    /// <summary>True, wenn die Zeile ARect von AContext überdeckt ist: Der Zeichner lässt sie aus.</summary>
    class function Covers(const ARect: TRect; const AContext: INTACodeEditorPaintContext): Boolean; static;
  end;

  TAtlasIdeEditorRefresh = class
  public
    /// <summary>Steht ein Editorfenster, das neu gezeichnet werden kann (und die IDE wird nicht beendet)?</summary>
    class function EditorOpen: Boolean; static;
    /// <summary>InvalidateTopEditor, aber nur bei offenem Editorfenster.</summary>
    class procedure InvalidateTop(const AServices: INTACodeEditorServices); overload; static;
    class procedure InvalidateTop(const AServices: INTACodeEditorServices280); overload; static;
    /// <summary>InvalidateTopEditorLogicalLine, aber nur bei offenem Editorfenster.</summary>
    class procedure InvalidateTopLine(const AServices: INTACodeEditorServices; ALogicalLine: Integer); static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms;

const
  cEditWindowClass = 'TEditWindow';

{ TAtlasIdeEditorCover }

class procedure TAtlasIdeEditorCover.SetCovers(const ACovers: TAtlasEditorCoverTest);
begin
  FCovers := ACovers;
end;

class function TAtlasIdeEditorCover.Covers(const ARect: TRect; const AContext: INTACodeEditorPaintContext): Boolean;
begin
  Result := Assigned(FCovers) and (AContext <> nil) and FCovers(ARect, AContext);
end;

{ TAtlasIdeEditorRefresh }

class function TAtlasIdeEditorRefresh.EditorOpen: Boolean;
var
  mIndex: Integer;
  mForm: TCustomForm;
begin
  if Application.Terminated or (Application.MainForm = nil) or
    (csDestroying in Application.MainForm.ComponentState) then
  begin
    Exit(False);
  end;
  for mIndex := 0 to Screen.CustomFormCount - 1 do
  begin
    mForm := Screen.CustomForms[mIndex];
    if SameText(mForm.ClassName, cEditWindowClass) and not (csDestroying in mForm.ComponentState) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class procedure TAtlasIdeEditorRefresh.InvalidateTop(const AServices: INTACodeEditorServices);
begin
  if (AServices <> nil) and EditorOpen then
  begin
    AServices.InvalidateTopEditor;
  end;
end;

class procedure TAtlasIdeEditorRefresh.InvalidateTop(const AServices: INTACodeEditorServices280);
begin
  if (AServices <> nil) and EditorOpen then
  begin
    AServices.InvalidateTopEditor;
  end;
end;

class procedure TAtlasIdeEditorRefresh.InvalidateTopLine(const AServices: INTACodeEditorServices;
  ALogicalLine: Integer);
begin
  if (AServices <> nil) and EditorOpen then
  begin
    AServices.InvalidateTopEditorLogicalLine(ALogicalLine);
  end;
end;

end.
