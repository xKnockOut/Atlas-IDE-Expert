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
  HresultIntegerMixRuleId = 'hresult-integer-mix';

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
  Atlas.Common.Rules.Builtin.TypeChecks.Types;

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
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[Index].Kind = TSyntaxKind.TypeReference then
    begin
      Result := AHeader[Index];
    end;
  end;
end;

/// <summary>Weicht jede Implementierung in AActual von jeder Variante in AExpected ab (HRESULT gegen Integer)?
/// </summary>
function AllInterchanged(const AExpected, AActual: TIndexSymbols): Boolean;
var
  Method, Wanted: TIndexSymbol;
begin
  for Method in AActual do
  begin
    for Wanted in AExpected do
    begin
      if not THresultIntegerMixRule.Interchanged(Wanted.TypeName, Method.TypeName) then
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
  ParamType: string;
begin
  Result := LowerCase(AName) + '(';
  for ParamType in AParamTypes do
  begin
    Result := Result + LowerCase(FResolver.UnqualifyType(NormalizedType(ParamType), FLocal.UnitName)) + ';';
  end;
  Result := Result + ')';
end;

function THresultScan.AlignFix(const AMethod: TIndexSymbol; const AType: string; out AFix: TRuleFix): Boolean;
var
  Node, Declaration, Body, Target: TSyntaxNode;
  Bodies: Integer;
  Edits: TArray<TTextEdit>;
begin
  // Korrektur: Ergebnistyp in Deklaration und (einzigem) Rumpf auf AType setzen.
  Result := False;
  Declaration := nil;
  Body := nil;
  Bodies := 0;
  for Node in FNodes do
  begin
    if (Node.Kind = TSyntaxKind.RoutineHeader) and Covers(Node, AMethod.SelectionRange.StartPos) then
    begin
      Declaration := Node;
    end
    else if (Node.Kind = TSyntaxKind.RoutineDecl) and SameText(Node.Name, FClass.Name + '.' + AMethod.Name) then
    begin
      Inc(Bodies);
      Body := Node.FindChild(TSyntaxKind.RoutineHeader);
    end;
  end;
  if (Declaration = nil) or (Bodies > 1) then
  begin
    Exit;
  end;
  Target := ResultNode(Declaration);
  if Target = nil then
  begin
    Exit;
  end;
  Edits := [TTextEdit.Create(TTextRange.Create(Target.StartPos, Target.EndPos), AType)];
  if Body <> nil then
  begin
    Target := ResultNode(Body);
    // Ein Rumpf ohne Ergebnistyp (function TExport.Schreiben;) bleibt richtig.
    if (Target <> nil) and (Target.StartPos.Line <> Declaration.StartPos.Line) then
    begin
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Target.StartPos, Target.EndPos), AType)];
    end;
  end;
  AFix := TRuleFix.Create(Format('Ergebnistyp %s wie im Interface', [AType]), Edits);
  Result := True;
end;

procedure THresultScan.CollectMethods;
var
  Member: TIndexSymbol;
begin
  // Methoden im Rumpf der Klasse.
  FMethods.Clear;
  for Member in FLocal.Symbols do
  begin
    if SameText(Member.Container, FClass.Name) and (Member.Kind = TIndexSymbolKind.Method) and
      Inside(Member.SelectionRange, FClass.Range) then
    begin
      FMethods.Add(Member);
    end;
  end;
end;

procedure THresultScan.CollectResolutions;
var
  Target: string;
begin
  // Zuordnungen "function IExport.Lesen = LesenIntern" stehen an der Klasse.
  FResolutions.Clear;
  for Target in FClass.Resolutions do
  begin
    FResolutions.Values[LowerCase(Copy(Target, 1, Pos('=', Target) - 1))] := Copy(Target, Pos('=', Target) + 1,
      MaxInt);
  end;
end;

procedure THresultScan.CheckClass(const AClass: TIndexSymbol);
var
  Name: string;
  Ancestor: TResolvedSymbol;
begin
  FClass := AClass;
  FSeen.Clear;
  CollectMethods;
  CollectResolutions;
  for Name in AClass.Ancestors do
  begin
    if FResolver.ResolveTypeFrom(FLocal, Name, Ancestor) and
      (Ancestor.SymbolKind = TIndexSymbolKind.InterfaceType) then
    begin
      CheckInterfaceChain(Ancestor);
    end;
  end;
end;

procedure THresultScan.CheckInterfaceChain(const AInterface: TResolvedSymbol);
var
  Intf, Parent: TResolvedSymbol;
  IntfUnit: TUnitIndex;
  Depth: Integer;
begin
  // Das Interface und seine Vorfahren, jedes nur einmal je Klasse.
  Intf := AInterface;
  for Depth := 0 to cMaxInterfaceDepth do
  begin
    if (FSeen.IndexOf(Intf.QualifiedName) >= 0) or not SymbolUnit(FResolver, FLocal, Intf, IntfUnit) then
    begin
      Break;
    end;
    FSeen.Add(Intf.QualifiedName);
    CheckInterface(Intf, IntfUnit);
    if not FResolver.AncestorOf(Intf, Parent) or (Parent.SymbolKind <> TIndexSymbolKind.InterfaceType) then
    begin
      Break;
    end;
    Intf := Parent;
  end;
end;

procedure THresultScan.CheckInterface(const AInterface: TResolvedSymbol; const AUnit: TUnitIndex);
var
  Member: TIndexSymbol;
begin
  for Member in AUnit.Symbols do
  begin
    if SameText(Member.Container, AInterface.QualifiedName) and (Member.Kind = TIndexSymbolKind.Method) then
    begin
      CheckMember(AInterface, AUnit, Member);
    end;
  end;
end;

function THresultScan.ExpectedVariants(const AUnit: TUnitIndex; const AMember: TIndexSymbol): TIndexSymbols;
var
  Method: TIndexSymbol;
  MemberKey: string;
begin
  // Alle Varianten der Interface-Methode (bedingte Zweige).
  Result := nil;
  MemberKey := Key(AMember.Name, AMember.ParamTypes);
  for Method in AUnit.Symbols do
  begin
    if SameText(Method.Container, AMember.Container) and (Method.Kind = TIndexSymbolKind.Method) and
      (Key(Method.Name, Method.ParamTypes) = MemberKey) then
    begin
      Result := Result + [Method];
    end;
  end;
end;

function THresultScan.ActualVariants(const AInterface: TResolvedSymbol; const AMember: TIndexSymbol): TIndexSymbols;
var
  Method: TIndexSymbol;
  Target, MethodKey: string;
begin
  // Alle Varianten der Implementierung, auch über eine Zuordnung "IFoo.Bar = Baz".
  Result := nil;
  Target := FResolutions.Values[LowerCase(AInterface.Name + '.' + AMember.Name)];
  if Target = '' then
  begin
    Target := AMember.Name;
  end;
  MethodKey := Key(Target, AMember.ParamTypes);
  for Method in FMethods do
  begin
    if Key(Method.Name, Method.ParamTypes) = MethodKey then
    begin
      Result := Result + [Method];
    end;
  end;
end;

procedure THresultScan.CheckMember(const AInterface: TResolvedSymbol; const AUnit: TUnitIndex;
  const AMember: TIndexSymbol);
var
  Expected, Actual: TIndexSymbols;
begin
  Expected := ExpectedVariants(AUnit, AMember);
  // Jede Methode einmal: nur an ihrer ersten Variante.
  if (Length(Expected) = 0) or (Expected[0].SelectionRange.StartPos.Line <> AMember.SelectionRange.StartPos.Line) then
  begin
    Exit;
  end;
  Actual := ActualVariants(AInterface, AMember);
  if (Length(Actual) > 0) and AllInterchanged(Expected, Actual) then
  begin
    ReportMember(AInterface, AMember, Expected, Actual);
  end;
end;

procedure THresultScan.ReportMember(const AInterface: TResolvedSymbol; const AMember: TIndexSymbol; const AExpected,
  AActual: TIndexSymbols);
var
  Method: TIndexSymbol;
  Fix: TRuleFix;
  Fixes: TArray<TRuleFix>;
begin
  for Method in AActual do
  begin
    Fixes := nil;
    if (Length(AExpected) = 1) and (Length(AActual) = 1) and AlignFix(Method, AMember.TypeName, Fix) then
    begin
      Fixes := [Fix];
    end;
    FReport.Add(Method.SelectionRange, Format('%s.%s liefert %s, die Implementierung %s (wie W1008).',
      [AInterface.Name, AMember.Name, AMember.TypeName, Method.TypeName]), TRuleConfidence.High, Fixes);
  end;
end;

{ THresultIntegerMixRule }

function THresultIntegerMixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(HresultIntegerMixRuleId, TRuleSeverity.Warning, 'Integer und HRESULT vertauscht');
end;

/// <summary>1 für HRESULT, 2 für Integer bzw. LongInt, 0 sonst.</summary>
function ResultFamily(const AType: string): Integer;
var
  Name: string;
begin
  Name := Trim(AType);
  Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  if SameText(Name, 'HRESULT') then
  begin
    Result := 1;
  end
  else if SameText(Name, 'Integer') or SameText(Name, 'LongInt') then
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
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Local: TUnitIndex;
  Symbol: TIndexSymbol;
  Scan: THresultScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (not ContainsText(AContext.Text, 'HRESULT') and
    not ContainsText(AContext.Text, 'Integer') and not ContainsText(AContext.Text, 'LongInt')) then
  begin
    Exit;
  end;
  FileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
    Scan := THresultScan.Create(Resolver, Local, PreOrder(AContext.Tree.Root), AReport);
    try
      for Symbol in Local.Symbols do
      begin
        if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Length(Symbol.Ancestors) > 0) then
        begin
          Scan.CheckClass(Symbol);
        end;
      end;
    finally
      Scan.Free;
    end;
  finally
    Resolver.UnpinTree;
  end;
end;

end.
