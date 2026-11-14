unit Atlas.Core.Status.Tests;

// Tests für das Atlas-Statusfeld (#591): Registry, Reihenfolge,
// Gesamtzustand, Kurztext und Tooltip, feste Zeilen (Server, Index, Datei),
// Dateiformat (Kodierung, Zeilenenden) und die Quellen im LSP-Client
// (Antwortzeiten, Ende der Verbindung, Fortschritt).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusRegistryTests = class
  public
    [Test]
    procedure ItemsAreSortedByOrderThenId;
    [Test]
    procedure AddReplacesSameIdAndRemoveDeletes;
    [Test]
    procedure ListenersHearAddChangeAndRemove;
    [Test]
    procedure LineReportsOnlyRealChanges;
    [Test]
    procedure DetachedLineReportsNothing;
    /// <summary>#1356: Die Aktion der Zeile „Server“ gilt nur mit server.statusWindow.</summary>
    [Test]
    procedure ActionFollowsEnabled;
    [Test]
    procedure OverallIsWorstState;
    [Test]
    procedure HiddenLinesDoNotCount;
    [Test]
    procedure FieldTextShowsSummaryOfWorstLine;
    [Test]
    procedure FieldTextAlwaysShowsIndexProgress;
    [Test]
    procedure TooltipListsLinesThatAreNotGreen;
    [Test]
    procedure ParsesHiddenIds;
    [Test]
    procedure ForeignLineAppearsWithoutChanges;
  end;

  [TestFixture]
  TAtlasStatusLinesTests = class
  public
    [Test]
    procedure ServerPhases;
    [Test]
    procedure SlowServerIsYellow;
    /// <summary>#1355: Übersprungene Anfragen machen das Statusfeld gelb und stehen im Text.</summary>
    [Test]
    procedure SkippedRequestsAreYellow;
        [Test]
    procedure IndexWhileBuildingThenUnits;
    [Test]
    procedure FileLineShowsFormatAndTarget;
    [Test]
    procedure UnitsFromStatusAnswer;
  end;

  [TestFixture]
  TAtlasFileFormatTests = class
  public
    [Test]
    procedure DetectsUtf8WithoutBomAndLf;
    [Test]
    procedure DetectsUtf8WithBomAndCrlf;
    [Test]
    procedure DetectsAnsiAndUtf16;
    [Test]
    procedure DetectsMixedAndMissingLineBreaks;
    [Test]
    procedure ConvertsToUtf8BomCrlf;
    [Test]
    procedure ConvertsToAnsiLf;
    [Test]
    procedure SatisfiesTreatsAsciiAsAnsiAndUtf8;
    [Test]
    procedure RejectsInvalidUtf8;
    [Test]
    procedure OffersSixTargets;
  end;

  [TestFixture]
  TAtlasStatusSourcesTests = class
  public
    [Test]
    procedure ClientAveragesLastFiftyResponses;
    [Test]
    procedure ClientMeasuresRequests;
    [Test]
    procedure LongPollingDoesNotCount;
    [Test]
    procedure ClientReportsCloseOnce;
    [Test]
    procedure ProgressReportsChangesAndPercent;
    [Test]
    procedure StatusFieldSettingsRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.Core.Files.Format,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Progress,
  Atlas.Core.Settings.Plugin;

type
  /// <summary>Zeile eines anderen Issues, ohne TAtlasStatusLine (Abnahme: erscheint ohne Änderung).</summary>
  TForeignItem = class(TInterfacedObject, IAtlasStatusItem)
  private
    FClicks: Integer;
  public
    function Id: string;
    function Text: string;
    function Summary: string;
    function State: TAtlasStatusState;
    function Order: Integer;
    function HasAction: Boolean;
    procedure Execute;
    property Clicks: Integer read FClicks;
  end;

  TMemoryStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

{ TForeignItem }

function TForeignItem.Id: string;
begin
  Result := 'test.fehler';
end;

function TForeignItem.Text: string;
begin
  Result := 'Fehler: 2 in dieser Datei';
end;

function TForeignItem.Summary: string;
begin
  Result := '2 Fehler';
end;

function TForeignItem.State: TAtlasStatusState;
begin
  Result := TAtlasStatusState.Red;
end;

function TForeignItem.Order: Integer;
begin
  Result := 5;
end;

function TForeignItem.HasAction: Boolean;
begin
  Result := True;
end;

procedure TForeignItem.Execute;
begin
  Inc(FClicks);
end;

{ TMemoryStore }

constructor TMemoryStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
end;

destructor TMemoryStore.Destroy;
begin
  FValues.Free;
  inherited;
end;

function TMemoryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
var
  mValue: string;
begin
  if FValues.TryGetValue(AName, mValue) then
  begin
    Result := StrToInt(mValue);
  end
  else
  begin
    Result := ADefault;
  end;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function Line(const ARegistry: IAtlasStatusRegistry; const AId: string; AOrder: Integer;
  AState: TAtlasStatusState; const AText, ASummary: string): IAtlasStatusItem;
var
  mItem: TAtlasStatusLine;
begin
  mItem := TAtlasStatusLine.Create(ARegistry, AId, AOrder);
  Result := mItem;
  mItem.Update(AText, AState, ASummary);
end;

function Ids(const AItems: TArray<IAtlasStatusItem>): string;
var
  mItem: IAtlasStatusItem;
begin
  Result := '';
  for mItem in AItems do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mItem.Id;
  end;
end;

function Bytes(const AValues: array of Byte): TBytes;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AValues));
  for mIndex := 0 to High(AValues) do
  begin
    Result[mIndex] := AValues[mIndex];
  end;
end;

{ TAtlasStatusRegistryTests }

procedure TAtlasStatusRegistryTests.ItemsAreSortedByOrderThenId;
var
  mRegistry: IAtlasStatusRegistry;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mRegistry.Add(Line(nil, 'c', 20, TAtlasStatusState.Green, 'C', ''));
  mRegistry.Add(Line(nil, 'b', 10, TAtlasStatusState.Green, 'B', ''));
  mRegistry.Add(Line(nil, 'a', 20, TAtlasStatusState.Green, 'A', ''));
  mRegistry.Add(Line(nil, 'z', 0, TAtlasStatusState.Green, 'Z', ''));
  Assert.AreEqual('z b a c', Ids(mRegistry.Items));
end;

procedure TAtlasStatusRegistryTests.AddReplacesSameIdAndRemoveDeletes;
var
  mRegistry: IAtlasStatusRegistry;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mRegistry.Add(Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'alt', ''));
  mRegistry.Add(Line(nil, 'ATLAS.SERVER', 30, TAtlasStatusState.Red, 'neu', ''));
  mRegistry.Add(Line(nil, 'atlas.index', 10, TAtlasStatusState.Green, 'Index', ''));
  Assert.AreEqual(2, Integer(Length(mRegistry.Items)));
  Assert.AreEqual('neu', mRegistry.Find('atlas.server').Text);
  Assert.AreEqual('atlas.index ATLAS.SERVER', Ids(mRegistry.Items), 'neue Reihenfolge gilt');
  mRegistry.Remove('atlas.server');
  Assert.IsNull(mRegistry.Find('atlas.server'));
  Assert.AreEqual('atlas.index', Ids(mRegistry.Items));
  mRegistry.Remove('gibt-es-nicht');
  Assert.AreEqual(1, Integer(Length(mRegistry.Items)));
end;

procedure TAtlasStatusRegistryTests.ListenersHearAddChangeAndRemove;
var
  mRegistry: IAtlasStatusRegistry;
  mCalls, mHandle, mBefore: Integer;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mCalls := 0;
  mHandle := mRegistry.AddListener(
    procedure
    begin
      Inc(mCalls);
    end);
  mBefore := mRegistry.Version;
  mRegistry.Add(Line(nil, 'a', 0, TAtlasStatusState.Green, 'A', ''));
  mRegistry.Changed;
  mRegistry.Remove('a');
  Assert.AreEqual(3, mCalls);
  Assert.AreEqual(mBefore + 3, mRegistry.Version);
  mRegistry.RemoveListener(mHandle);
  mRegistry.Changed;
  Assert.AreEqual(3, mCalls, 'abgemeldet');
end;

procedure TAtlasStatusRegistryTests.LineReportsOnlyRealChanges;
var
  mRegistry: IAtlasStatusRegistry;
  mItem: TAtlasStatusLine;
  mRef: IAtlasStatusItem;
  mCalls: Integer;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mItem := TAtlasStatusLine.Create(mRegistry, 'atlas.index', 10);
  mRef := mItem;
  mRegistry.Add(mRef);
  mCalls := 0;
  mRegistry.AddListener(
    procedure
    begin
      Inc(mCalls);
    end);
  mItem.Update('Index: wird aufgebaut (10 %)', TAtlasStatusState.Yellow, 'Index 10 %');
  Assert.AreEqual(1, mCalls);
  mItem.Update('Index: wird aufgebaut (10 %)', TAtlasStatusState.Yellow, 'Index 10 %');
  Assert.AreEqual(1, mCalls, 'gleicher Inhalt meldet nichts');
  mItem.Update('Index: 120 Units', TAtlasStatusState.Green);
  Assert.AreEqual(2, mCalls);
  Assert.AreEqual('', mRef.Summary);
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(mRef.State));
  mRegistry.Remove('atlas.index');
  mItem.Detach;
end;

procedure TAtlasStatusRegistryTests.DetachedLineReportsNothing;
var
  mRegistry: IAtlasStatusRegistry;
  mItem: TAtlasStatusLine;
  mRef: IAtlasStatusItem;
  mCalls: Integer;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mItem := TAtlasStatusLine.Create(mRegistry, 'x', 0);
  mRef := mItem;
  mCalls := 0;
  mRegistry.AddListener(
    procedure
    begin
      Inc(mCalls);
    end);
  mItem.Detach;
  mItem.Update('neu', TAtlasStatusState.Red);
  Assert.AreEqual(0, mCalls);
  Assert.AreEqual('neu', mRef.Text);
end;

procedure TAtlasStatusRegistryTests.ActionFollowsEnabled;
var
  mRegistry: IAtlasStatusRegistry;
  mRef: IAtlasStatusItem;
  mEnabled: Boolean;
  mRuns: Integer;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mEnabled := False;
  mRuns := 0;
  mRef := TAtlasStatusLine.Create(mRegistry, 'x', 0,
    procedure
    begin
      Inc(mRuns);
    end,
    function: Boolean
    begin
      Result := mEnabled;
    end);
  Assert.IsFalse(mRef.HasAction);
  mRef.Execute;
  Assert.AreEqual(0, mRuns, 'abgeschaltet tut ein Klick nichts');
  mEnabled := True;
  Assert.IsTrue(mRef.HasAction);
  mRef.Execute;
  Assert.AreEqual(1, mRuns);
end;

procedure TAtlasStatusRegistryTests.OverallIsWorstState;
var
  mItems: TArray<IAtlasStatusItem>;
begin
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusSummary.Overall(nil)), 'ohne Zeilen');
  mItems := [Line(nil, 'a', 0, TAtlasStatusState.Neutral, 'A', '')];
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusSummary.Overall(mItems)));
  mItems := mItems + [Line(nil, 'b', 1, TAtlasStatusState.Green, 'B', '')];
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusSummary.Overall(mItems)));
  mItems := mItems + [Line(nil, 'c', 2, TAtlasStatusState.Yellow, 'C', '')];
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusSummary.Overall(mItems)));
  mItems := [Line(nil, 'd', 3, TAtlasStatusState.Red, 'D', '')] + mItems;
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusSummary.Overall(mItems)));
end;

procedure TAtlasStatusRegistryTests.HiddenLinesDoNotCount;
var
  mItems, mVisible: TArray<IAtlasStatusItem>;
begin
  mItems := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'S', ''),
    Line(nil, 'atlas.file', 20, TAtlasStatusState.Yellow, 'F', '')];
  mVisible := TAtlasStatusSummary.Visible(mItems, ['ATLAS.FILE', ' gibt.es.nicht ']);
  Assert.AreEqual('atlas.server', Ids(mVisible));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusSummary.Overall(mVisible)));
  Assert.AreEqual(2, Integer(Length(TAtlasStatusSummary.Visible(mItems, nil))));
end;

procedure TAtlasStatusRegistryTests.FieldTextShowsSummaryOfWorstLine;
var
  mItems: TArray<IAtlasStatusItem>;
begin
  mItems := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'Server: läuft', 'unwichtig'),
    Line(nil, 'atlas.index', 10, TAtlasStatusState.Yellow, 'Index', 'Index 45 %')];
  Assert.AreEqual('Atlas · Index 45 %', TAtlasStatusSummary.FieldText(mItems, True));
  Assert.AreEqual('Atlas', TAtlasStatusSummary.FieldText(mItems, False), 'showSummary aus');
  mItems := mItems + [Line(nil, 'test.fehler', 5, TAtlasStatusState.Red, 'Fehler', '2 Fehler')];
  Assert.AreEqual('Atlas · 2 Fehler', TAtlasStatusSummary.FieldText(mItems, True), 'rot vor gelb');
  mItems := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'Server: läuft', 'läuft')];
  Assert.AreEqual('Atlas', TAtlasStatusSummary.FieldText(mItems, True), 'grün ohne Kurztext');
  mItems := [Line(nil, 'a', 0, TAtlasStatusState.Red, 'A', ''), Line(nil, 'b', 1, TAtlasStatusState.Red, 'B', 'B!')];
  Assert.AreEqual('Atlas', TAtlasStatusSummary.FieldText(mItems, True), 'wichtigste Zeile ohne Kurztext');
end;

procedure TAtlasStatusRegistryTests.FieldTextAlwaysShowsIndexProgress;
var
  mItems: TArray<IAtlasStatusItem>;
begin
  mItems := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Yellow, 'Server: langsam', 'Server langsam'),
    Line(nil, 'atlas.index', 10, TAtlasStatusState.Yellow, 'Index', 'Index 45 %')];
  Assert.AreEqual('Atlas · Server langsam', TAtlasStatusSummary.FieldText(mItems, True), 'ohne Fortschritt');
  Assert.AreEqual('Atlas · Server langsam · Index 45 %', TAtlasStatusSummary.FieldText(mItems, True, 'atlas.index'));
  Assert.AreEqual('Atlas · Index 45 %', TAtlasStatusSummary.FieldText(mItems, False, 'atlas.index'),
    'Fortschritt auch ohne Kurztext');
  mItems := [Line(nil, 'atlas.index', 10, TAtlasStatusState.Yellow, 'Index', 'Index 45 %')];
  Assert.AreEqual('Atlas · Index 45 %', TAtlasStatusSummary.FieldText(mItems, True, 'ATLAS.INDEX'), 'nicht doppelt');
  mItems := [Line(nil, 'atlas.index', 10, TAtlasStatusState.Green, 'Index: 1569 Units', '')];
  Assert.AreEqual('Atlas', TAtlasStatusSummary.FieldText(mItems, True, 'atlas.index'), 'fertig: nichts');
end;

procedure TAtlasStatusRegistryTests.TooltipListsLinesThatAreNotGreen;
var
  mItems: TArray<IAtlasStatusItem>;
begin
  mItems := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'Server: läuft', '')];
  Assert.AreEqual('Atlas: alles in Ordnung', TAtlasStatusSummary.Tooltip(mItems));
  mItems := mItems + [Line(nil, 'atlas.index', 10, TAtlasStatusState.Yellow, 'Index: wird aufgebaut', ''),
    Line(nil, 'atlas.file', 20, TAtlasStatusState.Neutral, 'Datei: keine aktiv', '')];
  Assert.AreEqual('Index: wird aufgebaut' + sLineBreak + 'Datei: keine aktiv', TAtlasStatusSummary.Tooltip(mItems));
end;

procedure TAtlasStatusRegistryTests.ParsesHiddenIds;
var
  mParsed: TArray<string>;
begin
  mParsed := TAtlasStatusSummary.ParseIds(' atlas.file, atlas.index;test  ');
  Assert.AreEqual(3, Integer(Length(mParsed)));
  Assert.AreEqual('atlas.file', mParsed[0]);
  Assert.AreEqual('test', mParsed[2]);
  Assert.AreEqual('atlas.file, atlas.index, test', TAtlasStatusSummary.JoinIds(mParsed));
  Assert.AreEqual(0, Integer(Length(TAtlasStatusSummary.ParseIds(''))));
end;

procedure TAtlasStatusRegistryTests.ForeignLineAppearsWithoutChanges;
var
  mRegistry: IAtlasStatusRegistry;
  mForeign: TForeignItem;
  mRef: IAtlasStatusItem;
  mItems: TArray<IAtlasStatusItem>;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mRegistry.Add(Line(nil, TAtlasStatusLines.cServerId, TAtlasStatusLines.cServerOrder, TAtlasStatusState.Green,
    'Server: läuft', ''));
  mRegistry.Add(Line(nil, TAtlasStatusLines.cIndexId, TAtlasStatusLines.cIndexOrder, TAtlasStatusState.Green,
    'Index: 10 Units', ''));
  mForeign := TForeignItem.Create;
  mRef := mForeign;
  mRegistry.Add(mRef);
  mItems := TAtlasStatusSummary.Visible(mRegistry.Items, nil);
  Assert.AreEqual('atlas.server test.fehler atlas.index', Ids(mItems));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusSummary.Overall(mItems)));
  Assert.AreEqual('Atlas · 2 Fehler', TAtlasStatusSummary.FieldText(mItems, True));
  Assert.Contains(TAtlasStatusSummary.Tooltip(mItems), 'Fehler: 2 in dieser Datei');
  mItems[1].Execute;
  Assert.AreEqual(1, mForeign.Clicks);
end;

{ TAtlasStatusLinesTests }

procedure TAtlasStatusLinesTests.ServerPhases;
var
  mInfo: TAtlasServerInfo;
begin
  mInfo := Default(TAtlasServerInfo);
  Assert.AreEqual('Server: nicht gestartet', TAtlasStatusLines.ServerText(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.ServerState(mInfo)));
  mInfo.Phase := TAtlasServerPhase.Starting;
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.ServerState(mInfo)));
  mInfo.Phase := TAtlasServerPhase.Running;
  mInfo.Version := '1.0.0';
  mInfo.AverageMs := 12.4;
  mInfo.Samples := 50;
  Assert.AreEqual('Server: läuft, 12 ms im Mittel der letzten 50 Anfragen, Version 1.0.0',
    TAtlasStatusLines.ServerText(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.ServerState(mInfo)));
  Assert.AreEqual('', TAtlasStatusLines.ServerSummary(mInfo));
  mInfo.Phase := TAtlasServerPhase.Stopped;
  // Ohne „von Atlas beendet“ ist der Server abgestürzt (#754).
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusLines.ServerState(mInfo)));
  Assert.AreEqual('Server abgestürzt', TAtlasStatusLines.ServerSummary(mInfo));
  mInfo := Default(TAtlasServerInfo);
  mInfo.Phase := TAtlasServerPhase.Failed;
  mInfo.Error := 'AtlasServer.exe nicht gefunden';
  Assert.AreEqual('Server: Start fehlgeschlagen (AtlasServer.exe nicht gefunden)',
    TAtlasStatusLines.ServerText(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusLines.ServerState(mInfo)));
end;

procedure TAtlasStatusLinesTests.SlowServerIsYellow;
var
  mInfo: TAtlasServerInfo;
begin
  mInfo := Default(TAtlasServerInfo);
  mInfo.Phase := TAtlasServerPhase.Running;
  mInfo.AverageMs := TAtlasStatusLines.cSlowMs;
  mInfo.Samples := 3;
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.ServerState(mInfo)));
  Assert.Contains(TAtlasStatusLines.ServerText(mInfo), '(langsam)');
  Assert.AreEqual('Server langsam', TAtlasStatusLines.ServerSummary(mInfo));
  mInfo.Samples := 0;
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.ServerState(mInfo)), 'ohne Messung');
end;

procedure TAtlasStatusLinesTests.SkippedRequestsAreYellow;
var
  mInfo: TAtlasServerInfo;
begin
  mInfo := Default(TAtlasServerInfo);
  mInfo.Phase := TAtlasServerPhase.Running;
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.ServerState(mInfo)));
  mInfo.Skipped := 1;
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.ServerState(mInfo)));
  Assert.IsTrue(TAtlasStatusLines.ServerText(mInfo).EndsWith(', 1 Anfrage übersprungen nach Absturz'));
  Assert.AreEqual('übersprungen nach Absturz', TAtlasStatusLines.ServerSummary(mInfo));
  mInfo.Skipped := 2;
  Assert.AreEqual('Server läuft, 2 Anfragen übersprungen nach Absturz', TAtlasStatusLines.ServerBrief(mInfo));
  Assert.AreEqual('2 Anfragen übersprungen nach Absturz', TAtlasStatusLines.ServerDetail(mInfo));
end;

procedure TAtlasStatusLinesTests.IndexWhileBuildingThenUnits;
var
  mInfo: TAtlasIndexInfo;
begin
  mInfo := Default(TAtlasIndexInfo);
  mInfo.Units := -1;
  mInfo.Indexing := True;
  mInfo.Percent := 45;
  Assert.AreEqual('Index: wird aufgebaut (45 %)', TAtlasStatusLines.IndexText(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.IndexState(mInfo)));
  Assert.AreEqual('Index 45 %', TAtlasStatusLines.IndexSummary(mInfo));
  mInfo.Percent := -1;
  mInfo.Units := 80;
  Assert.AreEqual('Index: wird aufgebaut, bisher 80 Units', TAtlasStatusLines.IndexText(mInfo));
  Assert.AreEqual('Index …', TAtlasStatusLines.IndexSummary(mInfo));
  mInfo.Indexing := False;
  mInfo.Units := 1234;
  Assert.AreEqual('Index: 1234 Units', TAtlasStatusLines.IndexText(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.IndexState(mInfo)));
  Assert.AreEqual('', TAtlasStatusLines.IndexSummary(mInfo));
  mInfo.Units := -1;
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.IndexState(mInfo)));
end;

procedure TAtlasStatusLinesTests.FileLineShowsFormatAndTarget;
var
  mInfo: TAtlasFileInfo;
begin
  mInfo := Default(TAtlasFileInfo);
  Assert.AreEqual('Datei: keine aktiv', TAtlasStatusLines.FileText(mInfo));
  mInfo.Name := 'Main.pas';
  mInfo.Known := True;
  mInfo.Format := TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8, TAtlasLineBreak.LF);
  Assert.AreEqual('Datei Main.pas: UTF-8 ohne BOM, LF', TAtlasStatusLines.FileText(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.FileState(mInfo)));
  mInfo.HasTarget := True;
  mInfo.Target := TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8Bom, TAtlasLineBreak.CRLF);
  Assert.AreEqual('Datei Main.pas: UTF-8 ohne BOM, LF → UTF-8 mit BOM, CRLF beim Speichern',
    TAtlasStatusLines.FileText(mInfo));
  mInfo.HasTarget := False;
  mInfo.Format.LineBreak := TAtlasLineBreak.Mixed;
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.FileState(mInfo)));
  mInfo.Known := False;
  Assert.AreEqual('Datei Main.pas: noch nicht gespeichert', TAtlasStatusLines.FileText(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.FileState(mInfo)));
end;

procedure TAtlasStatusLinesTests.UnitsFromStatusAnswer;
begin
  Assert.AreEqual(57, TAtlasStatusLines.UnitsOf('{"units":57,"symbols":900}'));
  Assert.AreEqual(-1, TAtlasStatusLines.UnitsOf(''));
  Assert.AreEqual(-1, TAtlasStatusLines.UnitsOf('[1,2]'));
  Assert.AreEqual(-1, TAtlasStatusLines.UnitsOf('{"symbols":3}'));
end;

{ TAtlasFileFormatTests }

procedure TAtlasFileFormatTests.DetectsUtf8WithoutBomAndLf;
var
  mFormat: TAtlasFileFormat;
begin
  mFormat := TAtlasFileFormats.Detect(TEncoding.UTF8.GetBytes('unit Grüße;'#10'interface'#10));
  Assert.AreEqual('UTF-8 ohne BOM, LF', mFormat.Text);
  mFormat := TAtlasFileFormats.Detect(TEncoding.UTF8.GetBytes('unit A;'#10));
  Assert.AreEqual('UTF-8 ohne BOM, LF', mFormat.Text, 'reines ASCII');
end;

procedure TAtlasFileFormatTests.DetectsUtf8WithBomAndCrlf;
begin
  Assert.AreEqual('UTF-8 mit BOM, CRLF', TAtlasFileFormats.Detect(TEncoding.UTF8.GetPreamble +
    TEncoding.UTF8.GetBytes('unit Ä;'#13#10'end.'#13#10)).Text);
end;

procedure TAtlasFileFormatTests.DetectsAnsiAndUtf16;
begin
  // „ä“ in Windows-1252 allein ist kein gültiges UTF-8.
  Assert.AreEqual('ANSI, CRLF', TAtlasFileFormats.Detect(Bytes([$61, $E4, 13, 10])).Text);
  Assert.AreEqual('UTF-16 LE, LF', TAtlasFileFormats.Detect(Bytes([$FF, $FE, $61, 0, 10, 0])).Text);
  Assert.AreEqual('UTF-16 BE, ohne Zeilenende', TAtlasFileFormats.Detect(Bytes([$FE, $FF, 0, $61])).Text);
end;

procedure TAtlasFileFormatTests.DetectsMixedAndMissingLineBreaks;
begin
  Assert.AreEqual(Ord(TAtlasLineBreak.Mixed), Ord(TAtlasFileFormats.LineBreakOf('a'#13#10'b'#10'c')));
  Assert.AreEqual(Ord(TAtlasLineBreak.None), Ord(TAtlasFileFormats.LineBreakOf('abc')));
  Assert.AreEqual(Ord(TAtlasLineBreak.CR), Ord(TAtlasFileFormats.LineBreakOf('a'#13'b'#13)));
  Assert.AreEqual(Ord(TAtlasLineBreak.CRLF), Ord(TAtlasFileFormats.LineBreakOf('a'#13#10)));
  Assert.AreEqual('gemischte Zeilenenden', TAtlasFileFormats.LineBreakText(TAtlasLineBreak.Mixed));
end;

procedure TAtlasFileFormatTests.ConvertsToUtf8BomCrlf;
var
  mSource, mConverted: TBytes;
  mTarget: TAtlasFileFormat;
begin
  // Abnahme: UTF-8 ohne BOM, LF → UTF-8 mit BOM, CRLF.
  mSource := TEncoding.UTF8.GetBytes('unit Grüße;'#10'end.'#10);
  mTarget := TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8Bom, TAtlasLineBreak.CRLF);
  Assert.IsFalse(TAtlasFileFormats.Satisfies(mSource, mTarget));
  mConverted := TAtlasFileFormats.Convert(mSource, mTarget);
  Assert.AreEqual('UTF-8 mit BOM, CRLF', TAtlasFileFormats.Detect(mConverted).Text);
  Assert.AreEqual('unit Grüße;'#13#10'end.'#13#10, TAtlasFileFormats.Decode(mConverted, TAtlasFileEncoding.Utf8Bom));
  Assert.IsTrue(TAtlasFileFormats.Satisfies(mConverted, mTarget));
  // Und zurück, gemischte Zeilenenden werden vereinheitlicht.
  mConverted := TAtlasFileFormats.Convert(TEncoding.UTF8.GetBytes('a'#13#10'b'#10'c'#13),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8, TAtlasLineBreak.LF));
  Assert.AreEqual('a'#10'b'#10'c'#10, TEncoding.UTF8.GetString(mConverted));
end;

procedure TAtlasFileFormatTests.ConvertsToAnsiLf;
var
  mConverted: TBytes;
begin
  mConverted := TAtlasFileFormats.Convert(TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes('x := 1;'#13#10),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Ansi, TAtlasLineBreak.LF));
  Assert.AreEqual('x := 1;'#10, TEncoding.ANSI.GetString(mConverted));
  Assert.AreEqual(0, TAtlasFileFormats.AnsiLosses('x := 1;'));
end;

procedure TAtlasFileFormatTests.SatisfiesTreatsAsciiAsAnsiAndUtf8;
var
  mAscii: TBytes;
begin
  mAscii := TEncoding.UTF8.GetBytes('unit A;'#13#10);
  Assert.IsTrue(TAtlasFileFormats.Satisfies(mAscii, TAtlasFileFormat.Create(TAtlasFileEncoding.Ansi,
    TAtlasLineBreak.CRLF)));
  Assert.IsTrue(TAtlasFileFormats.Satisfies(mAscii, TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8,
    TAtlasLineBreak.CRLF)));
  Assert.IsFalse(TAtlasFileFormats.Satisfies(mAscii, TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8,
    TAtlasLineBreak.LF)));
  Assert.IsFalse(TAtlasFileFormats.Satisfies(TEncoding.UTF8.GetBytes('ä'), TAtlasFileFormat.Create(
    TAtlasFileEncoding.Ansi, TAtlasLineBreak.LF)), 'Umlaut in UTF-8 ist kein ANSI');
  Assert.IsTrue(TAtlasFileFormats.Satisfies(TEncoding.UTF8.GetBytes('ä'), TAtlasFileFormat.Create(
    TAtlasFileEncoding.Utf8, TAtlasLineBreak.LF)), 'ohne Zeilenende passt jedes');
end;

procedure TAtlasFileFormatTests.RejectsInvalidUtf8;
begin
  Assert.IsFalse(TAtlasFileFormats.IsUtf8(Bytes([$C3]), 0), 'abgeschnitten');
  Assert.IsFalse(TAtlasFileFormats.IsUtf8(Bytes([$C3, $41]), 0), 'kein Folgebyte');
  Assert.IsFalse(TAtlasFileFormats.IsUtf8(Bytes([$C0, $80]), 0), 'überlang');
  Assert.IsTrue(TAtlasFileFormats.IsUtf8(Bytes([$E2, $82, $AC, $41]), 0), 'Euro');
  Assert.IsTrue(TAtlasFileFormats.IsUtf8(nil, 0));
end;

procedure TAtlasFileFormatTests.OffersSixTargets;
var
  mTargets: TArray<TAtlasFileFormat>;
begin
  mTargets := TAtlasFileFormats.Targets;
  Assert.AreEqual(6, Integer(Length(mTargets)));
  Assert.AreEqual('UTF-8 mit BOM, CRLF', mTargets[0].Text);
  Assert.AreEqual('ANSI, LF', mTargets[5].Text);
  Assert.IsTrue(mTargets[0].Equals(TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8Bom, TAtlasLineBreak.CRLF)));
  Assert.IsFalse(mTargets[0].Equals(mTargets[1]));
end;

{ TAtlasStatusSourcesTests }

procedure TAtlasStatusSourcesTests.ClientAveragesLastFiftyResponses;
var
  mClient: TLspClient;
  mSamples, mIndex: Integer;
begin
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    Assert.AreEqual(0.0, mClient.AverageMs(mSamples), 0.001);
    Assert.AreEqual(0, mSamples);
    mClient.AddResponseTime(10);
    mClient.AddResponseTime(30);
    Assert.AreEqual(20.0, mClient.AverageMs(mSamples), 0.001);
    Assert.AreEqual(2, mSamples);
    // 60 weitere: nur die letzten 50 zählen.
    for mIndex := 1 to 10 do
    begin
      mClient.AddResponseTime(1000);
    end;
    for mIndex := 1 to TLspResponseTimes.cSamples do
    begin
      mClient.AddResponseTime(4);
    end;
    Assert.AreEqual(4.0, mClient.AverageMs(mSamples), 0.001);
    Assert.AreEqual(TLspResponseTimes.cSamples, mSamples);
  finally
    mClient.Free;
  end;
end;

procedure TAtlasStatusSourcesTests.ClientMeasuresRequests;
var
  mClient: TLspClient;
  mSamples: Integer;
begin
  mClient := nil;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
      mClient.Receive(TLspClient.Frame('{"jsonrpc":"2.0","id":1,"result":null}'), Length(TLspClient.Frame(
        '{"jsonrpc":"2.0","id":1,"result":null}')));
    end);
  try
    mClient.Request('test', nil, 1000).Free;
    mClient.AverageMs(mSamples);
    Assert.AreEqual(1, mSamples);
  finally
    mClient.Free;
  end;
end;

procedure TAtlasStatusSourcesTests.LongPollingDoesNotCount;
var
  mClient: TLspClient;
  mSamples: Integer;
begin
  // Rückmeldung 15.10.2026: workspace/diagnostic wartet absichtlich bis zu 10 s.
  Assert.IsFalse(TLspClient.CountsResponseTime('workspace/diagnostic'));
  Assert.IsTrue(TLspClient.CountsResponseTime('textDocument/diagnostic'));
  mClient := nil;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
      mClient.Receive(TLspClient.Frame('{"jsonrpc":"2.0","id":1,"result":null}'), Length(TLspClient.Frame(
        '{"jsonrpc":"2.0","id":1,"result":null}')));
    end);
  try
    mClient.Request('workspace/diagnostic', nil, 1000).Free;
    mClient.AverageMs(mSamples);
    Assert.AreEqual(0, mSamples);
  finally
    mClient.Free;
  end;
end;

procedure TAtlasStatusSourcesTests.ClientReportsCloseOnce;
var
  mClient: TLspClient;
  mCalls: Integer;
begin
  mCalls := 0;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    mClient.OnClosed :=
      procedure
      begin
        Inc(mCalls);
      end;
    mClient.Close;
    mClient.Close;
    Assert.AreEqual(1, mCalls);
    Assert.IsTrue(mClient.Closed);
  finally
    mClient.Free;
  end;
  Assert.AreEqual(1, mCalls, 'Freigeben meldet nicht noch einmal');
end;

procedure SendProgress(const AProgress: ILspProgress; const AJson: string);
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    AProgress.Handle(mValue);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasStatusSourcesTests.ProgressReportsChangesAndPercent;
var
  mProgress: ILspProgress;
  mCalls, mPercent: Integer;
begin
  mProgress := TLspProgress.Create;
  mCalls := 0;
  mProgress.SetOnChanged(
    procedure
    begin
      Inc(mCalls);
    end);
  Assert.IsFalse(mProgress.Active(mPercent));
  Assert.AreEqual(-1, mPercent);
  SendProgress(mProgress, '{"token":"atlas-index","value":{"kind":"begin","title":"Index"}}');
  Assert.IsTrue(mProgress.Active(mPercent));
  Assert.AreEqual(-1, mPercent);
  SendProgress(mProgress, '{"token":"atlas-index","value":{"kind":"report","percentage":45}}');
  Assert.IsTrue(mProgress.Active(mPercent));
  Assert.AreEqual(45, mPercent);
  SendProgress(mProgress, '{"token":"atlas-index","value":{"kind":"end"}}');
  Assert.IsFalse(mProgress.Active(mPercent));
  Assert.AreEqual(3, mCalls);
  mProgress.SetOnChanged(nil);
  SendProgress(mProgress, '{"token":"x","value":{"kind":"begin"}}');
  Assert.AreEqual(3, mCalls);
end;

procedure TAtlasStatusSourcesTests.StatusFieldSettingsRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.StatusField, 'statusField.enabled: Vorgabe an');
  Assert.IsTrue(mSettings.StatusFieldSummary, 'statusField.showSummary: Vorgabe an');
  Assert.AreEqual('', mSettings.StatusFieldHidden);
  Assert.AreEqual('both', mSettings.StatusFieldToggles, 'statusField.openToggles: Vorgabe beide');
  Assert.AreEqual('statusField', mSettings.IndexProgressPlace, 'statusField.indexProgress: Vorgabe Statusfeld');
  Assert.IsTrue(mSettings.IndexProgressInField);
  Assert.IsFalse(mSettings.IndexProgressInMenu);
  Assert.IsTrue(mSettings.StatusTogglesOnRightClick);
  Assert.IsTrue(mSettings.StatusTogglesOnDoubleClick);
  mStore := TMemoryStore.Create;
  mSettings.StatusField := False;
  mSettings.StatusFieldSummary := False;
  mSettings.StatusFieldToggles := 'doubleClick';
  mSettings.IndexProgressPlace := 'menu';
  mSettings.StatusFieldHidden := ' atlas.file, test.fehler ';
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.StatusField);
  Assert.IsFalse(mLoaded.StatusFieldSummary);
  Assert.AreEqual('doubleClick', mLoaded.StatusFieldToggles);
  Assert.AreEqual('menu', mLoaded.IndexProgressPlace);
  Assert.IsFalse(mLoaded.IndexProgressInField);
  Assert.IsTrue(mLoaded.IndexProgressInMenu);
  // Statusfeld aus: Der Fortschritt weicht in den Menütitel aus.
  mLoaded.IndexProgressPlace := 'statusField';
  Assert.IsFalse(mLoaded.IndexProgressInField, 'Statusfeld aus');
  Assert.IsTrue(mLoaded.IndexProgressInMenu, 'Statusfeld aus');
  mLoaded.IndexProgressPlace := ' OFF ';
  mLoaded.Normalize;
  Assert.AreEqual('off', mLoaded.IndexProgressPlace);
  Assert.IsFalse(mLoaded.IndexProgressInField);
  Assert.IsFalse(mLoaded.IndexProgressInMenu);
  Assert.IsFalse(mLoaded.StatusTogglesOnRightClick, 'nur Doppelklick');
  Assert.IsTrue(mLoaded.StatusTogglesOnDoubleClick);
  // Groß-/Kleinschreibung egal, Unbekanntes wird zur Vorgabe.
  mSettings.StatusFieldToggles := ' RIGHTCLICK ';
  mSettings.Normalize;
  Assert.AreEqual('rightClick', mSettings.StatusFieldToggles);
  Assert.IsTrue(mSettings.StatusTogglesOnRightClick);
  Assert.IsFalse(mSettings.StatusTogglesOnDoubleClick, 'nur Rechtsklick');
  mSettings.StatusFieldToggles := 'dreifach';
  mSettings.Normalize;
  Assert.AreEqual('both', mSettings.StatusFieldToggles);
  Assert.AreEqual('atlas.file, test.fehler', mLoaded.StatusFieldHidden);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusRegistryTests);
  TDUnitX.RegisterTestFixture(TAtlasStatusLinesTests);
  TDUnitX.RegisterTestFixture(TAtlasFileFormatTests);
  TDUnitX.RegisterTestFixture(TAtlasStatusSourcesTests);

end.
