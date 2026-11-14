unit Atlas.Common.Lsp.UpcomingConditions.Tests;

interface

uses
  DUnitX.TestFramework,
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
  cSource =
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
  FTree := TSyntaxTreeCache.Parse(cSource);
end;

procedure TLspUpcomingConditionsTests.TearDown;
begin
  FreeAndNil(FTree);
end;

function TLspUpcomingConditionsTests.LineOf(const AMarker: string): Integer;
var
  mLines: TArray<string>;
begin
  mLines := cSource.Split([#10]);
  Result := 0;
  while (Result <= High(mLines)) and (Pos(AMarker, mLines[Result]) = 0) do
  begin
    Inc(Result);
  end;
  Assert.IsTrue(Result <= High(mLines), AMarker + ' nicht gefunden');
end;

function TLspUpcomingConditionsTests.Blocks(const AMarker: string; ALines: Integer): TLspUpcomingBlocks;
var
  mConditions: TLspUpcomingConditions;
begin
  mConditions := TLspUpcomingConditions.Create(FTree, cSource, nil);
  try
    Result := mConditions.Answer(LineOf(AMarker), ALines);
  finally
    mConditions.Free;
  end;
end;

function TLspUpcomingConditionsTests.Kinds(const ABlocks: TLspUpcomingBlocks): string;
var
  mBlock: TLspUpcomingBlock;
  mTexts: TArray<string>;
begin
  mTexts := nil;
  for mBlock in ABlocks do
  begin
    mTexts := mTexts + [Format('%s@%d', [mBlock.Kind, mBlock.Line])];
  end;
  Result := string.Join(' ', mTexts);
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
  mAnswer: TLspUpcomingBlocks;
  mBlock: TLspUpcomingBlock;
begin
  mAnswer := Blocks('// Fall', 0);
  Assert.AreEqual('case@13 while@20', Kinds(mAnswer));
  mBlock := mAnswer[0];
  Assert.AreEqual(6, Integer(Length(mBlock.Parts)));
  Assert.AreEqual('FMode', mBlock.Parts[0].Text);
  Assert.AreEqual('smAuto', mBlock.Parts[1].Text);
  Assert.AreEqual('1', mBlock.Parts[3].Text);
  Assert.AreEqual('3', mBlock.Parts[4].Text);
  Assert.AreEqual(4, Integer(Length(mBlock.Branches)));
  Assert.AreEqual('item', mBlock.Branches[2].Name);
  Assert.AreEqual(2, Integer(Length(mBlock.Branches[2].Labels)));
  Assert.AreEqual(3, mBlock.Branches[2].Labels[0][0]);
  Assert.AreEqual(4, mBlock.Branches[2].Labels[0][1]);
  Assert.AreEqual(5, mBlock.Branches[2].Labels[1][0]);
  Assert.AreEqual(-1, mBlock.Branches[2].Labels[1][1]);
  Assert.AreEqual('else', mBlock.Branches[3].Name);
  Assert.AreEqual(14, mBlock.Branches[0].FromLine);
  Assert.AreEqual(18, mBlock.Branches[3].ToLine);
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
  mAnswer: TLspUpcomingBlocks;
  mJson: TJSONObject;
  mItem: TJSONObject;
begin
  mAnswer := Blocks('// Wenn', 0);
  Assert.AreEqual('then', mAnswer[0].Branches[0].Name);
  Assert.AreEqual(10, mAnswer[0].Branches[0].FromLine);
  Assert.AreEqual('else', mAnswer[0].Branches[1].Name);
  Assert.AreEqual(12, mAnswer[0].Branches[1].FromLine);
  Assert.AreEqual('and', mAnswer[0].Parts[0].Kind);
  mJson := TLspUpcomingConditions.ToJson(mAnswer);
  try
    Assert.AreEqual(1, (mJson.GetValue('format') as TJSONNumber).AsInt);
    mItem := (mJson.GetValue('blocks') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('if', mItem.GetValue('kind').Value);
    Assert.AreEqual(2, Integer((mItem.GetValue('branches') as TJSONArray).Count));
    Assert.IsTrue((mItem.GetValue('parts') as TJSONArray).Count >= 3);
  finally
    mJson.Free;
  end;
end;

procedure TLspUpcomingConditionsTests.ClampLines;
begin
  Assert.AreEqual(TLspUpcomingConditions.cDefaultLines, TLspUpcomingConditions.ClampLines(0));
  Assert.AreEqual(TLspUpcomingConditions.cMaxLines, TLspUpcomingConditions.ClampLines(1000));
  Assert.AreEqual(7, TLspUpcomingConditions.ClampLines(7));
end;

end.
