unit Atlas.Tests.SymbolIndex;

// Testhilfe: Symbolindex aus Quelltexten im Speicher.

interface

uses
  Atlas.Common.Index.Contract;

type
  TTestIndex = record
  public
    /// <summary>Index mit den Units AUnits als Paare aus Quelltext und Dateiname.</summary>
    class function Build(const AUnits: array of string): ISymbolIndex; static;
  end;

implementation

uses
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

{ TTestIndex }

class function TTestIndex.Build(const AUnits: array of string): ISymbolIndex;
var
  mIndex: Integer;
begin
  Result := TSymbolIndex.Create;
  mIndex := 0;
  while mIndex < High(AUnits) do
  begin
    Result.AddUnit(TIndexExtractor.ExtractText(AUnits[mIndex], AUnits[mIndex + 1], nil));
    Inc(mIndex, 2);
  end;
end;

end.
