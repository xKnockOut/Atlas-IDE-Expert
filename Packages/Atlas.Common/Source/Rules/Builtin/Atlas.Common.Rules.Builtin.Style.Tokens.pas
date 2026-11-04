unit Atlas.Common.Rules.Builtin.Style.Tokens;

// Gemeinsame Tokenhilfen der Stilregeln (Style, Style.BeginEnd): Code-Token vor und nach einer Stelle suchen und
// den Bereich einer Tokenfolge bilden.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TTokens = TArray<TPascalToken>;

/// <summary>Kommentar oder Compileranweisung?</summary>
function IsTrivia(const AToken: TPascalToken): Boolean;
/// <summary>Erstes Code-Token ab AIndex (AIndex eingeschlossen); High + 1 ohne.</summary>
function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
/// <summary>Letztes Code-Token vor AIndex (AIndex selbst ausgeschlossen); -1 ohne.</summary>
function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
/// <summary>Bereich vom Anfang des Tokens AFirst bis zum Ende des Tokens ALast.</summary>
function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;

implementation

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

end.
