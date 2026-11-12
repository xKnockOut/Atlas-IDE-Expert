unit Atlas.IDE.Foundation.CodeView;

// Zeigt das vorderste Editorfenster gerade Code? Im Designer und auf der
// Willkommensseite der IDE ist der Code nicht zu sehen; Anfragen an den
// Server, die nur ihm dienen (Inlay-Hints, Code Lens, Gliederung,
// Diagnosen der offenen Datei, Interface-Kosten), ruhen dann. Vorher fragten
// sie im Takt weiter, und im Diagnoselog standen im Designer hover,
// inlayHint und documentSymbol. Eigene Unit, weil die Prüfung den Leisten-Host
// (oberster Editor) und die Designer-Ansicht braucht, die sich gegenseitig
// kennen. Nur im Hauptthread.

interface

type
  TAtlasIdeCodeView = class
  public
    /// <summary>Editor des vordersten Editorfensters zeigt Code: sichtbar, nicht von Designer oder
    /// Willkommensseite verdeckt. False ohne Editorfenster.</summary>
    class function InFront: Boolean; static;
  end;

implementation

uses
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.DesignerView;

class function TAtlasIdeCodeView.InFront: Boolean;
begin
  Result := TAtlasIdeDesignerView.CodeInFront(TAtlasEditorBarHost.TopEditor);
end;

end.
