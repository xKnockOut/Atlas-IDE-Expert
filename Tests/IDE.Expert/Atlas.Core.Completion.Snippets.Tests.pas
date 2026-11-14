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
    [Test]
    procedure ContextForGenerateMenu;
    [Test]
    procedure ParsesPostfixSnippets;
    [Test]
    procedure SendsPostfixSnippetsToServer;
    [Test]
    procedure TagsPostfixItems;
    [Test]
    procedure ConvertsServerSnippets;
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
    /// <summary>Numerische Entities wie im Server (Atlas.Text.Entities).</summary>
    [Test]
    procedure DecodesNumericEntities;
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
    [Test]
    procedure LinkedFieldOutsideSnippet;
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
  System.Generics.Collections,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Presentation,
  Atlas.Common.Rules.Builtin.Components,
  Atlas.Tests.RuleAssert,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.LiveTemplates,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.Core.Completion.Placeholders,
  Atlas.Core.Completion.Providers.Snippets;

const
  cTryFinally = '${1:List} := ${2:TStringList}.Create;'#10'try'#10'  $0'#10'finally'#10'  ${1}.Free;'#10'end;';

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

function Find(const AList: TAtlasSnippetList; const APrefix: string; out ASnippet: TAtlasSnippet): Boolean;
var
  mItem: TAtlasSnippet;
begin
  for mItem in AList do
  begin
    if SameText(mItem.Prefix, APrefix) then
    begin
      ASnippet := mItem;
      Exit(True);
    end;
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
  mIndex: Integer;
begin
  Result := AText;
  for mIndex := High(AEdits) downto 0 do
  begin
    Result := Replace(Result, AEdits[mIndex].Start, AEdits[mIndex].Stop, AEdits[mIndex].Text);
  end;
end;

{ TAtlasSnippetsTests }

procedure TAtlasSnippetsTests.ParsesSnippetFile;
var
  mSnippet: TAtlasSnippet;
  mError: string;
begin
  Assert.IsTrue(TAtlasSnippets.Parse(
    '# Eigene Vorlage'#13#10'name: Liste anlegen'#13#10'prefix: lst'#13#10'description: TStringList mit Freigabe'#13#10 +
    '---'#13#10'${1:L} := TStringList.Create;'#13#10'  $0'#13#10#13#10, 'C:\lst.atlas-snippet', mSnippet, mError), mError);
  Assert.AreEqual('Liste anlegen', mSnippet.Name);
  Assert.AreEqual('lst', mSnippet.Prefix);
  Assert.AreEqual('TStringList mit Freigabe', mSnippet.Description);
  Assert.AreEqual('${1:L} := TStringList.Create;'#10'  $0', mSnippet.Body);
  Assert.AreEqual<TAtlasSnippetOrigin>(TAtlasSnippetOrigin.User, mSnippet.Origin);
  // Ohne Namen gilt das Kürzel.
  Assert.IsTrue(TAtlasSnippets.Parse('prefix: x'#10'---'#10'X;', '', mSnippet, mError));
  Assert.AreEqual('x', mSnippet.Name);
end;

procedure TAtlasSnippetsTests.ReportsBrokenFiles;
var
  mSnippet: TAtlasSnippet;
  mError: string;
begin
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x'#10'X;', '', mSnippet, mError));
  Assert.Contains(mError, '---');
  Assert.IsFalse(TAtlasSnippets.Parse('name: x'#10'---'#10'X;', '', mSnippet, mError));
  Assert.Contains(mError, 'prefix');
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x'#10'scope: y'#10'---'#10'X;', '', mSnippet, mError));
  Assert.Contains(mError, 'scope');
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x y'#10'---'#10'X;', '', mSnippet, mError));
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x'#10'---'#10#10, '', mSnippet, mError));
end;

procedure TAtlasSnippetsTests.ExpandsWithIndentAndLinkedDefaults;
var
  mExpansion: TAtlasSnippetExpansion;
begin
  mExpansion := TAtlasSnippets.Expand(cTryFinally, '    ', #13#10);
  Assert.AreEqual('List := TStringList.Create;'#13#10'    try'#13#10'      '#13#10'    finally'#13#10 +
    '      List.Free;'#13#10'    end;', mExpansion.Text);
  Assert.AreEqual(4, Integer(Length(mExpansion.Stops)));
  // List, TStringList, $0, zweites List mit dem Vorgabetext des ersten.
  Assert.AreEqual(1, mExpansion.Stops[0].Number);
  Assert.AreEqual(0, mExpansion.Stops[0].Start);
  Assert.AreEqual(4, mExpansion.Stops[0].Length);
  Assert.AreEqual(2, mExpansion.Stops[1].Number);
  Assert.AreEqual('TStringList', Copy(mExpansion.Text, mExpansion.Stops[1].Start + 1, mExpansion.Stops[1].Length));
  Assert.AreEqual(0, mExpansion.Stops[2].Number);
  Assert.AreEqual(0, mExpansion.Stops[2].Length);
  Assert.AreEqual(1, mExpansion.Stops[3].Number);
  Assert.AreEqual('List', Copy(mExpansion.Text, mExpansion.Stops[3].Start + 1, mExpansion.Stops[3].Length));
  Assert.IsTrue(mExpansion.HasPlaceholders);
  Assert.AreEqual('A := B;', TAtlasSnippets.PlainText('${1:A} := ${2:B};$0'));
  Assert.IsFalse(TAtlasSnippets.Expand('Exit;$0', '', #10).HasPlaceholders);
end;

procedure TAtlasSnippetsTests.KeepsHexNumbers;
var
  mExpansion: TAtlasSnippetExpansion;
begin
  mExpansion := TAtlasSnippets.Expand('Mask := $FF or $0F or $10 or $0A;${x} $', '', #10);
  Assert.AreEqual('Mask := $FF or $0F or $10 or $0A;${x} $', mExpansion.Text);
  Assert.AreEqual(0, Integer(Length(mExpansion.Stops)));
  Assert.AreEqual('{$IFDEF X}Y{$ENDIF}', TAtlasSnippets.PlainText('{$IFDEF X}${1:Y}{$ENDIF}'));
end;

procedure TAtlasSnippetsTests.UserSnippetsReplaceBuiltIn;
var
  mOwn, mSecond: TAtlasSnippet;
  mMerged: TAtlasSnippetList;
  mFound: TAtlasSnippet;
begin
  mOwn := Default(TAtlasSnippet);
  mOwn.Prefix := 'TRYF';
  mOwn.Body := 'eigene';
  mOwn.Origin := TAtlasSnippetOrigin.User;
  mSecond := mOwn;
  mSecond.Body := 'zweite';
  mMerged := TAtlasSnippets.Merge(TAtlasSnippets.BuiltIn, [mOwn, mSecond]);
  Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)), Integer(Length(mMerged)));
  Assert.IsTrue(Find(mMerged, 'tryf', mFound));
  Assert.AreEqual('eigene', mFound.Body);
  Assert.IsTrue(Find(mMerged, 'forin', mFound));
  Assert.AreEqual<TAtlasSnippetOrigin>(TAtlasSnippetOrigin.BuiltIn, mFound.Origin);
end;

procedure TAtlasSnippetsTests.BuiltInSnippetsParse;
var
  mSnippet: TAtlasSnippet;
  mCode, mText: string;
begin
  for mSnippet in TAtlasSnippets.BuiltIn do
  begin
    mCode := TAtlasSnippets.Expand(mSnippet.Body, '    ', #10).Text;
    // Je nach Art an die passende Stelle einer Unit.
    if (mSnippet.Prefix = 'class') or (mSnippet.Prefix = 'record') or (mSnippet.Prefix = 'comp') then
    begin
      mText := 'unit U;'#10'interface'#10'type'#10'  ' + mCode + #10'implementation'#10'end.';
    end
    else if mSnippet.Prefix = 'prop' then
    begin
      mText := 'unit U;'#10'interface'#10'type'#10'  T = class'#10'  public'#10'    ' + mCode + #10'  end;'#10 +
        'implementation'#10'end.';
    end
    else if (mSnippet.Prefix = 'propset') or (mSnippet.Prefix = 'reg') then
    begin
      mText := 'unit U;'#10'interface'#10'implementation'#10 + mCode + #10'end.';
    end
    else
    begin
      mText := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'    ' + mCode + #10'end;'#10'end.';
    end;
    Assert.IsTrue(Parses(mText), mSnippet.Prefix + ': ' + mText);
    Assert.AreNotEqual('', mSnippet.Description, mSnippet.Prefix);
  end;
end;

procedure TAtlasSnippetsTests.LoadsFolder;
var
  mFolder: string;
  mLines: TStringList;
  mSnippets: TAtlasSnippetList;
  mErrors: TArray<string>;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasSnippets' + IntToStr(Random(1000000)));
  ForceDirectories(mFolder);
  mLines := TStringList.Create;
  try
    mLines.Text := 'prefix: lst'#13#10'---'#13#10'L := TStringList.Create;';
    mLines.SaveToFile(TPath.Combine(mFolder, 'b.atlas-snippet'), TEncoding.UTF8);
    mLines.Text := 'kaputt';
    mLines.SaveToFile(TPath.Combine(mFolder, 'a.atlas-snippet'), TEncoding.UTF8);
    mLines.Text := 'prefix: nicht'#13#10'---'#13#10'X;';
    mLines.SaveToFile(TPath.Combine(mFolder, 'c.txt'), TEncoding.UTF8);
    mSnippets := TAtlasSnippets.LoadFolder(mFolder, mErrors);
    Assert.AreEqual(1, Integer(Length(mSnippets)));
    Assert.AreEqual('lst', mSnippets[0].Prefix);
    Assert.AreEqual('L := TStringList.Create;', mSnippets[0].Body);
    Assert.AreEqual(1, Integer(Length(mErrors)));
    Assert.StartsWith('a.atlas-snippet: ', mErrors[0]);
  finally
    mLines.Free;
    TDirectory.Delete(mFolder, True);
  end;
  mSnippets := TAtlasSnippets.LoadFolder(mFolder, mErrors);
  Assert.AreEqual(0, Integer(Length(mSnippets)));
end;

{ TAtlasPlaceholderSessionTests }

function Start(const ABefore, ABody, AAfter: string; out ADocument: string): TAtlasPlaceholderSession;
var
  mExpansion: TAtlasSnippetExpansion;
begin
  mExpansion := TAtlasSnippets.Expand(ABody, '  ', #10);
  ADocument := ABefore + mExpansion.Text + AAfter;
  Result := TAtlasPlaceholderSession.Create(ADocument, Length(ABefore), mExpansion);
end;

procedure TAtlasPlaceholderSessionTests.TabWalksThroughPlaceholders;
var
  mSession: TAtlasPlaceholderSession;
  mDocument: string;
begin
  mSession := Start('begin'#10'  ', cTryFinally, #10'end;', mDocument);
  try
    Assert.AreEqual(1, mSession.CurrentNumber);
    Assert.AreEqual(1, mSession.Position);
    Assert.AreEqual(2, Integer(mSession.Count));
    Assert.AreEqual(8, mSession.Current.Start);
    Assert.AreEqual('List', mSession.FieldText(mSession.Current));
    Assert.AreEqual(3, Integer(Length(mSession.Fields)));
    mSession.Previous;
    Assert.AreEqual(1, mSession.CurrentNumber);
    Assert.IsTrue(mSession.Next);
    Assert.AreEqual('TStringList', mSession.FieldText(mSession.Current));
    Assert.AreEqual(2, mSession.Position);
    mSession.Previous;
    Assert.AreEqual(1, mSession.CurrentNumber);
    Assert.IsTrue(mSession.Next);
    // Nach dem letzten Platzhalter: Endposition in der leeren Zeile zwischen try und finally.
    Assert.IsFalse(mSession.Next);
    Assert.AreEqual(0, mSession.CurrentNumber);
    Assert.AreEqual(Pos('try'#10'    ', mDocument) + 7, mSession.FinalOffset);
  finally
    mSession.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.TypingUpdatesLinkedPlaceholders;
var
  mSession: TAtlasPlaceholderSession;
  mDocument: string;
  mEdits: TAtlasPlaceholderEdits;
begin
  mSession := Start('', cTryFinally, '', mDocument);
  try
    // Die markierte Vorgabe "List" wird durch "I" ersetzt, dann "tems" getippt.
    mDocument := Replace(mDocument, 0, 4, 'I');
    Assert.IsTrue(mSession.Update(mDocument));
    mDocument := Replace(mDocument, 1, 1, 'tems');
    Assert.IsTrue(mSession.Update(mDocument));
    Assert.AreEqual('Items', mSession.FieldText(mSession.Current));
    mEdits := mSession.MirrorEdits;
    Assert.AreEqual(1, Integer(Length(mEdits)));
    Assert.AreEqual('Items', mEdits[0].Text);
    mDocument := Apply(mDocument, mEdits);
    mSession.Applied(mEdits);
    Assert.AreEqual(mDocument, mSession.Text);
    Assert.AreEqual('Items := TStringList.Create;'#10'  try'#10'    '#10'  finally'#10'    Items.Free;'#10'  end;', mDocument);
    // Die Benachrichtigung über das Angleichen ändert nichts mehr.
    Assert.IsTrue(mSession.Update(mDocument));
    Assert.AreEqual(0, Integer(Length(mSession.MirrorEdits)));
    // Im verknüpften Platzhalter getippt: Er wird zur Vorlage.
    mDocument := Replace(mDocument, Pos('Items.Free', mDocument) + 4, Pos('Items.Free', mDocument) + 4, 'X');
    Assert.IsTrue(mSession.Update(mDocument));
    mEdits := mSession.MirrorEdits;
    Assert.AreEqual('ItemsX', mEdits[0].Text);
    Assert.AreEqual(0, mEdits[0].Start);
    mDocument := Apply(mDocument, mEdits);
    mSession.Applied(mEdits);
    Assert.StartsWith('ItemsX := TStringList', mDocument);
    Assert.AreEqual(mDocument, mSession.Text);
    // Alles bis auf einen leeren Platzhalter löschen geht auch.
    mSession.Previous;
    mDocument := Replace(mDocument, 0, 6, '');
    Assert.IsTrue(mSession.Update(mDocument));
    Assert.AreEqual(0, mSession.Current.Length);
  finally
    mSession.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.TypingAfterPlaceholderMovesFollowingOnes;
var
  mSession: TAtlasPlaceholderSession;
  mDocument: string;
  mFinal: Integer;
begin
  mSession := Start('x', cTryFinally, '', mDocument);
  try
    Assert.IsTrue(mSession.Next);
    mFinal := mSession.FinalOffset;
    // Am Ende von "TStringList" ein "." anhängen; dahinter steht schon einer, die Stelle ist also mehrdeutig.
    mDocument := Replace(mDocument, mSession.Current.Stop, mSession.Current.Stop, '.');
    Assert.IsTrue(mSession.Update(mDocument));
    Assert.AreEqual('TStringList.', mSession.FieldText(mSession.Current));
    Assert.AreEqual(mFinal + 1, mSession.FinalOffset);
    Assert.AreEqual(0, Integer(Length(mSession.MirrorEdits)));
  finally
    mSession.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.EditOutsideEndsSession;
var
  mSession: TAtlasPlaceholderSession;
  mDocument: string;
begin
  mSession := Start('begin'#10, cTryFinally, '', mDocument);
  try
    Assert.IsFalse(mSession.Update(Replace(mDocument, 0, 0, '//')));
  finally
    mSession.Free;
  end;
  // Änderung im Platzhalter 2, während 1 aktiv ist: auch vorbei.
  mSession := Start('', cTryFinally, '', mDocument);
  try
    Assert.IsFalse(mSession.Update(Replace(mDocument, 9, 9, 'X')));
  finally
    mSession.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.WithoutEndMarkerEndsBehindSnippet;
var
  mSession: TAtlasPlaceholderSession;
  mDocument: string;
begin
  mSession := Start('a ', 'Exit(${1:False});', ' b', mDocument);
  try
    Assert.AreEqual(1, Integer(mSession.Count));
    Assert.IsFalse(mSession.Next);
    Assert.AreEqual(Integer(Length('a Exit(False);')), mSession.FinalOffset);
  finally
    mSession.Free;
  end;
end;

procedure TAtlasPlaceholderSessionTests.LocatesOffsets;
var
  mLine, mCharacter: Integer;
begin
  TAtlasPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 0, mLine, mCharacter);
  Assert.AreEqual(0, mLine);
  Assert.AreEqual(0, mCharacter);
  TAtlasPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 6, mLine, mCharacter);
  Assert.AreEqual(1, mLine);
  Assert.AreEqual(2, mCharacter);
  TAtlasPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 99, mLine, mCharacter);
  Assert.AreEqual(2, mLine);
  Assert.AreEqual(1, mCharacter);
end;

procedure TAtlasPlaceholderSessionTests.LinkedFieldOutsideSnippet;
const
  cDeclaration = '  SName = ''Name'';'#10;
var
  mSession: TAtlasPlaceholderSession;
  mDocument: string;
  mEdits: TAtlasPlaceholderEdits;
  mField: TAtlasPlaceholderField;
begin
  // resourcestring auslagern (#473): Der Name steht in der Deklaration davor und im Literal.
  mSession := Start(cDeclaration + 'begin'#10'  ShowMessage(', '${1:SName}', ');', mDocument);
  try
    mField.Number := 1;
    mField.Start := 2;
    mField.Length := 5;
    mSession.Link(mField);
    // Unbekannte Nummer und Endposition werden übergangen.
    mField.Number := 7;
    mSession.Link(mField);
    mField.Number := 0;
    mSession.Link(mField);
    Assert.AreEqual(2, Integer(Length(mSession.Fields)));
    Assert.AreEqual(1, Integer(mSession.Count));
    Assert.AreEqual('SName', mSession.FieldText(mSession.Current));
    // Im Literal getippt: Die Deklaration davor folgt, der Platzhalter im Literal rückt nach.
    mDocument := Replace(mDocument, mSession.Current.Start, mSession.Current.Stop, 'SFrage');
    Assert.IsTrue(mSession.Update(mDocument));
    mEdits := mSession.MirrorEdits;
    Assert.AreEqual(1, Integer(Length(mEdits)));
    Assert.AreEqual(2, mEdits[0].Start);
    Assert.AreEqual('SFrage', mEdits[0].Text);
    mDocument := Apply(mDocument, mEdits);
    mSession.Applied(mEdits);
    Assert.AreEqual(mDocument, mSession.Text);
    Assert.AreEqual('  SFrage = ''Name'';'#10'begin'#10'  ShowMessage(SFrage);', mDocument);
    Assert.AreEqual(Pos('(SFrage', mDocument), mSession.Current.Start);
    Assert.AreEqual('SFrage', mSession.FieldText(mSession.Current));
  finally
    mSession.Free;
  end;
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
  mItems: TAtlasCompletionItems;
  mTags: TAtlasTags;
begin
  mItems := TAtlasSnippetCompletionProvider.Items(TAtlasSnippets.BuiltIn);
  Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)), Integer(Length(mItems)));
  Assert.AreEqual('tryf', mItems[0].Name);
  Assert.AreEqual<TAtlasItemKind>(TAtlasItemKind.Snippet, mItems[0].Kind);
  Assert.AreEqual('try…finally mit Create/Free', mItems[0].Signature);
  Assert.AreEqual(TAtlasSnippets.BuiltIn[0].Body, mItems[0].Snippet);
  Assert.StartsWith('Objekt anlegen', mItems[0].Documentation);
  Assert.Contains(mItems[0].Documentation, 'List.Free;');
  Assert.IsTrue(mItems[1].Rank > mItems[0].Rank);
  Assert.AreEqual('sn', TAtlasItemPresentation.Badge(mItems[0]).Code);
  mTags := TAtlasItemPresentation.Tags(mItems[0]);
  Assert.AreEqual(1, Integer(Length(mTags)));
  Assert.AreEqual('Snippet', mTags[0].Text);
end;

procedure TAtlasSnippetsTests.ConvertsServerSnippets;
var
  mExpansion: TAtlasSnippetExpansion;
begin
  // LSP-Syntax des Servers (#51) im eigenen Format.
  Assert.AreEqual('property ${1:Farbe}: TColor;$0', TAtlasSnippets.FromLsp('property ${1:Farbe}: TColor;$0'));
  Assert.AreEqual('X := $$FF; a}b\c', TAtlasSnippets.FromLsp('X := \$FF; a\}b\\c'));
  Assert.AreEqual('${1} ${2:ja}', TAtlasSnippets.FromLsp('$1 ${2|ja,nein|}'));
  Assert.AreEqual('${1:Liste.Free} $$FF', TAtlasSnippets.FromLsp('${1:${2:Liste}.Free} ${TM_SELECTED_TEXT}$FF'));
  Assert.AreEqual('a$$b', TAtlasSnippets.FromLsp('a$b'));
  // Eingesetzt: Platzhalter und Endposition wie bei den eigenen Vorlagen, Hexzahl als Text.
  mExpansion := TAtlasSnippets.Expand(TAtlasSnippets.FromLsp('if F <> \$FF then'#10'  ${1:Invalidate};$0'), '  ',
    #10);
  Assert.AreEqual('if F <> $FF then'#10'    Invalidate;', mExpansion.Text);
  Assert.AreEqual(2, Integer(Length(mExpansion.Stops)));
  Assert.AreEqual(1, mExpansion.Stops[0].Number);
end;

procedure TAtlasSnippetsTests.DoubleDollarIsText;
var
  mExpansion: TAtlasSnippetExpansion;
begin
  mExpansion := TAtlasSnippets.Expand('X := Y and $$1;$0', '', #10);
  Assert.AreEqual('X := Y and $1;', mExpansion.Text);
  Assert.AreEqual(1, Integer(Length(mExpansion.Stops)));
  Assert.AreEqual(0, mExpansion.Stops[0].Number);
end;

procedure TAtlasSnippetsTests.SetterSnippetKeepsInvalidateRuleSilent;
const
  cHead = 'unit U;'#10'interface'#10'type'#10'  TMyControl = class(TCustomControl)'#10'  private'#10 +
    '    FValue: Integer;'#10'    procedure SetValue(const Value: Integer);'#10'  protected'#10 +
    '    procedure Paint; override;'#10'  published'#10'    property Value: Integer read FValue write SetValue;'#10 +
    '  end;'#10'implementation'#10'procedure TMyControl.Paint;'#10'begin'#10'  inherited;'#10 +
    '  Canvas.TextOut(0, 0, IntToStr(FValue));'#10'end;'#10;
var
  mSnippet: TAtlasSnippet;
begin
  // Gegenprobe: ohne Invalidate meldet die Regel (#55).
  TRuleAssert.Reports(TComponentSetterWithoutInvalidateRule.Create, cHead +
    'procedure TMyControl.SetValue(const Value: Integer);'#10'begin'#10'  FValue := Value;'#10'end;'#10'end.');
  Assert.IsTrue(Find(TAtlasSnippets.BuiltIn, 'propset', mSnippet));
  TRuleAssert.Silent(TComponentSetterWithoutInvalidateRule.Create,
    cHead + TAtlasSnippets.Expand(mSnippet.Body, '', #10).Text + #10'end.');
end;

procedure TAtlasSnippetsTests.FormatRoundTrips;
var
  mSnippet, mParsed: TAtlasSnippet;
  mError: string;
begin
  mSnippet := Default(TAtlasSnippet);
  mSnippet.Name := 'Schleife über eine Liste';
  mSnippet.Prefix := 'forl';
  mSnippet.Description := 'for-Schleife bis Count - 1';
  mSnippet.Body := 'for ${1:I} := 0 to ${2:List}.Count - 1 do'#10'  $0';
  Assert.IsTrue(TAtlasSnippets.Parse(TAtlasSnippets.ToFileText(mSnippet), 'forl.atlas-snippet', mParsed, mError), mError);
  Assert.AreEqual(mSnippet.Name, mParsed.Name);
  Assert.AreEqual(mSnippet.Prefix, mParsed.Prefix);
  Assert.AreEqual(mSnippet.Description, mParsed.Description);
  Assert.AreEqual(mSnippet.Body, mParsed.Body);
  Assert.AreEqual('forl.atlas-snippet', TAtlasSnippets.FileNameFor('forl'));
  Assert.AreEqual('a_b.atlas-snippet', TAtlasSnippets.FileNameFor('a\b'));
end;

procedure TAtlasSnippetsTests.ContextForGenerateMenu;
var
  mSnippet, mParsed: TAtlasSnippet;
  mError: string;
begin
  // Kontext für das Erzeugen-Menü (#719, Kontext aus #665).
  Assert.IsTrue(TAtlasSnippets.Parse('prefix: lg'#10'context: statement, class'#10'---'#10'Log;', '', mSnippet, mError),
    mError);
  Assert.AreEqual('statement, class', mSnippet.Context);
  Assert.IsTrue(TAtlasSnippets.Parse(TAtlasSnippets.ToFileText(mSnippet), '', mParsed, mError), mError);
  Assert.AreEqual('statement, class', mParsed.Context);
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: lg'#10'context: irgendwo'#10'---'#10'Log;', '', mSnippet, mError));
  Assert.Contains(mError, 'irgendwo');
  // Ohne Kontext überall, statement nur in Routinen, declaration nicht im Rumpf.
  Assert.IsTrue(TAtlasSnippets.FitsContext('', ['class']));
  Assert.IsTrue(TAtlasSnippets.FitsContext('any', []));
  Assert.IsTrue(TAtlasSnippets.FitsContext('statement', ['routine', 'class']));
  Assert.IsFalse(TAtlasSnippets.FitsContext('statement', ['class']));
  Assert.IsTrue(TAtlasSnippets.FitsContext('declaration', ['interface']));
  Assert.IsTrue(TAtlasSnippets.FitsContext('declaration', ['class']));
  Assert.IsFalse(TAtlasSnippets.FitsContext('declaration', ['routine', 'class']));
  Assert.IsTrue(TAtlasSnippets.FitsContext('implementation, class', ['implementation']));
  Assert.IsFalse(TAtlasSnippets.FitsContext('class', ['record']));
  // Mitgelieferte Vorlagen haben einen Kontext.
  for mSnippet in TAtlasSnippets.BuiltIn do
  begin
    Assert.AreNotEqual('', mSnippet.Context, mSnippet.Prefix);
  end;
  // Dateivorlage (#759): Kopf "file:", nur unit, form oder test; bleibt beim Speichern erhalten.
  Assert.IsTrue(TAtlasSnippets.Parse('prefix: svc'#10'file: Unit'#10'---'#10'unit %Unit%;', '', mSnippet, mError), mError);
  Assert.AreEqual('unit', mSnippet.FileKind);
  Assert.IsTrue(TAtlasSnippets.Parse(TAtlasSnippets.ToFileText(mSnippet), '', mParsed, mError), mError);
  Assert.AreEqual('unit', mParsed.FileKind);
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: svc'#10'file: paket'#10'---'#10'x', '', mSnippet, mError));
  Assert.Contains(mError, 'paket');
  Assert.AreEqual(1, Integer(Length(TAtlasSnippets.FileTemplates([mParsed] + TAtlasSnippets.BuiltIn))));
  Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)),
    Integer(Length(TAtlasSnippets.WithoutFileTemplates([mParsed] +
    TAtlasSnippets.BuiltIn))));
end;

procedure TAtlasSnippetsTests.ParsesPostfixSnippets;
var
  mSnippet, mParsed: TAtlasSnippet;
  mError: string;
begin
  // Eigene Postfix-Vorlage (#188): Kopfzeilen postfix und type.
  Assert.IsTrue(TAtlasSnippets.Parse('name: Protokoll'#10'prefix: log'#10'postfix: true'#10'type: class'#10'---'#10 +
    'Log($expr);', 'log.atlas-snippet', mSnippet, mError), mError);
  Assert.IsTrue(mSnippet.Postfix);
  Assert.AreEqual('class', mSnippet.TypeCondition);
  Assert.AreEqual('Log($expr);', mSnippet.Body);
  // Ohne Kopfzeile: gewöhnliche Vorlage.
  Assert.IsTrue(TAtlasSnippets.Parse('prefix: x'#10'---'#10'X;', '', mParsed, mError), mError);
  Assert.IsFalse(mParsed.Postfix);
  Assert.IsFalse(TAtlasSnippets.Parse('prefix: x'#10'postfix: ja'#10'---'#10'X;', '', mParsed, mError));
  Assert.Contains(mError, 'postfix');
  // Schreiben und wieder lesen.
  Assert.IsTrue(TAtlasSnippets.Parse(TAtlasSnippets.ToFileText(mSnippet), 'log.atlas-snippet', mParsed, mError), mError);
  Assert.IsTrue(mParsed.Postfix);
  Assert.AreEqual('class', mParsed.TypeCondition);
  mSnippet.TypeCondition := '';
  Assert.IsFalse(TAtlasSnippets.ToFileText(mSnippet).Contains('type:'));
  mSnippet.Postfix := False;
  Assert.IsFalse(TAtlasSnippets.ToFileText(mSnippet).Contains('postfix:'));
end;

procedure TAtlasSnippetsTests.SendsPostfixSnippetsToServer;
var
  mList: TAtlasSnippetList;
  mParams: TJSONObject;
  mTemplates: TJSONArray;
begin
  SetLength(mList, 3);
  mList[0].Name := 'Schleife';
  mList[0].Prefix := 'forl';
  mList[0].Body := 'for ${1:I} := 0 to 9 do';
  mList[1].Name := 'Protokoll';
  mList[1].Prefix := 'log';
  mList[1].Body := 'Log($expr);';
  mList[1].Postfix := True;
  mList[1].TypeCondition := 'TKunde';
  mList[2].Name := 'Prüfen';
  mList[2].Prefix := 'chk';
  mList[2].Description := 'Prüft den Wert';
  mList[2].Body := 'Pruefe($expr);';
  mList[2].Postfix := True;
  Assert.AreEqual(2, Integer(Length(TAtlasSnippets.Postfixes(mList))));
  Assert.AreEqual(1, Integer(Length(TAtlasSnippets.WithoutPostfix(mList))));
  Assert.AreEqual('forl', TAtlasSnippets.WithoutPostfix(mList)[0].Prefix);
  mParams := TAtlasSnippets.PostfixParams(mList);
  try
    mTemplates := mParams.GetValue('templates') as TJSONArray;
    Assert.AreEqual(2, Integer(mTemplates.Count));
    Assert.AreEqual('log', mTemplates.Items[0].GetValue<string>('key'));
    // Ohne Beschreibung gilt der Name.
    Assert.AreEqual('Protokoll', mTemplates.Items[0].GetValue<string>('description'));
    Assert.AreEqual('Log($expr);', mTemplates.Items[0].GetValue<string>('body'));
    Assert.AreEqual('TKunde', mTemplates.Items[0].GetValue<string>('type'));
    Assert.AreEqual('Prüft den Wert', mTemplates.Items[1].GetValue<string>('description'));
    Assert.IsNull(TJSONObject(mTemplates.Items[1]).GetValue('type'));
  finally
    mParams.Free;
  end;
  // Ohne Postfix-Vorlagen eine leere Liste: Der Server vergisst die früheren.
  mParams := TAtlasSnippets.PostfixParams(TAtlasSnippets.WithoutPostfix(mList));
  try
    Assert.AreEqual(0, (mParams.GetValue('templates') as TJSONArray).Count);
  finally
    mParams.Free;
  end;
end;

procedure TAtlasSnippetsTests.TagsPostfixItems;
var
  mItem: TAtlasCompletionItem;
  mTags: TAtlasTags;
begin
  mItem := Default(TAtlasCompletionItem);
  mItem.Name := 'notnil';
  mItem.Kind := TAtlasItemKind.Snippet;
  mItem.Snippet := 'if Assigned(X) then'#10'  $0';
  mItem.Postfix := True;
  mTags := TAtlasItemPresentation.Tags(mItem);
  Assert.AreEqual(1, Integer(Length(mTags)));
  Assert.AreEqual('Postfix', mTags[0].Text);
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
  mCatalog: TAtlasSnippetCatalog;
  mIde: TAtlasSnippet;
  mIndex: Integer;
begin
  mIde := OwnSnippet('forin', 'IDE;');
  mIde.Origin := TAtlasSnippetOrigin.Ide;
  mCatalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, [mIde], [OwnSnippet('tryf', 'X;')]);
  try
    Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)) + 2, mCatalog.Count);
    Assert.AreEqual<TAtlasSnippetOrigin>(TAtlasSnippetOrigin.User, mCatalog.Entry(0).Snippet.Origin);
    Assert.AreEqual<TAtlasSnippetOrigin>(TAtlasSnippetOrigin.Ide, mCatalog.Entry(1).Snippet.Origin);
    Assert.IsFalse(mCatalog.Replaced(0));
    Assert.IsFalse(mCatalog.Replaced(1));
    for mIndex := 2 to mCatalog.Count - 1 do
    begin
      if SameText(mCatalog.Entry(mIndex).Snippet.Prefix, 'tryf') or
        SameText(mCatalog.Entry(mIndex).Snippet.Prefix, 'forin') then
      begin
        Assert.IsTrue(mCatalog.Replaced(mIndex), mCatalog.Entry(mIndex).Snippet.Prefix);
      end
      else
      begin
        Assert.IsFalse(mCatalog.Replaced(mIndex), mCatalog.Entry(mIndex).Snippet.Prefix);
      end;
    end;
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSnippetCatalogTests.OnlyOwnAreEditable;
var
  mCatalog: TAtlasSnippetCatalog;
  mChanged: TAtlasSnippet;
  mIndex, mLast: Integer;
begin
  mCatalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, nil);
  try
    mLast := mCatalog.Count - 1;
    Assert.IsFalse(mCatalog.Editable(mLast));
    mChanged := mCatalog.Entry(mLast).Snippet;
    mChanged.Body := 'geändert';
    mCatalog.Update(mLast, mChanged);
    Assert.AreNotEqual('geändert', mCatalog.Entry(mLast).Snippet.Body);
    Assert.IsFalse(mCatalog.Modified);
    // Kopie als eigene: steht vorn, gleiches Kürzel, ersetzt das Original.
    mIndex := mCatalog.CopyAsOwn(mLast);
    Assert.AreEqual(0, mIndex);
    Assert.IsTrue(mCatalog.Editable(0));
    Assert.AreEqual(mCatalog.Entry(mLast + 1).Snippet.Prefix, mCatalog.Entry(0).Snippet.Prefix);
    Assert.IsTrue(mCatalog.Replaced(mLast + 1));
    Assert.IsTrue(mCatalog.Modified);
    // Neue eigene: freies Kürzel, hinter den eigenen.
    mIndex := mCatalog.AddNew;
    Assert.AreEqual(1, mIndex);
    Assert.AreEqual('neu', mCatalog.Entry(1).Snippet.Prefix);
    Assert.AreEqual('neu2', mCatalog.Entry(mCatalog.AddNew).Snippet.Prefix);
    mCatalog.Delete(1);
    Assert.AreEqual('neu2', mCatalog.Entry(1).Snippet.Prefix);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSnippetCatalogTests.ValidatesOwnSnippets;
var
  mCatalog: TAtlasSnippetCatalog;
  mProblems: TArray<TAtlasSnippetProblem>;
begin
  mCatalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil,
    [OwnSnippet('a', 'X;'), OwnSnippet('A', 'Y;'), OwnSnippet('', 'Z;'), OwnSnippet('b-c', ' '),
     OwnSnippet('tryf', 'W;')]);
  try
    Assert.IsFalse(mCatalog.Validate(mProblems));
    Assert.AreEqual(4, Integer(Length(mProblems)));
    Assert.AreEqual(1, mProblems[0].Index);
    Assert.AreEqual<TAtlasSnippetProblemKind>(TAtlasSnippetProblemKind.PrefixTwice, mProblems[0].Kind);
    Assert.AreEqual<TAtlasSnippetProblemKind>(TAtlasSnippetProblemKind.PrefixMissing, mProblems[1].Kind);
    Assert.AreEqual<TAtlasSnippetProblemKind>(TAtlasSnippetProblemKind.PrefixInvalid, mProblems[2].Kind);
    Assert.AreEqual<TAtlasSnippetProblemKind>(TAtlasSnippetProblemKind.BodyMissing, mProblems[3].Kind);
    // Gleiches Kürzel wie eine mitgelieferte ist erlaubt: die eigene ersetzt sie.
    Assert.AreEqual(3, mProblems[3].Index);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSnippetCatalogTests.SavesChangedAndDeletesRemoved;
var
  mFolder: string;
  mCatalog: TAtlasSnippetCatalog;
  mLoaded: TAtlasSnippetList;
  mErrors: TArray<string>;
  mChanged: TAtlasSnippet;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasCatalog' + IntToStr(Random(1000000)));
  try
    mCatalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, nil);
    try
      mChanged := mCatalog.Entry(mCatalog.AddNew).Snippet;
      mChanged.Prefix := 'liste';
      mChanged.Description := 'Liste anlegen';
      mChanged.Body := '${1:L} := TStringList.Create;$0';
      mCatalog.Update(0, mChanged);
      mCatalog.AddNew;
      mCatalog.Save(mFolder);
      Assert.IsFalse(mCatalog.Modified);
    finally
      mCatalog.Free;
    end;
    mLoaded := TAtlasSnippets.LoadFolder(mFolder, mErrors);
    Assert.AreEqual(0, Integer(Length(mErrors)));
    Assert.AreEqual(2, Integer(Length(mLoaded)));
    Assert.IsTrue(FileExists(TPath.Combine(mFolder, 'liste.atlas-snippet')));
    // Löschen entfernt die Datei; das Umbenennen des Kürzels behält den Dateinamen.
    mCatalog := TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, mLoaded);
    try
      mChanged := mCatalog.Entry(0).Snippet;
      mChanged.Prefix := 'liste2';
      mCatalog.Update(0, mChanged);
      mCatalog.Delete(1);
      mCatalog.Save(mFolder);
    finally
      mCatalog.Free;
    end;
    mLoaded := TAtlasSnippets.LoadFolder(mFolder, mErrors);
    Assert.AreEqual(1, Integer(Length(mLoaded)));
    Assert.AreEqual('liste2', mLoaded[0].Prefix);
    Assert.AreEqual('Liste anlegen', mLoaded[0].Description);
    Assert.AreEqual('${1:L} := TStringList.Create;$0', mLoaded[0].Body);
    Assert.IsTrue(FileExists(TPath.Combine(mFolder, 'liste.atlas-snippet')));
  finally
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

{ TAtlasLiveTemplatesTests }

function LiveTemplateFolder: string;
var
  mDirectory, mCandidate: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mCandidate := TPath.Combine(mDirectory, 'Tests\Data\LiveTemplates\Delphi12');
    if TDirectory.Exists(mCandidate) then
    begin
      Exit(mCandidate);
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

procedure TAtlasLiveTemplatesTests.ReadsDelphi12Folder;
var
  mList: TAtlasSnippetList;
  mStats: TAtlasLiveTemplateStats;
  mSnippet: TAtlasSnippet;
begin
  Assert.AreNotEqual('', LiveTemplateFolder, 'Ordner Tests\Data\LiveTemplates\Delphi12 fehlt');
  mList := TAtlasLiveTemplates.LoadFolder(LiveTemplateFolder, mStats);
  Assert.AreEqual(2, mStats.Templates);
  // Die C++-Vorlage wird übersprungen, das Skript in "forb" entfällt.
  Assert.AreEqual(1, mStats.Skipped);
  Assert.AreEqual(1, mStats.Scripts);
  Assert.IsTrue(Find(mList, 'forb', mSnippet));
  Assert.AreEqual('for statement', mSnippet.Description);
  Assert.AreEqual<TAtlasSnippetOrigin>(TAtlasSnippetOrigin.Ide, mSnippet.Origin);
  Assert.IsFalse(Find(mList, 'cppfor', mSnippet));
end;

procedure TAtlasLiveTemplatesTests.ConvertsPointsAndMarkers;
var
  mList: TAtlasSnippetList;
  mStats: TAtlasLiveTemplateStats;
  mSnippet: TAtlasSnippet;
  mExpansion: TAtlasSnippetExpansion;
begin
  mStats := Default(TAtlasLiveTemplateStats);
  mList := TAtlasLiveTemplates.Parse('<codetemplate><template name="forb"><point name="ident"><text>' +
    #10'  I'#10'</text></point><point name="to"><text>N</text></point>' +
    '<code language="Delphi" delimiter="|"><![CDATA[for |ident| := 0 to |to| do'#13#10'begin'#13#10 +
    '|selected||*||end|'#13#10'  X(|ident|);'#13#10'end;'#13#10']]></code></template></codetemplate>', '', mStats);
  Assert.AreEqual(1, Integer(Length(mList)));
  mSnippet := mList[0];
  Assert.AreEqual('for ${1:I} := 0 to ${2:N} do'#10'begin'#10'  $0'#10'  X(${1});'#10'end;', mSnippet.Body);
  mExpansion := TAtlasSnippets.Expand(mSnippet.Body, '', #10);
  Assert.AreEqual('for I := 0 to N do'#10'begin'#10'  '#10'  X(I);'#10'end;', mExpansion.Text);
end;

procedure TAtlasLiveTemplatesTests.DecodesNumericEntities;
var
  mList: TAtlasSnippetList;
  mStats: TAtlasLiveTemplateStats;
begin
  mStats := Default(TAtlasLiveTemplateStats);
  mList := TAtlasLiveTemplates.Parse('<codetemplate><template name="e"><point name="v"><text>&#228;&#x20AC;&lt;' +
    '</text></point><code language="Delphi" delimiter="|"><![CDATA[X := |v|;]]></code></template></codetemplate>',
    '', mStats);
  Assert.AreEqual(1, Integer(Length(mList)));
  Assert.AreEqual('X := ${1:'#$00E4#$20AC'<};', mList[0].Body);
end;

procedure TAtlasLiveTemplatesTests.KeepsFixedPointsAndEscapesDollar;
var
  mList: TAtlasSnippetList;
  mStats: TAtlasLiveTemplateStats;
  mSnippet: TAtlasSnippet;
begin
  mList := TAtlasLiveTemplates.LoadFolder(LiveTemplateFolder, mStats);
  Assert.IsTrue(Find(mList, 'atlasmask', mSnippet));
  Assert.AreEqual('Maske & Wert', mSnippet.Description);
  Assert.AreEqual('if Flags and $$1 <> 0 then $0;', mSnippet.Body);
  Assert.AreEqual('if Flags and $1 <> 0 then ;', TAtlasSnippets.Expand(mSnippet.Body, '', #10).Text);
end;

procedure TAtlasLiveTemplatesTests.SkipsBrokenXml;
var
  mList: TAtlasSnippetList;
  mStats: TAtlasLiveTemplateStats;
begin
  mStats := Default(TAtlasLiveTemplateStats);
  mList := TAtlasLiveTemplates.Parse('<codetemplate><template name="x"><code><![CDATA[X;', '', mStats);
  Assert.AreEqual(0, Integer(Length(mList)));
  Assert.AreEqual(1, mStats.Skipped);
  // Ohne Code: übersprungen.
  mList := TAtlasLiveTemplates.Parse('<codetemplate><template name="leer"></template></codetemplate>', '', mStats);
  Assert.AreEqual(0, Integer(Length(mList)));
  Assert.AreEqual(2, mStats.Skipped);
end;

procedure TAtlasLiveTemplatesTests.OwnBeforeIdeBeforeBuiltIn;
var
  mIde, mOwn, mMerged: TAtlasSnippetList;
  mSnippet: TAtlasSnippet;
begin
  mSnippet := Default(TAtlasSnippet);
  mSnippet.Prefix := 'tryf';
  mSnippet.Body := 'IDE;';
  mSnippet.Origin := TAtlasSnippetOrigin.Ide;
  mIde := [mSnippet];
  mSnippet.Prefix := 'forin';
  mSnippet.Body := 'IDE2;';
  mIde := mIde + [mSnippet];
  mSnippet.Prefix := 'FORIN';
  mSnippet.Body := 'Eigene;';
  mSnippet.Origin := TAtlasSnippetOrigin.User;
  mOwn := [mSnippet];
  mMerged := TAtlasSnippets.Merge(TAtlasSnippets.Merge(TAtlasSnippets.BuiltIn, mIde), mOwn);
  Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)), Integer(Length(mMerged)));
  Assert.IsTrue(Find(mMerged, 'tryf', mSnippet));
  Assert.AreEqual('IDE;', mSnippet.Body);
  Assert.IsTrue(Find(mMerged, 'forin', mSnippet));
  Assert.AreEqual('Eigene;', mSnippet.Body);
end;

procedure TAtlasLiveTemplatesTests.IdeTemplateAppearsInList;
var
  mList: TAtlasSnippetList;
  mStats: TAtlasLiveTemplateStats;
  mItems: TAtlasCompletionItems;
  mItem: TAtlasCompletionItem;
  mFound: Boolean;
begin
  mList := TAtlasLiveTemplates.LoadFolder(LiveTemplateFolder, mStats);
  mItems := TAtlasSnippetCompletionProvider.Items(TAtlasSnippets.Merge(TAtlasSnippets.BuiltIn, mList));
  mFound := False;
  for mItem in mItems do
  begin
    if mItem.Name = 'forb' then
    begin
      mFound := mItem.Snippet <> '';
    end;
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSnippetsTests);
  TDUnitX.RegisterTestFixture(TAtlasLiveTemplatesTests);
  TDUnitX.RegisterTestFixture(TAtlasSnippetCatalogTests);
  TDUnitX.RegisterTestFixture(TAtlasPlaceholderSessionTests);
  TDUnitX.RegisterTestFixture(TAtlasSnippetProviderTests);

end.
