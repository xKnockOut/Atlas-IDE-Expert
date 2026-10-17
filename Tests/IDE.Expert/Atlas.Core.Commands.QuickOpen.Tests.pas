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
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
    Result := Result + AFiles[Index].Name + '|';
end;

function FakeLister: TAtlasQuickOpenLister;
begin
  Result :=
    function(const AFolder: string; ARecursive: Boolean): TArray<string>
    begin
      Result := nil;
      if AFolder = 'C:\Gruppe\Haupt' then
        Result := ['C:\Gruppe\Haupt\FrmHaupt.pas', 'C:\Gruppe\Haupt\FrmHaupt.dfm', 'C:\Gruppe\Haupt\Defs.inc',
          'C:\Gruppe\Haupt\Bild.png', 'C:\Gruppe\Haupt\Haupt.res']
      else if AFolder = 'C:\Lib\Pfad' then
        Result := ['C:\Lib\Pfad\Kunden.pas', 'C:\Gruppe\Haupt\FrmHaupt.pas']
      else if (AFolder = 'C:\BDS\source') and ARecursive then
        Result := ['C:\BDS\source\rtl\sys\System.SysUtils.pas', 'C:\BDS\source\vcl\Vcl.Forms.pas'];
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
  Query: TAtlasQuickOpenQuery;
begin
  Query := TAtlasQuickOpenQuery.Parse('frmhaupt');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.Files), Ord(Query.Mode));
  Assert.AreEqual('frmhaupt', Query.Text);
  Assert.AreEqual(0, Query.Line);
  Query := TAtlasQuickOpenQuery.Parse('@Laden');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.FileSymbols), Ord(Query.Mode));
  Assert.AreEqual('Laden', Query.Text);
  Query := TAtlasQuickOpenQuery.Parse('#TKunde');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.ProjectSymbols), Ord(Query.Mode));
  Assert.AreEqual('TKunde', Query.Text);
  Query := TAtlasQuickOpenQuery.Parse(':42');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.Line), Ord(Query.Mode));
  Assert.AreEqual(42, Query.Line);
  Query := TAtlasQuickOpenQuery.Parse(':');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.Line), Ord(Query.Mode));
  Assert.AreEqual(0, Query.Line);
  Query := TAtlasQuickOpenQuery.Parse('FrmHaupt:123');
  Assert.AreEqual(Ord(TAtlasQuickOpenMode.Files), Ord(Query.Mode));
  Assert.AreEqual('FrmHaupt', Query.Text);
  Assert.AreEqual(123, Query.Line);
  // Ein Laufwerk oder Text hinter dem Doppelpunkt ist keine Zeile.
  Query := TAtlasQuickOpenQuery.Parse('C:\Gruppe');
  Assert.AreEqual('C:\Gruppe', Query.Text);
  Assert.AreEqual(0, Query.Line);
  Query := TAtlasQuickOpenQuery.Parse('Datei:-3');
  Assert.AreEqual('Datei:-3', Query.Text);
  Assert.AreEqual(0, Query.Line);
end;

procedure TAtlasQuickOpenTests.CollectsListedFilesWithoutDuplicates;
var
  Files: TAtlasQuickOpenFiles;
  Input: TAtlasQuickOpenSources;
  Index: Integer;
  Listed: string;
begin
  Files := TAtlasQuickOpen.Collect(Sources, FakeLister);
  Listed := '';
  for Index := 0 to High(Files) do
    Listed := Listed + Files[Index].Name + '=' + IntToStr(Ord(Files[Index].Origin)) + '|';
  // Projektdateien zuerst (Herkunft 0); .png und .res fehlen; FrmHaupt.pas nur einmal, als Projektdatei.
  Assert.AreEqual('Haupt.dproj=0|Haupt.dpr=0|FrmHaupt.pas=0|FrmHaupt.dfm=0|Defs.inc=1|Kunden.pas=1|', Listed);
  Assert.AreEqual('Haupt\FrmHaupt.pas', Files[2].RelativePath);
  Assert.AreEqual('FrmHaupt', Files[2].Stem);
  Assert.AreEqual('C:\Lib\Pfad\Kunden.pas', Files[5].RelativePath);
  // Bibliothek nur auf Wunsch, mit Unterordnern.
  Input := Sources;
  Input.LibraryFolders := ['C:\BDS\source'];
  Files := TAtlasQuickOpen.Collect(Input, FakeLister);
  Assert.AreEqual(8, Integer(Length(Files)));
  Assert.AreEqual(Ord(TAtlasQuickOpenOrigin.Library_), Ord(Files[7].Origin));
  // Abbruch zwischen den Ordnern: nur die Projektdateien.
  Files := TAtlasQuickOpen.Collect(Input, FakeLister,
    function: Boolean
    begin
      Result := True;
    end);
  Assert.AreEqual(4, Integer(Length(Files)));
  Assert.IsTrue(TAtlasQuickOpen.IsListed('X.RC'));
  Assert.IsFalse(TAtlasQuickOpen.IsListed('X.dcu'));
end;

procedure TAtlasQuickOpenTests.FindsFormUnitInLargeGroupQuickly;
var
  Input: TAtlasQuickOpenSources;
  Files: TAtlasQuickOpenFiles;
  Order: TArray<Integer>;
  Index: Integer;
  Watch: TStopwatch;
begin
  Input := Default(TAtlasQuickOpenSources);
  Input.Root := 'C:\Gruppe';
  for Index := 1 to 999 do
    Input.ProjectFiles := Input.ProjectFiles + [Format('C:\Gruppe\P%d\Unit%d.pas', [Index mod 20, Index])];
  Input.ProjectFiles := Input.ProjectFiles + ['C:\Gruppe\Haupt\FrmHaupt.pas'];
  Files := TAtlasQuickOpen.Collect(Input, FakeLister);
  Assert.AreEqual(1000, Integer(Length(Files)));
  Watch := TStopwatch.StartNew;
  Order := TAtlasQuickOpen.Order(Files, 'frmhaupt', nil, nil);
  Watch.Stop;
  Assert.IsTrue(Length(Order) >= 1);
  Assert.AreEqual('FrmHaupt.pas', Files[Order[0]].Name);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 50, 'Dauer ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
  // Ohne Eingabe höchstens MaxResults Treffer.
  Assert.AreEqual(TAtlasQuickOpen.MaxResults, Integer(Length(TAtlasQuickOpen.Order(Files, '', nil, nil))));
end;

procedure TAtlasQuickOpenTests.OpenThenRecentThenProjectThenRest;
var
  Files: TAtlasQuickOpenFiles;
  Recent: TAtlasCommandHistory;
begin
  Files := TAtlasQuickOpen.Collect(Sources, FakeLister);
  Recent := TAtlasCommandHistory.Create;
  try
    Recent.Executed(TAtlasQuickOpen.RecentKey('C:\Gruppe\Haupt\Defs.inc'));
    Recent.Executed(TAtlasQuickOpen.RecentKey('C:\Lib\Pfad\Kunden.pas'));
    // Ohne Eingabe: offen, dann zuletzt geöffnet (jüngste zuerst), dann Projekt (.pas vor .dpr …), dann Rest.
    Assert.AreEqual('FrmHaupt.dfm|Kunden.pas|Defs.inc|FrmHaupt.pas|Haupt.dpr|Haupt.dproj|',
      Names(Files, TAtlasQuickOpen.Order(Files, '', ['c:\gruppe\haupt\frmhaupt.dfm'], Recent)));
    // Gleicher Name: .pas vor .dfm.
    Assert.AreEqual('FrmHaupt.pas|FrmHaupt.dfm|', Names(Files, TAtlasQuickOpen.Order(Files, 'frmhaupt', nil, nil)));
    // Die bessere Übereinstimmung schlägt die Stufe.
    Assert.IsTrue(Names(Files, TAtlasQuickOpen.Order(Files, 'haupt', ['C:\Gruppe\Haupt\FrmHaupt.pas'], nil)).StartsWith(
      'Haupt.dpr|Haupt.dproj|FrmHaupt.pas|FrmHaupt.dfm|'));
  finally
    Recent.Free;
  end;
end;

procedure TAtlasQuickOpenTests.PathAndExtensionHelp;
var
  Files: TAtlasQuickOpenFiles;
begin
  Files := TAtlasQuickOpen.Collect(Sources, FakeLister);
  Assert.AreEqual('FrmHaupt.dfm|', Names(Files, TAtlasQuickOpen.Order(Files, 'frmhaupt.dfm', nil, nil)));
  Assert.AreEqual('Defs.inc|', Names(Files, TAtlasQuickOpen.Order(Files, 'haupt\defs', nil, nil)));
  Assert.AreEqual('Defs.inc|', Names(Files, TAtlasQuickOpen.Order(Files, 'haupt/defs', nil, nil)));
  // Wörter des Pfads mit Leerzeichen, halbe Punkte.
  Assert.AreEqual('Kunden.pas|', Names(Files, TAtlasQuickOpen.Order(Files, 'pfad kunden', nil, nil)));
  Assert.AreEqual('', Names(Files, TAtlasQuickOpen.Order(Files, 'xyz', nil, nil)));
  Assert.AreEqual('Haupt\FrmHaupt.pas', TAtlasQuickOpen.RelativeTo('C:\Gruppe\Haupt\FrmHaupt.pas', 'c:\gruppe\'));
  Assert.AreEqual('D:\X.pas', TAtlasQuickOpen.RelativeTo('D:\X.pas', 'C:\Gruppe'));
end;

procedure TAtlasQuickOpenTests.OrdersSymbols;
var
  Order: TArray<Integer>;
begin
  Order := TAtlasQuickOpen.OrderSymbols(['Speichern', 'NeuLaden', 'Laden', 'TKunde'], 'Laden');
  Assert.AreEqual(2, Integer(Length(Order)));
  Assert.AreEqual(2, Order[0]);
  Assert.AreEqual(1, Order[1]);
  Order := TAtlasQuickOpen.OrderSymbols(['B', 'A'], '');
  Assert.AreEqual(0, Order[0]);
  Assert.AreEqual(1, Order[1]);
end;

procedure TAtlasQuickOpenTests.ListBuildsInBackgroundOnlyOnChange;
var
  List: TAtlasQuickOpenList;
  Calls: Integer;
  Gate: TEvent;
  Input: TAtlasQuickOpenSources;
begin
  Calls := 0;
  Gate := TEvent.Create(nil, True, False, '');
  List := TAtlasQuickOpenList.Create(
    function(const AFolder: string; ARecursive: Boolean): TArray<string>
    begin
      TInterlocked.Increment(Calls);
      Gate.WaitFor(5000);
      Result := [AFolder + '\A.pas'];
    end);
  try
    Input := Default(TAtlasQuickOpenSources);
    Input.Folders := ['C:\Eins'];
    List.Refresh(Input);
    // Läuft im Hintergrund: Refresh kehrt sofort zurück, die Liste ist noch leer.
    Assert.IsTrue(List.Building);
    Assert.AreEqual(0, Integer(Length(List.Files)));
    Gate.SetEvent;
    Assert.IsTrue(List.WaitIdle(5000));
    Assert.AreEqual(1, Integer(Length(List.Files)));
    Assert.AreEqual('C:\Eins\A.pas', List.Files[0].FileName);
    // Gleiche Quellen: kein neuer Aufbau.
    List.Refresh(Input);
    Assert.IsTrue(List.WaitIdle(5000));
    Assert.AreEqual(1, Calls);
    // Projektwechsel: neu.
    Input.Folders := ['C:\Zwei'];
    List.Refresh(Input);
    Assert.IsTrue(List.WaitIdle(5000));
    Assert.AreEqual(2, Calls);
    Assert.AreEqual('C:\Zwei\A.pas', List.Files[0].FileName);
  finally
    List.Free;
    Gate.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickOpenTests);

end.
