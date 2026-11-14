unit Atlas.Core.Undo.Names.Tests;

// Tests der Einstellungstexte für undo.multiFile (#721): Name und Parse
// sind zueinander invers, unbekannter Text liefert die Vorgabe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUndoNamesTests = class
  public
    [Test]
    procedure ConflictModeRoundTrip;
    [Test]
    procedure NewFilesRoundTrip;
    [Test]
    procedure UnknownTextGivesDefault;
  end;

implementation

uses
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Names;

procedure TAtlasUndoNamesTests.ConflictModeRoundTrip;
var
  mMode: TAtlasUndoConflictMode;
begin
  for mMode := Low(TAtlasUndoConflictMode) to High(TAtlasUndoConflictMode) do
  begin
    Assert.AreEqual(Ord(mMode), Ord(TAtlasUndoNames.ParseConflictMode(TAtlasUndoNames.ConflictModeName(mMode))));
  end;
  Assert.AreEqual('abort', TAtlasUndoNames.ConflictModeName(TAtlasUndoConflictMode.Abort));
end;

procedure TAtlasUndoNamesTests.NewFilesRoundTrip;
var
  mMode: TAtlasNewFilesMode;
begin
  for mMode := Low(TAtlasNewFilesMode) to High(TAtlasNewFilesMode) do
  begin
    Assert.AreEqual(Ord(mMode), Ord(TAtlasUndoNames.ParseNewFiles(TAtlasUndoNames.NewFilesName(mMode))));
  end;
  Assert.AreEqual('recycleBin', TAtlasUndoNames.NewFilesName(TAtlasNewFilesMode.RecycleBin));
end;

procedure TAtlasUndoNamesTests.UnknownTextGivesDefault;
begin
  Assert.AreEqual(Ord(TAtlasUndoConflictMode.Partial), Ord(TAtlasUndoNames.ParseConflictMode('xyz')));
  Assert.AreEqual(Ord(TAtlasNewFilesMode.RecycleBin), Ord(TAtlasUndoNames.ParseNewFiles('')));
  Assert.AreEqual(Ord(TAtlasNewFilesMode.Keep), Ord(TAtlasUndoNames.ParseNewFiles(' Keep ')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUndoNamesTests);

end.
