unit Atlas.Common.Editing.PostfixTemplates.Tests;

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
    [Test]
    procedure AppliesNewTemplates;
    [Test]
    procedure ExpandsNewTemplates;
    [Test]
    procedure SnippetPlaceholders;
    [Test]
    procedure CustomConditions;
    [Test]
    procedure CustomTextReplacesExpression;
    [Test]
    procedure SuggestsNames;
    [Test]
    procedure ListsThirteenTemplates;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.PostfixTemplates;

procedure TPostfixTemplatesTests.ExpandsAllTemplates;
begin
  // Nach einem Kopf steht der Cursor eingerückt in der Folgezeile.
  Assert.AreEqual('for var Item in Liste do'#13#10'    ',
    TPostfixTemplates.Expand('for', 'Liste', '  ', #13#10, True));
  Assert.AreEqual('for Item in Liste do'#13#10'    ', TPostfixTemplates.Expand('for', 'Liste', '  ', #13#10, False));
  Assert.AreEqual('try'#13#10'    '#13#10'  finally'#13#10'    Obj.Free;'#13#10'  end;',
    TPostfixTemplates.Expand('tryf', 'Obj', '  ', #13#10, True));
  Assert.AreEqual('if Assigned(X) then'#10'  ', TPostfixTemplates.Expand('ifa', 'X', '', #10, True));
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

procedure TPostfixTemplatesTests.AppliesNewTemplates;
var
  Traits: TPostfixTraits;
begin
  Traits := Default(TPostfixTraits);
  Assert.IsFalse(TPostfixTemplates.Applies('not', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('exit', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('try', Traits, True));
  // var geht mit Inline-Variable immer, klassisch nur mit bekanntem Typ.
  Assert.IsTrue(TPostfixTemplates.Applies('var', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('var', Traits, False));
  Traits.IsBoolean := True;
  Assert.IsTrue(TPostfixTemplates.Applies('not', Traits, True));
  Assert.IsTrue(TPostfixTemplates.Applies('if', Traits, True));
  Traits := Default(TPostfixTraits);
  Traits.IsReference := True;
  Assert.IsTrue(TPostfixTemplates.Applies('notnil', Traits, True));
  Assert.IsTrue(TPostfixTemplates.Applies('nil', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('free', Traits, True));
  Traits.IsClass := True;
  Assert.IsTrue(TPostfixTemplates.Applies('free', Traits, True));
  Traits.IsConstructorCall := True;
  Assert.IsTrue(TPostfixTemplates.Applies('try', Traits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('try', Traits, False));
  Traits.TypeName := 'TFoo';
  Assert.IsTrue(TPostfixTemplates.Applies('try', Traits, False));
  Traits.InFunction := True;
  Assert.IsTrue(TPostfixTemplates.Applies('exit', Traits, True));
  Traits := Default(TPostfixTraits);
  Traits.Enumerable := True;
  Assert.IsTrue(TPostfixTemplates.Applies('forin', Traits, True));
end;

procedure TPostfixTemplatesTests.ExpandsNewTemplates;
var
  Traits: TPostfixTraits;
  Expansion: TPostfixExpansion;
  Template: TPostfixTemplate;
begin
  Assert.AreEqual('if not Assigned(X) then'#10'    ', TPostfixTemplates.Expand('nil', 'X', '  ', #10, True));
  Assert.AreEqual('not B', TPostfixTemplates.Expand('not', 'B', '  ', #10, True));
  Assert.AreEqual('if B then'#10'    ', TPostfixTemplates.Expand('if', 'B', '  ', #10, True));
  Assert.AreEqual('FreeAndNil(Obj);', TPostfixTemplates.Expand('free', 'Obj', '  ', #10, True));
  Assert.AreEqual('Exit(X);', TPostfixTemplates.Expand('exit', 'X', '  ', #10, True));
  Traits := Default(TPostfixTraits);
  Traits.TypeName := 'TStringList';
  Template := Default(TPostfixTemplate);
  Template.Key := 'try';
  Expansion := TPostfixTemplates.Expand(Template, 'TStringList.Create', '  ', #10, Traits, True, False);
  Assert.AreEqual('var StringList := TStringList.Create;'#10'  try'#10'    '#10'  finally'#10 +
    '    StringList.Free;'#10'  end;', Expansion.Text);
  Assert.AreEqual('', Expansion.Declaration);
  Expansion := TPostfixTemplates.Expand(Template, 'TStringList.Create', '  ', #10, Traits, False, False);
  Assert.IsTrue(Expansion.Text.StartsWith('StringList := TStringList.Create;'));
  Assert.AreEqual('StringList: TStringList;', Expansion.Declaration);
  Template.Key := 'var';
  Expansion := TPostfixTemplates.Expand(Template, 'Liste', '  ', #10, Traits, False, False);
  Assert.AreEqual('StringList := Liste;', Expansion.Text);
  Assert.AreEqual('StringList: TStringList;', Expansion.Declaration);
end;

procedure TPostfixTemplatesTests.SnippetPlaceholders;
var
  Traits: TPostfixTraits;
  Template: TPostfixTemplate;
begin
  Traits := Default(TPostfixTraits);
  Template := Default(TPostfixTemplate);
  Template.Key := 'for';
  Assert.AreEqual('for var ${1:Item} in Liste do'#10'  $0',
    TPostfixTemplates.Expand(Template, 'Liste', '', #10, Traits, True, True).Text);
  // Klassisch kein Platzhalter für den Namen, der auch in der Deklaration steht.
  Assert.AreEqual('for Item in Liste do'#10'  $0',
    TPostfixTemplates.Expand(Template, 'Liste', '', #10, Traits, False, True).Text);
  Template.Key := 'fmt';
  Assert.AreEqual('Format(S, [$0])', TPostfixTemplates.Expand(Template, 'S', '', #10, Traits, True, True).Text);
  // Der Ausdruck wird maskiert.
  Template.Key := 'notnil';
  Assert.AreEqual('if Assigned(A\\\$B) then'#10'  $0',
    TPostfixTemplates.Expand(Template, 'A\$B', '', #10, Traits, True, True).Text);
  Assert.AreEqual('a\\b\$c\}', TPostfixTemplates.Escape('a\b$c}'));
end;

procedure TPostfixTemplatesTests.CustomConditions;
var
  Traits: TPostfixTraits;
  Descends: TFunc<string, Boolean>;
begin
  Traits := Default(TPostfixTraits);
  Traits.IsClass := True;
  Traits.TypeName := 'TKunde';
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', ''), Traits, True, nil));
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'any'), Traits, True, nil));
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'class'), Traits, True, nil));
  Assert.IsFalse(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'string'), Traits, True, nil));
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'tkunde'), Traits, True, nil));
  Assert.IsFalse(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'TBasis'), Traits, True, nil));
  Descends :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'TBasis');
    end;
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'TBasis'), Traits, True, Descends));
  Assert.IsTrue(TPostfixTemplates.IsTypeCondition('TBasis'));
  Assert.IsFalse(TPostfixTemplates.IsTypeCondition('enumerable'));
  Assert.IsFalse(TPostfixTemplates.IsTypeCondition(''));
end;

procedure TPostfixTemplatesTests.CustomTextReplacesExpression;
begin
  Assert.AreEqual('Log(Wert);', TPostfixTemplates.CustomText('Log($expr);', 'Wert', '  ', #10, False));
  Assert.AreEqual('if ${1:Ok}(Wert) then'#10'    $0',
    TPostfixTemplates.CustomText('if ${1:Ok}($expr) then'#10'  $0', 'Wert', '  ', #10, True));
  // Klartext: Vorgabe statt Platzhalter, "$$" wird zu "$".
  Assert.AreEqual('if Ok(Wert) then'#13#10'    ',
    TPostfixTemplates.CustomText('if ${1:Ok}($expr) then'#13#10'  $0', 'Wert', '  ', #13#10, False));
  Assert.AreEqual('$Wert', TPostfixTemplates.CustomText('$$$expr', 'Wert', '', #10, False));
  Assert.AreEqual('\$Wert', TPostfixTemplates.CustomText('$$$expr', 'Wert', '', #10, True));
end;

procedure TPostfixTemplatesTests.SuggestsNames;
begin
  Assert.AreEqual('StringList', TPostfixTemplates.SuggestName('TStringList'));
  Assert.AreEqual('Kunde', TPostfixTemplates.SuggestName('System.Classes.TKunde'));
  Assert.AreEqual('List', TPostfixTemplates.SuggestName('TList<Integer>'));
  Assert.AreEqual('Values', TPostfixTemplates.SuggestName('TArray<Integer>'));
  Assert.AreEqual('Value', TPostfixTemplates.SuggestName('Integer'));
  Assert.AreEqual('Value', TPostfixTemplates.SuggestName(''));
end;

procedure TPostfixTemplatesTests.ListsThirteenTemplates;
var
  Keys: string;
  Template: TPostfixTemplate;
begin
  Keys := '';
  for Template in TPostfixTemplates.Templates do
  begin
    Keys := Keys + Template.Key + ' ';
    Assert.IsFalse(Template.IsCustom);
    Assert.IsTrue(Template.Description <> '');
  end;
  Assert.AreEqual('for forin tryf ifa notnil nil not if fmt free try var exit ', Keys);
end;

initialization
  TDUnitX.RegisterTestFixture(TPostfixTemplatesTests);

end.
