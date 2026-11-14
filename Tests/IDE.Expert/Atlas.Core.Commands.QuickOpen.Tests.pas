unit Atlas.Core.Commands.QuickOpen.Tests;

// Tests für „Datei und Symbol schnell öffnen“ (#503).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasQuickOpenTests = class
  public
    [Test]
    procedure ParsesPrefixesAndLines;
    [Test]
    procedure CollectsListedFilesWithoutDuplicates;
    [Test]
    [Category('Benchmark')]
    procedure FindsFormUnitInLargeGroupQuickly;
    [Test]
    procedure OpenThenRecentThenProjectThenRest;
    [Test]
    procedure PathAndExtensionHelp;
    [Test]
    procedure OrdersSymbols;
    [Test]
    procedure ListBuildsInBackgroundOnlyOnChange;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  System.SyncObjs,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Commands.QuickOpen;

function Names(const AFiles: TAtlasQuickOpenFiles; const AOrder: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AOrder do
  begin
    Result := Result + AFiles[mIndex].Name + '|';
  end;
end;

function FakeLister: TAtlasQuickOpenLister;
begin
  Result :=
    function(const AFolder: string; ARecursive: Boolean): TArray<string>
    begin
      Result := nil;
      if AFolder = 'C:\Gruppe\Haupt' then
      begin
        Result := ['C:\Gruppe\Haupt\FrmHaupt.pas', 'C:\Gruppe\Haupt\FrmHaupt.dfm', 'C:\Gruppe\Haupt\Defs.inc',
          'C:\Gruppe\Haupt\Bild.png', 'C:\Gruppe\Haupt\Haupt.res'];
      end
      else if AFolder = 'C:\Lib\Pfad' then
      begin
        Result := ['C:\Lib\Pfad\Kunden.pas', 'C:\Gruppe\Haupt\FrmHaupt.pas'];
      end
      else if (AFolder = 'C:\BDS\source') and ARecursive then
      begin
        Result := ['C:\BDS\source\rtl\sys\System.SysUtils.pas', 'C:\BDS\source\vcl\Vcl.Forms.pas'];
      end;
    end;
end;

function Sources: TAtlasQuickOpenSources;
begin
  Result := Default(TAtlasQuickOpenSources);
  Result.Root := 'C:\Gruppe';
  Result.ProjectFiles := ['C:\Gruppe\Haupt\Haupt.dproj', 'C:\Gruppe\Haupt\Haupt.dpr',
    'C:\Gruppe\Haupt\FrmHaupt.pas', 'C:\Gruppe\Haupt\FrmHaupt.dfm'];
  Result.Folders := ['C:\Gruppe\Haupt', 'C:\Lib\Pfad', 'c:\gruppe\haupt'];
end;

procedure TAtlasQuickOpenTests.ParsesPrefixesAndLines;
var
  mQuery: TAtlasQuickOpenQuery;
begin
  mQuery := TAtlasQuickOpenQuery.Parse('frmhaupt');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.Files), Ord(mQuery.Mode));
  Assert.AreEqual('frmhaupt', mQuery.Text);
  Assert.AreEqual(0, mQuery.Line);
  mQuery := TAtlasQuickOpenQuery.Parse('@Laden');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.FileSymbols), Ord(mQuery.Mode));
  Assert.AreEqual('Laden', mQuery.Text);
  mQuery := TAtlasQuickOpenQuery.Parse('#TKunde');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.ProjectSymbols), Ord(mQuery.Mode));
  Assert.AreEqual('TKunde', mQuery.Text);
  mQuery := TAtlasQuickOpenQuery.Parse(':42');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.Line), Ord(mQuery.Mode));
  Assert.AreEqual(42, mQuery.Line);
  mQuery := TAtlasQuickOpenQuery.Parse(':');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.Line), Ord(mQuery.Mode));
  Assert.AreEqual(0, mQuery.Line);
  mQuery := TAtlasQuickOpenQuery.Parse('FrmHaupt:123');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.Files), Ord(mQuery.Mode));
  Assert.AreEqual('FrmHaupt', mQuery.Text);
  Assert.AreEqual(123, mQuery.Line);
  // Ein Laufwerk oder Text hinter dem Doppelpunkt ist keine Zeile.
  mQuery := TAtlasQuickOpenQuery.Parse('C:\Gruppe');
  Assert.AreEqual('C:\Gruppe', mQuery.Text);
  Assert.AreEqual(0, mQuery.Line);
  mQuery := TAtlasQuickOpenQuery.Parse('Datei:-3');
  Assert.AreEqual('Datei:-3', mQuery.Text);
  Assert.AreEqual(0, mQuery.Line);
end;

procedure TAtlasQuickOpenTests.CollectsListedFilesWithoutDuplicates;
var
  mFiles: TAtlasQuickOpenFiles;
  mInput: TAtlasQuickOpenSources;
  mIndex: Integer;
  mListed: string;
begin
  mFiles := TAtlasQuickOpen.Collect(Sources, FakeLister());
  mListed := '';
  for mIndex := 0 to High(mFiles) do
  begin
    mListed := mListed + mFiles[mIndex].Name + '=' + IntToStr(Ord(mFiles[mIndex].Origin)) + '|';
  end;
  // Projektdateien zuerst (Herkunft 0); .png und .res fehlen; FrmHaupt.pas nur einmal, als Projektdatei.
  Assert.AreEqual('Haupt.dproj=0|Haupt.dpr=0|FrmHaupt.pas=0|FrmHaupt.dfm=0|Defs.inc=1|Kunden.pas=1|', mListed);
  Assert.AreEqual('Haupt\FrmHaupt.pas', mFiles[2].RelativePath);
  Assert.AreEqual('FrmHaupt', mFiles[2].Stem);
  Assert.AreEqual('C:\Lib\Pfad\Kunden.pas', mFiles[5].RelativePath);
  // Bibliothek nur auf Wunsch, mit Unterordnern.
  mInput := Sources;
  mInput.LibraryFolders := ['C:\BDS\source'];
  mFiles := TAtlasQuickOpen.Collect(mInput, FakeLister());
  Assert.AreEqual(8, Integer(Length(mFiles)));
  Assert.AreEqual(Ord(TAtlasQuickOpenOrigin.Library_), Ord(mFiles[7].Origin));
  // Abbruch zwischen den Ordnern: nur die Projektdateien.
  mFiles := TAtlasQuickOpen.Collect(mInput, FakeLister(),
    function: Boolean
    begin
      Result := True;
    end);
  Assert.AreEqual(4, Integer(Length(mFiles)));
  Assert.IsTrue(TAtlasQuickOpen.IsListed('X.RC'));
  Assert.IsFalse(TAtlasQuickOpen.IsListed('X.dcu'));
end;

procedure TAtlasQuickOpenTests.FindsFormUnitInLargeGroupQuickly;
var
  mInput: TAtlasQuickOpenSources;
  mFiles: TAtlasQuickOpenFiles;
  mOrder: TArray<Integer>;
  mIndex: Integer;
  mWatch: TStopwatch;
begin
  mInput := Default(TAtlasQuickOpenSources);
  mInput.Root := 'C:\Gruppe';
  for mIndex := 1 to 999 do
  begin
    mInput.ProjectFiles := mInput.ProjectFiles + [Format('C:\Gruppe\P%d\Unit%d.pas', [mIndex mod 20, mIndex])];
  end;
  mInput.ProjectFiles := mInput.ProjectFiles + ['C:\Gruppe\Haupt\FrmHaupt.pas'];
  mFiles := TAtlasQuickOpen.Collect(mInput, FakeLister());
  Assert.AreEqual(1000, Integer(Length(mFiles)));
  mWatch := TStopwatch.StartNew;
  mOrder := TAtlasQuickOpen.Order(mFiles, 'frmhaupt', nil, nil);
  mWatch.Stop;
  Assert.IsTrue(Length(mOrder) >= 1);
  Assert.AreEqual('FrmHaupt.pas', mFiles[mOrder[0]].Name);
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 50, 'Dauer ' + IntToStr(mWatch.ElapsedMilliseconds) + ' ms');
  // Ohne Eingabe höchstens MaxResults Treffer.
  Assert.AreEqual(TAtlasQuickOpen.cMaxResults, Integer(Length(TAtlasQuickOpen.Order(mFiles, '', nil, nil))));
end;

procedure TAtlasQuickOpenTests.OpenThenRecentThenProjectThenRest;
var
  mFiles: TAtlasQuickOpenFiles;
  mRecent: TAtlasCommandHistory;
begin
  mFiles := TAtlasQuickOpen.Collect(Sources, FakeLister());
  mRecent := TAtlasCommandHistory.Create;
  try
    mRecent.Executed(TAtlasQuickOpen.RecentKey('C:\Gruppe\Haupt\Defs.inc'));
    mRecent.Executed(TAtlasQuickOpen.RecentKey('C:\Lib\Pfad\Kunden.pas'));
    // Ohne Eingabe: offen, dann zuletzt geöffnet (jüngste zuerst), dann Projekt (.pas vor .dpr …), dann Rest.
    Assert.AreEqual('FrmHaupt.dfm|Kunden.pas|Defs.inc|FrmHaupt.pas|Haupt.dpr|Haupt.dproj|',
      Names(mFiles, TAtlasQuickOpen.Order(mFiles, '', ['c:\gruppe\haupt\frmhaupt.dfm'], mRecent)));
    // Gleicher Name: .pas vor .dfm.
    Assert.AreEqual('FrmHaupt.pas|FrmHaupt.dfm|', Names(mFiles, TAtlasQuickOpen.Order(mFiles, 'frmhaupt', nil, nil)));
    // Die bessere Übereinstimmung schlägt die Stufe.
    Assert.IsTrue(Names(mFiles, TAtlasQuickOpen.Order(mFiles, 'haupt', ['C:\Gruppe\Haupt\FrmHaupt.pas'], nil)).StartsWith(
      'Haupt.dpr|Haupt.dproj|FrmHaupt.pas|FrmHaupt.dfm|'));
  finally
    mRecent.Free;
  end;
end;

procedure TAtlasQuickOpenTests.PathAndExtensionHelp;
var
  mFiles: TAtlasQuickOpenFiles;
begin
  mFiles := TAtlasQuickOpen.Collect(Sources, FakeLister());
  Assert.AreEqual('FrmHaupt.dfm|', Names(mFiles, TAtlasQuickOpen.Order(mFiles, 'frmhaupt.dfm', nil, nil)));
  Assert.AreEqual('Defs.inc|', Names(mFiles, TAtlasQuickOpen.Order(mFiles, 'haupt\defs', nil, nil)));
  Assert.AreEqual('Defs.inc|', Names(mFiles, TAtlasQuickOpen.Order(mFiles, 'haupt/defs', nil, nil)));
  // Wörter des Pfads mit Leerzeichen, halbe Punkte.
  Assert.AreEqual('Kunden.pas|', Names(mFiles, TAtlasQuickOpen.Order(mFiles, 'pfad kunden', nil, nil)));
  Assert.AreEqual('', Names(mFiles, TAtlasQuickOpen.Order(mFiles, 'xyz', nil, nil)));
  Assert.AreEqual('Haupt\FrmHaupt.pas', TAtlasQuickOpen.RelativeTo('C:\Gruppe\Haupt\FrmHaupt.pas', 'c:\gruppe\'));
  Assert.AreEqual('D:\X.pas', TAtlasQuickOpen.RelativeTo('D:\X.pas', 'C:\Gruppe'));
end;

procedure TAtlasQuickOpenTests.OrdersSymbols;
var
  mOrder: TArray<Integer>;
begin
  mOrder := TAtlasQuickOpen.OrderSymbols(['Speichern', 'NeuLaden', 'Laden', 'TKunde'], 'Laden');
  Assert.AreEqual(2, Integer(Length(mOrder)));
  Assert.AreEqual(2, mOrder[0]);
  Assert.AreEqual(1, mOrder[1]);
  mOrder := TAtlasQuickOpen.OrderSymbols(['B', 'A'], '');
  Assert.AreEqual(0, mOrder[0]);
  Assert.AreEqual(1, mOrder[1]);
end;

procedure TAtlasQuickOpenTests.ListBuildsInBackgroundOnlyOnChange;
var
  mList: TAtlasQuickOpenList;
  mCalls: Integer;
  mGate: TEvent;
  mInput: TAtlasQuickOpenSources;
begin
  mCalls := 0;
  mGate := TEvent.Create(nil, True, False, '');
  mList := TAtlasQuickOpenList.Create(
    function(const AFolder: string; ARecursive: Boolean): TArray<string>
    begin
      TInterlocked.Increment(mCalls);
      mGate.WaitFor(5000);
      Result := [AFolder + '\A.pas'];
    end);
  try
    mInput := Default(TAtlasQuickOpenSources);
    mInput.Folders := ['C:\Eins'];
    mList.Refresh(mInput);
    // Läuft im Hintergrund: Refresh kehrt sofort zurück, die Liste ist noch leer.
    Assert.IsTrue(mList.Building);
    Assert.AreEqual(0, Integer(Length(mList.Files)));
    mGate.SetEvent;
    Assert.IsTrue(mList.WaitIdle(5000));
    Assert.AreEqual(1, Integer(Length(mList.Files)));
    Assert.AreEqual('C:\Eins\A.pas', mList.Files[0].FileName);
    // Gleiche Quellen: kein neuer Aufbau.
    mList.Refresh(mInput);
    Assert.IsTrue(mList.WaitIdle(5000));
    Assert.AreEqual(1, mCalls);
    // Projektwechsel: neu.
    mInput.Folders := ['C:\Zwei'];
    mList.Refresh(mInput);
    Assert.IsTrue(mList.WaitIdle(5000));
    Assert.AreEqual(2, mCalls);
    Assert.AreEqual('C:\Zwei\A.pas', mList.Files[0].FileName);
  finally
    mList.Free;
    mGate.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickOpenTests);

end.
