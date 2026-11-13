unit Atlas.Core.Debug.Logpoint.Tests;

// Tests für Logpunkte (#583): Platzhaltertext, Eigenschaften des Haltepunkts, Zusammenführen im Protokoll.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasLogpointTests = class
  public
    /// <summary>Text und Platzhalter mit Formatangabe.</summary>
    [Test]
    procedure ParsesPlaceholders;
    /// <summary>„{{“ und „}}“ sind Klammern im Text.</summary>
    [Test]
    procedure KeepsEscapedBraces;
    /// <summary>Fehlende „}“, einzelne „}“ und leerer Platzhalter mit Stelle.</summary>
    [Test]
    procedure ReportsErrors;
    /// <summary>Doppelpunkt in Klammern, Strings und „:=“ ist keine Formatangabe.</summary>
    [Test]
    procedure SplitsFormatOutsideBrackets;
    /// <summary>Ohne Platzhalter nur die Meldung, mit Ort.</summary>
    [Test]
    procedure PlainMessage;
    /// <summary>Ein Platzhalter ohne Angabe: die IDE wertet aus, „{0}“ in der Meldung.</summary>
    [Test]
    procedure SingleExpressionByIde;
    /// <summary>Mehrere oder formatierte Platzhalter: ein zusammengesetzter Ausdruck.</summary>
    [Test]
    procedure ConcatenatesParts;
    /// <summary>Bedingung ohne Klammern, Trefferzahl nicht negativ.</summary>
    [Test]
    procedure ConditionAndPassCount;
    /// <summary>Meldung und Wert werden eine Zeile; fremde Zeilen bleiben.</summary>
    [Test]
    procedure MergesMessageAndValue;
    /// <summary>Wert aus der Ausdruckszeile der IDE.</summary>
    [Test]
    procedure ReadsValue;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Logpoint;

procedure TAtlasLogpointTests.ParsesPlaceholders;
var
  mTemplate: TAtlasLogpointTemplate;
begin
  mTemplate := TAtlasLogpointTemplate.Parse('Kunde {Kunde.Name}, Summe {Summe:0.00}');
  Assert.IsTrue(mTemplate.Valid);
  Assert.AreEqual(Integer(4), Integer(Length(mTemplate.Parts)));
  Assert.AreEqual('Kunde ', mTemplate.Parts[0].Text);
  Assert.AreEqual(Ord(TAtlasLogpointPartKind.Expression), Ord(mTemplate.Parts[1].Kind));
  Assert.AreEqual('Kunde.Name', mTemplate.Parts[1].Text);
  Assert.AreEqual('', mTemplate.Parts[1].Format);
  Assert.AreEqual(', Summe ', mTemplate.Parts[2].Text);
  Assert.AreEqual('Summe', mTemplate.Parts[3].Text);
  Assert.AreEqual('0.00', mTemplate.Parts[3].Format);
  Assert.AreEqual('Kunde.Name,Summe', string.Join(',', mTemplate.Expressions));
end;

procedure TAtlasLogpointTests.KeepsEscapedBraces;
var
  mTemplate: TAtlasLogpointTemplate;
begin
  mTemplate := TAtlasLogpointTemplate.Parse('Menge {{a}} = {a}}}');
  Assert.IsTrue(mTemplate.Valid);
  Assert.AreEqual('Menge {a} = ', mTemplate.Parts[0].Text);
  Assert.AreEqual('a', mTemplate.Parts[1].Text);
  Assert.AreEqual('}', mTemplate.Parts[2].Text);
end;

procedure TAtlasLogpointTests.ReportsErrors;
var
  mTemplate: TAtlasLogpointTemplate;
begin
  mTemplate := TAtlasLogpointTemplate.Parse('x={x');
  Assert.AreEqual(Ord(TAtlasLogpointError.MissingClose), Ord(mTemplate.Error));
  Assert.AreEqual(Integer(3), mTemplate.ErrorPos);
  mTemplate := TAtlasLogpointTemplate.Parse('x}=1');
  Assert.AreEqual(Ord(TAtlasLogpointError.StrayClose), Ord(mTemplate.Error));
  Assert.AreEqual(Integer(2), mTemplate.ErrorPos);
  mTemplate := TAtlasLogpointTemplate.Parse('a { } b');
  Assert.AreEqual(Ord(TAtlasLogpointError.EmptyPlaceholder), Ord(mTemplate.Error));
  Assert.IsFalse(mTemplate.Valid);
end;

procedure TAtlasLogpointTests.SplitsFormatOutsideBrackets;
var
  mTemplate: TAtlasLogpointTemplate;
begin
  mTemplate := TAtlasLogpointTemplate.Parse('{Liste[i:j]}');
  Assert.AreEqual('Liste[i:j]', mTemplate.Parts[0].Text);
  Assert.AreEqual('', mTemplate.Parts[0].Format);
  mTemplate := TAtlasLogpointTemplate.Parse('{Text = ''a:b'':s}');
  Assert.AreEqual('Text = ''a:b''', mTemplate.Parts[0].Text);
  Assert.AreEqual('s', mTemplate.Parts[0].Format);
  mTemplate := TAtlasLogpointTemplate.Parse('{x:=1}');
  Assert.AreEqual('x:=1', mTemplate.Parts[0].Text);
end;

procedure TAtlasLogpointTests.PlainMessage;
var
  mPlan: TAtlasLogpointPlan;
begin
  mPlan := TAtlasLogpointPlan.Build(TAtlasLogpointTemplate.Parse('hier {{1}}'), '[LOG]', 'Unit1.pas:12', '', 0);
  Assert.AreEqual('[LOG] hier {1} · Unit1.pas:12', mPlan.LogMessage);
  Assert.AreEqual('', mPlan.EvalExpression);
end;

procedure TAtlasLogpointTests.SingleExpressionByIde;
var
  mPlan: TAtlasLogpointPlan;
begin
  mPlan := TAtlasLogpointPlan.Build(TAtlasLogpointTemplate.Parse('x={x}'), '[LOG]', 'Unit1.pas:12', '', 0);
  Assert.AreEqual('[LOG] x={0} · Unit1.pas:12', mPlan.LogMessage);
  Assert.AreEqual('x', mPlan.EvalExpression);
  mPlan := TAtlasLogpointPlan.Build(TAtlasLogpointTemplate.Parse('x={x}'), '', '', '', 0);
  Assert.AreEqual('x={0}', mPlan.LogMessage, 'ohne Präfix und Ort');
end;

procedure TAtlasLogpointTests.ConcatenatesParts;
var
  mPlan: TAtlasLogpointPlan;
begin
  mPlan := TAtlasLogpointPlan.Build(TAtlasLogpointTemplate.Parse('Kunde {Name}, Summe {Summe:0.00}, n={n:d}'),
    '[LOG]', '', '', 0);
  Assert.AreEqual('[LOG] {0}', mPlan.LogMessage);
  Assert.AreEqual('''Kunde '' + (Name) + '', Summe '' + FormatFloat(''0.00'', Summe) + '', n='' + IntToStr(n)',
    mPlan.EvalExpression);
  mPlan := TAtlasLogpointPlan.Build(TAtlasLogpointTemplate.Parse('{h:x} {v:.2f} {''it''''s''}'), '', '', '', 0);
  Assert.AreEqual('IntToHex(h) + '' '' + Format(''%.2f'', [v]) + '' '' + (''it''''s'')', mPlan.EvalExpression);
end;

procedure TAtlasLogpointTests.ConditionAndPassCount;
var
  mPlan: TAtlasLogpointPlan;
begin
  mPlan := TAtlasLogpointPlan.Build(TAtlasLogpointTemplate.Parse('a'), '[LOG]', '', ' {Summe} > 1000 ', -3);
  Assert.AreEqual('Summe > 1000', mPlan.Condition);
  Assert.AreEqual(Integer(0), mPlan.PassCount);
  mPlan := TAtlasLogpointPlan.Build(TAtlasLogpointTemplate.Parse('a'), '[LOG]', '', '', 5);
  Assert.AreEqual(Integer(5), mPlan.PassCount);
end;

procedure TAtlasLogpointTests.MergesMessageAndValue;
var
  mMerger: TAtlasLogpointMerger;
  mOutput: string;
  mIsLogpoint: Boolean;
begin
  mMerger := TAtlasLogpointMerger.Create('[LOG]');
  try
    Assert.IsFalse(mMerger.Feed('[LOG] x={0} · Unit1.pas:12', mOutput, mIsLogpoint), 'wartet auf den Wert');
    Assert.IsTrue(mIsLogpoint);
    Assert.IsTrue(mMerger.Pending);
    Assert.IsTrue(mMerger.Feed('x: 42', mOutput, mIsLogpoint));
    Assert.IsFalse(mMerger.Pending);
    Assert.IsTrue(mIsLogpoint);
    Assert.AreEqual('[LOG] x=42 · Unit1.pas:12', mOutput);
    Assert.IsTrue(mMerger.Feed('[log] fertig', mOutput, mIsLogpoint));
    Assert.AreEqual('[log] fertig', mOutput);
    Assert.IsFalse(mMerger.Feed('anderer Haltepunkt', mOutput, mIsLogpoint));
    Assert.IsFalse(mIsLogpoint);
  finally
    mMerger.Free;
  end;
end;

procedure TAtlasLogpointTests.ReadsValue;
begin
  Assert.AreEqual('42', TAtlasLogpointMerger.ValueOf('x: 42'));
  Assert.AreEqual('42', TAtlasLogpointMerger.ValueOf('x = 42'));
  Assert.AreEqual('it''s', TAtlasLogpointMerger.ValueOf('Name: ''it''''s'''));
  Assert.AreEqual('nur', TAtlasLogpointMerger.ValueOf(' nur '));
end;

end.
