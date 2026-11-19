unit Atlas.Core.Editor.EditSurface;

// Der Editorpuffer, wie ihn eine Bearbeitungssitzung braucht, die Tasten
// abfängt und den Puffer selbst umschreibt (Bezeichner live mitziehen,
// mehrere Einfügemarken): Datei, Text, Cursor und Markierung, Schreiben als
// ein Rückgängig-Schritt, Rückgängig und Wiederholen. Der Vertrag (IAtlasEditSurface) steht in
// Atlas.Core.Editor.Contract; die IDE setzt ihn über IOTAEditView um
// (Atlas.IDE.Editor.EditSurface), die Tests über einen Text mit
// Rückgängig-Stapel (Atlas.Tests.EditSurfaceFake).
// Zeilen und Zeichen sind 0-basiert, Zeichen in UTF-16-Einheiten wie im LSP.
// Nur im Hauptthread.

interface

uses
  Atlas.Core.Editor.Contract;

type
  TAtlasTextEdit = Atlas.Core.Editor.Contract.TAtlasTextEdit;
  TAtlasTextEdits = Atlas.Core.Editor.Contract.TAtlasTextEdits;

  TAtlasEditSurfaces = record
  public
    /// <summary>Datei von ASurface; '' ohne Puffer.</summary>
    class function FileNameOf(const ASurface: IAtlasEditSurface): string; static;
  end;

implementation

{ TAtlasEditSurfaces }

class function TAtlasEditSurfaces.FileNameOf(const ASurface: IAtlasEditSurface): string;
begin
  Result := '';
  if ASurface <> nil then
  begin
    Result := ASurface.FileName;
  end;
end;

end.
