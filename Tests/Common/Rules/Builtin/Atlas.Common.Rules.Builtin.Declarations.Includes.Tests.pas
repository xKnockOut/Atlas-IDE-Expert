unit Atlas.Common.Rules.Builtin.Declarations.Includes.Tests;

// Tests der Include-Dateien für declared-not-implemented: Name aus der
// Direktive, Schlüssel der Rümpfe, Rümpfe verschachtelter Include-Dateien
// (Generika, Kommentare im Namen) und Includes nur im implementation-Teil.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationIncludesTests = class
  public
    [Test]
    procedure ReadsIncludeName;
    [Test]
    procedure BuildsBodyKey;
    [Test]
    procedure CollectsNestedBodies;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Declarations.Includes;

/// <summary>Liest 'a.inc' und 'b.inc' aus festen Texten, sonst nichts.</summary>
function FixedReader: TRuleFileReader;
begin
  Result :=
    function(const AFileName: string; out AData: TBytes): Boolean
    begin
      Result := True;
      if SameText(AFileName, 'a.inc') then
      begin
        AData := TEncoding.UTF8.GetBytes('procedure TListe<T>.Add;'#10'begin'#10'end;'#10'{$I b.inc}');
      end
      else if SameText(AFileName, 'b.inc') then
      begin
        AData := TEncoding.UTF8.GetBytes('function TAussen.TInnen.{ x } Lies: Integer;'#10'begin'#10'end;');
      end
      else
      begin
        Result := False;
      end;
    end;
end;

{ TDeclarationIncludesTests }

procedure TDeclarationIncludesTests.ReadsIncludeName;
begin
  Assert.AreEqual('a.inc', TDeclarationIncludes.IncludeName('{$I a.inc}'));
  Assert.AreEqual('b c.inc', TDeclarationIncludes.IncludeName('{$INCLUDE ''b c.inc''}'));
  Assert.AreEqual('', TDeclarationIncludes.IncludeName('{$I+}'));
  Assert.AreEqual('', TDeclarationIncludes.IncludeName('{$IFDEF X}'));
end;

procedure TDeclarationIncludesTests.BuildsBodyKey;
begin
  Assert.AreEqual('tinnen.lies', TDeclarationIncludes.BodyKey('TAussen.TInnen<T>', 'Lies'));
  Assert.AreEqual('tfoo.bar', TDeclarationIncludes.BodyKey('TFoo', 'Bar'));
end;

procedure TDeclarationIncludesTests.CollectsNestedBodies;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mBodies: TStringList;
begin
  mContext := Default(TRuleContext);
  mContext.Text := 'unit U;'#10'{$I-}'#10'interface'#10'{$I x.inc}'#10'implementation'#10'{$I a.inc}'#10'end.';
  mContext.ReadFile := FixedReader;
  mTree := TPascalParser.Parse(mContext.Text);
  try
    mContext.Tree := mTree;
    Assert.IsTrue(TDeclarationIncludes.HasIncludes(mContext));
    mBodies := TDeclarationIncludes.Bodies(mContext);
    try
      Assert.AreEqual('tinnen.lies,tliste.add', mBodies.CommaText);
    finally
      mBodies.Free;
    end;
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationIncludesTests);

end.
