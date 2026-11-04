unit Atlas.Common.Lsp.Completion.Context;

// Was an der Cursorstelle vervollständigt wird (#31, #188, #450, #465, #483) und welcher Typ dort erwartet
// wird (#417, #468). Aus Atlas.Common.Lsp.Completion herausgelöst; die Fälle der Vervollständigung bauen
// darauf auf.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  TCompletionContexts = class
  public
    /// <summary>Was an APosition vervollständigt wird.</summary>
    class function Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext; static;
    /// <summary>Erwarteter Typ an APosition (#417): Typ des aktiven Parameters im innersten Aufruf, sonst der
    /// linken Seite einer Zuweisung (auch Result); '' wenn unbekannt.</summary>
    class function ExpectedType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): string; static;
    /// <summary>Wie ExpectedType, bei Zuweisungen aber samt Typargumenten der linken Seite (TProc&lt;string&gt;
    /// statt TProc, #468). ExpectedType bleibt ohne, weil die Gruppierung nach Fits mit den Typnamen der
    /// Kandidaten ohne Typargumente vergleicht.</summary>
    class function ExpectedFullType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): string; static;
    /// <summary>Schlüsselwörter für APlace (#31), klein geschrieben.</summary>
    class function Keywords(APlace: TCompletionPlace): TArray<string>; static;
  end;

/// <summary>Negativ, wenn A vor B liegt, 0 bei Gleichheit, sonst positiv.</summary>
function ComparePositions(const A, B: TTextPosition): Integer;
/// <summary>Name ohne führendes &amp;.</summary>
function CleanName(const AText: string): string;
/// <summary>Kommentar oder Direktive.</summary>
function IsTrivia(const AToken: TPascalToken): Boolean;
/// <summary>Index des Tokens vor AIndex ohne Kommentare und Direktiven; -1 am Anfang.</summary>
function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
/// <summary>Index der öffnenden Klammer zu ")" an AIndex; -1, wenn sie fehlt.</summary>
function OpeningParen(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
/// <summary>Steht das Token AIndex in einer uses-, contains- oder requires-Klausel?</summary>
function InUsesClause(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Lsp.CompletionEnums,
  Atlas.Common.Lsp.CompletionGenerics,
  Atlas.Common.Lsp.CompletionAttributes,
  Atlas.Common.Lsp.CompletionExceptions;

const
  // Schlüsselwörter je Stelle (#31).
  StatementKeywords: array[0..34] of string = ('begin', 'end', 'if', 'then', 'else', 'case', 'of', 'for', 'to',
    'downto', 'do', 'while', 'repeat', 'until', 'try', 'except', 'finally', 'on', 'raise', 'with', 'inherited',
    'var', 'const', 'nil', 'not', 'and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as');
  DeclarationKeywords: array[0..18] of string = ('procedure', 'function', 'constructor', 'destructor', 'var',
    'const', 'type', 'begin', 'end', 'class', 'record', 'uses', 'implementation', 'initialization', 'finalization',
    'resourcestring', 'threadvar', 'label', 'exports');
  ClassBodyKeywords: array[0..23] of string = ('procedure', 'function', 'constructor', 'destructor', 'property',
    'private', 'protected', 'public', 'published', 'strict', 'class', 'var', 'const', 'type', 'end', 'case',
    'virtual', 'override', 'overload', 'abstract', 'reintroduce', 'dynamic', 'static', 'message');
  /// <summary>Ergebnis von AssignmentBefore, wenn die Kette vor dem Cursor kein Bezeichner ist.</summary>
  cBrokenChain = -2;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function OpeningParen(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AIndex;
  while Result >= 0 do
  begin
    if ATokens[Result].IsSymbol(')') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol('(') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end
    else if ATokens[Result].IsSymbol(';') or ATokens[Result].IsKeyword('begin') then
    begin
      Break;
    end;
    Dec(Result);
  end;
  Result := -1;
end;

function InUsesClause(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mToken: TPascalToken;
begin
  // Rückwärts über Unit-Namen, Punkte, Kommas und "in 'Datei'" bis zum uses.
  while AIndex >= 0 do
  begin
    mToken := ATokens[AIndex];
    if mToken.IsKeyword('uses') or mToken.IsKeyword('contains') or mToken.IsKeyword('requires') then
    begin
      Exit(True);
    end;
    if not ((mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.StringLiteral]) or
      mToken.IsSymbol('.') or mToken.IsSymbol(',') or mToken.IsKeyword('in') or IsTrivia(mToken)) then
    begin
      Exit(False);
    end;
    Dec(AIndex);
  end;
  Result := False;
end;

/// <summary>Letztes Token, das vor APosition beginnt; -1 ohne.</summary>
function LastTokenBefore(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if ComparePositions(ATokens[mIndex].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    Result := mIndex;
  end;
end;

/// <summary>Anweisung, Deklaration oder Klassenrumpf an AOffset (#31): innerster Knoten, dann nach außen die
/// erste prägende Art.</summary>
function PlaceAt(ARoot: TSyntaxNode; AOffset: Integer): TCompletionPlace;
var
  mNode, mChild: TSyntaxNode;
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := TCompletionPlace.Unknown;
  if ARoot = nil then
  begin
    Exit;
  end;
  mNode := ARoot;
  repeat
    mFound := False;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      mChild := mNode[mIndex];
      if (mChild.StartOffset <= AOffset) and (AOffset <= mChild.EndOffset) then
      begin
        mNode := mChild;
        mFound := True;
        Break;
      end;
    end;
  until not mFound;
  while mNode <> nil do
  begin
    if mNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
      TSyntaxKind.InterfaceType, TSyntaxKind.HelperType] then
    begin
      Exit(TCompletionPlace.ClassBody);
    end;
    if mNode.Kind in [TSyntaxKind.Block .. TSyntaxKind.EmptyStatement] then
    begin
      Exit(TCompletionPlace.Statement);
    end;
    mNode := mNode.Parent;
  end;
  Result := TCompletionPlace.Declaration;
end;

/// <summary>"is", "as" oder "is not" an ALast.</summary>
function IsTypeOperator(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean;
var
  mBefore: Integer;
begin
  Result := ATokens[ALast].IsKeyword('is') or ATokens[ALast].IsKeyword('as');
  if not Result and ATokens[ALast].IsKeyword('not') then
  begin
    mBefore := PreviousIndex(ATokens, ALast);
    Result := (mBefore >= 0) and ATokens[mBefore].IsKeyword('is');
  end;
end;

/// <summary>":" an ALast leitet einen Typ ein: in Deklarationen immer, in Anweisungen nur bei inline var/const
/// und "on E:".</summary>
function ColonTypePosition(const ATokens: TArray<TPascalToken>; ALast: Integer; APlace: TCompletionPlace): Boolean;
var
  mIndex, mBefore: Integer;
begin
  if APlace <> TCompletionPlace.Statement then
  begin
    Exit(True);
  end;
  // var A, B: | bzw. on E: |
  Result := False;
  mIndex := PreviousIndex(ATokens, ALast);
  while (mIndex >= 0) and not Result and ((ATokens[mIndex].Kind = TPascalTokenKind.Identifier) or
    ATokens[mIndex].IsSymbol(',')) do
  begin
    mBefore := PreviousIndex(ATokens, mIndex);
    Result := SameText(ATokens[mIndex].Text, 'on') and (mBefore >= 0) and not ATokens[mBefore].IsSymbol('.');
    mIndex := mBefore;
  end;
  Result := Result or (mIndex >= 0) and (ATokens[mIndex].IsKeyword('var') or ATokens[mIndex].IsKeyword('const'));
end;

/// <summary>In der Vorfahrenliste: TFoo = class(TBasis, IFoo, |</summary>
function AncestorListPosition(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean;
var
  mIndex, mBefore: Integer;
begin
  mIndex := ALast;
  while (mIndex >= 0) and ((ATokens[mIndex].Kind = TPascalTokenKind.Identifier) or ATokens[mIndex].IsSymbol(',') or
    ATokens[mIndex].IsSymbol('.')) do
  begin
    mIndex := PreviousIndex(ATokens, mIndex);
  end;
  if (mIndex < 0) or not ATokens[mIndex].IsSymbol('(') then
  begin
    Exit(False);
  end;
  mBefore := PreviousIndex(ATokens, mIndex);
  Result := (mBefore >= 0) and (ATokens[mBefore].IsKeyword('class') or ATokens[mBefore].IsKeyword('interface') or
    ATokens[mBefore].IsKeyword('object') or ATokens[mBefore].IsKeyword('dispinterface'));
end;

/// <summary>An dieser Stelle kann nur ein Typ stehen (#31): nach "is", "is not", "as", in der Vorfahrenliste
/// "class(…" und nach ":" in Deklarationen (in Anweisungen nur bei inline var/const und "on E:").
/// AKeywords: auch string, array … anbieten (nur nach ":").</summary>
function TypePosition(const ATokens: TArray<TPascalToken>; ALast: Integer; APlace: TCompletionPlace;
  out AKeywords: Boolean): Boolean;
begin
  AKeywords := False;
  if ALast < 0 then
  begin
    Result := False;
  end
  else if ATokens[ALast].IsSymbol(':') then
  begin
    Result := ColonTypePosition(ATokens, ALast, APlace);
    AKeywords := Result;
  end
  else
  begin
    Result := IsTypeOperator(ATokens, ALast) or AncestorListPosition(ATokens, ALast);
  end;
end;

/// <summary>"TFoo&lt;|&gt;": Der Lexer liest "&lt;&gt;" als ein Token; Typargument wie nach "TFoo&lt;" (#450).
/// </summary>
function DiamondContext(ATree: TSyntaxTree; ALast: Integer; const APosition: TTextPosition;
  var AContext: TCompletionContext): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mBefore: Integer;
begin
  mTokens := ATree.Tokens;
  mBefore := PreviousIndex(mTokens, ALast);
  Result := mTokens[ALast].IsSymbol('<>') and (APosition.Character = mTokens[ALast].StartPos.Character + 1) and
    (mBefore >= 0) and (mTokens[mBefore].Kind = TPascalTokenKind.Identifier);
  if Result then
  begin
    AContext.Kind := TCompletionContextKind.Scope;
    AContext.Offset := mTokens[ALast].Offset + 1;
    AContext.Place := PlaceAt(ATree.Root, AContext.Offset);
    AContext.Generic := True;
    AContext.GenericOwnerPos := mTokens[mBefore].StartPos;
    AContext.GenericParam := 0;
  end;
end;

/// <summary>Angefangener Name bis zum Cursor; auch ein halbes Schlüsselwort wie "beg" gilt als Anfang.</summary>
function PrefixOf(const AToken: TPascalToken; const APosition: TTextPosition): string;
begin
  Result := Copy(AToken.Text, 1, APosition.Character - AToken.StartPos.Character);
  if AToken.Kind = TPascalTokenKind.Identifier then
  begin
    Result := CleanName(Result);
  end;
end;

/// <summary>Liest das Token ALast am Cursor: angefangener Name, Kommentar, mitten in einem Token. False, wenn die
/// Antwort damit feststeht (nichts anbieten bzw. Typargument in "&lt;&gt;").</summary>
function ReadAtCursor(ATree: TSyntaxTree; const APosition: TTextPosition; var ALast: Integer;
  var AContext: TCompletionContext): Boolean;
var
  mToken: TPascalToken;
begin
  mToken := ATree.Tokens[ALast];
  AContext.Offset := mToken.Offset + Length(mToken.Text);
  if ComparePositions(APosition, mToken.EndPos) < 0 then
  begin
    // Cursor mitten in einem Token: in Kommentaren, Strings und Zahlen nichts anbieten.
    if DiamondContext(ATree, ALast, APosition, AContext) or (mToken.Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
  if (mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (ComparePositions(APosition, mToken.EndPos) <= 0) then
  begin
    AContext.Prefix := PrefixOf(mToken, APosition);
    AContext.Offset := mToken.Offset;
    ALast := PreviousIndex(ATree.Tokens, ALast);
  end
  else if IsTrivia(mToken) then
  begin
    // Zeilenkommentar reicht bis zum Zeilenende.
    Result := not ((ComparePositions(APosition, mToken.EndPos) <= 0) and mToken.Text.StartsWith('//'));
    ALast := PreviousIndex(ATree.Tokens, ALast + 1);
  end;
end;

/// <summary>Bezeichner vor der Klammer, die zu ")" an AIndex gehört; -1, wenn es keinen gibt.</summary>
function CallBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := OpeningParen(ATokens, AIndex);
  if Result >= 0 then
  begin
    Result := PreviousIndex(ATokens, Result);
  end;
  if (Result >= 0) and (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
  begin
    Result := -1;
  end;
end;

/// <summary>Kette vor dem Punkt an ALast ("A.B(1)."); False, wenn sie nicht auflösbar ist (1. oder "a".).
/// </summary>
function ChainNames(const ATokens: TArray<TPascalToken>; ALast: Integer; var AContext: TCompletionContext;
  out ANames: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  ANames := nil;
  mIndex := PreviousIndex(ATokens, ALast);
  while mIndex >= 0 do
  begin
    // Foo(1). oder TFoo(X).: Klammern überspringen, das Glied davor ist ein Aufruf bzw. eine Typumwandlung (#188).
    if ATokens[mIndex].IsSymbol(')') then
    begin
      mIndex := CallBefore(ATokens, mIndex);
      if mIndex < 0 then
      begin
        Exit(False);
      end;
      AContext.Called := AContext.Called or (ANames = nil);
    end;
    if ATokens[mIndex].Kind <> TPascalTokenKind.Identifier then
    begin
      Break;
    end;
    ANames := [CleanName(ATokens[mIndex].Text)] + ANames;
    AContext.ChainStart := ATokens[mIndex].StartPos;
    mIndex := PreviousIndex(ATokens, mIndex);
    if (mIndex < 0) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Break;
    end;
    mIndex := PreviousIndex(ATokens, mIndex);
  end;
  Result := (ANames <> nil) and not ((mIndex >= 0) and ATokens[mIndex].IsSymbol('.'));
end;

/// <summary>Nach "Kette.": Mitglieder, in uses der Rest des Unit-Namens.</summary>
procedure SetMember(const ATokens: TArray<TPascalToken>; ALast: Integer; const ANames: TArray<string>;
  var AContext: TCompletionContext);
begin
  if InUsesClause(ATokens, ALast) then
  begin
    // uses System.Sys…: der Anfang gehört zum Unit-Namen.
    AContext.Kind := TCompletionContextKind.UsesClause;
    AContext.Prefix := string.Join('.', ANames) + '.' + AContext.Prefix;
  end
  else
  begin
    AContext.Kind := TCompletionContextKind.Member;
    AContext.Names := ANames;
    AContext.Offset := ATokens[ALast].Offset;
    AContext.DotPos := ATokens[ALast].StartPos;
  end;
end;

/// <summary>Kontexte ohne Typauflösung im Gültigkeitsbereich (#31, #450, #465, #483).</summary>
procedure SetScope(ATree: TSyntaxTree; ALast: Integer; var AContext: TCompletionContext);
var
  mTokens: TArray<TPascalToken>;
  mSite: TGenericArgSite;
  mExceptionSite: TExceptionSite;
begin
  mTokens := ATree.Tokens;
  AContext.Kind := TCompletionContextKind.Scope;
  AContext.Place := PlaceAt(ATree.Root, AContext.Offset);
  if (ALast >= 0) and mTokens[ALast].IsKeyword('inherited') then
  begin
    AContext.Filter := TCompletionFilter.InheritedCall;
    Exit;
  end;
  if TypePosition(mTokens, ALast, AContext.Place, AContext.TypeKeywords) then
  begin
    AContext.Filter := TCompletionFilter.Types;
  end
  else if TCompletionAttributes.SiteAt(mTokens, ALast) then
  begin
    // Attribut nach "[" vor einer Deklaration (#465); ob es gilt, entscheidet Collect nach der Einstellung.
    AContext.Attribute := True;
    AContext.Filter := TCompletionFilter.Types;
    Exit;
  end;
  // Exception-Klassen nach "raise " und "on E: " (#483); ob es gilt, entscheidet Collect nach der Einstellung.
  if TCompletionExceptions.SiteAt(mTokens, ALast, mExceptionSite) then
  begin
    AContext.Exceptions := True;
    AContext.ExceptionToken := ALast;
    AContext.Filter := TCompletionFilter.Types;
    Exit;
  end;
  // Typargument nach "TFoo<" (#450); ob TFoo ein generischer Typ ist, klärt Collect.
  mSite := TCompletionGenerics.SiteAt(mTokens, ALast);
  if mSite.Found then
  begin
    AContext.Generic := True;
    AContext.GenericOwnerPos := mSite.OwnerPosition;
    AContext.GenericParam := mSite.Parameter;
  end;
end;

/// <summary>Argument eines Aufrufs: Typ des aktiven Parameters (erste passende Überladung). False außerhalb
/// eines Aufrufs.</summary>
function ArgumentType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AType: string): Boolean;
var
  mSite: TCallSite;
  mCallee: TResolvedSymbol;
begin
  AType := '';
  mSite := TLspSignatureHelp.CallSiteAt(ATree, APosition);
  Result := mSite.Found;
  if not Result then
  begin
    Exit;
  end;
  mCallee := AResolver.Resolve(ATree, AFileName, mSite.NamePosition);
  // Mitglied einer generischen Instanz (TBox<TKunde>.Where): Typparameter der Klasse einsetzen (#468).
  if mCallee.Found and (mSite.ActiveParameter < Length(mCallee.ParamTypes)) then
  begin
    AType := TInterfaceStubs.SubstituteWords(mCallee.ParamTypes[mSite.ActiveParameter], mCallee.Bindings);
  end;
end;

/// <summary>"Ziel := A.B.Anf|": Index des ":=" rückwärts über die Kette rechts; -1 ohne Zuweisung,
/// cBrokenChain, wenn vor einem Punkt kein Bezeichner steht.</summary>
function AssignmentBefore(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
begin
  Result := PreviousIndex(ATokens, LastTokenBefore(ATokens, APosition) + 1);
  if (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (ComparePositions(APosition, ATokens[Result].EndPos) <= 0) then
  begin
    Result := PreviousIndex(ATokens, Result);
  end;
  while (Result >= 0) and ATokens[Result].IsSymbol('.') do
  begin
    Result := PreviousIndex(ATokens, Result);
    if (Result < 0) or (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit(cBrokenChain);
    end;
    Result := PreviousIndex(ATokens, Result);
  end;
  if (Result >= 0) and not ATokens[Result].IsSymbol(':=') then
  begin
    Result := -1;
  end;
end;

/// <summary>Vergleich ("Shape.Kind = ") und case-Zweig (#448): Typ der Kette. Ein Typ selbst steht bei typisierten
/// Konstanten und Standardwerten ("const C: TAlign = ", "A: TAlign = ").</summary>
function ComparedType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): string;
var
  mSlot: TEnumValueSlot;
  mTarget: TResolvedSymbol;
begin
  Result := '';
  if not TCompletionEnums.ValueSlot(ATree.Tokens, APosition, mSlot) then
  begin
    Exit;
  end;
  mTarget := AResolver.ResolveChain(ATree, AFileName, mSlot.Names, mSlot.Offset);
  if mTarget.Found and mTarget.IsType then
  begin
    Result := mTarget.Name;
  end
  else if mTarget.Found then
  begin
    Result := mTarget.TypeName;
  end;
end;

/// <summary>Kette links vom ":=" an AIndex.</summary>
function TargetNames(const ATokens: TArray<TPascalToken>; AIndex: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := PreviousIndex(ATokens, AIndex);
  while (mIndex >= 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := [CleanName(ATokens[mIndex].Text)] + Result;
    mIndex := PreviousIndex(ATokens, mIndex);
    if (mIndex < 0) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Break;
    end;
    mIndex := PreviousIndex(ATokens, mIndex);
  end;
end;

/// <summary>Rückgabetyp der Funktion, in deren Rumpf APosition steht; '' ohne.</summary>
function ResultTypeAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in AResolver.ExtractedUnit(ATree, AFileName).Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and (mSymbol.TypeName <> '') and
      (mSymbol.Range.StartPos.Line < APosition.Line) and (mSymbol.Range.EndPos.Line >= APosition.Line) then
    begin
      Result := mSymbol.TypeName;
    end;
  end;
end;

/// <summary>Typ eines Zuweisungsziels; mit AWithArgs samt Typargumenten.</summary>
function TargetType(const ATarget: TResolvedSymbol; AWithArgs: Boolean): string;
begin
  Result := '';
  if ATarget.Found and not ATarget.IsType and (ATarget.SymbolKind <> TIndexSymbolKind.Routine) and
    (ATarget.SymbolKind <> TIndexSymbolKind.Method) then
  begin
    Result := ATarget.TypeName;
    if AWithArgs and (Result <> '') and (ATarget.TypeArgs <> '') then
    begin
      Result := Result + '<' + ATarget.TypeArgs + '>';
    end;
  end;
end;

/// <summary>Erwarteter Typ am Cursor (siehe TCompletionContexts.ExpectedType); mit AWithArgs bei Zuweisungen samt
/// Typargumenten der Variablen.</summary>
function ExpectedTypeOf(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; AWithArgs: Boolean): string;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mNames: TArray<string>;
begin
  Result := '';
  if (ATree = nil) or ArgumentType(AResolver, ATree, AFileName, APosition, Result) then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mIndex := AssignmentBefore(mTokens, APosition);
  if mIndex = -1 then
  begin
    Exit(ComparedType(AResolver, ATree, AFileName, APosition));
  end;
  mNames := nil;
  if mIndex >= 0 then
  begin
    mNames := TargetNames(mTokens, mIndex);
  end;
  if mNames = nil then
  begin
    Exit;
  end;
  Result := TargetType(AResolver.ResolveChain(ATree, AFileName, mNames, mTokens[mIndex].Offset), AWithArgs);
  // Result: Rückgabetyp der umgebenden Funktion.
  if (Result = '') and (Length(mNames) = 1) and SameText(mNames[0], 'Result') then
  begin
    Result := ResultTypeAt(AResolver, ATree, AFileName, APosition);
  end;
end;

{ TCompletionContexts }

class function TCompletionContexts.Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext;
var
  mTokens: TArray<TPascalToken>;
  mLast: Integer;
  mNames: TArray<string>;
begin
  Result := Default(TCompletionContext);
  Result.Kind := TCompletionContextKind.None;
  if ATree = nil then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mLast := LastTokenBefore(mTokens, APosition);
  Result.Offset := 0;
  if (mLast >= 0) and not ReadAtCursor(ATree, APosition, mLast, Result) then
  begin
    Exit;
  end;
  if (mLast >= 0) and mTokens[mLast].IsSymbol('.') then
  begin
    if ChainNames(mTokens, mLast, Result, mNames) then
    begin
      SetMember(mTokens, mLast, mNames, Result);
    end;
  end
  else if (mLast >= 0) and InUsesClause(mTokens, mLast) then
  begin
    Result.Kind := TCompletionContextKind.UsesClause;
  end
  else
  begin
    SetScope(ATree, mLast, Result);
  end;
end;

class function TCompletionContexts.ExpectedType(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition): string;
begin
  Result := ExpectedTypeOf(AResolver, ATree, AFileName, APosition, False);
end;

class function TCompletionContexts.ExpectedFullType(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition): string;
begin
  Result := ExpectedTypeOf(AResolver, ATree, AFileName, APosition, True);
end;

class function TCompletionContexts.Keywords(APlace: TCompletionPlace): TArray<string>;
var
  mWord: string;
begin
  Result := nil;
  case APlace of
    TCompletionPlace.Statement:
      for mWord in StatementKeywords do
      begin
        Result := Result + [mWord];
      end;
    TCompletionPlace.Declaration:
      for mWord in DeclarationKeywords do
      begin
        Result := Result + [mWord];
      end;
    TCompletionPlace.ClassBody:
      for mWord in ClassBodyKeywords do
      begin
        Result := Result + [mWord];
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

end.
