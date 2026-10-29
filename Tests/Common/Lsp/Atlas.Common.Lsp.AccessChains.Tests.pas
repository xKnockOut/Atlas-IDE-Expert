unit Atlas.Common.Lsp.AccessChains.Tests;

// Zugriffsketten am Ausführungspunkt (#865): Zerlegung in Glieder (ohne letztes Mitglied, ohne Records,
// Units, Typen und Namen vor einem Aufruf), implizites Self, Getter und Aufrufe, Index dynamischer Arrays,
// mehrere Anweisungen in einer Zeile, Köpfe zusammengesetzter Anweisungen, Feldversätze unter Win32 und Win64
// und die JSON-Antwort.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.AccessChains;

type
  [TestFixture]
  TLspAccessChainsTests = class
  private
    FIndex: ISymbolIndex;
    function Chains(ALine: Integer): TAccessChainsResult; overload;
    function Chains(ALine, APointerSize: Integer): TAccessChainsResult; overload;
    /// <summary>„Ausdruck:Art:Typ[:call][:self][:idx=I][:plain]“ je Glied, Ketten mit „ | “ getrennt.</summary>
    function Describe(ALine: Integer): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SplitsMemberChainWithoutLastMember;
    [Test]
    procedure FieldWithoutSelfStartsWithSelf;
    [Test]
    procedure DynamicArrayIndex;
    [Test]
    procedure GetterMarksCallAndFollowingLinks;
    [Test]
    procedure SeveralStatementsInOneLine;
    [Test]
    procedure ConditionOfIfStatement;
    [Test]
    procedure PointerDereferenceAndRecords;
    [Test]
    procedure NoLinksForUnitsTypesAndPlainVariables;
    [Test]
    procedure NoImplicitSelfInsideWith;
    [Test]
    procedure FieldOffsetsWin32AndWin64;
    [Test]
    procedure NamePositionAndRange;
    [Test]
    procedure JsonAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver;

const
  UnitText =
    'unit Kunden;'#10 +                                          // 0
    'interface'#10 +                                             // 1
    'type'#10 +                                                  // 2
    '  TAdresse = class'#10 +                                    // 3
    '    FStrasse: string;'#10 +                                 // 4
    '    FOrt: string;'#10 +                                     // 5
    '  end;'#10 +                                                // 6
    '  TKunde = class'#10 +                                      // 7
    '    FName: string;'#10 +                                    // 8
    '    FAlter: Integer;'#10 +                                  // 9
    '    FAdresse: TAdresse;'#10 +                               // 10
    '    function GetAdresse: TAdresse;'#10 +                    // 11
    '    property Adresse: TAdresse read FAdresse;'#10 +         // 12
    '    property Haus: TAdresse read GetAdresse;'#10 +          // 13
    '  end;'#10 +                                                // 14
    '  TKunden = array of TKunde;'#10 +                          // 15
    '  TPunkt = record X, Y: Integer; end;'#10 +                 // 16
    '  PPunkt = ^TPunkt;'#10 +                                   // 17
    '  TAuftrag = class'#10 +                                    // 18
    '    FNummer: Integer;'#10 +                                 // 19
    '    FKunde: TKunde;'#10 +                                   // 20
    '    FPositionen: TKunden;'#10 +                             // 21
    '    FPunkt: TPunkt;'#10 +                                   // 22
    '    property Kunde: TKunde read FKunde;'#10 +               // 23
    '    procedure Pruefe;'#10 +                                 // 24
    '  end;'#10 +                                                // 25
    'implementation'#10 +                                        // 26
    'function TKunde.GetAdresse: TAdresse;'#10 +                 // 27
    'begin'#10 +                                                 // 28
    '  Result := FAdresse;'#10 +                                 // 29
    'end;'#10 +                                                  // 30
    'procedure TAuftrag.Pruefe;'#10 +                            // 31
    'var'#10 +                                                   // 32
    '  Auftrag: TAuftrag;'#10 +                                  // 33
    '  I, Zahl: Integer;'#10 +                                   // 34
    '  P: PPunkt;'#10 +                                          // 35
    'begin'#10 +                                                 // 36
    '  Auftrag.Kunde.Adresse.FOrt := ''Berlin'';'#10 +           // 37
    '  FKunde.FName := ''X'';'#10 +                              // 38
    '  FPositionen[I].FName := ''Y'';'#10 +                      // 39
    '  Auftrag.Kunde.Haus.FOrt := ''Z'';'#10 +                   // 40
    '  Zahl := 1; Auftrag.FNummer := 2;'#10 +                    // 41
    '  if Auftrag.Kunde.FAlter > 0 then'#10 +                    // 42
    '    Zahl := 3;'#10 +                                        // 43
    '  P^.X := FPunkt.Y;'#10 +                                   // 44
    '  Zahl := SysUtils.StrToInt(''1'') + I;'#10 +               // 45
    '  FPositionen[Zahl + 1].FAlter := Length(FPositionen);'#10 + // 46
    '  with Auftrag do FNummer := 1;'#10 +                       // 47
    'end;'#10 +                                                  // 48
    'end.';

  FileName = 'C:\P\Kunden.pas';

{ TLspAccessChainsTests }

procedure TLspAccessChainsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
end;

procedure TLspAccessChainsTests.TearDown;
begin
  FIndex := nil;
end;

function TLspAccessChainsTests.Chains(ALine: Integer): TAccessChainsResult;
begin
  Result := Chains(ALine, 4);
end;

function TLspAccessChainsTests.Chains(ALine, APointerSize: Integer): TAccessChainsResult;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(UnitText);
  Resolver := TNameResolver.Create(FIndex);
  try
    Result := TLspAccessChains.Collect(Resolver, FIndex, nil, Tree, UnitText, FileName, ALine, APointerSize);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function TLspAccessChainsTests.Describe(ALine: Integer): string;
var
  Found: TAccessChainsResult;
  Chain: TAccessChain;
  Link: TAccessLink;
  Part: string;
begin
  Result := '';
  Found := Chains(ALine);
  for Chain in Found.Chains do
  begin
    if Result <> '' then
      Result := Result + ' | ';
    Part := '';
    for Link in Chain.Links do
    begin
      if Part <> '' then
        Part := Part + ' ';
      Part := Part + Link.Expression + ':' + TLspAccessChains.KindName(Link.Kind) + ':' + Link.TypeName;
      if Link.Call then
        Part := Part + ':call';
      if Link.ImplicitSelf then
        Part := Part + ':self';
      if Link.IndexText <> '' then
        Part := Part + ':idx=' + Link.IndexText;
      if Link.IndexPlain then
        Part := Part + ':plain';
    end;
    Result := Result + Part;
  end;
end;

procedure TLspAccessChainsTests.SplitsMemberChainWithoutLastMember;
begin
  Assert.AreEqual('Auftrag:class:TAuftrag Auftrag.Kunde:class:TKunde Auftrag.Kunde.Adresse:class:TAdresse',
    Describe(37));
end;

procedure TLspAccessChainsTests.FieldWithoutSelfStartsWithSelf;
begin
  Assert.AreEqual('Self:class:TAuftrag:self FKunde:class:TKunde', Describe(38));
end;

procedure TLspAccessChainsTests.DynamicArrayIndex;
begin
  Assert.AreEqual('Self:class:TAuftrag:self FPositionen:dynArray:TKunden:idx=I:plain FPositionen[I]:class:TKunde',
    Describe(39));
  // Ausdruck als Index ohne Aufruf ist auswertbar; Length(...) rechts ist ein Aufruf ohne Glieder.
  Assert.AreEqual('Self:class:TAuftrag:self FPositionen:dynArray:TKunden:idx=Zahl + 1:plain ' +
    'FPositionen[Zahl + 1]:class:TKunde | Self:class:TAuftrag:self', Describe(46));
end;

procedure TLspAccessChainsTests.GetterMarksCallAndFollowingLinks;
begin
  Assert.AreEqual('Auftrag:class:TAuftrag Auftrag.Kunde:class:TKunde Auftrag.Kunde.Haus:class:TAdresse:call',
    Describe(40));
end;

procedure TLspAccessChainsTests.SeveralStatementsInOneLine;
var
  Found: TAccessChainsResult;
begin
  Found := Chains(41);
  Assert.AreEqual(2, Found.Statements);
  Assert.AreEqual('Auftrag:class:TAuftrag', Describe(41));
end;

procedure TLspAccessChainsTests.ConditionOfIfStatement;
var
  Found: TAccessChainsResult;
begin
  Found := Chains(42);
  Assert.AreEqual(1, Found.Statements);
  Assert.AreEqual('Auftrag:class:TAuftrag Auftrag.Kunde:class:TKunde', Describe(42));
  // Die Zuweisung im then-Zweig steht in der nächsten Zeile.
  Assert.AreEqual(1, Chains(43).Statements);
  Assert.AreEqual('', Describe(43));
end;

procedure TLspAccessChainsTests.PointerDereferenceAndRecords;
begin
  // P^ ist der Record hinter dem Zeiger, FPunkt ein Record-Feld (Self wird gelesen, FPunkt nicht dereferenziert).
  Assert.AreEqual('P:pointer:PPunkt | Self:class:TAuftrag:self', Describe(44));
end;

procedure TLspAccessChainsTests.NoLinksForUnitsTypesAndPlainVariables;
begin
  Assert.AreEqual('', Describe(45));
end;

procedure TLspAccessChainsTests.NoImplicitSelfInsideWith;
begin
  // FNummer gehört zu Auftrag (with), nicht zu Self; das with-Element selbst wird dereferenziert.
  Assert.AreEqual(2, Chains(47).Statements);
  Assert.AreEqual('Auftrag:class:TAuftrag', Describe(47));
  Assert.AreEqual('with', Chains(47).Chains[0].Links[0].Member);
end;

procedure TLspAccessChainsTests.FieldOffsetsWin32AndWin64;
var
  Found: TAccessChainsResult;
  Fields: TArray<TAccessField>;
begin
  Found := Chains(37, 4);
  Fields := Found.Chains[0].Links[1].Fields;
  Assert.AreEqual(3, Integer(Length(Fields)));
  Assert.AreEqual('FName', Fields[0].Name);
  Assert.AreEqual(4, Fields[0].Offset);
  Assert.AreEqual(8, Fields[1].Offset);
  Assert.AreEqual('FAdresse', Fields[2].Name);
  Assert.AreEqual($C, Fields[2].Offset);
  Found := Chains(37, 8);
  Fields := Found.Chains[0].Links[1].Fields;
  Assert.AreEqual(8, Fields[0].Offset);
  Assert.AreEqual(16, Fields[1].Offset);
  Assert.AreEqual(24, Fields[2].Offset);
  // Record-Feld mit unbekannter Größe: dahinter keine Schätzung mehr.
  Fields := Chains(38, 4).Chains[0].Links[0].Fields;
  Assert.AreEqual(4, Integer(Length(Fields)));
  Assert.AreEqual(8, Fields[1].Offset);
  Assert.AreEqual(12, Fields[2].Offset);
  Assert.AreEqual(-1, Fields[3].Offset);
  Fields := nil;
end;

procedure TLspAccessChainsTests.NamePositionAndRange;
var
  Link: TAccessLink;
begin
  Link := Chains(37).Chains[0].Links[1];
  Assert.AreEqual('Kunde', Link.Name);
  Assert.AreEqual('Adresse', Link.Member);
  Assert.AreEqual(37, Link.NamePosition.Line);
  Assert.AreEqual(10, Link.NamePosition.Character);
  Assert.AreEqual(2, Link.Range.StartPos.Character);
  Assert.AreEqual(15, Link.Range.EndPos.Character);
  // Implizites Self: Bereich und Name des Felds.
  Link := Chains(38).Chains[0].Links[0];
  Assert.AreEqual('FKunde', Link.Member);
  Assert.AreEqual(2, Link.Range.StartPos.Character);
  Assert.AreEqual(8, Link.Range.EndPos.Character);
end;

procedure TLspAccessChainsTests.JsonAnswer;
var
  Json: TJSONObject;
  Chains_, Links: TJSONArray;
  Link: TJSONObject;
begin
  Json := TLspAccessChains.ToJson(Chains(39));
  try
    Assert.AreEqual(1, Json.GetValue<Integer>('statements'));
    Chains_ := Json.GetValue('chains') as TJSONArray;
    Assert.AreEqual(1, Integer(Chains_.Count));
    Assert.AreEqual('FPositionen[I].FName', (Chains_.Items[0] as TJSONObject).GetValue<string>('text'));
    Links := (Chains_.Items[0] as TJSONObject).GetValue('links') as TJSONArray;
    Assert.AreEqual(3, Integer(Links.Count));
    Link := Links.Items[1] as TJSONObject;
    Assert.AreEqual('FPositionen', Link.GetValue<string>('expression'));
    Assert.AreEqual('dynArray', Link.GetValue<string>('kind'));
    Assert.AreEqual('I', Link.GetValue<string>('index'));
    Assert.IsTrue(Link.GetValue<Boolean>('indexPlain'));
    Assert.IsFalse(Link.GetValue<Boolean>('call'));
    Link := Links.Items[0] as TJSONObject;
    Assert.IsTrue(Link.GetValue<Boolean>('implicitSelf'));
    Assert.AreEqual(4, Integer((Link.GetValue('fields') as TJSONArray).Count));
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspAccessChainsTests);

end.
