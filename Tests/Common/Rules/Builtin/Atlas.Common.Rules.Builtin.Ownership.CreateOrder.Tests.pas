unit Atlas.Common.Rules.Builtin.Ownership.CreateOrder.Tests;

// Tests für multiple-create-in-try.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCreateOrderRuleTests = class
  public
    [Test]
    procedure IssueExampleBeforeTry;
    [Test]
    procedure CreatesInsideTryWithoutNil;
    [Test]
    procedure ThreeObjects;
    [Test]
    procedure OtherFreedVariables;
    [Test]
    procedure InlineVariables;
    [Test]
    procedure StatementBetweenSafeCreates;
    [Test]
    procedure SilentCases;
    [Test]
    procedure NoDuplicateWithLeakRules;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Ownership.LocalObjects,
  Atlas.Common.Rules.Builtin.Ownership.CreateOrder,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Routine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.Classes;'#10 +
    'procedure Laden(const AFile: string);'#10'var'#10 + AVars + 'begin'#10 + ABody + 'end;'#10'end.';
end;

const
  cVars = '  mList: TStringList;'#10'  mStream: TFileStream;'#10;
  cFinally = '  finally'#10'    mStream.Free;'#10'    mList.Free;'#10'  end;'#10;

procedure TCreateOrderRuleTests.IssueExampleBeforeTry;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine(cVars, '  mList := TStringList.Create;'#10'  mStream := TFileStream.Create(AFile, fmOpenRead);'#10 +
    '  try'#10'    mList.LoadFromStream(mStream);'#10 + cFinally);
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('multiple-create-in-try', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual('Scheitert TFileStream.Create, wird mList nicht freigegeben.', mFindings[0].Message);
  Assert.AreEqual(11, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(13, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.IsTrue(mFindings[0].Fixes[0].Safe, 'sichere Korrektur');
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(Routine(cVars, '  mList := nil;'#10'  mStream := nil;'#10'  try'#10 +
    '    mList := TStringList.Create;'#10'    mStream := TFileStream.Create(AFile, fmOpenRead);'#10 +
    '    mList.LoadFromStream(mStream);'#10 + cFinally), mFixed);
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, mFixed);
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, mFixed);
end;

procedure TCreateOrderRuleTests.CreatesInsideTryWithoutNil;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine(cVars, '  try'#10'    mList := TStringList.Create;'#10 +
    '    mStream := TFileStream.Create(AFile, fmOpenRead);'#10'    mList.LoadFromStream(mStream);'#10 + cFinally);
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Scheitert ein Create im try, gibt das finally die nicht vorbelegten Variablen mList, mStream frei.',
    mFindings[0].Message);
  // An der ersten Freigabe.
  Assert.AreEqual(15, mFindings[0].Range.StartPos.Line);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(Routine(cVars, '  mList := nil;'#10'  mStream := nil;'#10'  try'#10'    mList := TStringList.Create;'#10 +
    '    mStream := TFileStream.Create(AFile, fmOpenRead);'#10'    mList.LoadFromStream(mStream);'#10 + cFinally),
    mFixed);
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, mFixed);
  // Nur eine Variable vorbelegt: die andere wird genannt.
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, Routine(cVars, '  mList := nil;'#10'  try'#10 +
    '    mList := TStringList.Create;'#10'    mStream := TFileStream.Create(AFile, fmOpenRead);'#10 + cFinally));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'Variable mStream frei');
end;

procedure TCreateOrderRuleTests.ThreeObjects;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine(cVars + '  mReader: TStreamReader;'#10, '  mList := TStringList.Create;'#10 +
    '  mStream := TFileStream.Create(AFile, fmOpenRead);'#10'  mReader := TStreamReader.Create(mStream);'#10'  try'#10 +
    '    mList.Text := mReader.ReadToEnd;'#10'  finally'#10'    mReader.Free;'#10'    mStream.Free;'#10 +
    '    mList.Free;'#10'  end;'#10);
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Scheitert TStreamReader.Create, werden mList, mStream nicht freigegeben.', mFindings[1].Message);
  // Die Korrektur hängt nur am ersten Befund und ändert alle drei.
  Assert.AreEqual(0, Integer(Length(mFindings[1].Fixes)));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.Contains(mFixed, '  mList := nil;'#10'  mStream := nil;'#10'  mReader := nil;'#10'  try'#10 +
    '    mList := TStringList.Create;'#10'    mStream := TFileStream.Create(AFile, fmOpenRead);'#10 +
    '    mReader := TStreamReader.Create(mStream);'#10'    mList.Text := mReader.ReadToEnd;'#10);
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, mFixed);
end;

procedure TCreateOrderRuleTests.OtherFreedVariables;
const
  cReader = '  mReader: TStreamReader;'#10;
  cFreeAll = '  finally'#10'    mReader.Free;'#10'    mStream.Free;'#10'    mList.Free;'#10'  end;'#10;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Eine weitere freigegebene Variable, die mit ins try wandert, wird ebenfalls vorbelegt.
  mSource := Routine(cVars + cReader, '  mList := TStringList.Create;'#10 +
    '  mStream := TFileStream.Create(AFile, fmOpenRead);'#10'  mReader := OpenReader(mStream);'#10'  try'#10 +
    '    mList.Text := mReader.ReadToEnd;'#10 + cFreeAll);
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.Contains(mFixed, '  mList := nil;'#10'  mStream := nil;'#10'  mReader := nil;'#10'  try'#10);
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, mFixed);
  // Typ unbekannt (vielleicht ein Record): Befund ohne Korrektur.
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, Routine(cVars + '  mReader: TUnbekannt;'#10,
    '  mList := TStringList.Create;'#10'  mStream := TFileStream.Create(AFile, fmOpenRead);'#10 +
    '  mReader := OpenReader(mStream);'#10'  try'#10'    mList.Text := mReader.ReadToEnd;'#10 + cFreeAll));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Im try: eine nach dem ersten Create zugewiesene Variable und TStringBuilder ohne Vorbelegung.
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, Routine(cVars + cReader +
    '  mText: TStringBuilder;'#10, '  mList := nil;'#10'  mStream := nil;'#10'  try'#10 +
    '    mList := TStringList.Create;'#10'    mStream := TFileStream.Create(AFile, fmOpenRead);'#10 +
    '    mReader := OpenReader(mStream);'#10'    mText := TStringBuilder.Create;'#10'  finally'#10 +
    '    mText.Free;'#10'    mReader.Free;'#10'    mStream.Free;'#10'    mList.Free;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'Variablen mReader, mText frei');
end;

procedure TCreateOrderRuleTests.InlineVariables;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine('  mDummy: Integer;'#10, '  var mList := TStringList.Create;'#10 +
    '  var mStream: TStream := TFileStream.Create(AFile, fmOpenRead);'#10'  try'#10 +
    '    mList.LoadFromStream(mStream);'#10 + cFinally);
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(Routine('  mDummy: Integer;'#10, '  var mList: TStringList := nil;'#10 +
    '  var mStream: TStream := nil;'#10'  try'#10'    mList := TStringList.Create;'#10 +
    '    mStream := TFileStream.Create(AFile, fmOpenRead);'#10'    mList.LoadFromStream(mStream);'#10 + cFinally),
    mFixed);
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, mFixed);
end;

procedure TCreateOrderRuleTests.StatementBetweenSafeCreates;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMultipleCreateInTryRule.Create, Routine('  mA, mB: TStringList;'#10,
    '  mA := TStringList.Create;'#10'  mA.LoadFromFile(AFile);'#10'  mB := TStringList.Create;'#10'  try'#10 +
    '    mB.Assign(mA);'#10'  finally'#10'    mB.Free;'#10'    mA.Free;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Löst eine Anweisung vor dem try eine Ausnahme aus, wird mA nicht freigegeben.',
    mFindings[0].Message);
end;

procedure TCreateOrderRuleTests.SilentCases;
begin
  // Verschachtelte try … finally je Objekt (Gegenbeispiel aus dem Issue).
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, Routine(cVars, '  mList := TStringList.Create;'#10'  try'#10 +
    '    mStream := TFileStream.Create(AFile, fmOpenRead);'#10'    try'#10'      mList.LoadFromStream(mStream);'#10 +
    '    finally'#10'      mStream.Free;'#10'    end;'#10'  finally'#10'    mList.Free;'#10'  end;'#10));
  // Nur sichere Konstruktoren ohne Argumente und nichts dazwischen.
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, Routine('  mA: TStringList;'#10'  mB: TObject;'#10,
    '  mA := TStringList.Create;'#10'  mB := TObject.Create;'#10'  try'#10'    Work(mA, mB);'#10'  finally'#10 +
    '    mB.Free;'#10'    mA.Free;'#10'  end;'#10));
  // Sammlungen auch mit Argumenten (Besitz, Kapazität) und einfache Behälter ohne Argumente.
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, Routine('  mA: TStringList;'#10 +
    '  mB: TObjectDictionary<string, TObject>;'#10'  mC: TStack<Integer>;'#10'  mD: TMemoryStream;'#10,
    '  mA := TStringList.Create;'#10'  mB := TObjectDictionary<string, TObject>.Create([doOwnsValues]);'#10 +
    '  mC := TStack<Integer>.Create;'#10'  mD := TMemoryStream.Create;'#10'  try'#10'    Work(mA, mB, mC, mD);'#10 +
    '  finally'#10'    mD.Free;'#10'    mC.Free;'#10'    mB.Free;'#10'    mA.Free;'#10'  end;'#10));
  // Ein einziges Objekt; Interface-Variable; Komponente mit Owner; unbekannte Klasse (Record möglich).
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, Routine('  mList: TStringList;'#10,
    '  mList := TStringList.Create;'#10'  mList.LoadFromFile(AFile);'#10'  try'#10'    Work(mList);'#10'  finally'#10 +
    '    mList.Free;'#10'  end;'#10));
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, Routine('  mList: TStringList;'#10'  mIntf: IInterface;'#10 +
    '  mPoint: TKunde;'#10, '  mList := TStringList.Create;'#10'  mIntf := TInterfacedObject.Create;'#10 +
    '  mPoint := TKunde.Create(1);'#10'  try'#10'    Work(mList);'#10'  finally'#10'    mIntf.Free;'#10 +
    '    mPoint.Free;'#10'    mList.Free;'#10'  end;'#10));
  // Im try, beide vorher auf nil gesetzt; Feld statt lokaler Variable.
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, Routine(cVars, '  mList := nil;'#10'  mStream := nil;'#10 +
    '  try'#10'    mList := TStringList.Create;'#10'    mStream := TFileStream.Create(AFile, fmOpenRead);'#10 + cFinally));
  TRuleAssert.Silent(TMultipleCreateInTryRule.Create, Routine(cVars, '  FList := TStringList.Create;'#10 +
    '  FStream := TFileStream.Create(AFile, fmOpenRead);'#10'  try'#10'    Work;'#10'  finally'#10 +
    '    FStream.Free;'#10'    FList.Free;'#10'  end;'#10));
end;

procedure TCreateOrderRuleTests.NoDuplicateWithLeakRules;
var
  mSource: string;
begin
  // Die Objekte werden freigegeben: local-object-not-freed schweigt, nur diese Regel meldet.
  mSource := Routine(cVars, '  mList := TStringList.Create;'#10'  mStream := TFileStream.Create(AFile, fmOpenRead);'#10 +
    '  try'#10'    mList.LoadFromStream(mStream);'#10 + cFinally);
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, mSource);
  TRuleAssert.Silent(TCreatedResultNotFreedRule.Create, mSource);
  TRuleAssert.Reports(TMultipleCreateInTryRule.Create, mSource, 1);
end;

procedure TCreateOrderRuleTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Routine(cVars, '  mList := TStringList.Create;'#10'  mStream := TFileStream.Create(AFile, fmOpenRead);'#10 +
    '  try'#10'    Work;'#10 + cFinally);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMultipleCreateInTryRule.Create, mSource,
    '{"rules": {"multiple-create-in-try": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMultipleCreateInTryRule.Create, mSource,
    '{"rules": {"multiple-create-in-try": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TCreateOrderRuleTests);

end.
