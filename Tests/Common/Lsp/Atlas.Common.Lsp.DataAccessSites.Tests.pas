unit Atlas.Common.Lsp.DataAccessSites.Tests;

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.DataAccessSites;

type
  [TestFixture]
  TLspDataAccessSitesTests = class
  private
    FIndex: ISymbolIndex;
    FFiles: TDictionary<string, string>;
    FCommand: TLspDataAccessSites;
    FClasses: TArray<TDataAccessClass>;
    FSites: TArray<TDataAccessSite>;
    FUnresolved: Integer;
    function Describe: string;
    function Find(const AMethod: string; ALine: Integer): TDataAccessSite;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SitesOfWatchedClasses;
    [Test]
    procedure DescendantMatchesNearestClass;
    [Test]
    procedure ArgumentsAndReceiver;
    [Test]
    procedure UnresolvedReceiversCounted;
    [Test]
    procedure WithoutClassesNoSites;
    [Test]
    procedure ExecuteParsesClassesAndAnswersJson;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Metrics;

const
  cBibFile = 'C:\Bib\FireDAC.Comp.Client.pas';
  cKundeFile = 'C:\P\Kunde.pas';

  cUnitBib =
    'unit FireDAC.Comp.Client;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDataSet = class'#10 +
    '    procedure Open;'#10 +
    '  end;'#10 +
    '  TFDQuery = class(TDataSet)'#10 +
    '    procedure ExecSQL;'#10 +
    '  end;'#10 +
    '  TFDConnection = class'#10 +
    '    procedure Open;'#10 +
    '    function ExecSQL(const ASQL: string): Integer;'#10 +
    '  end;'#10 +
    '  THTTPClient = class'#10 +
    '    function Get(const AURL: string): TObject;'#10 +
    '    function Post(const AURL: string; ASource: TObject): TObject;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TDataSet.Open; begin end;'#10 +
    'procedure TFDQuery.ExecSQL; begin end;'#10 +
    'procedure TFDConnection.Open; begin end;'#10 +
    'function TFDConnection.ExecSQL(const ASQL: string): Integer; begin Result := 0; end;'#10 +
    'function THTTPClient.Get(const AURL: string): TObject; begin Result := nil; end;'#10 +
    'function THTTPClient.Post(const AURL: string; ASource: TObject): TObject; begin Result := nil; end;'#10 +
    'end.'#10;

  cUnitKunde =
    'unit Kunde;'#10 +                                              // 0
    'interface'#10 +                                                // 1
    'uses FireDAC.Comp.Client;'#10 +                                // 2
    'type'#10 +                                                     // 3
    '  TKundenQuery = class(TFDQuery)'#10 +                         // 4
    '  end;'#10 +                                                   // 5
    '  TfrmKunde = class'#10 +                                      // 6
    '    qryKunde: TFDQuery;'#10 +                                  // 7
    '    FConn: TFDConnection;'#10 +                                // 8
    '    procedure Speichern;'#10 +                                 // 9
    '  end;'#10 +                                                   // 10
    'implementation'#10 +                                           // 11
    'procedure TfrmKunde.Speichern;'#10 +                           // 12
    'var'#10 +                                                      // 13
    '  mQuery: TKundenQuery;'#10 +                                  // 14
    '  mClient: THTTPClient;'#10 +                                  // 15
    '  mListe: TStringList;'#10 +                                   // 16
    'begin'#10 +                                                    // 17
    '  qryKunde.ExecSQL;'#10 +                                      // 18
    '  mQuery.Open;'#10 +                                           // 19
    '  FConn.Open;'#10 +                                            // 20
    '  FConn.ExecSQL(''UPDATE Kunden SET Name = '''''' + ''A'''''');'#10 + // 21
    '  mClient.Post(''http://x/api/auftrag'', nil);'#10 +           // 22
    '  mListe.Get(0);'#10 +                                         // 23
    '  Unbekannt.Get(''x'');'#10 +                                  // 24
    '  if mQuery <> nil then'#10 +                                  // 25
    '    mQuery.ExecSQL;'#10 +                                      // 26
    'end;'#10 +                                                     // 27
    'end.'#10;

function Watched(const AName, AKind: string; const AMethods: array of string): TDataAccessClass;
var
  mMethod: string;
begin
  Result := Default(TDataAccessClass);
  Result.Name := AName;
  Result.Kind := AKind;
  for mMethod in AMethods do
  begin
    Result.Methods := Result.Methods + [mMethod];
  end;
end;

{ TLspDataAccessSitesTests }

function TLspDataAccessSitesTests.Describe: string;
var
  mSite: TDataAccessSite;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mSite in FSites do
  begin
    mParts := mParts + [Format('%s.%s@%d', [mSite.WatchedClass, mSite.Method, mSite.BreakLine])];
  end;
  Result := string.Join(' ', mParts);
end;

function TLspDataAccessSitesTests.Find(const AMethod: string; ALine: Integer): TDataAccessSite;
var
  mSite: TDataAccessSite;
begin
  for mSite in FSites do
  begin
    if SameText(mSite.Method, AMethod) and (mSite.Position.Line = ALine) then
    begin
      Exit(mSite);
    end;
  end;
  Assert.Fail(Format('nicht gefunden: %s in Zeile %d', [AMethod, ALine]));
  Result := Default(TDataAccessSite);
end;

procedure TLspDataAccessSitesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBib, cBibFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKunde, cKundeFile, nil));
  FFiles := TDictionary<string, string>.Create;
  FFiles.Add(LowerCase(cBibFile), cUnitBib);
  FFiles.Add(LowerCase(cKundeFile), cUnitKunde);
  FCommand := TLspDataAccessSites.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Files := TArray<string>.Create(cKundeFile);
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FFiles.TryGetValue(LowerCase(AFileName), AText);
    end,
    FIndex, nil, nil);
  FClasses := TArray<TDataAccessClass>.Create(
    Watched('TFDQuery', 'sql', ['Open', 'ExecSQL', 'Execute']),
    Watched('TFDConnection', 'sql', ['ExecSQL', 'ExecSQLScalar']),
    Watched('THTTPClient', 'http', ['Get', 'Post', 'Put', 'Delete']));
  FSites := FCommand.Collect(TArray<string>.Create(cKundeFile), FClasses, FUnresolved);
end;

procedure TLspDataAccessSitesTests.TearDown;
begin
  FreeAndNil(FCommand);
  FreeAndNil(FFiles);
  FIndex := nil;
  FClasses := nil;
  FSites := nil;
end;

procedure TLspDataAccessSitesTests.SitesOfWatchedClasses;
begin
  // FConn.Open fehlt: Open gehört nicht zu den Methoden von TFDConnection; TStringList ist nicht beobachtet.
  Assert.AreEqual('TFDQuery.ExecSQL@18 TFDQuery.Open@19 TFDConnection.ExecSQL@21 THTTPClient.Post@22 ' +
    'TFDQuery.ExecSQL@26', Describe);
end;

procedure TLspDataAccessSitesTests.DescendantMatchesNearestClass;
var
  mSite: TDataAccessSite;
begin
  mSite := Find('Open', 19);
  Assert.AreEqual('TFDQuery', mSite.WatchedClass);
  Assert.AreEqual('TKundenQuery', mSite.ReceiverType);
  Assert.AreEqual('sql', mSite.Kind);
  Assert.AreEqual('TfrmKunde.Speichern', mSite.Routine);
  // Aufruf im then-Zweig in eigener Zeile: Haltepunkt an der Zeile des Aufrufs.
  Assert.AreEqual(26, Find('ExecSQL', 26).Position.Line);
end;

procedure TLspDataAccessSitesTests.ArgumentsAndReceiver;
var
  mSite: TDataAccessSite;
begin
  mSite := Find('ExecSQL', 21);
  Assert.AreEqual('FConn', mSite.Receiver);
  Assert.AreEqual(1, Integer(Length(mSite.Arguments)));
  Assert.AreEqual('''UPDATE Kunden SET Name = '''''' + ''A''''''', mSite.Arguments[0]);
  mSite := Find('Post', 22);
  Assert.AreEqual('http', mSite.Kind);
  Assert.AreEqual(2, Integer(Length(mSite.Arguments)));
  Assert.AreEqual('''http://x/api/auftrag''', mSite.Arguments[0]);
  Assert.AreEqual(10, mSite.Position.Character);
end;

procedure TLspDataAccessSitesTests.UnresolvedReceiversCounted;
begin
  // Unbekannt.Get: Empfänger ohne Deklaration.
  Assert.AreEqual(1, FUnresolved);
end;

procedure TLspDataAccessSitesTests.WithoutClassesNoSites;
var
  mUnresolved: Integer;
begin
  Assert.AreEqual(0, Integer(Length(FCommand.Collect(TArray<string>.Create(cKundeFile), nil, mUnresolved))));
  Assert.AreEqual(0, mUnresolved);
end;

procedure TLspDataAccessSitesTests.ExecuteParsesClassesAndAnswersJson;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
  mSites: TJSONArray;
  mSite: TJSONObject;
begin
  mArguments := TJSONObject.ParseJSONValue('["file:///C:/P/Kunde.dproj", [' +
    '{"name": "THTTPClient", "kind": "http", "methods": ["Post"]},' +
    '{"name": "TOhneMethoden", "kind": "sql", "methods": []}, 7]]') as TJSONArray;
  try
    Assert.AreEqual(1, Integer(Length(TLspDataAccessSites.ParseClasses(mArguments.Items[1]))));
    mAnswer := FCommand.Execute(mArguments);
    try
      Assert.AreEqual(1, (mAnswer as TJSONObject).GetValue<Integer>('format'));
      mSites := (mAnswer as TJSONObject).GetValue<TJSONArray>('sites');
      Assert.AreEqual(1, mSites.Count);
      mSite := mSites.Items[0] as TJSONObject;
      Assert.AreEqual(cKundeFile, mSite.GetValue<string>('file'));
      Assert.AreEqual(22, mSite.GetValue<Integer>('line'));
      Assert.AreEqual(22, mSite.GetValue<Integer>('breakLine'));
      Assert.AreEqual('THTTPClient', mSite.GetValue<string>('class'));
      Assert.AreEqual('Post', mSite.GetValue<string>('method'));
      Assert.AreEqual('mClient', mSite.GetValue<string>('receiver'));
      Assert.AreEqual('THTTPClient', mSite.GetValue<string>('receiverType'));
      Assert.AreEqual(2, mSite.GetValue<TJSONArray>('arguments').Count);
      // Get steht diesmal nicht in den Methoden: Unbekannt.Get zählt nicht.
      Assert.AreEqual(0, (mAnswer as TJSONObject).GetValue<Integer>('unresolved'));
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDataAccessSitesTests);

end.
