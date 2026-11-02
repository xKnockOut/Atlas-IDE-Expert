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
// Nur im Hauptthread.

interface

uses
  ToolsAPI.Editor;

type
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
  EditWindowClass = 'TEditWindow';

{ TAtlasIdeEditorRefresh }

class function TAtlasIdeEditorRefresh.EditorOpen: Boolean;
var
  Index: Integer;
  Form: TCustomForm;
begin
  if Application.Terminated or (Application.MainForm = nil) or
    (csDestroying in Application.MainForm.ComponentState) then
    Exit(False);
  for Index := 0 to Screen.CustomFormCount - 1 do
  begin
    Form := Screen.CustomForms[Index];
    if SameText(Form.ClassName, EditWindowClass) and not (csDestroying in Form.ComponentState) then
      Exit(True);
  end;
  Result := False;
end;

class procedure TAtlasIdeEditorRefresh.InvalidateTop(const AServices: INTACodeEditorServices);
begin
  if (AServices <> nil) and EditorOpen then
    AServices.InvalidateTopEditor;
end;

class procedure TAtlasIdeEditorRefresh.InvalidateTop(const AServices: INTACodeEditorServices280);
begin
  if (AServices <> nil) and EditorOpen then
    AServices.InvalidateTopEditor;
end;

class procedure TAtlasIdeEditorRefresh.InvalidateTopLine(const AServices: INTACodeEditorServices;
  ALogicalLine: Integer);
begin
  if (AServices <> nil) and EditorOpen then
    AServices.InvalidateTopEditorLogicalLine(ALogicalLine);
end;

end.
