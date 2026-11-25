unit Atlas.Core.Outline.TestSupport;

// Gemeinsame Hilfen der Gliederungs-Tests (Atlas.Core.Outline.*.Tests, Brotkrumen, Gliederungsfenster):
// Knoten eines Quelltexts und Suche darin.

interface

uses
  Atlas.Core.Outline.Model;

type
  TOutlineTest = record
  public
    /// <summary>Gliederungsknoten von ACode, wie sie der Server über documentSymbol liefert.</summary>
    class function NodesOf(const ACode: string): TAtlasOutlineNodes; static;
    /// <summary>Index des ersten Knotens namens AName, -1 ohne Treffer.</summary>
    class function Find(const ANodes: TAtlasOutlineNodes; const AName: string): Integer; static;
    /// <summary>Index des Knotens namens AName, dessen Name in Zeile ALine steht, -1 ohne Treffer.</summary>
    class function NodeAt(const ANodes: TAtlasOutlineNodes; const AName: string; ALine: Integer): Integer; static;
    /// <summary>Namen der Knoten AItems, mit Komma getrennt.</summary>
    class function NamesOf(const ANodes: TAtlasOutlineNodes; const AItems: TArray<Integer>): string; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.DocumentSymbols;

{ TOutlineTest }

class function TOutlineTest.NodesOf(const ACode: string): TAtlasOutlineNodes;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TSyntaxTreeCache.Parse(ACode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, ACode);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

class function TOutlineTest.Find(const ANodes: TAtlasOutlineNodes; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if ANodes[mIndex].Name = AName then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TOutlineTest.NodeAt(const ANodes: TAtlasOutlineNodes; const AName: string; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if (ANodes[mIndex].Name = AName) and (ANodes[mIndex].NameLine = ALine) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TOutlineTest.NamesOf(const ANodes: TAtlasOutlineNodes; const AItems: TArray<Integer>): string;
var
  mItem: Integer;
begin
  Result := '';
  for mItem in AItems do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + ANodes[mItem].Name;
  end;
end;

end.
