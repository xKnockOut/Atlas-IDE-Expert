unit Atlas.Common.Mcp.Freshness;

// Aktueller Index im MCP-Modus (#48): Der MCP-Prozess hat keinen Editor, der
// Änderungen meldet, und KI-Assistenten ändern laufend Dateien. Vor jedem
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
  mFileName: string;
  mUnitIndex: TUnitIndex;
  mStamp: Int64;
  mIndexed, mExists: Boolean;
begin
  Result := nil;
  for mFileName in AFiles do
  begin
    mIndexed := AIndex.FindFile(mFileName, mUnitIndex);
    mExists := AFileSystem.FileStamp(mFileName, mStamp);
    if mIndexed and not mExists then
    begin
      Result := Result + [TFileChange.Create(mFileName, TFileChangeKind.Deleted)];
    end
    else if mIndexed and (mStamp <> mUnitIndex.Stamp) then
    begin
      Result := Result + [TFileChange.Create(mFileName, TFileChangeKind.Changed)];
    end
    else if not mIndexed and mExists then
    begin
      Result := Result + [TFileChange.Create(mFileName, TFileChangeKind.Created)];
    end;
  end;
end;

end.