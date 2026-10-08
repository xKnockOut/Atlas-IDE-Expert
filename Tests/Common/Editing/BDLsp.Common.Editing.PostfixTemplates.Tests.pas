unit BDLsp.Common.Editing.PostfixTemplates.Tests;

// Tests für die Postfix-Vorlagen (#188): Typprüfung und erzeugter Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPostfixTemplatesTests = class
  public
    [Test]
    procedure ExpandsAllTemplates;
    [Test]
    procedure AppliesByType;
    [Test]
    procedure ElementTypes;
    [Test]
    procedure StringAndPointerTypes;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Editing.PostfixTemplates;

procedure TPostfixTemplatesTests.ExpandsAllTemplates;
begin
  Assert.AreEqual('for var Item in Liste do', TPostfixTemplates.Expand('for', 'Liste', '  ', #13#10, True));
  Assert.AreEqual('for Item in Liste do', TPostfixTemplates.Expand('for', 'Liste', '  ', #13#10, False));
  Assert.AreEqual('try'#13#10'    '#13#10'  finally'#13#10'    Obj.Free;'#13#10'  end;',
    TPostfixTemplates.Expand('tryf', 'Obj', '  ', #13#10, True));
  Assert.AreEqual('if Assigned(X) then', TPostfixTemplates.Expand('ifa', 'X', '', #10, True));
  Assert.AreEqual('Format(S, [])', TPostfixTemplates.Expand('fmt', 'S', '', #10, True));
end;

procedure TPostfixTemplatesTests.AppliesByType;
var
  Traits: TPostfixTraits;
begin
  Traits := Default(TPostfixTraits);
  Assert.IsFalse(TPostfixTemplates.Applies('for', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('ifa', Traits, True));
  Traits.Enumerable := True;
  Assert.IsTrue(TPostfixTemplates.Applies('for', Traits, True));
  // Klassisch nur mit bekanntem Elementtyp.
  Assert.IsFalse(TPostfixTemplates.Applies('for', Traits, False));
  Traits.ElementType := 'Integer';
  Assert.IsTrue(TPostfixTemplates.Applies('for', Traits, False));
  Assert.AreEqual('Item: Integer;', TPostfixTemplates.ClassicDeclaration(Traits));
  Traits := Default(TPostfixTraits);
  Traits.IsReference := True;
  Assert.IsTrue(TPostfixTemplates.Applies('ifa', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('tryf', Traits, True));
  Traits.IsClass := True;
  Assert.IsTrue(TPostfixTemplates.Applies('tryf', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('fmt', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('unbekannt', Traits, True));
end;

procedure TPostfixTemplatesTests.ElementTypes;
begin
  Assert.AreEqual('Integer', TPostfixTemplates.ElementOf('TArray<Integer>'));
  Assert.AreEqual('TPair<string, Integer>', TPostfixTemplates.ElementOf('TArray<TPair<string, Integer>>'));
  Assert.AreEqual('string', TPostfixTemplates.ElementOf('array of string'));
  Assert.AreEqual('Byte', TPostfixTemplates.ElementOf('array[0..9] of Byte'));
  Assert.AreEqual('TFarbe', TPostfixTemplates.ElementOf('set of TFarbe'));
  Assert.AreEqual('', TPostfixTemplates.ElementOf('array of const'));
  Assert.AreEqual('', TPostfixTemplates.ElementOf('TStringList'));
end;

procedure TPostfixTemplatesTests.StringAndPointerTypes;
begin
  Assert.IsTrue(TPostfixTemplates.IsStringType('string'));
  Assert.IsTrue(TPostfixTemplates.IsStringType('AnsiString'));
  Assert.IsFalse(TPostfixTemplates.IsStringType('Char'));
  Assert.IsTrue(TPostfixTemplates.IsPointerType('Pointer'));
  Assert.IsTrue(TPostfixTemplates.IsPointerType('^TKunde'));
  Assert.IsFalse(TPostfixTemplates.IsPointerType('TKunde'));
end;

initialization
  TDUnitX.RegisterTestFixture(TPostfixTemplatesTests);

end.
