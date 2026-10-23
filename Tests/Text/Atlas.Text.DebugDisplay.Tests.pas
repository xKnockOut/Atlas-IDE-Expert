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
  Template: TDebugDisplayTemplate;
begin
  Template := TDebugDisplayTemplate.Parse('{Name}, {Ort} (Nr {Nr})');
  Assert.IsTrue(Template.Valid);
  Assert.AreEqual(6, Integer(Length(Template.Segments)));
  Assert.AreEqual('Name', Template.Segments[0].Text);
  Assert.AreEqual(1, Template.Segments[0].Offset);
  Assert.AreEqual(', ', Template.Segments[1].Text);
  Assert.AreEqual('Ort', Template.Segments[2].Text);
  Assert.AreEqual(' (Nr ', Template.Segments[3].Text);
  Assert.AreEqual('Nr', Template.Segments[4].Text);
  Assert.AreEqual(')', Template.Segments[5].Text);
  Assert.AreEqual(3, Integer(Length(Template.Placeholders)));
end;

procedure TTextDebugDisplayTests.TemplateFormatAndBraces;
var
  Template: TDebugDisplayTemplate;
begin
  Template := TDebugDisplayTemplate.Parse('Summe {Betrag:0.00} {{fest}} { Positionen.Count }');
  Assert.IsTrue(Template.Valid);
  Assert.AreEqual('Betrag', Template.Placeholders[0].Text);
  Assert.AreEqual('0.00', Template.Placeholders[0].Format);
  Assert.AreEqual('Positionen.Count', Template.Placeholders[1].Text);
  Assert.AreEqual('', Template.Placeholders[1].Format);
  Assert.AreEqual(Pos('Positionen', Template.Source) - 1, Template.Placeholders[1].Offset);
  Assert.AreEqual(' {fest} ', Template.Segments[2].Text);
  // Doppelpunkt in Klammern ist kein Format.
  Template := TDebugDisplayTemplate.Parse('{Werte[Low(Werte)]} {Text(''a:b'')}');
  Assert.AreEqual('Werte[Low(Werte)]', Template.Placeholders[0].Text);
  Assert.AreEqual('Text(''a:b'')', Template.Placeholders[1].Text);
  Assert.AreEqual('', Template.Placeholders[1].Format);
end;

procedure TTextDebugDisplayTests.TemplateErrors;
var
  Template: TDebugDisplayTemplate;
begin
  Template := TDebugDisplayTemplate.Parse('{Name');
  Assert.IsFalse(Template.Valid);
  Assert.AreEqual(0, Template.ErrorOffset);
  Template := TDebugDisplayTemplate.Parse('a {} b');
  Assert.IsFalse(Template.Valid);
  Assert.AreEqual(2, Template.ErrorOffset);
  Template := TDebugDisplayTemplate.Parse('a } b');
  Assert.IsFalse(Template.Valid);
  Assert.IsTrue(TDebugDisplayTemplate.Parse('nur Text').Valid);
end;

procedure TTextDebugDisplayTests.RootAndCalls;
var
  Template: TDebugDisplayTemplate;
begin
  Template := TDebugDisplayTemplate.Parse('{Positionen.Count} {GetName()} {Items[0].Name} {[1]} {Länge}');
  Assert.AreEqual('Positionen', Template.Placeholders[0].Root);
  Assert.IsFalse(Template.Placeholders[0].NeedsCall);
  Assert.AreEqual('GetName', Template.Placeholders[1].Root);
  Assert.IsTrue(Template.Placeholders[1].NeedsCall);
  Assert.AreEqual('Items', Template.Placeholders[2].Root);
  Assert.IsFalse(Template.Placeholders[2].NeedsCall);
  Assert.AreEqual('', Template.Placeholders[3].Root);
  Assert.AreEqual('Länge', Template.Placeholders[4].Root);
end;

procedure TTextDebugDisplayTests.CommentRule;
var
  Template: string;
  Column: Integer;
  Names: TArray<string>;
begin
  Assert.IsTrue(TDebugDisplayText.CommentTemplate('  // atlas-debug: ''{Name}, {Ort} (Nr {Nr})''', Template,
    Column));
  Assert.AreEqual('{Name}, {Ort} (Nr {Nr})', Template);
  Assert.AreEqual(19, Column);
  Assert.IsTrue(TDebugDisplayText.CommentTemplate('//Atlas-Debug: {Name} – ''x''', Template, Column));
  Assert.AreEqual('{Name} – ''x''', Template);
  Assert.AreEqual(15, Column);
  Assert.IsTrue(TDebugDisplayText.CommentTemplate('// atlas-debug: ''It''''s {Name}''', Template, Column));
  Assert.AreEqual('It''s {Name}', Template);
  Assert.IsFalse(TDebugDisplayText.CommentTemplate('// atlas-debugger: x', Template, Column));
  Assert.IsFalse(TDebugDisplayText.CommentTemplate('X := 1; // atlas-debug: x', Template, Column));
  Assert.IsTrue(TDebugDisplayText.CommentChildren('// atlas-debug-children: Name, Ort, ,name, Saldo', Names));
  Assert.AreEqual('Name|Ort|Saldo', string.Join('|', Names));
end;

procedure TTextDebugDisplayTests.AttributeRule;
var
  Template: string;
  Column: Integer;
  Names: TArray<string>;
begin
  Assert.IsTrue(TDebugDisplayText.AttributeTemplate('  [AtlasDebugDisplay(''{Name}, {Ort}'')]', Template, Column));
  Assert.AreEqual('{Name}, {Ort}', Template);
  Assert.AreEqual(22, Column);
  Assert.IsTrue(TDebugDisplayText.AttributeTemplate('[Atlas.Debug.Attributes.AtlasDebugDisplayAttribute( ''{A}'' )]',
    Template, Column));
  Assert.AreEqual('{A}', Template);
  Assert.IsTrue(TDebugDisplayText.AttributeTemplate('[Serializable, AtlasDebugDisplay(''{A}'')]', Template, Column));
  Assert.IsFalse(TDebugDisplayText.AttributeTemplate('[AtlasDebugDisplayer(''{A}'')]', Template, Column));
  Assert.IsFalse(TDebugDisplayText.AttributeTemplate('X := AtlasDebugDisplay(''{A}'');', Template, Column));
  Assert.IsTrue(TDebugDisplayText.AttributeChildren('[AtlasDebugChildren(''Name, Ort'')]', Names));
  Assert.AreEqual('Name|Ort', string.Join('|', Names));
end;

procedure TTextDebugDisplayTests.RuleAboveDeclaration;
var
  Lines: TArray<string>;
  Rule: TDebugDisplaySource;
begin
  Lines := TArray<string>.Create(
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
  Assert.IsTrue(TDebugDisplayText.RuleAbove(Lines, 4, Rule));
  Assert.AreEqual(Ord(TDebugDisplayOrigin.Comment), Ord(Rule.Origin));
  Assert.AreEqual('{Name}, {Ort}', Rule.Template);
  Assert.AreEqual(2, Rule.TemplateLine);
  Assert.AreEqual('Name|Ort', string.Join('|', Rule.Children));
  Assert.AreEqual(3, Rule.ChildrenLine);
  // Die Zeile direkt über der Deklaration gewinnt.
  Assert.IsTrue(TDebugDisplayText.RuleAbove(Lines, 9, Rule));
  Assert.AreEqual('{Name}', Rule.Template);
  Assert.AreEqual(8, Rule.TemplateLine);
  // Attribut in der Zeile der Deklaration.
  Lines := TArray<string>.Create('  [AtlasDebugDisplay(''{X}'')] TPunkt = record');
  Assert.IsTrue(TDebugDisplayText.RuleAbove(Lines, 0, Rule));
  Assert.AreEqual(Ord(TDebugDisplayOrigin.Attribute), Ord(Rule.Origin));
  Assert.AreEqual('{X}', Rule.Template);
end;

procedure TTextDebugDisplayTests.RuleNeedsAdjacentLines;
var
  Lines: TArray<string>;
  Rule: TDebugDisplaySource;
begin
  Lines := TArray<string>.Create(
    '  // atlas-debug: ''{Name}''',
    '',
    '  TKunde = class');
  Assert.IsFalse(TDebugDisplayText.RuleAbove(Lines, 2, Rule));
  Lines := TArray<string>.Create(
    '  // atlas-debug: ''{Name}''',
    '  FWert: Integer;',
    '  TKunde = class');
  Assert.IsFalse(TDebugDisplayText.RuleAbove(Lines, 2, Rule));
  Assert.IsFalse(TDebugDisplayText.RuleAbove(Lines, 9, Rule));
end;

procedure TTextDebugDisplayTests.SourceColumnWithQuotes;
var
  Line, Template: string;
  Column: Integer;
  Parsed: TDebugDisplayTemplate;
begin
  Line := '// atlas-debug: ''It''''s {Name}''';
  Assert.IsTrue(TDebugDisplayText.CommentTemplate(Line, Template, Column));
  Parsed := TDebugDisplayTemplate.Parse(Template);
  // {Name}: Ausdruck „Name“ steht in der Zeile hinter der verdoppelten Hochkomma.
  Assert.AreEqual(Pos('Name', Line) - 1, TDebugDisplayText.SourceColumn(Line, Column, Parsed.Placeholders[0]));
  Line := '// atlas-debug: A {Ort}';
  Assert.IsTrue(TDebugDisplayText.CommentTemplate(Line, Template, Column));
  Parsed := TDebugDisplayTemplate.Parse(Template);
  Assert.AreEqual(Pos('Ort', Line) - 1, TDebugDisplayText.SourceColumn(Line, Column, Parsed.Placeholders[0]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextDebugDisplayTests);

end.
