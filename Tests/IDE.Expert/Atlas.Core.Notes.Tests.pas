unit Atlas.Core.Notes.Tests;

// Tests der persönlichen Notizen (#545): Notizbuch (Anlegen, Ändern, Löschen,
// Neuverankern, Liste mit verwaisten Notizen am Ende) und Ablage (Format,
// unbekannte Felder, höheres Format, Platte, alle Notizbücher ohne geöffnetes
// Projekt). Die Verankerung selbst testet Atlas.Core.Editor.LineAnchor.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasNoteStoreTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AddFindChangeAndRemove;
    [Test]
    procedure RelocateFollowsAndOrphans;
    [Test]
    procedure OrphanFileMarksAllNotes;
    /// <summary>Akzeptanzkriterium: Die Liste zeigt alle Notizen des Projekts.</summary>
    [Test]
    procedure GroupsListEveryNoteWithOrphansLast;
    [Test]
    procedure TitleIsFirstLine;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure ParsesDocumentedFormat;
    [Test]
    procedure KeepsUnknownFields;
    [Test]
    procedure RejectsInvalidAndNewerFormat;
    [Test]
    procedure SaveAndLoadOnDisk;
    [Test]
    procedure EmptyBookRemovesFile;
    [Test]
    procedure SaveKeepsNewerFormatFile;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben (Bericht N3).</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure LoadAllWithoutOpenProject;
    /// <summary>Akzeptanzkriterium „git status zeigt nichts“: die Ablage liegt im Notizordner, nie beim
    /// Projekt.</summary>
    [Test]
    procedure StorageLivesOutsideTheProject;
    [Test]
    procedure SameFileIgnoresCaseAndSlashes;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Notes.Store,
  Atlas.Core.Projects.Summary;

const
  Project = 'C:\Projekte\Demo.dproj';
  UnitFile = 'C:\Projekte\Kunde.pas';

function Code: TArray<string>;
begin
  Result := ['unit Kunde;', '', 'interface', '', 'implementation', '', 'function Runde(X: Double): Double;',
    'begin', '  Result := Round(X * 100) / 100;', 'end;', '', 'end.'];
end;

function Insert(const ALines: TArray<string>; AAt: Integer; const ANew: TArray<string>): TArray<string>;
begin
  Result := Copy(ALines, 0, AAt) + ANew + Copy(ALines, AAt, Length(ALines) - AAt);
end;

function Without(const ALines: TArray<string>; AAt, ACount: Integer): TArray<string>;
begin
  Result := Copy(ALines, 0, AAt) + Copy(ALines, AAt + ACount, Length(ALines) - AAt - ACount);
end;

function At(AYear, AMonth, ADay, AHour, AMinute, ASecond: Word): TDateTime;
begin
  Result := EncodeDate(AYear, AMonth, ADay) + EncodeTime(AHour, AMinute, ASecond, 0);
end;

function SameTime(A, B: TDateTime): Boolean;
begin
  Result := Abs(A - B) < 1 / 86400 / 2;
end;

{ TAtlasNoteStoreTests }

procedure TAtlasNoteStoreTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasNotes' + IntToStr(Random(1000000)));
end;

procedure TAtlasNoteStoreTests.TearDown;
begin
  if DirectoryExists(FFolder) then
    TDirectory.Delete(FFolder, True);
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

procedure TAtlasNoteStoreTests.AddFindChangeAndRemove;
var
  Book: TAtlasNoteBook;
  Id: string;
  Index: Integer;
begin
  Book := TAtlasNoteBook.Create(Project);
  Id := Book.Add(UnitFile, Code, 8, 'hier noch Rundung prüfen', At(2026, 10, 15, 9, 0, 0));
  Assert.AreNotEqual('', Id);
  Assert.AreEqual(1, Integer(Book.Count));
  Index := Book.IndexAt('c:/projekte/kunde.pas', 8);
  Assert.AreEqual(0, Index, 'Pfad ohne Groß-/Kleinschreibung');
  Assert.AreEqual(-1, Book.IndexAt(UnitFile, 7));
  Assert.AreEqual(1, Integer(Length(Book.AtLine(UnitFile, 8))));
  Assert.AreEqual('Result := Round(X * 100) / 100;', Book.Notes[0].Anchor.Text);
  Assert.IsTrue(SameTime(At(2026, 10, 15, 9, 0, 0), Book.Notes[0].Created));
  Assert.IsTrue(Book.SetText(Id, 'Rundung prüfen'#10'und testen', At(2026, 10, 15, 10, 0, 0)));
  Assert.AreEqual('Rundung prüfen'#10'und testen', Book.Notes[0].Text);
  Assert.IsTrue(SameTime(At(2026, 10, 15, 10, 0, 0), Book.Notes[0].Changed));
  Assert.IsFalse(Book.SetText('gibt-es-nicht', 'x', Now));
  Assert.AreNotEqual(Id, Book.Add(UnitFile, Code, 2, 'zweite', Now), 'Kennungen eindeutig');
  Assert.AreEqual(1, Integer(Length(Book.Files)), 'eine Datei');
  Assert.IsTrue(Book.Remove(Id));
  Assert.IsFalse(Book.Remove(Id));
  Assert.AreEqual(1, Integer(Book.Count));
end;

procedure TAtlasNoteStoreTests.RelocateFollowsAndOrphans;
var
  Book: TAtlasNoteBook;
  Changed: TArray<string>;
begin
  Book := TAtlasNoteBook.Create(Project);
  Book.Add(UnitFile, Code, 8, 'Rundung', Now);
  Book.Add('C:\Projekte\Andere.pas', Code, 8, 'andere Datei', Now);
  Assert.IsFalse(Book.Relocate(UnitFile, Code), 'nichts geändert');
  Changed := Insert(Code, 0, ['// 1', '// 2']);
  Assert.IsTrue(Book.Relocate(UnitFile, Changed));
  Assert.AreEqual(10, Book.Notes[0].Line);
  Assert.AreEqual(8, Book.Notes[1].Line, 'andere Datei unberührt');
  Assert.IsTrue(Book.Notes[0].Anchor.SameAs(TAtlasLineAnchors.Capture(Changed, 10)), 'neuer Stand gemerkt');
  // Zeile gelöscht: verwaist; wieder eingefügt (Rückgängig): wieder zugeordnet.
  Assert.IsTrue(Book.Relocate(UnitFile, Without(Changed, 10, 1)));
  Assert.IsTrue(Book.Notes[0].Orphaned);
  Assert.AreEqual(-1, Book.IndexAt(UnitFile, 10), 'verwaiste Notizen hängen an keiner Zeile');
  Assert.IsFalse(Book.Relocate(UnitFile, Without(Changed, 10, 1)), 'bleibt verwaist');
  Assert.IsTrue(Book.Relocate(UnitFile, Changed));
  Assert.IsFalse(Book.Notes[0].Orphaned);
  Assert.AreEqual(10, Book.Notes[0].Line);
end;

procedure TAtlasNoteStoreTests.OrphanFileMarksAllNotes;
var
  Book: TAtlasNoteBook;
begin
  Book := TAtlasNoteBook.Create(Project);
  Book.Add(UnitFile, Code, 8, 'a', Now);
  Book.Add(UnitFile, Code, 2, 'b', Now);
  Assert.IsTrue(Book.OrphanFile(UnitFile));
  Assert.AreEqual(2, Book.OrphanCount);
  Assert.IsFalse(Book.OrphanFile(UnitFile));
end;

procedure TAtlasNoteStoreTests.GroupsListEveryNoteWithOrphansLast;
var
  Book: TAtlasNoteBook;
  Groups: TArray<TAtlasNoteGroup>;
  Total, Index: Integer;
begin
  Book := TAtlasNoteBook.Create(Project);
  Book.Add('C:\Projekte\Zahlung.pas', Code, 8, 'z', Now);
  Book.Add(UnitFile, Code, 9, 'k2', Now);
  Book.Add(UnitFile, Code, 2, 'k1', Now);
  Book.Add('C:\Projekte\Alt.pas', Code, 4, 'verwaist', Now);
  Book.OrphanFile('C:\Projekte\Alt.pas');
  Groups := Book.Groups;
  Assert.AreEqual(3, Integer(Length(Groups)));
  Assert.AreEqual(UnitFile, Groups[0].FileName, 'nach Dateiname');
  Assert.AreEqual('k1', Groups[0].Notes[0].Text, 'nach Zeile');
  Assert.AreEqual('k2', Groups[0].Notes[1].Text);
  Assert.AreEqual('C:\Projekte\Zahlung.pas', Groups[1].FileName);
  Assert.IsTrue(Groups[2].Orphaned, 'verwaiste am Ende');
  Assert.AreEqual('verwaist', Groups[2].Notes[0].Text);
  Total := 0;
  for Index := 0 to High(Groups) do
    Inc(Total, Length(Groups[Index].Notes));
  Assert.AreEqual(Book.Count, Total, 'alle Notizen des Projekts');
end;

procedure TAtlasNoteStoreTests.TitleIsFirstLine;
var
  Note: TAtlasNote;
begin
  Note := Default(TAtlasNote);
  Note.Text := #10'  Rundung prüfen  '#10'Details';
  Assert.AreEqual('Rundung prüfen …', Note.Title);
  Note.Text := 'einzeilig';
  Assert.AreEqual('einzeilig', Note.Title);
  Note.Text := '';
  Assert.AreEqual('', Note.Title);
end;

procedure TAtlasNoteStoreTests.JsonRoundTrip;
var
  Book, Read: TAtlasNoteBook;
begin
  Book := TAtlasNoteBook.Create(Project);
  Book.Add(UnitFile, Code, 8, 'Rundung'#10'prüfen "genau"', At(2026, 10, 15, 9, 30, 0));
  Book.Add(UnitFile, Code, 2, 'zweite', At(2026, 10, 15, 9, 31, 0));
  Book.Notes[1].Orphaned := True;
  Assert.IsTrue(TAtlasNotes.Parse(TAtlasNotes.ToJson(Book), Read));
  Assert.AreEqual(Project, Read.Project);
  Assert.AreEqual(2, Integer(Read.Count));
  Assert.AreEqual(Book.Notes[0].Id, Read.Notes[0].Id);
  Assert.AreEqual(UnitFile, Read.Notes[0].FileName);
  Assert.AreEqual('Rundung'#10'prüfen "genau"', Read.Notes[0].Text);
  Assert.IsTrue(Book.Notes[0].Anchor.SameAs(Read.Notes[0].Anchor), 'Anker vollständig');
  Assert.IsTrue(SameTime(Book.Notes[0].Created, Read.Notes[0].Created));
  Assert.IsTrue(SameTime(Book.Notes[0].Changed, Read.Notes[0].Changed));
  Assert.IsFalse(Read.Notes[0].Orphaned);
  Assert.IsTrue(Read.Notes[1].Orphaned);
end;

procedure TAtlasNoteStoreTests.ParsesDocumentedFormat;
var
  Book: TAtlasNoteBook;
begin
  Assert.IsTrue(TAtlasNotes.Parse(
    '{"format": 1, "project": "C:\\Projekte\\Demo.dproj", "notes": [' +
    '{"id": "a1", "file": "C:\\Projekte\\Kunde.pas", "line": 42, "text": "hier noch Rundung prüfen",' +
    ' "lineText": "Result := Round(X);", "before": ["begin", "var X: Double;"], "after": ["end;"],' +
    ' "created": "2026-10-15T09:30:00Z", "changed": "2026-10-15T10:00:00Z"},' +
    '{"file": "ohne Kennung"}, 7]}', Book));
  Assert.AreEqual(1, Integer(Book.Count), 'unvollständige Einträge übergangen');
  Assert.AreEqual(41, Book.Notes[0].Line, '"line" zählt ab 1');
  Assert.AreEqual('Result := Round(X);', Book.Notes[0].Anchor.Text);
  Assert.AreEqual('var X: Double;', Book.Notes[0].Anchor.Before[1]);
  Assert.AreEqual(1, Integer(Length(Book.Notes[0].Anchor.After)));
  Assert.IsTrue(SameTime(At(2026, 10, 15, 9, 30, 0), Book.Notes[0].Created));
  Assert.IsFalse(Book.Notes[0].Orphaned);
  // Ohne "format" gilt 1.
  Assert.IsTrue(TAtlasNotes.Parse('{"project": "x", "notes": []}', Book));
end;

procedure TAtlasNoteStoreTests.KeepsUnknownFields;
var
  Book: TAtlasNoteBook;
  Root, Note: TJSONObject;
begin
  Assert.IsTrue(TAtlasNotes.Parse('{"format": 1, "project": "p", "zukunft": {"a": 1}, "notes": [' +
    '{"id": "a1", "file": "f.pas", "line": 1, "text": "t", "farbe": "gelb"}]}', Book));
  Book.SetText('a1', 'neu', Now);
  Root := TJSONObject.ParseJSONValue(TAtlasNotes.ToJson(Book)) as TJSONObject;
  try
    Assert.IsTrue(Root.GetValue('zukunft') is TJSONObject, 'oben');
    Note := (Root.GetValue('notes') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('gelb', Note.GetValue('farbe').Value, 'je Notiz');
    Assert.AreEqual('neu', Note.GetValue('text').Value);
  finally
    Root.Free;
  end;
end;

procedure TAtlasNoteStoreTests.RejectsInvalidAndNewerFormat;
var
  Book: TAtlasNoteBook;
begin
  Assert.IsFalse(TAtlasNotes.Parse('', Book));
  Assert.IsFalse(TAtlasNotes.Parse('kein JSON', Book));
  Assert.IsFalse(TAtlasNotes.Parse('[1, 2]', Book));
  Assert.IsFalse(TAtlasNotes.Parse('{"format": 2, "project": "p", "notes": []}', Book));
  Assert.AreEqual(0, Integer(Book.Count));
  Assert.AreEqual(2, TAtlasNotes.FormatOf('{"format": 2}'));
end;

procedure TAtlasNoteStoreTests.SaveAndLoadOnDisk;
var
  Book, Read: TAtlasNoteBook;
begin
  Assert.IsFalse(TAtlasNotes.Load(FFolder, Project, Read), 'noch keine Datei');
  Assert.AreEqual(Project, Read.Project);
  Book := TAtlasNoteBook.Create(Project);
  Book.Add(UnitFile, Code, 8, 'Rundung', Now);
  Assert.IsTrue(TAtlasNotes.Save(FFolder, Book), 'legt den Ordner an');
  Assert.IsTrue(FileExists(TAtlasNotes.FileFor(FFolder, Project)));
  Assert.IsFalse(FileExists(TAtlasNotes.FileFor(FFolder, Project) + '.tmp'));
  Assert.IsTrue(TAtlasNotes.Load(FFolder, 'c:/projekte/DEMO.dproj', Read));
  Assert.AreEqual(1, Integer(Read.Count));
  Assert.AreEqual('Rundung', Read.Notes[0].Text);
end;

procedure TAtlasNoteStoreTests.EmptyBookRemovesFile;
var
  Book: TAtlasNoteBook;
  Id: string;
begin
  Book := TAtlasNoteBook.Create(Project);
  Id := Book.Add(UnitFile, Code, 8, 'Rundung', Now);
  Assert.IsTrue(TAtlasNotes.Save(FFolder, Book));
  Book.Remove(Id);
  Assert.IsTrue(TAtlasNotes.Save(FFolder, Book));
  Assert.IsFalse(FileExists(TAtlasNotes.FileFor(FFolder, Project)));
  Assert.IsTrue(TAtlasNotes.Save(FFolder, Book), 'auch ohne Datei');
end;

procedure TAtlasNoteStoreTests.SaveKeepsNewerFormatFile;
var
  Book: TAtlasNoteBook;
  FileName, Newer: string;
begin
  FileName := TAtlasNotes.FileFor(FFolder, Project);
  ForceDirectories(FFolder);
  Newer := '{"format": 2, "project": "C:\\Projekte\\Demo.dproj"}';
  TFile.WriteAllText(FileName, Newer);
  Book := TAtlasNoteBook.Create(Project);
  Book.Add(UnitFile, Code, 8, 'x', Now);
  Assert.IsFalse(TAtlasNotes.Save(FFolder, Book));
  Assert.AreEqual(Newer, TFile.ReadAllText(FileName));
end;

procedure TAtlasNoteStoreTests.LoadAllWithoutOpenProject;
var
  Book: TAtlasNoteBook;
  Books: TArray<TAtlasNoteBook>;
begin
  Book := TAtlasNoteBook.Create('C:\Projekte\Zweites.dproj');
  Book.Add(UnitFile, Code, 2, 'b', Now);
  TAtlasNotes.Save(FFolder, Book);
  Book := TAtlasNoteBook.Create(Project);
  Book.Add(UnitFile, Code, 8, 'a', Now);
  TAtlasNotes.Save(FFolder, Book);
  // Kaputte Datei stört nicht.
  TFile.WriteAllText(TPath.Combine(FFolder, 'kaputt.json'), '{');
  Books := TAtlasNotes.LoadAll(FFolder);
  Assert.AreEqual(2, Integer(Length(Books)));
  Assert.AreEqual(Project, Books[0].Project, 'nach Projektpfad');
  Assert.AreEqual('a', Books[0].Notes[0].Text);
  Assert.AreEqual('C:\Projekte\Zweites.dproj', Books[1].Project);
  Assert.AreEqual(0, Integer(Length(TAtlasNotes.LoadAll(TPath.Combine(FFolder, 'fehlt')))));
end;

procedure TAtlasNoteStoreTests.StorageLivesOutsideTheProject;
var
  Base: string;
begin
  // Derselbe Schlüssel wie die Projekt-Zusammenfassung (#592); nur der Ordner unterscheidet sich.
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + TAtlasProjectSummaries.KeyOf(Project) + '.json',
    TAtlasNotes.FileFor(FFolder, Project));
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + 'cea7b8ab83412c7a.json',
    TAtlasNotes.FileFor(FFolder, Project));
  Base := GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then
    Assert.AreEqual('', TAtlasNotes.DefaultFolder)
  else
    Assert.AreEqual(IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(Base) + 'Atlas') + 'Notes',
      TAtlasNotes.DefaultFolder);
end;

procedure TAtlasNoteStoreTests.SameFileIgnoresCaseAndSlashes;
begin
  Assert.IsTrue(TAtlasNotes.SameFile('C:\Projekte\Kunde.pas', ' c:/projekte/KUNDE.pas '));
  Assert.IsFalse(TAtlasNotes.SameFile('C:\Projekte\Kunde.pas', 'C:\Projekte\Kunde.dfm'));
end;

procedure TAtlasNoteStoreTests.BrokenFileSetAsideLockedFileKept;
var
  Book: TAtlasNoteBook;
  FileName: string;
  Lock: TFileStream;
begin
  FileName := TAtlasNotes.FileFor(FFolder, Project);
  ForceDirectories(FFolder);
  TFile.WriteAllText(FileName, '{"notes": [');
  Assert.IsFalse(TAtlasNotes.Load(FFolder, Project, Book));
  Assert.AreEqual(Project, Book.Project);
  Assert.IsTrue(FileExists(FileName + TAtlasDataFile.DefectExtension), 'beiseitegelegt');
  Book.Add(UnitFile, Code, 8, 'Rundung', Now);
  Assert.IsTrue(TAtlasNotes.Save(FFolder, Book));
  Lock := TFileStream.Create(FileName, fmOpenRead or fmShareExclusive);
  try
    Assert.IsFalse(TAtlasNotes.Load(FFolder, Project, Book));
  finally
    Lock.Free;
  end;
  Assert.AreEqual(0, Integer(Book.Count));
  Assert.AreEqual(FileName, Book.KeptFile);
  Book.Add(UnitFile, Code, 8, 'Ersatz', Now);
  Assert.IsFalse(TAtlasNotes.Save(FFolder, Book), 'beim Laden gesperrt: nicht überschreiben');
  Assert.Contains(TFile.ReadAllText(FileName), 'Rundung');
  Assert.DoesNotContain(TFile.ReadAllText(FileName), 'Ersatz');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNoteStoreTests);

end.
