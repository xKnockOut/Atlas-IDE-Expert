unit Atlas.Text.DebugDisplay.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextDebugDisplayTests = class
  public
    [Test]
    procedure TemplateSegments;
    [Test]
    procedure TemplateFormatAndBraces;
    [Test]
    procedure TemplateErrors;
    [Test]
    procedure RootAndCalls;
    [Test]
    procedure CommentRule;
    [Test]
    procedure AttributeRule;
    [Test]
    procedure RuleAboveDeclaration;
    [Test]
    procedure RuleNeedsAdjacentLines;
    [Test]
    procedure SourceColumnWithQuotes;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.DebugDisplay;

procedure TTextDebugDisplayTests.TemplateSegments;
var
  mTemplate: TDebugDisplayTemplate;
begin
  mTemplate := TDebugDisplayTemplate.Parse('{Name}, {Ort} (Nr {Nr})');
  Assert.IsTrue(mTemplate.Valid);
  Assert.AreEqual(6, Integer(Length(mTemplate.Segments)));
  Assert.AreEqual('Name', mTemplate.Segments[0].Text);
  Assert.AreEqual(1, mTemplate.Segments[0].Offset);
  Assert.AreEqual(', ', mTemplate.Segments[1].Text);
  Assert.AreEqual('Ort', mTemplate.Segments[2].Text);
  Assert.AreEqual(' (Nr ', mTemplate.Segments[3].Text);
  Assert.AreEqual('Nr', mTemplate.Segments[4].Text);
  Assert.AreEqual(')', mTemplate.Segments[5].Text);
  Assert.AreEqual(3, Integer(Length(mTemplate.Placeholders)));
end;

procedure TTextDebugDisplayTests.TemplateFormatAndBraces;
var
  mTemplate: TDebugDisplayTemplate;
begin
  mTemplate := TDebugDisplayTemplate.Parse('Summe {Betrag:0.00} {{fest}} { Positionen.Count }');
  Assert.IsTrue(mTemplate.Valid);
  Assert.AreEqual('Betrag', mTemplate.Placeholders[0].Text);
  Assert.AreEqual('0.00', mTemplate.Placeholders[0].Format);
  Assert.AreEqual('Positionen.Count', mTemplate.Placeholders[1].Text);
  Assert.AreEqual('', mTemplate.Placeholders[1].Format);
  Assert.AreEqual(Pos('Positionen', mTemplate.Source) - 1, mTemplate.Placeholders[1].Offset);
  Assert.AreEqual(' {fest} ', mTemplate.Segments[2].Text);
  // Doppelpunkt in Klammern ist kein Format.
  mTemplate := TDebugDisplayTemplate.Parse('{Werte[Low(Werte)]} {Text(''a:b'')}');
  Assert.AreEqual('Werte[Low(Werte)]', mTemplate.Placeholders[0].Text);
  Assert.AreEqual('Text(''a:b'')', mTemplate.Placeholders[1].Text);
  Assert.AreEqual('', mTemplate.Placeholders[1].Format);
end;

procedure TTextDebugDisplayTests.TemplateErrors;
var
  mTemplate: TDebugDisplayTemplate;
begin
  mTemplate := TDebugDisplayTemplate.Parse('{Name');
  Assert.IsFalse(mTemplate.Valid);
  Assert.AreEqual(0, mTemplate.ErrorOffset);
  mTemplate := TDebugDisplayTemplate.Parse('a {} b');
  Assert.IsFalse(mTemplate.Valid);
  Assert.AreEqual(2, mTemplate.ErrorOffset);
  mTemplate := TDebugDisplayTemplate.Parse('a } b');
  Assert.IsFalse(mTemplate.Valid);
  Assert.IsTrue(TDebugDisplayTemplate.Parse('nur Text').Valid);
end;

procedure TTextDebugDisplayTests.RootAndCalls;
var
  mTemplate: TDebugDisplayTemplate;
begin
  mTemplate := TDebugDisplayTemplate.Parse('{Positionen.Count} {GetName()} {Items[0].Name} {[1]} {Länge}');
  Assert.AreEqual('Positionen', mTemplate.Placeholders[0].Root);
  Assert.IsFalse(mTemplate.Placeholders[0].NeedsCall);
  Assert.AreEqual('GetName', mTemplate.Placeholders[1].Root);
  Assert.IsTrue(mTemplate.Placeholders[1].NeedsCall);
  Assert.AreEqual('Items', mTemplate.Placeholders[2].Root);
  Assert.IsFalse(mTemplate.Placeholders[2].NeedsCall);
  Assert.AreEqual('', mTemplate.Placeholders[3].Root);
  Assert.AreEqual('Länge', mTemplate.Placeholders[4].Root);
end;

procedure TTextDebugDisplayTests.CommentRule;
var
  mTemplate: string;
  mColumn: Integer;
  mNames: TArray<string>;
begin
  Assert.IsTrue(TDebugDisplayText.CommentTemplate('  // atlas-debug: ''{Name}, {Ort} (Nr {Nr})''', mTemplate,
    mColumn));
  Assert.AreEqual('{Name}, {Ort} (Nr {Nr})', mTemplate);
  Assert.AreEqual(19, mColumn);
  Assert.IsTrue(TDebugDisplayText.CommentTemplate('//Atlas-Debug: {Name} – ''x''', mTemplate, mColumn));
  Assert.AreEqual('{Name} – ''x''', mTemplate);
  Assert.AreEqual(15, mColumn);
  Assert.IsTrue(TDebugDisplayText.CommentTemplate('// atlas-debug: ''It''''s {Name}''', mTemplate, mColumn));
  Assert.AreEqual('It''s {Name}', mTemplate);
  Assert.IsFalse(TDebugDisplayText.CommentTemplate('// atlas-debugger: x', mTemplate, mColumn));
  Assert.IsFalse(TDebugDisplayText.CommentTemplate('X := 1; // atlas-debug: x', mTemplate, mColumn));
  Assert.IsTrue(TDebugDisplayText.CommentChildren('// atlas-debug-children: Name, Ort, ,name, Saldo', mNames));
  Assert.AreEqual('Name|Ort|Saldo', string.Join('|', mNames));
end;

procedure TTextDebugDisplayTests.AttributeRule;
var
  mTemplate: string;
  mColumn: Integer;
  mNames: TArray<string>;
begin
  Assert.IsTrue(TDebugDisplayText.AttributeTemplate('  [AtlasDebugDisplay(''{Name}, {Ort}'')]', mTemplate, mColumn));
  Assert.AreEqual('{Name}, {Ort}', mTemplate);
  Assert.AreEqual(22, mColumn);
  Assert.IsTrue(TDebugDisplayText.AttributeTemplate('[Atlas.Debug.Attributes.AtlasDebugDisplayAttribute( ''{A}'' )]',
    mTemplate, mColumn));
  Assert.AreEqual('{A}', mTemplate);
  Assert.IsTrue(TDebugDisplayText.AttributeTemplate('[Serializable, AtlasDebugDisplay(''{A}'')]', mTemplate, mColumn));
  Assert.IsFalse(TDebugDisplayText.AttributeTemplate('[AtlasDebugDisplayer(''{A}'')]', mTemplate, mColumn));
  Assert.IsFalse(TDebugDisplayText.AttributeTemplate('X := AtlasDebugDisplay(''{A}'');', mTemplate, mColumn));
  Assert.IsTrue(TDebugDisplayText.AttributeChildren('[AtlasDebugChildren(''Name, Ort'')]', mNames));
  Assert.AreEqual('Name|Ort', string.Join('|', mNames));
end;

procedure TTextDebugDisplayTests.RuleAboveDeclaration;
var
  mLines: TArray<string>;
  mRule: TDebugDisplaySource;
begin
  mLines := TArray<string>.Create(
    'type',
    '  /// <summary>Kunde.</summary>',
    '  // atlas-debug: ''{Name}, {Ort}''',
    '  // atlas-debug-children: Name, Ort',
    '  TKunde = class',
    '  end;',
    '',
    '  [AtlasDebugDisplay(''{Nr}'')]',
    '  // atlas-debug: ''{Name}''',
    '  TAuftrag = record',
    '  end;');
  Assert.IsTrue(TDebugDisplayText.RuleAbove(mLines, 4, mRule));
  Assert.AreEqual(Ord(TDebugDisplayOrigin.Comment), Ord(mRule.Origin));
  Assert.AreEqual('{Name}, {Ort}', mRule.Template);
  Assert.AreEqual(2, mRule.TemplateLine);
  Assert.AreEqual('Name|Ort', string.Join('|', mRule.Children));
  Assert.AreEqual(3, mRule.ChildrenLine);
  // Die Zeile direkt über der Deklaration gewinnt.
  Assert.IsTrue(TDebugDisplayText.RuleAbove(mLines, 9, mRule));
  Assert.AreEqual('{Name}', mRule.Template);
  Assert.AreEqual(8, mRule.TemplateLine);
  // Attribut in der Zeile der Deklaration.
  mLines := TArray<string>.Create('  [AtlasDebugDisplay(''{X}'')] TPunkt = record');
  Assert.IsTrue(TDebugDisplayText.RuleAbove(mLines, 0, mRule));
  Assert.AreEqual(Ord(TDebugDisplayOrigin.Attribute), Ord(mRule.Origin));
  Assert.AreEqual('{X}', mRule.Template);
end;

procedure TTextDebugDisplayTests.RuleNeedsAdjacentLines;
var
  mLines: TArray<string>;
  mRule: TDebugDisplaySource;
begin
  mLines := TArray<string>.Create(
    '  // atlas-debug: ''{Name}''',
    '',
    '  TKunde = class');
  Assert.IsFalse(TDebugDisplayText.RuleAbove(mLines, 2, mRule));
  mLines := TArray<string>.Create(
    '  // atlas-debug: ''{Name}''',
    '  FWert: Integer;',
    '  TKunde = class');
  Assert.IsFalse(TDebugDisplayText.RuleAbove(mLines, 2, mRule));
  Assert.IsFalse(TDebugDisplayText.RuleAbove(mLines, 9, mRule));
end;

procedure TTextDebugDisplayTests.SourceColumnWithQuotes;
var
  mLine, mTemplate: string;
  mColumn: Integer;
  mParsed: TDebugDisplayTemplate;
begin
  mLine := '// atlas-debug: ''It''''s {Name}''';
  Assert.IsTrue(TDebugDisplayText.CommentTemplate(mLine, mTemplate, mColumn));
  mParsed := TDebugDisplayTemplate.Parse(mTemplate);
  // {Name}: Ausdruck „Name“ steht in der Zeile hinter der verdoppelten Hochkomma.
  Assert.AreEqual(Pos('Name', mLine) - 1, TDebugDisplayText.SourceColumn(mLine, mColumn, mParsed.Placeholders[0]));
  mLine := '// atlas-debug: A {Ort}';
  Assert.IsTrue(TDebugDisplayText.CommentTemplate(mLine, mTemplate, mColumn));
  mParsed := TDebugDisplayTemplate.Parse(mTemplate);
  Assert.AreEqual(Pos('Ort', mLine) - 1, TDebugDisplayText.SourceColumn(mLine, mColumn, mParsed.Placeholders[0]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextDebugDisplayTests);

end.
