unit Shell.Mcp.RefactorHost.Tests;

// Werkzeug refactor im MCP-Modus (#2150) mit den echten Code-Aktionen und Befehlen des Servers: Jede Art steht in
// der Liste ihrer Stelle und liefert eine Vorschau, ohne zu schreiben; dryRun=false schreibt und legt neue Units an.
// moveClass ist experimentell (experimental.enabled nur in den Benutzereinstellungen) und fehlt hier; die Auswahl
// und Argumente prüft Atlas.Common.Mcp.RefactorTools.Tests mit einem Server-Ersatz.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpRefactorHostTests = class
  public
    [Test]
    procedure EachKindIsListedAndPreviewed;
    [Test]
    procedure WritesAndCreatesUnits;
    [Test]
    procedure ListsAsJsonAndRefusesWrongArguments;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Mcp.Server,
  Shell.Mcp.Context,
  Shell.Mcp.Services,
  Shell.Mcp.RefactorSources,
  Shell.Mcp.EditingTools;

const
  cUnit = 'Probe.Kunden.pas';
  cLines: array[0..119] of string = (
    'unit Probe.Kunden;',
    '',
    'interface',
    '',
    'type',
    '  TFarbe = (Rot, Gruen, Blau);',
    '  TName = string;',
    '',
    '  TKunde = class',
    '  private',
    '    FName: string;',
    '    FAlter: Integer;',
    '    function GetName: string;',
    '    procedure SetName(const AValue: string);',
    '  public',
    '    procedure Begruessen(const AText: string; AAnzahl: Integer);',
    '    function Summe(A, B: Integer): Integer;',
    '    procedure Pruefen;',
    '    property Name: string read GetName write SetName;',
    '  end;',
    '',
    '  TPremiumKunde = class(TKunde)',
    '  public',
    '    procedure Rabatt;',
    '  end;',
    '',
    '  TLeser = class',
    '  private',
    '    FWert: Integer;',
    '  public',
    '    function GetWert: Integer;',
    '    procedure SetWert(AValue: Integer);',
    '    procedure Lesen(const AListe: TArray<string>);',
    '  end;',
    '',
    'procedure Hilfe(const AName: TName);',
    '',
    'implementation',
    '',
    'uses',
    '  System.SysUtils;',
    '',
    'function TLeser.GetWert: Integer;',
    'begin',
    '  Result := FWert;',
    'end;',
    '',
    'procedure TLeser.SetWert(AValue: Integer);',
    'begin',
    '  FWert := AValue;',
    'end;',
    '',
    'procedure TLeser.Lesen(const AListe: TArray<string>);',
    'var',
    '  mProc: TProc;',
    'begin',
    '  mProc :=',
    '    procedure',
    '    begin',
    '      SetWert(Length(AListe));',
    '    end;',
    '  mProc();',
    'end;',
    '',
    'function TKunde.GetName: string;',
    'begin',
    '  Result := FName;',
    'end;',
    '',
    'procedure TKunde.SetName(const AValue: string);',
    'begin',
    '  FName := AValue;',
    'end;',
    '',
    'procedure TKunde.Begruessen(const AText: string; AAnzahl: Integer);',
    'var',
    '  mZaehler: Integer;',
    '  mFertig: Boolean;',
    'begin',
    '  mFertig := False;',
    '  for mZaehler := 1 to AAnzahl do',
    '  begin',
    '    Hilfe(AText + GetName);',
    '  end;',
    '  if not mFertig then',
    '  begin',
    '    FAlter := Summe(1, 2);',
    '  end;',
    'end;',
    '',
    'function TKunde.Summe(A, B: Integer): Integer;',
    'begin',
    '  Result := A + B;',
    'end;',
    '',
    'procedure TKunde.Pruefen;',
    'var',
    '  mFarbe: TFarbe;',
    'begin',
    '  mFarbe := Rot;',
    '  case mFarbe of',
    '    Rot: Begruessen(''rot'', 1);',
    '    Gruen: Begruessen(''gruen'', 2);',
    '  end;',
    'end;',
    '',
    'procedure TPremiumKunde.Rabatt;',
    'begin',
    '  Pruefen;',
    'end;',
    '',
    'procedure Hilfe(const AName: TName);',
    'begin',
    '  if AName = '''' then',
    '  begin',
    '    Exit;',
    '  end;',
    'end;',
    '',
    'end.');

type
  /// <summary>Ein Umbau: Stelle über die erste Zeile mit LineText und das Wort darin, dazu args und title.</summary>
  TKindCase = record
    Kind: string;
    LineText: string;
    Word: string;
    Args: string;
    Title: string;
  end;

  /// <summary>MCP-Dienste über einem Ordner mit Probe.Kunden.pas und dem Werkzeug refactor.</summary>
  TRefactorFixture = class
  private
    FFolder: string;
    FLogger: ILogger;
    FServices: TMcpServices;
    FServer: TMcpServer;
    FSaved: TTextLanguage;
  public
    constructor Create;
    destructor Destroy; override;
    function Text: string;
    /// <summary>Zeile und Spalte (ab 1) als JSON-Felder.</summary>
    function Place(const ALineText, AWord: string): string;
    /// <summary>Ruft refactor mit AArguments (JSON-Felder ohne Klammern) auf; AIsError: isError der Antwort.</summary>
    function Call(const AArguments: string; out AIsError: Boolean): string;
    property Folder: string read FFolder;
  end;

function KindCase(const AKind, ALineText, AWord, AArgs, ATitle: string): TKindCase;
begin
  Result.Kind := AKind;
  Result.LineText := ALineText;
  Result.Word := AWord;
  Result.Args := AArgs;
  Result.Title := ATitle;
end;

function SourceText: string;
begin
  Result := string.Join(#13#10, cLines) + #13#10;
end;

{ TRefactorFixture }

constructor TRefactorFixture.Create;
var
  mContext: TMcpToolContext;
begin
  inherited Create;
  FSaved := TAtlasLocale.Language;
  TAtlasLocale.Use(TTextLanguage.German);
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-refactor-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(FFolder);
  TFile.WriteAllText(TPath.Combine(FFolder, cUnit), SourceText, TEncoding.UTF8);
  FLogger := TLogger.Create;
  FServices := TMcpServices.Create(FFolder, FLogger);
  FServer := TMcpServer.Create('Atlas', '0');
  mContext := FServices.ToolContext(FServer);
  TMcpRefactorSources.Attach(mContext, FLogger);
  RegisterEditingTools(mContext);
end;

destructor TRefactorFixture.Destroy;
begin
  FServer.Free;
  FServices.Free;
  FLogger := nil;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  TAtlasLocale.Use(FSaved);
  inherited Destroy;
end;

function TRefactorFixture.Text: string;
begin
  Result := TFile.ReadAllText(TPath.Combine(FFolder, cUnit), TEncoding.UTF8);
end;

/// <summary>Index der Zeile: zuerst eine, die ohne Einrückung ALineText ist, sonst die erste, die ihn enthält.
/// </summary>
function LineIndex(const ALineText: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(cLines) do
  begin
    if Trim(cLines[mIndex]) = Trim(ALineText) then
    begin
      Exit(mIndex);
    end;
  end;
  for mIndex := 0 to High(cLines) do
  begin
    if Pos(ALineText, cLines[mIndex]) > 0 then
    begin
      Exit(mIndex);
    end;
  end;
  Assert.Fail(ALineText + ' fehlt im Beispiel');
  Result := -1;
end;

function TRefactorFixture.Place(const ALineText, AWord: string): string;
var
  mIndex: Integer;
begin
  mIndex := LineIndex(ALineText);
  Assert.IsTrue(Pos(AWord, cLines[mIndex]) > 0, AWord + ' fehlt in ' + cLines[mIndex]);
  Result := Format('"line":%d,"column":%d', [mIndex + 1, Pos(AWord, cLines[mIndex])]);
end;

function TRefactorFixture.Call(const AArguments: string; out AIsError: Boolean): string;
var
  mParams, mCalled: TJSONObject;
  mContent: TJSONValue;
begin
  mParams := TJSONObject.ParseJSONValue('{"name":"refactor","arguments":{"file":"' + cUnit + '",' + AArguments +
    '}}') as TJSONObject;
  Assert.IsNotNull(mParams, AArguments);
  try
    mCalled := FServer.CallTool(mParams);
    try
      if not mCalled.TryGetValue<Boolean>('isError', AIsError) then
      begin
        AIsError := False;
      end;
      Result := '';
      for mContent in mCalled.GetValue<TJSONArray>('content') do
      begin
        Result := Result + mContent.GetValue<string>('text');
      end;
    finally
      mCalled.Free;
    end;
  finally
    mParams.Free;
  end;
end;

function Cases: TArray<TKindCase>;
begin
  Result := [
    KindCase('promoteVariable', 'FAlter: Integer', 'FAlter', '', ''),
    KindCase('invertBoolean', 'mFertig: Boolean', 'mFertig', '', ''),
    KindCase('anonymousMethod', 'procedure', 'procedure', '{"name":"Ausgeben"}', ''),
    KindCase('methodKind', 'function Summe(A, B', 'function', '{"conversion":"classMethod"}', ''),
    KindCase('inlineAccessor', 'TKunde = class', 'TKunde', '{"scope":"unit"}', ''),
    KindCase('propertyFromAccessors', 'TLeser = class', 'TLeser', '{"calls":false}', ''),
    KindCase('typeAlias', 'procedure Lesen(const AListe: TArray<string>);', 'TArray', '{"name":"TTexte"}', ''),
    KindCase('inlineTypeAlias', 'TName = string', 'TName', '', ''),
    KindCase('enumTable', 'TFarbe = (', 'TFarbe', '', 'Namenstabelle anlegen (TFarbe)'),
    KindCase('enumTablesSync', 'TFarbe = (', 'TFarbe', '', ''),
    KindCase('createOverload', 'function GetName: string;', 'function', '{"kind":"copy"}', ''),
    KindCase('changeSignature', 'function Summe(A, B', 'Summe', '{"parameters":[{"name":"B"},{"name":"A"}]}', ''),
    KindCase('safeDelete', 'procedure Rabatt;', 'Rabatt', '', ''),
    KindCase('extractInterface', 'TKunde = class', 'TKunde', '{"name":"IKunde","members":["Summe"]}', ''),
    KindCase('extractSuperclass', 'TKunde = class', 'TKunde', '{"name":"TBasis","members":["Summe"]}', ''),
    KindCase('moveMember', 'procedure Rabatt;', 'Rabatt', '', '')];
end;

{ TMcpRefactorHostTests }

procedure TMcpRefactorHostTests.EachKindIsListedAndPreviewed;
var
  mFixture: TRefactorFixture;
  mCase: TKindCase;
  mPlace, mArguments, mText: string;
  mIsError: Boolean;
begin
  mFixture := TRefactorFixture.Create;
  try
    for mCase in Cases do
    begin
      mPlace := mFixture.Place(mCase.LineText, mCase.Word);
      mText := mFixture.Call(mPlace, mIsError);
      Assert.IsFalse(mIsError, mCase.Kind + ': ' + mText);
      Assert.Contains(mText, '- ' + mCase.Kind + ' – ', mCase.Kind + ' fehlt in der Liste: ' + mText);
      mArguments := mPlace + ',"kind":"' + mCase.Kind + '"';
      if mCase.Args <> '' then
      begin
        mArguments := mArguments + ',"args":' + mCase.Args;
      end;
      if mCase.Title <> '' then
      begin
        mArguments := mArguments + ',"title":"' + mCase.Title + '"';
      end;
      mText := mFixture.Call(mArguments, mIsError);
      Assert.IsFalse(mIsError, mCase.Kind + ': ' + mText);
      Assert.Contains(mText, 'Vorschau (dryRun)', mCase.Kind + ': ' + mText);
      Assert.AreEqual(SourceText, mFixture.Text, mCase.Kind + ': Vorschau schreibt nichts');
    end;
  finally
    mFixture.Free;
  end;
end;

procedure TMcpRefactorHostTests.WritesAndCreatesUnits;
var
  mFixture: TRefactorFixture;
  mText, mNewFile: string;
  mIsError: Boolean;
begin
  mFixture := TRefactorFixture.Create;
  try
    mText := mFixture.Call(mFixture.Place('TKunde = class', 'TKunde') + ',"kind":"extractInterface",' +
      '"args":{"name":"IKunde","unit":"Probe.Schnittstellen","members":["Summe"]},"dryRun":false', mIsError);
    Assert.IsFalse(mIsError, mText);
    Assert.Contains(mText, 'Probe.Schnittstellen.pas (neue Datei)');
    mNewFile := TPath.Combine(mFixture.Folder, 'Probe.Schnittstellen.pas');
    Assert.IsTrue(TFile.Exists(mNewFile), 'neue Unit angelegt');
    Assert.Contains(TFile.ReadAllText(mNewFile, TEncoding.UTF8), 'IKunde = interface');
    Assert.Contains(mFixture.Text, 'TKunde = class(TInterfacedObject, IKunde)');
    Assert.Contains(mFixture.Text, 'Probe.Schnittstellen;');
    mText := mFixture.Call(mFixture.Place('TKunde = class', 'TKunde') + ',"kind":"extractInterface",' +
      '"args":{"name":"IKunde","unit":"Probe.Schnittstellen","members":["Summe"]}', mIsError);
    Assert.IsTrue(mIsError, 'die Unit gibt es schon: ' + mText);
  finally
    mFixture.Free;
  end;
end;

procedure TMcpRefactorHostTests.ListsAsJsonAndRefusesWrongArguments;
var
  mFixture: TRefactorFixture;
  mText: string;
  mIsError: Boolean;
  mJson: TJSONValue;
begin
  mFixture := TRefactorFixture.Create;
  try
    mText := mFixture.Call(mFixture.Place('TFarbe = (', 'TFarbe') + ',"format":"json"', mIsError);
    Assert.IsFalse(mIsError, mText);
    mJson := TJSONObject.ParseJSONValue(mText);
    try
      Assert.IsNotNull(mJson, mText);
      Assert.Contains(mJson.GetValue<TJSONArray>('refactorings').ToJSON([]), '"kind":"enumTable"');
    finally
      mJson.Free;
    end;
    mText := mFixture.Call(mFixture.Place('mFertig: Boolean', 'mFertig') + ',"kind":"invertBoolean","args":{"neu":1}',
      mIsError);
    Assert.IsTrue(mIsError);
    Assert.Contains(mText, 'Unbekanntes Argument "neu". Erwartet: name: string');
    mText := mFixture.Call(mFixture.Place('mFertig: Boolean', 'mFertig') + ',"kind":"gibtsnicht"', mIsError);
    Assert.IsTrue(mIsError);
    Assert.Contains(mText, 'invertBoolean', 'die Liste der Stelle hilft weiter');
    Assert.AreEqual(SourceText, mFixture.Text);
  finally
    mFixture.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpRefactorHostTests);

end.
