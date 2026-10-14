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
  Stamps: TDictionary<string, string>;
begin
  FStamps := TDictionary<string, string>.Create;
  Stamps := FStamps;
  FTracker := TFileChangeTracker.Create(
    function(const AFileName: string): string
    begin
      if not Stamps.TryGetValue(LowerCase(AFileName), Result) then
        Result := '';
    end);
end;

procedure TFileChangeTrackerTests.TearDown;
begin
  FTracker.Free;
  FStamps.Free;
end;

procedure TFileChangeTrackerTests.ReportsChangedCreatedAndDeletedFiles;
var
  Changed: TArray<string>;
begin
  FStamps.AddOrSetValue('c:\p\atlas.json', '1');
  FTracker.SetFiles(['c:\p\atlas.json', 'c:\a\settings.json']);
  Assert.AreEqual(0, Integer(Length(FTracker.Poll)));
  // Geändert und neu angelegt.
  FStamps.AddOrSetValue('c:\p\atlas.json', '2');
  FStamps.AddOrSetValue('c:\a\settings.json', '1');
  Changed := FTracker.Poll;
  Assert.AreEqual(2, Integer(Length(Changed)));
  Assert.AreEqual('c:\p\atlas.json', Changed[0]);
  Assert.AreEqual(0, Integer(Length(FTracker.Poll)));
  // Gelöscht.
  FStamps.Remove('c:\a\settings.json');
  Changed := FTracker.Poll;
  Assert.AreEqual(1, Integer(Length(Changed)));
  Assert.AreEqual('c:\a\settings.json', Changed[0]);
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
  Dirs: TArray<string>;
begin
  FTracker.SetFiles(['c:\p\atlas.json', 'c:\p\delphi-lsp.json', 'c:\a\settings.json']);
  Dirs := FTracker.Directories;
  Assert.AreEqual(2, Integer(Length(Dirs)));
  Assert.AreEqual('c:\p', Dirs[0]);
  Assert.AreEqual('c:\a', Dirs[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TFileChangeTrackerTests);

end.
