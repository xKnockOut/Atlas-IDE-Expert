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
  FFolder := '';
end;

procedure TFileWatcherTests.ReportsChangedAndCreatedFiles;
var
  mWatcher: TFileWatcher;
  mSignal: TEvent;
  mSeen: string;
  mLock: TObject;
  mConfig, mOther: string;
begin
  mConfig := TPath.Combine(FFolder, 'atlas.json');
  mOther := TPath.Combine(FFolder, 'settings.json');
  TFile.WriteAllText(mConfig, '{}');
  mSignal := TEvent.Create(nil, False, False, '');
  mLock := TObject.Create;
  try
    mWatcher := TFileWatcher.Create(
      procedure(const AFiles: TArray<string>)
      var
        FileName: string;
      begin
        TMonitor.Enter(mLock);
        try
          for FileName in AFiles do
          begin
            mSeen := mSeen + ExtractFileName(FileName) + ';';
          end;
        finally
          TMonitor.Exit(mLock);
        end;
        mSignal.SetEvent;
      end);
    try
      mWatcher.SetFiles([mConfig, mOther]);
      Sleep(200);
      TFile.WriteAllText(mConfig, '{"platform": "Win64"}');
      Assert.AreEqual<TWaitResult>(wrSignaled, mSignal.WaitFor(5000));
      TMonitor.Enter(mLock);
      try
        Assert.AreEqual('atlas.json;', mSeen);
        mSeen := '';
      finally
        TMonitor.Exit(mLock);
      end;
      // Neu angelegte Datei wird ebenso gemeldet; andere Dateien im Ordner nicht.
      TFile.WriteAllText(TPath.Combine(FFolder, 'Unit1.pas'), 'unit Unit1;');
      TFile.WriteAllText(mOther, '{}');
      Assert.AreEqual<TWaitResult>(wrSignaled, mSignal.WaitFor(5000));
      Sleep(300);
      TMonitor.Enter(mLock);
      try
        Assert.AreEqual('settings.json;', mSeen);
      finally
        TMonitor.Exit(mLock);
      end;
    finally
      mWatcher.Free;
    end;
  finally
    mLock.Free;
    mSignal.Free;
  end;
end;

procedure TFileWatcherTests.StampChangesWithContent;
var
  mFileName, mBefore: string;
begin
  mFileName := TPath.Combine(FFolder, 'atlas.json');
  Assert.AreEqual('', TFileWatcher.Stamp(mFileName));
  TFile.WriteAllText(mFileName, '{}');
  mBefore := TFileWatcher.Stamp(mFileName);
  Assert.AreNotEqual('', mBefore);
  TFile.WriteAllText(mFileName, '{"a": 1}');
  Assert.AreNotEqual(mBefore, TFileWatcher.Stamp(mFileName));
  Assert.AreEqual('', TFileWatcher.Stamp(FFolder));
end;

initialization
  TDUnitX.RegisterTestFixture(TFileWatcherTests);

end.
