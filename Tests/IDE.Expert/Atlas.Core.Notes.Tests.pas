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
  [Category('Atlas.IDE.Bookmarks')]
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
    /// überschrieben.</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure LoadAllWithoutOpenProject;
    /// <summary>Akzeptanzkriterium „git status zeigt nichts“: die Ablage liegt im Notizordner, nie beim
    /// Projekt.</summary>
    [Test]
    procedure StorageLivesOutsideTheProject;
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
  cProject = 'C:\Projekte\Demo.dproj';
  cUnitFile = 'C:\Projekte\Kunde.pas';

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
  begin
    TDirectory.Delete(FFolder, True);
  end;
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

procedure TAtlasNoteStoreTests.AddFindChangeAndRemove;
var
  mBook: TAtlasNoteBook;
  mId: string;
  mIndex: Integer;
begin
  mBook := TAtlasNoteBook.Create(cProject);
  mId := mBook.Add(cUnitFile, Code, 8, 'hier noch Rundung prüfen', At(2026, 10, 15, 9, 0, 0));
  Assert.AreNotEqual('', mId);
  Assert.AreEqual(1, Integer(mBook.Count));
  mIndex := mBook.IndexAt('c:/projekte/kunde.pas', 8);
  Assert.AreEqual(0, mIndex, 'Pfad ohne Groß-/Kleinschreibung');
  Assert.AreEqual(-1, mBook.IndexAt(cUnitFile, 7));
  Assert.AreEqual(1, Integer(Length(mBook.AtLine(cUnitFile, 8))));
  Assert.AreEqual('Result := Round(X * 100) / 100;', mBook.Notes[0].Anchor.Text);
  Assert.IsTrue(SameTime(At(2026, 10, 15, 9, 0, 0), mBook.Notes[0].Created));
  Assert.IsTrue(mBook.SetText(mId, 'Rundung prüfen'#10'und testen', At(2026, 10, 15, 10, 0, 0)));
  Assert.AreEqual('Rundung prüfen'#10'und testen', mBook.Notes[0].Text);
  Assert.IsTrue(SameTime(At(2026, 10, 15, 10, 0, 0), mBook.Notes[0].Changed));
  Assert.IsFalse(mBook.SetText('gibt-es-nicht', 'x', Now));
  Assert.AreNotEqual(mId, mBook.Add(cUnitFile, Code, 2, 'zweite', Now), 'Kennungen eindeutig');
  Assert.AreEqual(1, Integer(Length(mBook.Files)), 'eine Datei');
  Assert.IsTrue(mBook.Remove(mId));
  Assert.IsFalse(mBook.Remove(mId));
  Assert.AreEqual(1, Integer(mBook.Count));
end;

procedure TAtlasNoteStoreTests.RelocateFollowsAndOrphans;
var
  mBook: TAtlasNoteBook;
  mChanged: TArray<string>;
begin
  mBook := TAtlasNoteBook.Create(cProject);
  mBook.Add(cUnitFile, Code, 8, 'Rundung', Now);
  mBook.Add('C:\Projekte\Andere.pas', Code, 8, 'andere Datei', Now);
  Assert.IsFalse(mBook.Relocate(cUnitFile, Code), 'nichts geändert');
  mChanged := Insert(Code, 0, ['// 1', '// 2']);
  Assert.IsTrue(mBook.Relocate(cUnitFile, mChanged));
  Assert.AreEqual(10, mBook.Notes[0].Line);
  Assert.AreEqual(8, mBook.Notes[1].Line, 'andere Datei unberührt');
  Assert.IsTrue(mBook.Notes[0].Anchor.SameAs(TAtlasLineAnchors.Capture(mChanged, 10)), 'neuer Stand gemerkt');
  // Zeile gelöscht: verwaist; wieder eingefügt (Rückgängig): wieder zugeordnet.
  Assert.IsTrue(mBook.Relocate(cUnitFile, Without(mChanged, 10, 1)));
  Assert.IsTrue(mBook.Notes[0].Orphaned);
  Assert.AreEqual(-1, mBook.IndexAt(cUnitFile, 10), 'verwaiste Notizen hängen an keiner Zeile');
  Assert.IsFalse(mBook.Relocate(cUnitFile, Without(mChanged, 10, 1)), 'bleibt verwaist');
  Assert.IsTrue(mBook.Relocate(cUnitFile, mChanged));
  Assert.IsFalse(mBook.Notes[0].Orphaned);
  Assert.AreEqual(10, mBook.Notes[0].Line);
end;

procedure TAtlasNoteStoreTests.OrphanFileMarksAllNotes;
var
  mBook: TAtlasNoteBook;
begin
  mBook := TAtlasNoteBook.Create(cProject);
  mBook.Add(cUnitFile, Code, 8, 'a', Now);
  mBook.Add(cUnitFile, Code, 2, 'b', Now);
  Assert.IsTrue(mBook.OrphanFile(cUnitFile));
  Assert.AreEqual(2, mBook.OrphanCount);
  Assert.IsFalse(mBook.OrphanFile(cUnitFile));
end;

procedure TAtlasNoteStoreTests.GroupsListEveryNoteWithOrphansLast;
var
  mBook: TAtlasNoteBook;
  mGroups: TArray<TAtlasNoteGroup>;
  mTotal, mIndex: Integer;
begin
  mBook := TAtlasNoteBook.Create(cProject);
  mBook.Add('C:\Projekte\Zahlung.pas', Code, 8, 'z', Now);
  mBook.Add(cUnitFile, Code, 9, 'k2', Now);
  mBook.Add(cUnitFile, Code, 2, 'k1', Now);
  mBook.Add('C:\Projekte\Alt.pas', Code, 4, 'verwaist', Now);
  mBook.OrphanFile('C:\Projekte\Alt.pas');
  mGroups := mBook.Groups;
  Assert.AreEqual(3, Integer(Length(mGroups)));
  Assert.AreEqual(cUnitFile, mGroups[0].FileName, 'nach Dateiname');
  Assert.AreEqual('k1', mGroups[0].Notes[0].Text, 'nach Zeile');
  Assert.AreEqual('k2', mGroups[0].Notes[1].Text);
  Assert.AreEqual('C:\Projekte\Zahlung.pas', mGroups[1].FileName);
  Assert.IsTrue(mGroups[2].Orphaned, 'verwaiste am Ende');
  Assert.AreEqual('verwaist', mGroups[2].Notes[0].Text);
  mTotal := 0;
  for mIndex := 0 to High(mGroups) do
  begin
    Inc(mTotal, Length(mGroups[mIndex].Notes));
  end;
  Assert.AreEqual(mBook.Count, mTotal, 'alle Notizen des Projekts');
end;

procedure TAtlasNoteStoreTests.TitleIsFirstLine;
var
  mNote: TAtlasNote;
begin
  mNote := Default(TAtlasNote);
  mNote.Text := #10'  Rundung prüfen  '#10'Details';
  Assert.AreEqual('Rundung prüfen …', mNote.Title);
  mNote.Text := 'einzeilig';
  Assert.AreEqual('einzeilig', mNote.Title);
  mNote.Text := '';
  Assert.AreEqual('', mNote.Title);
end;

procedure TAtlasNoteStoreTests.JsonRoundTrip;
var
  mBook, mRead: TAtlasNoteBook;
begin
  mBook := TAtlasNoteBook.Create(cProject);
  mBook.Add(cUnitFile, Code, 8, 'Rundung'#10'prüfen "genau"', At(2026, 10, 15, 9, 30, 0));
  mBook.Add(cUnitFile, Code, 2, 'zweite', At(2026, 10, 15, 9, 31, 0));
  mBook.Notes[1].Orphaned := True;
  Assert.IsTrue(TAtlasNotes.Parse(TAtlasNotes.ToJson(mBook), mRead));
  Assert.AreEqual(cProject, mRead.Project);
  Assert.AreEqual(2, Integer(mRead.Count));
  Assert.AreEqual(mBook.Notes[0].Id, mRead.Notes[0].Id);
  Assert.AreEqual(cUnitFile, mRead.Notes[0].FileName);
  Assert.AreEqual('Rundung'#10'prüfen "genau"', mRead.Notes[0].Text);
  Assert.IsTrue(mBook.Notes[0].Anchor.SameAs(mRead.Notes[0].Anchor), 'Anker vollständig');
  Assert.IsTrue(SameTime(mBook.Notes[0].Created, mRead.Notes[0].Created));
  Assert.IsTrue(SameTime(mBook.Notes[0].Changed, mRead.Notes[0].Changed));
  Assert.IsFalse(mRead.Notes[0].Orphaned);
  Assert.IsTrue(mRead.Notes[1].Orphaned);
end;

procedure TAtlasNoteStoreTests.ParsesDocumentedFormat;
var
  mBook: TAtlasNoteBook;
begin
  Assert.IsTrue(TAtlasNotes.Parse(
    '{"format": 1, "project": "C:\\Projekte\\Demo.dproj", "notes": [' +
    '{"id": "a1", "file": "C:\\Projekte\\Kunde.pas", "line": 42, "text": "hier noch Rundung prüfen",' +
    ' "lineText": "Result := Round(X);", "before": ["begin", "var X: Double;"], "after": ["end;"],' +
    ' "created": "2026-10-15T09:30:00Z", "changed": "2026-10-15T10:00:00Z"},' +
    '{"file": "ohne Kennung"}, 7]}', mBook));
  Assert.AreEqual(1, Integer(mBook.Count), 'unvollständige Einträge übergangen');
  Assert.AreEqual(41, mBook.Notes[0].Line, '"line" zählt ab 1');
  Assert.AreEqual('Result := Round(X);', mBook.Notes[0].Anchor.Text);
  Assert.AreEqual('var X: Double;', mBook.Notes[0].Anchor.Before[1]);
  Assert.AreEqual(1, Integer(Length(mBook.Notes[0].Anchor.After)));
  Assert.IsTrue(SameTime(At(2026, 10, 15, 9, 30, 0), mBook.Notes[0].Created));
  Assert.IsFalse(mBook.Notes[0].Orphaned);
  // Ohne "format" gilt 1.
  Assert.IsTrue(TAtlasNotes.Parse('{"project": "x", "notes": []}', mBook));
end;

procedure TAtlasNoteStoreTests.KeepsUnknownFields;
var
  mBook: TAtlasNoteBook;
  mRoot, mNote: TJSONObject;
begin
  Assert.IsTrue(TAtlasNotes.Parse('{"format": 1, "project": "p", "zukunft": {"a": 1}, "notes": [' +
    '{"id": "a1", "file": "f.pas", "line": 1, "text": "t", "farbe": "gelb"}]}', mBook));
  mBook.SetText('a1', 'neu', Now);
  mRoot := TJSONObject.ParseJSONValue(TAtlasNotes.ToJson(mBook)) as TJSONObject;
  try
    Assert.IsTrue(mRoot.GetValue('zukunft') is TJSONObject, 'oben');
    mNote := (mRoot.GetValue('notes') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('gelb', mNote.GetValue('farbe').Value, 'je Notiz');
    Assert.AreEqual('neu', mNote.GetValue('text').Value);
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasNoteStoreTests.RejectsInvalidAndNewerFormat;
var
  mBook: TAtlasNoteBook;
begin
  Assert.IsFalse(TAtlasNotes.Parse('', mBook));
  Assert.IsFalse(TAtlasNotes.Parse('kein JSON', mBook));
  Assert.IsFalse(TAtlasNotes.Parse('[1, 2]', mBook));
  Assert.IsFalse(TAtlasNotes.Parse('{"format": 2, "project": "p", "notes": []}', mBook));
  Assert.AreEqual(0, Integer(mBook.Count));
  Assert.AreEqual(2, TAtlasNotes.FormatOf('{"format": 2}'));
end;

procedure TAtlasNoteStoreTests.SaveAndLoadOnDisk;
var
  mBook, mRead: TAtlasNoteBook;
begin
  Assert.IsFalse(TAtlasNotes.Load(FFolder, cProject, mRead), 'noch keine Datei');
  Assert.AreEqual(cProject, mRead.Project);
  mBook := TAtlasNoteBook.Create(cProject);
  mBook.Add(cUnitFile, Code, 8, 'Rundung', Now);
  Assert.IsTrue(TAtlasNotes.Save(FFolder, mBook), 'legt den Ordner an');
  Assert.IsTrue(FileExists(TAtlasNotes.FileFor(FFolder, cProject)));
  Assert.IsFalse(FileExists(TAtlasNotes.FileFor(FFolder, cProject) + '.tmp'));
  Assert.IsTrue(TAtlasNotes.Load(FFolder, 'c:/projekte/DEMO.dproj', mRead));
  Assert.AreEqual(1, Integer(mRead.Count));
  Assert.AreEqual('Rundung', mRead.Notes[0].Text);
end;

procedure TAtlasNoteStoreTests.EmptyBookRemovesFile;
var
  mBook: TAtlasNoteBook;
  mId: string;
begin
  mBook := TAtlasNoteBook.Create(cProject);
  mId := mBook.Add(cUnitFile, Code, 8, 'Rundung', Now);
  Assert.IsTrue(TAtlasNotes.Save(FFolder, mBook));
  mBook.Remove(mId);
  Assert.IsTrue(TAtlasNotes.Save(FFolder, mBook));
  Assert.IsFalse(FileExists(TAtlasNotes.FileFor(FFolder, cProject)));
  Assert.IsTrue(TAtlasNotes.Save(FFolder, mBook), 'auch ohne Datei');
end;

procedure TAtlasNoteStoreTests.SaveKeepsNewerFormatFile;
var
  mBook: TAtlasNoteBook;
  mFileName, mNewer: string;
begin
  mFileName := TAtlasNotes.FileFor(FFolder, cProject);
  ForceDirectories(FFolder);
  mNewer := '{"format": 2, "project": "C:\\Projekte\\Demo.dproj"}';
  TFile.WriteAllText(mFileName, mNewer);
  mBook := TAtlasNoteBook.Create(cProject);
  mBook.Add(cUnitFile, Code, 8, 'x', Now);
  Assert.IsFalse(TAtlasNotes.Save(FFolder, mBook));
  Assert.AreEqual(mNewer, TFile.ReadAllText(mFileName, TEncoding.UTF8));
end;

procedure TAtlasNoteStoreTests.LoadAllWithoutOpenProject;
var
  mBook: TAtlasNoteBook;
  mBooks: TArray<TAtlasNoteBook>;
begin
  mBook := TAtlasNoteBook.Create('C:\Projekte\Zweites.dproj');
  mBook.Add(cUnitFile, Code, 2, 'b', Now);
  TAtlasNotes.Save(FFolder, mBook);
  mBook := TAtlasNoteBook.Create(cProject);
  mBook.Add(cUnitFile, Code, 8, 'a', Now);
  TAtlasNotes.Save(FFolder, mBook);
  // Kaputte Datei stört nicht.
  TFile.WriteAllText(TPath.Combine(FFolder, 'kaputt.json'), '{');
  mBooks := TAtlasNotes.LoadAll(FFolder);
  Assert.AreEqual(2, Integer(Length(mBooks)));
  Assert.AreEqual(cProject, mBooks[0].Project, 'nach Projektpfad');
  Assert.AreEqual('a', mBooks[0].Notes[0].Text);
  Assert.AreEqual('C:\Projekte\Zweites.dproj', mBooks[1].Project);
  Assert.AreEqual(0, Integer(Length(TAtlasNotes.LoadAll(TPath.Combine(FFolder, 'fehlt')))));
end;

procedure TAtlasNoteStoreTests.StorageLivesOutsideTheProject;
var
  mBase: string;
begin
  // Derselbe Schlüssel wie die Projekt-Zusammenfassung (#592); nur der Ordner unterscheidet sich.
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + TAtlasProjectSummaries.KeyOf(cProject) + '.json',
    TAtlasNotes.FileFor(FFolder, cProject));
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + 'cea7b8ab83412c7a.json',
    TAtlasNotes.FileFor(FFolder, cProject));
  mBase := GetEnvironmentVariable('LOCALAPPDATA');
  if mBase = '' then
  begin
    Assert.AreEqual('', TAtlasNotes.DefaultFolder);
  end
  else
  begin
    Assert.AreEqual(IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(mBase) + 'Atlas') + 'Notes',
      TAtlasNotes.DefaultFolder);
  end;
end;

procedure TAtlasNoteStoreTests.BrokenFileSetAsideLockedFileKept;
var
  mBook: TAtlasNoteBook;
  mFileName: string;
  mLock: TFileStream;
begin
  mFileName := TAtlasNotes.FileFor(FFolder, cProject);
  ForceDirectories(FFolder);
  TFile.WriteAllText(mFileName, '{"notes": [');
  Assert.IsFalse(TAtlasNotes.Load(FFolder, cProject, mBook));
  Assert.AreEqual(cProject, mBook.Project);
  Assert.IsTrue(FileExists(mFileName + TAtlasDataFile.cDefectExtension), 'beiseitegelegt');
  mBook.Add(cUnitFile, Code, 8, 'Rundung', Now);
  Assert.IsTrue(TAtlasNotes.Save(FFolder, mBook));
  mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
  try
    Assert.IsFalse(TAtlasNotes.Load(FFolder, cProject, mBook));
  finally
    mLock.Free;
  end;
  Assert.AreEqual(0, Integer(mBook.Count));
  Assert.AreEqual(mFileName, mBook.KeptFile);
  mBook.Add(cUnitFile, Code, 8, 'Ersatz', Now);
  Assert.IsFalse(TAtlasNotes.Save(FFolder, mBook), 'beim Laden gesperrt: nicht überschreiben');
  Assert.Contains(TFile.ReadAllText(mFileName, TEncoding.UTF8), 'Rundung');
  Assert.DoesNotContain(TFile.ReadAllText(mFileName, TEncoding.UTF8), 'Ersatz');
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNoteStoreTests);

end.
