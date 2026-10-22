unit Atlas.Common.Rules.Builtin.Performance.Tests;

// Tests für die Performance-Regeln (#278): je Regel ein positiver und ein negativer Fall.
// setlength-in-loop (#974): Beispiel des Issues samt Korrektur, Schleifen ohne bekannte Anzahl,
// Strings und fremde Arrays, Korrektur nur bei frischer lokaler Variable, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPerformanceRulesTests = class
  public
    [Test]
    procedure RulesOffByDefault;
    [Test]
    procedure StringConcatInLoopReported;
    [Test]
    procedure StringConcatOutsideLoopOrNoStringSilent;
    [Test]
    procedure LoopInvariantCallReported;
    [Test]
    procedure ForBoundsAndCheapConditionSilent;
    [Test]
    procedure MissingBeginUpdateReported;
    [Test]
    procedure BeginUpdatePresentSilent;
    [Test]
    procedure SetLengthInLoopReportedWithCount;
    [Test]
    procedure SetLengthInLoopFixSetsLengthBefore;
    [Test]
    procedure SetLengthInLoopFixKeepsOtherStatements;
    [Test]
    procedure SetLengthInLoopWithoutCount;
    [Test]
    procedure SetLengthInLoopSilentCases;
    [Test]
    procedure SetLengthInLoopNoFixWhenArrayInUse;
    [Test]
    procedure SetLengthInLoopSwitchedOff;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Performance,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

const
  // Niedrige Konfidenz wird erst ab minConfidence "low" gemeldet.
  AllOn = '{ "minConfidence": "low", "rules": { "string-concat-in-loop": "hint", "loop-invariant-call": "hint", ' +
    '"missing-begin-update": "hint" } }';

function InRoutine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10 + AVars + #10'begin'#10 +
    ABody + #10'end;'#10'end.';
end;

function Count(const ARule: IRule; const ASource: string): Integer;
begin
  Result := Length(TRuleAssert.Findings(ARule, ASource, AllOn));
end;

procedure TPerformanceRulesTests.RulesOffByDefault;
var
  Rule: IRule;
begin
  for Rule in TArray<IRule>.Create(TStringConcatInLoopRule.Create, TLoopInvariantCallRule.Create,
    TMissingBeginUpdateRule.Create) do
    Assert.IsTrue(Rule.Descriptor.Experimental, Rule.Descriptor.Id);
end;

procedure TPerformanceRulesTests.StringConcatInLoopReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TStringConcatInLoopRule.Create, InRoutine('  S: string;'#10'  I: Integer;',
    '  for I := 1 to 10 do'#10'    S := S + IntToStr(I);'), AllOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
  Assert.AreEqual(1, Count(TStringConcatInLoopRule.Create, InRoutine('  S: string;',
    '  repeat'#10'    S := S + ''x'';'#10'  until Length(S) > 5;')));
end;

procedure TPerformanceRulesTests.StringConcatOutsideLoopOrNoStringSilent;
begin
  Assert.AreEqual(0, Count(TStringConcatInLoopRule.Create, InRoutine('  S: string;'#10'  N, I: Integer;',
    '  S := S + ''x'';'#10'  for I := 1 to 10 do'#10'    N := N + I;')));
end;

procedure TPerformanceRulesTests.LoopInvariantCallReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLoopInvariantCallRule.Create, InRoutine('  I: Integer;',
    '  while I < Length(Trim(Memo.Lines.Text)) do'#10'    Inc(I);'), AllOn);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(1, Count(TLoopInvariantCallRule.Create, InRoutine('  I: Integer;',
    '  repeat'#10'    Inc(I);'#10'  until FileExists(Name);')));
end;

procedure TPerformanceRulesTests.ForBoundsAndCheapConditionSilent;
begin
  Assert.AreEqual(0, Count(TLoopInvariantCallRule.Create, InRoutine('  I: Integer;',
    '  for I := 1 to Length(Trim(S)) do'#10'    Inc(N);'#10'  while I < List.Count do'#10'    Inc(I);'#10 +
    '  while Reader.Trim do'#10'    Inc(I);')));
end;

procedure TPerformanceRulesTests.MissingBeginUpdateReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMissingBeginUpdateRule.Create, InRoutine('  I: Integer;',
    '  for I := 1 to 100 do'#10'  begin'#10'    ListBox1.Items.Add(IntToStr(I));'#10 +
    '    ListBox1.Items.Add(''x'');'#10'  end;'), AllOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'ListBox1.Items.BeginUpdate');
end;

procedure TPerformanceRulesTests.BeginUpdatePresentSilent;
begin
  Assert.AreEqual(0, Count(TMissingBeginUpdateRule.Create, InRoutine('  I: Integer;',
    '  Memo1.Lines.BeginUpdate;'#10'  try'#10'    for I := 1 to 100 do'#10'      Memo1.Lines.Add(''x'');'#10 +
    '  finally'#10'    Memo1.Lines.EndUpdate;'#10'  end;'#10'  ListBox1.Items.Add(''y'');'#10 +
    '  for I := 1 to 3 do'#10'    List.Add(I);')));
end;

const
  IssueBody = '  for I := 0 to Liste.Count - 1 do'#10'  begin'#10'    SetLength(Namen, Length(Namen) + 1);'#10 +
    '    Namen[High(Namen)] := Liste[I].Name;'#10'  end;';

function SetLengthFindings(const AVars, ABody: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TSetLengthInLoopRule.Create, InRoutine(AVars, ABody));
end;

/// <summary>Wendet die einzige Korrektur an und prüft, dass das Ergebnis fehlerfrei parst.</summary>
function Fixed(const ASource: string; const AFinding: TRuleFinding): string;
var
  Tree: TSyntaxTree;
begin
  Assert.AreEqual(1, Integer(Length(AFinding.Fixes)));
  Result := TChangeSignature.ApplyEdits(ASource, AFinding.Fixes[0].Edits);
  Tree := TPascalParser.Parse(Result);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), Result);
  finally
    Tree.Free;
  end;
end;

procedure TPerformanceRulesTests.SetLengthInLoopReportedWithCount;
var
  Findings: TArray<TRuleFinding>;
begin
  Assert.IsFalse(TSetLengthInLoopRule.Create.Descriptor.Experimental, 'Standard an');
  Findings := SetLengthFindings('  Namen: TArray<string>;'#10'  I: Integer;', IssueBody);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('SetLength in der Schleife kopiert Namen bei jedem Durchlauf; die Anzahl Liste.Count ist ' +
    'vorher bekannt.', Findings[0].Message);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line);
  // Andere Grenzen: 1 bis N und A bis B.
  Findings := SetLengthFindings('  Werte: array of Integer;'#10'  I: Integer;',
    '  for I := 1 to N do'#10'  begin'#10'    SetLength(Werte, Length(Werte) + 1);'#10'    Werte[High(Werte)] := I;' +
    #10'  end;');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.EndsWith('die Anzahl N ist vorher bekannt.', Findings[0].Message);
  Findings := SetLengthFindings('  Werte: TBytes;'#10'  I: Integer;',
    '  for I := A to B do'#10'    SetLength(Werte, 1 + Length(Werte));');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.EndsWith('die Anzahl B - A + 1 ist vorher bekannt.', Findings[0].Message);
end;

procedure TPerformanceRulesTests.SetLengthInLoopFixSetsLengthBefore;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  Namen: TArray<string>;'#10'  I: Integer;', IssueBody);
  Findings := TRuleAssert.Findings(TSetLengthInLoopRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(InRoutine('  Namen: TArray<string>;'#10'  I: Integer;',
    '  SetLength(Namen, Liste.Count);'#10'  for I := 0 to Liste.Count - 1 do'#10 +
    '    Namen[I] := Liste[I].Name;'), Fixed(Source, Findings[0]));
  // Start bei 1: Index I - 1, Anzahl N.
  Source := InRoutine('  Werte: array of Integer;'#10'  I: Integer;',
    '  for I := 1 to N do'#10'  begin'#10'    SetLength(Werte, Length(Werte) + 1);'#10 +
    '    Werte[Length(Werte) - 1] := I * I;'#10'  end;');
  Findings := TRuleAssert.Findings(TSetLengthInLoopRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(InRoutine('  Werte: array of Integer;'#10'  I: Integer;',
    '  SetLength(Werte, N);'#10'  for I := 1 to N do'#10'    Werte[I - 1] := I * I;'), Fixed(Source, Findings[0]));
end;

procedure TPerformanceRulesTests.SetLengthInLoopFixKeepsOtherStatements;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  Namen: TArray<string>;'#10'  I: Integer;',
    '  for I := 0 to High(Liste) do'#10'  begin'#10'    Log(I);'#10'    SetLength(Namen, Length(Namen) + 1);'#10 +
    '    Namen[High(Namen)] := Liste[I];'#10'  end;');
  Findings := TRuleAssert.Findings(TSetLengthInLoopRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.EndsWith('die Anzahl High(Liste) + 1 ist vorher bekannt.', Findings[0].Message);
  Assert.AreEqual(InRoutine('  Namen: TArray<string>;'#10'  I: Integer;',
    '  SetLength(Namen, High(Liste) + 1);'#10'  for I := 0 to High(Liste) do'#10'  begin'#10'    Log(I);'#10 +
    '    Namen[I] := Liste[I];'#10'  end;'), Fixed(Source, Findings[0]));
end;

procedure TPerformanceRulesTests.SetLengthInLoopWithoutCount;
var
  Findings: TArray<TRuleFinding>;
begin
  // while, repeat, for-in, bedingtes SetLength und downto: Anzahl unbekannt, keine Korrektur.
  Findings := SetLengthFindings('  Zeilen: TStringDynArray;',
    '  while not Eof(F) do'#10'  begin'#10'    SetLength(Zeilen, Length(Zeilen) + 1);'#10 +
    '    Readln(F, Zeilen[High(Zeilen)]);'#10'  end;');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('SetLength in der Schleife kopiert Zeilen bei jedem Durchlauf; die Länge vor der Schleife setzen ' +
    'oder die Werte in einer TList<T> sammeln.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(1, Integer(Length(SetLengthFindings('  A: TArray<Integer>;',
    '  repeat'#10'    SetLength(A, Succ(Length(A)));'#10'  until Fertig;'))));
  Assert.AreEqual(1, Integer(Length(SetLengthFindings('  A: TArray<Integer>;'#10'  X: Integer;',
    '  for X in Quelle do'#10'    if X > 0 then'#10'    begin'#10'      SetLength(A, Length(A) + 1);'#10 +
    '      A[High(A)] := X;'#10'    end;'))));
  Findings := SetLengthFindings('  A: TArray<Integer>;'#10'  I: Integer;',
    '  for I := 10 downto 1 do'#10'    SetLength(A, Length(A) + 1);');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TPerformanceRulesTests.SetLengthInLoopSilentCases;
begin
  // Strings, unbekannte Typen, SetLength außerhalb einer Schleife, feste Länge, anderes Array,
  // anonyme Methode in der Schleife.
  Assert.AreEqual(0, Integer(Length(SetLengthFindings('  S: string;'#10'  I: Integer;',
    '  for I := 1 to 10 do'#10'    SetLength(S, Length(S) + 1);'))));
  Assert.AreEqual(0, Integer(Length(SetLengthFindings('  I: Integer;',
    '  for I := 1 to 10 do'#10'    SetLength(Unbekannt, Length(Unbekannt) + 1);'))));
  Assert.AreEqual(0, Integer(Length(SetLengthFindings('  A, B: TArray<Integer>;'#10'  I: Integer;',
    '  SetLength(A, Length(A) + 1);'#10'  for I := 1 to 10 do'#10'    SetLength(A, 10);'#10 +
    '  for I := 1 to 10 do'#10'    SetLength(A, Length(B) + 1);'#10 +
    '  for I := 1 to 10 do'#10'    TThread.Queue(nil, procedure begin SetLength(A, Length(A) + 1) end);'))));
end;

procedure TPerformanceRulesTests.SetLengthInLoopNoFixWhenArrayInUse;
var
  Findings: TArray<TRuleFinding>;
begin
  // Array vorher schon befüllt, im Rumpf anders benutzt oder mit Break verlassen: Meldung ohne Korrektur.
  Findings := SetLengthFindings('  Namen: TArray<string>;'#10'  I: Integer;', '  Namen := Vorgabe;'#10 + IssueBody);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Findings := SetLengthFindings('  Namen: TArray<string>;'#10'  I: Integer;',
    '  for I := 0 to N - 1 do'#10'  begin'#10'    SetLength(Namen, Length(Namen) + 1);'#10 +
    '    Namen[High(Namen)] := Namen[0];'#10'  end;');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Findings := SetLengthFindings('  Namen: TArray<string>;'#10'  I: Integer;',
    '  for I := 0 to N - 1 do'#10'  begin'#10'    if Stop then'#10'      Break;'#10 +
    '    SetLength(Namen, Length(Namen) + 1);'#10'    Namen[High(Namen)] := '''';'#10'  end;');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));  // Result einer Funktion: Typ aus dem Kopf, nie leer vorbelegt, also keine Korrektur.
  Findings := TRuleAssert.Findings(TSetLengthInLoopRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'function F(N: Integer): TArray<Integer>;'#10'var'#10'  I: Integer;'#10'begin'#10'  for I := 0 to N - 1 do'#10 +
    '  begin'#10'    SetLength(Result, Length(Result) + 1);'#10'    Result[High(Result)] := I;'#10'  end;'#10 +
    'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TPerformanceRulesTests.SetLengthInLoopSwitchedOff;
var
  Source: string;
begin
  Source := InRoutine('  Namen: TArray<string>;'#10'  I: Integer;', IssueBody);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSetLengthInLoopRule.Create, Source,
    '{"rules": {"setlength-in-loop": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSetLengthInLoopRule.Create, Source,
    '{"rules": {"setlength-in-loop": {"exclude": ["Alt/**"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TSetLengthInLoopRule.Create, Source,
    '{"rules": {"setlength-in-loop": {"exclude": ["Alt/**"]}}}', 'Neu/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TPerformanceRulesTests);

end.
