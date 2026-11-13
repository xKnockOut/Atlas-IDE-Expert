unit Atlas.Common.Rules.Builtin.TypeDeclarations.Scan;

// Gemeinsame Sicht der Regeln zu Typdeklarationen (Atlas.Common.Rules.Builtin.TypeDeclarations) auf eine Datei:
// Token, Zweige bedingter Übersetzung, Namensauflösung, Spezifizierer von Properties und Methodenköpfe bzw.
// -rümpfe einer Klasse.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Token, Zweige bedingter Übersetzung und Namensauflösung einer Datei für die Regeln zu
  /// Typdeklarationen; pinnt den Baum für die Dauer der Prüfung.</summary>
  TDeclarationScan = class
  private
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FResolver: TNameResolver;
    FOwnUnit: TUnitIndex;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    function FirstToken(ANode: TSyntaxNode): Integer;
    /// <summary>Erstes Token hinter ANode.</summary>
    function StopToken(ANode: TSyntaxNode): Integer;
    /// <summary>Erstes Token ab AIndex, das kein Kommentar und keine Direktive ist (höchstens AStop).</summary>
    function NextCode(AIndex, AStop: Integer): Integer;
    /// <summary>Löscht die Direktive ADirective samt ihrem Semikolon und dem Leerraum davor.</summary>
    function DirectiveRemoval(ADirective: TSyntaxNode): TTextEdit;
    /// <summary>Token des Schlüsselworts dispinterface am Anfang von AType (InterfaceType); -1 bei
    /// interface.</summary>
    function DispKeyword(AType: TSyntaxNode): Integer;
    /// <summary>Steht ANode außerhalb jeder bedingten Übersetzung?</summary>
    function Unconditional(ANode: TSyntaxNode): Boolean;
    function TokenRange(AIndex: Integer): TTextRange;
    function FirstRange(ANode: TSyntaxNode): TTextRange;
    /// <summary>Token des Property-Namens (erster passender Bezeichner); StopToken ohne.</summary>
    function PropertyNameToken(AProperty: TSyntaxNode): Integer;
    function PropertyRange(AProperty: TSyntaxNode): TTextRange;
    /// <summary>Erstes Semikolon der Property auf Klammerebene 0 (Ende der Spezifizierer).</summary>
    function ClauseEnd(AProperty: TSyntaxNode): Integer;
    /// <summary>Spezifizierer der Property (read, write, stored, default, index, implements …) als Token-Index,
    /// ohne Namen, Parameter, Typ und Argumente der Spezifizierer.</summary>
    function ClauseWords(AProperty: TSyntaxNode): TArray<Integer>;
    /// <summary>Token des Arguments hinter dem Spezifizierer an AIndex; ClauseEnd ohne.</summary>
    function ClauseArgument(AProperty: TSyntaxNode; AIndex: Integer): Integer;
    /// <summary>Text des Knotens ohne Leerraum, Groß-/Kleinschreibung und Unit-Präfix (E2208, E2257).</summary>
    function TypeKey(ANode: TSyntaxNode): string; overload;
    function TypeKey(AFirst, AStop: Integer): string; overload;
    /// <summary>Text der Token AFirst..AStop-1 ohne Kommentare und Leerraum.</summary>
    function Text(AFirst, AStop: Integer): string;
    property Tokens: TArray<TPascalToken> read FTokens;
    property Resolver: TNameResolver read FResolver;
    property OwnUnit: TUnitIndex read FOwnUnit;
  end;

/// <summary>Einziger Methodenkopf AName im Typ AType; nil ohne oder bei Überladungen.</summary>
function UniqueMethodHeader(AType: TSyntaxNode; const AName: string): TSyntaxNode;

/// <summary>Rumpf AClassName.AMethod im implementation-Teil von ATree; nil ohne oder bei mehreren.</summary>
function MethodBody(ATree: TSyntaxTree; const AClassName, AMethod: string): TSyntaxNode;

implementation

uses
  Atlas.Common.Pascal.TokenCursor,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Text.Lines;

const
  // Spezifizierer einer Property nach Name und Typ.
  cPropertySpecifiers: array[0..9] of string = ('read', 'write', 'stored', 'default', 'nodefault', 'index',
    'implements', 'dispid', 'readonly', 'writeonly');

function UniqueMethodHeader(AType: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AType.ChildCount - 1 do
  begin
    if (AType[mIndex].Kind = TSyntaxKind.RoutineHeader) and SameText(AType[mIndex].Name, AName) then
    begin
      if Result <> nil then
      begin
        Exit(nil);
      end;
      Result := AType[mIndex];
    end;
  end;
end;

function MethodBody(ATree: TSyntaxTree; const AClassName, AMethod: string): TSyntaxNode;
var
  mSection: TSyntaxNode;
  mIndex: Integer;
  mMany: Boolean;
begin
  Result := nil;
  mMany := False;
  mSection := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    mSection := ATree.Root;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    if (mSection[mIndex].Kind = TSyntaxKind.RoutineDecl) and
      SameText(mSection[mIndex].Name, AClassName + '.' + AMethod) then
    begin
      mMany := Result <> nil;
      Result := mSection[mIndex];
    end;
  end;
  if mMany then
  begin
    Result := nil;
  end;
end;


constructor TDeclarationScan.Create(const AContext: TRuleContext);
var
  mFileName: string;
begin
  inherited Create;
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  mFileName := AContext.FileName;
  if mFileName = '' then
  begin
    mFileName := AContext.RelativePath;
  end;
  if mFileName = '' then
  begin
    mFileName := AContext.UnitName + '.pas';
  end;
  FResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FResolver.PinTree(AContext.Tree, mFileName);
  FOwnUnit := FResolver.ExtractedUnit(AContext.Tree, mFileName);
end;

destructor TDeclarationScan.Destroy;
begin
  FResolver.UnpinTree;
  FResolver.Free;
  FTokens := nil;
  FPaths := nil;
  inherited;
end;

function TDeclarationScan.FirstToken(ANode: TSyntaxNode): Integer;
begin
  Result := TokenFrom(FTokens, ANode.StartOffset);
end;

function TDeclarationScan.StopToken(ANode: TSyntaxNode): Integer;
begin
  Result := TokenFrom(FTokens, ANode.EndOffset);
end;

function TDeclarationScan.NextCode(AIndex, AStop: Integer): Integer;
begin
  Result := AIndex;
  while (Result < AStop) and IsTrivia(FTokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function TDeclarationScan.DirectiveRemoval(ADirective: TSyntaxNode): TTextEdit;
var
  mFirst, mLast, mNext, mBefore: Integer;
begin
  mFirst := FirstToken(ADirective);
  mLast := StopToken(ADirective) - 1;
  mNext := NextCode(mLast + 1, Length(FTokens));
  if (mNext < Length(FTokens)) and FTokens[mNext].IsSymbol(';') then
  begin
    mLast := mNext;
  end;
  mBefore := PreviousCode(FTokens, mFirst);
  if mBefore < 0 then
  begin
    mBefore := mFirst;
  end;
  Result := TTextEdit.Create(TTextRange.Create(FTokens[mBefore].EndPos, FTokens[mLast].EndPos), '');
end;

function TDeclarationScan.DispKeyword(AType: TSyntaxNode): Integer;
begin
  Result := NextCode(FirstToken(AType), Length(FTokens));
  if (Result >= Length(FTokens)) or not SameText(FTokens[Result].Text, 'dispinterface') then
  begin
    Result := -1;
  end;
end;

function TDeclarationScan.Unconditional(ANode: TSyntaxNode): Boolean;
begin
  Result := TConditionalBranches.PathAt(FPaths, FirstToken(ANode)) = '';
end;

function TDeclarationScan.TokenRange(AIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AIndex].StartPos, FTokens[AIndex].EndPos);
end;

function TDeclarationScan.FirstRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TokenRange(FirstToken(ANode));
end;

function TDeclarationScan.PropertyNameToken(AProperty: TSyntaxNode): Integer;
var
  mStop: Integer;
begin
  mStop := StopToken(AProperty);
  Result := FirstToken(AProperty);
  while (Result < mStop) and not ((FTokens[Result].Kind = TPascalTokenKind.Identifier) and
    SameText(FTokens[Result].Text, AProperty.Name)) do
  begin
    Inc(Result);
  end;
end;

function TDeclarationScan.PropertyRange(AProperty: TSyntaxNode): TTextRange;
var
  mIndex: Integer;
begin
  mIndex := PropertyNameToken(AProperty);
  if mIndex < StopToken(AProperty) then
  begin
    Result := TokenRange(mIndex);
  end
  else
  begin
    Result := TTextRange.Create(AProperty.StartPos, AProperty.EndPos);
  end;
end;

function TDeclarationScan.ClauseEnd(AProperty: TSyntaxNode): Integer;
var
  mStop, mDepth: Integer;
begin
  mStop := StopToken(AProperty);
  mDepth := 0;
  Result := PropertyNameToken(AProperty);
  while Result < mStop do
  begin
    if FTokens[Result].IsSymbol('[') or FTokens[Result].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if FTokens[Result].IsSymbol(']') or FTokens[Result].IsSymbol(')') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and FTokens[Result].IsSymbol(';') then
    begin
      Exit;
    end;
    Inc(Result);
  end;
end;

function TDeclarationScan.ClauseWords(AProperty: TSyntaxNode): TArray<Integer>;
var
  mIndex, mStop, mDepth: Integer;
  mArgument: Boolean;
begin
  Result := nil;
  mStop := ClauseEnd(AProperty);
  mDepth := 0;
  // Ein Bezeichner direkt hinter read, write, stored … ist dessen Argument (read Stored), kein Spezifizierer.
  mArgument := False;
  for mIndex := PropertyNameToken(AProperty) + 1 to mStop - 1 do
  begin
    if IsTrivia(FTokens[mIndex]) then
    begin
      Continue;
    end;
    if FTokens[mIndex].IsSymbol('[') or FTokens[mIndex].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if FTokens[mIndex].IsSymbol(']') or FTokens[mIndex].IsSymbol(')') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and not mArgument and (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      MatchText(FTokens[mIndex].Text, cPropertySpecifiers) then
    begin
      Result := Result + [mIndex];
      mArgument := not MatchText(FTokens[mIndex].Text, ['nodefault', 'readonly', 'writeonly']);
      Continue;
    end;
    mArgument := False;
  end;
end;

function TDeclarationScan.ClauseArgument(AProperty: TSyntaxNode; AIndex: Integer): Integer;
begin
  Result := NextCode(AIndex + 1, ClauseEnd(AProperty));
end;

function TDeclarationScan.Text(AFirst, AStop: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to AStop - 1 do
  begin
    if not IsTrivia(FTokens[mIndex]) then
    begin
      Result := Result + FTokens[mIndex].Text;
    end;
  end;
end;

function TDeclarationScan.TypeKey(ANode: TSyntaxNode): string;
begin
  Result := TypeKey(FirstToken(ANode), StopToken(ANode));
end;

function TDeclarationScan.TypeKey(AFirst, AStop: Integer): string;
var
  mAngle: Integer;
  mHead: string;
begin
  Result := UpperCase(Text(AFirst, AStop));
  mAngle := Pos('<', Result);
  if mAngle = 0 then
  begin
    mAngle := Length(Result) + 1;
  end;
  mHead := Copy(Result, 1, mAngle - 1);
  Result := Copy(mHead, LastDelimiter('.', mHead) + 1, MaxInt) + Copy(Result, mAngle, MaxInt);
end;

end.
