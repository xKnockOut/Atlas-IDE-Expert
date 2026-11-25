unit Atlas.Core.Editor.LineItems;

// Einträge, die an einer Zeile des Editors hängen (Kennzahlen einer Methode, Marke „getestet von“), ohne VCL und
// Open Tools API: den Eintrag einer Zeile finden. Die Linsen über den Methodenköpfen nutzen diese eine Fassung.

interface

uses
  System.SysUtils;

type
  TAtlasLineItems = class
  public
    /// <summary>Index des ersten Eintrags von AItems, dessen Zeile (über ALineOf) ALine ist; -1 ohne.</summary>
    class function IndexAt<T>(const AItems: TArray<T>; ALine: Integer; const ALineOf: TFunc<T, Integer>): Integer;
      static;
  end;

implementation

{ TAtlasLineItems }

class function TAtlasLineItems.IndexAt<T>(const AItems: TArray<T>; ALine: Integer;
  const ALineOf: TFunc<T, Integer>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if ALineOf(AItems[mIndex]) = ALine then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

end.
