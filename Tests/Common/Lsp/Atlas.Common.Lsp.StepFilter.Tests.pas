unit Atlas.Common.Lsp.StepFilter.Tests;

// Tests für die Einordnung der Routinen beim Schrittfilter (#850): Getter und
// Setter (nur mit einer einfachen Anweisung), triviale Routinen, Operatoren,
// leere Konstruktoren und Destruktoren, Namen mit Unit und Klasse, lokale
// Routinen, Deklaration im Klassenkopf, Zählen und JSON.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.StepFilter;

type
  [TestFixture]
  TLspStepFilterTests = class
  private
    FTree: TSyntaxTree;
    function At(ALine: Integer): TLspStepRoutine;
    function KindsAt(ALine: Integer): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TrivialGetterIsGetterAndTrivial;
    [Test]
    procedure GetterWithLogicIsNotFiltered;
    [Test]
    procedure SetterWithOneAssignment;
    [Test]
    procedure TrivialNeedsCallFreeValue;
    [Test]
    procedure AssignmentToParameterIsNotTrivial;
    [Test]
    procedure ExitWithValueIsTrivial;
    [Test]
    procedure ClassOperator;
    [Test]
    procedure EmptyConstructorAndDestructor;
    [Test]
    procedure ConstructorWithWorkIsNotEmpty;
    [Test]
    procedure NamesCarryUnitAndClass;
    [Test]
    procedure NestedRoutineIsInnermost;
    [Test]
    procedure DeclarationInClassUsesImplementation;
    [Test]
    procedure OutsideRoutinesNothing;
    [Test]
    procedure CountsKindsAndPatterns;
    [Test]
    procedure JsonShape;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.StepFilter,
  Atlas.Common.Pascal.Parser;

const
  Source =
    'unit Kunden;'#10 +                                                 // 0
    'interface'#10 +                                                    // 1
    'type'#10 +                                                         // 2
    '  TKunde = class(TBasis)'#10 +                                     // 3
    '  private'#10 +                                                    // 4
    '    FName: string;'#10 +                                           // 5
    '    FAlter: Integer;'#10 +                                         // 6
    '    function GetName: string;'#10 +                                // 7
    '    procedure SetName(const AValue: string);'#10 +                 // 8
    '    function GetTitel: string;'#10 +                               // 9
    '  public'#10 +                                                     // 10
    '    constructor Create(AOwner: TObject);'#10 +                     // 11
    '    destructor Destroy; override;'#10 +                            // 12
    '    property Name: string read GetName write SetName;'#10 +        // 13
    '    property Titel: string read GetTitel;'#10 +                    // 14
    '    function Doppelt(A: Integer): Integer;'#10 +                   // 15
    '    function Gross: string;'#10 +                                  // 16
    '  end;'#10 +                                                       // 17
    '  TBetrag = record'#10 +                                           // 18
    '    class operator Add(A, B: TBetrag): TBetrag;'#10 +              // 19
    '  end;'#10 +                                                       // 20
    'implementation'#10 +                                               // 21
    'function TKunde.GetName: string;'#10 +                             // 22
    'begin'#10 +                                                        // 23
    '  Result := FName;'#10 +                                           // 24
    'end;'#10 +                                                         // 25
    'procedure TKunde.SetName(const AValue: string);'#10 +              // 26
    'begin'#10 +                                                        // 27
    '  FName := AValue;'#10 +                                           // 28
    'end;'#10 +                                                         // 29
    'function TKunde.GetTitel: string;'#10 +                            // 30
    'begin'#10 +                                                        // 31
    '  if FAlter > 60 then'#10 +                                        // 32
    '    Result := ''Senior'';'#10 +                                    // 33
    '  Result := Result + FName;'#10 +                                  // 34
    'end;'#10 +                                                         // 35
    'constructor TKunde.Create(AOwner: TObject);'#10 +                  // 36
    'begin'#10 +                                                        // 37
    '  inherited Create(AOwner);'#10 +                                  // 38
    'end;'#10 +                                                         // 39
    'destructor TKunde.Destroy;'#10 +                                   // 40
    'begin'#10 +                                                        // 41
    '  inherited;'#10 +                                                 // 42
    'end;'#10 +                                                         // 43
    'function TKunde.Doppelt(A: Integer): Integer;'#10 +                // 44
    '  function Mal(B: Integer): Integer;'#10 +                         // 45
    '  begin'#10 +                                                      // 46
    '    Result := B * 2;'#10 +                                         // 47
    '  end;'#10 +                                                       // 48
    'begin'#10 +                                                        // 49
    '  A := Mal(A);'#10 +                                               // 50
    '  Result := A;'#10 +                                               // 51
    'end;'#10 +                                                         // 52
    'function TKunde.Gross: string;'#10 +                               // 53
    'begin'#10 +                                                        // 54
    '  Result := UpperCase(FName);'#10 +                                // 55
    'end;'#10 +                                                         // 56
    'class operator TBetrag.Add(A, B: TBetrag): TBetrag;'#10 +          // 57
    'begin'#10 +                                                        // 58
    '  Result := A;'#10 +                                               // 59
    'end;'#10 +                                                         // 60
    'function Fertig: Boolean;'#10 +                                    // 61
    'begin'#10 +                                                        // 62
    '  Exit(True);'#10 +                                                // 63
    'end;'#10 +                                                         // 64
    'procedure Setze(A: Integer);'#10 +                                 // 65
    'begin'#10 +                                                        // 66
    '  A := 1;'#10 +                                                    // 67
    'end;'#10 +                                                         // 68
    'type'#10 +                                                         // 69
    '  TArbeiter = class'#10 +                                          // 70
    '    constructor Create;'#10 +                                      // 71
    '  end;'#10 +                                                       // 72
    'constructor TArbeiter.Create;'#10 +                                // 73
    'begin'#10 +                                                        // 74
    '  inherited Create;'#10 +                                          // 75
    '  Starte;'#10 +                                                    // 76
    'end;'#10 +                                                         // 77
    'end.';

{ TLspStepFilterTests }

procedure TLspStepFilterTests.Setup;
begin
  FTree := TPascalParser.Parse(Source);
end;

procedure TLspStepFilterTests.TearDown;
begin
  FreeAndNil(FTree);
end;

function TLspStepFilterTests.At(ALine: Integer): TLspStepRoutine;
begin
  Assert.IsTrue(TLspStepFilter.RoutineAt(FTree, Source, ALine, Result), 'Routine an Zeile ' + IntToStr(ALine));
end;

function TLspStepFilterTests.KindsAt(ALine: Integer): string;
begin
  Result := TStepFilterNames.KindsText(At(ALine).Kinds);
end;

procedure TLspStepFilterTests.TrivialGetterIsGetterAndTrivial;
begin
  Assert.AreEqual('getters,trivial', KindsAt(24));
  Assert.AreEqual('getters,trivial', KindsAt(22), 'Kopf der Implementierung');
end;

procedure TLspStepFilterTests.GetterWithLogicIsNotFiltered;
begin
  Assert.AreEqual('', KindsAt(32));
end;

procedure TLspStepFilterTests.SetterWithOneAssignment;
begin
  Assert.AreEqual('setters,trivial', KindsAt(28));
end;

procedure TLspStepFilterTests.TrivialNeedsCallFreeValue;
begin
  Assert.AreEqual('', KindsAt(55), 'UpperCase(FName) ruft auf');
end;

procedure TLspStepFilterTests.AssignmentToParameterIsNotTrivial;
begin
  Assert.AreEqual('', KindsAt(67));
end;

procedure TLspStepFilterTests.ExitWithValueIsTrivial;
begin
  Assert.AreEqual('trivial', KindsAt(63));
end;

procedure TLspStepFilterTests.ClassOperator;
begin
  Assert.AreEqual('trivial,operators', KindsAt(59));
end;

procedure TLspStepFilterTests.EmptyConstructorAndDestructor;
begin
  Assert.AreEqual('emptyConstructors', KindsAt(38));
  Assert.AreEqual('emptyConstructors', KindsAt(42));
end;

procedure TLspStepFilterTests.ConstructorWithWorkIsNotEmpty;
begin
  Assert.AreEqual('', KindsAt(76));
end;

procedure TLspStepFilterTests.NamesCarryUnitAndClass;
var
  mRoutine: TLspStepRoutine;
begin
  mRoutine := At(24);
  Assert.AreEqual('Kunden.TKunde.GetName', mRoutine.Name);
  Assert.AreEqual('TKunde', mRoutine.Container);
  Assert.AreEqual('GetName', mRoutine.Routine);
  Assert.AreEqual(22, mRoutine.StartLine);
  Assert.AreEqual(25, mRoutine.EndLine);
  Assert.AreEqual('Kunden.Fertig', At(63).Name);
  Assert.AreEqual('', At(63).Container);
  Assert.AreEqual('Kunden.TBetrag.Add', At(59).Name);
end;

procedure TLspStepFilterTests.NestedRoutineIsInnermost;
var
  mRoutine: TLspStepRoutine;
begin
  mRoutine := At(47);
  Assert.AreEqual('Kunden.TKunde.Doppelt.Mal', mRoutine.Name);
  Assert.AreEqual('trivial', TStepFilterNames.KindsText(mRoutine.Kinds), 'B * 2 ruft nichts auf');
  Assert.AreEqual('Kunden.TKunde.Doppelt', At(50).Name);
  Assert.AreEqual('', KindsAt(50));
end;

procedure TLspStepFilterTests.DeclarationInClassUsesImplementation;
var
  mRoutine: TLspStepRoutine;
begin
  mRoutine := At(7);
  Assert.AreEqual('Kunden.TKunde.GetName', mRoutine.Name);
  Assert.AreEqual('getters,trivial', TStepFilterNames.KindsText(mRoutine.Kinds));
  Assert.AreEqual('Kunden.TBetrag.Add', At(19).Name);
end;

procedure TLspStepFilterTests.OutsideRoutinesNothing;
var
  mRoutine: TLspStepRoutine;
begin
  Assert.IsFalse(TLspStepFilter.RoutineAt(FTree, Source, 5, mRoutine), 'Feld');
  Assert.IsFalse(TLspStepFilter.RoutineAt(FTree, Source, 13, mRoutine), 'Eigenschaft');
  Assert.IsFalse(TLspStepFilter.RoutineAt(FTree, Source, 21, mRoutine), 'implementation');
end;

procedure TLspStepFilterTests.CountsKindsAndPatterns;
var
  mCounts: TLspStepFilterCounts;
  mPatterns: TArray<string>;
begin
  mPatterns := TArray<string>.Create('TKunde.*', '*.Get*', 'Nirgends.*');
  mCounts := TLspStepFilter.NewCounts(mPatterns);
  TLspStepFilter.AddCounts(FTree, Source, mPatterns, mCounts);
  Assert.AreEqual(1, mCounts.Files);
  Assert.AreEqual(12, mCounts.Routines);
  Assert.AreEqual(1, mCounts.Kinds[TStepFilterKind.Getters]);
  Assert.AreEqual(1, mCounts.Kinds[TStepFilterKind.Setters]);
  Assert.AreEqual(5, mCounts.Kinds[TStepFilterKind.Trivial], 'GetName, SetName, Mal, Add, Fertig');
  Assert.AreEqual(1, mCounts.Kinds[TStepFilterKind.Operators]);
  Assert.AreEqual(2, mCounts.Kinds[TStepFilterKind.EmptyConstructors]);
  Assert.AreEqual(8, mCounts.Patterns[0], 'TKunde.* mit Doppelt.Mal');
  Assert.AreEqual(2, mCounts.Patterns[1]);
  Assert.AreEqual(0, mCounts.Patterns[2]);
end;

procedure TLspStepFilterTests.JsonShape;
var
  mJson: TJSONObject;
  mArguments: TJSONArray;
  mPatterns: TArray<string>;
begin
  mJson := TLspStepFilter.Execute(FTree, Source, 24);
  try
    Assert.AreEqual(1, mJson.GetValue<Integer>('format'));
    Assert.IsTrue(mJson.GetValue<Boolean>('found'));
    Assert.AreEqual('Kunden.TKunde.GetName', mJson.GetValue<string>('name'));
    Assert.AreEqual(22, mJson.GetValue<Integer>('startLine'));
    Assert.AreEqual(25, mJson.GetValue<Integer>('endLine'));
    Assert.AreEqual('["getters","trivial"]', mJson.GetValue<TJSONArray>('kinds').ToJSON);
  finally
    mJson.Free;
  end;
  mJson := TLspStepFilter.Execute(FTree, Source, 1);
  try
    Assert.IsFalse(mJson.GetValue<Boolean>('found'));
    Assert.IsNull(mJson.GetValue('name'));
  finally
    mJson.Free;
  end;
  mArguments := TJSONObject.ParseJSONValue('[["*.Log*", " ", 3, "TKunde.*"]]') as TJSONArray;
  try
    mPatterns := TLspStepFilter.ReadPatterns(mArguments);
    Assert.AreEqual(2, Integer(Length(mPatterns)));
    Assert.AreEqual('TKunde.*', mPatterns[1]);
  finally
    mArguments.Free;
  end;
  mJson := TLspStepFilter.CountsToJson(TLspStepFilter.NewCounts(mPatterns));
  try
    Assert.AreEqual(0, mJson.GetValue<Integer>('kinds.emptyConstructors'));
    Assert.AreEqual('[0,0]', mJson.GetValue<TJSONArray>('patterns').ToJSON);
    Assert.IsFalse(mJson.GetValue<Boolean>('truncated'));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspStepFilterTests);

end.
