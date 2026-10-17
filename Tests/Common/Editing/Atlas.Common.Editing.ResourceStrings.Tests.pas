unit Atlas.Common.Editing.ResourceStrings.Tests;

// Tests für das Auslagern von String-Literalen als resourcestring (#473):
// Namen, Literal am Cursor, zulässige Stellen, Einträge und Einfügestelle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TResourceStringsTests = class
  public
    [Test]
    procedure NamesFromMeaningfulWords;
    [Test]
    procedure NamesSkipPlaceholdersAndStopWords;
    [Test]
    procedure UniqueNameAddsDigits;
    [Test]
    procedure FindsLiteralUnderCursor;
    [Test]
    procedure JoinsCharConstants;
    [Test]
    procedure RejectsEmptyAndSingleCharacters;
    [Test]
    procedure AllowsStatementsOnly;
    [Test]
    procedure RejectsConstantsAttributesAndParameters;
    [Test]
    procedure RejectsCaseLabels;
    [Test]
    procedure ReadsEntries;
    [Test]
    procedure FindsSameText;
    [Test]
    procedure AppendsToImplementationSection;
    [Test]
    procedure CreatesImplementationSectionBehindUses;
    [Test]
    procedure CreatesInterfaceSectionBeforeImplementation;
    [Test]
    procedure IgnoresSectionBehindLiteral;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ResourceStrings;

function Join(const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
    Result := Result + ALines[Index] + #10;
end;

/// <summary>Position des "|" in AMarked; AText ohne "|".</summary>
function Marked(const AMarked: string; out AText: string): TTextPosition;
var
  Index, Line, Character: Integer;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  AText := StringReplace(AMarked, '|', '', []);
  Result := TTextPosition.Create(Line, Character);
end;

/// <summary>Quelltext des Literals am "|"; '-' ohne.</summary>
function LiteralOf(const AMarked: string): string;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Literal: TResourceLiteral;
begin
  Position := Marked(AMarked, Text);
  Tree := TPascalParser.Parse(Text);
  try
    Result := '-';
    if TResourceStrings.LiteralAt(Text, Tree.Tokens, Position, Literal) then
      Result := Literal.Source;
  finally
    Tree.Free;
  end;
end;

/// <summary>Darf am "|" (im Literal) ein resourcestring stehen?</summary>
function AllowedAt(const AMarked: string): Boolean;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Literal: TResourceLiteral;
begin
  Position := Marked(AMarked, Text);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TResourceStrings.LiteralAt(Text, Tree.Tokens, Position, Literal) and
      TResourceStrings.Allowed(Tree, Literal.StartOffset);
  finally
    Tree.Free;
  end;
end;

function InUnit(const ACode: array of string): string;
begin
  Result := Join(['unit Haupt;', 'interface', 'implementation', 'procedure P;', 'var', '  S: string;',
    '  C: Char;', 'begin']) + Join(ACode) + Join(['end;', 'end.']);
end;

/// <summary>AText mit der Einfügung von ADecl (AInterface, vor Zeile ABefore); '-' ohne.</summary>
function Inserted(const AText: string; AInterface: Boolean; ABefore: Integer; const ADecl: string): string;
var
  Tree: TSyntaxTree;
  Edit: TTextEdit;
  Lines: TArray<string>;
  Line: string;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := '-';
    if not TResourceStrings.Insertion(AText, Tree.Tokens, AInterface, ABefore, ADecl, #10, Edit) then
      Exit;
    Assert.AreEqual(Edit.Range.StartPos.Line, Edit.Range.EndPos.Line);
    Lines := AText.Split([#10]);
    Line := Lines[Edit.Range.StartPos.Line];
    Lines[Edit.Range.StartPos.Line] := Copy(Line, 1, Edit.Range.StartPos.Character) + Edit.NewText +
      Copy(Line, Edit.Range.EndPos.Character + 1, MaxInt);
    Result := string.Join(#10, Lines);
  finally
    Tree.Free;
  end;
end;

{ TResourceStringsTests }

procedure TResourceStringsTests.NamesFromMeaningfulWords;
begin
  Assert.AreEqual('SEintragWirklichLoeschen', TResourceStrings.NameFor('Eintrag wirklich löschen?'));
  Assert.AreEqual('SFehlerBeimLaden', TResourceStrings.NameFor('Fehler beim Laden'));
  // Höchstens vier Wörter.
  Assert.AreEqual('SDateiKonnteNichtGespeichert',
    TResourceStrings.NameFor('Die Datei konnte nicht gespeichert werden'));
  Assert.AreEqual('SGroesseUeberMass', TResourceStrings.NameFor('Größe über Maß'));
  Assert.AreEqual('SText', TResourceStrings.NameFor('?!'));
end;

procedure TResourceStringsTests.NamesSkipPlaceholdersAndStopWords;
begin
  Assert.AreEqual('SKundeNichtGefunden', TResourceStrings.NameFor('Kunde %s nicht gefunden'));
  Assert.AreEqual('SZeileVon', TResourceStrings.NameFor('Zeile %0:d von %1:d'));
  Assert.AreEqual('SDateiOrdner', TResourceStrings.NameFor('Datei oder Ordner'));
  Assert.AreEqual('SNameAdresse', TResourceStrings.NameFor('Name und Adresse'));
  // Nur Füllwörter: die bleiben.
  Assert.AreEqual('SUndOder', TResourceStrings.NameFor('und oder'));
end;

procedure TResourceStringsTests.UniqueNameAddsDigits;
begin
  Assert.AreEqual('SFehler', TResourceStrings.UniqueName('SFehler', ['SOk']));
  Assert.AreEqual('SFehler2', TResourceStrings.UniqueName('SFehler', ['sfehler']));
  Assert.AreEqual('SFehler3', TResourceStrings.UniqueName('SFehler', ['SFehler', 'SFehler2']));
end;

procedure TResourceStringsTests.FindsLiteralUnderCursor;
begin
  Assert.AreEqual('''Eintrag löschen?''', LiteralOf(InUnit(['  S := ''Eintrag| löschen?'';'])));
  // Vor dem öffnenden und hinter dem schließenden Hochkomma nicht.
  Assert.AreEqual('-', LiteralOf(InUnit(['  S := |''Eintrag'';'])));
  Assert.AreEqual('-', LiteralOf(InUnit(['  S := ''Eintrag''|;'])));
  Assert.AreEqual('''It''''s''', LiteralOf(InUnit(['  S := ''It''''|s'';'])));
end;

procedure TResourceStringsTests.JoinsCharConstants;
begin
  Assert.AreEqual('''Zeile''#13#10''Zwei''', LiteralOf(InUnit(['  S := ''Zei|le''#13#10''Zwei'';'])));
  // Mit Leerzeichen getrennt gehört der zweite Teil nicht dazu.
  Assert.AreEqual('''Eins''', LiteralOf(InUnit(['  S := ''Ei|ns'' + ''Zwei'';'])));
end;

procedure TResourceStringsTests.RejectsEmptyAndSingleCharacters;
begin
  Assert.AreEqual('-', LiteralOf(InUnit(['  C := ''|x'';'])));
  Assert.AreEqual('-', LiteralOf(InUnit(['  S := ''|'';'])));
end;

procedure TResourceStringsTests.AllowsStatementsOnly;
begin
  Assert.IsTrue(AllowedAt(InUnit(['  S := ''Hal|lo Welt'';'])));
  Assert.IsTrue(AllowedAt(InUnit(['  ShowMessage(Format(''Kun|de %s'', [S]));'])));
  Assert.IsTrue(AllowedAt(InUnit(['  var T := ''Inl|ine'';'])));
  Assert.IsTrue(AllowedAt(InUnit(['  case Length(S) of', '    1: S := ''Ei|ns'';', '  end;'])));
  Assert.IsTrue(AllowedAt(Join(['unit Haupt;', 'interface', 'implementation', 'var', '  S: string;',
    'initialization', '  S := ''Sta|rt'';', 'end.'])));
end;

procedure TResourceStringsTests.RejectsConstantsAttributesAndParameters;
begin
  Assert.IsFalse(AllowedAt(Join(['unit Haupt;', 'interface', 'const', '  CName = ''Kon|stante'';',
    'implementation', 'end.'])));
  Assert.IsFalse(AllowedAt(InUnit(['  const K = ''Inl|ine'';'])));
  Assert.IsFalse(AllowedAt(Join(['unit Haupt;', 'interface', 'type', '  [Description(''Attr|ibut'')]',
    '  TFoo = class', '  end;', 'implementation', 'end.'])));
  Assert.IsFalse(AllowedAt(Join(['unit Haupt;', 'interface', 'procedure P(const S: string = ''Vor|gabe'');',
    'implementation', 'procedure P(const S: string);', 'begin', 'end;', 'end.'])));
  Assert.IsFalse(AllowedAt(Join(['unit Haupt;', 'interface', 'var', '  G: string = ''Glo|bal'';',
    'implementation', 'end.'])));
  Assert.IsFalse(AllowedAt(Join(['unit Haupt;', 'interface', 'implementation', 'resourcestring',
    '  SA = ''Schon aus|gelagert'';', 'end.'])));
end;

procedure TResourceStringsTests.RejectsCaseLabels;
begin
  Assert.IsFalse(AllowedAt(InUnit(['  case S of', '    ''ab|c'': S := ''x'';', '  end;'])));
  Assert.IsTrue(AllowedAt(InUnit(['  case C of', '    ''a'': S := ''Ers|tes'';', '  end;'])));
end;

procedure TResourceStringsTests.ReadsEntries;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'resourcestring'#10 +
    '  SOffen = ''Offen'';'#10 +
    'implementation'#10 +
    'resourcestring'#10 +
    '  SZeile = ''Zeile''#13#10;'#10 +
    '  { Kommentar }'#10 +
    '  SZwei = ''Zwei'';'#10 +
    'const'#10 +
    '  CKein = ''nein'';'#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Entries: TArray<TResourceEntry>;
begin
  Tree := TPascalParser.Parse(Text);
  try
    Entries := TResourceStrings.Entries(Text, Tree.Tokens);
    Assert.AreEqual(3, Integer(Length(Entries)));
    Assert.AreEqual('SOffen', Entries[0].Name);
    Assert.IsTrue(Entries[0].InInterface);
    Assert.AreEqual('''Zeile''#13#10', Entries[1].Value);
    Assert.IsFalse(Entries[1].InInterface);
    Assert.AreEqual(6, Entries[1].Line);
    Assert.AreEqual(5, Entries[1].Section);
    Assert.AreEqual('SZwei', Entries[2].Name);
    Assert.AreEqual(5, Entries[2].Section);
  finally
    Tree.Free;
  end;
end;

procedure TResourceStringsTests.FindsSameText;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'resourcestring'#10 +
    '  SFrage = ''Eintrag wirklich l'' + ''öschen?'';'#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Entry: TResourceEntry;
begin
  Tree := TPascalParser.Parse(Text);
  try
    // Gleicher Text, auch anders geschrieben.
    Assert.IsTrue(TResourceStrings.SameText(TResourceStrings.Entries(Text, Tree.Tokens), 'Eintrag wirklich löschen?',
      False, -1, Entry));
    Assert.AreEqual('SFrage', Entry.Name);
    Assert.IsFalse(TResourceStrings.SameText(TResourceStrings.Entries(Text, Tree.Tokens), 'Eintrag löschen?',
      False, -1, Entry));
    // Nur Einträge vor der Stelle zählen, und nur im passenden Teil.
    Assert.IsFalse(TResourceStrings.SameText(TResourceStrings.Entries(Text, Tree.Tokens), 'Eintrag wirklich löschen?',
      False, 3, Entry));
    Assert.IsFalse(TResourceStrings.SameText(TResourceStrings.Entries(Text, Tree.Tokens), 'Eintrag wirklich löschen?',
      True, -1, Entry));
  finally
    Tree.Free;
  end;
end;

procedure TResourceStringsTests.AppendsToImplementationSection;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    #10 +
    'resourcestring'#10 +
    '    SEins = ''Eins'';'#10 +
    '    SZwei = ''Zwei'';'#10 +
    #10 +
    'procedure P;'#10 +
    'end.';
begin
  // Hinter den letzten Eintrag, mit dessen Einrückung.
  Assert.AreEqual(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    #10 +
    'resourcestring'#10 +
    '    SEins = ''Eins'';'#10 +
    '    SZwei = ''Zwei'';'#10 +
    '    SDrei = ''Drei'';'#10 +
    #10 +
    'procedure P;'#10 +
    'end.', Inserted(Text, False, 8, 'SDrei = ''Drei'';'));
end;

procedure TResourceStringsTests.CreatesImplementationSectionBehindUses;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    #10 +
    'uses'#10 +
    '  System.SysUtils;'#10 +
    #10 +
    'procedure P;'#10 +
    'end.';
begin
  Assert.AreEqual(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    #10 +
    'uses'#10 +
    '  System.SysUtils;'#10 +
    #10 +
    'resourcestring'#10 +
    '  SNeu = ''Neu'';'#10 +
    #10 +
    'procedure P;'#10 +
    'end.', Inserted(Text, False, 7, 'SNeu = ''Neu'';'));
end;

procedure TResourceStringsTests.CreatesInterfaceSectionBeforeImplementation;
const
  Text =
    'unit Texte;'#10 +
    'interface'#10 +
    #10 +
    'implementation'#10 +
    #10 +
    'end.';
begin
  Assert.AreEqual(
    'unit Texte;'#10 +
    'interface'#10 +
    #10 +
    'resourcestring'#10 +
    '  SNeu = ''Neu'';'#10 +
    #10 +
    'implementation'#10 +
    #10 +
    'end.', Inserted(Text, True, -1, 'SNeu = ''Neu'';'));
  Assert.AreEqual('-', Inserted('unit Kaputt;'#10'interface'#10, True, -1, 'SNeu = ''Neu'';'));
end;

procedure TResourceStringsTests.IgnoresSectionBehindLiteral;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    'end;'#10 +
    'resourcestring'#10 +
    '  SSpaet = ''Spät'';'#10 +
    'end.';
begin
  // Der Abschnitt hinter der Stelle (Zeile 4) hilft nicht: Der Name wäre dort noch unbekannt.
  Assert.AreEqual(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    #10 +
    'resourcestring'#10 +
    '  SNeu = ''Neu'';'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    'end;'#10 +
    'resourcestring'#10 +
    '  SSpaet = ''Spät'';'#10 +
    'end.', Inserted(Text, False, 4, 'SNeu = ''Neu'';'));
end;

initialization
  TDUnitX.RegisterTestFixture(TResourceStringsTests);

end.
