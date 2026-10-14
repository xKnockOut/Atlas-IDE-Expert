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
  Atlas.Core.Completion.Snippets,
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasSnippetsTests);
  TDUnitX.RegisterTestFixture(TAtlasPlaceholderSessionTests);
  TDUnitX.RegisterTestFixture(TAtlasSnippetProviderTests);

end.
