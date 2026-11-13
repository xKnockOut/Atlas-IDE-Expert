unit Atlas.Core.Files.Contract;

// Contract des Plugin-Features Files: Inhalt einer Textdatei samt Kodierung
// (#121). Andere Features (z. B. Undo) beschreiben damit Dateiinhalte, ohne
// das Root Atlas.Core.Files.TextFile zu importieren.
// IAtlasEditorFiles ist die schmale Sicht auf die Dateien, die in der IDE offen
// sind (Puffer lesen, Modul speichern). Entscheidungen, die den Pufferzustand
// brauchen, hängen nur daran und lassen sich mit einer Fälschung ohne IDE
// testen (#1967); die Umsetzung über die Open Tools API ist
// Atlas.IDE.Foundation.EditorFiles. IAtlasActiveEditor ist ebenso die schmale
// Sicht auf den oberen Editor (Datei und Schreibmarke), umgesetzt in
// Atlas.IDE.Foundation.ActiveEditor.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  TAtlasTextEncoding = (Utf8Bom, Utf8, Utf16LE, Utf16BE, Ansi);

  TAtlasTextFileContent = record
    Text: string;
    Encoding: TAtlasTextEncoding;
    /// <summary>Codepage bei Ansi; 0 = ANSI-Codepage des Systems.</summary>
    CodePage: Integer;
  end;

  EAtlasTextFileError = class(Exception);

  /// <summary>Puffer einer Datei im Editor, wie ihn die IDE meldet.</summary>
  TAtlasEditorFile = record
    /// <summary>Ein Modul der IDE hat die Datei offen.</summary>
    Open: Boolean;
    /// <summary>Text des Puffers, auch ungespeichert; '' bei geschlossener Datei.</summary>
    Text: string;
    /// <summary>Der Puffer ist ungespeichert geändert.</summary>
    Modified: Boolean;
    /// <summary>Die Datei ist in der IDE nicht offen.</summary>
    class function Closed: TAtlasEditorFile; static;
    /// <summary>Offener Puffer mit Text AText; AModified = ungespeichert geändert.</summary>
    class function Opened(const AText: string; AModified: Boolean): TAtlasEditorFile; static;
  end;

  /// <summary>Dateien, die in der IDE offen sind; alle Aufrufe im Hauptthread.</summary>
  IAtlasEditorFiles = interface
    ['{108A3A1D-BFD4-4720-B470-267346CBDFE7}']
    /// <summary>Puffer der Datei AFileName; Open = False, wenn kein Modul sie offen hat.</summary>
    function Buffer(const AFileName: string): TAtlasEditorFile;
    /// <summary>Speichert das Modul der Datei AFileName; False, wenn keins sie offen hat.</summary>
    function Save(const AFileName: string): Boolean;
  end;

  /// <summary>Schreibmarke des oberen Editors, wie sie die IDE meldet.</summary>
  TAtlasActiveEditorPos = record
    /// <summary>Datei des oberen Editors; '' ohne Editor.</summary>
    FileName: string;
    /// <summary>Zeile der Schreibmarke, 0-basiert.</summary>
    Line: Integer;
    /// <summary>Zeichenindex der Schreibmarke in ihrer Zeile (ein Tabulator ist ein Zeichen).</summary>
    Character: Integer;
    /// <summary>Kein Editor offen.</summary>
    class function None: TAtlasActiveEditorPos; static;
    /// <summary>Schreibmarke in AFileName an Zeile ALine und Zeichen ACharacter (beide 0-basiert).</summary>
    class function At(const AFileName: string; ALine, ACharacter: Integer): TAtlasActiveEditorPos; static;
    /// <summary>Ein Editor ist offen.</summary>
    function Present: Boolean;
  end;

  /// <summary>Der obere Editor der IDE; alle Aufrufe im Hauptthread.</summary>
  IAtlasActiveEditor = interface
    ['{183B49F3-5255-4FB5-8D41-BBDAB16C0EA7}']
    /// <summary>Datei und Schreibmarke des oberen Editors; None ohne Editor.</summary>
    function Caret: TAtlasActiveEditorPos;
  end;

implementation

class function TAtlasEditorFile.Closed: TAtlasEditorFile;
begin
  Result := Default(TAtlasEditorFile);
end;

class function TAtlasEditorFile.Opened(const AText: string; AModified: Boolean): TAtlasEditorFile;
begin
  Result.Open := True;
  Result.Text := AText;
  Result.Modified := AModified;
end;

class function TAtlasActiveEditorPos.None: TAtlasActiveEditorPos;
begin
  Result := Default(TAtlasActiveEditorPos);
end;

class function TAtlasActiveEditorPos.At(const AFileName: string; ALine, ACharacter: Integer): TAtlasActiveEditorPos;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

function TAtlasActiveEditorPos.Present: Boolean;
begin
  Result := FileName <> '';
end;

end.
