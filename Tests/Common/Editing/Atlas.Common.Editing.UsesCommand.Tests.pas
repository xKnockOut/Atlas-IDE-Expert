unit Atlas.Common.Editing.UsesCommand.Tests;

// Tests für den Schnellbefehl /uses (#254).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesCommandTests = class
  public
    [Test]
    procedure ParsesCommandLines;
    [Test]
    procedure AddsToImplementationAndRemovesLine;
    [Test]
    procedure AddsToInterfaceWhenTypedThere;
    [Test]
    procedure SkipsUsedUnitsButRemovesLine;
    [Test]
    procedure IgnoresOtherLines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.UsesCommand;

const
  cUnitText =
    'unit A;'#10 +
    'interface'#10 +
    'uses Classes;'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  /uses System.SysUtils, Vcl.Forms;'#10 +
    #10 +
    'end;'#10 +
    'end.';

procedure TUsesCommandTests.ParsesCommandLines;
var
  mUnits: TArray<string>;
begin
  Assert.IsTrue(TUsesCommand.Parse('  /uses System.SysUtils, Vcl.Forms;', mUnits));
  Assert.AreEqual('System.SysUtils|Vcl.Forms', string.Join('|', mUnits));
  Assert.IsTrue(TUsesCommand.Parse('/USES X', mUnits));
  Assert.IsFalse(TUsesCommand.Parse('/uses ', mUnits));
  Assert.IsFalse(TUsesCommand.Parse('/uses A B', mUnits));
  Assert.IsFalse(TUsesCommand.Parse('uses A;', mUnits));
  Assert.IsFalse(TUsesCommand.Parse('// /uses A', mUnits));
end;

procedure TUsesCommandTests.AddsToImplementationAndRemovesLine;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TUsesCommand.AfterEnter(cUnitText, TTextPosition.Create(7, 0), nil, mEdits));
  Assert.AreEqual(2, Integer(Length(mEdits)));
  Assert.AreEqual(#10#10'uses'#10'  System.SysUtils, Vcl.Forms;', mEdits[0].NewText);
  Assert.AreEqual(3, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual('', mEdits[1].NewText);
  Assert.AreEqual(6, mEdits[1].Range.StartPos.Line);
  Assert.AreEqual(7, mEdits[1].Range.EndPos.Line);
  Assert.AreEqual(0, mEdits[1].Range.EndPos.Character);
end;

procedure TUsesCommandTests.AddsToInterfaceWhenTypedThere;
const
  cText = 'unit A;'#13#10'interface'#13#10'uses Classes;'#13#10'/uses Vcl.Forms'#13#10#13#10'implementation'#13#10'end.';
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TUsesCommand.AfterEnter(cText, TTextPosition.Create(4, 0), nil, mEdits));
  Assert.AreEqual(', Vcl.Forms', mEdits[0].NewText);
  Assert.AreEqual(2, mEdits[0].Range.StartPos.Line);
end;

procedure TUsesCommandTests.SkipsUsedUnitsButRemovesLine;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TUsesCommand.AfterEnter(StringReplace(cUnitText, 'System.SysUtils, Vcl.Forms', 'Classes', []),
    TTextPosition.Create(7, 0), nil, mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual('', mEdits[0].NewText);
  Assert.IsTrue(TUsesCommand.AfterEnter(StringReplace(cUnitText, 'System.SysUtils, Vcl.Forms', 'SysUtils', []),
    TTextPosition.Create(7, 0), nil, mEdits));
  Assert.AreEqual(2, Integer(Length(mEdits)));
end;

procedure TUsesCommandTests.IgnoresOtherLines;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(TUsesCommand.AfterEnter(cUnitText, TTextPosition.Create(6, 0), nil, mEdits));
  Assert.IsFalse(TUsesCommand.AfterEnter(cUnitText, TTextPosition.Create(0, 0), nil, mEdits));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesCommandTests);

end.
