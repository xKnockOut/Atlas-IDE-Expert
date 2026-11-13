unit Atlas.Common.Lsp.CoveredBy;

// „Getestet von“ (#1778): Welche DUnitX-Tests prüfen die Methoden einer
// normalen Unit? Rückwärts wie die betroffenen Tests einer Änderung (#1353):
// Jede Methode mit Rumpf ist ein Startpunkt der Auswirkungsanalyse (#1120,
// TImpactAnalysis.AnalyzeEach); Tests bis zur gewählten Tiefe (Vorgabe 1 =
// Tests, die die Methode direkt aufrufen) gehören zu ihr.
//
// Welche Methoden: Routinen mit Rumpf im implementation-Teil (keine lokalen
// Routinen, keine Destruktoren: die ruft Free, nicht der Test). Ohne
// IncludePrivate nur öffentliche: Methoden mit Sichtbarkeit public oder
// published einer Klasse aus dem interface-Teil und Routinen, die im
// interface-Teil deklariert sind. Die Marke steht am Namen im Kopf des Rumpfs.
//
// Testunits (Name nach testUnits.pattern, uses eines Testprogramms oder mit
// DUnitX-Fixtures) bekommen keine Marken: Dort steht die Testlinse (#69).
// HasTestUnit sagt, ob eine Testunit die Unit verwendet (#1783: ohne keine
// Marke „n von m Methoden getestet“).
//
// LSP: atlas/coveredBy {textDocument, text?, depth?, includePrivate?}.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Impact;

type
  /// <summary>Ein Test, der eine Methode erreicht.</summary>
  TCoveredTest = record
    /// <summary>Unit.Fixture.Methode.</summary>
    Name: string;
    /// <summary>Namen für --run bzw. run_tests (bei [TestCase] je Fall).</summary>
    RunNames: TArray<string>;
    FileName: string;
    /// <summary>Kopf der Testmethode, 0-basiert.</summary>
    Line: Integer;
    /// <summary>1 = ruft die Methode direkt auf, 2 und mehr = über andere Routinen.</summary>
    Level: Integer;
    /// <summary>Ein Schritt des Wegs ist erschlossen (#1119), nicht sicher.</summary>
    Inferred: Boolean;
  end;

  TCoveredMethod = record
    /// <summary>TFoo.Bar bzw. Bar bei Routinen.</summary>
    Name: string;
    /// <summary>Startpunkt der Analyse: der Rumpf.</summary>
    Item: THierarchyItem;
    Visibility: TIndexVisibility;
    /// <summary>Öffentlich (public/published einer Klasse aus dem interface-Teil, Routine im interface-Teil).
    /// </summary>
    IsPublic: Boolean;
    Tests: TArray<TCoveredTest>;
    /// <summary>Zeile und Spalte des Namens im Kopf des Rumpfs, 0-basiert.</summary>
    function Line: Integer;
    function Character: Integer;
  end;

  TCoveredRequest = record
    /// <summary>Projektdateien aller Projekte (Referenzsuche).</summary>
    Files: TArray<string>;
    /// <summary>Tiefe, Treffersicherheit, Testunits und Zeitlimit.</summary>
    Options: TImpactOptions;
    /// <summary>Auch private und protected Methoden sowie Routinen nur im implementation-Teil.</summary>
    IncludePrivate: Boolean;
  end;

  TCoveredResult = record
    UnitName: string;
    Depth: Integer;
    /// <summary>Die Unit ist selbst eine Testunit: keine Methoden.</summary>
    IsTestUnit: Boolean;
    /// <summary>Eine Testunit verwendet die Unit (uses).</summary>
    HasTestUnit: Boolean;
    Methods: TArray<TCoveredMethod>;
    Limits: TImpactLimits;
    /// <summary>Methoden mit mindestens einem Test.</summary>
    function Tested: Integer;
  end;

  TCoveredBy = class
  public const
    cMethod = 'atlas/coveredBy';
    cDefaultDepth = 1;
  public
    /// <summary>Methoden mit Rumpf der Unit AText (Datei AFileName) in Reihenfolge des Quelltexts; ohne
    /// AIncludePrivate nur öffentliche.</summary>
    class function Methods(const AFileName, AText: string; AIncludePrivate: Boolean): TArray<TCoveredMethod>; static;
    /// <summary>Ist die Unit eine Testunit (Muster, uses eines Testprogramms, DUnitX-Fixtures)?</summary>
    class function IsTestUnit(const AUnitName, AText: string; const AScope: TImpactTestScope): Boolean; static;
    /// <summary>Verwendet eine Testunit aus AScope die Unit AUnitName (laut Index)?</summary>
    class function HasTestUnit(const AIndex: ISymbolIndex; const AUnitName: string;
      const AScope: TImpactTestScope): Boolean; static;
    /// <summary>Tests je Methode der Unit AText (Datei AFileName).</summary>
    class function Determine(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AFileName, AText: string;
      const ARequest: TCoveredRequest; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken): TCoveredResult; static;
    /// <summary>"public", "published", "protected", "private".</summary>
    class function VisibilityName(AVisibility: TIndexVisibility): string; static;
    /// <summary>Antwort von atlas/coveredBy; der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AResult: TCoveredResult): TJSONObject; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX;

const
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.HelperType];
  cMethodKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];

{ TCoveredMethod }

function TCoveredMethod.Line: Integer;
begin
  Result := Item.SelectionRange.StartPos.Line;
end;

function TCoveredMethod.Character: Integer;
begin
  Result := Item.SelectionRange.StartPos.Character;
end;

{ TCoveredResult }

function TCoveredResult.Tested: Integer;
var
  mMethod: TCoveredMethod;
begin
  Result := 0;
  for mMethod in Methods do
  begin
    if Length(mMethod.Tests) > 0 then
    begin
      Inc(Result);
    end;
  end;
end;

{ Methoden der Unit }

function WithoutGenerics(const AName: string): string;
var
  mBracket: Integer;
begin
  mBracket := Pos('<', AName);
  if mBracket > 0 then
  begin
    Result := Copy(AName, 1, mBracket - 1);
  end
  else
  begin
    Result := AName;
  end;
end;

/// <summary>Letzter Teil eines qualifizierten Typnamens (TAussen.TInnen → TInnen), ohne Typparameter.</summary>
function LastTypeName(const AName: string): string;
var
  mPlain: string;
begin
  mPlain := WithoutGenerics(AName);
  Result := Copy(mPlain, LastDelimiter('.', mPlain) + 1, MaxInt);
end;

/// <summary>Routinen mit Rumpf auf Unit-Ebene, ohne lokale Routinen, in Reihenfolge des Quelltexts.</summary>
function BodyNodes(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        if ANode.FindChild(TSyntaxKind.Block) <> nil then
        begin
          mFound := mFound + [ANode];
        end;
        // Lokale Routinen und Rümpfe anonymer Methoden gehören zur Routine.
        Exit(False);
      end;
      // Typdeklarationen enthalten nur Köpfe.
      Result := ANode.Kind <> TSyntaxKind.TypeDecl;
    end);
  Result := mFound;
end;

/// <summary>Beginnt der Kopf mit destructor (auch nach class)?</summary>
function IsDestructor(const ALines: TArray<string>; ANode: TSyntaxNode): Boolean;
var
  mText: string;
begin
  Result := False;
  if (ANode.StartPos.Line < 0) or (ANode.StartPos.Line > High(ALines)) then
  begin
    Exit;
  end;
  mText := LowerCase(TrimLeft(Copy(ALines[ANode.StartPos.Line], ANode.StartPos.Character + 1, MaxInt)));
  if StartsStr('class ', mText) then
  begin
    mText := TrimLeft(Copy(mText, Length('class ') + 1, MaxInt));
  end;
  Result := StartsStr('destructor', mText);
end;

/// <summary>Deklaration des Typs ATypeName in AUnit; False ohne.</summary>
function FindType(const AUnit: TUnitIndex; const ATypeName: string; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cTypeKinds) and SameText(WithoutGenerics(mSymbol.Name), ATypeName) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  ASymbol := Default(TIndexSymbol);
  Result := False;
end;

function Inside(const AOuter, AInner: TTextRange): Boolean;
begin
  Result := ((AOuter.StartPos.Line < AInner.StartPos.Line) or ((AOuter.StartPos.Line = AInner.StartPos.Line) and
    (AOuter.StartPos.Character <= AInner.StartPos.Character))) and ((AInner.StartPos.Line < AOuter.EndPos.Line) or
    ((AInner.StartPos.Line = AOuter.EndPos.Line) and (AInner.StartPos.Character <= AOuter.EndPos.Character)));
end;

/// <summary>Sichtbarkeit des Rumpfs AItem laut Deklaration in der Klasse; APublic = von anderen Units aufrufbar.
/// </summary>
procedure VisibilityOf(const AUnit: TUnitIndex; const AItem: THierarchyItem; out AVisibility: TIndexVisibility;
  out APublic: Boolean);
var
  mSymbol, mType: TIndexSymbol;
  mTypeName: string;
  mFound: Boolean;
begin
  AVisibility := TIndexVisibility.Private;
  APublic := False;
  mFound := False;
  if AItem.Container = '' then
  begin
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Routine) and (mSymbol.Container = '') and
        SameText(mSymbol.Name, AItem.Name) and mSymbol.InInterface then
      begin
        AVisibility := TIndexVisibility.Public;
        APublic := True;
        Exit;
      end;
    end;
    Exit;
  end;
  mTypeName := LastTypeName(AItem.Container);
  if not FindType(AUnit, mTypeName, mType) then
  begin
    Exit;
  end;
  for mSymbol in AUnit.Symbols do
  begin
    // Nur die Deklaration in der Klasse, nicht der Rumpf im implementation-Teil.
    if not ((mSymbol.Kind in cMethodKinds) and SameText(mSymbol.Name, AItem.Name) and
      (mSymbol.FileName = '') and Inside(mType.Range, mSymbol.SelectionRange)) then
    begin
      Continue;
    end;
    // Überladungen mit verschiedener Sichtbarkeit: die sichtbarste.
    if not mFound or (Ord(mSymbol.Visibility) < Ord(AVisibility)) then
    begin
      AVisibility := mSymbol.Visibility;
    end;
    mFound := True;
  end;
  APublic := mFound and (AVisibility in [TIndexVisibility.Public, TIndexVisibility.Published]) and mType.InInterface;
end;

class function TCoveredBy.Methods(const AFileName, AText: string;
  AIncludePrivate: Boolean): TArray<TCoveredMethod>;
var
  mTree: TSyntaxTree;
  mUnit: TUnitIndex;
  mLines: TArray<string>;
  mNode: TSyntaxNode;
  mMethod: TCoveredMethod;
begin
  Result := nil;
  mLines := TTextLines.SplitLines(AText);
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    mUnit := TIndexExtractor.Extract(mTree, AFileName);
    for mNode in BodyNodes(mTree) do
    begin
      if IsDestructor(mLines, mNode) or mNode.IsMethodResolution then
      begin
        Continue;
      end;
      mMethod := Default(TCoveredMethod);
      if not TLspHierarchies.RoutineAt(mTree, AFileName, mNode.StartPos, mMethod.Item) then
      begin
        Continue;
      end;
      mMethod.Item.UnitName := mUnit.UnitName;
      if mMethod.Item.Container <> '' then
      begin
        mMethod.Name := mMethod.Item.Container + '.' + mMethod.Item.Name;
      end
      else
      begin
        mMethod.Name := mMethod.Item.Name;
      end;
      VisibilityOf(mUnit, mMethod.Item, mMethod.Visibility, mMethod.IsPublic);
      if mMethod.IsPublic or AIncludePrivate then
      begin
        Result := Result + [mMethod];
      end;
    end;
  finally
    mTree.Free;
  end;
end;

class function TCoveredBy.IsTestUnit(const AUnitName, AText: string; const AScope: TImpactTestScope): Boolean;
begin
  Result := AScope.Contains(AUnitName) or
    (Length(TDUnitXSource.Scan(TTextLines.SplitLines(AText)).Fixtures) > 0);
end;

class function TCoveredBy.HasTestUnit(const AIndex: ISymbolIndex; const AUnitName: string;
  const AScope: TImpactTestScope): Boolean;
var
  mUnit: TUnitIndex;
begin
  Result := False;
  if (AIndex = nil) or (AUnitName = '') then
  begin
    Exit;
  end;
  for mUnit in AIndex.Units do
  begin
    if not mUnit.Library_ and AScope.Contains(mUnit.UnitName) and
      (IndexText(AUnitName, mUnit.InterfaceUses + mUnit.ImplementationUses) >= 0) then
    begin
      Exit(True);
    end;
  end;
end;

{ Tests je Methode }

/// <summary>Stelle des Tests ATestIndex in AFound.Places; -1, wenn das Symbol selbst der Test ist.</summary>
function PlaceOfTest(const AFound: TImpactResult; ATestIndex: Integer): Integer;
var
  mStep: Integer;
begin
  for mStep := 0 to High(AFound.Places) do
  begin
    if AFound.Places[mStep].Test = ATestIndex then
    begin
      Exit(mStep);
    end;
  end;
  Result := -1;
end;

/// <summary>Ist ein Schritt von der Stelle APlace zurück zum Symbol erschlossen?</summary>
function PathInferred(const AFound: TImpactResult; APlace: Integer): Boolean;
var
  mStep: Integer;
begin
  Result := False;
  mStep := APlace;
  while mStep >= 0 do
  begin
    Result := Result or not AFound.Places[mStep].Confidence.IsSure;
    mStep := AFound.Places[mStep].Cause;
  end;
end;

/// <summary>Tests aus AFound ohne Doppelte, nach Name (ohne Groß-/Kleinschreibung, bei Gleichstand ordinal).
/// </summary>
function TestsOf(const AFound: TImpactResult): TArray<TCoveredTest>;
var
  mIndex: Integer;
  mTest: TCoveredTest;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to High(AFound.Tests) do
    begin
      if mSeen.ContainsKey(UpperCase(AFound.Tests[mIndex].Name)) then
      begin
        Continue;
      end;
      mSeen.Add(UpperCase(AFound.Tests[mIndex].Name), True);
      mTest := Default(TCoveredTest);
      mTest.Name := AFound.Tests[mIndex].Name;
      mTest.RunNames := AFound.Tests[mIndex].RunNames;
      mTest.FileName := AFound.Tests[mIndex].FileName;
      mTest.Line := AFound.Tests[mIndex].Line;
      mTest.Level := AFound.Tests[mIndex].Level;
      mTest.Inferred := PathInferred(AFound, PlaceOfTest(AFound, mIndex));
      Result := Result + [mTest];
    end;
  finally
    mSeen.Free;
  end;
  TArray.Sort<TCoveredTest>(Result, TComparer<TCoveredTest>.Construct(
    function(const A, B: TCoveredTest): Integer
    begin
      Result := CompareText(A.Name, B.Name);
      if Result = 0 then
      begin
        Result := CompareStr(A.Name, B.Name);
      end;
    end));
end;

class function TCoveredBy.Determine(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AFileName, AText: string; const ARequest: TCoveredRequest; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TCoveredResult;
var
  mOptions: TImpactOptions;
  mStarts: TArray<THierarchyItem>;
  mFound: TArray<TImpactResult>;
  mIndex: Integer;
begin
  Result := Default(TCoveredResult);
  mOptions := ARequest.Options;
  mOptions.Depth := TImpactAnalysis.ClampDepth(mOptions.Depth);
  Result.Depth := mOptions.Depth;
  Result.Methods := Methods(AFileName, AText, ARequest.IncludePrivate);
  Result.UnitName := ChangeFileExt(ExtractFileName(AFileName), '');
  if Length(Result.Methods) > 0 then
  begin
    Result.UnitName := Result.Methods[0].Item.UnitName;
  end;
  Result.IsTestUnit := IsTestUnit(Result.UnitName, AText, mOptions.Tests);
  if Result.IsTestUnit then
  begin
    Result.Methods := nil;
    Exit;
  end;
  Result.HasTestUnit := HasTestUnit(AIndex, Result.UnitName, mOptions.Tests);
  mStarts := nil;
  for mIndex := 0 to High(Result.Methods) do
  begin
    mStarts := mStarts + [Result.Methods[mIndex].Item];
  end;
  if mStarts = nil then
  begin
    Exit;
  end;
  mFound := TImpactAnalysis.AnalyzeEach(AResolver, AIndex, mStarts, TImpactSources.Create(ARequest.Files,
    AReadText), mOptions, ACancellation);
  for mIndex := 0 to High(mFound) do
  begin
    Result.Limits := Result.Limits + mFound[mIndex].Limits;
    Result.Methods[mIndex].Tests := TestsOf(mFound[mIndex]);
  end;
  // Die Tiefe ist gewollt, keine Grenze.
  Result.Limits := Result.Limits - [TImpactLimit.Depth];
end;

{ JSON }

class function TCoveredBy.VisibilityName(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Public:
      Result := 'public';
    TIndexVisibility.Published:
      Result := 'published';
    TIndexVisibility.Protected, TIndexVisibility.StrictProtected:
      Result := 'protected';
  else
    Result := 'private';
  end;
end;

function TestJson(const ATest: TCoveredTest): TJSONObject;
var
  mRun: TJSONArray;
  mName: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ATest.Name);
  mRun := TJSONArray.Create;
  Result.AddPair('run', mRun);
  for mName in ATest.RunNames do
  begin
    mRun.Add(mName);
  end;
  Result.AddPair('uri', TDocumentUris.FromPath(ATest.FileName));
  Result.AddPair('line', TJSONNumber.Create(ATest.Line));
  Result.AddPair('level', TJSONNumber.Create(ATest.Level));
  Result.AddPair('inferred', TJSONBool.Create(ATest.Inferred));
end;

function MethodJson(const AMethod: TCoveredMethod): TJSONObject;
var
  mTests: TJSONArray;
  mTest: TCoveredTest;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AMethod.Name);
  Result.AddPair('line', TJSONNumber.Create(AMethod.Line));
  Result.AddPair('character', TJSONNumber.Create(AMethod.Character));
  Result.AddPair('visibility', TCoveredBy.VisibilityName(AMethod.Visibility));
  Result.AddPair('public', TJSONBool.Create(AMethod.IsPublic));
  mTests := TJSONArray.Create;
  Result.AddPair('tests', mTests);
  for mTest in AMethod.Tests do
  begin
    mTests.AddElement(TestJson(mTest));
  end;
end;

class function TCoveredBy.ToJson(const AResult: TCoveredResult): TJSONObject;
var
  mMethods, mLimits: TJSONArray;
  mMethod: TCoveredMethod;
  mLimit: TImpactLimit;
begin
  Result := TJSONObject.Create;
  Result.AddPair('unit', AResult.UnitName);
  Result.AddPair('depth', TJSONNumber.Create(AResult.Depth));
  Result.AddPair('testUnit', TJSONBool.Create(AResult.IsTestUnit));
  Result.AddPair('hasTestUnit', TJSONBool.Create(AResult.HasTestUnit));
  Result.AddPair('tested', TJSONNumber.Create(AResult.Tested));
  Result.AddPair('total', TJSONNumber.Create(Length(AResult.Methods)));
  mMethods := TJSONArray.Create;
  Result.AddPair('methods', mMethods);
  for mMethod in AResult.Methods do
  begin
    mMethods.AddElement(MethodJson(mMethod));
  end;
  mLimits := TJSONArray.Create;
  Result.AddPair('limits', mLimits);
  for mLimit := Low(TImpactLimit) to High(TImpactLimit) do
  begin
    if mLimit in AResult.Limits then
    begin
      mLimits.Add(TImpactAnalysis.LimitName(mLimit));
    end;
  end;
end;

end.
