unit Atlas.Windows.Documents.FileWatcher.Tests;

// Tests für den eigenen Dateibeobachter des Servers (#227) mit echten Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFileWatcherTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReportsChangedAndCreatedFiles;
    [Test]
    procedure StampChangesWithContent;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Atlas.Windows.Documents.FileWatcher;

procedure TFileWatcherTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasWatcher' + IntToStr(Random(1000000)));
  ForceDirectories(FFolder);
end;

procedure TFileWatcherTests.TearDown;
begin
  TDirectory.Delete(FFolder, True);
end;

procedure TFileWatcherTests.ReportsChangedAndCreatedFiles;
var
  Watcher: TFileWatcher;
  Signal: TEvent;
  Seen: string;
  Lock: TObject;
  Config, Other: string;
begin
  Config := TPath.Combine(FFolder, 'atlas.json');
  Other := TPath.Combine(FFolder, 'settings.json');
  TFile.WriteAllText(Config, '{}');
  Signal := TEvent.Create(nil, False, False, '');
  Lock := TObject.Create;
  try
    Watcher := TFileWatcher.Create(
      procedure(const AFiles: TArray<string>)
      var
        FileName: string;
      begin
        TMonitor.Enter(Lock);
        try
          for FileName in AFiles do
            Seen := Seen + ExtractFileName(FileName) + ';';
        finally
          TMonitor.Exit(Lock);
        end;
        Signal.SetEvent;
      end);
    try
      Watcher.SetFiles([Config, Other]);
      Sleep(200);
      TFile.WriteAllText(Config, '{"platform": "Win64"}');
      Assert.IsTrue(Signal.WaitFor(5000) = wrSignaled);
      TMonitor.Enter(Lock);
      try
        Assert.AreEqual('atlas.json;', Seen);
        Seen := '';
      finally
        TMonitor.Exit(Lock);
      end;
      // Neu angelegte Datei wird ebenso gemeldet; andere Dateien im Ordner nicht.
      TFile.WriteAllText(TPath.Combine(FFolder, 'Unit1.pas'), 'unit Unit1;');
      TFile.WriteAllText(Other, '{}');
      Assert.IsTrue(Signal.WaitFor(5000) = wrSignaled);
      Sleep(300);
      TMonitor.Enter(Lock);
      try
        Assert.AreEqual('settings.json;', Seen);
      finally
        TMonitor.Exit(Lock);
      end;
    finally
      Watcher.Free;
    end;
  finally
    Lock.Free;
    Signal.Free;
  end;
end;

procedure TFileWatcherTests.StampChangesWithContent;
var
  FileName, Before: string;
begin
  FileName := TPath.Combine(FFolder, 'atlas.json');
  Assert.AreEqual('', TFileWatcher.Stamp(FileName));
  TFile.WriteAllText(FileName, '{}');
  Before := TFileWatcher.Stamp(FileName);
  Assert.IsTrue(Before <> '');
  TFile.WriteAllText(FileName, '{"a": 1}');
  Assert.AreNotEqual(Before, TFileWatcher.Stamp(FileName));
  Assert.AreEqual('', TFileWatcher.Stamp(FFolder));
end;

initialization
  TDUnitX.RegisterTestFixture(TFileWatcherTests);

end.
