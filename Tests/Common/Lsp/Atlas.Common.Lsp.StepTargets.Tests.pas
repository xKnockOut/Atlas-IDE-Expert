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
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cHauptFile = 'C:\P\Haupt.pas';
  cBasisFile = 'C:\P\Basis.pas';

  cUnitBasis =
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

  cUnitHaupt =
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHaupt, cHauptFile, nil));
  FResolver := TNameResolver.Create(FIndex);
  FTree := TPascalParser.Parse(cUnitHaupt, nil);
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
  begin
    Result := ACall.Container + '.' + Result;
  end;
  Result := Result + ':' + ACall.Kind;
  if Length(ACall.Targets) = 0 then
  begin
    Result := Result + '!';
  end;
end;

function TLspStepTargetsTests.AnswerAt(const AMarker: string; out AAnswer: TLspStepAnswer): string;
var
  mLines: TArray<string>;
  mLine: Integer;
  mTargets: TLspStepTargets;
  mCall: TLspStepCall;
  mNames: TArray<string>;
begin
  mLines := cUnitHaupt.Split([#10]);
  mLine := 0;
  while (mLine <= High(mLines)) and (Pos(AMarker, mLines[mLine]) = 0) do
  begin
    Inc(mLine);
  end;
  Assert.IsTrue(mLine <= High(mLines), AMarker + ' nicht gefunden');
  mTargets := TLspStepTargets.Create(FResolver, FIndex, FTree, cUnitHaupt, cHauptFile,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, cBasisFile);
      if Result then
      begin
        AText := cUnitBasis;
      end;
    end);
  try
    Assert.IsTrue(mTargets.Answer(mLine, AAnswer));
  finally
    mTargets.Free;
  end;
  mNames := nil;
  for mCall in AAnswer.Calls do
  begin
    mNames := mNames + [Describe(mCall)];
  end;
  Result := string.Join(' ', mNames);
end;

procedure TLspStepTargetsTests.AcceptanceOrderWithGetterAndUnknownFormat;
var
  mAnswer: TLspStepAnswer;
begin
  // Getter vor Format (ohne RTL im Index: ausgegraut), dann Pruefe.
  Assert.AreEqual('TKunde.GetName:getter Format:call! Pruefe:call',
    AnswerAt('Pruefe(Kunde.Name', mAnswer));
  Assert.AreEqual('Kunde.Name', mAnswer.Calls[0].Text);
  Assert.AreEqual('Kunde', mAnswer.Calls[0].Receiver);
  Assert.AreEqual(63, mAnswer.FollowLine);
end;

procedure TLspStepTargetsTests.TargetsPointAtBegin;
var
  mAnswer: TLspStepAnswer;
begin
  AnswerAt('Pruefe(Kunde.Name', mAnswer);
  Assert.AreEqual(1, Integer(Length(mAnswer.Calls[0].Targets)));
  Assert.AreEqual(27, mAnswer.Calls[0].Targets[0].Line);
  Assert.AreEqual(cHauptFile, mAnswer.Calls[0].Targets[0].FileName);
  Assert.AreEqual(51, mAnswer.Calls[2].Targets[0].Line);
  Assert.AreEqual(10, mAnswer.Calls[0].DeclLine);
end;

procedure TLspStepTargetsTests.VirtualCallListsOverrides;
var
  mAnswer: TLspStepAnswer;
begin
  Assert.AreEqual('TKunde.Speichere:call', AnswerAt('  Kunde.Speichere;', mAnswer));
  Assert.IsTrue(mAnswer.Calls[0].IsVirtual);
  Assert.AreEqual(2, Integer(Length(mAnswer.Calls[0].Targets)));
  Assert.AreEqual('TKunde', mAnswer.Calls[0].Targets[0].Container);
  Assert.AreEqual(38, mAnswer.Calls[0].Targets[0].Line);
  Assert.AreEqual('TStammkunde', mAnswer.Calls[0].Targets[1].Container);
  Assert.AreEqual(47, mAnswer.Calls[0].Targets[1].Line);
end;

procedure TLspStepTargetsTests.InterfaceCallListsImplementations;
var
  mAnswer: TLspStepAnswer;
begin
  Assert.AreEqual('IDrucker.Drucke:call', AnswerAt('  D.Drucke;', mAnswer));
  Assert.IsTrue(mAnswer.Calls[0].IsVirtual);
  Assert.IsTrue(mAnswer.Calls[0].ReceiverInterface);
  Assert.AreEqual(1, Integer(Length(mAnswer.Calls[0].Targets)));
  Assert.AreEqual('TKunde', mAnswer.Calls[0].Targets[0].Container);
  Assert.AreEqual(41, mAnswer.Calls[0].Targets[0].Line);
end;

procedure TLspStepTargetsTests.SetterAndFieldAccess;
var
  mAnswer: TLspStepAnswer;
begin
  // Ort liest und schreibt ein Feld: kein Aufruf.
  Assert.AreEqual('TKunde.SetName:setter', AnswerAt('  Kunde.Name := Kunde.Ort;', mAnswer));
  Assert.AreEqual(31, mAnswer.Calls[0].Targets[0].Line);
  Assert.AreEqual('', AnswerAt('  Kunde.Ort := ''x'';', mAnswer));
end;

procedure TLspStepTargetsTests.MethodPointerIntrinsicAndCastSkipped;
var
  mAnswer: TLspStepAnswer;
begin
  // OnClick := Kunde.Klick ist ein Methodenzeiger, Length ein Intrinsic, TButton(T) eine Typumwandlung.
  Assert.AreEqual('', AnswerAt('  TButton(T).OnClick', mAnswer));
  Assert.AreEqual('TKunde.Speichere:call', AnswerAt('  TKunde(T).Speichere;', mAnswer));
end;

procedure TLspStepTargetsTests.ConstructorNestedRoutineAndInherited;
var
  mAnswer: TLspStepAnswer;
begin
  Assert.AreEqual('TKunde.Create:constructor Innen:call', AnswerAt('  Kunde := TKunde.Create; Innen;', mAnswer));
  Assert.AreEqual(34, mAnswer.Calls[0].Targets[0].Line);
  Assert.AreEqual(56, mAnswer.Calls[1].Targets[0].Line);
  Assert.AreEqual('TKunde.Speichere:inherited', AnswerAt('  inherited Speichere;', mAnswer));
  Assert.AreEqual(38, mAnswer.Calls[0].Targets[0].Line);
end;

procedure TLspStepTargetsTests.ReceiverSimpleOnlyWithoutCalls;
var
  mAnswer: TLspStepAnswer;
begin
  AnswerAt('  Kunde.Speichere;', mAnswer);
  Assert.IsTrue(mAnswer.Calls[0].ReceiverSimple);
  AnswerAt('  TKunde(T).Speichere;', mAnswer);
  Assert.IsFalse(mAnswer.Calls[0].ReceiverSimple);
  // Innen ohne Empfänger in einer Routine ohne Klasse: kein Self.
  AnswerAt('  Kunde := TKunde.Create; Innen;', mAnswer);
  Assert.AreEqual('', mAnswer.Calls[1].Receiver);
end;

procedure TLspStepTargetsTests.OtherUnitReadThroughReadText;
var
  mAnswer: TLspStepAnswer;
begin
  Assert.AreEqual('TAblage.Lege:call', AnswerAt('  Ablage.Lege(N);', mAnswer));
  Assert.AreEqual(cBasisFile, mAnswer.Calls[0].Targets[0].FileName);
  Assert.AreEqual(10, mAnswer.Calls[0].Targets[0].Line);
end;

procedure TLspStepTargetsTests.JsonShape;
var
  mJson: TJSONObject;
  mCalls: TJSONArray;
  mCall: TJSONObject;
  mTargets: TLspStepTargets;
begin
  mTargets := TLspStepTargets.Create(FResolver, FIndex, FTree, cUnitHaupt, cHauptFile, nil);
  try
    mJson := mTargets.Execute(63);
  finally
    mTargets.Free;
  end;
  try
    Assert.AreEqual(1, mJson.GetValue<Integer>('format'));
    Assert.AreEqual(63, mJson.GetValue<Integer>('line'));
    Assert.AreEqual(64, mJson.GetValue<Integer>('followLine'));
    mCalls := mJson.GetValue<TJSONArray>('calls');
    Assert.AreEqual(1, mCalls.Count);
    mCall := mCalls.Items[0] as TJSONObject;
    Assert.AreEqual('Speichere', mCall.GetValue<string>('name'));
    Assert.AreEqual('TKunde', mCall.GetValue<string>('container'));
    Assert.IsTrue(mCall.GetValue<Boolean>('virtual'));
    Assert.AreEqual(2, mCall.GetValue<TJSONArray>('targets').Count);
    Assert.AreEqual(38, (mCall.GetValue<TJSONArray>('targets').Items[0] as TJSONObject).GetValue<Integer>('line'));
  finally
    mJson.Free;
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
