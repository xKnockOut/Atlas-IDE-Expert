unit Atlas.Common.Semantics.UnresolvedNames.Tests;

// Tests für nicht auflösbare Bezeichner (#178, MCP check_code); TextFile und
// die alte object-Syntax mit New/Dispose/Fail (#1382).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TUnresolvedNamesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Names(const AText: string): string;
    /// <summary>Wie Names, je Eintrag mit Code und object-Typ: "Anlegen=E2601/TAltObjekt;".</summary>
    function Coded(const AText: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReportsUnknownName;
    [Test]
    procedure KnowsLocalsUsesAndIntrinsics;
    /// <summary>#1239: Variable aus for var … in mit begin … end.</summary>
    [Test]
    procedure KnowsForInVariableInBlock;
    [Test]
    procedure SkipsWithAndExceptionVariables;
    /// <summary>Typparameter der Klasse gelten in den Rümpfen ihrer Methoden, auch in class function und als
    /// Argument von TypeInfo, SizeOf und GetTypeKind (TComparer&lt;T&gt; aus System.Generics.Defaults).</summary>
    [Test]
    procedure KnowsTypeParametersInGenericMethodBodies;
    [Test]
    procedure NeedsSystemUnit;
    [Test]
    procedure RuleReportsInEditorOnlyWithIndex;
    [Test]
    procedure KnowsCastsUnitPrefixesAndNestedTypes;
    [Test]
    procedure KnowsMembersOfStrictNestedTypes;
    [Test]
    procedure SkipsNamesWithUnknownAncestor;
    [Test]
    procedure UsesKnownNeedsEveryUnit;
    [Test]
    procedure KnowsTextFile;
    [Test]
    procedure KnowsFileRoutines;
    [Test]
    procedure KnowsOldObjectSyntax;
    [Test]
    procedure ReportsMissingConstructorAndDestructor;
    [Test]
    procedure ReportsFailOutsideConstructor;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin.Unresolved;

const
  UnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  Integer = -2147483648..2147483647;'#10 +
    '  TObject = class'#10 +
    '  end;'#10 +
    '  Exception = class(TObject)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'procedure Melde(A: Integer);'#10 +
    'implementation'#10 +
    'procedure Melde(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

procedure TUnresolvedNamesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSystem, 'C:\Lib\System.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TUnresolvedNamesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TUnresolvedNamesTests.Names(const AText: string): string;
var
  Tree: TSyntaxTree;
  Name: TUnresolvedName;
begin
  Result := '';
  Tree := TPascalParser.Parse(AText);
  try
    for Name in TUnresolvedNames.Find(FResolver, Tree, 'C:\P\Haupt.pas') do
      Result := Result + Name.Name + Format('@%d:%d;', [Name.Range.StartPos.Line, Name.Range.StartPos.Character]);
  finally
    Tree.Free;
  end;
end;

function TUnresolvedNamesTests.Coded(const AText: string): string;
var
  mTree: TSyntaxTree;
  mName: TUnresolvedName;
begin
  Result := '';
  mTree := TPascalParser.Parse(AText);
  try
    for mName in TUnresolvedNames.Find(FResolver, mTree, 'C:\P\Haupt.pas') do
      Result := Result + Format('%s=%s/%s;', [mName.Name, mName.Code, mName.Owner]);
  finally
    mTree.Free;
  end;
end;

/// <summary>Unit mit object-Typ wie in den Fällen Cm.E2601/Cm.E2602; ABody steht in der Routine Fall.</summary>
function ObjectUnit(const ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'type'#10'  TAltObjekt = object'#10'    Wert: Integer;'#10 +
    '    constructor Init;'#10'    destructor Done;'#10'  end;'#10'  PAltObjekt = ^TAltObjekt;'#10 +
    '  PZahl = ^Integer;'#10'implementation'#10'constructor TAltObjekt.Init;'#10'begin'#10'end;'#10 +
    'destructor TAltObjekt.Done;'#10'begin'#10'end;'#10'procedure Fall;'#10'var'#10'  mObjekt: PAltObjekt;'#10 +
    '  mZahl: PZahl;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TUnresolvedNamesTests.KnowsTextFile;
begin
  // Fälle Cm.E2002, Cm.E2071, Cm.E2538: TextFile kommt vom Compiler, nicht aus System.pas.
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'var'#10 +
    '  mDatei: TextFile;'#10 +
    'begin'#10 +
    '  mDatei := Default(TextFile);'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsFileRoutines;
begin
  // AssignFile, Append, CloseFile & Co. kommen wie TextFile vom Compiler, nicht aus System.pas (#1382).
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure AppendToLog(const AText: string);'#10 +
    'var'#10 +
    '  FileName: string;'#10 +
    '  Log: TextFile;'#10 +
    '  Daten: file;'#10 +
    'begin'#10 +
    '  AssignFile(Log, FileName);'#10 +
    '  {$I-}'#10 +
    '  Append(Log);'#10 +
    '  {$I+}'#10 +
    '  if IOResult <> 0 then'#10 +
    '    Exit;'#10 +
    '  try'#10 +
    '    Writeln(Log, AText);'#10 +
    '    Flush(Log);'#10 +
    '  finally'#10 +
    '    CloseFile(Log);'#10 +
    '  end;'#10 +
    '  Assign(Daten, FileName);'#10 +
    '  Reset(Daten, 1);'#10 +
    '  Seek(Daten, FileSize(Daten) - FilePos(Daten));'#10 +
    '  Truncate(Daten);'#10 +
    '  Close(Daten);'#10 +
    '  Rewrite(Log);'#10 +
    '  if Eof(Log) or Eoln(Log) or SeekEof(Log) or SeekEoln(Log) then'#10 +
    '    Erase(Daten);'#10 +
    '  Rename(Daten, AText);'#10 +
    'end;'#10 +
    'procedure Speicher;'#10 +
    'var'#10 +
    '  P: Pointer;'#10 +
    '  V: OleVariant;'#10 +
    'begin'#10 +
    '  GetMem(P, 16);'#10 +
    '  ReallocMem(P, 32);'#10 +
    '  FreeMem(P);'#10 +
    '  if Sqrt(Int(2.5)) + Frac(1.5) + Sin(0) + Cos(0) + ArcTan(1) + Ln(1) + Exp(0) < 0 then'#10 +
    '    RunError(1);'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsOldObjectSyntax;
begin
  // New(P, Init) und Dispose(P, Done): Konstruktor und Destruktor sind keine eigenen Bezeichner (Cm.E2602).
  Assert.AreEqual('', Coded(ObjectUnit('  New(mObjekt, Init);'#10'  Dispose(mObjekt, Done);'#10 +
    '  mObjekt := New(PAltObjekt, Init);'#10)));
  // Kein object-Typ hinter dem Zeiger (Cm.E2079, Cm.E2080): das melden andere Regeln (E2467, E2019).
  Assert.AreEqual('', Coded(ObjectUnit('  New(mZahl, Init);'#10'  Dispose(mZahl, Done);'#10)));
  // Fail im Konstruktor.
  Assert.AreEqual('', Coded('unit Haupt;'#10'interface'#10'type'#10'  TAltObjekt = object'#10 +
    '    constructor Init;'#10'  end;'#10'implementation'#10'constructor TAltObjekt.Init;'#10'begin'#10'  Fail;'#10 +
    'end;'#10'end.'));
end;

procedure TUnresolvedNamesTests.ReportsMissingConstructorAndDestructor;
begin
  // Fälle Cm.E2601 und Cm.E2602: Delphi 13 meldet E2601 bzw. E2602, nicht E2003.
  Assert.AreEqual('Anlegen=E2601/TAltObjekt;', Coded(ObjectUnit('  New(mObjekt, Anlegen);'#10)));
  Assert.AreEqual('Abbauen=E2602/TAltObjekt;', Coded(ObjectUnit('  New(mObjekt, Init);'#10 +
    '  Dispose(mObjekt, Abbauen);'#10)));
end;

procedure TUnresolvedNamesTests.ReportsFailOutsideConstructor;
var
  mTree: TSyntaxTree;
  mFound: TArray<TUnresolvedName>;
begin
  // Fall Cm.E2078.
  mTree := TPascalParser.Parse('unit Haupt;'#10'interface'#10'implementation'#10'procedure Fall;'#10'begin'#10 +
    '  Fail;'#10'end;'#10'end.');
  try
    mFound := TUnresolvedNames.Find(FResolver, mTree, 'C:\P\Haupt.pas');
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual('E2078', mFound[0].Code);
    Assert.AreEqual('Fail ist nur im Konstruktor eines object-Typs erlaubt (wie E2078).',
      TUnresolvedNames.Describe(mFound[0]));
    Assert.AreEqual(5, mFound[0].Range.StartPos.Line);
  finally
    mTree.Free;
    mFound := nil;
  end;
end;

procedure TUnresolvedNamesTests.RuleReportsInEditorOnlyWithIndex;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  fdsfds.Create;'#10 +
    'end;'#10 +
    'end.';
var
  Registry: TRuleRegistry;
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Findings: TArray<TRuleFinding>;
begin
  Registry := TRuleRegistry.Create;
  Tree := TPascalParser.Parse(Text);
  try
    RegisterUnresolvedRules(Registry);
    Context := Default(TRuleContext);
    Context.RelativePath := 'Haupt.pas';
    Context.Text := Text;
    Context.Tree := Tree;
    // Ohne Index (Linter): keine Aussage.
    Findings := TRuleEngine.Run(Registry.Rules, TServerSettings.Default, Context);
    Assert.AreEqual(0, Integer(Length(Findings)));
    Context.Index := FIndex;
    Findings := TRuleEngine.Run(Registry.Rules, TServerSettings.Default, Context);
    Assert.AreEqual(1, Integer(Length(Findings)));
    Assert.AreEqual('unresolved-identifier', Findings[0].RuleId);
    Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
    Assert.Contains(Findings[0].Message, 'fdsfds');
  finally
    Tree.Free;
    Registry.Free;
  end;
end;

procedure TUnresolvedNamesTests.ReportsUnknownName;
begin
  Assert.AreEqual('Unbekannt@5:2;', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  Unbekannt(1);'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsLocalsUsesAndIntrinsics;
begin
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Basis;'#10 +
    'function P(A: Integer): Integer;'#10 +
    'var'#10 +
    '  B: Integer;'#10 +
    'begin'#10 +
    '  B := A;'#10 +
    '  Inc(B);'#10 +
    '  Melde(Length(''x'') + B);'#10 +
    '  Result := B;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsForInVariableInBlock;
begin
  // #1239: for var X in … do begin … end; die Variable gilt im ganzen Rumpf.
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P(const AWerte: TArray<string>);'#10 +
    'begin'#10 +
    '  for var mKunde in AWerte do'#10 +
    '  begin'#10 +
    '    Writeln(mKunde);'#10 +
    '  end;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.SkipsWithAndExceptionVariables;
begin
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P(O: TObject);'#10 +
    'begin'#10 +
    '  with O do'#10 +
    '    Feld := 1;'#10 +
    '  try'#10 +
    '  except'#10 +
    '    on E: Exception do'#10 +
    '      raise E;'#10 +
    '  end;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsTypeParametersInGenericMethodBodies;
begin
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IComparer<T> = interface'#10 +
    '    function Compare(const Left, Right: T): Integer;'#10 +
    '  end;'#10 +
    '  TComparer<T> = class(TObject, IComparer<T>)'#10 +
    '  protected'#10 +
    '    class function TryUseRecEqualityOperator: Pointer;'#10 +
    '    class function _Default: Pointer;'#10 +
    '  public'#10 +
    '    function Compare(const Left, Right: T): Integer; virtual; abstract;'#10 +
    '  end;'#10 +
    '  TPaar<TKey, TValue> = class'#10 +
    '    procedure Lauf;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'class function TComparer<T>.TryUseRecEqualityOperator: Pointer;'#10 +
    'var'#10 +
    '  pEQ: Pointer;'#10 +
    'begin'#10 +
    '  pEQ := TypeInfo(T);'#10 +
    '  if pEQ <> nil then'#10 +
    '    Result := Pointer(SizeOf(T))'#10 +
    '  else'#10 +
    '    Result := nil;'#10 +
    'end;'#10 +
    'class function TComparer<T>._Default: Pointer;'#10 +
    'begin'#10 +
    '  if (GetTypeKind(T) = GetTypeKind(Integer)) and (TypeInfo(T) <> nil) then'#10 +
    '    Exit(TryUseRecEqualityOperator);'#10 +
    '  Result := Pointer(SizeOf(T));'#10 +
    'end;'#10 +
    'procedure TPaar<TKey, TValue>.Lauf;'#10 +
    'var'#10 +
    '  mSchluessel: TKey;'#10 +
    'begin'#10 +
    '  mSchluessel := Default(TKey);'#10 +
    '  if SizeOf(TValue) = SizeOf(TKey) then'#10 +
    '    mSchluessel := TKey(nil);'#10 +
    'end;'#10 +
    'end.'));
  // Ein Name, der kein Typparameter ist, bleibt unbekannt.
  Assert.AreEqual('U@9:19;', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBox<T> = class'#10 +
    '    class function Groesse: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'class function TBox<T>.Groesse: Integer;'#10 +
    'begin'#10 +
    '  Result := SizeOf(U);'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsCastsUnitPrefixesAndNestedTypes;
begin
  // Fehlalarme aus der Problemliste zu Atlas selbst (#647).
  FIndex.AddUnit(TIndexExtractor.ExtractText(
    'unit Werk.Hilfe;'#10 +
    'interface'#10 +
    'procedure Hilf;'#10 +
    'implementation'#10 +
    'procedure Hilf;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.', 'C:\P\Werk.Hilfe.pas', nil));
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAussen = class'#10 +
    '  type'#10 +
    '    TInnen = class'#10 +
    '    private'#10 +
    '      FWert: Integer;'#10 +
    '      procedure Lauf;'#10 +
    '    end;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'uses Werk.Hilfe;'#10 +
    'procedure TAussen.TInnen.Lauf;'#10 +
    'var'#10 +
    '  P: PChar;'#10 +
    'begin'#10 +
    '  FWert := Integer(MaxInt);'#10 +
    '  P := PChar(''x'');'#10 +
    '  AtomicIncrement(FWert);'#10 +
    '  Werk.Hilfe.Hilf;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsMembersOfStrictNestedTypes;
begin
  // Code-Review F-02: Der Kopf TAussen.TInnen.Lauf wurde mit den Sichtbarkeitsregeln des Rumpfs aufgelöst;
  // für TInnen in strict private fragte IsVisible nach der Klasse der Methode, die gerade ermittelt wurde,
  // und die Rekursion lief bis zum Stapelüberlauf. Jetzt gilt der Pfad im Kopf unabhängig von der
  // Sichtbarkeit, und die strict-Mitglieder sind im eigenen Rumpf bekannt.
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAussen = class'#10 +
    '  strict private'#10 +
    '    type'#10 +
    '      TInnen = class'#10 +
    '      strict private'#10 +
    '        FWert: Integer;'#10 +
    '        procedure Lauf;'#10 +
    '      end;'#10 +
    '  strict protected'#10 +
    '    type'#10 +
    '      TGeschuetzt = class'#10 +
    '      strict protected'#10 +
    '        FZahl: Integer;'#10 +
    '        procedure Zaehle;'#10 +
    '      end;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TAussen.TInnen.Lauf;'#10 +
    'begin'#10 +
    '  FWert := 1;'#10 +
    '  Lauf;'#10 +
    'end;'#10 +
    'procedure TAussen.TGeschuetzt.Zaehle;'#10 +
    'begin'#10 +
    '  FZahl := FZahl + 1;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.SkipsNamesWithUnknownAncestor;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFenster = class(TFremd)'#10 +
    '    procedure Male;'#10 +
    '  end;'#10 +
    '  TEigen = class'#10 +
    '    procedure Male;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'uses Basis;'#10 +
    'procedure TFenster.Male;'#10 +
    'begin'#10 +
    '  Melde(ClientWidth);'#10 +
    'end;'#10 +
    'procedure TEigen.Male;'#10 +
    'begin'#10 +
    '  Melde(ClientWidth);'#10 +
    'end;'#10 +
    'end.';
begin
  // TFremd steht nicht im Index: ClientWidth kann geerbt sein (#647). In TEigen ist es sicher unbekannt.
  Assert.AreEqual('ClientWidth@17:8;', Names(Text));
end;

procedure TUnresolvedNamesTests.NeedsSystemUnit;
var
  Empty: ISymbolIndex;
begin
  Assert.IsTrue(TUnresolvedNames.Available(FIndex));
  Empty := TSymbolIndex.Create;
  Assert.IsFalse(TUnresolvedNames.Available(Empty));
  Assert.IsTrue(TUnresolvedNames.IsIntrinsic('writeln'));
  // Aus TSystemIntrinsics (#880), früher als „nicht deklariert“ gemeldet.
  Assert.IsTrue(TUnresolvedNames.IsIntrinsic('Sqr'));
  Assert.IsTrue(TUnresolvedNames.IsIntrinsic('Pi'));
  Assert.IsFalse(TUnresolvedNames.IsIntrinsic('GibtEsNicht'));
end;

procedure TUnresolvedNamesTests.UsesKnownNeedsEveryUnit;
var
  Asked: string;
begin
  // Für unresolved-attribute und xmldoc-mismatch (#979): auch über Namespaces und nachgeladene Units.
  Assert.IsTrue(TUnresolvedNames.UsesKnown(FIndex, ['System', 'Basis'], nil, nil));
  Assert.IsFalse(TUnresolvedNames.UsesKnown(FIndex, ['Basis', 'Fremd'], nil, nil));
  Assert.IsTrue(TUnresolvedNames.UsesKnown(FIndex, ['Fremd'], nil,
    function(const AUnitName: string): Boolean
    begin
      Asked := AUnitName;
      Result := True;
    end));
  Assert.AreEqual('Fremd', Asked);
  Assert.IsFalse(TUnresolvedNames.UsesKnown(FIndex, ['Lib'], ['Fremd'], nil));
  Asked := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TUnresolvedNamesTests);

end.
