unit Atlas.Common.Pascal.MethodText;

// Textbausteine für Methodenköpfe, die die Zuordnung von Deklarationen und Rümpfen, die Klassenvervollständigung
// und die Prüfregeln zu Deklarationen gemeinsam brauchen: Bereichstext, Direktiven, Aufrufkonvention, Token an
// einer Position.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract;

type
  /// <summary>Textbausteine für Methodenköpfe.</summary>
  TMethodText = class
  public const
    cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.HelperType];
    cMethodKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];
  public
    class function ContainsLine(const ARange: TTextRange; ALine: Integer): Boolean; static;
    /// <summary>Steht das Wort AWord als Bezeichner oder reserviertes Wort in AText? Kommentare und Strings
    /// zählen nicht (procedure Redo; virtual; {abstract;} ist nicht abstrakt).</summary>
    class function HasWord(const AText, AWord: string): Boolean; static;
    /// <summary>Ist AWord eine Aufrufkonvention (register, stdcall …)?</summary>
    class function IsConvention(const AWord: string): Boolean; static;
    /// <summary>Ist AWord eine Direktive hinter einem Methodenkopf (overload, virtual …)?</summary>
    class function IsDirective(const AWord: string): Boolean; static;
    /// <summary>Aufrufkonvention aus den Direktiven hinter dem Kopf ("overload; stdcall; …"); '' ohne.</summary>
    class function ConventionOfRest(const ARest: string): string; static;
    /// <summary>Weicht die ausdrücklich angegebene Konvention des Rumpfs von der Deklaration ab?</summary>
    class function ConventionDiffers(const ABody, ADeclaration: string): Boolean; static;
    /// <summary>Index des Tokens, das an APosition endet; -1 ohne. Binäre Suche: Die Token sind nach ihrer Lage
    /// geordnet.</summary>
    class function TokenEndingAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
      static;
    /// <summary>Index des Tokens, das an APosition beginnt; -1 ohne. Binäre Suche wie TokenEndingAt.</summary>
    class function TokenStartingAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.RoutineSignatures;

const
  cConventions: array[0..5] of string = ('register', 'pascal', 'cdecl', 'stdcall', 'safecall', 'winapi');
  cDirectives: array[0..20] of string = ('overload', 'inline', 'static', 'virtual', 'dynamic', 'override',
    'abstract', 'reintroduce', 'final', 'message', 'deprecated', 'platform', 'experimental', 'library', 'assembler',
    'varargs', 'external', 'forward', 'unsafe', 'dispid', 'export');

{ TMethodText }

class function TMethodText.ContainsLine(const ARange: TTextRange; ALine: Integer): Boolean;
begin
  Result := (ALine >= ARange.StartPos.Line) and (ALine <= ARange.EndPos.Line);
end;

class function TMethodText.HasWord(const AText, AWord: string): Boolean;
var
  mToken: TPascalToken;
begin
  if not ContainsText(AText, AWord) then
  begin
    Exit(False);
  end;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if (mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(mToken.Text, AWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TMethodText.IsConvention(const AWord: string): Boolean;
begin
  Result := MatchText(AWord, cConventions);
end;

class function TMethodText.IsDirective(const AWord: string): Boolean;
begin
  Result := MatchText(AWord, cDirectives);
end;

class function TMethodText.ConventionOfRest(const ARest: string): string;
var
  mPart, mWord: string;
  mSpace: Integer;
begin
  Result := '';
  for mPart in TRoutineSignatures.SplitTopLevel(ARest, ';') do
  begin
    mWord := LowerCase(Trim(mPart));
    mSpace := Pos(' ', mWord);
    if mSpace > 0 then
    begin
      mWord := Copy(mWord, 1, mSpace - 1);
    end;
    if IsConvention(mWord) then
    begin
      Exit(mWord);
    end;
    if not IsDirective(mWord) then
    begin
      Exit;
    end;
  end;
end;

class function TMethodText.ConventionDiffers(const ABody, ADeclaration: string): Boolean;
var
  mDeclaration: string;
begin
  mDeclaration := ADeclaration;
  if mDeclaration = '' then
  begin
    mDeclaration := 'register';
  end;
  Result := (ABody <> '') and (ABody <> mDeclaration);
end;

/// <summary>Lage als eine Zahl in Textreihenfolge (Zeile vor Spalte) für die binäre Suche.</summary>
function PositionKey(const APosition: TTextPosition): Int64;
begin
  Result := Int64(APosition.Line) * (Int64(High(Integer)) + 1) + APosition.Character;
end;

class function TMethodText.TokenEndingAt(const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition): Integer;
var
  mLow, mHigh, mMiddle: Integer;
  mKey: Int64;
begin
  mLow := 0;
  mHigh := High(ATokens);
  mKey := PositionKey(APosition);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if PositionKey(ATokens[mMiddle].EndPos) < mKey then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle - 1;
    end;
  end;
  // mLow ist das erste Token, das nicht vor APosition endet; leere Token davor teilen sich das Ende nicht.
  Result := -1;
  if (mLow <= High(ATokens)) and (ATokens[mLow].EndPos = APosition) then
  begin
    Result := mLow;
  end;
end;

class function TMethodText.TokenStartingAt(const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition): Integer;
var
  mLow, mHigh, mMiddle: Integer;
  mKey: Int64;
begin
  mLow := 0;
  mHigh := High(ATokens);
  mKey := PositionKey(APosition);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if PositionKey(ATokens[mMiddle].StartPos) < mKey then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle - 1;
    end;
  end;
  Result := -1;
  if (mLow <= High(ATokens)) and (ATokens[mLow].StartPos = APosition) then
  begin
    Result := mLow;
  end;
end;

end.
