unit Atlas.Common.Rules.Builtin.SharedState.Tests;

// Tests der Thread-Regeln aus Builtin.SharedState: parallel-for-shared-write (#1058).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSharedStateRulesTests = class
  public
    [Test]
    procedure ParallelIssueExample;
    [Test]
    procedure ParallelFixUsesInterlocked;
    [Test]
    procedure ParallelFixAddsSyncObjs;
    [Test]
    procedure ParallelIncAndSubtract;
    [Test]
    procedure ParallelCollectionGetsLock;
    [Test]
    procedure ParallelFieldsAndGlobals;
    [Test]
    procedure ParallelTaskInLoop;
    [Test]
    procedure ParallelSilentCases;
    [Test]
    procedure ParallelThreadSafeTypes;
    [Test]
    procedure ParallelOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.SharedState,
  Atlas.Tests.RuleAssert;

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

procedure AssertParses(const ASource: string);
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
end;

/// <summary>Unit Rechnen mit der Routine Summieren: AVar als lokale Variablen, ABody als Rumpf von TParallel.For.
/// </summary>
function Rechnen(const AUses, AVar, ABody: string): string;
begin
  Result :=
    'unit Rechnen;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses ' + AUses + ';'#10 +
    'procedure Summieren(const Werte: TArray<Integer>);'#10 +
    'var'#10 +
    AVar +
    'begin'#10 +
    '  TParallel.For(0, High(Werte), procedure(I: Integer)'#10 +
    '    begin'#10 +
    ABody +
    '    end);'#10 +
    'end;'#10 +
    'end.';
end;

function ParallelFindings(const AVar, ABody: string; const AConfigJson: string = ''): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Rechnen('System.Threading', AVar, ABody),
    AConfigJson);
end;

/// <summary>Formular-Unit, deren Methode Starten ABody ausführt (Feld FAnzahl, globale GZaehler).</summary>
function Starter(const AVar, ABody: string): string;
begin
  Result :=
    'unit Starter;'#10 +
    'interface'#10 +
    'uses System.Classes, System.Threading;'#10 +
    'type'#10 +
    '  TfrmStart = class'#10 +
    '  private'#10 +
    '    FAnzahl: Integer;'#10 +
    '  public'#10 +
    '    procedure Starten;'#10 +
    '  end;'#10 +
    'var'#10 +
    '  GZaehler: Int64;'#10 +
    'implementation'#10 +
    'procedure TfrmStart.Starten;'#10 +
    AVar +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

{ TSharedStateRulesTests }

procedure TSharedStateRulesTests.ParallelIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := ParallelFindings('  Summe: Integer;'#10, '      Summe := Summe + Werte[I];'#10);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('parallel-for-shared-write', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('Summe wird parallel ohne Sperre geschrieben; Additionen gehen verloren.', Findings[0].Message);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(31, Findings[0].Range.EndPos.Character);
end;

procedure TSharedStateRulesTests.ParallelFixUsesInterlocked;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Rechnen('System.Threading, System.SyncObjs', '  Summe: Integer;'#10, '      Summe := Summe + Werte[I];'#10);
  Findings := TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('TInterlocked.Add(Summe, Werte[I]) verwenden', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Rechnen('System.Threading, System.SyncObjs', '  Summe: Integer;'#10,
    '      TInterlocked.Add(Summe, Werte[I]);'#10), Fixed);
  AssertParses(Fixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Fixed))));
end;

procedure TSharedStateRulesTests.ParallelFixAddsSyncObjs;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Rechnen('System.Threading', '  Summe: Integer;'#10, '      Summe := Summe + Werte[I];'#10);
  Findings := TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Rechnen('System.Threading, System.SyncObjs', '  Summe: Integer;'#10,
    '      TInterlocked.Add(Summe, Werte[I]);'#10), Fixed);
end;

procedure TSharedStateRulesTests.ParallelIncAndSubtract;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Rechnen('System.Threading, System.SyncObjs', '  Anzahl: Integer;'#10'  Rest: Int64;'#10,
    '      Inc(Anzahl);'#10'      Rest := Rest - Werte[I];'#10'      Dec(Anzahl, 2);'#10);
  Findings := TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source);
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Anzahl wird parallel ohne Sperre geschrieben; Additionen gehen verloren.', Findings[0].Message);
  Assert.AreEqual('TInterlocked.Increment(Anzahl) verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual('Rest wird parallel ohne Sperre geschrieben; Änderungen gehen verloren.', Findings[1].Message);
  Assert.AreEqual('TInterlocked.Add(Rest, -(Werte[I])) verwenden', Findings[1].Fixes[0].Title);
  Assert.AreEqual('TInterlocked.Add(Anzahl, -(2)) verwenden', Findings[2].Fixes[0].Title);
  // Ohne passenden Typ keine Korrektur, aber die Meldung.
  Findings := ParallelFindings('  Summe: Double;'#10, '      Summe := Summe + Werte[I];'#10);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Zuweisung ohne Bezug auf den alten Wert ist ebenfalls ein Wettlauf.
  Findings := ParallelFindings('  Letzter: Integer;'#10, '      Letzter := Werte[I] * Letzter;'#10);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TSharedStateRulesTests.ParallelCollectionGetsLock;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Rechnen('System.Threading, System.Generics.Collections', '  Liste: TList<Integer>;'#10,
    '      if Werte[I] > 0 then'#10'        Liste.Add(Werte[I]);'#10);
  Findings := TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Liste wird parallel ohne Sperre verändert (Add); die Sammlung kann beschädigt werden.',
    Findings[0].Message);
  Assert.AreEqual('Sperre mit TMonitor um Liste.Add legen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Rechnen('System.Threading, System.Generics.Collections', '  Liste: TList<Integer>;'#10,
    '      if Werte[I] > 0 then'#10 +
    '        begin'#10 +
    '          System.TMonitor.Enter(Liste);'#10 +
    '          try'#10 +
    '            Liste.Add(Werte[I]);'#10 +
    '          finally'#10 +
    '            System.TMonitor.Exit(Liste);'#10 +
    '          end;'#10 +
    '        end;'#10), Fixed);
  AssertParses(Fixed);
  // Direkt im Rumpf ohne begin … end.
  Source := Rechnen('System.Threading, System.Generics.Collections', '  Liste: TList<Integer>;'#10,
    '      Liste.Add(Werte[I]);'#10);
  Findings := TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source);
  Assert.AreEqual(Rechnen('System.Threading, System.Generics.Collections', '  Liste: TList<Integer>;'#10,
    '      System.TMonitor.Enter(Liste);'#10 +
    '      try'#10 +
    '        Liste.Add(Werte[I]);'#10 +
    '      finally'#10 +
    '        System.TMonitor.Exit(Liste);'#10 +
    '      end;'#10), ApplyFix(Source, Findings[0].Fixes[0]));
  // Mehrere Anweisungen in einer Zeile: keine Korrektur.
  Source := Rechnen('System.Threading, System.Generics.Collections', '  Liste: TList<Integer>;'#10,
    '      Liste.Add(Werte[I]); Liste.Delete(0);'#10);
  Findings := TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TSharedStateRulesTests.ParallelFieldsAndGlobals;
const
  Source =
    'unit Rechnen;'#10 +
    'interface'#10 +
    'uses System.Threading;'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '    FSumme: Integer;'#10 +
    '    procedure Summieren(const Werte: TArray<Integer>);'#10 +
    '  end;'#10 +
    'var'#10 +
    '  GAnzahl: Integer;'#10 +
    'implementation'#10 +
    'procedure TRechner.Summieren(const Werte: TArray<Integer>);'#10 +
    'begin'#10 +
    '  TParallel.For(0, High(Werte), procedure(I: Integer)'#10 +
    '    begin'#10 +
    '      FSumme := FSumme + Werte[I];'#10 +
    '      Inc(GAnzahl);'#10 +
    '    end);'#10 +
    'end;'#10 +
    'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('FSumme wird parallel ohne Sperre geschrieben; Additionen gehen verloren.', Findings[0].Message);
  Assert.AreEqual('TInterlocked.Add(FSumme, Werte[I]) verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual('GAnzahl wird parallel ohne Sperre geschrieben; Additionen gehen verloren.', Findings[1].Message);
end;

procedure TSharedStateRulesTests.ParallelTaskInLoop;
const
  InLoop =
    '  for J := 1 to 4 do'#10 +
    '    TTask.Run(procedure'#10 +
    '      begin'#10 +
    '        Inc(FAnzahl);'#10 +
    '      end);'#10;
  Single =
    '  TTask.Run(procedure'#10 +
    '    begin'#10 +
    '      Inc(FAnzahl);'#10 +
    '    end);'#10;
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TParallelForSharedWriteRule.Create,
    Starter('var'#10'  J: Integer;'#10, InLoop)))));
  // Ein einzelner Task läuft nur einmal parallel zum Aufrufer.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TParallelForSharedWriteRule.Create,
    Starter('', Single)))));
end;

procedure TSharedStateRulesTests.ParallelSilentCases;
begin
  // Eigene Variablen der anonymen Methode und Zugriffe über Index.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TParallelForSharedWriteRule.Create,
    'unit Rechnen;'#10'interface'#10'implementation'#10'uses System.Threading;'#10 +
    'procedure Summieren(var Werte: TArray<Integer>);'#10 +
    'begin'#10 +
    '  TParallel.For(0, High(Werte), procedure(I: Integer)'#10 +
    '    var'#10'      Teil: Integer;'#10 +
    '    begin'#10 +
    '      Teil := 0;'#10 +
    '      Teil := Teil + Werte[I];'#10 +
    '      Werte[I] := Teil * 2;'#10 +
    '    end);'#10 +
    'end;'#10'end.'))));
  Assert.AreEqual(0, Integer(Length(ParallelFindings('  Summe: Integer;'#10,
    '      var Teil := Werte[I];'#10'      Inc(Teil);'#10))));
  // Sperren im Rumpf.
  Assert.AreEqual(0, Integer(Length(ParallelFindings('  Summe: Integer;'#10'  Sperre: TCriticalSection;'#10,
    '      Sperre.Enter;'#10'      try'#10'        Summe := Summe + Werte[I];'#10 +
    '      finally'#10'        Sperre.Leave;'#10'      end;'#10))));
  Assert.AreEqual(0, Integer(Length(ParallelFindings('  Summe: Integer;'#10,
    '      System.TMonitor.Enter(Self);'#10'      Summe := Summe + Werte[I];'#10 +
    '      System.TMonitor.Exit(Self);'#10))));
  // Im Hauptthread über Synchronize.
  Assert.AreEqual(0, Integer(Length(ParallelFindings('  Summe: Integer;'#10,
    '      TThread.Synchronize(nil, procedure'#10'        begin'#10'          Summe := Summe + Werte[I];'#10 +
    '        end);'#10))));
  // Unbekannte Herkunft (geerbtes Feld, with): keine Aussage.
  Assert.AreEqual(0, Integer(Length(ParallelFindings('', '      Summe := Summe + Werte[I];'#10))));
  // Kein paralleler Aufruf.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TParallelForSharedWriteRule.Create,
    StringReplace(Rechnen('System.Threading', '  Summe: Integer;'#10, '      Summe := Summe + Werte[I];'#10),
    'TParallel.For', 'Durchlaufen', [])))));
end;

procedure TSharedStateRulesTests.ParallelThreadSafeTypes;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(0, Integer(Length(ParallelFindings('  Liste: TThreadList<Integer>;'#10,
    '      Liste.Add(Werte[I]);'#10))));
  Assert.AreEqual(0, Integer(Length(ParallelFindings('  Schlange: TThreadedQueue<Integer>;'#10,
    '      Schlange.Enqueue(Werte[I]);'#10))));
  Assert.AreEqual(1, Integer(Length(ParallelFindings('  Liste: TThreadList<Integer>;'#10,
    '      Liste.Add(Werte[I]);'#10, '{"rules": {"parallel-for-shared-write": {"threadSafeTypes": []}}}'))));
  Assert.AreEqual(0, Integer(Length(ParallelFindings('  Liste: TSichereListe;'#10,
    '      Liste.Add(Werte[I]);'#10,
    '{"rules": {"parallel-for-shared-write": {"threadSafeTypes": ["TSichereListe"]}}}'))));
  Assert.AreEqual(1, Integer(Length(ParallelFindings('  Liste: TSichereListe;'#10,
    '      Liste.Add(Werte[I]);'#10))));
  TConfigurationParser.Parse('{"rules": {"parallel-for-shared-write": {"threadSafeTypes": "TSichereListe"}}}',
    Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"parallel-for-shared-write": {"threadSafeTypes": ["TSichereListe"]}}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TSharedStateRulesTests.ParallelOffAndExclude;
var
  Source: string;
begin
  Source := Rechnen('System.Threading', '  Summe: Integer;'#10, '      Summe := Summe + Werte[I];'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source,
    '{"rules": {"parallel-for-shared-write": "off"}}'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source, '',
    'Source/Rechnen.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TParallelForSharedWriteRule.Create, Source,
    '{"rules": {"parallel-for-shared-write": {"exclude": ["Source/*.pas"]}}}', 'Source/Rechnen.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TSharedStateRulesTests);

end.
