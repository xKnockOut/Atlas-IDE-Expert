unit Atlas.Common.Editing.MethodMatching;

// Zuordnung von Methodendeklarationen und Rümpfen einer Datei (#42, #660) für
// TClassCompletion: je Typ die deklarierten Methoden, die Rümpfe und welcher
// Rumpf zu welcher Deklaration gehört.
//
// Gebaut wird einmal je Datei und ohne Suchläufe je Methode (#1477): Methoden
// je Typ, Typen je Name, Rümpfe je Schlüssel und die Zeilen innerhalb von
// Typen stehen in Tabellen. Vorher wuchs die Zeit mit Typen mal Symbolen bzw.
// Methoden mal Rümpfen; eine Unit wie System.Classes brauchte Minuten.
//
// TMethodText enthält die Textbausteine, die Zuordnung und Klassenvervoll-
// ständigung gemeinsam brauchen (Bereichstext, Direktiven, Aufrufkonvention,
// Token an einer Position).

interface

uses
  System.Generics.Collections,
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
    /// <summary>Text von ARange bis zum Ende seiner letzten Zeile, Zeilen mit Leerzeichen verbunden.</summary>
    class function RangeText(const ALines: TArray<string>; const ARange: TTextRange): string; static;
    /// <summary>Steht das Wort AWord als Bezeichner oder reserviertes Wort in AText? Kommentare und Strings
    /// zählen nicht (procedure Redo; virtual; {abstract;} ist nicht abstrakt).</summary>
    class function HasWord(const AText, AWord: string): Boolean; static;
    /// <summary>Name des Typs ASymbol mit umgebendem Typ (TAussen.TInnen).</summary>
    class function TypeNameOf(const ASymbol: TIndexSymbol): string; static;
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

  /// <summary>Zuordnung von Deklarationen und Rümpfen eines Typs.</summary>
  TTypeMethodMatch = record
    TypeName: string;
    Declarations: TArray<TIndexSymbol>;
    DeclarationHeaders: TArray<string>;
    /// <summary>Rumpf je Deklaration als Index in Bodies; -1 ohne Rumpf, -2 übergangen (abstract, external,
    /// forward).</summary>
    BodyOf: TArray<Integer>;
    Bodies: TArray<TIndexSymbol>;
    BodyHeaders: TArray<string>;
    BodyUsed: TArray<Boolean>;
  end;

  /// <summary>Ordnet die Methoden der Typen einer Datei ihren Rümpfen zu; generische Typen fehlen.</summary>
  TMethodMatching = class
  private
    FLines: TArray<string>;
    FUnit: TUnitIndex;
    /// <summary>Indizes der Typen in FUnit.Symbols, in ihrer Reihenfolge.</summary>
    FTypes: TList<Integer>;
    /// <summary>Typname (klein, mit umgebendem Typ) → Indizes der Typen.</summary>
    FTypesByName: TObjectDictionary<string, TList<Integer>>;
    /// <summary>Container (klein) → Indizes der Methoden mit diesem Container.</summary>
    FMethods: TObjectDictionary<string, TList<Integer>>;
    /// <summary>Je Zeile: steht sie in irgendeinem Typ der Datei?</summary>
    FInType: TArray<Boolean>;
    FMatches: TArray<TTypeMethodMatch>;
    FMatched: Boolean;
    /// <summary>Schlüssel → Rümpfe des gerade zugeordneten Typs (Index in Bodies).</summary>
    FBodySlots: TObjectDictionary<string, TList<Integer>>;
    FBodyConventions: TArray<string>;
    procedure AddTo(ATable: TObjectDictionary<string, TList<Integer>>; const AKey: string; AIndex: Integer);
    procedure IndexSymbols;
    function InAnyType(ALine: Integer): Boolean;
    function IsGeneric(const AType: TIndexSymbol): Boolean;
    function IsGenericOuter(const AType: TIndexSymbol; const AName: string): Boolean;
    function TypeMask(const AType: TIndexSymbol): string;
    function FreeBody(const AMatch: TTypeMethodMatch; const AKey: string): Integer;
    procedure AddBody(var AMatch: TTypeMethodMatch; ABody: Integer; const ASymbol: TIndexSymbol;
      const AHeader, ARest: string);
    procedure CollectMembers(const AType: TIndexSymbol; var AMatch: TTypeMethodMatch);
    function BodyFor(var AMatch: TTypeMethodMatch; ADeclaration: Integer): Integer;
    function MatchType(const AType: TIndexSymbol): TTypeMethodMatch;
    procedure MatchAll;
    function GetMatches: TArray<TTypeMethodMatch>;
  public
    /// <summary>Zuordnung über die Zeilen ALines und den Index AUnit derselben Datei.</summary>
    constructor Create(const ALines: TArray<string>; const AUnit: TUnitIndex);
    destructor Destroy; override;
    /// <summary>Erster Typ namens ATypeName ("TAussen.TInnen") in Symbolreihenfolge; False ohne.</summary>
    function FindType(const ATypeName: string; out AType: TIndexSymbol): Boolean;
    /// <summary>Indizes der Methoden mit Container ATypeName in Symbolreihenfolge (Deklarationen und Rümpfe).
    /// </summary>
    function MethodsOf(const ATypeName: string): TArray<Integer>;
    /// <summary>Indizes aller Typen in Symbolreihenfolge.</summary>
    function TypeIndexes: TArray<Integer>;
    property Lines: TArray<string> read FLines;
    property UnitIndex: TUnitIndex read FUnit;
    /// <summary>Je Typ der Datei (in ihrer Reihenfolge, ohne generische) Deklarationen und Rümpfe; beim ersten
    /// Zugriff zugeordnet.</summary>
    property Matches: TArray<TTypeMethodMatch> read GetMatches;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
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

class function TMethodText.RangeText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (mLine < 0) or (mLine > High(ALines)) then
    begin
      Break;
    end;
    if mLine = ARange.StartPos.Line then
    begin
      Result := Copy(ALines[mLine], ARange.StartPos.Character + 1, MaxInt);
    end
    else
    begin
      Result := Result + ' ' + Trim(ALines[mLine]);
    end;
  end;
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

class function TMethodText.TypeNameOf(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.Container <> '' then
  begin
    Result := ASymbol.Container + '.' + ASymbol.Name;
  end
  else
  begin
    Result := ASymbol.Name;
  end;
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

/// <summary>-1, 0 oder 1, je nachdem ob A vor, auf oder hinter B liegt.</summary>
function ComparePositions(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

class function TMethodText.TokenEndingAt(const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition): Integer;
var
  mLow, mHigh, mMiddle, mOrder: Integer;
begin
  mLow := 0;
  mHigh := High(ATokens);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    mOrder := ComparePositions(ATokens[mMiddle].EndPos, APosition);
    if mOrder < 0 then
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
begin
  mLow := 0;
  mHigh := High(ATokens);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if ComparePositions(ATokens[mMiddle].StartPos, APosition) < 0 then
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

{ TMethodMatching }

constructor TMethodMatching.Create(const ALines: TArray<string>; const AUnit: TUnitIndex);
begin
  inherited Create;
  FLines := ALines;
  FUnit := AUnit;
  FTypes := TList<Integer>.Create;
  FTypesByName := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FMethods := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FBodySlots := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  IndexSymbols;
end;

destructor TMethodMatching.Destroy;
begin
  FBodySlots.Free;
  FMethods.Free;
  FTypesByName.Free;
  FTypes.Free;
  inherited Destroy;
end;

procedure TMethodMatching.AddTo(ATable: TObjectDictionary<string, TList<Integer>>; const AKey: string;
  AIndex: Integer);
var
  mList: TList<Integer>;
begin
  if not ATable.TryGetValue(AKey, mList) then
  begin
    mList := TList<Integer>.Create;
    ATable.Add(AKey, mList);
  end;
  mList.Add(AIndex);
end;

/// <summary>Typen, Methoden je Container und die Zeilen in Typen, einmal über alle Symbole.</summary>
procedure TMethodMatching.IndexSymbols;
var
  mIndex, mLine, mLast: Integer;
begin
  mLast := High(FLines);
  for mIndex := 0 to High(FUnit.Symbols) do
  begin
    if FUnit.Symbols[mIndex].Kind in TMethodText.cTypeKinds then
    begin
      mLast := Max(mLast, FUnit.Symbols[mIndex].Range.EndPos.Line);
    end;
  end;
  SetLength(FInType, mLast + 1);
  for mIndex := 0 to High(FUnit.Symbols) do
  begin
    if FUnit.Symbols[mIndex].Kind in TMethodText.cTypeKinds then
    begin
      FTypes.Add(mIndex);
      AddTo(FTypesByName, LowerCase(TMethodText.TypeNameOf(FUnit.Symbols[mIndex])), mIndex);
      for mLine := Max(0, FUnit.Symbols[mIndex].Range.StartPos.Line) to FUnit.Symbols[mIndex].Range.EndPos.Line do
      begin
        FInType[mLine] := True;
      end;
    end
    else if FUnit.Symbols[mIndex].Kind in TMethodText.cMethodKinds then
    begin
      AddTo(FMethods, LowerCase(FUnit.Symbols[mIndex].Container), mIndex);
    end;
  end;
end;

/// <summary>Steht ALine in irgendeinem Typ der Datei? Dann ist es eine Deklaration, kein Rumpf, auch wenn der Typ
/// ein gleichnamiger generischer ist (THashTable neben THashTable&lt;T&gt;, #1325).</summary>
function TMethodMatching.InAnyType(ALine: Integer): Boolean;
begin
  Result := (ALine >= 0) and (ALine <= High(FInType)) and FInType[ALine];
end;

/// <summary>Generisch ist ein Typ mit Typparametern; die kennt der Index nicht immer, dann steht "&lt;" hinter dem
/// Namen.</summary>
function TMethodMatching.IsGeneric(const AType: TIndexSymbol): Boolean;
var
  mRest: string;
begin
  mRest := '';
  if (AType.SelectionRange.EndPos.Line >= 0) and (AType.SelectionRange.EndPos.Line <= High(FLines)) then
  begin
    mRest := Copy(FLines[AType.SelectionRange.EndPos.Line], AType.SelectionRange.EndPos.Character + 1, MaxInt);
  end;
  Result := (AType.TypeParams <> '') or TrimLeft(mRest).StartsWith('<');
end;

/// <summary>Ist der Typ AName, der AType umschließt, generisch?</summary>
function TMethodMatching.IsGenericOuter(const AType: TIndexSymbol; const AName: string): Boolean;
var
  mList: TList<Integer>;
  mIndex: Integer;
begin
  if FTypesByName.TryGetValue(LowerCase(AName), mList) then
  begin
    for mIndex in mList do
    begin
      if TMethodText.ContainsLine(FUnit.Symbols[mIndex].Range, AType.Range.StartPos.Line) then
      begin
        Exit(IsGeneric(FUnit.Symbols[mIndex]));
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Maske wie TRoutineSignatures.QualifierMask für den Typ AType: je umschließendem Typ '1' oder '0',
/// zuletzt AType selbst ('0', generische Typen werden übergangen).</summary>
function TMethodMatching.TypeMask(const AType: TIndexSymbol): string;
var
  mParts: TArray<string>;
  mPrefix: string;
  mPart: Integer;
begin
  Result := '';
  mParts := TMethodText.TypeNameOf(AType).Split(['.']);
  mPrefix := '';
  for mPart := 0 to High(mParts) - 1 do
  begin
    if mPrefix <> '' then
    begin
      mPrefix := mPrefix + '.';
    end;
    mPrefix := mPrefix + mParts[mPart];
    if IsGenericOuter(AType, mPrefix) then
    begin
      Result := Result + '1';
    end
    else
    begin
      Result := Result + '0';
    end;
  end;
  Result := Result + '0';
end;

/// <summary>Erster noch freier Rumpf mit dem Schlüssel AKey; -1 ohne.</summary>
function TMethodMatching.FreeBody(const AMatch: TTypeMethodMatch; const AKey: string): Integer;
var
  mList: TList<Integer>;
  mCandidate: Integer;
begin
  if FBodySlots.TryGetValue(AKey, mList) then
  begin
    for mCandidate in mList do
    begin
      if not AMatch.BodyUsed[mCandidate] then
      begin
        Exit(mCandidate);
      end;
    end;
  end;
  Result := -1;
end;

procedure TMethodMatching.AddBody(var AMatch: TTypeMethodMatch; ABody: Integer; const ASymbol: TIndexSymbol;
  const AHeader, ARest: string);
begin
  AMatch.Bodies[ABody] := ASymbol;
  AMatch.BodyHeaders[ABody] := AHeader;
  AMatch.BodyUsed[ABody] := False;
  AddTo(FBodySlots, LowerCase(ASymbol.Name) + TRoutineSignatures.ParameterKey(AHeader) +
    TRoutineSignatures.ResultKey(AHeader), ABody);
  FBodyConventions[ABody] := TMethodText.ConventionOfRest(ARest);
end;

/// <summary>Deklarationen in AType und Rümpfe des Typs AMatch.TypeName.</summary>
procedure TMethodMatching.CollectMembers(const AType: TIndexSymbol; var AMatch: TTypeMethodMatch);
var
  mMembers: TArray<Integer>;
  mMask, mHeader, mRest: string;
  mIndex, mDeclarations, mBodies: Integer;
begin
  mMask := TypeMask(AType);
  mMembers := MethodsOf(AMatch.TypeName);
  SetLength(AMatch.Declarations, Length(mMembers));
  SetLength(AMatch.DeclarationHeaders, Length(mMembers));
  SetLength(AMatch.Bodies, Length(mMembers));
  SetLength(AMatch.BodyHeaders, Length(mMembers));
  SetLength(AMatch.BodyUsed, Length(mMembers));
  SetLength(FBodyConventions, Length(mMembers));
  mDeclarations := 0;
  mBodies := 0;
  for mIndex in mMembers do
  begin
    mHeader := TRoutineSignatures.Head(TMethodText.RangeText(FLines, FUnit.Symbols[mIndex].Range), mRest);
    if TMethodText.ContainsLine(AType.Range, FUnit.Symbols[mIndex].Range.StartPos.Line) then
    begin
      AMatch.Declarations[mDeclarations] := FUnit.Symbols[mIndex];
      AMatch.DeclarationHeaders[mDeclarations] := mHeader;
      Inc(mDeclarations);
    end
    // Deklarationen und Rümpfe eines gleichnamigen generischen Typs (TProperty<T>.Create) gehören nicht dazu;
    // mit bedingten Direktiven im Qualifizierer ('?') zählt der Rumpf wie bisher.
    else if not InAnyType(FUnit.Symbols[mIndex].Range.StartPos.Line) and
      MatchStr(TRoutineSignatures.QualifierMask(mHeader, FUnit.Symbols[mIndex].Name), [mMask, '?']) then
    begin
      AddBody(AMatch, mBodies, FUnit.Symbols[mIndex], mHeader, mRest);
      Inc(mBodies);
    end;
  end;
  SetLength(AMatch.Declarations, mDeclarations);
  SetLength(AMatch.DeclarationHeaders, mDeclarations);
  SetLength(AMatch.Bodies, mBodies);
  SetLength(AMatch.BodyHeaders, mBodies);
  SetLength(AMatch.BodyUsed, mBodies);
end;

/// <summary>Rumpf zur Deklaration ADeclaration als Index in Bodies und belegt ihn; -1 ohne, -2 übergangen
/// (abstract, external, forward).</summary>
function TMethodMatching.BodyFor(var AMatch: TTypeMethodMatch; ADeclaration: Integer): Integer;
var
  mSymbol: TIndexSymbol;
  mRest, mHeader: string;
begin
  mSymbol := AMatch.Declarations[ADeclaration];
  TRoutineSignatures.Head(TMethodText.RangeText(FLines, mSymbol.Range), mRest);
  if TMethodText.HasWord(mRest, 'abstract') or TMethodText.HasWord(mRest, 'external') or
    TMethodText.HasWord(mRest, 'forward') then
  begin
    Exit(-2);
  end;
  mHeader := AMatch.DeclarationHeaders[ADeclaration];
  Result := FreeBody(AMatch, LowerCase(mSymbol.Name) + TRoutineSignatures.ParameterKey(mHeader) +
    TRoutineSignatures.ResultKey(mHeader));
  // Ohne Parameterliste im Rumpf passt er zur ersten Deklaration gleichen Namens.
  if Result < 0 then
  begin
    Result := FreeBody(AMatch, LowerCase(mSymbol.Name));
  end;
  // Eine andere ausdrückliche Aufrufkonvention im Rumpf passt nicht (E2037).
  if (Result >= 0) and
    TMethodText.ConventionDiffers(FBodyConventions[Result], TMethodText.ConventionOfRest(mRest)) then
  begin
    Result := -1;
  end;
  if Result >= 0 then
  begin
    AMatch.BodyUsed[Result] := True;
  end;
end;

function TMethodMatching.MatchType(const AType: TIndexSymbol): TTypeMethodMatch;
var
  mDeclaration: Integer;
begin
  Result := Default(TTypeMethodMatch);
  Result.TypeName := TMethodText.TypeNameOf(AType);
  FBodySlots.Clear;
  FBodyConventions := nil;
  CollectMembers(AType, Result);
  SetLength(Result.BodyOf, Length(Result.Declarations));
  for mDeclaration := 0 to High(Result.Declarations) do
  begin
    Result.BodyOf[mDeclaration] := BodyFor(Result, mDeclaration);
  end;
end;

procedure TMethodMatching.MatchAll;
var
  mIndex, mCount: Integer;
begin
  SetLength(FMatches, FTypes.Count);
  mCount := 0;
  for mIndex in FTypes do
  begin
    // Generische Typen brauchen die Typparameter im Kopf; die kennt der Index nicht.
    if not IsGeneric(FUnit.Symbols[mIndex]) then
    begin
      FMatches[mCount] := MatchType(FUnit.Symbols[mIndex]);
      Inc(mCount);
    end;
  end;
  SetLength(FMatches, mCount);
  FBodySlots.Clear;
  FBodyConventions := nil;
end;

function TMethodMatching.GetMatches: TArray<TTypeMethodMatch>;
begin
  if not FMatched then
  begin
    MatchAll;
    FMatched := True;
  end;
  Result := FMatches;
end;

function TMethodMatching.FindType(const ATypeName: string; out AType: TIndexSymbol): Boolean;
var
  mList: TList<Integer>;
begin
  Result := FTypesByName.TryGetValue(LowerCase(ATypeName), mList);
  if Result then
  begin
    AType := FUnit.Symbols[mList[0]];
  end
  else
  begin
    AType := Default(TIndexSymbol);
  end;
end;

function TMethodMatching.MethodsOf(const ATypeName: string): TArray<Integer>;
var
  mList: TList<Integer>;
begin
  Result := nil;
  if FMethods.TryGetValue(LowerCase(ATypeName), mList) then
  begin
    Result := mList.ToArray;
  end;
end;

function TMethodMatching.TypeIndexes: TArray<Integer>;
begin
  Result := FTypes.ToArray;
end;

end.
