unit Atlas.Core.Projects.Baseline.Tests;

// Tests der Baseline im Plugin (#97): Datei im Projektordner (neuer und
// früherer Name), Einträge ohne Datei vor dem Aktualisieren, Argumente und
// Antwort von atlas.updateBaseline und der Abschnitt "baseline" der
// Projekt-Zusammenfassung (#758, #759).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectBaselinesTests = class
  public
    [Test]
    procedure FileInPrefersNewName;
    [Test]
    procedure StateWithoutFile;
    [Test]
    procedure StateCountsEntriesAndHits;
    /// <summary>Abnahme: Einträge ohne Datei mit Pfaden, bevor das Aktualisieren sie entfernt.</summary>
    [Test]
    procedure StateListsOrphansOncePerPath;
    [Test]
    procedure StateOfInvalidFile;
    [Test]
    procedure ArgumentsAreProjectUri;
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure RejectsInvalidAnswer;
    [Test]
    procedure SectionAfterBuildKeepsLastUpdate;
    [Test]
    procedure SectionAfterUpdate;
    /// <summary>Baseline nicht im Projektordner geschrieben (#758): Das Plugin erkennt es an der Antwort.</summary>
    [Test]
    procedure WrittenElsewhereComparesFolders;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Baseline;

const
  Folder = 'C:\Projekte\Kasse';
  Baseline =
    '{"version": 1, "findings": [' +
    '{"path": "Source/Main.pas", "rule": "a", "fingerprint": "1", "count": 2, "routine": "TMain.Run"},' +
    '{"path": "Alt/Weg.pas", "rule": "a", "fingerprint": "2", "count": 3},' +
    '{"path": "Source/Main.pas", "rule": "b", "fingerprint": "3"},' +
    '{"path": "alt/weg.pas", "rule": "b", "fingerprint": "4", "count": 1},' +
    '{"path": "Weg2.pas", "rule": "c", "fingerprint": "5", "count": 4}]}';

var
  /// <summary>Vorhandene Dateien der unechten Platte (Groß-/Kleinschreibung egal) und Zahl der Abfragen.</summary>
  Disk: TDictionary<string, string>;
  Asked: Integer;

procedure Reset(const AFiles: array of string);
var
  Name: string;
begin
  Disk.Clear;
  Asked := 0;
  for Name in AFiles do
    Disk.AddOrSetValue(UpperCase(Name), Baseline);
end;

function Exists(const AFileName: string): Boolean;
begin
  Inc(Asked);
  Result := Disk.ContainsKey(UpperCase(AFileName));
end;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := Disk.TryGetValue(UpperCase(AFileName), AText);
end;

{ TAtlasProjectBaselinesTests }

procedure TAtlasProjectBaselinesTests.FileInPrefersNewName;
begin
  Reset([Folder + '\atlas-baseline.json', Folder + '\delphi-lsp-baseline.json']);
  Assert.AreEqual(Folder + '\atlas-baseline.json', TAtlasProjectBaselines.FileIn(Folder, Exists));
  Reset([Folder + '\delphi-lsp-baseline.json']);
  Assert.AreEqual(Folder + '\delphi-lsp-baseline.json', TAtlasProjectBaselines.FileIn(Folder + '\', Exists));
  Reset([]);
  Assert.AreEqual('', TAtlasProjectBaselines.FileIn(Folder, Exists));
  Assert.AreEqual('', TAtlasProjectBaselines.FileIn('', Exists));
end;

procedure TAtlasProjectBaselinesTests.StateWithoutFile;
var
  State: TAtlasBaselineState;
begin
  Reset([]);
  State := TAtlasProjectBaselines.StateOf(Folder, Exists, ReadText);
  Assert.IsFalse(State.Exists);
  Assert.IsFalse(State.Valid);
  Assert.AreEqual('', State.FileName);
  Assert.AreEqual(0, State.Entries);
end;

procedure TAtlasProjectBaselinesTests.StateCountsEntriesAndHits;
var
  State: TAtlasBaselineState;
begin
  Reset([Folder + '\atlas-baseline.json', Folder + '\Source\Main.pas', Folder + '\Alt\Weg.pas',
    Folder + '\Weg2.pas']);
  State := TAtlasProjectBaselines.StateOf(Folder, Exists, ReadText);
  Assert.IsTrue(State.Exists);
  Assert.IsTrue(State.Valid);
  Assert.AreEqual(Folder + '\atlas-baseline.json', State.FileName);
  Assert.AreEqual(5, State.Entries);
  // Ohne "count" zählt ein Eintrag als ein Treffer.
  Assert.AreEqual(11, State.Hits);
  Assert.AreEqual(0, Integer(Length(State.Orphans)));
  Assert.AreEqual(0, State.OrphanCount);
end;

procedure TAtlasProjectBaselinesTests.StateListsOrphansOncePerPath;
var
  State: TAtlasBaselineState;
begin
  // Alt/Weg.pas wurde umbenannt, Weg2.pas gelöscht.
  Reset([Folder + '\atlas-baseline.json', Folder + '\Source\Main.pas']);
  State := TAtlasProjectBaselines.StateOf(Folder, Exists, ReadText);
  Assert.AreEqual(2, Integer(Length(State.Orphans)));
  Assert.AreEqual('Alt/Weg.pas', State.Orphans[0].Path);
  Assert.AreEqual(4, State.Orphans[0].Count, 'gleicher Pfad in anderer Schreibweise zählt mit');
  Assert.AreEqual('Weg2.pas', State.Orphans[1].Path);
  Assert.AreEqual(4, State.Orphans[1].Count);
  Assert.AreEqual(8, State.OrphanCount);
  // Je Pfad eine Abfrage (plus die nach der Baseline selbst).
  Assert.AreEqual(4, Asked);
end;

procedure TAtlasProjectBaselinesTests.StateOfInvalidFile;
var
  State: TAtlasBaselineState;
begin
  State := TAtlasProjectBaselines.StateOfText(Folder, '{"version": 1}', nil);
  Assert.IsTrue(State.Exists);
  Assert.IsFalse(State.Valid);
  State := TAtlasProjectBaselines.StateOfText(Folder, 'kein JSON', nil);
  Assert.IsTrue(State.Exists);
  Assert.IsFalse(State.Valid);
  // Ohne Prüffunktion keine Einträge ohne Datei.
  State := TAtlasProjectBaselines.StateOfText(Folder, Baseline, nil);
  Assert.IsTrue(State.Valid);
  Assert.AreEqual(0, State.OrphanCount);
end;

procedure TAtlasProjectBaselinesTests.ArgumentsAreProjectUri;
begin
  Assert.AreEqual('["file:///C:/Projekte/Kasse/Kasse.dproj"]',
    TAtlasProjectBaselines.Arguments('file:///C:/Projekte/Kasse/Kasse.dproj'));
  Assert.AreEqual('atlas.updateBaseline', TAtlasProjectBaselines.Command);
end;

procedure TAtlasProjectBaselinesTests.ParsesServerAnswer;
const
  Answer = '{"format": 1, "file": "C:\\Projekte\\Kasse\\atlas-baseline.json", "previous": "valid", ' +
    '"skipped": 1, "total": 120, "files": 40, "added": 3, "removed": 5, "unchanged": 117, "completed": 7, ' +
    '"orphaned": {"count": 3, "entries": [{"path": "Alt/U.pas", "count": 2}, {"path": "X.pas", "count": 1}]}}';
var
  Update: TAtlasBaselineUpdate;
begin
  Assert.IsTrue(TAtlasProjectBaselines.FromServer(Answer, Update));
  Assert.AreEqual('C:\Projekte\Kasse\atlas-baseline.json', Update.FileName);
  Assert.AreEqual('valid', Update.Previous);
  Assert.AreEqual(1, Update.Skipped);
  Assert.AreEqual(120, Update.Total);
  Assert.AreEqual(40, Update.Files);
  Assert.AreEqual(3, Update.Added);
  Assert.AreEqual(5, Update.Removed);
  Assert.AreEqual(117, Update.Unchanged);
  Assert.AreEqual(7, Update.Completed);
  Assert.AreEqual(3, Update.OrphanCount);
  Assert.AreEqual(2, Integer(Length(Update.Orphans)));
  Assert.AreEqual('Alt/U.pas', Update.Orphans[0].Path);
  Assert.AreEqual(2, Update.Orphans[0].Count);
  // Ohne "orphaned" (ältere Server-Fassung): keine Einträge ohne Datei.
  Assert.IsTrue(TAtlasProjectBaselines.FromServer('{"file": "C:\\B.json", "total": 0}', Update));
  Assert.AreEqual(0, Update.OrphanCount);
  Assert.AreEqual(0, Integer(Length(Update.Orphans)));
end;

procedure TAtlasProjectBaselinesTests.RejectsInvalidAnswer;
var
  Update: TAtlasBaselineUpdate;
begin
  // Leer: Fehler, Zeitlimit oder geschlossene Verbindung.
  Assert.IsFalse(TAtlasProjectBaselines.FromServer('', Update));
  Assert.IsFalse(TAtlasProjectBaselines.FromServer('null', Update));
  Assert.IsFalse(TAtlasProjectBaselines.FromServer('{"total": 3}', Update));
  Assert.IsFalse(TAtlasProjectBaselines.FromServer('{"file": "C:\\B.json"}', Update));
end;

procedure TAtlasProjectBaselinesTests.SectionAfterBuildKeepsLastUpdate;
var
  Section: TAtlasProjectBaseline;
  State: TAtlasBaselineState;
begin
  Section := TAtlasProjectBaseline.Empty;
  Section.Updated := 1;
  Section.Added := 3;
  Section.Removed := 5;
  Reset([Folder + '\atlas-baseline.json', Folder + '\Source\Main.pas']);
  State := TAtlasProjectBaselines.StateOf(Folder, Exists, ReadText);
  TAtlasProjectBaselines.Measured(Section, State, 2);
  Assert.IsTrue(Section.Known);
  Assert.IsTrue(Section.At = 2);
  Assert.IsTrue(Section.Exists);
  Assert.IsTrue(Section.Valid);
  Assert.AreEqual(5, Section.Entries);
  Assert.AreEqual(11, Section.Hits);
  Assert.AreEqual(8, Section.Orphaned);
  Assert.IsTrue(Section.Updated = 1, 'ein Build ändert das letzte Aktualisieren nicht');
  Assert.AreEqual(3, Section.Added);
  // Baseline gelöscht: bekannt, aber nicht vorhanden.
  Reset([]);
  TAtlasProjectBaselines.Measured(Section, TAtlasProjectBaselines.StateOf(Folder, Exists, ReadText), 3);
  Assert.IsTrue(Section.Known);
  Assert.IsFalse(Section.Exists);
  Assert.AreEqual(0, Section.Hits);
end;

procedure TAtlasProjectBaselinesTests.SectionAfterUpdate;
var
  Section: TAtlasProjectBaseline;
  Update: TAtlasBaselineUpdate;
  State: TAtlasBaselineState;
begin
  Section := TAtlasProjectBaseline.Empty;
  Update := Default(TAtlasBaselineUpdate);
  Update.Added := 2;
  Update.Removed := 9;
  Reset([Folder + '\atlas-baseline.json', Folder + '\Source\Main.pas', Folder + '\Alt\Weg.pas',
    Folder + '\Weg2.pas']);
  State := TAtlasProjectBaselines.StateOf(Folder, Exists, ReadText);
  TAtlasProjectBaselines.Updated(Section, Update, State, 4);
  Assert.IsTrue(Section.Known);
  Assert.IsTrue(Section.Exists);
  Assert.IsTrue(Section.At = 4);
  Assert.IsTrue(Section.Updated = 4);
  Assert.AreEqual(2, Section.Added);
  Assert.AreEqual(9, Section.Removed);
  Assert.AreEqual(0, Section.Orphaned);
end;

procedure TAtlasProjectBaselinesTests.WrittenElsewhereComparesFolders;
begin
  Assert.IsFalse(TAtlasProjectBaselines.WrittenElsewhere(Folder + '\Kasse.dproj', Folder + '\atlas-baseline.json'));
  Assert.IsFalse(TAtlasProjectBaselines.WrittenElsewhere('c:\projekte\kasse\Kasse.dproj',
    'C:/Projekte/Kasse/delphi-lsp-baseline.json'), 'Schreibweise egal');
  Assert.IsTrue(TAtlasProjectBaselines.WrittenElsewhere(Folder + '\Kasse.dproj', 'C:\Projekte\atlas-baseline.json'),
    'übergeordneter Arbeitsbereich');
  Assert.IsTrue(TAtlasProjectBaselines.WrittenElsewhere(Folder + '\Kasse.dproj',
    Folder + '\Sub\atlas-baseline.json'), 'Unterordner');
  Assert.IsFalse(TAtlasProjectBaselines.WrittenElsewhere(Folder + '\Kasse.dproj', ''), 'ohne Angabe');
  Assert.IsFalse(TAtlasProjectBaselines.WrittenElsewhere('', 'C:\B\atlas-baseline.json'));
end;

initialization
  Disk := TDictionary<string, string>.Create;
  TDUnitX.RegisterTestFixture(TAtlasProjectBaselinesTests);

finalization
  Disk.Free;

end.
