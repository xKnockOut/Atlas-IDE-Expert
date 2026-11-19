unit Atlas.Core.Debug.OpenedFiles.Tests;

// Buchführung „vom Debugger geöffnete Dateien“ (#842) ohne IDE: was vor der
// Sitzung offen war, was beim Halt aufgeht, Halt kurz nach dem Öffnen, feste
// und vom Aufrufer gehaltene Dateien, Schließen, Vorschau und Einstellwert.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.OpenedFiles;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasOpenedFilesTests = class
  private
    FFiles: TAtlasOpenedFiles;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Abnahme: Drei F7-Schritte in RTL-Code öffnen drei Units, alle drei sind zu schließen.</summary>
    [Test]
    procedure ThreeStepsOpenThreeUnits;
    /// <summary>Abnahme: Eine vor der Sitzung offene System.pas bleibt offen.</summary>
    [Test]
    procedure FilesOpenBeforeSessionStay;
    /// <summary>Abnahme: Eine während der Sitzung geänderte Unit bleibt offen (AKeep).</summary>
    [Test]
    procedure KeptFilesStay;
    [Test]
    procedure PinnedFilesStay;
    [Test]
    procedure OpenWhileRunningCountsOnlyWithStopSoonAfter;
    [Test]
    procedure ClosedFileLeavesList;
    [Test]
    procedure NothingCountsOutsideSession;
    [Test]
    procedure NamesIgnoreCaseAndSlashes;
    /// <summary>Abnahme: Mit Vorschau ist nach fünf Schritten durch verschiedene Units nur einer offen.</summary>
    [Test]
    procedure PreviewClosesPreviousUntouched;
    [Test]
    procedure PreviewKeepsPinned;
    [Test]
    procedure ModeFromSetting;
  end;

implementation

uses
  System.SysUtils;

function KeepModified: TAtlasOpenedFileKeep;
begin
  Result :=
    function(const AFileName: string): Boolean
    begin
      Result := SameText(ExtractFileName(AFileName), 'Vcl.Controls.pas');
    end;
end;

procedure TAtlasOpenedFilesTests.Setup;
begin
  FFiles := TAtlasOpenedFiles.Create;
end;

procedure TAtlasOpenedFilesTests.TearDown;
begin
  FreeAndNil(FFiles);
end;

procedure TAtlasOpenedFilesTests.ThreeStepsOpenThreeUnits;
var
  mClose: TArray<string>;
begin
  FFiles.BeginSession(TArray<string>.Create('C:\P\Main.pas'));
  Assert.IsTrue(FFiles.Opened('C:\RTL\System.pas', True, 100));
  Assert.IsTrue(FFiles.Opened('C:\RTL\System.Classes.pas', True, 200));
  Assert.IsTrue(FFiles.Opened('C:\RTL\Vcl.Forms.pas', True, 300));
  FFiles.EndSession;
  mClose := FFiles.ToClose(nil);
  Assert.AreEqual(3, Integer(Length(mClose)));
  Assert.AreEqual('C:\RTL\System.pas', mClose[0]);
  Assert.AreEqual('C:\RTL\Vcl.Forms.pas', mClose[2]);
  Assert.AreEqual(3, FFiles.Count);
end;

procedure TAtlasOpenedFilesTests.FilesOpenBeforeSessionStay;
begin
  FFiles.BeginSession(TArray<string>.Create('C:\RTL\System.pas'));
  Assert.IsFalse(FFiles.Opened('C:\RTL\System.pas', True, 100));
  Assert.IsFalse(FFiles.IsOpenedByDebugger('C:\RTL\System.pas'));
  Assert.AreEqual(0, Integer(Length(FFiles.ToClose(nil))));
end;

procedure TAtlasOpenedFilesTests.KeptFilesStay;
var
  mClose: TArray<string>;
begin
  FFiles.BeginSession(nil);
  FFiles.Opened('C:\RTL\Vcl.Controls.pas', True, 100);
  FFiles.Opened('C:\RTL\System.pas', True, 200);
  mClose := FFiles.ToClose(KeepModified);
  Assert.AreEqual(1, Integer(Length(mClose)));
  Assert.AreEqual('C:\RTL\System.pas', mClose[0]);
end;

procedure TAtlasOpenedFilesTests.PinnedFilesStay;
begin
  FFiles.BeginSession(nil);
  FFiles.Opened('C:\RTL\System.pas', True, 100);
  FFiles.Pin('c:\rtl\system.pas');
  Assert.IsTrue(FFiles.IsPinned('C:\RTL\System.pas'));
  Assert.AreEqual(0, Integer(Length(FFiles.ToClose(nil))));
end;

procedure TAtlasOpenedFilesTests.OpenWhileRunningCountsOnlyWithStopSoonAfter;
begin
  FFiles.BeginSession(nil);
  Assert.IsFalse(FFiles.Opened('C:\RTL\System.pas', False, 1000));
  Assert.IsFalse(FFiles.IsOpenedByDebugger('C:\RTL\System.pas'));
  Assert.IsTrue(FFiles.Stopped('C:\RTL\System.pas', 1000 + TAtlasOpenedFiles.cStopWindowMs));
  Assert.IsTrue(FFiles.IsOpenedByDebugger('C:\RTL\System.pas'));
  // Vom Benutzer im laufenden Programm geöffnet, Halt erst viel später: zählt nicht.
  FFiles.Opened('C:\P\Other.pas', False, 1000);
  Assert.IsFalse(FFiles.Stopped('C:\P\Other.pas', 1001 + TAtlasOpenedFiles.cStopWindowMs));
  Assert.IsFalse(FFiles.IsOpenedByDebugger('C:\P\Other.pas'));
end;

procedure TAtlasOpenedFilesTests.ClosedFileLeavesList;
begin
  FFiles.BeginSession(TArray<string>.Create('C:\RTL\System.pas'));
  FFiles.Opened('C:\RTL\Vcl.Forms.pas', True, 100);
  FFiles.Closed('C:\RTL\Vcl.Forms.pas');
  Assert.AreEqual(0, FFiles.Count);
  // Vor der Sitzung offen, geschlossen und vom Debugger wieder geöffnet: jetzt seine.
  FFiles.Closed('C:\RTL\System.pas');
  Assert.IsTrue(FFiles.Opened('C:\RTL\System.pas', True, 200));
end;

procedure TAtlasOpenedFilesTests.NothingCountsOutsideSession;
begin
  Assert.IsFalse(FFiles.Active);
  Assert.IsFalse(FFiles.Opened('C:\RTL\System.pas', True, 100));
  FFiles.BeginSession(nil);
  FFiles.EndSession;
  Assert.IsFalse(FFiles.Opened('C:\RTL\System.pas', True, 100));
  Assert.AreEqual(0, FFiles.Count);
end;

procedure TAtlasOpenedFilesTests.NamesIgnoreCaseAndSlashes;
begin
  FFiles.BeginSession(TArray<string>.Create('C:/rtl/system.pas'));
  Assert.IsFalse(FFiles.Opened('C:\RTL\System.pas', True, 100));
  Assert.AreEqual('C:\RTL\SYSTEM.PAS', TAtlasOpenedFiles.KeyOf(' c:/rtl/System.pas '));
end;

procedure TAtlasOpenedFilesTests.PreviewClosesPreviousUntouched;
var
  mIndex: Integer;
  mClosed: Integer;
  mFile: string;
  mPrevious: string;
begin
  FFiles.BeginSession(nil);
  mClosed := 0;
  for mIndex := 1 to 5 do
  begin
    mFile := Format('C:\RTL\Unit%d.pas', [mIndex]);
    FFiles.Opened(mFile, True, mIndex * 100);
    mPrevious := FFiles.PreviewToClose(mFile, nil);
    if mPrevious <> '' then
    begin
      FFiles.Closed(mPrevious);
      Inc(mClosed);
    end;
  end;
  Assert.AreEqual(4, mClosed);
  Assert.AreEqual(1, FFiles.Count);
  Assert.AreEqual('C:\RTL\Unit5.pas', FFiles.Preview);
end;

procedure TAtlasOpenedFilesTests.PreviewKeepsPinned;
begin
  FFiles.BeginSession(nil);
  FFiles.Opened('C:\RTL\A.pas', True, 100);
  Assert.AreEqual('', FFiles.PreviewToClose('C:\RTL\A.pas', nil));
  FFiles.Pin('C:\RTL\A.pas');
  FFiles.Opened('C:\RTL\B.pas', True, 200);
  Assert.AreEqual('', FFiles.PreviewToClose('C:\RTL\B.pas', nil));
  FFiles.Opened('C:\RTL\Vcl.Controls.pas', True, 300);
  Assert.AreEqual('C:\RTL\B.pas', FFiles.PreviewToClose('C:\RTL\Vcl.Controls.pas', nil));
  FFiles.Opened('C:\RTL\D.pas', True, 400);
  Assert.AreEqual('', FFiles.PreviewToClose('C:\RTL\D.pas', KeepModified));
end;

procedure TAtlasOpenedFilesTests.ModeFromSetting;
begin
  Assert.AreEqual(Ord(TAtlasCloseOpenedFiles.Off), Ord(TAtlasOpenedFiles.ModeOf('off')));
  Assert.AreEqual(Ord(TAtlasCloseOpenedFiles.Auto), Ord(TAtlasOpenedFiles.ModeOf(' AUTO ')));
  Assert.AreEqual(Ord(TAtlasCloseOpenedFiles.Ask), Ord(TAtlasOpenedFiles.ModeOf('ask')));
  Assert.AreEqual(Ord(TAtlasCloseOpenedFiles.Ask), Ord(TAtlasOpenedFiles.ModeOf('unbekannt')));
  Assert.AreEqual('auto', TAtlasOpenedFiles.NameOf(TAtlasCloseOpenedFiles.Auto));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOpenedFilesTests);

end.
