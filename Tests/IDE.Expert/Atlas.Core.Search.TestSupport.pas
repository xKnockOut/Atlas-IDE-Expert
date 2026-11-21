unit Atlas.Core.Search.TestSupport;

// Gemeinsame Hilfen der Such-Tests (Atlas.Core.Search.*.Tests).

interface

uses
  Atlas.Core.Search.Matching;

/// <summary>"Zeile:Zeichen+Länge" je Treffer, durch Leerzeichen getrennt.</summary>
function Describe(const AHits: TArray<TAtlasSearchHit>): string;

implementation

uses
  System.SysUtils;

function Describe(const AHits: TArray<TAtlasSearchHit>): string;
var
  mHit: TAtlasSearchHit;
begin
  Result := '';
  for mHit in AHits do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + Format('%d:%d+%d', [mHit.Line, mHit.Character, mHit.Length]);
  end;
end;

end.
