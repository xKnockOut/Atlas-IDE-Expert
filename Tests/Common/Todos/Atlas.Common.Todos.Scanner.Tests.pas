unit Atlas.Common.Todos.Scanner.Tests;

// Tests der TODO-Erkennung (#68): die drei Formate mit Person, Kategorie und
// Priorität, DONE als erledigt, keine Treffer in Strings und gewöhnlichen
// Kommentaren, eigene Marken, Sammeln über die Dateien eines Projekts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTodoScannerTests = class
  public
    [Test]
    procedure RecognizesAllThreeFormats;
    [Test]
    procedure DoneIsCompleted;
    [Test]
    procedure IgnoresStringsAndOrdinaryComments;
    [Test]
    procedure ParsesOptionsWithSpacesAndQuotes;
    [Test]
    procedure BlockCommentsOverLines;
    [Test]
    procedure OwnKeywords;
    [Test]
    procedure CommentBodyStripsDelimiters;
    [Test]
    procedure CollectsOnlyGivenProjectFiles;
    [Test]
    procedure FilterKeepsMatchingEntries;
    [Test]
    procedure UnitNameOfPath;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Todos.Scanner;

const
  /// <summary>Testdatei mit allen drei Formaten und einem erledigten Eintrag.</summary>
  Sample =
    'unit Kasse;'#10 +
    'interface'#10 +
    'implementation'#10 +
    '// TODO Rundung prüfen'#10 +
    'procedure Buchen;'#10 +
    'begin'#10 +
    '  // FIXME: Rabatt wird doppelt abgezogen'#10 +
    '  { TODO 2 -oMarco -cGUI : Fokus auf das Feld setzen }'#10 +
    '  { DONE 1 -oAnna -cDaten : Index angelegt }'#10 +
    'end;'#10 +
    'end.';

{ TTodoScannerTests }

procedure TTodoScannerTests.RecognizesAllThreeFormats;
var
  Entries: TArray<TTodoEntry>;
begin
  Entries := TTodoScanner.ForText(Sample);
  Assert.AreEqual(4, Integer(Length(Entries)));
  // // TODO ohne Optionen
  Assert.AreEqual('TODO', Entries[0].Keyword);
  Assert.IsFalse(Entries[0].Done);
  Assert.AreEqual(0, Entries[0].Priority);
  Assert.AreEqual('', Entries[0].Owner);
  Assert.AreEqual('Rundung prüfen', Entries[0].Text);
  Assert.AreEqual(3, Entries[0].Range.StartPos.Line);
  Assert.AreEqual(0, Entries[0].Range.StartPos.Character);
  // // FIXME mit Doppelpunkt
  Assert.AreEqual('FIXME', Entries[1].Keyword);
  Assert.AreEqual('Rabatt wird doppelt abgezogen', Entries[1].Text);
  Assert.AreEqual(6, Entries[1].Range.StartPos.Line);
  Assert.AreEqual(2, Entries[1].Range.StartPos.Character);
  // Format der IDE-To-Do-Liste
  Assert.AreEqual('TODO', Entries[2].Keyword);
  Assert.AreEqual(2, Entries[2].Priority);
  Assert.AreEqual('Marco', Entries[2].Owner);
  Assert.AreEqual('GUI', Entries[2].Category);
  Assert.AreEqual('Fokus auf das Feld setzen', Entries[2].Text);
  Assert.AreEqual(7, Entries[2].Range.StartPos.Line);
end;

procedure TTodoScannerTests.DoneIsCompleted;
var
  Entries: TArray<TTodoEntry>;
begin
  Entries := TTodoScanner.ForText(Sample);
  Assert.AreEqual('DONE', Entries[3].Keyword);
  Assert.IsTrue(Entries[3].Done);
  Assert.AreEqual(1, Entries[3].Priority);
  Assert.AreEqual('Anna', Entries[3].Owner);
  Assert.AreEqual('Daten', Entries[3].Category);
  Assert.AreEqual('Index angelegt', Entries[3].Text);
end;

procedure TTodoScannerTests.IgnoresStringsAndOrdinaryComments;
begin
  Assert.AreEqual(0, Integer(Length(TTodoScanner.ForText(
    'unit A;'#10 +
    'const S = ''// TODO im String'';'#10 +
    '// Die TODO-Liste der IDE'#10 +
    '// TODO-Liste aufräumen'#10 +
    '// TODOs sammeln'#10 +
    '// Hinweis: TODO steht nicht am Anfang'#10 +
    '{$IFDEF TODO}'#10 +
    '{$ENDIF}'#10 +
    'end.'))));
  // Groß-/Kleinschreibung egal, Doppelpunkt direkt nach der Marke, Kommentarende direkt nach der Marke.
  Assert.AreEqual(3, Integer(Length(TTodoScanner.ForText('// todo: klein'#10'{TODO:x}'#10'(* FIXME *)'))));
end;

procedure TTodoScannerTests.ParsesOptionsWithSpacesAndQuotes;
var
  Entry: TTodoEntry;
begin
  Assert.IsTrue(TTodoScanner.ParseBody(' TODO 3 -oMarco Bähring -cOberfläche : Text ', TTodos.DefaultKeywords,
    Entry));
  Assert.AreEqual(3, Entry.Priority);
  Assert.AreEqual('Marco Bähring', Entry.Owner);
  Assert.AreEqual('Oberfläche', Entry.Category);
  Assert.AreEqual('Text', Entry.Text);
  Assert.IsTrue(TTodoScanner.ParseBody('TODO -c''Daten bank'' -o"A B": x', TTodos.DefaultKeywords, Entry));
  Assert.AreEqual(0, Entry.Priority);
  Assert.AreEqual('Daten bank', Entry.Category);
  Assert.AreEqual('A B', Entry.Owner);
  Assert.AreEqual('x', Entry.Text);
  // Zeilenkommentar im IDE-Format (#474)
  Assert.IsTrue(TTodoScanner.ParseBody(' TODO 1 -oMarco -cGUI : Fokus', TTodos.DefaultKeywords, Entry));
  Assert.AreEqual('Marco', Entry.Owner);
  Assert.AreEqual('GUI', Entry.Category);
  // Ohne Text
  Assert.IsTrue(TTodoScanner.ParseBody('TODO', TTodos.DefaultKeywords, Entry));
  Assert.AreEqual('', Entry.Text);
  // Ein Bindestrich ohne o/c ist Text.
  Assert.IsTrue(TTodoScanner.ParseBody('TODO - später', TTodos.DefaultKeywords, Entry));
  Assert.AreEqual('- später', Entry.Text);
  Assert.IsFalse(TTodoScanner.ParseBody('', TTodos.DefaultKeywords, Entry));
  Assert.IsFalse(TTodoScanner.ParseBody('  : TODO', TTodos.DefaultKeywords, Entry));
end;

procedure TTodoScannerTests.BlockCommentsOverLines;
var
  Entries: TArray<TTodoEntry>;
begin
  Entries := TTodoScanner.ForText('(* TODO -oMarco : erste Zeile'#13#10'   zweite Zeile *)'#13#10'unit A;');
  Assert.AreEqual(1, Integer(Length(Entries)));
  Assert.AreEqual('erste Zeile zweite Zeile', Entries[0].Text);
  Assert.AreEqual(0, Entries[0].Range.StartPos.Line);
  Assert.AreEqual(1, Entries[0].Range.EndPos.Line);
end;

procedure TTodoScannerTests.OwnKeywords;
var
  Entries: TArray<TTodoEntry>;
begin
  Entries := TTodoScanner.ForText('// HACK: Umweg'#10'// TODO bleibt'#10'// FIXME fällt weg'#10'{ DONE immer }',
    ['HACK', 'TODO']);
  Assert.AreEqual(3, Integer(Length(Entries)));
  Assert.AreEqual('HACK', Entries[0].Keyword);
  Assert.AreEqual('TODO', Entries[1].Keyword);
  Assert.IsTrue(Entries[2].Done);
end;

procedure TTodoScannerTests.CommentBodyStripsDelimiters;
begin
  Assert.AreEqual(' TODO x', TTodoScanner.CommentBody('// TODO x'));
  Assert.AreEqual(' TODO x', TTodoScanner.CommentBody('/// TODO x'));
  Assert.AreEqual(' TODO x ', TTodoScanner.CommentBody('{ TODO x }'));
  Assert.AreEqual(' TODO x ', TTodoScanner.CommentBody('(* TODO x *)'));
  // Ohne Abschluss (unvollständiger Code) bleibt der Rest.
  Assert.AreEqual(' TODO x', TTodoScanner.CommentBody('{ TODO x'));
end;

procedure TTodoScannerTests.CollectsOnlyGivenProjectFiles;
var
  Files: TArray<TFileTodos>;
  Read: TArray<string>;
begin
  Read := nil;
  // Fremd.pas liegt im selben Ordner, gehört aber nicht zum Projekt und wird nicht übergeben.
  Files := TTodoScanner.Collect(['C:\P\Kasse.pas', 'C:\P\kasse.PAS', 'C:\P\Ohne.pas', 'C:\P\Kasse.dfm',
    'C:\P\Fehlt.pas', 'C:\P\Src\Lager.pas'], 'C:\P',
    function(const AFileName: string; out AText: string): Boolean
    begin
      Read := Read + [AFileName];
      Result := not AFileName.EndsWith('Fehlt.pas');
      if AFileName.EndsWith('Lager.pas') then
        AText := 'unit Lager;'#10'// FIXME Lager'
      else if AFileName.EndsWith('Ohne.pas') then
        AText := 'unit Ohne;'#10'// nichts zu tun'
      else
        AText := Sample;
    end, TTodos.DefaultKeywords);
  Assert.AreEqual(2, Integer(Length(Files)));
  Assert.AreEqual('Kasse.pas', Files[0].Path);
  Assert.AreEqual('Kasse', Files[0].UnitName);
  Assert.AreEqual(4, Integer(Length(Files[0].Entries)));
  Assert.AreEqual('Src/Lager.pas', Files[1].Path);
  Assert.AreEqual('Lager', Files[1].UnitName);
  // Doppelte und die .dfm werden nicht gelesen.
  Assert.AreEqual(4, Integer(Length(Read)));
end;

procedure TTodoScannerTests.FilterKeepsMatchingEntries;
var
  Files, Kept: TArray<TFileTodos>;
  Filter: TTodoFilter;
begin
  Files := [TFileTodos.Create('Kasse.pas', TTodoScanner.ForText(Sample)),
    TFileTodos.Create('Src/Lager.pas', TTodoScanner.ForText('// FIXME Lager'))];
  Kept := TTodoScanner.Filter(Files, TTodoFilter.Default);
  Assert.AreEqual(2, Integer(Length(Kept)));
  Assert.AreEqual(3, Integer(Length(Kept[0].Entries)), 'DONE ist ausgeblendet');
  Assert.AreEqual(4, Integer(Length(TTodoScanner.Filter(Files, TTodoFilter.All)[0].Entries)));
  Filter := TTodoFilter.Default;
  Filter.Category := 'gui';
  Kept := TTodoScanner.Filter(Files, Filter);
  Assert.AreEqual(1, Integer(Length(Kept)));
  Assert.AreEqual('Fokus auf das Feld setzen', Kept[0].Entries[0].Text);
  Filter := TTodoFilter.Default;
  Filter.Owner := 'Anna';
  Assert.AreEqual(0, Integer(Length(TTodoScanner.Filter(Files, Filter))), 'Annas Eintrag ist erledigt');
  Filter.IncludeDone := True;
  Assert.AreEqual(1, Integer(Length(TTodoScanner.Filter(Files, Filter))));
  Filter := TTodoFilter.Default;
  Filter.UnitName := 'lager';
  Kept := TTodoScanner.Filter(Files, Filter);
  Assert.AreEqual(1, Integer(Length(Kept)));
  Assert.AreEqual('Src/Lager.pas', Kept[0].Path);
  Filter.UnitName := 'Src\Lager.pas';
  Assert.AreEqual(1, Integer(Length(TTodoScanner.Filter(Files, Filter))));
  Filter := TTodoFilter.Default;
  Filter.Keyword := 'fixme';
  Kept := TTodoScanner.Filter(Files, Filter);
  Assert.AreEqual(2, Integer(Length(Kept)));
  Assert.AreEqual(1, Integer(Length(Kept[0].Entries)));
end;

procedure TTodoScannerTests.UnitNameOfPath;
begin
  Assert.AreEqual('Kasse', TTodos.UnitNameOf('Kasse.pas'));
  Assert.AreEqual('Atlas.Common.Todos.Contract', TTodos.UnitNameOf('Source/Atlas.Common.Todos.Contract.pas'));
  Assert.AreEqual('App', TTodos.UnitNameOf('C:\P\App.dpr'));
  Assert.AreEqual('Ohne', TTodos.UnitNameOf('Ohne'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTodoScannerTests);

end.
