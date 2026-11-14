unit Atlas.Core.Editor.Commands.Tests;

// Tests für Auswahl erweitern/verkleinern und die Auslöser der
// Schnellbefehle (#399).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEditorCommandsTests = class
  public
    /// <summary>F3 mit Markierung: nächstes und vorheriges Vorkommen, über das Dateiende hinweg.</summary>
    [Test]
    procedure SearchFindsNextAndPreviousWithWrap;
    [Test]
    procedure ExpandsStepByStep;
    [Test]
    procedure ShrinksBackToCursor;
    [Test]
    procedure FetchesChainAtAnchor;
    [Test]
    procedure DetectsSlashCommandAfterEnter;
    [Test]
    procedure DetectsDocCommentScaffold;
    /// <summary>#88: je Beschreibung ein leerer Platzhalter, Endposition hinter dem letzten Tag.</summary>
    [Test]
    procedure DocCommentPlaceholdersInDescriptions;
    /// <summary>Antwort im Hintergrund: gilt nur für dieselbe Datei mit unverändertem Text.</summary>
    [Test]
    procedure SlashAnswerOnlyForUnchangedText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.Selection,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Editor.SlashTrigger;

function Chain: TArray<TLspRange>;
begin
  // Bezeichner, Anweisung, Datei.
  Result := [TLspRange.Create(3, 2, 3, 7), TLspRange.Create(3, 2, 3, 20), TLspRange.Create(0, 0, 9, 0)];
end;

procedure TAtlasEditorCommandsTests.ExpandsStepByStep;
var
  mNext: TLspRange;
begin
  Assert.IsTrue(TAtlasSelectionSteps.Expand(Chain, TLspRange.Create(3, 4, 3, 4), mNext));
  Assert.IsTrue(mNext.Same(TLspRange.Create(3, 2, 3, 7)), 'erst der Bezeichner');
  Assert.IsTrue(TAtlasSelectionSteps.Expand(Chain, mNext, mNext));
  Assert.IsTrue(mNext.Same(TLspRange.Create(3, 2, 3, 20)), 'dann die Anweisung');
  // Eine selbst gezogene Auswahl springt zum nächsten Bereich, der sie ganz enthält.
  Assert.IsTrue(TAtlasSelectionSteps.Expand(Chain, TLspRange.Create(3, 5, 3, 12), mNext));
  Assert.IsTrue(mNext.Same(TLspRange.Create(3, 2, 3, 20)));
  Assert.IsFalse(TAtlasSelectionSteps.Expand(Chain, TLspRange.Create(0, 0, 9, 0), mNext), 'ganze Datei');
  Assert.IsFalse(TAtlasSelectionSteps.Expand(nil, TLspRange.Create(3, 4, 3, 4), mNext), 'ohne Server');
end;

procedure TAtlasEditorCommandsTests.ShrinksBackToCursor;
var
  mNext: TLspRange;
begin
  Assert.IsTrue(TAtlasSelectionSteps.Shrink(Chain, TLspRange.Create(0, 0, 9, 0), mNext));
  Assert.IsTrue(mNext.Same(TLspRange.Create(3, 2, 3, 20)));
  Assert.IsTrue(TAtlasSelectionSteps.Shrink(Chain, mNext, mNext));
  Assert.IsTrue(mNext.Same(TLspRange.Create(3, 2, 3, 7)));
  Assert.IsTrue(TAtlasSelectionSteps.Shrink(Chain, mNext, mNext));
  Assert.IsTrue(mNext.Same(TLspRange.Create(3, 2, 3, 2)), 'zuletzt leer am Anfang');
  Assert.IsFalse(TAtlasSelectionSteps.Shrink(Chain, mNext, mNext), 'leere Auswahl bleibt');
end;

procedure TAtlasEditorCommandsTests.FetchesChainAtAnchor;
var
  mPosition: TLspTextPosition;
begin
  mPosition := TAtlasSelectionSteps.ChainPosition(TLspRange.Create(3, 2, 3, 20), True, TLspTextPosition.Create(3, 4));
  Assert.AreEqual(4, mPosition.Character, 'Anker in der Auswahl');
  mPosition := TAtlasSelectionSteps.ChainPosition(TLspRange.Create(5, 1, 5, 8), True, TLspTextPosition.Create(3, 4));
  Assert.AreEqual(5, mPosition.Line, 'Anker außerhalb: Anfang der Auswahl');
  Assert.AreEqual(1, mPosition.Character);
  mPosition := TAtlasSelectionSteps.ChainPosition(TLspRange.Create(5, 1, 5, 8), False, TLspTextPosition.Create(5, 4));
  Assert.AreEqual(1, mPosition.Character, 'ohne Anker');
end;

procedure TAtlasEditorCommandsTests.DetectsSlashCommandAfterEnter;
begin
  Assert.AreEqual(Ord(TAtlasSlashKind.Command), Ord(TAtlasSlashTrigger.Detect('  /uses Unit2', '  ')));
  Assert.AreEqual(Ord(TAtlasSlashKind.Command), Ord(TAtlasSlashTrigger.Detect('/try', '')));
  Assert.AreEqual(Ord(TAtlasSlashKind.None), Ord(TAtlasSlashTrigger.Detect('  // Kommentar', '  ')), 'Kommentar');
  Assert.AreEqual(Ord(TAtlasSlashKind.None), Ord(TAtlasSlashTrigger.Detect('  /uses Unit2', '  x')),
    'schon weitergetippt');
  Assert.AreEqual(Ord(TAtlasSlashKind.None), Ord(TAtlasSlashTrigger.Detect('  A := B / C;', '')), 'Division');
  Assert.AreEqual(Ord(TAtlasSlashKind.None), Ord(TAtlasSlashTrigger.Detect('/', '')));
  Assert.AreEqual(#10, TAtlasSlashTrigger.TriggerChar(TAtlasSlashKind.Command));
end;

procedure TAtlasEditorCommandsTests.DocCommentPlaceholdersInDescriptions;
const
  cText = '  /// <summary></summary>'#13#10'  /// <param name="A"></param>'#13#10'  /// <returns></returns>'#13#10;
var
  mExpansion: TAtlasSnippetExpansion;
begin
  mExpansion := TAtlasSlashTrigger.DocCommentExpansion(cText);
  Assert.AreEqual(cText, mExpansion.Text);
  Assert.IsTrue(mExpansion.HasPlaceholders);
  Assert.AreEqual(4, Integer(Length(mExpansion.Stops)));
  Assert.AreEqual(1, mExpansion.Stops[0].Number);
  Assert.AreEqual(Length('  /// <summary>'), mExpansion.Stops[0].Start);
  Assert.AreEqual(0, mExpansion.Stops[0].Length);
  Assert.AreEqual(2, mExpansion.Stops[1].Number);
  Assert.AreEqual(Pos('"></param>', cText) + 1, mExpansion.Stops[1].Start);
  Assert.AreEqual(3, mExpansion.Stops[2].Number);
  // Ende ohne den abschließenden Zeilenumbruch.
  Assert.AreEqual(0, mExpansion.Stops[3].Number);
  Assert.AreEqual(Length(cText) - 2, mExpansion.Stops[3].Start);
  // Ohne leere Beschreibung keine Platzhalter.
  Assert.IsFalse(TAtlasSlashTrigger.DocCommentExpansion('/// <summary>X</summary>').HasPlaceholders);
end;

procedure TAtlasEditorCommandsTests.DetectsDocCommentScaffold;
begin
  Assert.AreEqual(Ord(TAtlasSlashKind.DocComment), Ord(TAtlasSlashTrigger.Detect('', '    ///')));
  Assert.AreEqual(Ord(TAtlasSlashKind.None), Ord(TAtlasSlashTrigger.Detect('', '    ////')));
  Assert.AreEqual(Ord(TAtlasSlashKind.None), Ord(TAtlasSlashTrigger.Detect('', '  x := 1; ///')), 'hinter Code');
  Assert.AreEqual('/', TAtlasSlashTrigger.TriggerChar(TAtlasSlashKind.DocComment));
  Assert.AreEqual(TAtlasSlashTrigger.Key('c:\p\a.pas', 3, TAtlasSlashKind.Command, ' /try'),
    TAtlasSlashTrigger.Key('C:\P\A.pas', 3, TAtlasSlashKind.Command, '/try '));
  Assert.AreNotEqual(TAtlasSlashTrigger.Key('a.pas', 3, TAtlasSlashKind.Command, '/try'),
    TAtlasSlashTrigger.Key('a.pas', 4, TAtlasSlashKind.Command, '/try'));
end;

procedure TAtlasEditorCommandsTests.SlashAnswerOnlyForUnchangedText;
begin
  Assert.IsTrue(TAtlasSlashTrigger.StillValid('C:\P\A.pas', '/try'#13#10, 'c:\p\a.pas', '/try'#13#10));
  Assert.IsFalse(TAtlasSlashTrigger.StillValid('A.pas', '/try'#13#10, 'A.pas', '/try'#13#10'x'), 'weitergetippt');
  Assert.IsFalse(TAtlasSlashTrigger.StillValid('A.pas', '/try'#13#10, 'B.pas', '/try'#13#10), 'andere Datei');
end;

procedure TAtlasEditorCommandsTests.SearchFindsNextAndPreviousWithWrap;
var
  mLines: TArray<string>;
  mFound: TLspRange;
begin
  mLines := ['Foo := Bar;', 'if foo then', '  Baz(Foo);'];
  // Markierung „Foo“ in Zeile 0, Zeichen 0..3: weiter ab dem Ende.
  Assert.IsTrue(TAtlasSelectionSearch.Find(mLines, 'Foo', TLspTextPosition.Create(0, 3), False, mFound));
  Assert.IsTrue(mFound.Same(TLspRange.Create(1, 3, 1, 6)), 'ohne Groß-/Kleinschreibung');
  Assert.IsTrue(TAtlasSelectionSearch.Find(mLines, 'Foo', TLspTextPosition.Create(2, 9), False, mFound));
  Assert.IsTrue(mFound.Same(TLspRange.Create(0, 0, 0, 3)), 'am Ende von vorn');
  // Rückwärts: endet vor dem Anfang der Markierung.
  Assert.IsTrue(TAtlasSelectionSearch.Find(mLines, 'Foo', TLspTextPosition.Create(2, 6), True, mFound));
  Assert.IsTrue(mFound.Same(TLspRange.Create(1, 3, 1, 6)));
  Assert.IsTrue(TAtlasSelectionSearch.Find(mLines, 'Foo', TLspTextPosition.Create(0, 0), True, mFound));
  Assert.IsTrue(mFound.Same(TLspRange.Create(2, 6, 2, 9)), 'am Anfang von hinten');
  Assert.IsTrue(TAtlasSelectionSearch.Find(mLines, 'Bar', TLspTextPosition.Create(0, 10), False, mFound));
  Assert.IsTrue(mFound.Same(TLspRange.Create(0, 7, 0, 10)), 'einziges Vorkommen: wieder dasselbe');
  Assert.IsFalse(TAtlasSelectionSearch.Find(mLines, 'Nichts', TLspTextPosition.Create(0, 0), False, mFound));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorCommandsTests);

end.
