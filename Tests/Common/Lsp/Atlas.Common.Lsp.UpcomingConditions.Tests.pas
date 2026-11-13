unit Atlas.Common.Lsp.UpcomingConditions.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.UpcomingConditions;

type
  [TestFixture]
  TLspUpcomingConditionsTests = class
  private
    FTree: TSyntaxTree;
    function LineOf(const AMarker: string): Integer;
    function Blocks(const AMarker: string; ALines: Integer): TLspUpcomingBlocks;
    function Kinds(const ABlocks: TLspUpcomingBlocks): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CallInBranchHidesFieldConditionsAfterIt;
    [Test]
    procedure AssignmentBeforeConditionHidesIt;
    [Test]
    procedure CaseBranchesWithLabelsRangesAndElse;
    [Test]
    procedure ExitStopsLookingAhead;
    [Test]
    procedure VarArgumentAndCallHideConditions;
    [Test]
    procedure LinesLimitTheLookAhead;
    [Test]
    procedure InsideLoopBodyLooksNoFurther;
    [Test]
    procedure IfBranchesAndJsonShape;
    [Test]
    procedure ClampLines;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.TreeCache;

const
  Source =
    'unit Vorschau;'#10 +                                        // 0
    'interface'#10 +                                             // 1
    'implementation'#10 +                                        // 2
    'procedure TSender.Senden;'#10 +                             // 3
    'var'#10 +                                                   // 4
    '  mOffen: Integer;'#10 +                                    // 5
    '  mText: string;'#10 +                                      // 6
    'begin'#10 +                                                 // 7
    '  mOffen := FQueue.Count; // Halt'#10 +                     // 8
    '  if (mOffen > 0) and FOnline then // Wenn'#10 +            // 9
    '    SendQueue // Dann'#10 +                                 // 10
    '  else'#10 +                                                // 11
    '    Log(''nichts''); // Sonst'#10 +                         // 12
    '  case FMode of // Fall'#10 +                               // 13
    '    smAuto: Reschedule;'#10 +                               // 14
    '    smManual: ;'#10 +                                       // 15
    '    1..3, 7: mText := '''';'#10 +                           // 16
    '  else'#10 +                                                // 17
    '    mText := ''x'';'#10 +                                   // 18
    '  end;'#10 +                                                // 19
    '  while mOffen > 0 do // Solange'#10 +                      // 20
    '    Dec(mOffen); // Schleife'#10 +                          // 21
    'end;'#10 +                                                  // 22
    'procedure Zwei;'#10 +                                       // 23
    'begin'#10 +                                                 // 24
    '  if A then Exit; // Sprung'#10 +                           // 25
    '  if B then C; // NachSprung'#10 +                          // 26
    'end;'#10 +                                                  // 27
    'procedure Drei;'#10 +                                       // 28
    'var'#10 +                                                   // 29
    '  mWert: Integer;'#10 +                                     // 30
    'begin'#10 +                                                 // 31
    '  Lies(mWert); // VarArg'#10 +                              // 32
    '  if mWert > 0 then Zeige;'#10 +                            // 33
    '  if mAnders then Zeige;'#10 +                              // 34
    'end;'#10 +                                                  // 35
    'end.';

{ TLspUpcomingConditionsTests }

procedure TLspUpcomingConditionsTests.Setup;
begin
  FTree := TSyntaxTreeCache.Parse(Source);
end;

procedure TLspUpcomingConditionsTests.TearDown;
begin
  FreeAndNil(FTree);
end;

function TLspUpcomingConditionsTests.LineOf(const AMarker: string): Integer;
var
  Lines: TArray<string>;
begin
  Lines := Source.Split([#10]);
  Result := 0;
  while (Result <= High(Lines)) and (Pos(AMarker, Lines[Result]) = 0) do
  begin
    Inc(Result);
  end;
  Assert.IsTrue(Result <= High(Lines), AMarker + ' nicht gefunden');
end;

function TLspUpcomingConditionsTests.Blocks(const AMarker: string; ALines: Integer): TLspUpcomingBlocks;
var
  Conditions: TLspUpcomingConditions;
begin
  Conditions := TLspUpcomingConditions.Create(FTree, Source, nil);
  try
    Result := Conditions.Answer(LineOf(AMarker), ALines);
  finally
    Conditions.Free;
  end;
end;

function TLspUpcomingConditionsTests.Kinds(const ABlocks: TLspUpcomingBlocks): string;
var
  Block: TLspUpcomingBlock;
  Texts: TArray<string>;
begin
  Texts := nil;
  for Block in ABlocks do
  begin
    Texts := Texts + [Format('%s@%d', [Block.Kind, Block.Line])];
  end;
  Result := string.Join(' ', Texts);
end;

procedure TLspUpcomingConditionsTests.CallInBranchHidesFieldConditionsAfterIt;
begin
  // Halt auf dem if: es selbst zählt; SendQueue/Log darin können FMode ändern, mOffen nicht.
  Assert.AreEqual('if@9 while@20', Kinds(Blocks('// Wenn', 0)));
end;

procedure TLspUpcomingConditionsTests.AssignmentBeforeConditionHidesIt;
begin
  // Die Zuweisung an mOffen steht noch aus: if und while hängen davon ab, case folgt auf Aufrufe.
  Assert.AreEqual('', Kinds(Blocks('// Halt', 0)));
end;

procedure TLspUpcomingConditionsTests.CaseBranchesWithLabelsRangesAndElse;
var
  Answer: TLspUpcomingBlocks;
  Block: TLspUpcomingBlock;
begin
  Answer := Blocks('// Fall', 0);
  Assert.AreEqual('case@13 while@20', Kinds(Answer));
  Block := Answer[0];
  Assert.AreEqual(6, Integer(Length(Block.Parts)));
  Assert.AreEqual('FMode', Block.Parts[0].Text);
  Assert.AreEqual('smAuto', Block.Parts[1].Text);
  Assert.AreEqual('1', Block.Parts[3].Text);
  Assert.AreEqual('3', Block.Parts[4].Text);
  Assert.AreEqual(4, Integer(Length(Block.Branches)));
  Assert.AreEqual('item', Block.Branches[2].Name);
  Assert.AreEqual(2, Integer(Length(Block.Branches[2].Labels)));
  Assert.AreEqual(3, Block.Branches[2].Labels[0][0]);
  Assert.AreEqual(4, Block.Branches[2].Labels[0][1]);
  Assert.AreEqual(5, Block.Branches[2].Labels[1][0]);
  Assert.AreEqual(-1, Block.Branches[2].Labels[1][1]);
  Assert.AreEqual('else', Block.Branches[3].Name);
  Assert.AreEqual(14, Block.Branches[0].FromLine);
  Assert.AreEqual(18, Block.Branches[3].ToLine);
end;

procedure TLspUpcomingConditionsTests.ExitStopsLookingAhead;
begin
  Assert.AreEqual('if@25', Kinds(Blocks('// Sprung', 0)));
end;

procedure TLspUpcomingConditionsTests.VarArgumentAndCallHideConditions;
begin
  // mWert kann als var-Argument geändert sein, mAnders ist keine lokale Variable.
  Assert.AreEqual('', Kinds(Blocks('// VarArg', 0)));
end;

procedure TLspUpcomingConditionsTests.LinesLimitTheLookAhead;
begin
  Assert.AreEqual('if@9', Kinds(Blocks('// Wenn', 5)));
end;

procedure TLspUpcomingConditionsTests.InsideLoopBodyLooksNoFurther;
begin
  Assert.AreEqual('', Kinds(Blocks('// Schleife', 0)));
end;

procedure TLspUpcomingConditionsTests.IfBranchesAndJsonShape;
var
  Answer: TLspUpcomingBlocks;
  Json: TJSONObject;
  Item: TJSONObject;
begin
  Answer := Blocks('// Wenn', 0);
  Assert.AreEqual('then', Answer[0].Branches[0].Name);
  Assert.AreEqual(10, Answer[0].Branches[0].FromLine);
  Assert.AreEqual('else', Answer[0].Branches[1].Name);
  Assert.AreEqual(12, Answer[0].Branches[1].FromLine);
  Assert.AreEqual('and', Answer[0].Parts[0].Kind);
  Json := TLspUpcomingConditions.ToJson(Answer);
  try
    Assert.AreEqual(1, (Json.GetValue('format') as TJSONNumber).AsInt);
    Item := (Json.GetValue('blocks') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('if', Item.GetValue('kind').Value);
    Assert.AreEqual(2, Integer((Item.GetValue('branches') as TJSONArray).Count));
    Assert.IsTrue((Item.GetValue('parts') as TJSONArray).Count >= 3);
  finally
    Json.Free;
  end;
end;

procedure TLspUpcomingConditionsTests.ClampLines;
begin
  Assert.AreEqual(TLspUpcomingConditions.cDefaultLines, TLspUpcomingConditions.ClampLines(0));
  Assert.AreEqual(TLspUpcomingConditions.cMaxLines, TLspUpcomingConditions.ClampLines(1000));
  Assert.AreEqual(7, TLspUpcomingConditions.ClampLines(7));
end;

end.
