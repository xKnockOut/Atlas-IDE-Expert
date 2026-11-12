unit Atlas.Common.Rules.Builtin.IgnoredResult.Tests;

// Tests von ignored-result (#624): verworfenes Ergebnis von RTL-Funktionen, String-Helfern und Funktionen aus
// pureFunctions, stille Fälle, Korrektur „Ergebnis zuweisen“ (zurückschreiben bzw. Inline-Variable) und
// Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIgnoredResultTests = class
  public
    [Test]
    procedure RtlFunction;
    [Test]
    procedure StringHelper;
    [Test]
    procedure FunctionFromSettings;
    [Test]
    procedure QualifiedCalls;
    [Test]
    procedure InlineVariable;
    [Test]
    procedure InlineVariableNeedsBlockAndVersion;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OwnFunctionFromIndexIsSilent;
    [Test]
    procedure RuleCanBeTurnedOff;
    [Test]
    procedure CatalogListsAllPureRoutines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Builtin.IgnoredResult,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message + '|';
  end;
end;

/// <summary>Unit mit der Routine Lauf, deren Rumpf ABody ist; S und Pfad: string, Zahl: Integer.</summary>
function Source(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils, System.IOUtils;'#10 +
    'procedure Lauf(Zahl: Integer);'#10'var'#10'  S, Pfad: string;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

/// <summary>Quelltext nach der ersten Korrektur des einzigen Treffers.</summary>
function Fixed(const ASource: string; const AFound: TArray<TRuleFinding>): string;
begin
  Assert.AreEqual(1, Integer(Length(AFound)));
  Assert.AreEqual(1, Integer(Length(AFound[0].Fixes)));
  Result := TChangeSignature.ApplyEdits(ASource, AFound[0].Fixes[0].Edits);
end;

procedure ParsesWithoutErrors(const ASource: string);
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(ASource);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), ASource);
  finally
    mTree.Free;
  end;
end;

{ TIgnoredResultTests }

procedure TIgnoredResultTests.RtlFunction;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('  Trim(S);'#10'  IncludeTrailingPathDelimiter(Pfad);'#10);
  mFound := TRuleAssert.Findings(TIgnoredResultRule.Create, mSource);
  Assert.AreEqual('9: Das Ergebnis von Trim wird verworfen: Die Funktion hat keine Seiteneffekte, der Aufruf ' +
    'bewirkt nichts.|10: Das Ergebnis von IncludeTrailingPathDelimiter wird verworfen: Die Funktion hat keine ' +
    'Seiteneffekte, der Aufruf bewirkt nichts.|', Messages(mFound));
  Assert.AreEqual(cIgnoredResultRuleId, mFound[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual('Ergebnis zuweisen: S := …', mFound[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[1].Fixes[0].Edits);
  mFixed := TChangeSignature.ApplyEdits(mFixed, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(Source('  S := Trim(S);'#10'  Pfad := IncludeTrailingPathDelimiter(Pfad);'#10), mFixed);
  ParsesWithoutErrors(mFixed);
  TRuleAssert.Silent(TIgnoredResultRule.Create, mFixed);
end;

procedure TIgnoredResultTests.StringHelper;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('  S.Replace(''a'', ''b'');'#10'  S.Trim;'#10'  S.ToUpper();'#10);
  mFound := TRuleAssert.Findings(TIgnoredResultRule.Create, mSource);
  Assert.AreEqual(3, Integer(Length(mFound)), Messages(mFound));
  Assert.Contains(mFound[0].Message, 'S.Replace');
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[2].Fixes[0].Edits);
  mFixed := TChangeSignature.ApplyEdits(mFixed, mFound[1].Fixes[0].Edits);
  mFixed := TChangeSignature.ApplyEdits(mFixed, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(Source('  S := S.Replace(''a'', ''b'');'#10'  S := S.Trim;'#10'  S := S.ToUpper();'#10), mFixed);
  ParsesWithoutErrors(mFixed);
  TRuleAssert.Silent(TIgnoredResultRule.Create, mFixed);
end;

procedure TIgnoredResultTests.FunctionFromSettings;
const
  cOwn = 'unit U;'#10'interface'#10'implementation'#10'function Bereinigt(const A: string): string;'#10 +
    'begin'#10'  Result := A;'#10'end;'#10'procedure Lauf(S: string);'#10'begin'#10'  Bereinigt(S);'#10'end;'#10 +
    'end.';
begin
  // Ohne Eintrag schweigt die Regel, mit Eintrag meldet sie ohne Zurückschreiben (Typ unbekannt).
  TRuleAssert.Silent(TIgnoredResultRule.Create, cOwn);
  Assert.AreEqual('9: Das Ergebnis von Bereinigt wird verworfen: Die Funktion hat keine Seiteneffekte, der ' +
    'Aufruf bewirkt nichts.|', Messages(TRuleAssert.Findings(TIgnoredResultRule.Create, cOwn,
    '{"rules": {"ignored-result": {"pureFunctions": ["bereinigt"]}}}')));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TIgnoredResultRule.Create, cOwn,
    '{"rules": {"ignored-result": {"pureFunctions": ["U.Bereinigt"]}}}'))));
end;

procedure TIgnoredResultTests.QualifiedCalls;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TIgnoredResultRule.Create, Source('  System.SysUtils.Trim(S);'#10 +
    '  SysUtils.UpperCase(S);'#10'  TPath.Combine(Pfad, S);'#10'  string.Join('','', [S, Pfad]);'#10));
  Assert.AreEqual(4, Integer(Length(mFound)), Messages(mFound));
  Assert.Contains(mFound[2].Message, 'TPath.Combine');
end;

procedure TIgnoredResultTests.InlineVariable;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // Anderer Ergebnistyp: neue Inline-Variable; der Name ist frei (Ergebnis gibt es schon).
  mSource := Source('  IntToStr(Zahl);'#10'  Format(''%d'', [Zahl]);'#10'  S := ''Ergebnis'';'#10);
  mFound := TRuleAssert.Findings(TIgnoredResultRule.Create, StringReplace(mSource, 'S, Pfad: string;',
    'S, Pfad, Ergebnis: string;', []));
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('Ergebnis zuweisen: var Ergebnis2 := …', mFound[0].Fixes[0].Title);
  mFound := TRuleAssert.Findings(TIgnoredResultRule.Create, mSource);
  Assert.AreEqual('Ergebnis zuweisen: var Ergebnis := …', mFound[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(Source('  var Ergebnis := IntToStr(Zahl);'#10'  Format(''%d'', [Zahl]);'#10 +
    '  S := ''Ergebnis'';'#10), mFixed);
  ParsesWithoutErrors(mFixed);
  // Literal als erstes Argument: nicht zuweisbar, also Inline-Variable.
  mSource := Source('  Trim('' a '');'#10);
  mFixed := Fixed(mSource, TRuleAssert.Findings(TIgnoredResultRule.Create, mSource));
  Assert.AreEqual(Source('  var Ergebnis := Trim('' a '');'#10), mFixed);
end;

procedure TIgnoredResultTests.InlineVariableNeedsBlockAndVersion;
var
  mFound: TArray<TRuleFinding>;
  mContext: TRuleContext;
begin
  // Nach then ist keine Inline-Variable erlaubt; Zurückschreiben geht trotzdem.
  mFound := TRuleAssert.Findings(TIgnoredResultRule.Create, Source('  if Zahl > 0 then'#10'    IntToStr(Zahl);'#10 +
    '  if Zahl > 1 then'#10'    Trim(S);'#10));
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual(1, Integer(Length(mFound[1].Fixes)));
  // Delphi 10.2 (BDS 19.0) kennt keine Inline-Variablen.
  mContext := Default(TRuleContext);
  mContext.Text := Source('  IntToStr(Zahl);'#10);
  mContext.DelphiVersion := '19.0';
  mFound := TRuleAssert.ContextFindings(TIgnoredResultRule.Create, mContext, '');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TIgnoredResultTests.SilentCases;
begin
  // Verwendetes Ergebnis, Prozedur, eigene Routine gleichen Namens mit var-Parameter, Methode eines Objekts,
  // with-Block, ToInteger als Prüfung.
  TRuleAssert.Silent(TIgnoredResultRule.Create, Source('  S := Trim(S);'#10'  if Trim(S) = '''' then'#10 +
    '    Exit;'#10'  Pfad := S.Replace(''a'', ''b'').Trim;'#10'  SetLength(S, 2);'#10'  Delete(S, 1, 1);'#10 +
    '  S.ToInteger;'#10));
  TRuleAssert.Silent(TIgnoredResultRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'function Trim(var A: string): string;'#10'begin'#10'  A := A + '' '';'#10'  Result := A;'#10'end;'#10 +
    'procedure Lauf(S: string);'#10'begin'#10'  Trim(S);'#10'end;'#10'end.');
  TRuleAssert.Silent(TIgnoredResultRule.Create, 'unit U;'#10'interface'#10'uses'#10'  System.Classes;'#10 +
    'implementation'#10'procedure Lauf(L: TStringList; W: TObject);'#10'begin'#10'  L.Insert(0, ''a'');'#10 +
    '  L.Remove(''a'');'#10'  with W do'#10'    Format(''%d'', [1]);'#10'end;'#10'end.');
end;

procedure TIgnoredResultTests.OwnFunctionFromIndexIsSilent;
var
  mIndex: ISymbolIndex;
  mSource: string;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Werk.Text;'#10'interface'#10 +
    'function UpperCase(var A: string): string;'#10'implementation'#10'function UpperCase(var A: string): string;'#10 +
    'begin'#10'  Result := A;'#10'end;'#10'end.', 'C:\P\Werk.Text.pas', nil));
  mSource := 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils, Werk.Text;'#10 +
    'procedure Lauf(S: string);'#10'begin'#10'  UpperCase(S);'#10'  Trim(S);'#10'end;'#10'end.';
  Assert.AreEqual('8: Das Ergebnis von Trim wird verworfen: Die Funktion hat keine Seiteneffekte, der Aufruf ' +
    'bewirkt nichts.|', Messages(TRuleAssert.IndexFindings(TIgnoredResultRule.Create, mSource, mIndex, '',
    'U.pas')));
end;

procedure TIgnoredResultTests.RuleCanBeTurnedOff;
const
  cBody = '  Trim(S);'#10;
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TIgnoredResultRule.Create, Source(cBody)))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TIgnoredResultRule.Create, Source(cBody),
    '{"rules": {"ignored-result": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TIgnoredResultRule.Create, Source(cBody),
    '{"rules": {"group:find-bugs": "off"}}'))));
end;

procedure TIgnoredResultTests.CatalogListsAllPureRoutines;
var
  mEntry: TRuleCatalogEntry;
  mGroup: TPureRoutineGroup;
  mName: string;
begin
  // Der Regelkatalog nennt die Liste je Unit (#145); neue Namen in Pascal.PureRoutines gehören auch dorthin.
  Assert.IsTrue(TRuleCatalog.Shared.TryFind(cIgnoredResultRuleId, mEntry));
  for mGroup in TPureRoutines.Groups do
  begin
    Assert.Contains(mEntry.Description, mGroup.UnitName + ':');
    for mName in mGroup.Names.Split([',']) do
    begin
      Assert.IsTrue(Pos(mName, mEntry.Description) > 0, mName);
    end;
  end;
  for mName in TPureRoutines.StringMembers do
  begin
    Assert.IsTrue(Pos(mName, mEntry.Description) > 0, mName);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIgnoredResultTests);

end.
