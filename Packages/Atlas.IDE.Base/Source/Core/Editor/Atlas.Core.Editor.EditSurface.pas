unit Atlas.Core.Editor.EditSurface;

// Der Editorpuffer, wie ihn eine Bearbeitungssitzung braucht, die Tasten
// abfängt und den Puffer selbst umschreibt (Bezeichner live mitziehen,
// mehrere Einfügemarken): Datei, Text, Cursor und Markierung, Schreiben als
// ein Rückgängig-Schritt, Rückgängig und Wiederholen. Die IDE setzt den Vertrag über IOTAEditView um
// (Atlas.IDE.Editor.EditSurface), die Tests über einen Text mit
// Rückgängig-Stapel (Atlas.Tests.EditSurfaceFake).
// Zeilen und Zeichen sind 0-basiert, Zeichen in UTF-16-Einheiten wie im LSP.
// Nur im Hauptthread.

interface

type
  /// <summary>Ersetzung im Text: ab Start (Zeichenversatz, 0-basiert) Count Zeichen durch Insert.</summary>
  TAtlasTextEdit = record
    Start: Integer;
    Count: Integer;
    Insert: string;
    class function Create(AStart, ACount: Integer; const AInsert: string): TAtlasTextEdit; static;
  end;
  TAtlasTextEdits = TArray<TAtlasTextEdit>;

  /// <summary>Der Editorpuffer einer Ansicht, wie eine Bearbeitungssitzung ihn braucht.</summary>
  IAtlasEditSurface = interface
    ['{48874E87-1C11-4114-8B01-084EBC6F5C55}']
    function FileName: string;
    function IsReadOnly: Boolean;
    /// <summary>Ungespeicherte Änderungen?</summary>
    function IsModified: Boolean;
    /// <summary>Tabulatorweite des Puffers (für Anzeigespalten).</summary>
    function TabWidth: Integer;
    /// <summary>Ganzer Text des Puffers.</summary>
    function Text: string;
    /// <summary>Zeile ALine ohne Umbruch; '' außerhalb. Billiger als Text, etwa für einen Takt.</summary>
    function LineText(ALine: Integer): string;
    function HasSelection: Boolean;
    procedure ReadCaret(out ALine, ACharacter: Integer);
    /// <summary>Cursor setzen, Markierung aufheben, den Cursor sichtbar machen und neu zeichnen.</summary>
    procedure WriteCaret(ALine, ACharacter: Integer);
    /// <summary>Markierung als Anker und Cursor; ohne Markierung steht der Anker am Cursor.</summary>
    procedure ReadSelection(out AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer);
    /// <summary>Markierung vom Anker zum Cursor setzen (ohne Markierung, wenn beide gleich sind) und den Cursor
    /// sichtbar machen; zeichnet nicht neu.</summary>
    procedure WriteSelection(AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer);
    /// <summary>Zeile ALine in den sichtbaren Bereich holen, ohne den Cursor zu bewegen.</summary>
    procedure Reveal(ALine: Integer);
    /// <summary>Ansicht neu zeichnen.</summary>
    procedure Paint;
    /// <summary>AEdits (aufsteigend, ohne Überlappung) als einen Rückgängig-Schritt schreiben. Die Versätze
    /// beziehen sich auf ABase, den Text des Puffers vor dem Schreiben.</summary>
    procedure Write(const ABase: string; const AEdits: TAtlasTextEdits);
    /// <summary>Letzten Schritt des Puffers zurücknehmen; False, wenn es keinen gibt.</summary>
    function Undo: Boolean;
    /// <summary>Zurückgenommenen Schritt wiederholen; False, wenn es keinen gibt.</summary>
    function Redo: Boolean;
  end;

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

{ TAtlasTextEdit }

class function TAtlasTextEdit.Create(AStart, ACount: Integer; const AInsert: string): TAtlasTextEdit;
begin
  Result.Start := AStart;
  Result.Count := ACount;
  Result.Insert := AInsert;
end;

end.
