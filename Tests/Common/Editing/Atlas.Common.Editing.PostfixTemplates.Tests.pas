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
  mTraits: TPostfixTraits;
begin
  mTraits := Default(TPostfixTraits);
  Assert.IsFalse(TPostfixTemplates.Applies('for', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('ifa', mTraits, True));
  mTraits.Enumerable := True;
  Assert.IsTrue(TPostfixTemplates.Applies('for', mTraits, True));
  // Klassisch nur mit bekanntem Elementtyp.
  Assert.IsFalse(TPostfixTemplates.Applies('for', mTraits, False));
  mTraits.ElementType := 'Integer';
  Assert.IsTrue(TPostfixTemplates.Applies('for', mTraits, False));
  Assert.AreEqual('Item: Integer;', TPostfixTemplates.ClassicDeclaration(mTraits));
  mTraits := Default(TPostfixTraits);
  mTraits.IsReference := True;
  Assert.IsTrue(TPostfixTemplates.Applies('ifa', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('tryf', mTraits, True));
  mTraits.IsClass := True;
  Assert.IsTrue(TPostfixTemplates.Applies('tryf', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('fmt', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('unbekannt', mTraits, True));
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
  mTraits: TPostfixTraits;
begin
  mTraits := Default(TPostfixTraits);
  Assert.IsFalse(TPostfixTemplates.Applies('not', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('exit', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('try', mTraits, True));
  // var geht mit Inline-Variable immer, klassisch nur mit bekanntem Typ.
  Assert.IsTrue(TPostfixTemplates.Applies('var', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('var', mTraits, False));
  mTraits.IsBoolean := True;
  Assert.IsTrue(TPostfixTemplates.Applies('not', mTraits, True));
  Assert.IsTrue(TPostfixTemplates.Applies('if', mTraits, True));
  mTraits := Default(TPostfixTraits);
  mTraits.IsReference := True;
  Assert.IsTrue(TPostfixTemplates.Applies('notnil', mTraits, True));
  Assert.IsTrue(TPostfixTemplates.Applies('nil', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('free', mTraits, True));
  mTraits.IsClass := True;
  Assert.IsTrue(TPostfixTemplates.Applies('free', mTraits, True));
  mTraits.IsConstructorCall := True;
  Assert.IsTrue(TPostfixTemplates.Applies('try', mTraits, True));
  Assert.IsFalse(TPostfixTemplates.Applies('try', mTraits, False));
  mTraits.TypeName := 'TFoo';
  Assert.IsTrue(TPostfixTemplates.Applies('try', mTraits, False));
  mTraits.InFunction := True;
  Assert.IsTrue(TPostfixTemplates.Applies('exit', mTraits, True));
  mTraits := Default(TPostfixTraits);
  mTraits.Enumerable := True;
  Assert.IsTrue(TPostfixTemplates.Applies('forin', mTraits, True));
end;

procedure TPostfixTemplatesTests.ExpandsNewTemplates;
var
  mTraits: TPostfixTraits;
  mExpansion: TPostfixExpansion;
  mTemplate: TPostfixTemplate;
begin
  Assert.AreEqual('if not Assigned(X) then'#10'    ', TPostfixTemplates.Expand('nil', 'X', '  ', #10, True));
  Assert.AreEqual('not B', TPostfixTemplates.Expand('not', 'B', '  ', #10, True));
  Assert.AreEqual('if B then'#10'    ', TPostfixTemplates.Expand('if', 'B', '  ', #10, True));
  Assert.AreEqual('FreeAndNil(Obj);', TPostfixTemplates.Expand('free', 'Obj', '  ', #10, True));
  Assert.AreEqual('Exit(X);', TPostfixTemplates.Expand('exit', 'X', '  ', #10, True));
  mTraits := Default(TPostfixTraits);
  mTraits.TypeName := 'TStringList';
  mTemplate := Default(TPostfixTemplate);
  mTemplate.Key := 'try';
  mExpansion := TPostfixTemplates.Expand(mTemplate, 'TStringList.Create', mTraits,
    TPostfixLayout.Create('  ', #10, True, False));
  Assert.AreEqual('var StringList := TStringList.Create;'#10'  try'#10'    '#10'  finally'#10 +
    '    StringList.Free;'#10'  end;', mExpansion.Text);
  Assert.AreEqual('', mExpansion.Declaration);
  mExpansion := TPostfixTemplates.Expand(mTemplate, 'TStringList.Create', mTraits,
    TPostfixLayout.Create('  ', #10, False, False));
  Assert.IsTrue(mExpansion.Text.StartsWith('StringList := TStringList.Create;'));
  Assert.AreEqual('StringList: TStringList;', mExpansion.Declaration);
  mTemplate.Key := 'var';
  mExpansion := TPostfixTemplates.Expand(mTemplate, 'Liste', mTraits, TPostfixLayout.Create('  ', #10, False, False));
  Assert.AreEqual('StringList := Liste;', mExpansion.Text);
  Assert.AreEqual('StringList: TStringList;', mExpansion.Declaration);
end;

procedure TPostfixTemplatesTests.SnippetPlaceholders;
var
  mTraits: TPostfixTraits;
  mTemplate: TPostfixTemplate;
begin
  mTraits := Default(TPostfixTraits);
  mTemplate := Default(TPostfixTemplate);
  mTemplate.Key := 'for';
  Assert.AreEqual('for var ${1:Item} in Liste do'#10'  $0',
    TPostfixTemplates.Expand(mTemplate, 'Liste', mTraits, TPostfixLayout.Create('', #10, True, True)).Text);
  // Klassisch kein Platzhalter für den Namen, der auch in der Deklaration steht.
  Assert.AreEqual('for Item in Liste do'#10'  $0',
    TPostfixTemplates.Expand(mTemplate, 'Liste', mTraits, TPostfixLayout.Create('', #10, False, True)).Text);
  mTemplate.Key := 'fmt';
  Assert.AreEqual('Format(S, [$0])', TPostfixTemplates.Expand(mTemplate, 'S', mTraits,
    TPostfixLayout.Create('', #10, True, True)).Text);
  // Der Ausdruck wird maskiert.
  mTemplate.Key := 'notnil';
  Assert.AreEqual('if Assigned(A\\\$B) then'#10'  $0',
    TPostfixTemplates.Expand(mTemplate, 'A\$B', mTraits, TPostfixLayout.Create('', #10, True, True)).Text);
  Assert.AreEqual('a\\b\$c\}', TPostfixTemplates.Escape('a\b$c}'));
end;

procedure TPostfixTemplatesTests.CustomConditions;
var
  mTraits: TPostfixTraits;
  mDescends: TFunc<string, Boolean>;
begin
  mTraits := Default(TPostfixTraits);
  mTraits.IsClass := True;
  mTraits.TypeName := 'TKunde';
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', ''), mTraits, True, nil));
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'any'), mTraits, True, nil));
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'class'), mTraits, True, nil));
  Assert.IsFalse(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'string'), mTraits, True, nil));
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'tkunde'), mTraits, True, nil));
  Assert.IsFalse(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'TBasis'), mTraits, True, nil));
  mDescends :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'TBasis');
    end;
  Assert.IsTrue(TPostfixTemplates.Applies(TPostfixTemplate.Custom('a', '', 'x', 'TBasis'), mTraits, True, mDescends));
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
  mKeys: string;
  mTemplate: TPostfixTemplate;
begin
  mKeys := '';
  for mTemplate in TPostfixTemplates.Templates do
  begin
    mKeys := mKeys + mTemplate.Key + ' ';
    Assert.IsFalse(mTemplate.IsCustom);
    Assert.AreNotEqual('', mTemplate.Description);
  end;
  Assert.AreEqual('for forin tryf ifa notnil nil not if fmt free try var exit ', mKeys);
end;

initialization
  TDUnitX.RegisterTestFixture(TPostfixTemplatesTests);

end.
