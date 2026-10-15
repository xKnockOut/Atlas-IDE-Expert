unit Atlas.Common.Todos.Contract;

// Contract des Platform-Features Todos (#68): TODO-Einträge aus Kommentaren.
// Erkannt wird ein Kommentar, dessen erstes Wort eine Marke ist (Vorgabe
// TODO und FIXME, Groß-/Kleinschreibung egal) oder DONE, in jeder
// Kommentarform (//, { }, (* *)):
//   // TODO Text
//   // FIXME: Text
//   { TODO 1 -oName -cKategorie : Text }     Format der To-Do-Liste der IDE
//   { DONE 2 -oName -cKategorie : Text }     erledigt
//   // TODO 1 -oName -cKategorie : Text      dasselbe Format im Zeilenkommentar (#474)
// Priorität (Zahl), Person (-o) und Kategorie (-c) sind freiwillig; Werte
// mit Leerzeichen dürfen in ' oder " stehen. DONE-Einträge sind erledigt und
// in Liste und Bericht standardmäßig ausgeblendet (TTodoFilter.IncludeDone).
// Die Marken stellt die Option "keywords" der Regel todo-comment ein
// (Atlas.Common.Rules.Builtin.Todos).

interface

uses
  Atlas.Common.Documents.Contract;

type
  /// <summary>Ein TODO-Eintrag in einem Kommentar.</summary>
  TTodoEntry = record
    /// <summary>Marke in Großbuchstaben: TODO, FIXME, eine eigene Marke oder DONE.</summary>
    Keyword: string;
    /// <summary>True für DONE (erledigt).</summary>
    Done: Boolean;
    /// <summary>Priorität aus dem IDE-Format; 0 = keine.</summary>
    Priority: Integer;
    /// <summary>Person aus -o; '' = keine.</summary>
    Owner: string;
    /// <summary>Kategorie aus -c; '' = keine.</summary>
    Category: string;
    /// <summary>Text nach dem Doppelpunkt bzw. nach Marke und Optionen, Leerraum zusammengefasst.</summary>
    Text: string;
    /// <summary>Ganzer Kommentar (Zeilen und Spalten ab 0).</summary>
    Range: TTextRange;
  end;

  /// <summary>TODO-Einträge einer Datei.</summary>
  TFileTodos = record
    /// <summary>Pfad für Bericht und JSON (relativ zur Wurzel mit „/“, sonst wie übergeben).</summary>
    Path: string;
    /// <summary>Unit-Name (Dateiname ohne Endung).</summary>
    UnitName: string;
    Entries: TArray<TTodoEntry>;
    constructor Create(const APath: string; const AEntries: TArray<TTodoEntry>);
  end;

  /// <summary>Auswahl für Liste, Bericht und MCP; leere Felder schränken nicht ein.</summary>
  TTodoFilter = record
    /// <summary>Kategorie (Groß-/Kleinschreibung egal).</summary>
    Category: string;
    /// <summary>Person (Groß-/Kleinschreibung egal).</summary>
    Owner: string;
    /// <summary>Unit-Name oder Pfad der Datei (Groß-/Kleinschreibung egal).</summary>
    UnitName: string;
    /// <summary>Marke, z. B. FIXME.</summary>
    Keyword: string;
    /// <summary>Auch erledigte Einträge (DONE); Vorgabe aus.</summary>
    IncludeDone: Boolean;
    /// <summary>Keine Einschränkung, DONE ausgeblendet.</summary>
    class function Default: TTodoFilter; static;
    /// <summary>Keine Einschränkung, DONE eingeschlossen (für die Zusammenfassung).</summary>
    class function All: TTodoFilter; static;
    function Matches(const AFile: TFileTodos; const AEntry: TTodoEntry): Boolean;
  end;

  TTodos = class
  public const
    /// <summary>Marke erledigter Einträge (IDE-Format).</summary>
    DoneKeyword = 'DONE';
  public
    /// <summary>TODO und FIXME.</summary>
    class function DefaultKeywords: TArray<string>; static;
    /// <summary>Dateiname ohne Ordner und Endung; Pfade mit „/“ oder „\“.</summary>
    class function UnitNameOf(const APath: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TFileTodos }

constructor TFileTodos.Create(const APath: string; const AEntries: TArray<TTodoEntry>);
begin
  Path := APath;
  UnitName := TTodos.UnitNameOf(APath);
  Entries := AEntries;
end;

{ TTodoFilter }

class function TTodoFilter.Default: TTodoFilter;
begin
  Result.Category := '';
  Result.Owner := '';
  Result.UnitName := '';
  Result.Keyword := '';
  Result.IncludeDone := False;
end;

class function TTodoFilter.All: TTodoFilter;
begin
  Result := Default;
  Result.IncludeDone := True;
end;

function TTodoFilter.Matches(const AFile: TFileTodos; const AEntry: TTodoEntry): Boolean;
begin
  Result := False;
  if AEntry.Done and not IncludeDone then
    Exit;
  if (Category <> '') and not SameText(Category, AEntry.Category) then
    Exit;
  if (Owner <> '') and not SameText(Owner, AEntry.Owner) then
    Exit;
  if (Keyword <> '') and not SameText(Keyword, AEntry.Keyword) then
    Exit;
  if (UnitName <> '') and not SameText(UnitName, AFile.UnitName) and not SameText(UnitName, AFile.Path) and
    not SameText(StringReplace(UnitName, '\', '/', [rfReplaceAll]), AFile.Path) then
    Exit;
  Result := True;
end;

{ TTodos }

class function TTodos.DefaultKeywords: TArray<string>;
begin
  Result := ['TODO', 'FIXME'];
end;

class function TTodos.UnitNameOf(const APath: string): string;
var
  Index: Integer;
begin
  Result := APath;
  for Index := Length(Result) downto 1 do
    if (Result[Index] = '/') or (Result[Index] = '\') then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  Index := LastDelimiter('.', Result);
  if Index > 1 then
    Result := Copy(Result, 1, Index - 1);
end;

end.
