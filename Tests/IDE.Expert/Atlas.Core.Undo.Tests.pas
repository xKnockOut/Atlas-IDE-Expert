unit Atlas.Core.Undo.Tests;

// Dateiübergreifendes Zurücknehmen (#721): Stellenvergleich, Protokoll mit
// offenen (Speicherziel) und geschlossenen Dateien (Platte), DFM, neue und
// gelöschte Dateien, Konflikte in beiden Modi, Kodierung und Zeilenenden,
// Persistenz mit Größenbegrenzung, kein Quelltext im Protokoll.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLinePatchTests = class
  public
    [Test]
    procedure SplitsLinesWithTheirEnds;
    [Test]
    procedure FindsChangedBlocks;
    [Test]
    procedure RebaseKeepsLaterEditsElsewhere;
    [Test]
    procedure RebaseRefusesTouchedPlaces;
  end;

  [TestFixture]
  TAtlasUndoJournalTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RecordsOnlyMultiFileActions;
    [Test]
    procedure UndoAndRedoOpenFilesAndForm;
    [Test]
    procedure ClosedFilesKeepEncodingAndLineEnds;
    [Test]
    procedure NewAndDeletedFiles;
    [Test]
    procedure ConflictPartialAndAbort;
    [Test]
    procedure OlderSetWhilePlacesUnchanged;
    [Test]
    procedure RedoFollowsUndoOrder;
    [Test]
    procedure PersistsWithSizeLimit;
    [Test]
    procedure LogHasNoNamesOrSource;
    [Test]
    procedure DisabledRecordsNothing;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.LinePatch,
  Atlas.Core.Undo.Journal,
  Atlas.Core.Undo.Adapters.FileStore,
  Atlas.Core.Undo.Adapters.DiskTarget;

type
  /// <summary>Ziel im Speicher wie offene Puffer: zählt Schreibvorgänge je Datei
  /// (ein Rückgängig-Schritt).</summary>
  TMemoryTarget = class(TInterfacedObject, IAtlasUndoTarget)
  public
    Files: TDictionary<string, TAtlasTextFileContent>;
    Writes: TDictionary<string, Integer>;
    Removed: TList<string>;
    RemoveModes: TList<TAtlasNewFilesMode>;
    FailOn: string;
    constructor Create;
    destructor Destroy; override;
    function Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
    procedure Write(const AFileName: string; const AContent: TAtlasTextFileContent);
    procedure CreateFile(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
    procedure RemoveFile(const AFileName, AProject: string; AMode: TAtlasNewFilesMode);
    procedure Put(const AFileName, AText: string);
    function Text(const AFileName: string): string;
    function WriteCount(const AFileName: string): Integer;
  end;

function Content(const AText: string; AEncoding: TAtlasTextEncoding): TAtlasTextFileContent; overload;
begin
  Result := Default(TAtlasTextFileContent);
  Result.Text := AText;
  Result.Encoding := AEncoding;
end;

function Content(const AText: string): TAtlasTextFileContent; overload;
begin
  Result := Content(AText, TAtlasTextEncoding.Utf8Bom);
end;

{ TMemoryTarget }

constructor TMemoryTarget.Create;
begin
  inherited Create;
  Files := TDictionary<string, TAtlasTextFileContent>.Create;
  Writes := TDictionary<string, Integer>.Create;
  Removed := TList<string>.Create;
  RemoveModes := TList<TAtlasNewFilesMode>.Create;
end;

destructor TMemoryTarget.Destroy;
begin
  RemoveModes.Free;
  Removed.Free;
  Writes.Free;
  Files.Free;
  inherited;
end;

function TMemoryTarget.Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
begin
  Result := Files.TryGetValue(AFileName, AContent);
end;

procedure TMemoryTarget.Write(const AFileName: string; const AContent: TAtlasTextFileContent);
begin
  if AFileName = FailOn then
    raise EInOutError.Create('schreibgeschützt');
  Files.AddOrSetValue(AFileName, AContent);
  Writes.AddOrSetValue(AFileName, WriteCount(AFileName) + 1);
end;

procedure TMemoryTarget.CreateFile(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
begin
  Files.AddOrSetValue(AFileName, AContent);
end;

procedure TMemoryTarget.RemoveFile(const AFileName, AProject: string; AMode: TAtlasNewFilesMode);
begin
  Files.Remove(AFileName);
  Removed.Add(AFileName);
  RemoveModes.Add(AMode);
end;

procedure TMemoryTarget.Put(const AFileName, AText: string);
begin
  Files.AddOrSetValue(AFileName, Content(AText));
end;

function TMemoryTarget.Text(const AFileName: string): string;
var
  Value: TAtlasTextFileContent;
begin
  Result := '<fehlt>';
  if Files.TryGetValue(AFileName, Value) then
    Result := Value.Text;
end;

function TMemoryTarget.WriteCount(const AFileName: string): Integer;
begin
  if not Writes.TryGetValue(AFileName, Result) then
    Result := 0;
end;

/// <summary>Satz für AFiles (Name, vorher, nachher) anlegen und den Stand „nachher“ ins Ziel schreiben.</summary>
function Apply(AJournal: TAtlasUndoJournal; ATarget: TMemoryTarget; const AAction: string;
  const AFiles: array of string): Integer;
var
  Index: Integer;
  Changes: TArray<TAtlasFileChange>;
begin
  Changes := nil;
  Index := 0;
  while Index + 2 <= High(AFiles) do
  begin
    Changes := Changes + [TAtlasFileChange.Modified(AFiles[Index], Content(AFiles[Index + 1]),
      Content(AFiles[Index + 2]))];
    ATarget.Put(AFiles[Index], AFiles[Index + 2]);
    Inc(Index, 3);
  end;
  Result := AJournal.Add(AAction, Changes);
end;

{ TAtlasLinePatchTests }

procedure TAtlasLinePatchTests.SplitsLinesWithTheirEnds;
var
  Lines: TArray<string>;
begin
  Lines := TAtlasLinePatch.SplitLines('a'#13#10'b'#10'c'#13'd');
  Assert.AreEqual(4, Integer(Length(Lines)));
  Assert.AreEqual('a'#13#10, Lines[0]);
  Assert.AreEqual('b'#10, Lines[1]);
  Assert.AreEqual('c'#13, Lines[2]);
  Assert.AreEqual('d', Lines[3]);
  Assert.AreEqual(1, Integer(Length(TAtlasLinePatch.SplitLines('x'#13#10))));
  Assert.AreEqual(0, Integer(Length(TAtlasLinePatch.SplitLines(''))));
end;

procedure TAtlasLinePatchTests.FindsChangedBlocks;
var
  Hunks: TArray<TAtlasLineHunk>;
begin
  Hunks := TAtlasLinePatch.Hunks(['a', 'b', 'c', 'd', 'e'], ['a', 'B', 'c', 'd', 'x', 'e']);
  Assert.AreEqual(2, Integer(Length(Hunks)));
  Assert.AreEqual(1, Hunks[0].OldStart);
  Assert.AreEqual(1, Hunks[0].OldCount);
  Assert.AreEqual(1, Hunks[0].NewCount);
  Assert.AreEqual(4, Hunks[1].OldStart);
  Assert.AreEqual(0, Hunks[1].OldCount);
  Assert.AreEqual(1, Hunks[1].NewCount);
  Assert.AreEqual(4, Hunks[1].NewStart);
  Assert.AreEqual(0, Integer(Length(TAtlasLinePatch.Hunks(['a'], ['a']))));
end;

procedure TAtlasLinePatchTests.RebaseKeepsLaterEditsElsewhere;
const
  Before = 'unit A;'#13#10'var'#13#10'  Alt: Integer;'#13#10'begin'#13#10'  Alt := 1;'#13#10'end.'#13#10;
  After = 'unit A;'#13#10'var'#13#10'  Neu: Integer;'#13#10'begin'#13#10'  Neu := 1;'#13#10'end.'#13#10;
var
  Current, Undone: string;
begin
  Assert.IsTrue(TAtlasLinePatch.Rebase(After, Before, After, Undone));
  Assert.AreEqual(Before, Undone);
  // Später eine Zeile am Ende ergänzt (nicht angrenzend): bleibt beim Zurücknehmen.
  Current := After + '// Ende'#13#10;
  Assert.IsTrue(TAtlasLinePatch.Rebase(After, Before, Current, Undone));
  Assert.AreEqual(Before + '// Ende'#13#10, Undone);
  // Schon von Hand zurückgenommen: Ziel.
  Assert.IsTrue(TAtlasLinePatch.Rebase(After, Before, Before, Undone));
  Assert.AreEqual(Before, Undone);
end;

procedure TAtlasLinePatchTests.RebaseRefusesTouchedPlaces;
const
  Before = 'a'#10'b'#10'c'#10'd'#10'e'#10'f'#10;
  After = 'a'#10'B'#10'c'#10'd'#10'e'#10'f'#10;
var
  Result: string;
begin
  // Die geänderte Zeile selbst und eine direkt angrenzende sind Konflikte.
  Assert.IsFalse(TAtlasLinePatch.Rebase(After, Before, 'a'#10'BB'#10'c'#10'd'#10'e'#10'f'#10, Result));
  Assert.IsFalse(TAtlasLinePatch.Rebase(After, Before, 'a'#10'B'#10'C'#10'd'#10'e'#10'f'#10, Result));
  Assert.AreEqual('', Result);
  // Zwei Zeilen Abstand: kein Konflikt.
  Assert.IsTrue(TAtlasLinePatch.Rebase(After, Before, 'a'#10'B'#10'c'#10'D'#10'e'#10'f'#10, Result));
  Assert.AreEqual('a'#10'b'#10'c'#10'D'#10'e'#10'f'#10, Result);
end;

{ TAtlasUndoJournalTests }

procedure TAtlasUndoJournalTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-undo-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TAtlasUndoJournalTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
end;

procedure TAtlasUndoJournalTests.RecordsOnlyMultiFileActions;
var
  Target: TMemoryTarget;
  TargetRef: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
  ChangeSet: TAtlasChangeSet;
begin
  Target := TMemoryTarget.Create;
  TargetRef := Target;
  Journal := TAtlasUndoJournal.Create(TargetRef);
  try
    // Eine Datei: Strg+Z im Puffer genügt.
    Assert.AreEqual(0, Apply(Journal, Target, 'Eins', ['A.pas', 'a', 'b']));
    // Unveränderte Dateien zählen nicht.
    Assert.AreEqual(0, Apply(Journal, Target, 'Gleich', ['A.pas', 'b', 'c', 'B.pas', 'x', 'x']));
    Assert.AreEqual(1, Apply(Journal, Target, 'Zwei', ['A.pas', 'c', 'd', 'B.pas', 'x', 'y', 'C.pas', 'z', 'z']));
    Assert.IsTrue(Journal.Find(1, ChangeSet));
    Assert.AreEqual('Zwei', ChangeSet.Action);
    Assert.AreEqual(2, Integer(Length(ChangeSet.Files)));
    Assert.AreEqual(Ord(TAtlasChangeSetState.Applied), Ord(ChangeSet.State));
    // Eine neue Datei allein ist schon eine Dateioperation.
    Assert.AreEqual(2, Journal.Add('Neue Unit', [TAtlasFileChange.Created('N.pas', 'P.dproj', Content('unit N;'))]));
    Assert.AreEqual(2, Journal.LastUndoable);
    Assert.AreEqual(2, Journal.Sets[0].Id, 'neueste zuerst');
    // Tiefe: nur die letzten Sätze bleiben.
    Journal.Options := TAtlasUndoOptions.Defaults;
    Journal.Add('Drei', [TAtlasFileChange.Created('M.pas', '', Content('m'))]);
    Assert.AreEqual(3, Journal.Count);
    Journal.Options := Default(TAtlasUndoOptions);
    Assert.AreEqual(1, Journal.Count, 'Tiefe mindestens 1');
    Assert.AreEqual(3, Journal.Sets[0].Id);
  finally
    Journal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.UndoAndRedoOpenFilesAndForm;
const
  Unit1Before = 'unit Unit1;'#13#10'procedure Alt;'#13#10'implementation'#13#10'end.';
  Unit1After = 'unit Unit1;'#13#10'procedure Neu;'#13#10'implementation'#13#10'end.';
  FormBefore = 'object Form1: TForm1'#13#10'  OnClick = Alt'#13#10'end'#13#10;
  FormAfter = 'object Form1: TForm1'#13#10'  OnClick = Neu'#13#10'end'#13#10;
var
  Target: TMemoryTarget;
  TargetRef: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
  Report: TAtlasUndoReport;
  ChangeSet: TAtlasChangeSet;
  Id: Integer;
begin
  Target := TMemoryTarget.Create;
  TargetRef := Target;
  Journal := TAtlasUndoJournal.Create(TargetRef);
  try
    // Umbenennen über drei Units und eine DFM.
    Id := Apply(Journal, Target, 'Umbenennen: Alt → Neu', ['Unit1.pas', Unit1Before, Unit1After, 'Unit2.pas',
      'uses Unit1;'#10'Alt;'#10, 'uses Unit1;'#10'Neu;'#10, 'Unit3.pas', 'Alt', 'Neu', 'Unit1.dfm', FormBefore,
      FormAfter]);
    Assert.AreEqual(1, Id);
    Report := Journal.Undo;
    Assert.IsTrue(Report.Complete);
    Assert.AreEqual('Umbenennen: Alt → Neu', Report.Action);
    Assert.AreEqual(4, Integer(Length(Report.Done)));
    Assert.AreEqual(Unit1Before, Target.Text('Unit1.pas'));
    Assert.AreEqual('uses Unit1;'#10'Alt;'#10, Target.Text('Unit2.pas'));
    Assert.AreEqual('Alt', Target.Text('Unit3.pas'));
    Assert.AreEqual(FormBefore, Target.Text('Unit1.dfm'));
    // Je Datei genau ein Schreibvorgang = ein Rückgängig-Schritt im Puffer.
    Assert.AreEqual(1, Target.WriteCount('Unit1.pas'));
    Assert.AreEqual(1, Target.WriteCount('Unit1.dfm'));
    Assert.IsTrue(Journal.Find(Id, ChangeSet));
    Assert.AreEqual(Ord(TAtlasChangeSetState.Undone), Ord(ChangeSet.State));
    Assert.AreEqual(0, Journal.LastUndoable);
    // Noch einmal: nichts mehr zurückzunehmen.
    Assert.IsTrue(Journal.Undo.NotFound);
    Assert.AreEqual(Id, Journal.LastRedoable);
    Report := Journal.Redo;
    Assert.IsTrue(Report.Complete);
    Assert.IsTrue(Report.Redo);
    Assert.AreEqual(Unit1After, Target.Text('Unit1.pas'));
    Assert.AreEqual(FormAfter, Target.Text('Unit1.dfm'));
    Assert.AreEqual(2, Target.WriteCount('Unit3.pas'));
    Assert.AreEqual(0, Journal.LastRedoable);
    Assert.AreEqual(Id, Journal.LastUndoable);
  finally
    Journal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.ClosedFilesKeepEncodingAndLineEnds;
var
  Disk: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
  Utf16, Ansi, Mixed, Form: string;
  Utf16Before, AnsiBefore, MixedBefore, FormBefore: TBytes;
  Changes: TArray<TAtlasFileChange>;

  function Change(const AFileName, ANewText: string; out AOriginal: TBytes): TAtlasFileChange;
  var
    Before, After: TAtlasTextFileContent;
  begin
    AOriginal := TFile.ReadAllBytes(AFileName);
    Before := TAtlasTextFile.Decode(AOriginal, 1252);
    After := Before;
    After.Text := ANewText;
    TAtlasTextFile.Save(AFileName, After);
    Result := TAtlasFileChange.Modified(AFileName, Before, After);
  end;

begin
  Utf16 := TPath.Combine(FFolder, 'Utf16.pas');
  Ansi := TPath.Combine(FFolder, 'Ansi.pas');
  Mixed := TPath.Combine(FFolder, 'Mixed.pas');
  Form := TPath.Combine(FFolder, 'Form.dfm');
  // Vorgabe-Codepage wie in einem Projekt mit ANSI-Quelltexten (#121), unabhängig vom System.
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.json'), '{"encoding": "windows-1252"}');
  TFile.WriteAllBytes(Utf16, TBytes.Create($FF, $FE) + TEncoding.Unicode.GetBytes('Größe := 1;'#13#10'Alt;'#13#10));
  TFile.WriteAllBytes(Ansi, TBytes.Create(Ord('A'), Ord('l'), Ord('t'), $FC, 10, Ord('x'), 10));
  TFile.WriteAllBytes(Mixed, TEncoding.UTF8.GetBytes('Alt'#13#10'zwei'#10'drei'));
  TFile.WriteAllBytes(Form, TEncoding.UTF8.GetBytes('object F: TF'#13#10'  OnClick = Alt'#13#10'end'#13#10));
  Changes := [Change(Utf16, 'Größe := 1;'#13#10'Neu;'#13#10, Utf16Before),
    Change(Ansi, 'Neu'#$00FC#10'x'#10, AnsiBefore),
    Change(Mixed, 'Neu'#13#10'zwei'#10'drei', MixedBefore),
    Change(Form, 'object F: TF'#13#10'  OnClick = Neu'#13#10'end'#13#10, FormBefore)];
  Disk := TAtlasUndoDiskTarget.Create;
  Journal := TAtlasUndoJournal.Create(Disk);
  try
    Assert.AreEqual(1, Journal.Add('Umbenennen', Changes));
    Assert.IsTrue(Journal.Undo.Complete);
    // Byte für Byte wie vorher: BOM, Kodierung, Umlaute, CRLF/LF gemischt, fehlende letzte Zeilenschaltung.
    Assert.AreEqual(TEncoding.Unicode.GetString(Utf16Before), TEncoding.Unicode.GetString(TFile.ReadAllBytes(Utf16)));
    Assert.AreEqual(Integer(Length(Utf16Before)), Integer(Length(TFile.ReadAllBytes(Utf16))));
    Assert.AreEqual(Integer(Length(AnsiBefore)), Integer(Length(TFile.ReadAllBytes(Ansi))));
    Assert.AreEqual($FC, Integer(TFile.ReadAllBytes(Ansi)[3]));
    Assert.AreEqual(TEncoding.UTF8.GetString(MixedBefore), TEncoding.UTF8.GetString(TFile.ReadAllBytes(Mixed)));
    Assert.AreEqual(TEncoding.UTF8.GetString(FormBefore), TEncoding.UTF8.GetString(TFile.ReadAllBytes(Form)));
    Assert.IsTrue(Journal.Redo.Complete);
    Assert.AreEqual('Neu'#13#10'zwei'#10'drei', TEncoding.UTF8.GetString(TFile.ReadAllBytes(Mixed)));
    Assert.AreEqual($FF, Integer(TFile.ReadAllBytes(Utf16)[0]), 'UTF-16 bleibt');
  finally
    Journal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.NewAndDeletedFiles;
var
  Disk: TAtlasUndoDiskTarget;
  DiskRef: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
  Options: TAtlasUndoOptions;
  NewUnit, OldUnit, Dpr: string;
  Added, Removed, Recycled: TList<string>;
  OldContent: TAtlasTextFileContent;
  Report: TAtlasUndoReport;
begin
  NewUnit := TPath.Combine(FFolder, 'Neu.pas');
  OldUnit := TPath.Combine(FFolder, 'Alt.pas');
  Dpr := TPath.Combine(FFolder, 'P.dpr');
  Added := TList<string>.Create;
  Removed := TList<string>.Create;
  Recycled := TList<string>.Create;
  Disk := TAtlasUndoDiskTarget.Create;
  DiskRef := Disk;
  Disk.OnAddToProject :=
    procedure(const AFileName, AProject: string)
    begin
      Added.Add(ExtractFileName(AFileName) + '@' + AProject);
    end;
  Disk.OnRemoveFromProject :=
    procedure(const AFileName, AProject: string)
    begin
      Removed.Add(ExtractFileName(AFileName) + '@' + AProject);
    end;
  Disk.OnRecycle :=
    procedure(AFileName: string)
    begin
      Recycled.Add(ExtractFileName(AFileName));
      TFile.Delete(AFileName);
    end;
  Journal := TAtlasUndoJournal.Create(DiskRef);
  try
    // Aktion: neue Unit angelegt, alte gelöscht (ANSI-Umlaut bleibt), .dpr geändert.
    TFile.WriteAllBytes(NewUnit, TEncoding.UTF8.GetBytes('unit Neu;'));
    TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.json'), '{"encoding": "windows-1252"}');
    OldContent := Content('unit Alt; // Grüße', TAtlasTextEncoding.Ansi);
    OldContent.CodePage := 1252;
    TFile.WriteAllBytes(Dpr, TEncoding.UTF8.GetBytes('uses Neu;'));
    Assert.AreEqual(1, Journal.Add('Unit verschieben', [
      TAtlasFileChange.Created(NewUnit, 'P.dproj', Content('unit Neu;', TAtlasTextEncoding.Utf8)),
      TAtlasFileChange.Deleted(OldUnit, 'P.dproj', OldContent),
      TAtlasFileChange.Modified(Dpr, Content('uses Alt;', TAtlasTextEncoding.Utf8),
        Content('uses Neu;', TAtlasTextEncoding.Utf8))]));
    Report := Journal.Undo;
    Assert.IsTrue(Report.Complete);
    Assert.IsFalse(TFile.Exists(NewUnit), 'neue Unit in den Papierkorb');
    Assert.AreEqual('Neu.pas', Recycled[0]);
    Assert.AreEqual('Neu.pas@P.dproj', Removed[0]);
    Assert.IsTrue(TFile.Exists(OldUnit), 'gelöschte Unit wiederhergestellt');
    Assert.AreEqual('Alt.pas@P.dproj', Added[0]);
    Assert.AreEqual(Integer(Length('unit Alt; // Grüße')), Integer(Length(TFile.ReadAllBytes(OldUnit))), 'ANSI wie vorher');
    Assert.AreEqual('uses Alt;', TEncoding.UTF8.GetString(TFile.ReadAllBytes(Dpr)));
    // Wiederherstellen: neue Unit wieder da, alte wieder weg (Papierkorb, nie liegen lassen).
    Assert.IsTrue(Journal.Redo.Complete);
    Assert.AreEqual('unit Neu;', TEncoding.UTF8.GetString(TFile.ReadAllBytes(NewUnit)));
    Assert.IsFalse(TFile.Exists(OldUnit));
    Assert.AreEqual('Alt.pas', Recycled[1]);
    // Löschen statt Papierkorb.
    Options := TAtlasUndoOptions.Defaults;
    Options.NewFiles := TAtlasNewFilesMode.Delete;
    Journal.Options := Options;
    Assert.IsTrue(Journal.Undo.Complete);
    Assert.IsFalse(TFile.Exists(NewUnit));
    Assert.AreEqual(2, Integer(Recycled.Count), 'gelöscht, nicht im Papierkorb');
    // Behalten: aus dem Projekt ausgetragen, Datei bleibt.
    Assert.IsTrue(Journal.Redo.Complete);
    Options.NewFiles := TAtlasNewFilesMode.Keep;
    Journal.Options := Options;
    Assert.IsTrue(Journal.Undo.Complete);
    Assert.IsTrue(TFile.Exists(NewUnit));
    Assert.AreEqual('Neu.pas@P.dproj', Removed[Removed.Count - 1]);
    // Behaltene Datei ist beim Wiederherstellen schon genau so da.
    Assert.IsTrue(Journal.Redo.Complete);
    // Gelöschte Datei, die inzwischen wieder jemand angelegt hat: Konflikt.
    TFile.WriteAllBytes(OldUnit, TEncoding.UTF8.GetBytes('unit Alt; // neu geschrieben'));
    Options.OnConflict := TAtlasUndoConflictMode.Abort;
    Journal.Options := Options;
    Report := Journal.Undo;
    Assert.IsTrue(Report.Aborted);
    Assert.AreEqual(Ord(TAtlasUndoProblemKind.Exists), Ord(Report.Conflicts[0].Kind));
    Assert.IsTrue(TFile.Exists(NewUnit), 'abgebrochen: nichts geändert');
  finally
    Journal.Free;
    Recycled.Free;
    Removed.Free;
    Added.Free;
  end;
end;

procedure TAtlasUndoJournalTests.ConflictPartialAndAbort;
var
  Target: TMemoryTarget;
  TargetRef: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
  Report: TAtlasUndoReport;
  Options: TAtlasUndoOptions;
  ChangeSet: TAtlasChangeSet;
begin
  Target := TMemoryTarget.Create;
  TargetRef := Target;
  Journal := TAtlasUndoJournal.Create(TargetRef);
  try
    Apply(Journal, Target, 'Umbenennen', ['A.pas', 'Alt'#10, 'Neu'#10, 'B.pas', 'x Alt'#10, 'x Neu'#10, 'C.pas',
      'Alt'#10, 'Neu'#10]);
    // B nach der Aktion an derselben Stelle von Hand geändert, C fehlt inzwischen.
    Target.Put('B.pas', 'x Neu2'#10);
    Target.Files.Remove('C.pas');
    Options := TAtlasUndoOptions.Defaults;
    Options.OnConflict := TAtlasUndoConflictMode.Abort;
    Journal.Options := Options;
    Report := Journal.Undo;
    Assert.IsTrue(Report.Aborted);
    Assert.AreEqual(2, Integer(Length(Report.Conflicts)));
    Assert.AreEqual(0, Integer(Length(Report.Done)));
    Assert.AreEqual('Neu'#10, Target.Text('A.pas'), 'abgebrochen: A unverändert');
    // Teilweise: nur A; B und C bleiben, wie sie sind.
    Journal.Options := TAtlasUndoOptions.Defaults;
    Report := Journal.Undo;
    Assert.IsFalse(Report.Aborted);
    Assert.IsFalse(Report.Complete);
    Assert.AreEqual(1, Integer(Length(Report.Done)));
    Assert.AreEqual('B.pas', Report.Conflicts[0].FileName);
    Assert.AreEqual(Ord(TAtlasUndoProblemKind.ChangedSince), Ord(Report.Conflicts[0].Kind));
    Assert.AreEqual(Ord(TAtlasUndoProblemKind.Missing), Ord(Report.Conflicts[1].Kind));
    Assert.AreEqual('Alt'#10, Target.Text('A.pas'));
    Assert.AreEqual('x Neu2'#10, Target.Text('B.pas'), 'Benutzerarbeit bleibt');
    Assert.IsTrue(Journal.Find(1, ChangeSet));
    Assert.AreEqual(Ord(TAtlasChangeSetState.PartlyUndone), Ord(ChangeSet.State));
    // Noch einmal: A ist schon zurück, B und C weiter Konflikte.
    Assert.AreEqual(1, Journal.LastUndoable);
    Report := Journal.Undo;
    Assert.AreEqual(0, Integer(Length(Report.Done)));
    Assert.AreEqual(2, Integer(Length(Report.Conflicts)));
    // Ein Schreibfehler zählt als Fehler der Datei; die anderen laufen weiter.
    Target.Put('B.pas', 'x Neu'#10);
    Target.Put('C.pas', 'Neu'#10);
    Target.FailOn := 'C.pas';
    Report := Journal.Undo;
    Assert.AreEqual(1, Integer(Length(Report.Done)));
    Assert.AreEqual(1, Integer(Length(Report.Errors)));
    Assert.AreEqual('schreibgeschützt', Report.Errors[0].Message);
    Assert.AreEqual('x Alt'#10, Target.Text('B.pas'));
  finally
    Journal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.OlderSetWhilePlacesUnchanged;
const
  Base = '1'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'8'#10;
var
  Target: TMemoryTarget;
  TargetRef: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
  Report: TAtlasUndoReport;
begin
  Target := TMemoryTarget.Create;
  TargetRef := Target;
  Journal := TAtlasUndoJournal.Create(TargetRef);
  try
    // Satz 1 ändert Zeile 1 in A und B, Satz 2 Zeile 8 in A und C.
    Apply(Journal, Target, 'Eins', ['A.pas', Base, 'eins'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'8'#10, 'B.pas',
      'b', 'B']);
    Apply(Journal, Target, 'Zwei', ['A.pas', Target.Text('A.pas'),
      'eins'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'acht'#10, 'C.pas', 'c', 'C']);
    // Den älteren Satz zurücknehmen: Seine Stellen sind unverändert, Satz 2 bleibt erhalten.
    Report := Journal.Undo(1);
    Assert.IsTrue(Report.Complete);
    Assert.AreEqual('1'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'acht'#10, Target.Text('A.pas'));
    Assert.AreEqual('b', Target.Text('B.pas'));
    Assert.AreEqual('C', Target.Text('C.pas'));
    // Satz 2 lässt sich danach trotzdem zurücknehmen und Satz 1 wiederherstellen.
    Assert.IsTrue(Journal.Undo(2).Complete);
    Assert.AreEqual(Base, Target.Text('A.pas'));
    Assert.IsTrue(Journal.Redo(1).Complete);
    Assert.AreEqual('eins'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'8'#10, Target.Text('A.pas'));
    // Überschneiden sich die Stellen, ist der ältere Satz ein Konflikt.
    Apply(Journal, Target, 'Drei', ['A.pas', Target.Text('A.pas'),
      'EINS'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'8'#10, 'D.pas', 'd', 'D']);
    Report := Journal.Undo(1);
    Assert.AreEqual(1, Integer(Length(Report.Conflicts)));
    Assert.AreEqual('A.pas', Report.Conflicts[0].FileName);
    Assert.IsTrue(Journal.Undo(99).NotFound);
  finally
    Journal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.RedoFollowsUndoOrder;
var
  Target: TMemoryTarget;
  TargetRef: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
begin
  Target := TMemoryTarget.Create;
  TargetRef := Target;
  Journal := TAtlasUndoJournal.Create(TargetRef);
  try
    Apply(Journal, Target, 'Eins', ['A.pas', 'a', 'a1', 'B.pas', 'b', 'b1']);
    Apply(Journal, Target, 'Zwei', ['C.pas', 'c', 'c1', 'D.pas', 'd', 'd1']);
    Assert.AreEqual(2, Journal.Undo.SetId);
    Assert.AreEqual(1, Journal.Undo.SetId);
    // Wiederherstellen in umgekehrter Reihenfolge.
    Assert.AreEqual(1, Journal.Redo.SetId);
    Assert.AreEqual(2, Journal.LastRedoable);
    // Eine neue Aktion leert die Wiederherstellen-Liste; über die Kennung geht es weiter.
    Apply(Journal, Target, 'Drei', ['E.pas', 'e', 'e1', 'F.pas', 'f', 'f1']);
    Assert.AreEqual(0, Journal.LastRedoable);
    Assert.IsTrue(Journal.Redo.NotFound);
    Assert.IsTrue(Journal.Redo(2).Complete);
    Assert.AreEqual('d1', Target.Text('D.pas'));
  finally
    Journal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.PersistsWithSizeLimit;
var
  Target: TMemoryTarget;
  TargetRef: IAtlasUndoTarget;
  Journal, Restarted: TAtlasUndoJournal;
  Store: TAtlasUndoFileStore;
  StoreRef: IAtlasUndoStore;
  Sets: TArray<TAtlasChangeSet>;
  Options: TAtlasUndoOptions;
  Big: string;
begin
  Target := TMemoryTarget.Create;
  TargetRef := Target;
  Store := TAtlasUndoFileStore.Create(FFolder, 1024 * 1024);
  StoreRef := Store;
  Journal := TAtlasUndoJournal.Create(TargetRef);
  try
    Journal.Store := StoreRef;
    Apply(Journal, Target, 'Eins', ['A.pas', 'a'#13#10, 'a1'#13#10, 'B.pas', 'b', 'b1']);
    Journal.Add('Neu', [TAtlasFileChange.Created('N.pas', 'P.dproj', Content('n', TAtlasTextEncoding.Utf16LE)),
      TAtlasFileChange.Deleted('O.pas', '', Content('o', TAtlasTextEncoding.Ansi))]);
    Journal.Undo;
    Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(FFolder, 'set-*.json'))));
  finally
    Journal.Free;
  end;
  // Neustart: Sätze, Zustände, Kodierungen und Zeilenenden sind wieder da.
  Restarted := TAtlasUndoJournal.Create(TargetRef);
  try
    Restarted.Store := StoreRef;
    Restarted.Load;
    Sets := Restarted.Sets;
    Assert.AreEqual(2, Integer(Length(Sets)));
    Assert.AreEqual('Neu', Sets[0].Action);
    Assert.AreEqual(Ord(TAtlasChangeSetState.Undone), Ord(Sets[0].State));
    Assert.AreEqual(Ord(TAtlasFileChangeKind.Created), Ord(Sets[0].Files[0].Kind));
    Assert.AreEqual('P.dproj', Sets[0].Files[0].Project);
    Assert.AreEqual(Ord(TAtlasTextEncoding.Utf16LE), Ord(Sets[0].Files[0].After.Encoding));
    Assert.AreEqual(Ord(TAtlasTextEncoding.Ansi), Ord(Sets[0].Files[1].Before.Encoding));
    Assert.AreEqual('a'#13#10, Sets[1].Files[0].Before.Text);
    Assert.IsTrue(Abs(Sets[1].Time - Now) < 1 / 24, 'Zeit');
    Assert.AreEqual(3, Restarted.Add('Weiter', [TAtlasFileChange.Created('X.pas', '', Content('x'))]),
      'Kennungen laufen weiter');
    // Tiefe: der älteste Satz fällt auch aus dem Speicher.
    Options := TAtlasUndoOptions.Defaults;
    Options.Depth := 2;
    Restarted.Options := Options;
    Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(FFolder, 'set-*.json'))));
    Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'set-000001.json')));
    // Größe: ein zu großer Satz wird nicht gesichert, ältere fallen weg, bis alles passt.
    Options.Depth := 10;
    Restarted.Options := Options;
    Store.MaxBytes := 2048;
    Big := StringOfChar('x', 4096);
    Restarted.Add('Groß', [TAtlasFileChange.Created('G.pas', '', Content(Big))]);
    Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'set-000004.json')));
    Restarted.Add('Mittel', [TAtlasFileChange.Created('M.pas', '', Content(StringOfChar('m', 1800)))]);
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'set-000005.json')));
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FFolder, 'set-*.json'))), 'nur der neueste passt');
    Restarted.Clear;
    Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FFolder, 'set-*.json'))));
  finally
    Restarted.Free;
  end;
end;

procedure TAtlasUndoJournalTests.LogHasNoNamesOrSource;
var
  Target: TMemoryTarget;
  TargetRef: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
  Lines: TList<string>;
  Line: string;
begin
  Target := TMemoryTarget.Create;
  TargetRef := Target;
  Lines := TList<string>.Create;
  Journal := TAtlasUndoJournal.Create(TargetRef);
  try
    Journal.OnLog :=
      procedure(AText: string)
      begin
        Lines.Add(AText);
      end;
    Apply(Journal, Target, 'Umbenennen: GeheimesFeld → Anderes', ['C:\Kunde\Geheim.pas', 'GeheimesFeld := 42;',
      'Anderes := 42;', 'C:\Kunde\Zwei.pas', 'X := GeheimesFeld;', 'X := Anderes;']);
    Target.Put('C:\Kunde\Zwei.pas', 'Y := Anderes;');
    Journal.Undo;
    Journal.Redo;
    Assert.IsTrue(Lines.Count >= 3);
    for Line in Lines do
    begin
      Assert.IsFalse(Line.Contains('Kunde'), Line);
      Assert.IsFalse(Line.Contains('Geheim'), Line);
      Assert.IsFalse(Line.Contains('Anderes'), Line);
      Assert.IsFalse(Line.Contains('42'), Line);
      Assert.IsFalse(Line.Contains('.pas'), Line);
    end;
    Assert.AreEqual(3, Integer(Length(TAtlasUndoJournal.Diff(Journal.Sets[0].Files[0]))));
  finally
    Journal.Free;
    Lines.Free;
  end;
end;

procedure TAtlasUndoJournalTests.DisabledRecordsNothing;
var
  Target: TMemoryTarget;
  TargetRef: IAtlasUndoTarget;
  Journal: TAtlasUndoJournal;
  Options: TAtlasUndoOptions;
begin
  Target := TMemoryTarget.Create;
  TargetRef := Target;
  Journal := TAtlasUndoJournal.Create(TargetRef);
  try
    Options := TAtlasUndoOptions.Defaults;
    Options.Enabled := False;
    Journal.Options := Options;
    // Die Aktion schreibt wie bisher, nur ohne Protokoll.
    Assert.AreEqual(0, Apply(Journal, Target, 'Zwei', ['A.pas', 'a', 'b', 'B.pas', 'c', 'd']));
    Assert.AreEqual('b', Target.Text('A.pas'));
    Assert.AreEqual(0, Journal.Count);
    Assert.IsTrue(Journal.Undo.Disabled);
    Assert.IsTrue(Journal.Redo.Disabled);
  finally
    Journal.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinePatchTests);
  TDUnitX.RegisterTestFixture(TAtlasUndoJournalTests);

end.
