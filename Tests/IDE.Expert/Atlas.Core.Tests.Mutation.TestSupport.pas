unit Atlas.Core.Tests.Mutation.TestSupport;

// Gemeinsame Hilfen der Tests der Mutationstests (Mutanten, Plan).

interface

/// <summary>Kleine Unit Preise mit Bedingung und Rechnung als Zeilen.</summary>
function SampleLines: TArray<string>;

implementation

function SampleLines: TArray<string>;
begin
  Result := TArray<string>.Create('unit Preise;', 'interface', 'implementation',
    'function Satz(AMenge: Integer): Integer;', 'begin', '  if AMenge >= 100 then', '    Result := 10',
    '  else', '    Result := 0;', 'end;', 'function Doppelt(A: Integer): Integer;', 'begin',
    '  Result := A + A;', 'end;', 'end.');
end;

end.
