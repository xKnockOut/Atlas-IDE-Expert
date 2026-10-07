unit BDLsp.Common.Pascal.Contract;

// Contract des Platform-Features Pascal: Token des Lexers für Object Pascal.
// Positionen wie im LSP: Zeile und Spalte ab 0, Spalte in UTF-16-Codeeinheiten.

interface

{$SCOPEDENUMS ON}

uses
  BDLsp.Common.Documents.Contract;

type
  TPascalTokenKind = (
    /// <summary>Bezeichner, auch mit &amp;-Escape (&amp;begin).</summary>
    Identifier,
    /// <summary>Reserviertes Wort wie begin, class, procedure.</summary>
    Keyword,
    /// <summary>Zahl: dezimal, Gleitkomma, $-Hex oder %-Binär.</summary>
    Number,
    /// <summary>String in Hochkommas, auch mehrzeilig mit '''.</summary>
    StringLiteral,
    /// <summary>Zeichenkonstante wie #13 oder #$0D.</summary>
    CharLiteral,
    /// <summary>Kommentar mit //, { } oder (* *).</summary>
    Comment,
    /// <summary>Compiler-Direktive {$...} oder (*$...*).</summary>
    Directive,
    /// <summary>Operator oder Satzzeichen, z. B. := .. ; ( ).</summary>
    Symbol,
    /// <summary>Zeichen, das in Object Pascal nicht vorkommt.</summary>
    Unknown);

  TPascalToken = record
    Kind: TPascalTokenKind;
    /// <summary>Quelltext des Tokens, unverändert.</summary>
    Text: string;
    /// <summary>Offset ab 0 im Dokument.</summary>
    Offset: Integer;
    StartPos: TTextPosition;
    /// <summary>Position hinter dem letzten Zeichen.</summary>
    EndPos: TTextPosition;
    /// <summary>False bei String, Kommentar oder Direktive ohne Abschluss (unvollständiger Code).</summary>
    Terminated: Boolean;
    /// <summary>Für Keyword: Wort in Kleinbuchstaben vergleichen, z. B. IsKeyword('begin').</summary>
    function IsKeyword(const AWord: string): Boolean;
    /// <summary>Für Symbol: z. B. IsSymbol(':=').</summary>
    function IsSymbol(const ASymbol: string): Boolean;
  end;

implementation

uses
  System.SysUtils;

{ TPascalToken }

function TPascalToken.IsKeyword(const AWord: string): Boolean;
begin
  Result := (Kind = TPascalTokenKind.Keyword) and SameText(Text, AWord);
end;

function TPascalToken.IsSymbol(const ASymbol: string): Boolean;
begin
  Result := (Kind = TPascalTokenKind.Symbol) and (Text = ASymbol);
end;

end.
