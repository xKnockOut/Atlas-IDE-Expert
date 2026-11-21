unit Atlas.Common.Architecture.TestSupport;

// Gemeinsame Hilfen der Architekturtests.

interface

uses
  Atlas.Common.Architecture.UsesLocator;

/// <summary>Bedingungssymbole: für jede Datei keine.</summary>
function NoDefines: TUsesDefinesFunc;

implementation

function NoDefines: TUsesDefinesFunc;
begin
  Result :=
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end;
end;

end.
