unit Atlas.Common.Rules.Builtin.Style.Tokens;

// Gemeinsame Tokenhilfen der Stilregeln (Style, Style.BeginEnd): Bereich einer Tokenfolge. Code-Token und
// Klammern sucht Atlas.Common.Pascal.TokenCursor.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TTokens = TArray<TPascalToken>;

/// <summary>Bereich vom Anfang des Tokens AFirst bis zum Ende des Tokens ALast.</summary>
function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;

implementation

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

end.
