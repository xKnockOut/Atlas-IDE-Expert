unit Atlas.Common.Rules.Options.Tests;

// Optionen einer Prüfregel lesen (#909): Wahrheitswert, Zahl und Liste mit
// Vorgabe bei fehlender Option, falschem Typ und leerem Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleOptionsTests = class
  public
    [Test]
    procedure BoolReadsValueOrDefault;
    [Test]
    procedure IntReadsValueOrDefault;
    [Test]
    procedure StringsReadsListOrDefault;
    [Test]
    procedure NumbersReadsListOrDefault;
    [Test]
    procedure TextReadsValueOrDefault;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Options;

{ TRuleOptionsTests }

procedure TRuleOptionsTests.BoolReadsValueOrDefault;
begin
  Assert.IsFalse(TRuleOptions.Bool('{"severity": "warning", "allowCommented": false}', 'allowCommented', True));
  Assert.IsTrue(TRuleOptions.Bool('{"allowCommented": true}', 'allowCommented', False));
  Assert.IsTrue(TRuleOptions.Bool('{"allowCommented": "nein"}', 'allowCommented', True), 'falscher Typ');
  Assert.IsTrue(TRuleOptions.Bool('{"severity": "off"}', 'allowCommented', True), 'fehlt');
  Assert.IsFalse(TRuleOptions.Bool('', 'allowCommented', False), 'leer');
  Assert.IsTrue(TRuleOptions.Bool('kaputt', 'allowCommented', True), 'kein JSON');
end;

procedure TRuleOptionsTests.IntReadsValueOrDefault;
begin
  Assert.AreEqual(120, TRuleOptions.Int('{"max": 120}', 'max', 80));
  Assert.AreEqual(80, TRuleOptions.Int('{"max": 1.5}', 'max', 80), 'keine ganze Zahl');
  Assert.AreEqual(80, TRuleOptions.Int('{"max": "120"}', 'max', 80), 'Text');
  Assert.AreEqual(80, TRuleOptions.Int('', 'max', 80));
end;

procedure TRuleOptionsTests.StringsReadsListOrDefault;
var
  mItems: TArray<string>;
begin
  mItems := TRuleOptions.Strings('{"ignore": ["0", 1, "2"]}', 'ignore', ['x']);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('0', mItems[0]);
  Assert.AreEqual('2', mItems[1]);
  mItems := TRuleOptions.Strings('{"ignore": []}', 'ignore', ['x']);
  Assert.AreEqual(0, Integer(Length(mItems)), 'leere Liste ersetzt die Vorgabe');
  mItems := TRuleOptions.Strings('{}', 'ignore', ['x']);
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('x', mItems[0]);
end;

procedure TRuleOptionsTests.NumbersReadsListOrDefault;
var
  mItems: TArray<Double>;
begin
  mItems := TRuleOptions.Numbers('{"allowed": [0, -1, 2.5, "3"]}', 'allowed', [7]);
  Assert.AreEqual(3, Integer(Length(mItems)));
  Assert.AreEqual(Double(-1), mItems[1]);
  Assert.AreEqual(Double(2.5), mItems[2]);
  mItems := TRuleOptions.Numbers('{"allowed": []}', 'allowed', [7]);
  Assert.AreEqual(0, Integer(Length(mItems)), 'leere Liste ersetzt die Vorgabe');
  mItems := TRuleOptions.Numbers('{"allowed": "1"}', 'allowed', [7]);
  Assert.AreEqual(1, Integer(Length(mItems)), 'falscher Typ');
  Assert.AreEqual(Double(7), mItems[0]);
end;

procedure TRuleOptionsTests.TextReadsValueOrDefault;
begin
  Assert.AreEqual('Log.Queue', TRuleOptions.Text('{"wrapper": " Log.Queue "}', 'wrapper', 'X'));
  Assert.AreEqual('X', TRuleOptions.Text('{"wrapper": ""}', 'wrapper', 'X'), 'leer');
  Assert.AreEqual('X', TRuleOptions.Text('{"wrapper": 1}', 'wrapper', 'X'), 'falscher Typ');
  Assert.AreEqual('X', TRuleOptions.Text('', 'wrapper', 'X'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleOptionsTests);

end.
