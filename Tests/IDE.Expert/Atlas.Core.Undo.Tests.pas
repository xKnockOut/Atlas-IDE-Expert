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
  begin
    raise EInOutError.Create('schreibgeschützt');
  end;
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
  mValue: TAtlasTextFileContent;
begin
  Result := '<fehlt>';
  if Files.TryGetValue(AFileName, mValue) then
  begin
    Result := mValue.Text;
  end;
end;

function TMemoryTarget.WriteCount(const AFileName: string): Integer;
begin
  if not Writes.TryGetValue(AFileName, Result) then
  begin
    Result := 0;
  end;
end;

/// <summary>Satz für AFiles (Name, vorher, nachher) anlegen und den Stand „nachher“ ins Ziel schreiben.</summary>
function Apply(AJournal: TAtlasUndoJournal; ATarget: TMemoryTarget; const AAction: string;
  const AFiles: array of string): Integer;
var
  mIndex: Integer;
  mChanges: TArray<TAtlasFileChange>;
begin
  mChanges := nil;
  mIndex := 0;
  while mIndex + 2 <= High(AFiles) do
  begin
    mChanges := mChanges + [TAtlasFileChange.Modified(AFiles[mIndex], Content(AFiles[mIndex + 1]),
      Content(AFiles[mIndex + 2]))];
    ATarget.Put(AFiles[mIndex], AFiles[mIndex + 2]);
    Inc(mIndex, 3);
  end;
  Result := AJournal.Add(AAction, mChanges);
end;

{ TAtlasLinePatchTests }

procedure TAtlasLinePatchTests.SplitsLinesWithTheirEnds;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasLinePatch.SplitLines('a'#13#10'b'#10'c'#13'd');
  Assert.AreEqual(4, Integer(Length(mLines)));
  Assert.AreEqual('a'#13#10, mLines[0]);
  Assert.AreEqual('b'#10, mLines[1]);
  Assert.AreEqual('c'#13, mLines[2]);
  Assert.AreEqual('d', mLines[3]);
  Assert.AreEqual(1, Integer(Length(TAtlasLinePatch.SplitLines('x'#13#10))));
  Assert.AreEqual(0, Integer(Length(TAtlasLinePatch.SplitLines(''))));
end;

procedure TAtlasLinePatchTests.FindsChangedBlocks;
var
  mHunks: TArray<TAtlasLineHunk>;
begin
  mHunks := TAtlasLinePatch.Hunks(['a', 'b', 'c', 'd', 'e'], ['a', 'B', 'c', 'd', 'x', 'e']);
  Assert.AreEqual(2, Integer(Length(mHunks)));
  Assert.AreEqual(1, mHunks[0].OldStart);
  Assert.AreEqual(1, mHunks[0].OldCount);
  Assert.AreEqual(1, mHunks[0].NewCount);
  Assert.AreEqual(4, mHunks[1].OldStart);
  Assert.AreEqual(0, mHunks[1].OldCount);
  Assert.AreEqual(1, mHunks[1].NewCount);
  Assert.AreEqual(4, mHunks[1].NewStart);
  Assert.AreEqual(0, Integer(Length(TAtlasLinePatch.Hunks(['a'], ['a']))));
end;

procedure TAtlasLinePatchTests.RebaseKeepsLaterEditsElsewhere;
const
  cBefore = 'unit A;'#13#10'var'#13#10'  Alt: Integer;'#13#10'begin'#13#10'  Alt := 1;'#13#10'end.'#13#10;
  cAfter = 'unit A;'#13#10'var'#13#10'  Neu: Integer;'#13#10'begin'#13#10'  Neu := 1;'#13#10'end.'#13#10;
var
  mCurrent, mUndone: string;
begin
  Assert.IsTrue(TAtlasLinePatch.Rebase(cAfter, cBefore, cAfter, mUndone));
  Assert.AreEqual(cBefore, mUndone);
  // Später eine Zeile am Ende ergänzt (nicht angrenzend): bleibt beim Zurücknehmen.
  mCurrent := cAfter + '// Ende'#13#10;
  Assert.IsTrue(TAtlasLinePatch.Rebase(cAfter, cBefore, mCurrent, mUndone));
  Assert.AreEqual(cBefore + '// Ende'#13#10, mUndone);
  // Schon von Hand zurückgenommen: Ziel.
  Assert.IsTrue(TAtlasLinePatch.Rebase(cAfter, cBefore, cBefore, mUndone));
  Assert.AreEqual(cBefore, mUndone);
end;

procedure TAtlasLinePatchTests.RebaseRefusesTouchedPlaces;
const
  cBefore = 'a'#10'b'#10'c'#10'd'#10'e'#10'f'#10;
  cAfter = 'a'#10'B'#10'c'#10'd'#10'e'#10'f'#10;
var
  Result: string;
begin
  // Die geänderte Zeile selbst und eine direkt angrenzende sind Konflikte.
  Assert.IsFalse(TAtlasLinePatch.Rebase(cAfter, cBefore, 'a'#10'BB'#10'c'#10'd'#10'e'#10'f'#10, Result));
  Assert.IsFalse(TAtlasLinePatch.Rebase(cAfter, cBefore, 'a'#10'B'#10'C'#10'd'#10'e'#10'f'#10, Result));
  Assert.AreEqual('', Result);
  // Zwei Zeilen Abstand: kein Konflikt.
  Assert.IsTrue(TAtlasLinePatch.Rebase(cAfter, cBefore, 'a'#10'B'#10'c'#10'D'#10'e'#10'f'#10, Result));
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
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TAtlasUndoJournalTests.RecordsOnlyMultiFileActions;
var
  mTarget: TMemoryTarget;
  mTargetRef: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
  mChangeSet: TAtlasChangeSet;
begin
  mTarget := TMemoryTarget.Create;
  mTargetRef := mTarget;
  mJournal := TAtlasUndoJournal.Create(mTargetRef);
  try
    // Eine Datei: Strg+Z im Puffer genügt.
    Assert.AreEqual(0, Apply(mJournal, mTarget, 'Eins', ['A.pas', 'a', 'b']));
    // Unveränderte Dateien zählen nicht.
    Assert.AreEqual(0, Apply(mJournal, mTarget, 'Gleich', ['A.pas', 'b', 'c', 'B.pas', 'x', 'x']));
    Assert.AreEqual(1, Apply(mJournal, mTarget, 'Zwei', ['A.pas', 'c', 'd', 'B.pas', 'x', 'y', 'C.pas', 'z', 'z']));
    Assert.IsTrue(mJournal.Find(1, mChangeSet));
    Assert.AreEqual('Zwei', mChangeSet.Action);
    Assert.AreEqual(2, Integer(Length(mChangeSet.Files)));
    Assert.AreEqual(Ord(TAtlasChangeSetState.Applied), Ord(mChangeSet.State));
    // Eine neue Datei allein ist schon eine Dateioperation.
    Assert.AreEqual(2, mJournal.Add('Neue Unit', [TAtlasFileChange.Created('N.pas', 'P.dproj', Content('unit N;'))]));
    Assert.AreEqual(2, mJournal.LastUndoable);
    Assert.AreEqual(2, mJournal.Sets[0].Id, 'neueste zuerst');
    // Tiefe: nur die letzten Sätze bleiben.
    mJournal.Options := TAtlasUndoOptions.Defaults;
    mJournal.Add('Drei', [TAtlasFileChange.Created('M.pas', '', Content('m'))]);
    Assert.AreEqual(3, Integer(mJournal.Count));
    mJournal.Options := Default(TAtlasUndoOptions);
    Assert.AreEqual(1, Integer(mJournal.Count), 'Tiefe mindestens 1');
    Assert.AreEqual(3, mJournal.Sets[0].Id);
  finally
    mJournal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.UndoAndRedoOpenFilesAndForm;
const
  cUnit1Before = 'unit Unit1;'#13#10'procedure Alt;'#13#10'implementation'#13#10'end.';
  cUnit1After = 'unit Unit1;'#13#10'procedure Neu;'#13#10'implementation'#13#10'end.';
  cFormBefore = 'object Form1: TForm1'#13#10'  OnClick = Alt'#13#10'end'#13#10;
  cFormAfter = 'object Form1: TForm1'#13#10'  OnClick = Neu'#13#10'end'#13#10;
var
  mTarget: TMemoryTarget;
  mTargetRef: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
  mReport: TAtlasUndoReport;
  mChangeSet: TAtlasChangeSet;
  mId: Integer;
begin
  mTarget := TMemoryTarget.Create;
  mTargetRef := mTarget;
  mJournal := TAtlasUndoJournal.Create(mTargetRef);
  try
    // Umbenennen über drei Units und eine DFM.
    mId := Apply(mJournal, mTarget, 'Umbenennen: Alt → Neu', ['Unit1.pas', cUnit1Before, cUnit1After, 'Unit2.pas',
      'uses Unit1;'#10'Alt;'#10, 'uses Unit1;'#10'Neu;'#10, 'Unit3.pas', 'Alt', 'Neu', 'Unit1.dfm', cFormBefore,
      cFormAfter]);
    Assert.AreEqual(1, mId);
    mReport := mJournal.Undo;
    Assert.IsTrue(mReport.Complete);
    Assert.AreEqual('Umbenennen: Alt → Neu', mReport.Action);
    Assert.AreEqual(4, Integer(Length(mReport.Done)));
    Assert.AreEqual(cUnit1Before, mTarget.Text('Unit1.pas'));
    Assert.AreEqual('uses Unit1;'#10'Alt;'#10, mTarget.Text('Unit2.pas'));
    Assert.AreEqual('Alt', mTarget.Text('Unit3.pas'));
    Assert.AreEqual(cFormBefore, mTarget.Text('Unit1.dfm'));
    // Je Datei genau ein Schreibvorgang = ein Rückgängig-Schritt im Puffer.
    Assert.AreEqual(1, mTarget.WriteCount('Unit1.pas'));
    Assert.AreEqual(1, mTarget.WriteCount('Unit1.dfm'));
    Assert.IsTrue(mJournal.Find(mId, mChangeSet));
    Assert.AreEqual(Ord(TAtlasChangeSetState.Undone), Ord(mChangeSet.State));
    Assert.AreEqual(0, mJournal.LastUndoable);
    // Noch einmal: nichts mehr zurückzunehmen.
    Assert.IsTrue(mJournal.Undo.NotFound);
    Assert.AreEqual(mId, mJournal.LastRedoable);
    mReport := mJournal.Redo;
    Assert.IsTrue(mReport.Complete);
    Assert.IsTrue(mReport.Redo);
    Assert.AreEqual(cUnit1After, mTarget.Text('Unit1.pas'));
    Assert.AreEqual(cFormAfter, mTarget.Text('Unit1.dfm'));
    Assert.AreEqual(2, mTarget.WriteCount('Unit3.pas'));
    Assert.AreEqual(0, mJournal.LastRedoable);
    Assert.AreEqual(mId, mJournal.LastUndoable);
  finally
    mJournal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.ClosedFilesKeepEncodingAndLineEnds;
var
  mDisk: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
  mUtf16, mAnsi, mMixed, mForm: string;
  mUtf16Before, mAnsiBefore, mMixedBefore, mFormBefore: TBytes;
  mChanges: TArray<TAtlasFileChange>;

  function Change(const AFileName, ANewText: string; out AOriginal: TBytes): TAtlasFileChange;
  var
    mBefore, mAfter: TAtlasTextFileContent;
  begin
    AOriginal := TFile.ReadAllBytes(AFileName);
    mBefore := TAtlasTextFile.Decode(AOriginal, 1252);
    mAfter := mBefore;
    mAfter.Text := ANewText;
    TAtlasTextFile.Save(AFileName, mAfter);
    Result := TAtlasFileChange.Modified(AFileName, mBefore, mAfter);
  end;

begin
  mUtf16 := TPath.Combine(FFolder, 'Utf16.pas');
  mAnsi := TPath.Combine(FFolder, 'Ansi.pas');
  mMixed := TPath.Combine(FFolder, 'Mixed.pas');
  mForm := TPath.Combine(FFolder, 'Form.dfm');
  // Vorgabe-Codepage wie in einem Projekt mit ANSI-Quelltexten (#121), unabhängig vom System.
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.json'), '{"encoding": "windows-1252"}');
  TFile.WriteAllBytes(mUtf16, TBytes.Create($FF, $FE) + TEncoding.Unicode.GetBytes('Größe := 1;'#13#10'Alt;'#13#10));
  TFile.WriteAllBytes(mAnsi, TBytes.Create(Ord('A'), Ord('l'), Ord('t'), $FC, 10, Ord('x'), 10));
  TFile.WriteAllBytes(mMixed, TEncoding.UTF8.GetBytes('Alt'#13#10'zwei'#10'drei'));
  TFile.WriteAllBytes(mForm, TEncoding.UTF8.GetBytes('object F: TF'#13#10'  OnClick = Alt'#13#10'end'#13#10));
  mChanges := [Change(mUtf16, 'Größe := 1;'#13#10'Neu;'#13#10, mUtf16Before),
    Change(mAnsi, 'Neu'#$00FC#10'x'#10, mAnsiBefore),
    Change(mMixed, 'Neu'#13#10'zwei'#10'drei', mMixedBefore),
    Change(mForm, 'object F: TF'#13#10'  OnClick = Neu'#13#10'end'#13#10, mFormBefore)];
  mDisk := TAtlasUndoDiskTarget.Create;
  mJournal := TAtlasUndoJournal.Create(mDisk);
  try
    Assert.AreEqual(1, mJournal.Add('Umbenennen', mChanges));
    Assert.IsTrue(mJournal.Undo.Complete);
    // Byte für Byte wie vorher: BOM, Kodierung, Umlaute, CRLF/LF gemischt, fehlende letzte Zeilenschaltung.
    Assert.AreEqual(TEncoding.Unicode.GetString(mUtf16Before), TEncoding.Unicode.GetString(TFile.ReadAllBytes(mUtf16)));
    Assert.AreEqual(Integer(Length(mUtf16Before)), Integer(Length(TFile.ReadAllBytes(mUtf16))));
    Assert.AreEqual(Integer(Length(mAnsiBefore)), Integer(Length(TFile.ReadAllBytes(mAnsi))));
    Assert.AreEqual($FC, Integer(TFile.ReadAllBytes(mAnsi)[3]));
    Assert.AreEqual(TEncoding.UTF8.GetString(mMixedBefore), TEncoding.UTF8.GetString(TFile.ReadAllBytes(mMixed)));
    Assert.AreEqual(TEncoding.UTF8.GetString(mFormBefore), TEncoding.UTF8.GetString(TFile.ReadAllBytes(mForm)));
    Assert.IsTrue(mJournal.Redo.Complete);
    Assert.AreEqual('Neu'#13#10'zwei'#10'drei', TEncoding.UTF8.GetString(TFile.ReadAllBytes(mMixed)));
    Assert.AreEqual($FF, Integer(TFile.ReadAllBytes(mUtf16)[0]), 'UTF-16 bleibt');
  finally
    mJournal.Free;
  end;
end;

/// <summary>Projektänderungen und Papierkorb des Datenträgerziels landen in den Listen.</summary>
procedure WireDiskLists(const ADisk: TAtlasUndoDiskTarget; const AAdded, ARemoved, ARecycled: TList<string>);
begin
  ADisk.OnAddToProject :=
    procedure(const AFileName, AProject: string)
    begin
      AAdded.Add(ExtractFileName(AFileName) + '@' + AProject);
    end;
  ADisk.OnRemoveFromProject :=
    procedure(const AFileName, AProject: string)
    begin
      ARemoved.Add(ExtractFileName(AFileName) + '@' + AProject);
    end;
  ADisk.OnRecycle :=
    procedure(AFileName: string)
    begin
      ARecycled.Add(ExtractFileName(AFileName));
      TFile.Delete(AFileName);
    end;
end;

/// <summary>Neue Dateien löschen oder behalten; eine wieder angelegte gelöschte Datei ist ein Konflikt.</summary>
procedure AssertNewFilesModes(const AJournal: TAtlasUndoJournal; const ARecycled, ARemoved: TList<string>;
  const ANewUnit, AOldUnit: string);
var
  mOptions: TAtlasUndoOptions;
  mReport: TAtlasUndoReport;
begin
  // Löschen statt Papierkorb.
  mOptions := TAtlasUndoOptions.Defaults;
  mOptions.NewFiles := TAtlasNewFilesMode.Delete;
  AJournal.Options := mOptions;
  Assert.IsTrue(AJournal.Undo.Complete);
  Assert.IsFalse(TFile.Exists(ANewUnit));
  Assert.AreEqual(2, Integer(ARecycled.Count), 'gelöscht, nicht im Papierkorb');
  // Behalten: aus dem Projekt ausgetragen, Datei bleibt.
  Assert.IsTrue(AJournal.Redo.Complete);
  mOptions.NewFiles := TAtlasNewFilesMode.Keep;
  AJournal.Options := mOptions;
  Assert.IsTrue(AJournal.Undo.Complete);
  Assert.IsTrue(TFile.Exists(ANewUnit));
  Assert.AreEqual('Neu.pas@P.dproj', ARemoved[ARemoved.Count - 1]);
  // Behaltene Datei ist beim Wiederherstellen schon genau so da.
  Assert.IsTrue(AJournal.Redo.Complete);
  // Gelöschte Datei, die inzwischen wieder jemand angelegt hat: Konflikt.
  TFile.WriteAllBytes(AOldUnit, TEncoding.UTF8.GetBytes('unit Alt; // neu geschrieben'));
  mOptions.OnConflict := TAtlasUndoConflictMode.Abort;
  AJournal.Options := mOptions;
  mReport := AJournal.Undo;
  Assert.IsTrue(mReport.Aborted);
  Assert.AreEqual(Ord(TAtlasUndoProblemKind.Exists), Ord(mReport.Conflicts[0].Kind));
  Assert.IsTrue(TFile.Exists(ANewUnit), 'abgebrochen: nichts geändert');
end;

procedure TAtlasUndoJournalTests.NewAndDeletedFiles;
var
  mDisk: TAtlasUndoDiskTarget;
  mDiskRef: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
  mNewUnit, mOldUnit, mDpr: string;
  mAdded, mRemoved, mRecycled: TList<string>;
  mOldContent: TAtlasTextFileContent;
  mReport: TAtlasUndoReport;
begin
  mNewUnit := TPath.Combine(FFolder, 'Neu.pas');
  mOldUnit := TPath.Combine(FFolder, 'Alt.pas');
  mDpr := TPath.Combine(FFolder, 'P.dpr');
  mAdded := TList<string>.Create;
  mRemoved := TList<string>.Create;
  mRecycled := TList<string>.Create;
  mDisk := TAtlasUndoDiskTarget.Create;
  mDiskRef := mDisk;
  WireDiskLists(mDisk, mAdded, mRemoved, mRecycled);
  mJournal := TAtlasUndoJournal.Create(mDiskRef);
  try
    // Aktion: neue Unit angelegt, alte gelöscht (ANSI-Umlaut bleibt), .dpr geändert.
    TFile.WriteAllBytes(mNewUnit, TEncoding.UTF8.GetBytes('unit Neu;'));
    TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.json'), '{"encoding": "windows-1252"}');
    mOldContent := Content('unit Alt; // Grüße', TAtlasTextEncoding.Ansi);
    mOldContent.CodePage := 1252;
    TFile.WriteAllBytes(mDpr, TEncoding.UTF8.GetBytes('uses Neu;'));
    Assert.AreEqual(1, mJournal.Add('Unit verschieben', [
      TAtlasFileChange.Created(mNewUnit, 'P.dproj', Content('unit Neu;', TAtlasTextEncoding.Utf8)),
      TAtlasFileChange.Deleted(mOldUnit, 'P.dproj', mOldContent),
      TAtlasFileChange.Modified(mDpr, Content('uses Alt;', TAtlasTextEncoding.Utf8),
        Content('uses Neu;', TAtlasTextEncoding.Utf8))]));
    mReport := mJournal.Undo;
    Assert.IsTrue(mReport.Complete);
    Assert.IsFalse(TFile.Exists(mNewUnit), 'neue Unit in den Papierkorb');
    Assert.AreEqual('Neu.pas', mRecycled[0]);
    Assert.AreEqual('Neu.pas@P.dproj', mRemoved[0]);
    Assert.IsTrue(TFile.Exists(mOldUnit), 'gelöschte Unit wiederhergestellt');
    Assert.AreEqual('Alt.pas@P.dproj', mAdded[0]);
    Assert.AreEqual(Integer(Length('unit Alt; // Grüße')), Integer(Length(TFile.ReadAllBytes(mOldUnit))), 'ANSI wie vorher');
    Assert.AreEqual('uses Alt;', TEncoding.UTF8.GetString(TFile.ReadAllBytes(mDpr)));
    // Wiederherstellen: neue Unit wieder da, alte wieder weg (Papierkorb, nie liegen lassen).
    Assert.IsTrue(mJournal.Redo.Complete);
    Assert.AreEqual('unit Neu;', TEncoding.UTF8.GetString(TFile.ReadAllBytes(mNewUnit)));
    Assert.IsFalse(TFile.Exists(mOldUnit));
    Assert.AreEqual('Alt.pas', mRecycled[1]);
    AssertNewFilesModes(mJournal, mRecycled, mRemoved, mNewUnit, mOldUnit);
  finally
    mJournal.Free;
    mRecycled.Free;
    mRemoved.Free;
    mAdded.Free;
  end;
end;

procedure TAtlasUndoJournalTests.ConflictPartialAndAbort;
var
  mTarget: TMemoryTarget;
  mTargetRef: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
  mReport: TAtlasUndoReport;
  mOptions: TAtlasUndoOptions;
  mChangeSet: TAtlasChangeSet;
begin
  mTarget := TMemoryTarget.Create;
  mTargetRef := mTarget;
  mJournal := TAtlasUndoJournal.Create(mTargetRef);
  try
    Apply(mJournal, mTarget, 'Umbenennen', ['A.pas', 'Alt'#10, 'Neu'#10, 'B.pas', 'x Alt'#10, 'x Neu'#10, 'C.pas',
      'Alt'#10, 'Neu'#10]);
    // B nach der Aktion an derselben Stelle von Hand geändert, C fehlt inzwischen.
    mTarget.Put('B.pas', 'x Neu2'#10);
    mTarget.Files.Remove('C.pas');
    mOptions := TAtlasUndoOptions.Defaults;
    mOptions.OnConflict := TAtlasUndoConflictMode.Abort;
    mJournal.Options := mOptions;
    mReport := mJournal.Undo;
    Assert.IsTrue(mReport.Aborted);
    Assert.AreEqual(2, Integer(Length(mReport.Conflicts)));
    Assert.AreEqual(0, Integer(Length(mReport.Done)));
    Assert.AreEqual('Neu'#10, mTarget.Text('A.pas'), 'abgebrochen: A unverändert');
    // Teilweise: nur A; B und C bleiben, wie sie sind.
    mJournal.Options := TAtlasUndoOptions.Defaults;
    mReport := mJournal.Undo;
    Assert.IsFalse(mReport.Aborted);
    Assert.IsFalse(mReport.Complete);
    Assert.AreEqual(1, Integer(Length(mReport.Done)));
    Assert.AreEqual('B.pas', mReport.Conflicts[0].FileName);
    Assert.AreEqual(Ord(TAtlasUndoProblemKind.ChangedSince), Ord(mReport.Conflicts[0].Kind));
    Assert.AreEqual(Ord(TAtlasUndoProblemKind.Missing), Ord(mReport.Conflicts[1].Kind));
    Assert.AreEqual('Alt'#10, mTarget.Text('A.pas'));
    Assert.AreEqual('x Neu2'#10, mTarget.Text('B.pas'), 'Benutzerarbeit bleibt');
    Assert.IsTrue(mJournal.Find(1, mChangeSet));
    Assert.AreEqual(Ord(TAtlasChangeSetState.PartlyUndone), Ord(mChangeSet.State));
    // Noch einmal: A ist schon zurück, B und C weiter Konflikte.
    Assert.AreEqual(1, mJournal.LastUndoable);
    mReport := mJournal.Undo;
    Assert.AreEqual(0, Integer(Length(mReport.Done)));
    Assert.AreEqual(2, Integer(Length(mReport.Conflicts)));
    // Ein Schreibfehler zählt als Fehler der Datei; die anderen laufen weiter.
    mTarget.Put('B.pas', 'x Neu'#10);
    mTarget.Put('C.pas', 'Neu'#10);
    mTarget.FailOn := 'C.pas';
    mReport := mJournal.Undo;
    Assert.AreEqual(1, Integer(Length(mReport.Done)));
    Assert.AreEqual(1, Integer(Length(mReport.Errors)));
    Assert.AreEqual('schreibgeschützt', mReport.Errors[0].Message);
    Assert.AreEqual('x Alt'#10, mTarget.Text('B.pas'));
  finally
    mJournal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.OlderSetWhilePlacesUnchanged;
const
  cBase = '1'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'8'#10;
var
  mTarget: TMemoryTarget;
  mTargetRef: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
  mReport: TAtlasUndoReport;
begin
  mTarget := TMemoryTarget.Create;
  mTargetRef := mTarget;
  mJournal := TAtlasUndoJournal.Create(mTargetRef);
  try
    // Satz 1 ändert Zeile 1 in A und B, Satz 2 Zeile 8 in A und C.
    Apply(mJournal, mTarget, 'Eins', ['A.pas', cBase, 'eins'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'8'#10, 'B.pas',
      'b', 'B']);
    Apply(mJournal, mTarget, 'Zwei', ['A.pas', mTarget.Text('A.pas'),
      'eins'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'acht'#10, 'C.pas', 'c', 'C']);
    // Den älteren Satz zurücknehmen: Seine Stellen sind unverändert, Satz 2 bleibt erhalten.
    mReport := mJournal.Undo(1);
    Assert.IsTrue(mReport.Complete);
    Assert.AreEqual('1'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'acht'#10, mTarget.Text('A.pas'));
    Assert.AreEqual('b', mTarget.Text('B.pas'));
    Assert.AreEqual('C', mTarget.Text('C.pas'));
    // Satz 2 lässt sich danach trotzdem zurücknehmen und Satz 1 wiederherstellen.
    Assert.IsTrue(mJournal.Undo(2).Complete);
    Assert.AreEqual(cBase, mTarget.Text('A.pas'));
    Assert.IsTrue(mJournal.Redo(1).Complete);
    Assert.AreEqual('eins'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'8'#10, mTarget.Text('A.pas'));
    // Überschneiden sich die Stellen, ist der ältere Satz ein Konflikt.
    Apply(mJournal, mTarget, 'Drei', ['A.pas', mTarget.Text('A.pas'),
      'EINS'#10'2'#10'3'#10'4'#10'5'#10'6'#10'7'#10'8'#10, 'D.pas', 'd', 'D']);
    mReport := mJournal.Undo(1);
    Assert.AreEqual(1, Integer(Length(mReport.Conflicts)));
    Assert.AreEqual('A.pas', mReport.Conflicts[0].FileName);
    Assert.IsTrue(mJournal.Undo(99).NotFound);
  finally
    mJournal.Free;
  end;
end;

procedure TAtlasUndoJournalTests.RedoFollowsUndoOrder;
var
  mTarget: TMemoryTarget;
  mTargetRef: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
begin
  mTarget := TMemoryTarget.Create;
  mTargetRef := mTarget;
  mJournal := TAtlasUndoJournal.Create(mTargetRef);
  try
    Apply(mJournal, mTarget, 'Eins', ['A.pas', 'a', 'a1', 'B.pas', 'b', 'b1']);
    Apply(mJournal, mTarget, 'Zwei', ['C.pas', 'c', 'c1', 'D.pas', 'd', 'd1']);
    Assert.AreEqual(2, mJournal.Undo.SetId);
    Assert.AreEqual(1, mJournal.Undo.SetId);
    // Wiederherstellen in umgekehrter Reihenfolge.
    Assert.AreEqual(1, mJournal.Redo.SetId);
    Assert.AreEqual(2, mJournal.LastRedoable);
    // Eine neue Aktion leert die Wiederherstellen-Liste; über die Kennung geht es weiter.
    Apply(mJournal, mTarget, 'Drei', ['E.pas', 'e', 'e1', 'F.pas', 'f', 'f1']);
    Assert.AreEqual(0, mJournal.LastRedoable);
    Assert.IsTrue(mJournal.Redo.NotFound);
    Assert.IsTrue(mJournal.Redo(2).Complete);
    Assert.AreEqual('d1', mTarget.Text('D.pas'));
  finally
    mJournal.Free;
  end;
end;

/// <summary>Nach dem Neustart: beide Sätze mit Zustand, Art, Projekt, Kodierung, Zeilenenden und Zeit.</summary>
procedure AssertRestartedSets(const ASets: TArray<TAtlasChangeSet>);
begin
  Assert.AreEqual(2, Integer(Length(ASets)));
  Assert.AreEqual('Neu', ASets[0].Action);
  Assert.AreEqual(Ord(TAtlasChangeSetState.Undone), Ord(ASets[0].State));
  Assert.AreEqual(Ord(TAtlasFileChangeKind.Created), Ord(ASets[0].Files[0].Kind));
  Assert.AreEqual('P.dproj', ASets[0].Files[0].Project);
  Assert.AreEqual(Ord(TAtlasTextEncoding.Utf16LE), Ord(ASets[0].Files[0].After.Encoding));
  Assert.AreEqual(Ord(TAtlasTextEncoding.Ansi), Ord(ASets[0].Files[1].Before.Encoding));
  Assert.AreEqual('a'#13#10, ASets[1].Files[0].Before.Text);
  Assert.IsTrue(Abs(ASets[1].Time - Now) < 1 / 24, 'Zeit');
end;

procedure TAtlasUndoJournalTests.PersistsWithSizeLimit;
var
  mTarget: TMemoryTarget;
  mTargetRef: IAtlasUndoTarget;
  mJournal, mRestarted: TAtlasUndoJournal;
  mStore: TAtlasUndoFileStore;
  mStoreRef: IAtlasUndoStore;
  mSets: TArray<TAtlasChangeSet>;
  mOptions: TAtlasUndoOptions;
  mBig: string;
begin
  mTarget := TMemoryTarget.Create;
  mTargetRef := mTarget;
  mStore := TAtlasUndoFileStore.Create(FFolder, 1024 * 1024);
  mStoreRef := mStore;
  mJournal := TAtlasUndoJournal.Create(mTargetRef);
  try
    mJournal.Store := mStoreRef;
    Apply(mJournal, mTarget, 'Eins', ['A.pas', 'a'#13#10, 'a1'#13#10, 'B.pas', 'b', 'b1']);
    mJournal.Add('Neu', [TAtlasFileChange.Created('N.pas', 'P.dproj', Content('n', TAtlasTextEncoding.Utf16LE)),
      TAtlasFileChange.Deleted('O.pas', '', Content('o', TAtlasTextEncoding.Ansi))]);
    mJournal.Undo;
    Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(FFolder, 'set-*.json'))));
  finally
    mJournal.Free;
  end;
  // Neustart: Sätze, Zustände, Kodierungen und Zeilenenden sind wieder da.
  mRestarted := TAtlasUndoJournal.Create(mTargetRef);
  try
    mRestarted.Store := mStoreRef;
    mRestarted.Load;
    mSets := mRestarted.Sets;
    AssertRestartedSets(mSets);
    Assert.AreEqual(3, mRestarted.Add('Weiter', [TAtlasFileChange.Created('X.pas', '', Content('x'))]),
      'Kennungen laufen weiter');
    // Tiefe: der älteste Satz fällt auch aus dem Speicher.
    mOptions := TAtlasUndoOptions.Defaults;
    mOptions.Depth := 2;
    mRestarted.Options := mOptions;
    Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(FFolder, 'set-*.json'))));
    Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'set-000001.json')));
    // Größe: ein zu großer Satz wird nicht gesichert, ältere fallen weg, bis alles passt.
    mOptions.Depth := 10;
    mRestarted.Options := mOptions;
    mStore.MaxBytes := 2048;
    mBig := StringOfChar('x', 4096);
    mRestarted.Add('Groß', [TAtlasFileChange.Created('G.pas', '', Content(mBig))]);
    Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'set-000004.json')));
    mRestarted.Add('Mittel', [TAtlasFileChange.Created('M.pas', '', Content(StringOfChar('m', 1800)))]);
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'set-000005.json')));
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FFolder, 'set-*.json'))), 'nur der neueste passt');
    mRestarted.Clear;
    Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FFolder, 'set-*.json'))));
  finally
    mRestarted.Free;
  end;
end;

procedure TAtlasUndoJournalTests.LogHasNoNamesOrSource;
var
  mTarget: TMemoryTarget;
  mTargetRef: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
  mLines: TList<string>;
  mLine: string;
begin
  mTarget := TMemoryTarget.Create;
  mTargetRef := mTarget;
  mLines := TList<string>.Create;
  mJournal := TAtlasUndoJournal.Create(mTargetRef);
  try
    mJournal.OnLog :=
      procedure(AText: string)
      begin
        mLines.Add(AText);
      end;
    Apply(mJournal, mTarget, 'Umbenennen: GeheimesFeld → Anderes', ['C:\Kunde\Geheim.pas', 'GeheimesFeld := 42;',
      'Anderes := 42;', 'C:\Kunde\Zwei.pas', 'X := GeheimesFeld;', 'X := Anderes;']);
    mTarget.Put('C:\Kunde\Zwei.pas', 'Y := Anderes;');
    mJournal.Undo;
    mJournal.Redo;
    Assert.IsTrue(mLines.Count >= 3);
    for mLine in mLines do
    begin
      Assert.IsFalse(mLine.Contains('Kunde'), mLine);
      Assert.IsFalse(mLine.Contains('Geheim'), mLine);
      Assert.IsFalse(mLine.Contains('Anderes'), mLine);
      Assert.IsFalse(mLine.Contains('42'), mLine);
      Assert.IsFalse(mLine.Contains('.pas'), mLine);
    end;
    Assert.AreEqual(3, Integer(Length(TAtlasUndoJournal.Diff(mJournal.Sets[0].Files[0]))));
  finally
    mJournal.Free;
    mLines.Free;
  end;
end;

procedure TAtlasUndoJournalTests.DisabledRecordsNothing;
var
  mTarget: TMemoryTarget;
  mTargetRef: IAtlasUndoTarget;
  mJournal: TAtlasUndoJournal;
  mOptions: TAtlasUndoOptions;
begin
  mTarget := TMemoryTarget.Create;
  mTargetRef := mTarget;
  mJournal := TAtlasUndoJournal.Create(mTargetRef);
  try
    mOptions := TAtlasUndoOptions.Defaults;
    mOptions.Enabled := False;
    mJournal.Options := mOptions;
    // Die Aktion schreibt wie bisher, nur ohne Protokoll.
    Assert.AreEqual(0, Apply(mJournal, mTarget, 'Zwei', ['A.pas', 'a', 'b', 'B.pas', 'c', 'd']));
    Assert.AreEqual('b', mTarget.Text('A.pas'));
    Assert.AreEqual(0, Integer(mJournal.Count));
    Assert.IsTrue(mJournal.Undo.Disabled);
    Assert.IsTrue(mJournal.Redo.Disabled);
  finally
    mJournal.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinePatchTests);
  TDUnitX.RegisterTestFixture(TAtlasUndoJournalTests);

end.
