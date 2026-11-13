unit Atlas.Common.Lsp.EnclosingConditions.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.EnclosingConditions;

type
  [TestFixture]
  TLspEnclosingConditionsTests = class
  private
    FTree: TSyntaxTree;
    FCalls: TArray<TTextPosition>;
    function LineOf(const AMarker: string): Integer;
    function Blocks(const AMarker: string; ADepth: Integer): TLspEnclosingBlocks;
    function Describe(const ABlock: TLspEnclosingBlock): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CaseInIfInForFromInsideOut;
    [Test]
    procedure DepthLimitsBlocks;
    [Test]
    procedure ElseIfChainNamesBranches;
    [Test]
    procedure AndChainWithCallAndComparison;
    [Test]
    procedure NotAndParenthesizedOrKeepStructure;
    [Test]
    procedure RepeatUsesUntilLine;
    [Test]
    procedure CaseRangeAndElse;
    [Test]
    procedure WhileForInAndWith;
    [Test]
    procedure HeaderOnStopLineIsSkipped;
    [Test]
    procedure StopsAtRoutineBoundary;
    [Test]
    procedure CallPositionsMarkGetter;
    [Test]
    procedure JsonShape;
    [Test]
    procedure ClampDepth;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.TreeCache;

const
  Source =
    'unit Ablauf;'#10 +                                          // 0
    'interface'#10 +                                             // 1
    'implementation'#10 +                                        // 2
    'procedure Rechne(Liste: TListe; Art: TArt);'#10 +            // 3
    'var'#10 +                                                   // 4
    '  I, N, Summe: Integer;'#10 +                               // 5
    'begin'#10 +                                                 // 6
    '  for I := 1 to N do'#10 +                                  // 7
    '  begin'#10 +                                               // 8
    '    if (Summe > 1000) and Pruefe(I) and Aktiv then'#10 +    // 9
    '      case Art of'#10 +                                     // 10
    '        paNormal: Summe := 0;'#10 +                         // 11
    '        paRabatt:'#10 +                                     // 12
    '          Summe := Summe - 10; // Rabatt'#10 +              // 13
    '        paA..paC, paD:'#10 +                                // 14
    '          Summe := 1; // Bereich'#10 +                      // 15
    '      else'#10 +                                            // 16
    '        Summe := 2; // Sonst'#10 +                          // 17
    '      end;'#10 +                                            // 18
    '  end;'#10 +                                                // 19
    '  if N = 0 then'#10 +                                       // 20
    '    Exit'#10 +                                              // 21
    '  else if not (Aktiv or (N in [1, 2])) then'#10 +           // 22
    '    N := 1 // ElseIf'#10 +                                  // 23
    '  else'#10 +                                                // 24
    '    N := 2; // LetztesElse'#10 +                            // 25
    '  repeat'#10 +                                              // 26
    '    Dec(N); // ImRepeat'#10 +                               // 27
    '  until (N <= 0) or'#10 +                                   // 28
    '    Fertig;'#10 +                                           // 29
    '  while Liste.Count > N do'#10 +                            // 30
    '    for var E in Liste do'#10 +                             // 31
    '      with E do'#10 +                                       // 32
    '        Inc(N); // ImWith'#10 +                             // 33
    '  if N > 0 then Inc(N); // Kopfzeile'#10 +                  // 34
    'end;'#10 +                                                  // 35
    'procedure Aussen;'#10 +                                     // 36
    'begin'#10 +                                                 // 37
    '  if Bereit then'#10 +                                      // 38
    '    Liste.ForEach(procedure(X: Integer)'#10 +               // 39
    '      begin'#10 +                                           // 40
    '        if X > 0 then'#10 +                                 // 41
    '          Zeige(X); // Anonym'#10 +                         // 42
    '      end);'#10 +                                           // 43
    'end;'#10 +                                                  // 44
    'end.';

{ TLspEnclosingConditionsTests }

procedure TLspEnclosingConditionsTests.Setup;
begin
  FTree := TSyntaxTreeCache.Parse(Source);
  FCalls := nil;
end;

procedure TLspEnclosingConditionsTests.TearDown;
begin
  FreeAndNil(FTree);
  FCalls := nil;
end;

function TLspEnclosingConditionsTests.LineOf(const AMarker: string): Integer;
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

function TLspEnclosingConditionsTests.Blocks(const AMarker: string; ADepth: Integer): TLspEnclosingBlocks;
var
  Conditions: TLspEnclosingConditions;
  Calls: TArray<TTextPosition>;
begin
  Calls := FCalls;
  Conditions := TLspEnclosingConditions.Create(FTree, Source,
    function(ALine: Integer): TArray<TTextPosition>
    begin
      Result := Calls;
    end);
  try
    Result := Conditions.Answer(LineOf(AMarker), ADepth);
  finally
    Conditions.Free;
  end;
end;

function TLspEnclosingConditionsTests.Describe(const ABlock: TLspEnclosingBlock): string;
var
  Part: TLspConditionPart;
  Texts: TArray<string>;
begin
  Texts := nil;
  for Part in ABlock.Parts do
  begin
    Texts := Texts + [Format('%s%d:%s', [Part.Kind, Part.Parent, Part.Text])];
    if Part.Call then
    begin
      Texts[High(Texts)] := Texts[High(Texts)] + '!';
    end;
  end;
  Result := Format('%s@%d[%s] ', [ABlock.Kind, ABlock.Line, ABlock.Branch]) + string.Join(' | ', Texts);
end;

procedure TLspEnclosingConditionsTests.CaseInIfInForFromInsideOut;
var
  Answer: TLspEnclosingBlocks;
begin
  Answer := Blocks('// Rabatt', 3);
  Assert.AreEqual(3, Integer(Length(Answer)));
  Assert.AreEqual('case@10[paRabatt] value-1:Art', Describe(Answer[0]));
  Assert.AreEqual('if@9[then] and-1:(Summe > 1000) and Pruefe(I) and Aktiv! | compare0:Summe > 1000 | ' +
    'value1:Summe | value1:1000 | value0:Pruefe(I)! | value0:Aktiv', Describe(Answer[1]));
  Assert.AreEqual('for@7[] value-1:I | value-1:N', Describe(Answer[2]));
  Assert.AreEqual(7, Answer[2].Start.Line);
  Assert.AreEqual(2, Answer[2].Start.Character);
end;

procedure TLspEnclosingConditionsTests.DepthLimitsBlocks;
begin
  Assert.AreEqual(1, Integer(Length(Blocks('// Rabatt', 1))));
  Assert.AreEqual(2, Integer(Length(Blocks('// Rabatt', 2))));
  // 0 = Vorgabe 3; mehr Blöcke als vorhanden gibt es nicht.
  Assert.AreEqual(3, Integer(Length(Blocks('// Rabatt', 0))));
  Assert.AreEqual(3, Integer(Length(Blocks('// Rabatt', 10))));
end;

procedure TLspEnclosingConditionsTests.ElseIfChainNamesBranches;
var
  Answer: TLspEnclosingBlocks;
begin
  Answer := Blocks('// ElseIf', 3);
  Assert.AreEqual(2, Integer(Length(Answer)));
  Assert.AreEqual('if', Answer[0].Kind);
  Assert.AreEqual('then', Answer[0].Branch);
  Assert.AreEqual(22, Answer[0].Line);
  Assert.AreEqual('if@20[else] compare-1:N = 0 | value0:N | value0:0', Describe(Answer[1]));
  Answer := Blocks('// LetztesElse', 3);
  Assert.AreEqual('else', Answer[0].Branch);
  Assert.AreEqual('else', Answer[1].Branch);
end;

procedure TLspEnclosingConditionsTests.AndChainWithCallAndComparison;
var
  Answer: TLspEnclosingBlocks;
begin
  // Die and-Kette ist ein Teil mit drei Gliedern, nicht zwei geschachtelte.
  Answer := Blocks('// Bereich', 3);
  Assert.AreEqual(6, Integer(Length(Answer[1].Parts)));
  Assert.AreEqual('and', Answer[1].Parts[0].Operator_);
  Assert.AreEqual(0, Answer[1].Parts[5].Parent);
  Assert.IsTrue(Answer[1].Parts[0].Call, 'Die Kette enthält einen Aufruf');
  Assert.IsFalse(Answer[1].Parts[1].Call);
end;

procedure TLspEnclosingConditionsTests.NotAndParenthesizedOrKeepStructure;
var
  Answer: TLspEnclosingBlocks;
begin
  Answer := Blocks('// ElseIf', 3);
  Assert.AreEqual('if@22[then] not-1:not (Aktiv or (N in [1, 2])) | or0:Aktiv or (N in [1, 2]) | value1:Aktiv | ' +
    'compare1:N in [1, 2] | value3:N | value3:[1, 2]', Describe(Answer[0]));
end;

procedure TLspEnclosingConditionsTests.RepeatUsesUntilLine;
var
  Answer: TLspEnclosingBlocks;
begin
  Answer := Blocks('// ImRepeat', 3);
  Assert.AreEqual(1, Integer(Length(Answer)));
  Assert.AreEqual('repeat@29[] or-1:(N <= 0) or Fertig | compare0:N <= 0 | value1:N | value1:0 | value0:Fertig',
    Describe(Answer[0]));
  Assert.AreEqual(26, Answer[0].Start.Line);
end;

procedure TLspEnclosingConditionsTests.CaseRangeAndElse;
begin
  Assert.AreEqual('paA..paC, paD', Blocks('// Bereich', 1)[0].Branch);
  Assert.AreEqual('else', Blocks('// Sonst', 1)[0].Branch);
  Assert.AreEqual('paNormal', Blocks('paNormal: Summe', 3)[0].Branch);
end;

procedure TLspEnclosingConditionsTests.WhileForInAndWith;
var
  Answer: TLspEnclosingBlocks;
begin
  Answer := Blocks('// ImWith', 5);
  Assert.AreEqual(3, Integer(Length(Answer)));
  Assert.AreEqual('with@32[] value-1:E', Describe(Answer[0]));
  Assert.AreEqual('forIn@31[] value-1:E | value-1:Liste', Describe(Answer[1]));
  Assert.AreEqual('while@30[] compare-1:Liste.Count > N | value0:Liste.Count | value0:N', Describe(Answer[2]));
end;

procedure TLspEnclosingConditionsTests.HeaderOnStopLineIsSkipped;
begin
  // if N > 0 then Inc(N); in einer Zeile: Die Bedingung ist beim Halt noch nicht ausgewertet.
  Assert.AreEqual(0, Integer(Length(Blocks('// Kopfzeile', 3))));
  // Halt auf dem Kopf der case-Anweisung: nur die äußeren Blöcke.
  Assert.AreEqual('if', Blocks('case Art of', 3)[0].Kind);
end;

procedure TLspEnclosingConditionsTests.StopsAtRoutineBoundary;
var
  Answer: TLspEnclosingBlocks;
begin
  // In der anonymen Methode endet die Suche an ihrem Rand; das if Bereit außen zählt nicht.
  Answer := Blocks('// Anonym', 5);
  Assert.AreEqual(1, Integer(Length(Answer)));
  Assert.AreEqual(41, Answer[0].Line);
end;

procedure TLspEnclosingConditionsTests.CallPositionsMarkGetter;
var
  Answer: TLspEnclosingBlocks;
begin
  // Liste.Count als Getter gemeldet (Zeile 30, Spalte von Count).
  FCalls := [TTextPosition.Create(30, 14)];
  Answer := Blocks('// ImWith', 5);
  Assert.AreEqual('while@30[] compare-1:Liste.Count > N! | value0:Liste.Count! | value0:N', Describe(Answer[2]));
end;

procedure TLspEnclosingConditionsTests.JsonShape;
var
  Json: TJSONObject;
  Block, Part: TJSONObject;
begin
  Json := TLspEnclosingConditions.ToJson(Blocks('// ElseIf', 3));
  try
    Assert.AreEqual(1, Json.GetValue<Integer>('format'));
    Block := (Json.GetValue('blocks') as TJSONArray).Items[1] as TJSONObject;
    Assert.AreEqual('if', Block.GetValue<string>('kind'));
    Assert.AreEqual(20, Block.GetValue<Integer>('line'));
    Assert.AreEqual('else', Block.GetValue<string>('branch'));
    Part := (Block.GetValue('parts') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('compare', Part.GetValue<string>('kind'));
    Assert.AreEqual('=', Part.GetValue<string>('operator'));
    Assert.AreEqual(-1, (Part.GetValue('parent') as TJSONNumber).AsInt);
    Assert.IsFalse(Part.GetValue<Boolean>('call'));
  finally
    Json.Free;
  end;
end;

procedure TLspEnclosingConditionsTests.ClampDepth;
begin
  Assert.AreEqual(3, TLspEnclosingConditions.ClampDepth(0));
  Assert.AreEqual(1, TLspEnclosingConditions.ClampDepth(1));
  Assert.AreEqual(10, TLspEnclosingConditions.ClampDepth(99));
end;

end.
