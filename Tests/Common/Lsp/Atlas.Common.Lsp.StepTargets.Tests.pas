unit Atlas.Common.Lsp.StepTargets.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.StepTargets;

type
  [TestFixture]
  TLspStepTargetsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    function AnswerAt(const AMarker: string; out AAnswer: TLspStepAnswer): string;
    function Describe(const ACall: TLspStepCall): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AcceptanceOrderWithGetterAndUnknownFormat;
    [Test]
    procedure TargetsPointAtBegin;
    [Test]
    procedure VirtualCallListsOverrides;
    [Test]
    procedure InterfaceCallListsImplementations;
    [Test]
    procedure SetterAndFieldAccess;
    [Test]
    procedure MethodPointerIntrinsicAndCastSkipped;
    [Test]
    procedure ConstructorNestedRoutineAndInherited;
    [Test]
    procedure ReceiverSimpleOnlyWithoutCalls;
    [Test]
    procedure OtherUnitReadThroughReadText;
    [Test]
    procedure JsonShape;
    [Test]
    procedure AccessorAndCastHelpers;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';
  BasisFile = 'C:\P\Basis.pas';

  UnitBasis =
    'unit Basis;'#10 +                                           // 0
    'interface'#10 +                                             // 1
    'type'#10 +                                                  // 2
    '  TAblage = class'#10 +                                     // 3
    '    procedure Lege(A: Integer);'#10 +                       // 4
    '  end;'#10 +                                                // 5
    'implementation'#10 +                                        // 6
    'procedure TAblage.Lege(A: Integer);'#10 +                   // 7
    'var'#10 +                                                   // 8
    '  X: Integer;'#10 +                                         // 9
    'begin'#10 +                                                 // 10
    'end;'#10 +                                                  // 11
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +                                           // 0
    'interface'#10 +                                             // 1
    'uses Basis;'#10 +                                           // 2
    'type'#10 +                                                  // 3
    '  IDrucker = interface'#10 +                                // 4
    '    procedure Drucke;'#10 +                                 // 5
    '  end;'#10 +                                                // 6
    '  TKunde = class(TInterfacedObject, IDrucker)'#10 +        // 7
    '  private'#10 +                                             // 8
    '    FOrt: string;'#10 +                                     // 9
    '    function GetName: string;'#10 +                         // 10
    '    procedure SetName(const AValue: string);'#10 +          // 11
    '  public'#10 +                                              // 12
    '    constructor Create;'#10 +                               // 13
    '    procedure Speichere; virtual;'#10 +                     // 14
    '    procedure Drucke;'#10 +                                 // 15
    '    procedure Klick(Sender: TObject);'#10 +                 // 16
    '    property Name: string read GetName write SetName;'#10 + // 17
    '    property Ort: string read FOrt write FOrt;'#10 +        // 18
    '  end;'#10 +                                                // 19
    '  TStammkunde = class(TKunde)'#10 +                         // 20
    '    procedure Speichere; override;'#10 +                    // 21
    '  end;'#10 +                                                // 22
    'function Pruefe(const S: string): Boolean;'#10 +            // 23
    'procedure Ablauf(Kunde: TKunde; D: IDrucker; Ablage: TAblage);'#10 + // 24
    'implementation'#10 +                                        // 25
    'function TKunde.GetName: string;'#10 +                      // 26
    'begin'#10 +                                                 // 27
    '  Result := FOrt;'#10 +                                     // 28
    'end;'#10 +                                                  // 29
    'procedure TKunde.SetName(const AValue: string);'#10 +       // 30
    'begin'#10 +                                                 // 31
    'end;'#10 +                                                  // 32
    'constructor TKunde.Create;'#10 +                            // 33
    'begin'#10 +                                                 // 34
    '  inherited Create;'#10 +                                   // 35
    'end;'#10 +                                                  // 36
    'procedure TKunde.Speichere;'#10 +                           // 37
    'begin'#10 +                                                 // 38
    'end;'#10 +                                                  // 39
    'procedure TKunde.Drucke;'#10 +                              // 40
    'begin'#10 +                                                 // 41
    'end;'#10 +                                                  // 42
    'procedure TKunde.Klick(Sender: TObject);'#10 +              // 43
    'begin'#10 +                                                 // 44
    'end;'#10 +                                                  // 45
    'procedure TStammkunde.Speichere;'#10 +                      // 46
    'begin'#10 +                                                 // 47
    '  inherited Speichere;'#10 +                                // 48
    'end;'#10 +                                                  // 49
    'function Pruefe(const S: string): Boolean;'#10 +            // 50
    'begin'#10 +                                                 // 51
    '  Result := S <> '''';'#10 +                                // 52
    'end;'#10 +                                                  // 53
    'procedure Ablauf(Kunde: TKunde; D: IDrucker; Ablage: TAblage);'#10 + // 54
    '  procedure Innen;'#10 +                                    // 55
    '  begin'#10 +                                               // 56
    '  end;'#10 +                                                // 57
    'var'#10 +                                                   // 58
    '  N: Integer;'#10 +                                         // 59
    '  T: TObject;'#10 +                                         // 60
    'begin'#10 +                                                 // 61
    '  Pruefe(Kunde.Name + Format(''%d'', [N]));'#10 +           // 62
    '  Kunde.Speichere;'#10 +                                    // 63
    '  D.Drucke;'#10 +                                           // 64
    '  Kunde.Name := Kunde.Ort;'#10 +                            // 65
    '  Kunde.Ort := ''x'';'#10 +                                 // 66
    '  TButton(T).OnClick := Kunde.Klick; N := Length(''a'');'#10 + // 67
    '  Kunde := TKunde.Create; Innen;'#10 +                      // 68
    '  Ablage.Lege(N);'#10 +                                     // 69
    '  TKunde(T).Speichere;'#10 +                                // 70
    'end;'#10 +                                                  // 71
    'end.';

{ TLspStepTargetsTests }

procedure TLspStepTargetsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHaupt, HauptFile, nil));
  FResolver := TNameResolver.Create(FIndex);
  FTree := TPascalParser.Parse(UnitHaupt, nil);
end;

procedure TLspStepTargetsTests.TearDown;
begin
  FreeAndNil(FTree);
  FreeAndNil(FResolver);
  FIndex := nil;
end;

function TLspStepTargetsTests.Describe(const ACall: TLspStepCall): string;
begin
  Result := ACall.Name;
  if ACall.Container <> '' then
    Result := ACall.Container + '.' + Result;
  Result := Result + ':' + ACall.Kind;
  if Length(ACall.Targets) = 0 then
    Result := Result + '!';
end;

function TLspStepTargetsTests.AnswerAt(const AMarker: string; out AAnswer: TLspStepAnswer): string;
var
  Lines: TArray<string>;
  Line: Integer;
  Targets: TLspStepTargets;
  Call: TLspStepCall;
  Names: TArray<string>;
begin
  Lines := UnitHaupt.Split([#10]);
  Line := 0;
  while (Line <= High(Lines)) and (Pos(AMarker, Lines[Line]) = 0) do
    Inc(Line);
  Assert.IsTrue(Line <= High(Lines), AMarker + ' nicht gefunden');
  Targets := TLspStepTargets.Create(FResolver, FIndex, FTree, UnitHaupt, HauptFile,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, BasisFile);
      if Result then
        AText := UnitBasis;
    end);
  try
    Assert.IsTrue(Targets.Answer(Line, AAnswer));
  finally
    Targets.Free;
  end;
  Names := nil;
  for Call in AAnswer.Calls do
    Names := Names + [Describe(Call)];
  Result := string.Join(' ', Names);
end;

procedure TLspStepTargetsTests.AcceptanceOrderWithGetterAndUnknownFormat;
var
  Answer: TLspStepAnswer;
begin
  // Getter vor Format (ohne RTL im Index: ausgegraut), dann Pruefe.
  Assert.AreEqual('TKunde.GetName:getter Format:call! Pruefe:call',
    AnswerAt('Pruefe(Kunde.Name', Answer));
  Assert.AreEqual('Kunde.Name', Answer.Calls[0].Text);
  Assert.AreEqual('Kunde', Answer.Calls[0].Receiver);
  Assert.AreEqual(63, Answer.FollowLine);
end;

procedure TLspStepTargetsTests.TargetsPointAtBegin;
var
  Answer: TLspStepAnswer;
begin
  AnswerAt('Pruefe(Kunde.Name', Answer);
  Assert.AreEqual(1, Integer(Length(Answer.Calls[0].Targets)));
  Assert.AreEqual(27, Answer.Calls[0].Targets[0].Line);
  Assert.AreEqual(HauptFile, Answer.Calls[0].Targets[0].FileName);
  Assert.AreEqual(51, Answer.Calls[2].Targets[0].Line);
  Assert.AreEqual(10, Answer.Calls[0].DeclLine);
end;

procedure TLspStepTargetsTests.VirtualCallListsOverrides;
var
  Answer: TLspStepAnswer;
begin
  Assert.AreEqual('TKunde.Speichere:call', AnswerAt('  Kunde.Speichere;', Answer));
  Assert.IsTrue(Answer.Calls[0].IsVirtual);
  Assert.AreEqual(2, Integer(Length(Answer.Calls[0].Targets)));
  Assert.AreEqual('TKunde', Answer.Calls[0].Targets[0].Container);
  Assert.AreEqual(38, Answer.Calls[0].Targets[0].Line);
  Assert.AreEqual('TStammkunde', Answer.Calls[0].Targets[1].Container);
  Assert.AreEqual(47, Answer.Calls[0].Targets[1].Line);
end;

procedure TLspStepTargetsTests.InterfaceCallListsImplementations;
var
  Answer: TLspStepAnswer;
begin
  Assert.AreEqual('IDrucker.Drucke:call', AnswerAt('  D.Drucke;', Answer));
  Assert.IsTrue(Answer.Calls[0].IsVirtual);
  Assert.IsTrue(Answer.Calls[0].ReceiverInterface);
  Assert.AreEqual(1, Integer(Length(Answer.Calls[0].Targets)));
  Assert.AreEqual('TKunde', Answer.Calls[0].Targets[0].Container);
  Assert.AreEqual(41, Answer.Calls[0].Targets[0].Line);
end;

procedure TLspStepTargetsTests.SetterAndFieldAccess;
var
  Answer: TLspStepAnswer;
begin
  // Ort liest und schreibt ein Feld: kein Aufruf.
  Assert.AreEqual('TKunde.SetName:setter', AnswerAt('  Kunde.Name := Kunde.Ort;', Answer));
  Assert.AreEqual(31, Answer.Calls[0].Targets[0].Line);
  Assert.AreEqual('', AnswerAt('  Kunde.Ort := ''x'';', Answer));
end;

procedure TLspStepTargetsTests.MethodPointerIntrinsicAndCastSkipped;
var
  Answer: TLspStepAnswer;
begin
  // OnClick := Kunde.Klick ist ein Methodenzeiger, Length ein Intrinsic, TButton(T) eine Typumwandlung.
  Assert.AreEqual('', AnswerAt('  TButton(T).OnClick', Answer));
  Assert.AreEqual('TKunde.Speichere:call', AnswerAt('  TKunde(T).Speichere;', Answer));
end;

procedure TLspStepTargetsTests.ConstructorNestedRoutineAndInherited;
var
  Answer: TLspStepAnswer;
begin
  Assert.AreEqual('TKunde.Create:constructor Innen:call', AnswerAt('  Kunde := TKunde.Create; Innen;', Answer));
  Assert.AreEqual(34, Answer.Calls[0].Targets[0].Line);
  Assert.AreEqual(56, Answer.Calls[1].Targets[0].Line);
  Assert.AreEqual('TKunde.Speichere:inherited', AnswerAt('  inherited Speichere;', Answer));
  Assert.AreEqual(38, Answer.Calls[0].Targets[0].Line);
end;

procedure TLspStepTargetsTests.ReceiverSimpleOnlyWithoutCalls;
var
  Answer: TLspStepAnswer;
begin
  AnswerAt('  Kunde.Speichere;', Answer);
  Assert.IsTrue(Answer.Calls[0].ReceiverSimple);
  AnswerAt('  TKunde(T).Speichere;', Answer);
  Assert.IsFalse(Answer.Calls[0].ReceiverSimple);
  // Innen ohne Empfänger in einer Routine ohne Klasse: kein Self.
  AnswerAt('  Kunde := TKunde.Create; Innen;', Answer);
  Assert.AreEqual('', Answer.Calls[1].Receiver);
end;

procedure TLspStepTargetsTests.OtherUnitReadThroughReadText;
var
  Answer: TLspStepAnswer;
begin
  Assert.AreEqual('TAblage.Lege:call', AnswerAt('  Ablage.Lege(N);', Answer));
  Assert.AreEqual(BasisFile, Answer.Calls[0].Targets[0].FileName);
  Assert.AreEqual(10, Answer.Calls[0].Targets[0].Line);
end;

procedure TLspStepTargetsTests.JsonShape;
var
  Json: TJSONObject;
  Calls: TJSONArray;
  Call: TJSONObject;
begin
  Json := TLspStepTargets.Execute(FResolver, FIndex, FTree, UnitHaupt, HauptFile, 63, nil);
  try
    Assert.AreEqual(1, Json.GetValue<Integer>('format'));
    Assert.AreEqual(63, Json.GetValue<Integer>('line'));
    Assert.AreEqual(64, Json.GetValue<Integer>('followLine'));
    Calls := Json.GetValue<TJSONArray>('calls');
    Assert.AreEqual(1, Calls.Count);
    Call := Calls.Items[0] as TJSONObject;
    Assert.AreEqual('Speichere', Call.GetValue<string>('name'));
    Assert.AreEqual('TKunde', Call.GetValue<string>('container'));
    Assert.IsTrue(Call.GetValue<Boolean>('virtual'));
    Assert.AreEqual(2, Call.GetValue<TJSONArray>('targets').Count);
    Assert.AreEqual(38, (Call.GetValue<TJSONArray>('targets').Items[0] as TJSONObject).GetValue<Integer>('line'));
  finally
    Json.Free;
  end;
end;

procedure TLspStepTargetsTests.AccessorAndCastHelpers;
begin
  Assert.AreEqual('GetName', TLspStepTargets.Accessor('property Name: string read GetName write SetName;', False));
  Assert.AreEqual('SetName', TLspStepTargets.Accessor('property Name: string read GetName write SetName;', True));
  Assert.AreEqual('', TLspStepTargets.Accessor('property Name: string read GetName;', True));
  Assert.IsTrue(TLspStepTargets.LooksLikeCast('TButton'));
  Assert.IsTrue(TLspStepTargets.LooksLikeCast('IDrucker'));
  Assert.IsFalse(TLspStepTargets.LooksLikeCast('Pruefe'));
  Assert.IsFalse(TLspStepTargets.LooksLikeCast('TrimRight'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspStepTargetsTests);

end.
