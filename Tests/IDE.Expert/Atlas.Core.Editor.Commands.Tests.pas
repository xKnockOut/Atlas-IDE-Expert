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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.Selection,
  Atlas.Core.Editor.SlashTrigger;

function Chain: TArray<TLspRange>;
begin
  // Bezeichner, Anweisung, Datei.
  Result := [TLspRange.Create(3, 2, 3, 7), TLspRange.Create(3, 2, 3, 20), TLspRange.Create(0, 0, 9, 0)];
end;

procedure TAtlasEditorCommandsTests.ExpandsStepByStep;
var
  Next: TLspRange;
begin
  Assert.IsTrue(TAtlasSelectionSteps.Expand(Chain, TLspRange.Create(3, 4, 3, 4), Next));
  Assert.IsTrue(Next.Same(TLspRange.Create(3, 2, 3, 7)), 'erst der Bezeichner');
  Assert.IsTrue(TAtlasSelectionSteps.Expand(Chain, Next, Next));
  Assert.IsTrue(Next.Same(TLspRange.Create(3, 2, 3, 20)), 'dann die Anweisung');
  // Eine selbst gezogene Auswahl springt zum nächsten Bereich, der sie ganz enthält.
  Assert.IsTrue(TAtlasSelectionSteps.Expand(Chain, TLspRange.Create(3, 5, 3, 12), Next));
  Assert.IsTrue(Next.Same(TLspRange.Create(3, 2, 3, 20)));
  Assert.IsFalse(TAtlasSelectionSteps.Expand(Chain, TLspRange.Create(0, 0, 9, 0), Next), 'ganze Datei');
  Assert.IsFalse(TAtlasSelectionSteps.Expand(nil, TLspRange.Create(3, 4, 3, 4), Next), 'ohne Server');
end;

procedure TAtlasEditorCommandsTests.ShrinksBackToCursor;
var
  Next: TLspRange;
begin
  Assert.IsTrue(TAtlasSelectionSteps.Shrink(Chain, TLspRange.Create(0, 0, 9, 0), Next));
  Assert.IsTrue(Next.Same(TLspRange.Create(3, 2, 3, 20)));
  Assert.IsTrue(TAtlasSelectionSteps.Shrink(Chain, Next, Next));
  Assert.IsTrue(Next.Same(TLspRange.Create(3, 2, 3, 7)));
  Assert.IsTrue(TAtlasSelectionSteps.Shrink(Chain, Next, Next));
  Assert.IsTrue(Next.Same(TLspRange.Create(3, 2, 3, 2)), 'zuletzt leer am Anfang');
  Assert.IsFalse(TAtlasSelectionSteps.Shrink(Chain, Next, Next), 'leere Auswahl bleibt');
end;

procedure TAtlasEditorCommandsTests.FetchesChainAtAnchor;
var
  Position: TLspTextPosition;
begin
  Position := TAtlasSelectionSteps.ChainPosition(TLspRange.Create(3, 2, 3, 20), True, TLspTextPosition.Create(3, 4));
  Assert.AreEqual(4, Position.Character, 'Anker in der Auswahl');
  Position := TAtlasSelectionSteps.ChainPosition(TLspRange.Create(5, 1, 5, 8), True, TLspTextPosition.Create(3, 4));
  Assert.AreEqual(5, Position.Line, 'Anker außerhalb: Anfang der Auswahl');
  Assert.AreEqual(1, Position.Character);
  Position := TAtlasSelectionSteps.ChainPosition(TLspRange.Create(5, 1, 5, 8), False, TLspTextPosition.Create(5, 4));
  Assert.AreEqual(1, Position.Character, 'ohne Anker');
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

procedure TAtlasEditorCommandsTests.SearchFindsNextAndPreviousWithWrap;
var
  Lines: TArray<string>;
  Found: TLspRange;
begin
  Lines := ['Foo := Bar;', 'if foo then', '  Baz(Foo);'];
  // Markierung „Foo“ in Zeile 0, Zeichen 0..3: weiter ab dem Ende.
  Assert.IsTrue(TAtlasSelectionSearch.Find(Lines, 'Foo', TLspTextPosition.Create(0, 3), False, Found));
  Assert.IsTrue(Found.Same(TLspRange.Create(1, 3, 1, 6)), 'ohne Groß-/Kleinschreibung');
  Assert.IsTrue(TAtlasSelectionSearch.Find(Lines, 'Foo', TLspTextPosition.Create(2, 9), False, Found));
  Assert.IsTrue(Found.Same(TLspRange.Create(0, 0, 0, 3)), 'am Ende von vorn');
  // Rückwärts: endet vor dem Anfang der Markierung.
  Assert.IsTrue(TAtlasSelectionSearch.Find(Lines, 'Foo', TLspTextPosition.Create(2, 6), True, Found));
  Assert.IsTrue(Found.Same(TLspRange.Create(1, 3, 1, 6)));
  Assert.IsTrue(TAtlasSelectionSearch.Find(Lines, 'Foo', TLspTextPosition.Create(0, 0), True, Found));
  Assert.IsTrue(Found.Same(TLspRange.Create(2, 6, 2, 9)), 'am Anfang von hinten');
  Assert.IsTrue(TAtlasSelectionSearch.Find(Lines, 'Bar', TLspTextPosition.Create(0, 10), False, Found));
  Assert.IsTrue(Found.Same(TLspRange.Create(0, 7, 0, 10)), 'einziges Vorkommen: wieder dasselbe');
  Assert.IsFalse(TAtlasSelectionSearch.Find(Lines, 'Nichts', TLspTextPosition.Create(0, 0), False, Found));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorCommandsTests);

end.
