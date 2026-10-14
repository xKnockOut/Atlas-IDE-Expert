unit Atlas.Core.Completion.Snippets.Tests;

// Tests für Code-Vorlagen und den Platzhalter-Modus (#51).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSnippetsTests = class
  public
    [Test]
    procedure ParsesSnippetFile;
    [Test]
    procedure ReportsBrokenFiles;
    [Test]
    procedure ExpandsWithIndentAndLinkedDefaults;
    [Test]
    procedure KeepsHexNumbers;
    [Test]
    procedure UserSnippetsReplaceBuiltIn;
    [Test]
    procedure BuiltInSnippetsParse;
    [Test]
    procedure LoadsFolder;
    [Test]
    procedure DoubleDollarIsText;
    [Test]
    procedure SetterSnippetKeepsInvalidateRuleSilent;
    [Test]
    procedure FormatRoundTrips;
  end;

  /// <summary>Datenmodell der Seite „Snippets“ (#51).</summary>
  [TestFixture]
  TAtlasSnippetCatalogTests = class
  public
    [Test]
    procedure ListsAllWithOriginAndReplacement;
    [Test]
    procedure OnlyOwnAreEditable;
    [Test]
    procedure ValidatesOwnSnippets;
    [Test]
    procedure SavesChangedAndDeletesRemoved;
  end;

  /// <summary>Live Templates der IDE (#51).</summary>
  [TestFixture]
  TAtlasLiveTemplatesTests = class
  public
    [Test]
    procedure ReadsDelphi12Folder;
    [Test]
    procedure ConvertsPointsAndMarkers;
    [Test]
    procedure KeepsFixedPointsAndEscapesDollar;
    [Test]
    procedure SkipsBrokenXml;
    [Test]
    procedure OwnBeforeIdeBeforeBuiltIn;
    [Test]
    procedure IdeTemplateAppearsInList;
  end;

  [TestFixture]
  TAtlasPlaceholderSessionTests = class
  public
    [Test]
    procedure TabWalksThroughPlaceholders;
    [Test]
    procedure TypingUpdatesLinkedPlaceholders;
    [Test]
    procedure TypingAfterPlaceholderMovesFollowingOnes;
    [Test]
    procedure EditOutsideEndsSession;
    [Test]
    procedure WithoutEndMarkerEndsBehindSnippet;
    [Test]
    procedure LocatesOffsets;
  end;

  [TestFixture]
  TAtlasSnippetProviderTests = class
  public
    [Test]
    procedure OffersOnlyAtStatementStart;
    [Test]
    procedure MapsSnippetsToItems;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Presentation,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Components,
  Atlas.Tests.RuleAssert,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.LiveTemplates,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.Core.Completion.Placeholders,
  Atlas.Core.Completion.Providers.Snippets;

const
  TryFinally = '${1:List} := ${2:TStringList}.Create;'#10'try'#10'  $0'#10'finally'#10'  ${1}.Free;'#10'end;';

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

function Find(const AList: TAtlasSnippetList; const APrefix: string; out ASnippet: TAtlasSnippet): Boolean;
var
  Item: TAtlasSnippet;
begin
  for Item in AList do
    if SameText(Item.Prefix, APrefix) then
    begin
      ASnippet := Item;
      Exit(True);
    end;
  Result := False;
end;

/// <summary>Ersetzt in AText Start bis Stop durch AValue.</summary>
function Replace(const AText: string; AStart, AStop: Integer; const AValue: string): string;
begin
  Result := Copy(AText, 1, AStart) + AValue + Copy(AText, AStop + 1, MaxInt);
end;

function Apply(const AText: string; const AEdits: TAtlasPlaceholderEdits): string;
var
  Index: Integer;
begin
  Result := AText;
  for Index := High(AEdits) downto 0 do
    Result := Replace(Result, AEdits[Index].Start, AEdits[Index].Stop, AEdits[Index].Text);
end;

{ TAtlasSnippetsTests }

procedure TAtlasSnippetsTests.ParsesSnippetFile;
var
  Snippet: TAtlasSnippet;
  Error: string;
begin
  Assert.IsTrue(TAtlasSnippets.Parse(
    '# Eigene Vorlage'#13#10'name: Liste anlegen'#13#10'prefix: lst'#13#10'description: TStringList mit Freigabe'#13#10 +
    '---'#13#10'${1:L} := TStringList.Create;'#13#10'  $0'#13#10#13#10, 'C:\lst.atlas-snippet', Snippet, Error), Error);
  Assert.AreEqual('Liste anlegen', Snippet.Name);
  Assert.AreEqual('lst', Snippet.Prefix);
  Assert.AreEqual('TStringList mit Freigabe', Snippet.Description);
  Assert.AreEqual('${1:L} := TStringList.Create;'#10'  $0', Snippet.Body);
  Assert.IsTrue(Snippet.Origin = TAtlasSnippetOrigin.User);
  // Ohne Namen gilt das Kürzel.
  Assert.IsTrue(TAtlasSnippets.Parse('prefix: x'#10'---'#10'X;', '', Snippet, Error));
  Assert.AreEqual('x', Snippet.Name);
end;

procedure TAtlasSnippetsTests.ReportsBrokenFiles;
var
  Snippet: TAtlasSnippet;
  Error: string;
begin
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x'#10'X;', '', Snippet, Error));
  Assert.Contains(Error, '---');
  Assert.IsFalse(TAtlasSnippets.Parse('name: x'#10'---'#10'X;', '', Snippet, Error));
  Assert.Contains(Error, 'prefix');
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x'#10'scope: y'#10'---'#10'X;', '', Snippet, Error));
  Assert.Contains(Error, 'scope');
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x y'#10'---'#10'X;', '', Snippet, Error));
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x'#10'---'#10#10, '', Snippet, Error));
end;

procedure TAtlasSnippetsTests.ExpandsWithIndentAndLinkedDefaults;
var
  Expansion: TAtlasSnippetExpansion;
begin
  Expansion := TAtlasSnippets.Expand(TryFinally, '    ', #13#10);
  Assert.AreEqual('List := TStringList.Create;'#13#10'    try'#13#10'      '#13#10'    finally'#13#10 +
    '      List.Free;'#13#10'    end;', Expansion.Text);
  Assert.AreEqual(4, Integer(Length(Expansion.Stops)));
  // List, TStringList, $0, zweites List mit dem Vorgabetext des ersten.
  Assert.AreEqual(1, Expansion.Stops[0].Number);
  Assert.AreEqual(0, Expansion.Stops[0].Start);
  Assert.AreEqual(4, Expansion.Stops[0].Length);
  Assert.AreEqual(2, Expansion.Stops[1].Number);
  Assert.AreEqual('TStringList', Copy(Expansion.Text, Expansion.Stops[1].Start + 1, Expansion.Stops[1].Length));
  Assert.AreEqual(0, Expansion.Stops[2].Number);
  Assert.AreEqual(0, Expansion.Stops[2].Length);
  Assert.AreEqual(1, Expansion.Stops[3].Number);
  Assert.AreEqual('List', Copy(Expansion.Text, Expansion.Stops[3].Start + 1, Expansion.Stops[3].Length));
  Assert.IsTrue(Expansion.HasPlaceholders);
  Assert.AreEqual('A := B;', TAtlasSnippets.PlainText('${1:A} := ${2:B};$0'));
  Assert.IsFalse(TAtlasSnippets.Expand('Exit;$0', '', #10).HasPlaceholders);
end;

procedure TAtlasSnippetsTests.KeepsHexNumbers;
var
  Expansion: TAtlasSnippetExpansion;
begin
  Expansion := TAtlasSnippets.Expand('Mask := $FF or $0F or $10 or $0A;${x} $', '', #10);
  Assert.AreEqual('Mask := $FF or $0F or $10 or $0A;${x} $', Expansion.Text);
  Assert.AreEqual(0, Integer(Length(Expansion.Stops)));
  Assert.AreEqual('{$IFDEF X}Y{$ENDIF}', TAtlasSnippets.PlainText('{$IFDEF X}${1:Y}{$ENDIF}'));
end;

procedure TAtlasSnippetsTests.UserSnippetsReplaceBuiltIn;
var
  Own, Second: TAtlasSnippet;
  Merged: TAtlasSnippetList;
  Found: TAtlasSnippet;
begin
  Own := Default(TAtlasSnippet);
  Own.Prefix := 'TRYF';
  Own.Body := 'eigene';
  Own.Origin := TAtlasSnippetOrigin.User;
  Second := Own;
  Second.Body := 'zweite';
  Merged := TAtlasSnippets.Merge(TAtlasSnippets.BuiltIn, [Own, Second]);
  Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)), Integer(Length(Merged)));
  Assert.IsTrue(Find(Merged, 'tryf', Found));
  Assert.AreEqual('eigene', Found.Body);
  Assert.IsTrue(Find(Merged, 'forin', Found));
  Assert.IsTrue(Found.Origin = TAtlasSnippetOrigin.BuiltIn);
end;

procedure TAtlasSnippetsTests.BuiltInSnippetsParse;
var
  Snippet: TAtlasSnippet;
  Code, Text: string;
begin
  for Snippet in TAtlasSnippets.BuiltIn do
  begin
    Code := TAtlasSnippets.Expand(Snippet.Body, '    ', #10).Text;
    // Je nach Art an die passende Stelle einer Unit.
    if (Snippet.Prefix = 'class') or (Snippet.Prefix = 'record') or (Snippet.Prefix = 'comp') then
      Text := 'unit U;'#10'interface'#10'type'#10'  ' + Code + #10'implementation'#10'end.'
    else if Snippet.Prefix = 'prop' then
      Text := 'unit U;'#10'interface'#10'type'#10'  T = class'#10'  public'#10'    ' + Code + #10'  end;'#10 +
        'implementation'#10'end.'
    else if (Snippet.Prefix = 'propset') or (Snippet.Prefix = 'reg') then
      Text := 'unit U;'#10'interface'#10'implementation'#10 + Code + #10'end.'
    else
      Text := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'    ' + Code + #10'end;'#10'end.';
    Assert.IsTrue(Parses(Text), Snippet.Prefix + ': ' + Text);
    Assert.IsTrue(Snippet.Description <> '', Snippet.Prefix);
  end;
end;

procedure TAtlasSnippetsTests.LoadsFolder;
var
  Folder: string;
  Lines: TStringList;
  Snippets: TAtlasSnippetList;
  Errors: TArray<string>;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'AtlasSnippets' + IntToStr(Random(1000000)));
  ForceDirectories(Folder);
  Lines := TStringList.Create;
  try
    Lines.Text := 'prefix: lst'#13#10'---'#13#10'L := TStringList.Create;';
    Lines.SaveToFile(TPath.Combine(Folder, 'b.atlas-snippet'), TEncoding.UTF8);
    Lines.Text := 'kaputt';
    Lines.SaveToFile(TPath.Combine(Folder, 'a.atlas-snippet'), TEncoding.UTF8);
    Lines.Text := 'prefix: nicht'#13#10'---'#13#10'X;';
    Lines.SaveToFile(TPath.Combine(Folder, 'c.txt'), TEncoding.UTF8);
    Snippets := TAtlasSnippets.LoadFolder(Folder, Errors);
    Assert.AreEqual(1, Integer(Length(Snippets)));
    Assert.AreEqual('lst', Snippets[0].Prefix);
    Assert.AreEqual('L := TStringList.Create;', Snippets[0].Body);
    Assert.AreEqual(1, Integer(Length(Errors)));
    Assert.StartsWith('a.atlas-snippet: ', Errors[0]);
  finally
    Lines.Free;
    TDirectory.Delete(Folder, True);
  end;
  Snippets := TAtlasSnippets.LoadFolder(Folder, Errors);
  Assert.AreEqual(0, Integer(Length(Snippets)));
end;

{ TAtlasPlaceholderSessionTests }

function Start(const ABefore, ABody, AAfter: string; out ADocument: string): TAtlasPlaceholderSession;
var
  Expansion: TAtlasSnippetExpansion;
begin
  Expansion := TAtlasSnippets.Expand(ABody, '  ', #10);
  ADocument := ABefore + Expansion.Text + AAfter;
  Result := TAtlasPlaceholderSession.Create(ADocument, Length(ABefore), Expansion);
end;

procedure TAtlasPlaceholderSessionTests.TabWalksThroughPlaceholders;
var
  Session: TAtlasPlaceholderSession;
  Document: string;
begin
  Session := Start('begin'#10'  ', TryFinally, #10'end;', Document);
  try
    Assert.AreEqual(1, Session.CurrentNumber);
    Assert.AreEqual(1, Session.Position);
    Assert.AreEqual(2, Session.Count);
    Assert.AreEqual(8, Session.Current.Start);
    Assert.AreEqual('List', Session.FieldText(Session.Current));
    Assert.AreEqual(3, Integer(Length(Session.Fields)));
    Session.Previous;
    Assert.AreEqual(1, Session.CurrentNumber);
    Assert.IsTrue(Session.Next);
    Assert.AreEqual('TStringList', Session.FieldText(Session.Current));
    Assert.AreEqual(2, Session.Position);
    Session.Previous;
    Assert.AreEqual(1, Session.CurrentNumber);
    Assert.IsTrue(Session.Next);
    // Nach dem letzten Platzhalter: Endposition in der leeren Zeile zwischen try und finally.
    Assert.IsFalse(Session.Next);
    Assert.AreEqual(0, Session.CurrentNumber);
    Assert.AreEqual(Pos('try'#10'    ', Document) + 7, Session.FinalOffset);
  finally
    Session.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.TypingUpdatesLinkedPlaceholders;
var
  Session: TAtlasPlaceholderSession;
  Document: string;
  Edits: TAtlasPlaceholderEdits;
begin
  Session := Start('', TryFinally, '', Document);
  try
    // Die markierte Vorgabe "List" wird durch "I" ersetzt, dann "tems" getippt.
    Document := Replace(Document, 0, 4, 'I');
    Assert.IsTrue(Session.Update(Document));
    Document := Replace(Document, 1, 1, 'tems');
    Assert.IsTrue(Session.Update(Document));
    Assert.AreEqual('Items', Session.FieldText(Session.Current));
    Edits := Session.MirrorEdits;
    Assert.AreEqual(1, Integer(Length(Edits)));
    Assert.AreEqual('Items', Edits[0].Text);
    Document := Apply(Document, Edits);
    Session.Applied(Edits);
    Assert.AreEqual(Document, Session.Text);
    Assert.AreEqual('Items := TStringList.Create;'#10'  try'#10'    '#10'  finally'#10'    Items.Free;'#10'  end;', Document);
    // Die Benachrichtigung über das Angleichen ändert nichts mehr.
    Assert.IsTrue(Session.Update(Document));
    Assert.AreEqual(0, Integer(Length(Session.MirrorEdits)));
    // Im verknüpften Platzhalter getippt: Er wird zur Vorlage.
    Document := Replace(Document, Pos('Items.Free', Document) + 4, Pos('Items.Free', Document) + 4, 'X');
    Assert.IsTrue(Session.Update(Document));
    Edits := Session.MirrorEdits;
    Assert.AreEqual('ItemsX', Edits[0].Text);
    Assert.AreEqual(0, Edits[0].Start);
    Document := Apply(Document, Edits);
    Session.Applied(Edits);
    Assert.StartsWith('ItemsX := TStringList', Document);
    Assert.AreEqual(Document, Session.Text);
    // Alles bis auf einen leeren Platzhalter löschen geht auch.
    Session.Previous;
    Document := Replace(Document, 0, 6, '');
    Assert.IsTrue(Session.Update(Document));
    Assert.AreEqual(0, Session.Current.Length);
  finally
    Session.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.TypingAfterPlaceholderMovesFollowingOnes;
var
  Session: TAtlasPlaceholderSession;
  Document: string;
  Final: Integer;
begin
  Session := Start('x', TryFinally, '', Document);
  try
    Assert.IsTrue(Session.Next);
    Final := Session.FinalOffset;
    // Am Ende von "TStringList" ein "." anhängen; dahinter steht schon einer, die Stelle ist also mehrdeutig.
    Document := Replace(Document, Session.Current.Stop, Session.Current.Stop, '.');
    Assert.IsTrue(Session.Update(Document));
    Assert.AreEqual('TStringList.', Session.FieldText(Session.Current));
    Assert.AreEqual(Final + 1, Session.FinalOffset);
    Assert.AreEqual(0, Integer(Length(Session.MirrorEdits)));
  finally
    Session.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.EditOutsideEndsSession;
var
  Session: TAtlasPlaceholderSession;
  Document: string;
begin
  Session := Start('begin'#10, TryFinally, '', Document);
  try
    Assert.IsFalse(Session.Update(Replace(Document, 0, 0, '//')));
  finally
    Session.Free;
  end;
  // Änderung im Platzhalter 2, während 1 aktiv ist: auch vorbei.
  Session := Start('', TryFinally, '', Document);
  try
    Assert.IsFalse(Session.Update(Replace(Document, 9, 9, 'X')));
  finally
    Session.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.WithoutEndMarkerEndsBehindSnippet;
var
  Session: TAtlasPlaceholderSession;
  Document: string;
begin
  Session := Start('a ', 'Exit(${1:False});', ' b', Document);
  try
    Assert.AreEqual(1, Session.Count);
    Assert.IsFalse(Session.Next);
    Assert.AreEqual(Length('a Exit(False);'), Session.FinalOffset);
  finally
    Session.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.LocatesOffsets;
var
  Line, Character: Integer;
begin
  TAtlasPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 0, Line, Character);
  Assert.AreEqual(0, Line);
  Assert.AreEqual(0, Character);
  TAtlasPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 6, Line, Character);
  Assert.AreEqual(1, Line);
  Assert.AreEqual(2, Character);
  TAtlasPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 99, Line, Character);
  Assert.AreEqual(2, Line);
  Assert.AreEqual(1, Character);
end;

{ TAtlasSnippetProviderTests }

procedure TAtlasSnippetProviderTests.OffersOnlyAtStatementStart;
begin
  Assert.IsTrue(TAtlasSnippetCompletionProvider.IsSnippetContext('  tryf', 'tryf'));
  Assert.IsTrue(TAtlasSnippetCompletionProvider.IsSnippetContext(#9'for', 'for'));
  Assert.IsTrue(TAtlasSnippetCompletionProvider.IsSnippetContext('', ''));
  Assert.IsFalse(TAtlasSnippetCompletionProvider.IsSnippetContext('  X := tryf', 'tryf'));
  Assert.IsFalse(TAtlasSnippetCompletionProvider.IsSnippetContext('  List.tryf', 'tryf'));
  Assert.IsFalse(TAtlasSnippetCompletionProvider.IsSnippetContext('  // tryf', 'tryf'));
  Assert.IsFalse(TAtlasSnippetCompletionProvider.IsSnippetContext('  ''tryf', 'tryf'));
end;

procedure TAtlasSnippetProviderTests.MapsSnippetsToItems;
var
  Items: TAtlasCompletionItems;
  Tags: TAtlasTags;
begin
  Items := TAtlasSnippetCompletionProvider.Items(TAtlasSnippets.BuiltIn);
  Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)), Integer(Length(Items)));
  Assert.AreEqual('tryf', Items[0].Name);
  Assert.IsTrue(Items[0].Kind = TAtlasItemKind.Snippet);
  Assert.AreEqual('try…finally mit Create/Free', Items[0].Signature);
  Assert.AreEqual(TAtlasSnippets.BuiltIn[0].Body, Items[0].Snippet);
  Assert.StartsWith('Objekt anlegen', Items[0].Documentation);
  Assert.Contains(Items[0].Documentation, 'List.Free;');
  Assert.IsTrue(Items[1].Rank > Items[0].Rank);
  Assert.AreEqual('sn', TAtlasItemPresentation.Badge(Items[0]).Code);
  Tags := TAtlasItemPresentation.Tags(Items[0]);
  Assert.AreEqual(1, Integer(Length(Tags)));
  Assert.AreEqual('Snippet', Tags[0].Text);
end;

procedure TAtlasSnippetsTests.DoubleDollarIsText;
var
  Expansion: TAtlasSnippetExpansion;
begin
  Expansion := TAtlasSnippets.Expand('X := Y and $$1;$0', '', #10);
  Assert.AreEqual('X := Y and $1;', Expansion.Text);
  Assert.AreEqual(1, Integer(Length(Expansion.Stops)));
  Assert.AreEqual(0, Expansion.Stops[0].Number);
end;

procedure TAtlasSnippetsTests.SetterSnippetKeepsInvalidateRuleSilent;
const
  Head = 'unit U;'#10'interface'#10'type'#10'  TMyControl = class(TCustomControl)'#10'  private'#10 +
    '    FValue: Integer;'#10'    procedure SetValue(const AValue: Integer);'#10'  protected'#10 +
    '    procedure Paint; override;'#10'  published'#10'    property Value: Integer read FValue write SetValue;'#10 +
    '  end;'#10'implementation'#10'procedure TMyControl.Paint;'#10'begin'#10'  inherited;'#10 +
    '  Canvas.TextOut(0, 0, IntToStr(FValue));'#10'end;'#10;
var
  Snippet: TAtlasSnippet;
begin
  // Gegenprobe: ohne Invalidate meldet die Regel (#55).
  TRuleAssert.Reports(TComponentSetterWithoutInvalidateRule.Create, Head +
    'procedure TMyControl.SetValue(const AValue: Integer);'#10'begin'#10'  FValue := AValue;'#10'end;'#10'end.');
  Assert.IsTrue(Find(TAtlasSnippets.BuiltIn, 'propset', Snippet));
  TRuleAssert.Silent(TComponentSetterWithoutInvalidateRule.Create,
    Head + TAtlasSnippets.Expand(Snippet.Body, '', #10).Text + #10'end.');
end;

procedure TAtlasSnippetsTests.FormatRoundTrips;
var
  Snippet, Parsed: TAtlasSnippet;
  Error: string;
begin
  Snippet := Default(TAtlasSnippet);
  Snippet.Name := 'Schleife über eine Liste';
  Snippet.Prefix := 'forl';
  Snippet.Description := 'for-Schleife bis Count - 1';
  Snippet.Body := 'for ${1:I} := 0 to ${2:List}.Count - 1 do'#10'  $0';
  Assert.IsTrue(TAtlasSnippets.Parse(TAtlasSnippets.ToFileText(Snippet), 'forl.atlas-snippet', Parsed, Error), Error);
  Assert.AreEqual(Snippet.Name, Parsed.Name);
  Assert.AreEqual(Snippet.Prefix, Parsed.Prefix);
  Assert.AreEqual(Snippet.Description, Parsed.Description);
  Assert.AreEqual(Snippet.Body, Parsed.Body);
  Assert.AreEqual('forl.atlas-snippet', TAtlasSnippets.FileNameFor('forl'));
  Assert.AreEqual('a_b.atlas-snippet', TAtlasSnippets.FileNameFor('a\b'));
end;

{ TAtlasSnippetCatalogTests }

function OwnSnippet(const APrefix, ABody: string): TAtlasSnippet;
begin
  Result := Default(TAtlasSnippet);
  Result.Prefix := APrefix;
  Result.Name := APrefix;
  Result.Body := ABody;
  Result.Origin := TAtlasSnippetOrigin.User;
end;

procedure TAtlasSnippetCatalogTests.ListsAllWithOriginAndReplacement;
var
  Catalog: TAtlasSnippetCatalog;
  Ide: TAtlasSnippet;
  Index: Integer;
begin
  Ide := OwnSnippet('forin', 'IDE;');
  Ide.Origin := TAtlasSnippetOrigin.Ide;
  Catalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, [Ide], [OwnSnippet('tryf', 'X;')]);
  try
    Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)) + 2, Catalog.Count);
    Assert.IsTrue(Catalog.Entry(0).Snippet.Origin = TAtlasSnippetOrigin.User);
    Assert.IsTrue(Catalog.Entry(1).Snippet.Origin = TAtlasSnippetOrigin.Ide);
    Assert.IsFalse(Catalog.Replaced(0));
    Assert.IsFalse(Catalog.Replaced(1));
    for Index := 2 to Catalog.Count - 1 do
      if SameText(Catalog.Entry(Index).Snippet.Prefix, 'tryf') or
        SameText(Catalog.Entry(Index).Snippet.Prefix, 'forin') then
        Assert.IsTrue(Catalog.Replaced(Index), Catalog.Entry(Index).Snippet.Prefix)
      else
        Assert.IsFalse(Catalog.Replaced(Index), Catalog.Entry(Index).Snippet.Prefix);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSnippetCatalogTests.OnlyOwnAreEditable;
var
  Catalog: TAtlasSnippetCatalog;
  Changed: TAtlasSnippet;
  Index, Last: Integer;
begin
  Catalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, nil);
  try
    Last := Catalog.Count - 1;
    Assert.IsFalse(Catalog.Editable(Last));
    Changed := Catalog.Entry(Last).Snippet;
    Changed.Body := 'geändert';
    Catalog.Update(Last, Changed);
    Assert.AreNotEqual('geändert', Catalog.Entry(Last).Snippet.Body);
    Assert.IsFalse(Catalog.Modified);
    // Kopie als eigene: steht vorn, gleiches Kürzel, ersetzt das Original.
    Index := Catalog.CopyAsOwn(Last);
    Assert.AreEqual(0, Index);
    Assert.IsTrue(Catalog.Editable(0));
    Assert.AreEqual(Catalog.Entry(Last + 1).Snippet.Prefix, Catalog.Entry(0).Snippet.Prefix);
    Assert.IsTrue(Catalog.Replaced(Last + 1));
    Assert.IsTrue(Catalog.Modified);
    // Neue eigene: freies Kürzel, hinter den eigenen.
    Index := Catalog.AddNew;
    Assert.AreEqual(1, Index);
    Assert.AreEqual('neu', Catalog.Entry(1).Snippet.Prefix);
    Assert.AreEqual('neu2', Catalog.Entry(Catalog.AddNew).Snippet.Prefix);
    Catalog.Delete(1);
    Assert.AreEqual('neu2', Catalog.Entry(1).Snippet.Prefix);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSnippetCatalogTests.ValidatesOwnSnippets;
var
  Catalog: TAtlasSnippetCatalog;
  Problems: TArray<TAtlasSnippetProblem>;
begin
  Catalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil,
    [OwnSnippet('a', 'X;'), OwnSnippet('A', 'Y;'), OwnSnippet('', 'Z;'), OwnSnippet('b-c', ' '),
     OwnSnippet('tryf', 'W;')]);
  try
    Assert.IsFalse(Catalog.Validate(Problems));
    Assert.AreEqual(4, Integer(Length(Problems)));
    Assert.AreEqual(1, Problems[0].Index);
    Assert.IsTrue(Problems[0].Kind = TAtlasSnippetProblemKind.PrefixTwice);
    Assert.IsTrue(Problems[1].Kind = TAtlasSnippetProblemKind.PrefixMissing);
    Assert.IsTrue(Problems[2].Kind = TAtlasSnippetProblemKind.PrefixInvalid);
    Assert.IsTrue(Problems[3].Kind = TAtlasSnippetProblemKind.BodyMissing);
    // Gleiches Kürzel wie eine mitgelieferte ist erlaubt: die eigene ersetzt sie.
    Assert.AreEqual(3, Problems[3].Index);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSnippetCatalogTests.SavesChangedAndDeletesRemoved;
var
  Folder: string;
  Catalog: TAtlasSnippetCatalog;
  Loaded: TAtlasSnippetList;
  Errors: TArray<string>;
  Changed: TAtlasSnippet;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'AtlasCatalog' + IntToStr(Random(1000000)));
  try
    Catalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, nil);
    try
      Changed := Catalog.Entry(Catalog.AddNew).Snippet;
      Changed.Prefix := 'liste';
      Changed.Description := 'Liste anlegen';
      Changed.Body := '${1:L} := TStringList.Create;$0';
      Catalog.Update(0, Changed);
      Catalog.AddNew;
      Catalog.Save(Folder);
      Assert.IsFalse(Catalog.Modified);
    finally
      Catalog.Free;
    end;
    Loaded := TAtlasSnippets.LoadFolder(Folder, Errors);
    Assert.AreEqual(0, Integer(Length(Errors)));
    Assert.AreEqual(2, Integer(Length(Loaded)));
    Assert.IsTrue(FileExists(TPath.Combine(Folder, 'liste.atlas-snippet')));
    // Löschen entfernt die Datei; das Umbenennen des Kürzels behält den Dateinamen.
    Catalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, Loaded);
    try
      Changed := Catalog.Entry(0).Snippet;
      Changed.Prefix := 'liste2';
      Catalog.Update(0, Changed);
      Catalog.Delete(1);
      Catalog.Save(Folder);
    finally
      Catalog.Free;
    end;
    Loaded := TAtlasSnippets.LoadFolder(Folder, Errors);
    Assert.AreEqual(1, Integer(Length(Loaded)));
    Assert.AreEqual('liste2', Loaded[0].Prefix);
    Assert.AreEqual('Liste anlegen', Loaded[0].Description);
    Assert.AreEqual('${1:L} := TStringList.Create;$0', Loaded[0].Body);
    Assert.IsTrue(FileExists(TPath.Combine(Folder, 'liste.atlas-snippet')));
  finally
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
  end;
end;

{ TAtlasLiveTemplatesTests }

function LiveTemplateFolder: string;
var
  Directory, Candidate: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    Candidate := TPath.Combine(Directory, 'Tests\Data\LiveTemplates\Delphi12');
    if TDirectory.Exists(Candidate) then
      Exit(Candidate);
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  Result := '';
end;

procedure TAtlasLiveTemplatesTests.ReadsDelphi12Folder;
var
  List: TAtlasSnippetList;
  Stats: TAtlasLiveTemplateStats;
  Snippet: TAtlasSnippet;
begin
  Assert.IsTrue(LiveTemplateFolder <> '', 'Ordner Tests\Data\LiveTemplates\Delphi12 fehlt');
  List := TAtlasLiveTemplates.LoadFolder(LiveTemplateFolder, Stats);
  Assert.AreEqual(2, Stats.Templates);
  // Die C++-Vorlage wird übersprungen, das Skript in "forb" entfällt.
  Assert.AreEqual(1, Stats.Skipped);
  Assert.AreEqual(1, Stats.Scripts);
  Assert.IsTrue(Find(List, 'forb', Snippet));
  Assert.AreEqual('for statement', Snippet.Description);
  Assert.IsTrue(Snippet.Origin = TAtlasSnippetOrigin.Ide);
  Assert.IsFalse(Find(List, 'cppfor', Snippet));
end;

procedure TAtlasLiveTemplatesTests.ConvertsPointsAndMarkers;
var
  List: TAtlasSnippetList;
  Stats: TAtlasLiveTemplateStats;
  Snippet: TAtlasSnippet;
  Expansion: TAtlasSnippetExpansion;
begin
  Stats := Default(TAtlasLiveTemplateStats);
  List := TAtlasLiveTemplates.Parse('<codetemplate><template name="forb"><point name="ident"><text>' +
    #10'  I'#10'</text></point><point name="to"><text>N</text></point>' +
    '<code language="Delphi" delimiter="|"><![CDATA[for |ident| := 0 to |to| do'#13#10'begin'#13#10 +
    '|selected||*||end|'#13#10'  X(|ident|);'#13#10'end;'#13#10']]></code></template></codetemplate>', '', Stats);
  Assert.AreEqual(1, Integer(Length(List)));
  Snippet := List[0];
  Assert.AreEqual('for ${1:I} := 0 to ${2:N} do'#10'begin'#10'  $0'#10'  X(${1});'#10'end;', Snippet.Body);
  Expansion := TAtlasSnippets.Expand(Snippet.Body, '', #10);
  Assert.AreEqual('for I := 0 to N do'#10'begin'#10'  '#10'  X(I);'#10'end;', Expansion.Text);
end;

procedure TAtlasLiveTemplatesTests.KeepsFixedPointsAndEscapesDollar;
var
  List: TAtlasSnippetList;
  Stats: TAtlasLiveTemplateStats;
  Snippet: TAtlasSnippet;
begin
  List := TAtlasLiveTemplates.LoadFolder(LiveTemplateFolder, Stats);
  Assert.IsTrue(Find(List, 'atlasmask', Snippet));
  Assert.AreEqual('Maske & Wert', Snippet.Description);
  Assert.AreEqual('if Flags and $$1 <> 0 then $0;', Snippet.Body);
  Assert.AreEqual('if Flags and $1 <> 0 then ;', TAtlasSnippets.Expand(Snippet.Body, '', #10).Text);
end;

procedure TAtlasLiveTemplatesTests.SkipsBrokenXml;
var
  List: TAtlasSnippetList;
  Stats: TAtlasLiveTemplateStats;
begin
  Stats := Default(TAtlasLiveTemplateStats);
  List := TAtlasLiveTemplates.Parse('<codetemplate><template name="x"><code><![CDATA[X;', '', Stats);
  Assert.AreEqual(0, Integer(Length(List)));
  Assert.AreEqual(1, Stats.Skipped);
  // Ohne Code: übersprungen.
  List := TAtlasLiveTemplates.Parse('<codetemplate><template name="leer"></template></codetemplate>', '', Stats);
  Assert.AreEqual(0, Integer(Length(List)));
  Assert.AreEqual(2, Stats.Skipped);
end;

procedure TAtlasLiveTemplatesTests.OwnBeforeIdeBeforeBuiltIn;
var
  Ide, Own, Merged: TAtlasSnippetList;
  Snippet: TAtlasSnippet;
begin
  Snippet := Default(TAtlasSnippet);
  Snippet.Prefix := 'tryf';
  Snippet.Body := 'IDE;';
  Snippet.Origin := TAtlasSnippetOrigin.Ide;
  Ide := [Snippet];
  Snippet.Prefix := 'forin';
  Snippet.Body := 'IDE2;';
  Ide := Ide + [Snippet];
  Snippet.Prefix := 'FORIN';
  Snippet.Body := 'Eigene;';
  Snippet.Origin := TAtlasSnippetOrigin.User;
  Own := [Snippet];
  Merged := TAtlasSnippets.Merge(TAtlasSnippets.Merge(TAtlasSnippets.BuiltIn, Ide), Own);
  Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)), Integer(Length(Merged)));
  Assert.IsTrue(Find(Merged, 'tryf', Snippet));
  Assert.AreEqual('IDE;', Snippet.Body);
  Assert.IsTrue(Find(Merged, 'forin', Snippet));
  Assert.AreEqual('Eigene;', Snippet.Body);
end;

procedure TAtlasLiveTemplatesTests.IdeTemplateAppearsInList;
var
  List: TAtlasSnippetList;
  Stats: TAtlasLiveTemplateStats;
  Items: TAtlasCompletionItems;
  Item: TAtlasCompletionItem;
  Found: Boolean;
begin
  List := TAtlasLiveTemplates.LoadFolder(LiveTemplateFolder, Stats);
  Items := TAtlasSnippetCompletionProvider.Items(TAtlasSnippets.Merge(TAtlasSnippets.BuiltIn, List));
  Found := False;
  for Item in Items do
    if Item.Name = 'forb' then
      Found := Item.Snippet <> '';
  Assert.IsTrue(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSnippetsTests);
  TDUnitX.RegisterTestFixture(TAtlasLiveTemplatesTests);
  TDUnitX.RegisterTestFixture(TAtlasSnippetCatalogTests);
  TDUnitX.RegisterTestFixture(TAtlasPlaceholderSessionTests);
  TDUnitX.RegisterTestFixture(TAtlasSnippetProviderTests);

end.
