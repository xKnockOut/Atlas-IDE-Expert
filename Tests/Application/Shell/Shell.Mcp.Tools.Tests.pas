unit Shell.Mcp.Tools.Tests;

// Aufteilung des MCP-Modus (Shell.Mcp.*): Jede Werkzeuggruppe meldet ihre Werkzeuge an, zusammen ohne doppelte
// Namen; ContextTool reicht den Kontext durch; Dienste und Änderungen lassen sich ohne Laden anlegen; der
// Projektordner ist absolut; WriteSourceText behält die Zeilenenden der Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpToolsTests = class
  public
    /// <summary>Dienste einmal ungemessen anlegen: Was Index, Gruppe und Dienste beim ersten Gebrauch prozessweit
    /// anlegen und behalten (globale Sperren), zählte sonst als Leck von ServicesStartWithoutLoading (72 Byte).
    /// </summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure EachGroupRegistersItsTools;
    [Test]
    procedure AllToolsHaveDistinctNames;
    [Test]
    procedure ContextToolPassesContextAndArguments;
    [Test]
    procedure DryRunDefaultsToTrue;
    [Test]
    procedure RootIsAbsoluteWithoutTrailingDelimiter;
    [Test]
    procedure ServicesStartWithoutLoading;
    [Test]
    procedure ChangesOutsideVersionControlGiveReason;
    [Test]
    procedure WriteSourceTextKeepsLineBreaks;
    /// <summary>#1458: Beschreibungen und Eingabeschemas aller Werkzeuge in beiden Sprachen; jedes Schema ist
    /// gültiges JSON mit Eigenschaften, die englischen Texte sind ohne deutsche Wörter.</summary>
    [Test]
    procedure ToolsSpeakBothLanguages;
    /// <summary>SchemaWith setzt die Beschreibungen als JSON-Texte ein, auch mit Anführungszeichen.</summary>
    [Test]
    procedure SchemaWithQuotesDescriptions;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Prompts,
  Atlas.Common.Localization.Texts,
  Shell.CommandLine,
  Shell.Mcp.Context,
  Shell.Mcp.Ide,
  Shell.Mcp.Services,
  Shell.Mcp.Startup,
  Shell.Mcp.Tools,
  Shell.Mcp.NavigationTools,
  Shell.Mcp.BuildTestTools,
  Shell.Mcp.ReportTools,
  Shell.Mcp.CheckTools,
  Shell.Mcp.ArchitectureTools,
  Shell.Mcp.EditingTools,
  Shell.Mcp.ProjectTools,
  Shell.Mcp.ChangeTools,
  Shell.Mcp.Changes;

type
  TRegisterProc = procedure(const AContext: TMcpToolContext);

/// <summary>Namen der Werkzeuge, die ARegister an einem leeren Server anmeldet.</summary>
function NamesOf(ARegister: TRegisterProc): TArray<string>;
var
  mServer: TMcpServer;
  mContext: TMcpToolContext;
  mListed: TJSONObject;
  mTool: TJSONValue;
begin
  Result := nil;
  mServer := TMcpServer.Create('Atlas', '0');
  try
    mContext := Default(TMcpToolContext);
    mContext.Server := mServer;
    ARegister(mContext);
    mListed := mServer.ListTools;
    try
      for mTool in mListed.GetValue<TJSONArray>('tools') do
      begin
        Result := Result + [mTool.GetValue<string>('name')];
      end;
    finally
      mListed.Free;
    end;
  finally
    mServer.Free;
  end;
end;

/// <summary>Deutsche Spuren in einem englischen Text: Umlaute oder häufige deutsche Wörter.</summary>
function LooksGerman(const AText: string): Boolean;
const
  cMarks: array[0..8] of string = ('ä', 'ö', 'ü', 'ß', ' und ', ' oder ', ' der ', ' die ', ' nicht ');
var
  mMark: string;
begin
  Result := False;
  for mMark in cMarks do
  begin
    if Pos(mMark, LowerCase(AText)) > 0 then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Beschreibung des Werkzeugs ATool und aller seiner Parameter, mit Leerzeichen verbunden.</summary>
function ToolText(const ATool: TJSONValue): string;
var
  mName, mDescription: string;
  mProperties, mProperty: TJSONObject;
  mPair: TJSONPair;
begin
  mName := ATool.GetValue<string>('name');
  Result := ATool.GetValue<string>('description');
  Assert.AreNotEqual('', Result, mName);
  mProperties := ATool.GetValue<TJSONObject>('inputSchema').GetValue('properties') as TJSONObject;
  Assert.IsNotNull(mProperties, mName + ': Schema ungültig');
  for mPair in mProperties do
  begin
    mProperty := mPair.JsonValue as TJSONObject;
    if mProperty.TryGetValue<string>('description', mDescription) then
    begin
      Result := Result + ' ' + mDescription;
    end;
  end;
end;

/// <summary>Prüft Beschreibung und Schema jedes Werkzeugs in der aktuellen Sprache.</summary>
procedure CheckToolTexts(AEnglish: Boolean);
var
  mServer: TMcpServer;
  mContext: TMcpToolContext;
  mListed: TJSONObject;
  mTool: TJSONValue;
  mText: string;
begin
  mServer := TMcpServer.Create('Atlas', '0');
  try
    mContext := Default(TMcpToolContext);
    mContext.Server := mServer;
    RegisterContextTools(mContext);
    mListed := mServer.ListTools;
    try
      for mTool in mListed.GetValue<TJSONArray>('tools') do
      begin
        mText := ToolText(mTool);
        if AEnglish then
        begin
          Assert.IsFalse(LooksGerman(mText), mTool.GetValue<string>('name') + ': ' + mText);
        end;
      end;
    finally
      mListed.Free;
    end;
  finally
    mServer.Free;
  end;
end;

function Joined(const ANames: TArray<string>): string;
begin
  Result := ' ' + string.Join(' ', ANames) + ' ';
end;

procedure TMcpToolsTests.EachGroupRegistersItsTools;
begin
  Assert.AreEqual(10, Integer(Length(NamesOf(RegisterNavigationTools))));
  Assert.IsTrue(Pos(' qualified_name ', Joined(NamesOf(RegisterNavigationTools))) > 0);
  Assert.AreEqual(' get_last_build build_project run_tests get_profile get_mutants ',
    Joined(NamesOf(RegisterBuildTestTools)));
  Assert.AreEqual(7, Integer(Length(NamesOf(RegisterCheckTools))));
  Assert.AreEqual(' get_architecture find_path ', Joined(NamesOf(RegisterArchitectureTools)));
  Assert.AreEqual(' rename_symbol apply_code_action fix_findings format_code extract_method ',
    Joined(NamesOf(RegisterEditingTools)));
  Assert.AreEqual(' query_code ', Joined(NamesOf(RegisterQueryTools)));
  Assert.AreEqual(' find_unused_code get_unit_dependencies ', Joined(NamesOf(RegisterDeadCodeTools)));
  Assert.AreEqual(' get_server_status ', Joined(NamesOf(RegisterStatusTools)));
  Assert.AreEqual(' get_affected_tests ', Joined(NamesOf(RegisterAffectedTestsTool)));
  Assert.AreEqual(' get_hotspots ', Joined(NamesOf(RegisterHotspotTools)));
  Assert.AreEqual(' resolve_address analyze_report ', Joined(NamesOf(RegisterReportTools)));
end;

procedure TMcpToolsTests.AllToolsHaveDistinctNames;
var
  mNames: TArray<string>;
  mIndex, mOther: Integer;
begin
  mNames := NamesOf(RegisterContextTools);
  Assert.AreEqual(35, Integer(Length(mNames)));
  for mIndex := 0 to High(mNames) do
  begin
    for mOther := mIndex + 1 to High(mNames) do
    begin
      Assert.AreNotEqual(mNames[mIndex], mNames[mOther], 'doppelt angemeldet');
    end;
  end;
end;

function EchoTool(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Root + ':' + TMcpArgs.OptionalString(AArguments, 'name');
end;

procedure TMcpToolsTests.ContextToolPassesContextAndArguments;
var
  mContext: TMcpToolContext;
  mHandler: TMcpToolHandler;
  mArguments: TJSONObject;
begin
  mContext := Default(TMcpToolContext);
  mContext.Root := 'C:\Projekt';
  mHandler := ContextTool(mContext, EchoTool);
  // Spätere Änderungen am Kontext erreichen den Handler nicht: Er arbeitet mit einer Kopie.
  mContext.Root := 'anders';
  mArguments := TJSONObject.Create;
  try
    mArguments.AddPair('name', 'TFoo');
    Assert.AreEqual('C:\Projekt:TFoo', mHandler(mArguments));
  finally
    mArguments.Free;
  end;
end;

procedure TMcpToolsTests.DryRunDefaultsToTrue;
var
  mArguments: TJSONObject;
begin
  Assert.IsTrue(DryRunOf(nil));
  mArguments := TJSONObject.Create;
  try
    Assert.IsTrue(DryRunOf(mArguments));
    mArguments.AddPair('dryRun', TJSONBool.Create(False));
    Assert.IsFalse(DryRunOf(mArguments));
  finally
    mArguments.Free;
  end;
end;

procedure TMcpToolsTests.RootIsAbsoluteWithoutTrailingDelimiter;
var
  mOptions: TCommandLineOptions;
  mRoot: string;
begin
  mOptions := Default(TCommandLineOptions);
  mOptions.McpRoot := IncludeTrailingPathDelimiter(TPath.GetTempPath);
  mRoot := RootOf(mOptions);
  Assert.IsTrue(TPath.IsPathRooted(mRoot));
  Assert.AreEqual(ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.GetTempPath)), mRoot);
  mOptions.McpRoot := '';
  Assert.AreEqual(ExcludeTrailingPathDelimiter(TPath.GetFullPath(GetCurrentDir)), RootOf(mOptions));
end;

function NewFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'atlas-mcp-' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(Result);
end;

procedure TMcpToolsTests.WarmUpFirstUse;
begin
  ServicesStartWithoutLoading;
end;

procedure TMcpToolsTests.ServicesStartWithoutLoading;
var
  mFolder: string;
  mServices: TMcpServices;
  mServer: TMcpServer;
  mContext: TMcpToolContext;
  mLogger: ILogger;
begin
  mLogger := TLogger.Create;
  mFolder := NewFolder;
  mServer := TMcpServer.Create('Atlas', '0');
  try
    mServices := TMcpServices.Create(mFolder, mLogger);
    try
      Assert.AreEqual(mFolder, mServices.Root);
      Assert.IsNotNull(mServices.Workspace);
      mContext := mServices.ToolContext(mServer);
      Assert.AreSame(mServer, mContext.Server);
      Assert.AreSame(IInterface(mServices.Index), IInterface(mContext.Index));
      Assert.IsTrue(Assigned(mContext.Architecture) and Assigned(mContext.FindPath));
      Assert.AreEqual(0, Integer(Length(mServices.AllFiles()())));
    finally
      mServices.Free;
    end;
  finally
    mServer.Free;
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TMcpToolsTests.ChangesOutsideVersionControlGiveReason;
var
  mFolder: string;
  mServices: TMcpServices;
  mChanges: TMcpChangeSet;
  mLogger: ILogger;
begin
  mLogger := TLogger.Create;
  mFolder := NewFolder;
  try
    mServices := TMcpServices.Create(mFolder, mLogger);
    try
      mChanges := ChangesOf(mServices.Group, mFolder)('');
      Assert.AreEqual('HEAD', mChanges.Base);
      Assert.AreNotEqual('', mChanges.Error, 'ohne Git oder SVN ein Grund');
      Assert.AreEqual(0, Integer(Length(mChanges.Files)));
    finally
      mServices.Free;
    end;
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TMcpToolsTests.WriteSourceTextKeepsLineBreaks;
var
  mFolder, mFile: string;
begin
  mFolder := NewFolder;
  try
    mFile := TPath.Combine(mFolder, 'Datei.pas');
    TFile.WriteAllText(mFile, 'unit Datei;'#13#10, TEncoding.UTF8);
    WriteSourceText(mFile, 'unit Datei;'#10'end.'#10);
    Assert.IsTrue(Pos(#13#10'end.', TFile.ReadAllText(mFile, TEncoding.UTF8)) > 0, 'Zeilenende der Datei bleibt CRLF');
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TMcpToolsTests.ToolsSpeakBothLanguages;
var
  mSaved: TTextLanguage;
begin
  mSaved := TAtlasLocale.Language;
  try
    TAtlasLocale.Use(TTextLanguage.German);
    CheckToolTexts(False);
    TAtlasLocale.Use(TTextLanguage.English);
    CheckToolTexts(True);
  finally
    TAtlasLocale.Use(mSaved);
  end;
end;

procedure TMcpToolsTests.SchemaWithQuotesDescriptions;
begin
  Assert.AreEqual('{"a":"x \"y\"","b":"z"}', SchemaWith('{"a":%s,"b":%s}', ['x "y"', 'z']));
  Assert.AreEqual('{"a":%s}', SchemaWith('{"a":%s}', []));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpToolsTests);

end.
