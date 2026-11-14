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
    /// <summary>Unechte Platte leeren: Der Leckmonitor zählte sie sonst dem Test an.</summary>
    [TearDown]
    procedure TearDown;
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
    /// <summary>StateOnDisk (#1455): ohne Ordner und ohne Datei nichts; unter Windows Einträge der echten Datei.
    /// </summary>
    [Test]
    procedure StateOnDiskReadsFolder;
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
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Baseline;

const
  cFolder = 'C:\Projekte\Kasse';
  cBaseline =
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
  mName: string;
begin
  Disk.Clear;
  Asked := 0;
  for mName in AFiles do
  begin
    Disk.AddOrSetValue(UpperCase(mName), cBaseline);
  end;
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

procedure TAtlasProjectBaselinesTests.TearDown;
begin
  Disk.Clear;
end;

procedure TAtlasProjectBaselinesTests.FileInPrefersNewName;
begin
  Reset([cFolder + '\atlas-baseline.json', cFolder + '\delphi-lsp-baseline.json']);
  Assert.AreEqual(cFolder + '\atlas-baseline.json', TAtlasProjectBaselines.FileIn(cFolder, Exists));
  Reset([cFolder + '\delphi-lsp-baseline.json']);
  Assert.AreEqual(cFolder + '\delphi-lsp-baseline.json', TAtlasProjectBaselines.FileIn(cFolder + '\', Exists));
  Reset([]);
  Assert.AreEqual('', TAtlasProjectBaselines.FileIn(cFolder, Exists));
  Assert.AreEqual('', TAtlasProjectBaselines.FileIn('', Exists));
end;

procedure TAtlasProjectBaselinesTests.StateWithoutFile;
var
  mState: TAtlasBaselineState;
begin
  Reset([]);
  mState := TAtlasProjectBaselines.StateOf(cFolder, Exists, ReadText);
  Assert.IsFalse(mState.Exists);
  Assert.IsFalse(mState.Valid);
  Assert.AreEqual('', mState.FileName);
  Assert.AreEqual(0, mState.Entries);
end;

procedure TAtlasProjectBaselinesTests.StateCountsEntriesAndHits;
var
  mState: TAtlasBaselineState;
begin
  Reset([cFolder + '\atlas-baseline.json', cFolder + '\Source\Main.pas', cFolder + '\Alt\Weg.pas',
    cFolder + '\Weg2.pas']);
  mState := TAtlasProjectBaselines.StateOf(cFolder, Exists, ReadText);
  Assert.IsTrue(mState.Exists);
  Assert.IsTrue(mState.Valid);
  Assert.AreEqual(cFolder + '\atlas-baseline.json', mState.FileName);
  Assert.AreEqual(5, mState.Entries);
  // Ohne "count" zählt ein Eintrag als ein Treffer.
  Assert.AreEqual(11, mState.Hits);
  Assert.AreEqual(0, Integer(Length(mState.Orphans)));
  Assert.AreEqual(0, mState.OrphanCount);
end;

procedure TAtlasProjectBaselinesTests.StateListsOrphansOncePerPath;
var
  mState: TAtlasBaselineState;
begin
  // Alt/Weg.pas wurde umbenannt, Weg2.pas gelöscht.
  Reset([cFolder + '\atlas-baseline.json', cFolder + '\Source\Main.pas']);
  mState := TAtlasProjectBaselines.StateOf(cFolder, Exists, ReadText);
  Assert.AreEqual(2, Integer(Length(mState.Orphans)));
  Assert.AreEqual('Alt/Weg.pas', mState.Orphans[0].Path);
  Assert.AreEqual(4, Integer(mState.Orphans[0].Count), 'gleicher Pfad in anderer Schreibweise zählt mit');
  Assert.AreEqual('Weg2.pas', mState.Orphans[1].Path);
  Assert.AreEqual(4, Integer(mState.Orphans[1].Count));
  Assert.AreEqual(8, mState.OrphanCount);
  // Je Pfad eine Abfrage (plus die nach der Baseline selbst).
  Assert.AreEqual(4, Asked);
end;

procedure TAtlasProjectBaselinesTests.StateOfInvalidFile;
var
  mState: TAtlasBaselineState;
begin
  mState := TAtlasProjectBaselines.StateOfText(cFolder, '{"version": 1}', nil);
  Assert.IsTrue(mState.Exists);
  Assert.IsFalse(mState.Valid);
  mState := TAtlasProjectBaselines.StateOfText(cFolder, 'kein JSON', nil);
  Assert.IsTrue(mState.Exists);
  Assert.IsFalse(mState.Valid);
  // Ohne Prüffunktion keine Einträge ohne Datei.
  mState := TAtlasProjectBaselines.StateOfText(cFolder, cBaseline, nil);
  Assert.IsTrue(mState.Valid);
  Assert.AreEqual(0, mState.OrphanCount);
end;

procedure TAtlasProjectBaselinesTests.StateOnDiskReadsFolder;
var
  mFolder: string;
  mState: TAtlasBaselineState;
begin
  Assert.IsFalse(TAtlasProjectBaselines.StateOnDisk('').Exists);
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasBaseline' + IntToStr(Random(MaxInt)));
  ForceDirectories(mFolder);
  try
    mState := TAtlasProjectBaselines.StateOnDisk(mFolder);
    Assert.IsFalse(mState.Exists);
    Assert.AreEqual('', mState.FileName);
    {$IFDEF MSWINDOWS}
    // Die Pfade setzt StateOf mit „\“ an den Ordner: nur unter Windows eine echte Datei.
    TFile.WriteAllText(mFolder + '\atlas-baseline.json', cBaseline, TEncoding.UTF8);
    mState := TAtlasProjectBaselines.StateOnDisk(mFolder);
    Assert.IsTrue(mState.Valid);
    Assert.AreEqual(5, mState.Entries);
    Assert.AreEqual(11, mState.Hits);
    {$ENDIF}
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TAtlasProjectBaselinesTests.ArgumentsAreProjectUri;
begin
  Assert.AreEqual('["file:///C:/Projekte/Kasse/Kasse.dproj"]',
    TAtlasProjectBaselines.Arguments('file:///C:/Projekte/Kasse/Kasse.dproj'));
  Assert.AreEqual('atlas.updateBaseline', TAtlasProjectBaselines.cCommand);
end;

procedure TAtlasProjectBaselinesTests.ParsesServerAnswer;
const
  cAnswer = '{"format": 1, "file": "C:\\Projekte\\Kasse\\atlas-baseline.json", "previous": "valid", ' +
    '"skipped": 1, "total": 120, "files": 40, "added": 3, "removed": 5, "unchanged": 117, "completed": 7, ' +
    '"orphaned": {"count": 3, "entries": [{"path": "Alt/U.pas", "count": 2}, {"path": "X.pas", "count": 1}]}}';
var
  mUpdate: TAtlasBaselineUpdate;
begin
  Assert.IsTrue(TAtlasProjectBaselines.FromServer(cAnswer, mUpdate));
  Assert.AreEqual('C:\Projekte\Kasse\atlas-baseline.json', mUpdate.FileName);
  Assert.AreEqual('valid', mUpdate.Previous);
  Assert.AreEqual(1, mUpdate.Skipped);
  Assert.AreEqual(120, mUpdate.Total);
  Assert.AreEqual(40, mUpdate.Files);
  Assert.AreEqual(3, mUpdate.Added);
  Assert.AreEqual(5, mUpdate.Removed);
  Assert.AreEqual(117, mUpdate.Unchanged);
  Assert.AreEqual(7, mUpdate.Completed);
  Assert.AreEqual(3, mUpdate.OrphanCount);
  Assert.AreEqual(2, Integer(Length(mUpdate.Orphans)));
  Assert.AreEqual('Alt/U.pas', mUpdate.Orphans[0].Path);
  Assert.AreEqual(2, Integer(mUpdate.Orphans[0].Count));
  // Ohne "orphaned" (ältere Server-Fassung): keine Einträge ohne Datei.
  Assert.IsTrue(TAtlasProjectBaselines.FromServer('{"file": "C:\\B.json", "total": 0}', mUpdate));
  Assert.AreEqual(0, mUpdate.OrphanCount);
  Assert.AreEqual(0, Integer(Length(mUpdate.Orphans)));
end;

procedure TAtlasProjectBaselinesTests.RejectsInvalidAnswer;
var
  mUpdate: TAtlasBaselineUpdate;
begin
  // Leer: Fehler, Zeitlimit oder geschlossene Verbindung.
  Assert.IsFalse(TAtlasProjectBaselines.FromServer('', mUpdate));
  Assert.IsFalse(TAtlasProjectBaselines.FromServer('null', mUpdate));
  Assert.IsFalse(TAtlasProjectBaselines.FromServer('{"total": 3}', mUpdate));
  Assert.IsFalse(TAtlasProjectBaselines.FromServer('{"file": "C:\\B.json"}', mUpdate));
end;

procedure TAtlasProjectBaselinesTests.SectionAfterBuildKeepsLastUpdate;
var
  mSection: TAtlasProjectBaseline;
  mState: TAtlasBaselineState;
begin
  mSection := TAtlasProjectBaseline.Empty;
  mSection.Updated := 1;
  mSection.Added := 3;
  mSection.Removed := 5;
  Reset([cFolder + '\atlas-baseline.json', cFolder + '\Source\Main.pas']);
  mState := TAtlasProjectBaselines.StateOf(cFolder, Exists, ReadText);
  TAtlasProjectBaselines.Measured(mSection, mState, 2);
  Assert.IsTrue(mSection.Known);
  Assert.AreEqual<TDateTime>(2, mSection.At);
  Assert.IsTrue(mSection.Exists);
  Assert.IsTrue(mSection.Valid);
  Assert.AreEqual(5, mSection.Entries);
  Assert.AreEqual(11, mSection.Hits);
  Assert.AreEqual(8, mSection.Orphaned);
  Assert.AreEqual<TDateTime>(1, mSection.Updated, 'ein Build ändert das letzte Aktualisieren nicht');
  Assert.AreEqual(3, mSection.Added);
  // Baseline gelöscht: bekannt, aber nicht vorhanden.
  Reset([]);
  TAtlasProjectBaselines.Measured(mSection, TAtlasProjectBaselines.StateOf(cFolder, Exists, ReadText), 3);
  Assert.IsTrue(mSection.Known);
  Assert.IsFalse(mSection.Exists);
  Assert.AreEqual(0, mSection.Hits);
end;

procedure TAtlasProjectBaselinesTests.SectionAfterUpdate;
var
  mSection: TAtlasProjectBaseline;
  mUpdate: TAtlasBaselineUpdate;
  mState: TAtlasBaselineState;
begin
  mSection := TAtlasProjectBaseline.Empty;
  mUpdate := Default(TAtlasBaselineUpdate);
  mUpdate.Added := 2;
  mUpdate.Removed := 9;
  Reset([cFolder + '\atlas-baseline.json', cFolder + '\Source\Main.pas', cFolder + '\Alt\Weg.pas',
    cFolder + '\Weg2.pas']);
  mState := TAtlasProjectBaselines.StateOf(cFolder, Exists, ReadText);
  TAtlasProjectBaselines.Updated(mSection, mUpdate, mState, 4);
  Assert.IsTrue(mSection.Known);
  Assert.IsTrue(mSection.Exists);
  Assert.AreEqual<TDateTime>(4, mSection.At);
  Assert.AreEqual<TDateTime>(4, mSection.Updated);
  Assert.AreEqual(2, mSection.Added);
  Assert.AreEqual(9, mSection.Removed);
  Assert.AreEqual(0, mSection.Orphaned);
end;

procedure TAtlasProjectBaselinesTests.WrittenElsewhereComparesFolders;
begin
  Assert.IsFalse(TAtlasProjectBaselines.WrittenElsewhere(cFolder + '\Kasse.dproj', cFolder + '\atlas-baseline.json'));
  Assert.IsFalse(TAtlasProjectBaselines.WrittenElsewhere('c:\projekte\kasse\Kasse.dproj',
    'C:/Projekte/Kasse/delphi-lsp-baseline.json'), 'Schreibweise egal');
  Assert.IsTrue(TAtlasProjectBaselines.WrittenElsewhere(cFolder + '\Kasse.dproj', 'C:\Projekte\atlas-baseline.json'),
    'übergeordneter Arbeitsbereich');
  Assert.IsTrue(TAtlasProjectBaselines.WrittenElsewhere(cFolder + '\Kasse.dproj',
    cFolder + '\Sub\atlas-baseline.json'), 'Unterordner');
  Assert.IsFalse(TAtlasProjectBaselines.WrittenElsewhere(cFolder + '\Kasse.dproj', ''), 'ohne Angabe');
  Assert.IsFalse(TAtlasProjectBaselines.WrittenElsewhere('', 'C:\B\atlas-baseline.json'));
end;

initialization
  // Mit Vorrat: Ein Test, der die Tabelle wachsen ließe, zählte sonst als Leck.
  Disk := TDictionary<string, string>.Create(64);
  TDUnitX.RegisterTestFixture(TAtlasProjectBaselinesTests);

finalization
  Disk.Free;

end.
