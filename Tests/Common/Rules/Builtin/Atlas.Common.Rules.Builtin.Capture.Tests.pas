unit Atlas.Common.Rules.Builtin.Capture.Tests;

// Tests für captured-loop-variable (#116) und anonymous-capture-invalid (#1035):
// Beispiel mit Korrektur, out, untypisiert, Result, verschachtelte Bereiche,
// Verdecken, stille Fälle, bedingte Zweige, Abschalten und Ausnahmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCaptureRuleTests = class
  public
    [Test]
    procedure ForInVariableInQueueReports;
    [Test]
    procedure SynchronizeIsSilent;
    [Test]
    procedure VariableChangedInWhileLoopReports;
    [Test]
    procedure VariableNotChangedAfterCaptureIsSilent;
    [Test]
    procedure ClassicForCounterIsSilent;
    [Test]
    procedure InlineForVariableReports;
    [Test]
    procedure EventPropertyIsMedium;
    [Test]
    procedure CustomDeferredApiFromOptions;
    [Test]
    procedure FixCopiesValuePerIteration;
    /// <summary>Einfügeposition und Bereich über die Zeilentabelle des Ableitungscaches (Review D-04).</summary>
    [Test]
    procedure CopyPerIterationFixPositionsInCrLfFile;
  end;

  [TestFixture]
  TAnonymousCaptureInvalidTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure OutUntypedAndResult;
    [Test]
    procedure ResultOfAnonymousFunction;
    [Test]
    procedure NestedScopesAndShadowing;
    [Test]
    procedure SilentCases;
    [Test]
    procedure ConditionalBranches;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Capture,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Routine(const ABody: string; const AVars: string = ''): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10 + AVars + 'begin'#10 + ABody +
    #10'end;'#10'end.';
end;

const
  QueueLoop = '  for S in Liste do'#10'    TThread.Queue(nil, procedure begin Memo1.Lines.Add(S); end);';
  StringVar = 'var'#10'  S: string;'#10;

/// <summary>Wendet alle Änderungen der ersten Korrektur an, von hinten nach vorn (Zeilen mit #10).</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index: Integer;
  Edit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Position: Integer;
  begin
    Position := 0;
    for Line := 1 to APosition.Line do
      Position := Pos(#10, AText, Position + 1);
    Result := Position + APosition.Character;
  end;

begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Result := Copy(Result, 1, OffsetOf(Edit.Range.StartPos)) + Edit.NewText +
      Copy(Result, OffsetOf(Edit.Range.EndPos) + 1, MaxInt);
  end;
end;

procedure TCaptureRuleTests.ForInVariableInQueueReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TCapturedLoopVariableRule.Create, Routine(QueueLoop, StringVar));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
end;

procedure TCaptureRuleTests.SynchronizeIsSilent;
begin
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create,
    Routine(StringReplace(QueueLoop, 'Queue', 'Synchronize', []), StringVar));
end;

procedure TCaptureRuleTests.VariableChangedInWhileLoopReports;
begin
  TRuleAssert.Reports(TCapturedLoopVariableRule.Create,
    Routine('  I := 0;'#10'  while I < 3 do'#10'  begin'#10'    TTask.Run(procedure begin Foo(I); end);'#10 +
      '    Inc(I);'#10'  end;', 'var'#10'  I: Integer;'#10));
end;

procedure TCaptureRuleTests.VariableNotChangedAfterCaptureIsSilent;
begin
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create,
    Routine('  I := 5;'#10'  TTask.Run(procedure begin Foo(I); end);', 'var'#10'  I: Integer;'#10));
end;

procedure TCaptureRuleTests.ClassicForCounterIsSilent;
begin
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create,
    Routine('  for I := 1 to 3 do'#10'    TTask.Run(procedure begin Foo(I); end);', 'var'#10'  I: Integer;'#10));
end;

procedure TCaptureRuleTests.InlineForVariableReports;
begin
  TRuleAssert.Reports(TCapturedLoopVariableRule.Create,
    Routine('  for var I := 1 to 3 do'#10'    TTask.Run(procedure begin Foo(I); end);'));
end;

procedure TCaptureRuleTests.EventPropertyIsMedium;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TCapturedLoopVariableRule.Create,
    Routine('  for S in Liste do'#10'    F.OnDone := procedure begin Log(S); end;', StringVar));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
end;

procedure TCaptureRuleTests.CustomDeferredApiFromOptions;
var
  Source: string;
begin
  Source := Routine('  for S in Liste do'#10'    Pool.Post(procedure begin Log(S); end);', StringVar);
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCapturedLoopVariableRule.Create, Source,
    '{"rules": {"captured-loop-variable": {"deferredApis": ["Pool.Post"]}}}'))));
end;

procedure TCaptureRuleTests.FixCopiesValuePerIteration;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := Routine(QueueLoop, StringVar);
  Findings := TRuleAssert.Findings(TCapturedLoopVariableRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Routine('  for S in Liste do'#10'    TThread.Queue(nil, CaptureS(S));',
    StringVar + '  function CaptureS(const AValue: string): TProc;'#10'  begin'#10 +
    '    Result := procedure begin Memo1.Lines.Add(AValue); end;'#10'  end;'#10#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create, Fixed);
end;

procedure TCaptureRuleTests.CopyPerIterationFixPositionsInCrLfFile;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := StringReplace(Routine(QueueLoop, StringVar), #10, #13#10, [rfReplaceAll]);
  Findings := TRuleAssert.Findings(TCapturedLoopVariableRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(StringReplace(Routine('  for S in Liste do'#10'    TThread.Queue(nil, CaptureS(S));',
    StringVar + '  function CaptureS(const AValue: string): TProc;'#10'  begin'#10 +
    '    Result := procedure begin Memo1.Lines.Add(AValue); end;'#10'  end;'#10#10), #10, #13#10, [rfReplaceAll]),
    Fixed);
end;

{ TAnonymousCaptureInvalidTests }

function CaptureFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAnonymousCaptureInvalidRule.Create, ASource);
end;

function CaptureFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAnonymousCaptureInvalidRule.Create, ASource, AConfig, APath);
end;

function Laden(const AHead, ABody: string): string;
begin
  Result := 'unit Lader;'#10'interface'#10'implementation'#10 + AHead + #10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TAnonymousCaptureInvalidTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Laden('procedure Laden(var Anzahl: Integer);', '  TTask.Run(procedure begin Inc(Anzahl); end);'#10);
  Found := CaptureFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der var-Parameter Anzahl kann nicht erfasst werden (wie E2555).', Found[0].Message);
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(32, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Wert in die lokale Variable AnzahlKopie kopieren', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Laden('procedure Laden(var Anzahl: Integer);'#10'var'#10'  AnzahlKopie: Integer;',
    '  AnzahlKopie := Anzahl;'#10'  TTask.Run(procedure begin Inc(AnzahlKopie); end);'#10 +
    '  Anzahl := AnzahlKopie;'#10), Fixed);
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Fixed))), Fixed);
  // Mit var-Abschnitt; ein Argument unbekannter Signatur kann schreiben: zurückschreiben.
  Source := Laden('procedure Zeigen(var Text: string);'#10'var'#10'  I: Integer;',
    '  I := 0;'#10'  TThread.Queue(nil, procedure begin Memo.Lines.Add(Text); end);'#10);
  Found := CaptureFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Laden('procedure Zeigen(var Text: string);'#10'var'#10'  I: Integer;'#10'  TextKopie: string;',
    '  I := 0;'#10'  TextKopie := Text;'#10'  TThread.Queue(nil, procedure begin Memo.Lines.Add(TextKopie); end);'#10 +
    '  Text := TextKopie;'#10), Fixed);
  // Nur lesend: kein Zurückschreiben.
  Source := Laden('function Zeigen(var Text: string): Boolean;', '  F := function: Boolean begin Result := Text = ''''; end;'#10);
  Found := CaptureFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Laden('function Zeigen(var Text: string): Boolean;'#10'var'#10'  TextKopie: string;',
    '  TextKopie := Text;'#10'  F := function: Boolean begin Result := TextKopie = ''''; end;'#10), Fixed);
end;

procedure TAnonymousCaptureInvalidTests.OutUntypedAndResult;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Found := CaptureFindings(Laden('procedure Holen(out Wert: Integer);',
    '  TThread.Synchronize(nil, procedure begin Wert := 1; end);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der out-Parameter Wert kann nicht erfasst werden (wie E2555).', Found[0].Message);
  Found := CaptureFindings(Laden('procedure Puffer(const Daten; var Ziel);',
    '  Ausfuehren(procedure begin Move(Daten, Ziel, 4); end);'#10));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Der untypisierte Parameter Daten kann nicht erfasst werden (wie E2555).', Found[0].Message);
  Assert.AreEqual('Der untypisierte Parameter Ziel kann nicht erfasst werden (wie E2555).', Found[1].Message);
  // Untypisiert: keine Kopie möglich.
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  Source := Laden('function Lesen: string;', '  TThread.Synchronize(nil, procedure begin Result := Edit1.Text; end);'#10);
  Found := CaptureFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Result der umgebenden Funktion kann nicht erfasst werden (wie E2555).', Found[0].Message);
  Assert.AreEqual('Wert in die lokale Variable Ergebnis kopieren', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Laden('function Lesen: string;'#10'var'#10'  Ergebnis: string;',
    '  TThread.Synchronize(nil, procedure begin Ergebnis := Edit1.Text; end);'#10'  Result := Ergebnis;'#10), Fixed);
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Fixed))), Fixed);
  // Jede Stelle derselben Deklaration in einer anonymen Methode nur einmal.
  Found := CaptureFindings(Laden('procedure Laden(var Anzahl: Integer);',
    '  TTask.Run(procedure begin Inc(Anzahl); Anzahl := Anzahl * 2; end);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
end;

procedure TAnonymousCaptureInvalidTests.ResultOfAnonymousFunction;
var
  Found: TArray<TRuleFinding>;
begin
  // Result in einer anonymen Funktion ist ihr eigenes.
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Laden('function Erzeugen: TFunc<Integer>;',
    '  Result := function: Integer begin Result := 42; end;'#10)))));
  // Result der anonymen Funktion in einer inneren anonymen Prozedur.
  Found := CaptureFindings(Laden('procedure Starten;',
    '  F := function: Integer begin TThread.Synchronize(nil, procedure begin Result := 1; end); end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Result der umgebenden Funktion kann nicht erfasst werden (wie E2555).', Found[0].Message);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  // var-Parameter einer anonymen Methode in einer inneren.
  Found := CaptureFindings(Laden('procedure Starten;',
    '  P := procedure(var N: Integer) begin TTask.Run(procedure begin Inc(N); end); end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der var-Parameter N kann nicht erfasst werden (wie E2555).', Found[0].Message);
  // In einer Prozedur ohne Ergebnis ist Result kein Name der Routine.
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Laden('procedure Starten;',
    '  TTask.Run(procedure begin Result := 1; end);'#10)))));
end;

procedure TAnonymousCaptureInvalidTests.NestedScopesAndShadowing;
var
  Found: TArray<TRuleFinding>;
begin
  // Lokale Routine: der var-Parameter der äußeren Routine.
  Found := CaptureFindings(Laden('procedure Laden(var Anzahl: Integer);'#10#10'  procedure Melden;'#10'  begin'#10 +
    '    TTask.Run(procedure begin Inc(Anzahl); end);'#10'  end;'#10, '  Melden;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  // Ohne anonyme Methode greift die lokale Routine erlaubt zu.
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Laden('procedure Laden(var Anzahl: Integer);'#10#10 +
    '  procedure Melden;'#10'  begin'#10'    Inc(Anzahl);'#10'  end;'#10, '  Melden;'#10)))));
  // Gleichnamige Parameter, lokale Variablen und Inline-Variablen der anonymen Methode verdecken.
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Laden('procedure Laden(var Anzahl: Integer);',
    '  P := procedure(Anzahl: Integer) begin Inc(Anzahl); end;'#10 +
    '  P := procedure var Anzahl: Integer; begin Anzahl := 1; end;'#10 +
    '  P := procedure begin var Anzahl := 2; Inc(Anzahl); end;'#10)))));
  // Lokale Variable der Routine mit gleichem Namen wie ein Feld: erlaubt.
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Laden('procedure Laden(const Anzahl: Integer; Name: string);' +
    #10'var'#10'  Zaehler: Integer;', '  TTask.Run(procedure begin Inc(Zaehler, Anzahl); Zeigen(Name); end);'#10)))));
end;

procedure TAnonymousCaptureInvalidTests.SilentCases;
begin
  // Member hinter dem Punkt, Feldnamen in Record-Konstanten, with.
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Laden('procedure Laden(var Anzahl: Integer);',
    '  TTask.Run(procedure begin Liste.Anzahl := 1; P((Anzahl: 1)); end);'#10 +
    '  with Liste do'#10'    TTask.Run(procedure begin Inc(Anzahl); end);'#10)))));
  // Ohne anonyme Methode.
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Laden('procedure Laden(var Anzahl: Integer);',
    '  Inc(Anzahl);'#10)))));
end;

procedure TAnonymousCaptureInvalidTests.ConditionalBranches;
begin
  // Der Parameter steht nur im anderen Zweig.
  Assert.AreEqual(0, Integer(Length(CaptureFindings('unit Lader;'#10'interface'#10'implementation'#10 +
    '{$IFDEF ALT}'#10'procedure Laden(var Anzahl: Integer);'#10'begin'#10'end;'#10'{$ELSE}'#10 +
    'procedure Laden(Anzahl: Integer);'#10'begin'#10'  TTask.Run(procedure begin Zeigen(Anzahl); end);'#10'end;'#10 +
    '{$ENDIF}'#10'end.'))));
  Assert.AreEqual(1, Integer(Length(CaptureFindings('unit Lader;'#10'interface'#10'implementation'#10 +
    'procedure Laden(var Anzahl: Integer);'#10'begin'#10'{$IFDEF ALT}'#10 +
    '  TTask.Run(procedure begin Zeigen(Anzahl); end);'#10'{$ENDIF}'#10'end;'#10'end.'))));
end;

procedure TAnonymousCaptureInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := Laden('procedure Laden(var Anzahl: Integer);', '  TTask.Run(procedure begin Inc(Anzahl); end);'#10);
  Assert.AreEqual(1, Integer(Length(CaptureFindings(Source, '', 'Source/Lader.pas'))));
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Source, '{"rules": {"anonymous-capture-invalid": "off"}}',
    'Source/Lader.pas'))));
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Lader.pas'))));
  Assert.AreEqual(0, Integer(Length(CaptureFindings(Source,
    '{"rules": {"anonymous-capture-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Lader.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TCaptureRuleTests);
  TDUnitX.RegisterTestFixture(TAnonymousCaptureInvalidTests);

end.
