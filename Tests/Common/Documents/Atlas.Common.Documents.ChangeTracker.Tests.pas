unit Atlas.Common.Documents.ChangeTracker.Tests;

// Tests für das Erkennen geänderter Konfigurationsdateien (#227).

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Documents.ChangeTracker;

type
  [TestFixture]
  TFileChangeTrackerTests = class
  private
    FStamps: TDictionary<string, string>;
    FTracker: TFileChangeTracker;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReportsChangedCreatedAndDeletedFiles;
    [Test]
    procedure KeepsStampsOfKnownFiles;
    [Test]
    procedure ListsDirectoriesOnce;
  end;

implementation

uses
  System.SysUtils;

procedure TFileChangeTrackerTests.Setup;
var
  mStamps: TDictionary<string, string>;
begin
  FStamps := TDictionary<string, string>.Create;
  mStamps := FStamps;
  FTracker := TFileChangeTracker.Create(
    function(const AFileName: string): string
    begin
      if not mStamps.TryGetValue(LowerCase(AFileName), Result) then
      begin
        Result := '';
      end;
    end);
end;

procedure TFileChangeTrackerTests.TearDown;
begin
  FTracker.Free;
  FStamps.Free;
end;

procedure TFileChangeTrackerTests.ReportsChangedCreatedAndDeletedFiles;
var
  mChanged: TArray<string>;
begin
  FStamps.AddOrSetValue('c:\p\atlas.json', '1');
  FTracker.SetFiles(['c:\p\atlas.json', 'c:\a\settings.json']);
  Assert.AreEqual(0, Integer(Length(FTracker.Poll)));
  // Geändert und neu angelegt.
  FStamps.AddOrSetValue('c:\p\atlas.json', '2');
  FStamps.AddOrSetValue('c:\a\settings.json', '1');
  mChanged := FTracker.Poll;
  Assert.AreEqual(2, Integer(Length(mChanged)));
  Assert.AreEqual('c:\p\atlas.json', mChanged[0]);
  Assert.AreEqual(0, Integer(Length(FTracker.Poll)));
  // Gelöscht.
  FStamps.Remove('c:\a\settings.json');
  mChanged := FTracker.Poll;
  Assert.AreEqual(1, Integer(Length(mChanged)));
  Assert.AreEqual('c:\a\settings.json', mChanged[0]);
end;

procedure TFileChangeTrackerTests.KeepsStampsOfKnownFiles;
begin
  FStamps.AddOrSetValue('c:\p\atlas.json', '1');
  FTracker.SetFiles(['c:\p\atlas.json']);
  FStamps.AddOrSetValue('c:\p\atlas.json', '2');
  // Ein weiterer Ordner kommt dazu: Die Änderung an der bekannten Datei geht nicht verloren.
  FTracker.SetFiles(['C:\P\atlas.json', 'c:\q\atlas.json', '']);
  Assert.AreEqual(2, Integer(Length(FTracker.Files)));
  Assert.AreEqual(1, Integer(Length(FTracker.Poll)));
  // Entfernt: keine Meldung mehr.
  FTracker.SetFiles(['c:\q\atlas.json']);
  FStamps.AddOrSetValue('c:\p\atlas.json', '3');
  Assert.AreEqual(0, Integer(Length(FTracker.Poll)));
end;

procedure TFileChangeTrackerTests.ListsDirectoriesOnce;
var
  mDirs: TArray<string>;
begin
  FTracker.SetFiles(['c:\p\atlas.json', 'c:\p\delphi-lsp.json', 'c:\a\settings.json']);
  mDirs := FTracker.Directories;
  Assert.AreEqual(2, Integer(Length(mDirs)));
  Assert.AreEqual('c:\p', mDirs[0]);
  Assert.AreEqual('c:\a', mDirs[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TFileChangeTrackerTests);

end.
