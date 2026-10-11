unit Atlas.Common.Mcp.Freshness;

// Aktueller Index im MCP-Modus (#48): Der MCP-Prozess hat keinen Editor, der
// Änderungen meldet, und Claude Code ändert laufend Dateien. Vor jedem
// Werkzeugaufruf vergleicht Atlas deshalb die Zeitstempel der Projektdateien
// mit dem Stand im Index; geänderte, neue und gelöschte gehen als
// Dateiänderungen an den Index (wie didChangeWatchedFiles).

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  TMcpFreshness = class
  public
    /// <summary>Änderungen an AFiles gegenüber dem Index; leer, wenn alles aktuell ist.</summary>
    class function Changes(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
      const AFiles: TArray<string>): TArray<TFileChange>; static;
  end;

implementation

class function TMcpFreshness.Changes(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
  const AFiles: TArray<string>): TArray<TFileChange>;
var
  FileName: string;
  UnitIndex: TUnitIndex;
  Stamp: Int64;
  Indexed, Exists: Boolean;
begin
  Result := nil;
  for FileName in AFiles do
  begin
    Indexed := AIndex.FindFile(FileName, UnitIndex);
    Exists := AFileSystem.FileStamp(FileName, Stamp);
    if Indexed and not Exists then
      Result := Result + [TFileChange.Create(FileName, TFileChangeKind.Deleted)]
    else if Indexed and (Stamp <> UnitIndex.Stamp) then
      Result := Result + [TFileChange.Create(FileName, TFileChangeKind.Changed)]
    else if not Indexed and Exists then
      Result := Result + [TFileChange.Create(FileName, TFileChangeKind.Created)];
  end;
end;

end.