unit Atlas.Common.Rules.Builtin.TypeChecks.Hresult;

// Typprüfung hresult-integer-mix (#1040), registriert mit den übrigen Typprüfungen (RegisterTypeCheckRules):
//   Eine Klasse der Datei implementiert eine Interface-Methode mit HRESULT-Ergebnis über eine Methode mit
//   Integer-Ergebnis oder umgekehrt (wie W1008; die Delphi-Hilfe nennt X1008). Zugeordnet wird über Name und
//   Parametertypen samt Zuordnungen "IFoo.Bar = Baz"; Interfaces samt ihren Vorfahren kommen aus Datei bzw. Index.
//   Stehen Varianten in bedingten Zweigen, meldet die Regel nur, wenn jede Variante abweicht. Korrektur: den
//   Ergebnistyp in Deklaration und Rumpf an das Interface angleichen.

interface

uses
  Atlas.Common.Rules.Contract;

const
  cHresultIntegerMixRuleId = 'hresult-integer-mix';

type
  THresultIntegerMixRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist das eine Ergebnis HRESULT und das andere Integer (bzw. LongInt)?</summary>
    class function Interchanged(const AExpected, AActual: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.TypeChecks.Types,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeChecksHresultText = (ResultLikeInterface, Mismatch, Title);

const
  cTexts: array[TTypeChecksHresultText] of TAtlasText = (
    (De: 'Ergebnistyp %s wie im Interface'; En: 'Result type %s as in the interface'),
    (De: '%s.%s liefert %s, die Implementierung %s (wie W1008).';
     En: '%s.%s returns %s, the implementation %s (like W1008).'),
    (De: 'Integer und HRESULT vertauscht'; En: 'Integer and HRESULT swapped'));

{$SCOPEDENUMS OFF}

const
  cMaxInterfaceDepth = 16;

type
  TIndexSymbols = TArray<TIndexSymbol>;

  /// <summary>Prüft die Klassen einer Datei gegen die Ergebnistypen ihrer Interfaces.</summary>
  THresultScan = class
  private
    FResolver: TNameResolver;
    FLocal: TUnitIndex;
    FNodes: TArray<TSyntaxNode>;
    FReport: IRuleReport;
    /// <summary>Geprüfte Klasse, ihre Methoden und ihre Zuordnungen "IExport.Lesen=LesenIntern".</summary>
    FClass: TIndexSymbol;
    FMethods: TList<TIndexSymbol>;
    FResolutions: TStringList;
    FSeen: TStringList;
    function Key(const AName: string; const AParamTypes: TArray<string>): string;
    function AlignFix(const AMethod: TIndexSymbol; const AType: string; out AFix: TRuleFix): Boolean;
    procedure CollectMethods;
    procedure CollectResolutions;
    procedure CheckInterfaceChain(const AInterface: TResolvedSymbol);
    procedure CheckInterface(const AInterface: TResolvedSymbol; const AUnit: TUnitIndex);
    function ExpectedVariants(const AUnit: TUnitIndex; const AMember: TIndexSymbol): TIndexSymbols;
    function ActualVariants(const AInterface: TResolvedSymbol; const AMember: TIndexSymbol): TIndexSymbols;
    procedure CheckMember(const AInterface: TResolvedSymbol; const AUnit: TUnitIndex; const AMember: TIndexSymbol);
    procedure ReportMember(const AInterface: TResolvedSymbol; const AMember: TIndexSymbol; const AExpected,
      AActual: TIndexSymbols);
  public
    constructor Create(AResolver: TNameResolver; const ALocal: TUnitIndex; const ANodes: TArray<TSyntaxNode>;
      const AReport: IRuleReport);
    destructor Destroy; override;
    procedure CheckClass(const AClass: TIndexSymbol);
  end;

/// <summary>Liegt ARange (Zeile des Anfangs) in AOuter?</summary>
function Inside(const ARange, AOuter: TTextRange): Boolean;
begin
  Result := (ARange.StartPos.Line >= AOuter.StartPos.Line) and (ARange.StartPos.Line <= AOuter.EndPos.Line);
end;

/// <summary>Ergebnistyp im Kopf (letzter Typverweis); nil ohne.</summary>
function ResultNode(AHeader: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Result := AHeader[mIndex];
    end;
  end;
end;

/// <summary>Weicht jede Implementierung in AActual von jeder Variante in AExpected ab (HRESULT gegen Integer)?
/// </summary>
function AllInterchanged(const AExpected, AActual: TIndexSymbols): Boolean;
var
  mMethod, mWanted: TIndexSymbol;
begin
  for mMethod in AActual do
  begin
    for mWanted in AExpected do
    begin
      if not THresultIntegerMixRule.Interchanged(mWanted.TypeName, mMethod.TypeName) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

{ THresultScan }

constructor THresultScan.Create(AResolver: TNameResolver; const ALocal: TUnitIndex;
  const ANodes: TArray<TSyntaxNode>; const AReport: IRuleReport);
begin
  inherited Create;
  FResolver := AResolver;
  FLocal := ALocal;
  FNodes := ANodes;
  FReport := AReport;
  FMethods := TList<TIndexSymbol>.Create;
  FResolutions := TStringList.Create;
  FSeen := TStringList.Create;
end;

destructor THresultScan.Destroy;
begin
  FSeen.Free;
  FResolutions.Free;
  FMethods.Free;
  inherited Destroy;
end;

function THresultScan.Key(const AName: string; const AParamTypes: TArray<string>): string;
var
  mParamType: string;
begin
  Result := LowerCase(AName) + '(';
  for mParamType in AParamTypes do
  begin
    Result := Result + LowerCase(FResolver.Queries.UnqualifyType(NormalizedType(mParamType), FLocal.UnitName)) + ';';
  end;
  Result := Result + ')';
end;

function THresultScan.AlignFix(const AMethod: TIndexSymbol; const AType: string; out AFix: TRuleFix): Boolean;
var
  mNode, mDeclaration, mBody, mTarget: TSyntaxNode;
  mBodies: Integer;
  mEdits: TArray<TTextEdit>;
begin
  // Korrektur: Ergebnistyp in Deklaration und (einzigem) Rumpf auf AType setzen.
  Result := False;
  mDeclaration := nil;
  mBody := nil;
  mBodies := 0;
  for mNode in FNodes do
  begin
    if (mNode.Kind = TSyntaxKind.RoutineHeader) and Covers(mNode, AMethod.SelectionRange.StartPos) then
    begin
      mDeclaration := mNode;
    end
    else if (mNode.Kind = TSyntaxKind.RoutineDecl) and SameText(mNode.Name, FClass.Name + '.' + AMethod.Name) then
    begin
      Inc(mBodies);
      mBody := mNode.FindChild(TSyntaxKind.RoutineHeader);
    end;
  end;
  if (mDeclaration = nil) or (mBodies > 1) then
  begin
    Exit;
  end;
  mTarget := ResultNode(mDeclaration);
  if mTarget = nil then
  begin
    Exit;
  end;
  mEdits := [TTextEdit.Create(TTextRange.Create(mTarget.StartPos, mTarget.EndPos), AType)];
  if mBody <> nil then
  begin
    mTarget := ResultNode(mBody);
    // Ein Rumpf ohne Ergebnistyp (function TExport.Schreiben;) bleibt richtig.
    if (mTarget <> nil) and (mTarget.StartPos.Line <> mDeclaration.StartPos.Line) then
    begin
      mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mTarget.StartPos, mTarget.EndPos), AType)];
    end;
  end;
  AFix := TRuleFix.Create(cTexts[TTypeChecksHresultText.ResultLikeInterface].Fmt([AType]), mEdits);
  Result := True;
end;

procedure THresultScan.CollectMethods;
var
  mMember: TIndexSymbol;
begin
  // Methoden im Rumpf der Klasse.
  FMethods.Clear;
  for mMember in FLocal.Symbols do
  begin
    if SameText(mMember.Container, FClass.Name) and (mMember.Kind = TIndexSymbolKind.Method) and
      Inside(mMember.SelectionRange, FClass.Range) then
    begin
      FMethods.Add(mMember);
    end;
  end;
end;

procedure THresultScan.CollectResolutions;
var
  mTarget: string;
begin
  // Zuordnungen "function IExport.Lesen = LesenIntern" stehen an der Klasse.
  FResolutions.Clear;
  for mTarget in FClass.Resolutions do
  begin
    FResolutions.Values[LowerCase(Copy(mTarget, 1, Pos('=', mTarget) - 1))] := Copy(mTarget, Pos('=', mTarget) + 1,
      MaxInt);
  end;
end;

procedure THresultScan.CheckClass(const AClass: TIndexSymbol);
var
  mName: string;
  mAncestor: TResolvedSymbol;
begin
  FClass := AClass;
  FSeen.Clear;
  CollectMethods;
  CollectResolutions;
  for mName in AClass.Ancestors do
  begin
    if FResolver.ResolveTypeFrom(FLocal, mName, mAncestor) and
      (mAncestor.SymbolKind = TIndexSymbolKind.InterfaceType) then
    begin
      CheckInterfaceChain(mAncestor);
    end;
  end;
end;

procedure THresultScan.CheckInterfaceChain(const AInterface: TResolvedSymbol);
var
  mIntf, mParent: TResolvedSymbol;
  mIntfUnit: TUnitIndex;
  mDepth: Integer;
begin
  // Das Interface und seine Vorfahren, jedes nur einmal je Klasse.
  mIntf := AInterface;
  for mDepth := 0 to cMaxInterfaceDepth do
  begin
    if (FSeen.IndexOf(mIntf.QualifiedName) >= 0) or not SymbolUnit(FResolver, FLocal, mIntf, mIntfUnit) then
    begin
      Break;
    end;
    FSeen.Add(mIntf.QualifiedName);
    CheckInterface(mIntf, mIntfUnit);
    if not FResolver.AncestorOf(mIntf, mParent) or (mParent.SymbolKind <> TIndexSymbolKind.InterfaceType) then
    begin
      Break;
    end;
    mIntf := mParent;
  end;
end;

procedure THresultScan.CheckInterface(const AInterface: TResolvedSymbol; const AUnit: TUnitIndex);
var
  mMember: TIndexSymbol;
begin
  for mMember in AUnit.Symbols do
  begin
    if SameText(mMember.Container, AInterface.QualifiedName) and (mMember.Kind = TIndexSymbolKind.Method) then
    begin
      CheckMember(AInterface, AUnit, mMember);
    end;
  end;
end;

function THresultScan.ExpectedVariants(const AUnit: TUnitIndex; const AMember: TIndexSymbol): TIndexSymbols;
var
  mMethod: TIndexSymbol;
  mMemberKey: string;
begin
  // Alle Varianten der Interface-Methode (bedingte Zweige).
  Result := nil;
  mMemberKey := Key(AMember.Name, AMember.ParamTypes);
  for mMethod in AUnit.Symbols do
  begin
    if SameText(mMethod.Container, AMember.Container) and (mMethod.Kind = TIndexSymbolKind.Method) and
      (Key(mMethod.Name, mMethod.ParamTypes) = mMemberKey) then
    begin
      Result := Result + [mMethod];
    end;
  end;
end;

function THresultScan.ActualVariants(const AInterface: TResolvedSymbol; const AMember: TIndexSymbol): TIndexSymbols;
var
  mMethod: TIndexSymbol;
  mTarget, mMethodKey: string;
begin
  // Alle Varianten der Implementierung, auch über eine Zuordnung "IFoo.Bar = Baz".
  Result := nil;
  mTarget := FResolutions.Values[LowerCase(AInterface.Name + '.' + AMember.Name)];
  if mTarget = '' then
  begin
    mTarget := AMember.Name;
  end;
  mMethodKey := Key(mTarget, AMember.ParamTypes);
  for mMethod in FMethods do
  begin
    if Key(mMethod.Name, mMethod.ParamTypes) = mMethodKey then
    begin
      Result := Result + [mMethod];
    end;
  end;
end;

procedure THresultScan.CheckMember(const AInterface: TResolvedSymbol; const AUnit: TUnitIndex;
  const AMember: TIndexSymbol);
var
  mExpected, mActual: TIndexSymbols;
begin
  mExpected := ExpectedVariants(AUnit, AMember);
  // Jede Methode einmal: nur an ihrer ersten Variante.
  if (Length(mExpected) = 0) or (mExpected[0].SelectionRange.StartPos.Line <> AMember.SelectionRange.StartPos.Line) then
  begin
    Exit;
  end;
  mActual := ActualVariants(AInterface, AMember);
  if (Length(mActual) > 0) and AllInterchanged(mExpected, mActual) then
  begin
    ReportMember(AInterface, AMember, mExpected, mActual);
  end;
end;

procedure THresultScan.ReportMember(const AInterface: TResolvedSymbol; const AMember: TIndexSymbol; const AExpected,
  AActual: TIndexSymbols);
var
  mMethod: TIndexSymbol;
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  for mMethod in AActual do
  begin
    mFixes := nil;
    if (Length(AExpected) = 1) and (Length(AActual) = 1) and AlignFix(mMethod, AMember.TypeName, mFix) then
    begin
      mFixes := [mFix];
    end;
    FReport.Add(mMethod.SelectionRange, cTexts[TTypeChecksHresultText.Mismatch].Fmt(
      [AInterface.Name, AMember.Name, AMember.TypeName, mMethod.TypeName]), TRuleConfidence.High, mFixes);
  end;
end;

{ THresultIntegerMixRule }

function THresultIntegerMixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cHresultIntegerMixRuleId, TRuleSeverity.Warning,
    cTexts[TTypeChecksHresultText.Title].Text);
end;

/// <summary>1 für HRESULT, 2 für Integer bzw. LongInt, 0 sonst.</summary>
function ResultFamily(const AType: string): Integer;
var
  mName: string;
begin
  mName := Trim(AType);
  mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  if SameText(mName, 'HRESULT') then
  begin
    Result := 1;
  end
  else if SameText(mName, 'Integer') or SameText(mName, 'LongInt') then
  begin
    Result := 2;
  end
  else
  begin
    Result := 0;
  end;
end;

class function THresultIntegerMixRule.Interchanged(const AExpected, AActual: string): Boolean;
begin
  Result := (ResultFamily(AExpected) <> 0) and (ResultFamily(AActual) <> 0) and
    (ResultFamily(AExpected) <> ResultFamily(AActual));
end;

procedure THresultIntegerMixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mLocal: TUnitIndex;
  mSymbol: TIndexSymbol;
  mScan: THresultScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (not ContainsText(AContext.Text, 'HRESULT') and
    not ContainsText(AContext.Text, 'Integer') and not ContainsText(AContext.Text, 'LongInt')) then
  begin
    Exit;
  end;
  mFileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    mLocal := mResolver.ExtractedUnit(AContext.Tree, mFileName);
    mScan := THresultScan.Create(mResolver, mLocal, PreOrder(AContext.Tree.Root), AReport);
    try
      for mSymbol in mLocal.Symbols do
      begin
        if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (Length(mSymbol.Ancestors) > 0) then
        begin
          mScan.CheckClass(mSymbol);
        end;
      end;
    finally
      mScan.Free;
    end;
  finally
    mResolver.UnpinTree;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeChecks.Hresult', cTexts);

end.
