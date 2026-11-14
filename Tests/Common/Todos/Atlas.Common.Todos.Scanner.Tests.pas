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
  cSample =
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
  mEntries: TArray<TTodoEntry>;
begin
  mEntries := TTodoScanner.ForText(cSample);
  Assert.AreEqual(4, Integer(Length(mEntries)));
  // // TODO ohne Optionen
  Assert.AreEqual('TODO', mEntries[0].Keyword);
  Assert.IsFalse(mEntries[0].Done);
  Assert.AreEqual(0, mEntries[0].Priority);
  Assert.AreEqual('', mEntries[0].Owner);
  Assert.AreEqual('Rundung prüfen', mEntries[0].Text);
  Assert.AreEqual(3, mEntries[0].Range.StartPos.Line);
  Assert.AreEqual(0, mEntries[0].Range.StartPos.Character);
  // // FIXME mit Doppelpunkt
  Assert.AreEqual('FIXME', mEntries[1].Keyword);
  Assert.AreEqual('Rabatt wird doppelt abgezogen', mEntries[1].Text);
  Assert.AreEqual(6, mEntries[1].Range.StartPos.Line);
  Assert.AreEqual(2, mEntries[1].Range.StartPos.Character);
  // Format der IDE-To-Do-Liste
  Assert.AreEqual('TODO', mEntries[2].Keyword);
  Assert.AreEqual(2, mEntries[2].Priority);
  Assert.AreEqual('Marco', mEntries[2].Owner);
  Assert.AreEqual('GUI', mEntries[2].Category);
  Assert.AreEqual('Fokus auf das Feld setzen', mEntries[2].Text);
  Assert.AreEqual(7, mEntries[2].Range.StartPos.Line);
end;

procedure TTodoScannerTests.DoneIsCompleted;
var
  mEntries: TArray<TTodoEntry>;
begin
  mEntries := TTodoScanner.ForText(cSample);
  Assert.AreEqual('DONE', mEntries[3].Keyword);
  Assert.IsTrue(mEntries[3].Done);
  Assert.AreEqual(1, mEntries[3].Priority);
  Assert.AreEqual('Anna', mEntries[3].Owner);
  Assert.AreEqual('Daten', mEntries[3].Category);
  Assert.AreEqual('Index angelegt', mEntries[3].Text);
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
  mEntry: TTodoEntry;
begin
  Assert.IsTrue(TTodoScanner.ParseBody(' TODO 3 -oMarco Bähring -cOberfläche : Text ', TTodos.DefaultKeywords,
    mEntry));
  Assert.AreEqual(3, mEntry.Priority);
  Assert.AreEqual('Marco Bähring', mEntry.Owner);
  Assert.AreEqual('Oberfläche', mEntry.Category);
  Assert.AreEqual('Text', mEntry.Text);
  Assert.IsTrue(TTodoScanner.ParseBody('TODO -c''Daten bank'' -o"A B": x', TTodos.DefaultKeywords, mEntry));
  Assert.AreEqual(0, mEntry.Priority);
  Assert.AreEqual('Daten bank', mEntry.Category);
  Assert.AreEqual('A B', mEntry.Owner);
  Assert.AreEqual('x', mEntry.Text);
  // Zeilenkommentar im IDE-Format (#474)
  Assert.IsTrue(TTodoScanner.ParseBody(' TODO 1 -oMarco -cGUI : Fokus', TTodos.DefaultKeywords, mEntry));
  Assert.AreEqual('Marco', mEntry.Owner);
  Assert.AreEqual('GUI', mEntry.Category);
  // Ohne Text
  Assert.IsTrue(TTodoScanner.ParseBody('TODO', TTodos.DefaultKeywords, mEntry));
  Assert.AreEqual('', mEntry.Text);
  // Ein Bindestrich ohne o/c ist Text.
  Assert.IsTrue(TTodoScanner.ParseBody('TODO - später', TTodos.DefaultKeywords, mEntry));
  Assert.AreEqual('- später', mEntry.Text);
  Assert.IsFalse(TTodoScanner.ParseBody('', TTodos.DefaultKeywords, mEntry));
  Assert.IsFalse(TTodoScanner.ParseBody('  : TODO', TTodos.DefaultKeywords, mEntry));
end;

procedure TTodoScannerTests.BlockCommentsOverLines;
var
  mEntries: TArray<TTodoEntry>;
begin
  mEntries := TTodoScanner.ForText('(* TODO -oMarco : erste Zeile'#13#10'   zweite Zeile *)'#13#10'unit A;');
  Assert.AreEqual(1, Integer(Length(mEntries)));
  Assert.AreEqual('erste Zeile zweite Zeile', mEntries[0].Text);
  Assert.AreEqual(0, mEntries[0].Range.StartPos.Line);
  Assert.AreEqual(1, mEntries[0].Range.EndPos.Line);
end;

procedure TTodoScannerTests.OwnKeywords;
var
  mEntries: TArray<TTodoEntry>;
begin
  mEntries := TTodoScanner.ForText('// HACK: Umweg'#10'// TODO bleibt'#10'// FIXME fällt weg'#10'{ DONE immer }',
    ['HACK', 'TODO']);
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual('HACK', mEntries[0].Keyword);
  Assert.AreEqual('TODO', mEntries[1].Keyword);
  Assert.IsTrue(mEntries[2].Done);
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
  mFiles: TArray<TFileTodos>;
  mRead: TArray<string>;
begin
  mRead := nil;
  // Fremd.pas liegt im selben Ordner, gehört aber nicht zum Projekt und wird nicht übergeben.
  mFiles := TTodoScanner.Collect(['C:\P\Kasse.pas', 'C:\P\kasse.PAS', 'C:\P\Ohne.pas', 'C:\P\Kasse.dfm',
    'C:\P\Fehlt.pas', 'C:\P\Src\Lager.pas'], 'C:\P',
    function(const AFileName: string; out AText: string): Boolean
    begin
      mRead := mRead + [AFileName];
      Result := not AFileName.EndsWith('Fehlt.pas');
      if AFileName.EndsWith('Lager.pas') then
      begin
        AText := 'unit Lager;'#10'// FIXME Lager';
      end
      else if AFileName.EndsWith('Ohne.pas') then
      begin
        AText := 'unit Ohne;'#10'// nichts zu tun';
      end
      else
      begin
        AText := cSample;
      end;
    end, TTodos.DefaultKeywords);
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('Kasse.pas', mFiles[0].Path);
  Assert.AreEqual('Kasse', mFiles[0].UnitName);
  Assert.AreEqual(4, Integer(Length(mFiles[0].Entries)));
  Assert.AreEqual('Src/Lager.pas', mFiles[1].Path);
  Assert.AreEqual('Lager', mFiles[1].UnitName);
  // Doppelte und die .dfm werden nicht gelesen.
  Assert.AreEqual(4, Integer(Length(mRead)));
end;

procedure TTodoScannerTests.FilterKeepsMatchingEntries;
var
  mFiles, mKept: TArray<TFileTodos>;
  mFilter: TTodoFilter;
begin
  mFiles := [TFileTodos.Create('Kasse.pas', TTodoScanner.ForText(cSample)),
    TFileTodos.Create('Src/Lager.pas', TTodoScanner.ForText('// FIXME Lager'))];
  mKept := TTodoScanner.Filter(mFiles, TTodoFilter.Default);
  Assert.AreEqual(2, Integer(Length(mKept)));
  Assert.AreEqual(3, Integer(Length(mKept[0].Entries)), 'DONE ist ausgeblendet');
  Assert.AreEqual(4, Integer(Length(TTodoScanner.Filter(mFiles, TTodoFilter.All)[0].Entries)));
  mFilter := TTodoFilter.Default;
  mFilter.Category := 'gui';
  mKept := TTodoScanner.Filter(mFiles, mFilter);
  Assert.AreEqual(1, Integer(Length(mKept)));
  Assert.AreEqual('Fokus auf das Feld setzen', mKept[0].Entries[0].Text);
  mFilter := TTodoFilter.Default;
  mFilter.Owner := 'Anna';
  Assert.AreEqual(0, Integer(Length(TTodoScanner.Filter(mFiles, mFilter))), 'Annas Eintrag ist erledigt');
  mFilter.IncludeDone := True;
  Assert.AreEqual(1, Integer(Length(TTodoScanner.Filter(mFiles, mFilter))));
  mFilter := TTodoFilter.Default;
  mFilter.UnitName := 'lager';
  mKept := TTodoScanner.Filter(mFiles, mFilter);
  Assert.AreEqual(1, Integer(Length(mKept)));
  Assert.AreEqual('Src/Lager.pas', mKept[0].Path);
  mFilter.UnitName := 'Src\Lager.pas';
  Assert.AreEqual(1, Integer(Length(TTodoScanner.Filter(mFiles, mFilter))));
  mFilter := TTodoFilter.Default;
  mFilter.Keyword := 'fixme';
  mKept := TTodoScanner.Filter(mFiles, mFilter);
  Assert.AreEqual(2, Integer(Length(mKept)));
  Assert.AreEqual(1, Integer(Length(mKept[0].Entries)));
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
