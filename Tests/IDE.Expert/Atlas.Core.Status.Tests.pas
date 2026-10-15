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
    [Test]
    procedure OverallIsWorstState;
    [Test]
    procedure HiddenLinesDoNotCount;
    [Test]
    procedure FieldTextShowsSummaryOfWorstLine;
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
  Value: string;
begin
  if FValues.TryGetValue(AName, Value) then
    Result := StrToInt(Value)
  else
    Result := ADefault;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function Line(const ARegistry: IAtlasStatusRegistry; const AId: string; AOrder: Integer;
  AState: TAtlasStatusState; const AText, ASummary: string): IAtlasStatusItem;
var
  Item: TAtlasStatusLine;
begin
  Item := TAtlasStatusLine.Create(ARegistry, AId, AOrder);
  Result := Item;
  Item.Update(AText, AState, ASummary);
end;

function Ids(const AItems: TArray<IAtlasStatusItem>): string;
var
  Item: IAtlasStatusItem;
begin
  Result := '';
  for Item in AItems do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Item.Id;
  end;
end;

function Bytes(const AValues: array of Byte): TBytes;
var
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
    Result[Index] := AValues[Index];
end;

{ TAtlasStatusRegistryTests }

procedure TAtlasStatusRegistryTests.ItemsAreSortedByOrderThenId;
var
  Registry: IAtlasStatusRegistry;
begin
  Registry := TAtlasStatusRegistry.Create;
  Registry.Add(Line(nil, 'c', 20, TAtlasStatusState.Green, 'C', ''));
  Registry.Add(Line(nil, 'b', 10, TAtlasStatusState.Green, 'B', ''));
  Registry.Add(Line(nil, 'a', 20, TAtlasStatusState.Green, 'A', ''));
  Registry.Add(Line(nil, 'z', 0, TAtlasStatusState.Green, 'Z', ''));
  Assert.AreEqual('z b a c', Ids(Registry.Items));
end;

procedure TAtlasStatusRegistryTests.AddReplacesSameIdAndRemoveDeletes;
var
  Registry: IAtlasStatusRegistry;
begin
  Registry := TAtlasStatusRegistry.Create;
  Registry.Add(Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'alt', ''));
  Registry.Add(Line(nil, 'ATLAS.SERVER', 30, TAtlasStatusState.Red, 'neu', ''));
  Registry.Add(Line(nil, 'atlas.index', 10, TAtlasStatusState.Green, 'Index', ''));
  Assert.AreEqual(2, Integer(Length(Registry.Items)));
  Assert.AreEqual('neu', Registry.Find('atlas.server').Text);
  Assert.AreEqual('atlas.index ATLAS.SERVER', Ids(Registry.Items), 'neue Reihenfolge gilt');
  Registry.Remove('atlas.server');
  Assert.IsNull(Registry.Find('atlas.server'));
  Assert.AreEqual('atlas.index', Ids(Registry.Items));
  Registry.Remove('gibt-es-nicht');
  Assert.AreEqual(1, Integer(Length(Registry.Items)));
end;

procedure TAtlasStatusRegistryTests.ListenersHearAddChangeAndRemove;
var
  Registry: IAtlasStatusRegistry;
  Calls, Handle, Before: Integer;
begin
  Registry := TAtlasStatusRegistry.Create;
  Calls := 0;
  Handle := Registry.AddListener(
    procedure
    begin
      Inc(Calls);
    end);
  Before := Registry.Version;
  Registry.Add(Line(nil, 'a', 0, TAtlasStatusState.Green, 'A', ''));
  Registry.Changed;
  Registry.Remove('a');
  Assert.AreEqual(3, Calls);
  Assert.AreEqual(Before + 3, Registry.Version);
  Registry.RemoveListener(Handle);
  Registry.Changed;
  Assert.AreEqual(3, Calls, 'abgemeldet');
end;

procedure TAtlasStatusRegistryTests.LineReportsOnlyRealChanges;
var
  Registry: IAtlasStatusRegistry;
  Item: TAtlasStatusLine;
  Ref: IAtlasStatusItem;
  Calls: Integer;
begin
  Registry := TAtlasStatusRegistry.Create;
  Item := TAtlasStatusLine.Create(Registry, 'atlas.index', 10);
  Ref := Item;
  Registry.Add(Ref);
  Calls := 0;
  Registry.AddListener(
    procedure
    begin
      Inc(Calls);
    end);
  Item.Update('Index: wird aufgebaut (10 %)', TAtlasStatusState.Yellow, 'Index 10 %');
  Assert.AreEqual(1, Calls);
  Item.Update('Index: wird aufgebaut (10 %)', TAtlasStatusState.Yellow, 'Index 10 %');
  Assert.AreEqual(1, Calls, 'gleicher Inhalt meldet nichts');
  Item.Update('Index: 120 Units', TAtlasStatusState.Green);
  Assert.AreEqual(2, Calls);
  Assert.AreEqual('', Ref.Summary);
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(Ref.State));
  Registry.Remove('atlas.index');
  Item.Detach;
end;

procedure TAtlasStatusRegistryTests.DetachedLineReportsNothing;
var
  Registry: IAtlasStatusRegistry;
  Item: TAtlasStatusLine;
  Ref: IAtlasStatusItem;
  Calls: Integer;
begin
  Registry := TAtlasStatusRegistry.Create;
  Item := TAtlasStatusLine.Create(Registry, 'x', 0);
  Ref := Item;
  Calls := 0;
  Registry.AddListener(
    procedure
    begin
      Inc(Calls);
    end);
  Item.Detach;
  Item.Update('neu', TAtlasStatusState.Red);
  Assert.AreEqual(0, Calls);
  Assert.AreEqual('neu', Ref.Text);
end;

procedure TAtlasStatusRegistryTests.OverallIsWorstState;
var
  Items: TArray<IAtlasStatusItem>;
begin
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusSummary.Overall(nil)), 'ohne Zeilen');
  Items := [Line(nil, 'a', 0, TAtlasStatusState.Neutral, 'A', '')];
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusSummary.Overall(Items)));
  Items := Items + [Line(nil, 'b', 1, TAtlasStatusState.Green, 'B', '')];
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusSummary.Overall(Items)));
  Items := Items + [Line(nil, 'c', 2, TAtlasStatusState.Yellow, 'C', '')];
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusSummary.Overall(Items)));
  Items := [Line(nil, 'd', 3, TAtlasStatusState.Red, 'D', '')] + Items;
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusSummary.Overall(Items)));
end;

procedure TAtlasStatusRegistryTests.HiddenLinesDoNotCount;
var
  Items, Visible: TArray<IAtlasStatusItem>;
begin
  Items := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'S', ''),
    Line(nil, 'atlas.file', 20, TAtlasStatusState.Yellow, 'F', '')];
  Visible := TAtlasStatusSummary.Visible(Items, ['ATLAS.FILE', ' gibt.es.nicht ']);
  Assert.AreEqual('atlas.server', Ids(Visible));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusSummary.Overall(Visible)));
  Assert.AreEqual(2, Integer(Length(TAtlasStatusSummary.Visible(Items, nil))));
end;

procedure TAtlasStatusRegistryTests.FieldTextShowsSummaryOfWorstLine;
var
  Items: TArray<IAtlasStatusItem>;
begin
  Items := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'Server: läuft', 'unwichtig'),
    Line(nil, 'atlas.index', 10, TAtlasStatusState.Yellow, 'Index', 'Index 45 %')];
  Assert.AreEqual('Atlas · Index 45 %', TAtlasStatusSummary.FieldText(Items, True));
  Assert.AreEqual('Atlas', TAtlasStatusSummary.FieldText(Items, False), 'showSummary aus');
  Items := Items + [Line(nil, 'test.fehler', 5, TAtlasStatusState.Red, 'Fehler', '2 Fehler')];
  Assert.AreEqual('Atlas · 2 Fehler', TAtlasStatusSummary.FieldText(Items, True), 'rot vor gelb');
  Items := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'Server: läuft', 'läuft')];
  Assert.AreEqual('Atlas', TAtlasStatusSummary.FieldText(Items, True), 'grün ohne Kurztext');
  Items := [Line(nil, 'a', 0, TAtlasStatusState.Red, 'A', ''), Line(nil, 'b', 1, TAtlasStatusState.Red, 'B', 'B!')];
  Assert.AreEqual('Atlas', TAtlasStatusSummary.FieldText(Items, True), 'wichtigste Zeile ohne Kurztext');
end;

procedure TAtlasStatusRegistryTests.TooltipListsLinesThatAreNotGreen;
var
  Items: TArray<IAtlasStatusItem>;
begin
  Items := [Line(nil, 'atlas.server', 0, TAtlasStatusState.Green, 'Server: läuft', '')];
  Assert.AreEqual('Atlas: alles in Ordnung', TAtlasStatusSummary.Tooltip(Items));
  Items := Items + [Line(nil, 'atlas.index', 10, TAtlasStatusState.Yellow, 'Index: wird aufgebaut', ''),
    Line(nil, 'atlas.file', 20, TAtlasStatusState.Neutral, 'Datei: keine aktiv', '')];
  Assert.AreEqual('Index: wird aufgebaut' + sLineBreak + 'Datei: keine aktiv', TAtlasStatusSummary.Tooltip(Items));
end;

procedure TAtlasStatusRegistryTests.ParsesHiddenIds;
var
  Parsed: TArray<string>;
begin
  Parsed := TAtlasStatusSummary.ParseIds(' atlas.file, atlas.index;test  ');
  Assert.AreEqual(3, Integer(Length(Parsed)));
  Assert.AreEqual('atlas.file', Parsed[0]);
  Assert.AreEqual('test', Parsed[2]);
  Assert.AreEqual('atlas.file, atlas.index, test', TAtlasStatusSummary.JoinIds(Parsed));
  Assert.AreEqual(0, Integer(Length(TAtlasStatusSummary.ParseIds(''))));
end;

procedure TAtlasStatusRegistryTests.ForeignLineAppearsWithoutChanges;
var
  Registry: IAtlasStatusRegistry;
  Foreign: TForeignItem;
  Ref: IAtlasStatusItem;
  Items: TArray<IAtlasStatusItem>;
begin
  Registry := TAtlasStatusRegistry.Create;
  Registry.Add(Line(nil, TAtlasStatusLines.ServerId, TAtlasStatusLines.ServerOrder, TAtlasStatusState.Green,
    'Server: läuft', ''));
  Registry.Add(Line(nil, TAtlasStatusLines.IndexId, TAtlasStatusLines.IndexOrder, TAtlasStatusState.Green,
    'Index: 10 Units', ''));
  Foreign := TForeignItem.Create;
  Ref := Foreign;
  Registry.Add(Ref);
  Items := TAtlasStatusSummary.Visible(Registry.Items, nil);
  Assert.AreEqual('atlas.server test.fehler atlas.index', Ids(Items));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusSummary.Overall(Items)));
  Assert.AreEqual('Atlas · 2 Fehler', TAtlasStatusSummary.FieldText(Items, True));
  Assert.Contains(TAtlasStatusSummary.Tooltip(Items), 'Fehler: 2 in dieser Datei');
  Items[1].Execute;
  Assert.AreEqual(1, Foreign.Clicks);
end;

{ TAtlasStatusLinesTests }

procedure TAtlasStatusLinesTests.ServerPhases;
var
  Info: TAtlasServerInfo;
begin
  Info := Default(TAtlasServerInfo);
  Assert.AreEqual('Server: nicht gestartet', TAtlasStatusLines.ServerText(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.ServerState(Info)));
  Info.Phase := TAtlasServerPhase.Starting;
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.ServerState(Info)));
  Info.Phase := TAtlasServerPhase.Running;
  Info.Version := '1.0.0';
  Info.AverageMs := 12.4;
  Info.Samples := 50;
  Assert.AreEqual('Server: läuft, 12 ms im Mittel der letzten 50 Anfragen, Version 1.0.0',
    TAtlasStatusLines.ServerText(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.ServerState(Info)));
  Assert.AreEqual('', TAtlasStatusLines.ServerSummary(Info));
  Info.Phase := TAtlasServerPhase.Stopped;
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusLines.ServerState(Info)));
  Assert.AreEqual('Server gestoppt', TAtlasStatusLines.ServerSummary(Info));
  Info := Default(TAtlasServerInfo);
  Info.Phase := TAtlasServerPhase.Failed;
  Info.Error := 'AtlasServer.exe nicht gefunden';
  Assert.AreEqual('Server: Start fehlgeschlagen (AtlasServer.exe nicht gefunden)',
    TAtlasStatusLines.ServerText(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusLines.ServerState(Info)));
end;

procedure TAtlasStatusLinesTests.SlowServerIsYellow;
var
  Info: TAtlasServerInfo;
begin
  Info := Default(TAtlasServerInfo);
  Info.Phase := TAtlasServerPhase.Running;
  Info.AverageMs := TAtlasStatusLines.SlowMs;
  Info.Samples := 3;
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.ServerState(Info)));
  Assert.Contains(TAtlasStatusLines.ServerText(Info), '(langsam)');
  Assert.AreEqual('Server langsam', TAtlasStatusLines.ServerSummary(Info));
  Info.Samples := 0;
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.ServerState(Info)), 'ohne Messung');
end;

procedure TAtlasStatusLinesTests.IndexWhileBuildingThenUnits;
var
  Info: TAtlasIndexInfo;
begin
  Info.Units := -1;
  Info.Indexing := True;
  Info.Percent := 45;
  Assert.AreEqual('Index: wird aufgebaut (45 %)', TAtlasStatusLines.IndexText(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.IndexState(Info)));
  Assert.AreEqual('Index 45 %', TAtlasStatusLines.IndexSummary(Info));
  Info.Percent := -1;
  Info.Units := 80;
  Assert.AreEqual('Index: wird aufgebaut, bisher 80 Units', TAtlasStatusLines.IndexText(Info));
  Assert.AreEqual('Index …', TAtlasStatusLines.IndexSummary(Info));
  Info.Indexing := False;
  Info.Units := 1234;
  Assert.AreEqual('Index: 1234 Units', TAtlasStatusLines.IndexText(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.IndexState(Info)));
  Assert.AreEqual('', TAtlasStatusLines.IndexSummary(Info));
  Info.Units := -1;
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.IndexState(Info)));
end;

procedure TAtlasStatusLinesTests.FileLineShowsFormatAndTarget;
var
  Info: TAtlasFileInfo;
begin
  Info := Default(TAtlasFileInfo);
  Assert.AreEqual('Datei: keine aktiv', TAtlasStatusLines.FileText(Info));
  Info.Name := 'Main.pas';
  Info.Known := True;
  Info.Format := TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8, TAtlasLineBreak.LF);
  Assert.AreEqual('Datei Main.pas: UTF-8 ohne BOM, LF', TAtlasStatusLines.FileText(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.FileState(Info)));
  Info.HasTarget := True;
  Info.Target := TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8Bom, TAtlasLineBreak.CRLF);
  Assert.AreEqual('Datei Main.pas: UTF-8 ohne BOM, LF → UTF-8 mit BOM, CRLF beim Speichern',
    TAtlasStatusLines.FileText(Info));
  Info.HasTarget := False;
  Info.Format.LineBreak := TAtlasLineBreak.Mixed;
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.FileState(Info)));
  Info.Known := False;
  Assert.AreEqual('Datei Main.pas: noch nicht gespeichert', TAtlasStatusLines.FileText(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.FileState(Info)));
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
  Format: TAtlasFileFormat;
begin
  Format := TAtlasFileFormats.Detect(TEncoding.UTF8.GetBytes('unit Grüße;'#10'interface'#10));
  Assert.AreEqual('UTF-8 ohne BOM, LF', Format.Text);
  Format := TAtlasFileFormats.Detect(TEncoding.UTF8.GetBytes('unit A;'#10));
  Assert.AreEqual('UTF-8 ohne BOM, LF', Format.Text, 'reines ASCII');
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
  Source, Converted: TBytes;
  Target: TAtlasFileFormat;
begin
  // Abnahme: UTF-8 ohne BOM, LF → UTF-8 mit BOM, CRLF.
  Source := TEncoding.UTF8.GetBytes('unit Grüße;'#10'end.'#10);
  Target := TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8Bom, TAtlasLineBreak.CRLF);
  Assert.IsFalse(TAtlasFileFormats.Satisfies(Source, Target));
  Converted := TAtlasFileFormats.Convert(Source, Target);
  Assert.AreEqual('UTF-8 mit BOM, CRLF', TAtlasFileFormats.Detect(Converted).Text);
  Assert.AreEqual('unit Grüße;'#13#10'end.'#13#10, TAtlasFileFormats.Decode(Converted, TAtlasFileEncoding.Utf8Bom));
  Assert.IsTrue(TAtlasFileFormats.Satisfies(Converted, Target));
  // Und zurück, gemischte Zeilenenden werden vereinheitlicht.
  Converted := TAtlasFileFormats.Convert(TEncoding.UTF8.GetBytes('a'#13#10'b'#10'c'#13),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8, TAtlasLineBreak.LF));
  Assert.AreEqual('a'#10'b'#10'c'#10, TEncoding.UTF8.GetString(Converted));
end;

procedure TAtlasFileFormatTests.ConvertsToAnsiLf;
var
  Converted: TBytes;
begin
  Converted := TAtlasFileFormats.Convert(TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes('x := 1;'#13#10),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Ansi, TAtlasLineBreak.LF));
  Assert.AreEqual('x := 1;'#10, TEncoding.ANSI.GetString(Converted));
  Assert.AreEqual(0, TAtlasFileFormats.AnsiLosses('x := 1;'));
end;

procedure TAtlasFileFormatTests.SatisfiesTreatsAsciiAsAnsiAndUtf8;
var
  Ascii: TBytes;
begin
  Ascii := TEncoding.UTF8.GetBytes('unit A;'#13#10);
  Assert.IsTrue(TAtlasFileFormats.Satisfies(Ascii, TAtlasFileFormat.Create(TAtlasFileEncoding.Ansi,
    TAtlasLineBreak.CRLF)));
  Assert.IsTrue(TAtlasFileFormats.Satisfies(Ascii, TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8,
    TAtlasLineBreak.CRLF)));
  Assert.IsFalse(TAtlasFileFormats.Satisfies(Ascii, TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8,
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
  Targets: TArray<TAtlasFileFormat>;
begin
  Targets := TAtlasFileFormats.Targets;
  Assert.AreEqual(6, Integer(Length(Targets)));
  Assert.AreEqual('UTF-8 mit BOM, CRLF', Targets[0].Text);
  Assert.AreEqual('ANSI, LF', Targets[5].Text);
  Assert.IsTrue(Targets[0].Equals(TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8Bom, TAtlasLineBreak.CRLF)));
  Assert.IsFalse(Targets[0].Equals(Targets[1]));
end;

{ TAtlasStatusSourcesTests }

procedure TAtlasStatusSourcesTests.ClientAveragesLastFiftyResponses;
var
  Client: TLspClient;
  Samples, Index: Integer;
begin
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    Assert.AreEqual(0.0, Client.AverageMs(Samples), 0.001);
    Assert.AreEqual(0, Samples);
    Client.AddResponseTime(10);
    Client.AddResponseTime(30);
    Assert.AreEqual(20.0, Client.AverageMs(Samples), 0.001);
    Assert.AreEqual(2, Samples);
    // 60 weitere: nur die letzten 50 zählen.
    for Index := 1 to 10 do
      Client.AddResponseTime(1000);
    for Index := 1 to TLspClient.TimeSamples do
      Client.AddResponseTime(4);
    Assert.AreEqual(4.0, Client.AverageMs(Samples), 0.001);
    Assert.AreEqual(TLspClient.TimeSamples, Samples);
  finally
    Client.Free;
  end;
end;

procedure TAtlasStatusSourcesTests.ClientMeasuresRequests;
var
  Client: TLspClient;
  Samples: Integer;
begin
  Client := nil;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
      Client.Receive(TLspClient.Frame('{"jsonrpc":"2.0","id":1,"result":null}'), Length(TLspClient.Frame(
        '{"jsonrpc":"2.0","id":1,"result":null}')));
    end);
  try
    Client.Request('test', nil, 1000).Free;
    Client.AverageMs(Samples);
    Assert.AreEqual(1, Samples);
  finally
    Client.Free;
  end;
end;

procedure TAtlasStatusSourcesTests.ClientReportsCloseOnce;
var
  Client: TLspClient;
  Calls: Integer;
begin
  Calls := 0;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    Client.OnClosed :=
      procedure
      begin
        Inc(Calls);
      end;
    Client.Close;
    Client.Close;
    Assert.AreEqual(1, Calls);
    Assert.IsTrue(Client.Closed);
  finally
    Client.Free;
  end;
  Assert.AreEqual(1, Calls, 'Freigeben meldet nicht noch einmal');
end;

procedure SendProgress(const AProgress: ILspProgress; const AJson: string);
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    AProgress.Handle(Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasStatusSourcesTests.ProgressReportsChangesAndPercent;
var
  Progress: ILspProgress;
  Calls, Percent: Integer;
begin
  Progress := TLspProgress.Create;
  Calls := 0;
  Progress.SetOnChanged(
    procedure
    begin
      Inc(Calls);
    end);
  Assert.IsFalse(Progress.Active(Percent));
  Assert.AreEqual(-1, Percent);
  SendProgress(Progress, '{"token":"atlas-index","value":{"kind":"begin","title":"Index"}}');
  Assert.IsTrue(Progress.Active(Percent));
  Assert.AreEqual(-1, Percent);
  SendProgress(Progress, '{"token":"atlas-index","value":{"kind":"report","percentage":45}}');
  Assert.IsTrue(Progress.Active(Percent));
  Assert.AreEqual(45, Percent);
  SendProgress(Progress, '{"token":"atlas-index","value":{"kind":"end"}}');
  Assert.IsFalse(Progress.Active(Percent));
  Assert.AreEqual(3, Calls);
  Progress.SetOnChanged(nil);
  SendProgress(Progress, '{"token":"x","value":{"kind":"begin"}}');
  Assert.AreEqual(3, Calls);
end;

procedure TAtlasStatusSourcesTests.StatusFieldSettingsRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.StatusField, 'statusField.enabled: Vorgabe an');
  Assert.IsTrue(Settings.StatusFieldSummary, 'statusField.showSummary: Vorgabe an');
  Assert.AreEqual('', Settings.StatusFieldHidden);
  Assert.AreEqual('both', Settings.StatusFieldToggles, 'statusField.openToggles: Vorgabe beide');
  Assert.IsTrue(Settings.StatusTogglesOnRightClick);
  Assert.IsTrue(Settings.StatusTogglesOnDoubleClick);
  Store := TMemoryStore.Create;
  Settings.StatusField := False;
  Settings.StatusFieldSummary := False;
  Settings.StatusFieldToggles := 'doubleClick';
  Settings.StatusFieldHidden := ' atlas.file, test.fehler ';
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.StatusField);
  Assert.IsFalse(Loaded.StatusFieldSummary);
  Assert.AreEqual('doubleClick', Loaded.StatusFieldToggles);
  Assert.IsFalse(Loaded.StatusTogglesOnRightClick, 'nur Doppelklick');
  Assert.IsTrue(Loaded.StatusTogglesOnDoubleClick);
  // Groß-/Kleinschreibung egal, Unbekanntes wird zur Vorgabe.
  Settings.StatusFieldToggles := ' RIGHTCLICK ';
  Settings.Normalize;
  Assert.AreEqual('rightClick', Settings.StatusFieldToggles);
  Assert.IsTrue(Settings.StatusTogglesOnRightClick);
  Assert.IsFalse(Settings.StatusTogglesOnDoubleClick, 'nur Rechtsklick');
  Settings.StatusFieldToggles := 'dreifach';
  Settings.Normalize;
  Assert.AreEqual('both', Settings.StatusFieldToggles);
  Assert.AreEqual('atlas.file, test.fehler', Loaded.StatusFieldHidden);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusRegistryTests);
  TDUnitX.RegisterTestFixture(TAtlasStatusLinesTests);
  TDUnitX.RegisterTestFixture(TAtlasFileFormatTests);
  TDUnitX.RegisterTestFixture(TAtlasStatusSourcesTests);

end.
