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
  UnitText =
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
  Units: TArray<string>;
begin
  Assert.IsTrue(TUsesCommand.Parse('  /uses System.SysUtils, Vcl.Forms;', Units));
  Assert.AreEqual('System.SysUtils|Vcl.Forms', string.Join('|', Units));
  Assert.IsTrue(TUsesCommand.Parse('/USES X', Units));
  Assert.IsFalse(TUsesCommand.Parse('/uses ', Units));
  Assert.IsFalse(TUsesCommand.Parse('/uses A B', Units));
  Assert.IsFalse(TUsesCommand.Parse('uses A;', Units));
  Assert.IsFalse(TUsesCommand.Parse('// /uses A', Units));
end;

procedure TUsesCommandTests.AddsToImplementationAndRemovesLine;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TUsesCommand.AfterEnter(UnitText, TTextPosition.Create(7, 0), nil, Edits));
  Assert.AreEqual(2, Integer(Length(Edits)));
  Assert.AreEqual(#10#10'uses'#10'  System.SysUtils, Vcl.Forms;', Edits[0].NewText);
  Assert.AreEqual(3, Edits[0].Range.StartPos.Line);
  Assert.AreEqual('', Edits[1].NewText);
  Assert.AreEqual(6, Edits[1].Range.StartPos.Line);
  Assert.AreEqual(7, Edits[1].Range.EndPos.Line);
  Assert.AreEqual(0, Edits[1].Range.EndPos.Character);
end;

procedure TUsesCommandTests.AddsToInterfaceWhenTypedThere;
const
  Text = 'unit A;'#13#10'interface'#13#10'uses Classes;'#13#10'/uses Vcl.Forms'#13#10#13#10'implementation'#13#10'end.';
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TUsesCommand.AfterEnter(Text, TTextPosition.Create(4, 0), nil, Edits));
  Assert.AreEqual(', Vcl.Forms', Edits[0].NewText);
  Assert.AreEqual(2, Edits[0].Range.StartPos.Line);
end;

procedure TUsesCommandTests.SkipsUsedUnitsButRemovesLine;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TUsesCommand.AfterEnter(StringReplace(UnitText, 'System.SysUtils, Vcl.Forms', 'Classes', []),
    TTextPosition.Create(7, 0), nil, Edits));
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual('', Edits[0].NewText);
  Assert.IsTrue(TUsesCommand.AfterEnter(StringReplace(UnitText, 'System.SysUtils, Vcl.Forms', 'SysUtils', []),
    TTextPosition.Create(7, 0), nil, Edits));
  Assert.AreEqual(2, Integer(Length(Edits)));
end;

procedure TUsesCommandTests.IgnoresOtherLines;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(TUsesCommand.AfterEnter(UnitText, TTextPosition.Create(6, 0), nil, Edits));
  Assert.IsFalse(TUsesCommand.AfterEnter(UnitText, TTextPosition.Create(0, 0), nil, Edits));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesCommandTests);

end.
