unit Atlas.Common.Pascal.Contract;

// Contract des Platform-Features Pascal: Token des Lexers für Object Pascal.
// Positionen wie im LSP: Zeile und Spalte ab 0, Spalte in UTF-16-Codeeinheiten.
// Außerdem die Präfixe neuer Namen (#1111): Korrekturen und Refactorings, die
// Bezeichner erzeugen (Konstante einführen, Variable einführen, with auflösen,
// Methode anlegen …), bilden sie mit dem Präfix ihrer Art, damit naming-prefix
// sie nicht gleich wieder meldet (NewConstant → cNewConstant). Welche Präfixe
// gelten, entscheidet die Regel (IRuleNewNames, TRuleEngine.NewNames); hier
// liegen Wertetyp und Namensbildung, damit Rules und Editing sie teilen.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract;

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
    /// <summary>False bei String, Kommentar oder Direktive ohne Abschluss (unvollständiger Code) und bei einer
    /// Zahl mit leerem Exponenten wie 1.5e (E2053).</summary>
    Terminated: Boolean;
    /// <summary>Für Keyword: Wort in Kleinbuchstaben vergleichen, z. B. IsKeyword('begin').</summary>
    function IsKeyword(const AWord: string): Boolean;
    /// <summary>Für Symbol: z. B. IsSymbol(':='). Die Ersatzklammern (. und .) gelten als [ und ] (#862).
    /// </summary>
    function IsSymbol(const ASymbol: string): Boolean;
  end;

  /// <summary>Präfixe neuer Namen je Art (lokale Variable, Feld, Parameter, Konstante); leer = ohne.</summary>
  TPascalNamePrefixes = record
    LocalPrefix: string;
    FieldPrefix: string;
    ParameterPrefix: string;
    ConstantPrefix: string;
    /// <summary>Ohne Präfixe: Namen bleiben, wie die Korrektur sie bildet.</summary>
    class function None: TPascalNamePrefixes; static;
    /// <summary>Trägt AName das Präfix APrefix? Bei einem Präfix, das auf einen Buchstaben endet, folgt ein
    /// Großbuchstabe oder eine Ziffer (mIndex, nicht menu). True für ein leeres Präfix.</summary>
    class function Follows(const AName, APrefix: string): Boolean; static;
    /// <summary>APrefix vor AName, dessen erster Buchstabe groß, wenn das Präfix auf einen Buchstaben endet
    /// (Index → mIndex, index → mIndex).</summary>
    class function Expected(const AName, APrefix: string): string; static;
    /// <summary>AName mit APrefix, außer er trägt es schon oder APrefix ist leer.</summary>
    class function WithPrefix(const AName, APrefix: string): string; static;
    function Local(const AName: string): string;
    function Field(const AName: string): string;
    function Parameter(const AName: string): string;
    function Constant(const AName: string): string;
  end;

  /// <summary>Abbruchsignal für lange Läufe, z. B. Parsen großer Dateien.</summary>
  IPascalCancellation = interface
    ['{4A7D2E91-6B3C-4F58-8E1A-C9D05B2F7E36}']
    function IsCancelled: Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TPascalToken }

function TPascalToken.IsKeyword(const AWord: string): Boolean;
begin
  Result := (Kind = TPascalTokenKind.Keyword) and SameText(Text, AWord);
end;

function TPascalToken.IsSymbol(const ASymbol: string): Boolean;
begin
  Result := (Kind = TPascalTokenKind.Symbol) and ((Text = ASymbol) or
    (ASymbol = '[') and (Text = '(.') or (ASymbol = ']') and (Text = '.)'));
end;


function IsLetter(ACh: Char): Boolean;
begin
  Result := AnsiUpperCase(ACh) <> AnsiLowerCase(ACh);
end;

function IsUpperOrDigit(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['0'..'9']) or (IsLetter(ACh) and (AnsiUpperCase(ACh) = ACh));
end;

{ TPascalNamePrefixes }

class function TPascalNamePrefixes.None: TPascalNamePrefixes;
begin
  Result.LocalPrefix := '';
  Result.FieldPrefix := '';
  Result.ParameterPrefix := '';
  Result.ConstantPrefix := '';
end;

class function TPascalNamePrefixes.Follows(const AName, APrefix: string): Boolean;
begin
  if APrefix = '' then
    Exit(True);
  if (Length(AName) <= Length(APrefix)) or not StartsStr(APrefix, AName) then
    Exit(False);
  Result := not IsLetter(APrefix[Length(APrefix)]) or IsUpperOrDigit(AName[Length(APrefix) + 1]);
end;

class function TPascalNamePrefixes.Expected(const AName, APrefix: string): string;
begin
  if (APrefix <> '') and IsLetter(APrefix[Length(APrefix)]) and (AName <> '') then
    Result := APrefix + AnsiUpperCase(AName[1]) + Copy(AName, 2, MaxInt)
  else
    Result := APrefix + AName;
end;

class function TPascalNamePrefixes.WithPrefix(const AName, APrefix: string): string;
begin
  if Follows(AName, APrefix) then
    Result := AName
  else
    Result := Expected(AName, APrefix);
end;

function TPascalNamePrefixes.Local(const AName: string): string;
begin
  Result := WithPrefix(AName, LocalPrefix);
end;

function TPascalNamePrefixes.Field(const AName: string): string;
begin
  Result := WithPrefix(AName, FieldPrefix);
end;

function TPascalNamePrefixes.Parameter(const AName: string): string;
begin
  Result := WithPrefix(AName, ParameterPrefix);
end;

function TPascalNamePrefixes.Constant(const AName: string): string;
begin
  Result := WithPrefix(AName, ConstantPrefix);
end;

end.
