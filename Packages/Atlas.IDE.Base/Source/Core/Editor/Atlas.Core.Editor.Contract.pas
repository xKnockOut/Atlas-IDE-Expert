unit Atlas.Core.Editor.Contract;

// Contract des Plugin-Features Editor (#1443): Marken der Übersichtsleiste (#1104),
// Ersetzungen im Text und die Schnittstellen zum Editorpuffer (IAtlasEditSurface), zur
// Umgebung des Planers von Arbeitsbereichsänderungen (IAtlasEditEnvironment) und zu eigenen
// Lesezeichen eines Moduls (#1455). Die Root-Units des Features führen die Typen als Alias
// weiter.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Core.Files.Contract;

type
  /// <summary>Art einer Marke; die Reihenfolge ist zugleich die Zeichenreihenfolge (spätere liegen oben).</summary>
  TAtlasOverviewMarkKind = (Cursor, Added, Modified, Deleted, Search, Bookmark, Breakpoint, Info, Warning, Error);

  TAtlasOverviewMark = record
    Kind: TAtlasOverviewMarkKind;
    Line: Integer;
    /// <summary>Zeilen ab Line (mindestens 1).</summary>
    Count: Integer;
    /// <summary>Beschreibung für die Vorschau (etwa die Meldung); '' ohne.</summary>
    Text: string;
    class function Create(AKind: TAtlasOverviewMarkKind; ALine, ACount: Integer): TAtlasOverviewMark; overload; static;
    class function Create(AKind: TAtlasOverviewMarkKind; ALine, ACount: Integer;
      const AText: string): TAtlasOverviewMark; overload; static;
    /// <summary>Indizes der Marken von AKind in AMarks, nach Zeile sortiert (bei gleicher Zeile in Eingabefolge).
    /// </summary>
    class function IndexesOfKind(const AMarks: TArray<TAtlasOverviewMark>;
      AKind: TAtlasOverviewMarkKind): TArray<Integer>; static;
  end;

  TAtlasOverviewMarks = TArray<TAtlasOverviewMark>;

  /// <summary>Eigene Lesezeichen eines Moduls für die Übersichtsleiste (#1104, #1455): Das Modul stellt die Quelle
  /// über seinen Scope bereit; die Leiste fragt bei jedem Sammeln die Registry. Nur im Hauptthread.</summary>
  IAtlasOverviewBookmarks = interface
    ['{CF205299-AA82-4210-8294-D1E4064066BA}']
    /// <summary>Lesezeichen für AFileName; False: keine eigenen, die Leiste zeigt die der IDE.</summary>
    function Marks(const AFileName: string; out AMarks: TAtlasOverviewMarks): Boolean;
  end;

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

  /// <summary>Was der Planer über Dateien und Projekte wissen muss; in der IDE TAtlasIdeEditEnvironment.</summary>
  IAtlasEditEnvironment = interface
    ['{7A9F35E4-0FD4-4DD2-9F8D-1B75CDA6E1C1}']
    /// <summary>Datei auf der Platte oder offener Puffer.</summary>
    function Exists(const AFileName: string): Boolean;
    function IsDirectory(const AFileName: string): Boolean;
    /// <summary>Wie IAtlasUndoTarget.Read: Puffer, Designer oder Platte; False, wenn sie fehlt.</summary>
    function Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
    /// <summary>Kodierung der Datei auf der Platte (Text leer); UTF-8 mit BOM, wenn sie fehlt.</summary>
    function DiskEncoding(const AFileName: string): TAtlasTextFileContent;
    /// <summary>Projektdatei des Projekts, das AFileName enthält; '' wenn keins.</summary>
    function ProjectOfFile(const AFileName: string): string;
    /// <summary>Aktives Projekt für eine neue Unit; '' wenn keins passt.</summary>
    function ProjectForNewFile(const AFileName: string): string;
    /// <summary>Ist die Projektdatei in der IDE geladen?</summary>
    function ProjectLoaded(const AProjectFile: string): Boolean;
  end;

implementation

uses
  System.Math;

{ TAtlasOverviewMark }

class function TAtlasOverviewMark.Create(AKind: TAtlasOverviewMarkKind; ALine, ACount: Integer): TAtlasOverviewMark;
begin
  Result := Create(AKind, ALine, ACount, '');
end;

class function TAtlasOverviewMark.Create(AKind: TAtlasOverviewMarkKind; ALine, ACount: Integer;
  const AText: string): TAtlasOverviewMark;
begin
  Result.Kind := AKind;
  Result.Line := Max(0, ALine);
  Result.Count := Max(1, ACount);
  Result.Text := AText;
end;

/// <summary>Marken der Art AKind nach Zeile (Einfügen; die Listen sind meist schon sortiert).</summary>
class function TAtlasOverviewMark.IndexesOfKind(const AMarks: TArray<TAtlasOverviewMark>;
  AKind: TAtlasOverviewMarkKind): TArray<Integer>;
var
  mIndex, mPosition, mMoved: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AMarks) do
  begin
    if AMarks[mIndex].Kind = AKind then
    begin
      Result := Result + [mIndex];
      mPosition := High(Result);
      while (mPosition > 0) and (AMarks[Result[mPosition - 1]].Line > AMarks[mIndex].Line) do
      begin
        mMoved := Result[mPosition - 1];
        Result[mPosition - 1] := Result[mPosition];
        Result[mPosition] := mMoved;
        Dec(mPosition);
      end;
    end;
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
