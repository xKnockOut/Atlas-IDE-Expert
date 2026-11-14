unit Atlas.Common.Editing.ProjectCommands.Tests;

// Tests für die Schnellbefehle /define, /searchpath, /config und /dfm (#301), /unit und /open (#297),
// /component (#299), /log und /except mit slashCommands.logCall (#304) und /event (#295)
// und /test (#295) mit einem Host, der Dateien im Speicher hält und Aufrufe mitschreibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProjectCommandsTests = class
  public
    [Test]
    procedure DefineAddsToActiveConfiguration;
    [Test]
    procedure DefineBangAddsToBase;
    [Test]
    procedure DefinePresentStays;
    [Test]
    procedure SearchPathNeedsExistingFolder;
    [Test]
    procedure ConfigSelectsBuild;
    [Test]
    procedure DfmJumpsToEvent;
    [Test]
    procedure WithoutHostNothingHappens;
    [Test]
    procedure UnitCreatesAndRegisters;
    [Test]
    procedure UnitWrongPlaceFails;
    [Test]
    procedure OpenFindsInSearchPath;
    [Test]
    procedure OpenUnknownFails;
    [Test]
    procedure LogUsesConfiguredCall;
    [Test]
    procedure ExceptUsesConfiguredCall;
    [Test]
    procedure ComponentGoesIntoPackage;
    [Test]
    procedure ComponentAncestorFromIndex;
    [Test]
    procedure ComponentWrongPlaceFails;
    [Test]
    procedure ComponentFollowsLineBreakAndStyle;
    [Test]
    procedure EventForFormAndComponent;
    [Test]
    procedure EventWrongPlaceFails;
    [Test]
    procedure TestCreatesTestUnit;
    [Test]
    procedure TestAddsToExistingTestUnit;
    [Test]
    procedure TestWrongPlaceFails;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Text.Lines;

type
  TFakeHost = class(TInterfacedObject, ISlashHost)
  public
    Info: TProjectInfo;
    Files: TDictionary<string, string>;
    Folders: TArray<string>;
    Written: string;
    Config: string;
    Platform: string;
    Shown: string;
    Selection: TTextRange;
    WrittenFiles: TArray<TSlashFile>;
    ShowAfterWrite: string;
    LogCallValue: string;
    PaletteValue: string;
    TestTarget: TSlashTestUnit;
    TestReason: string;
    constructor Create;
    destructor Destroy; override;
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    procedure WriteProject(const AUri, AText: string);
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
    function HeaderTemplate(const AUri: string): string;
    procedure WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
    function Setting(const AUri, AName: string): string;
    function TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
    procedure Notify(const AUri, AMessage: string);
    procedure MoveCursor(const AUri: string; const APosition: TTextPosition);
    function RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
    function UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
    function FindingsAt(const AUri, AText: string; ALine: Integer; out AFindings: TArray<TSlashFinding>): Boolean;
  end;

const
  cDproj =
    '<Project>'#13#10 +
    '    <PropertyGroup Condition="''$(Base)''!=''''">'#13#10 +
    '        <DCC_UnitSearchPath>$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <PropertyGroup Condition="''$(Cfg_1)''!=''''">'#13#10 +
    '        <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <BuildConfiguration Include="Debug">'#13#10 +
    '            <Key>Cfg_1</Key>'#13#10 +
    '        </BuildConfiguration>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>'#13#10;

  cFormUnit =
    'unit Main;'#10 +                                       // 0
    'interface'#10 +                                        // 1
    'type'#10 +                                             // 2
    '  TForm1 = class(TForm)'#10 +                          // 3
    '    procedure Button1Click(Sender: TObject);'#10 +     // 4
    '  end;'#10 +                                           // 5
    'implementation'#10 +                                   // 6
    'procedure TForm1.Button1Click(Sender: TObject);'#10 +  // 7
    'begin'#10 +                                            // 8
    '  %s'#10 +                                             // 9 Befehl
    'end;'#10 +                                             // 10
    'end.';

  cFormText =
    'object Form1: TForm1'#13#10 +
    '  Caption = ''Haupt'''#13#10 +
    '  object Button1: TButton'#13#10 +
    '    OnClick = Button1Click'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

/// <summary>Wie TDocumentUris.ToPath es für die Datei zurückgibt, plattformunabhängig.</summary>
function SameFile(const ALeft, ARight: string): Boolean;
begin
  // ExtractFileName trennt unter Windows nur an "\" und ":", daher "/" vereinheitlichen.
  Result := SameText(ExtractFileName(StringReplace(ALeft, '/', '\', [rfReplaceAll])),
    ExtractFileName(StringReplace(ARight, '/', '\', [rfReplaceAll])));
end;

{ TFakeHost }

constructor TFakeHost.Create;
begin
  inherited Create;
  Files := TDictionary<string, string>.Create;
  Info.FileName := 'App.dproj';
  Info.Config := 'Debug';
  Info.Configs := ['Debug', 'Release'];
  Info.Platforms := ['Win32', 'Win64'];
  Files.Add('App.dproj', cDproj);
  Files.Add('Main.dfm', cFormText);
end;

destructor TFakeHost.Destroy;
begin
  Files.Free;
  inherited;
end;

function TFakeHost.Project(const AUri: string; out AProject: TProjectInfo): Boolean;
begin
  AProject := Info;
  Result := True;
end;

function TFakeHost.ReadFile(const AFileName: string; out AText: string): Boolean;
var
  mPair: TPair<string, string>;
begin
  for mPair in Files do
  begin
    if SameFile(mPair.Key, AFileName) then
    begin
      AText := mPair.Value;
      Exit(True);
    end;
  end;
  AText := '';
  Result := False;
end;

function TFakeHost.DirectoryExists(const APath: string): Boolean;
var
  mFolder: string;
begin
  for mFolder in Folders do
  begin
    if SameFile(mFolder, APath) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TFakeHost.WriteProject(const AUri, AText: string);
begin
  Written := AText;
end;

procedure TFakeHost.SelectBuild(const AUri, AConfig, APlatform: string);
begin
  Config := AConfig;
  Platform := APlatform;
end;

procedure TFakeHost.ShowDocument(const AFileName: string; const ASelection: TTextRange);
begin
  Shown := AFileName;
  Selection := ASelection;
end;

function TFakeHost.HeaderTemplate(const AUri: string): string;
begin
  Result := '';
end;

procedure TFakeHost.WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
begin
  WrittenFiles := AFiles;
  ShowAfterWrite := AShow;
end;

function TFakeHost.Setting(const AUri, AName: string): string;
begin
  if AName = TSlashSettings.cLogCall then
  begin
    Result := LogCallValue;
  end
  else if AName = TSlashSettings.cComponentPalette then
  begin
    Result := PaletteValue;
  end
  else
  begin
    Result := '';
  end;
end;

function TFakeHost.TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
begin
  ATarget := TestTarget;
  ATarget.Reason := TestReason;
  Result := TestReason = '';
end;

procedure TFakeHost.Notify(const AUri, AMessage: string);
begin
end;

procedure TFakeHost.MoveCursor(const AUri: string; const APosition: TTextPosition);
begin
end;

function TFakeHost.RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
begin
  AIds := nil;
  Result := False;
end;

function TFakeHost.UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := False;
end;

function TFakeHost.FindingsAt(const AUri, AText: string; ALine: Integer;
  out AFindings: TArray<TSlashFinding>): Boolean;
begin
  AFindings := nil;
  Result := False;
end;

function Run(const ACommand: string; const AHost: ISlashHost; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(Format(cFormUnit, [ACommand]), TTextPosition.Create(10, 0),
    TSlashEnvironment.Create(nil, nil, nil, '', TDocumentUris.FromPath(TPath.Combine(GetCurrentDir, 'Main.pas')),
    AHost), AEdits);
end;

procedure TProjectCommandsTests.DefineAddsToActiveConfiguration;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  Assert.IsTrue(Run('/define TEST', mKeep, mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(9, mEdits[0].Range.StartPos.Line);
  // Ein Diff zeigt nur die DCC_Define-Zeile.
  Assert.AreEqual(StringReplace(cDproj, '>DEBUG;', '>TEST;DEBUG;', []), mHost.Written);
end;

procedure TProjectCommandsTests.DefineBangAddsToBase;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  Assert.IsTrue(Run('/define! TEST', mKeep, mEdits));
  Assert.AreEqual(StringReplace(cDproj, '''$(Base)''!=''''">'#13#10, '''$(Base)''!=''''">'#13#10 +
    '        <DCC_Define>TEST;$(DCC_Define)</DCC_Define>'#13#10, []), mHost.Written);
end;

procedure TProjectCommandsTests.DefinePresentStays;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  Assert.IsFalse(Run('/define DEBUG', mKeep, mEdits));
  Assert.IsFalse(Run('/define 1X', mKeep, mEdits));
  Assert.AreEqual('', mHost.Written);
end;

procedure TProjectCommandsTests.SearchPathNeedsExistingFolder;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  Assert.IsFalse(Run('/searchpath Fehlt', mKeep, mEdits));
  Assert.AreEqual('', mHost.Written);
  mHost.Folders := ['Common'];
  Assert.IsTrue(Run('/searchpath ''Common''', mKeep, mEdits));
  Assert.AreEqual(StringReplace(cDproj, '<DCC_UnitSearchPath>$', '<DCC_UnitSearchPath>Common;$', []),
    mHost.Written);
end;

procedure TProjectCommandsTests.ConfigSelectsBuild;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  Assert.IsTrue(Run('/config win64 release', mKeep, mEdits));
  Assert.AreEqual('Release', mHost.Config);
  Assert.AreEqual('Win64', mHost.Platform);
  mHost.Config := '';
  Assert.IsFalse(Run('/config Profil', mKeep, mEdits));
  Assert.AreEqual('', mHost.Config);
end;

procedure TProjectCommandsTests.DfmJumpsToEvent;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  Assert.IsTrue(Run('/dfm', mKeep, mEdits));
  Assert.IsTrue(SameFile('Main.dfm', mHost.Shown), mHost.Shown);
  Assert.AreEqual(3, mHost.Selection.StartPos.Line);
  Assert.AreEqual(4, mHost.Selection.StartPos.Character);
  mHost.Files.Remove('Main.dfm');
  mHost.Shown := '';
  Assert.IsFalse(Run('/dfm', mKeep, mEdits));
  Assert.AreEqual('', mHost.Shown);
end;

procedure TProjectCommandsTests.WithoutHostNothingHappens;
var
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(Run('/define TEST', nil, mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(Format(cFormUnit, ['/define TEST']), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
end;

const
  cProgramText =
    'program App;'#13#10 +
    'uses'#13#10 +
    '  Vcl.Forms,'#13#10 +
    '  Main in ''Main.pas'';'#13#10 +
    'begin'#13#10 +
    'end.'#13#10;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

procedure TProjectCommandsTests.UnitCreatesAndRegisters;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.Info.FileName := TPath.Combine(GetCurrentDir, 'App.dproj');
  mHost.Info.MainSource := TPath.Combine(GetCurrentDir, 'App.dpr');
  mHost.Files.Add('App.dpr', cProgramText);
  Assert.IsTrue(Run('/unit Kunden.Daten', mKeep, mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(3, Integer(Length(mHost.WrittenFiles)));
  // Neue Unit neben Main.pas, parst und wird danach geöffnet.
  Assert.IsTrue(mHost.WrittenFiles[0].New);
  Assert.IsTrue(SameFile('Kunden.Daten.pas', mHost.WrittenFiles[0].FileName), mHost.WrittenFiles[0].FileName);
  Assert.IsTrue(Parses(mHost.WrittenFiles[0].Text), mHost.WrittenFiles[0].Text);
  Assert.IsTrue(StartsText('unit Kunden.Daten;', mHost.WrittenFiles[0].Text));
  Assert.AreEqual(mHost.WrittenFiles[0].FileName, mHost.ShowAfterWrite);
  // .dpr: Eintrag am Ende des uses.
  Assert.IsFalse(mHost.WrittenFiles[1].New);
  Assert.IsTrue(Pos('  Main in ''Main.pas'','#13#10'  Kunden.Daten in ''Kunden.Daten.pas'';',
    mHost.WrittenFiles[1].Text) > 0, mHost.WrittenFiles[1].Text);
  Assert.IsTrue(Parses(mHost.WrittenFiles[1].Text), mHost.WrittenFiles[1].Text);
  // .dproj: gültige DCCReference vor der ersten BuildConfiguration (das Projekt hat noch keine).
  Assert.IsTrue(Pos('    <ItemGroup>'#13#10'        <DCCReference Include="Kunden.Daten.pas"/>'#13#10 +
    '        <BuildConfiguration Include="Debug">', mHost.WrittenFiles[2].Text) > 0, mHost.WrittenFiles[2].Text);
end;

procedure TProjectCommandsTests.UnitWrongPlaceFails;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.Info.FileName := TPath.Combine(GetCurrentDir, 'App.dproj');
  // Kein gültiger Name, Datei schon vorhanden, Unit schon im Projekt, ohne Projekt.
  Assert.IsFalse(Run('/unit 1Daten', mKeep, mEdits));
  mHost.Files.Add('Daten.pas', 'unit Daten;');
  Assert.IsFalse(Run('/unit Daten', mKeep, mEdits));
  mHost.Info.Units := [Default(TProjectUnit)];
  mHost.Info.Units[0].Name := 'Werkzeug';
  Assert.IsFalse(Run('/unit Werkzeug', mKeep, mEdits));
  Assert.IsFalse(Run('/unit Neu', nil, mEdits));
  Assert.AreEqual(0, Integer(Length(mHost.WrittenFiles)));
end;

procedure TProjectCommandsTests.OpenFindsInSearchPath;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.Info.SearchPaths := [TPath.Combine(GetCurrentDir, 'Common')];
  mHost.Files.Add(TPath.Combine(TPath.Combine(GetCurrentDir, 'Common'), 'Werkzeug.pas'), 'unit Werkzeug;');
  Assert.IsTrue(Run('/open Werkzeug', mKeep, mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.IsTrue(SameFile('Werkzeug.pas', mHost.Shown), mHost.Shown);
  Assert.AreEqual(0, mHost.Selection.StartPos.Line);
  // Mit Namespace des Projekts: /open SysUtils findet System.SysUtils.
  mHost.Shown := '';
  mHost.Info.Namespaces := ['System'];
  mHost.Files.Add(TPath.Combine(GetCurrentDir, 'System.SysUtils.pas'), 'unit System.SysUtils;');
  Assert.IsTrue(Run('/open SysUtils', mKeep, mEdits));
  Assert.IsTrue(SameFile('System.SysUtils.pas', mHost.Shown), mHost.Shown);
end;

procedure TProjectCommandsTests.OpenUnknownFails;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  Assert.IsFalse(Run('/open Fehlt', mKeep, mEdits));
  Assert.IsFalse(Run('/open', mKeep, mEdits));
  Assert.IsFalse(Run('/open Werkzeug', nil, mEdits));
  Assert.AreEqual('', mHost.Shown);
  // Stehen gebliebene Zeile: Hinweis statt Löschen.
  mProblems := TSlashCommandRegistry.Shared.Problems(Format(cFormUnit, ['/open Fehlt']), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
end;

/// <summary>FormUnit mit ACommand und angewandten AEdits; von hinten, damit frühere Positionen gültig
/// bleiben.</summary>
function Expanded(const ACommand: string; const AEdits: TArray<TRuleEdit>): string;
var
  mTable: TLineTable;
  mIndex, mStart, mStop: Integer;
begin
  Result := Format(cFormUnit, [ACommand]);
  for mIndex := High(AEdits) downto 0 do
  begin
    mTable := TLineTable.Build(Result);
    mStart := mTable.OffsetAt(AEdits[mIndex].Range.StartPos);
    mStop := mTable.OffsetAt(AEdits[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStart) + AEdits[mIndex].NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

procedure TProjectCommandsTests.LogUsesConfiguredCall;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  // Ohne Einstellung: OutputDebugString.
  Assert.IsTrue(Run('/log', mKeep, mEdits));
  mText := Expanded('/log', mEdits);
  Assert.IsTrue(Pos('  OutputDebugString(PChar(''Main.TForm1.Button1Click''));', mText) > 0, mText);
  // Routinenname: bekommt den Text als Argument.
  mHost.LogCallValue := 'Log.Debug';
  Assert.IsTrue(Run('/log', mKeep, mEdits));
  mText := Expanded('/log', mEdits);
  Assert.IsTrue(Pos('  Log.Debug(''Main.TForm1.Button1Click'');', mText) > 0, mText);
  // Vorlage mit {text}.
  mHost.LogCallValue := 'Logger.Send(TLogLevel.Debug, {text});';
  Assert.IsTrue(Run('/log Start', mKeep, mEdits));
  mText := Expanded('/log Start', mEdits);
  Assert.IsTrue(Pos('  Logger.Send(TLogLevel.Debug, ''Main.TForm1.Button1Click: Start'');', mText) > 0, mText);
end;

procedure TProjectCommandsTests.ExceptUsesConfiguredCall;
const
  cBody = '/except'#10'  Close;';
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mText: string;
  mProblems: TArray<TSlashProblem>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.LogCallValue := 'Log.Error';
  Assert.IsTrue(Run(cBody, mKeep, mEdits));
  mText := Expanded(cBody, mEdits);
  Assert.IsTrue(Pos('      Log.Error(E.ClassName + '': '' + E.Message);'#10'      raise;', mText) > 0, mText);
  // Falscher Ort: außerhalb einer Routine bleibt die Zeile mit Hinweis stehen.
  mProblems := TSlashCommandRegistry.Shared.Problems('unit U;'#10'interface'#10'/except'#10'implementation'#10 +
    'end.', nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
end;

const
  cPackageText =
    'package Paket;'#13#10 +
    'requires'#13#10 +
    '  rtl,'#13#10 +
    '  vcl;'#13#10 +
    'contains'#13#10 +
    '  Main in ''Main.pas'';'#13#10 +
    'end.'#13#10;

function RunWithIndex(const ACommand: string; const AHost: ISlashHost; const AIndex: ISymbolIndex;
  out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(Format(cFormUnit, [ACommand]), TTextPosition.Create(10, 0),
    TSlashEnvironment.Create(nil, nil, AIndex, '', TDocumentUris.FromPath(TPath.Combine(GetCurrentDir, 'Main.pas')),
    AHost), AEdits);
end;

procedure TProjectCommandsTests.ComponentGoesIntoPackage;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.Info.FileName := TPath.Combine(GetCurrentDir, 'Paket.dproj');
  mHost.Info.MainSource := TPath.Combine(GetCurrentDir, 'Paket.dpk');
  mHost.Files.Add('Paket.dproj', cDproj);
  mHost.Files.Add('Paket.dpk', cPackageText);
  mHost.PaletteValue := 'Firma';
  Assert.IsTrue(Run('/component TZaehler', mKeep, mEdits));
  Assert.AreEqual(3, Integer(Length(mHost.WrittenFiles)));
  mText := mHost.WrittenFiles[0].Text;
  Assert.IsTrue(SameFile('Zaehler.pas', mHost.WrittenFiles[0].FileName), mHost.WrittenFiles[0].FileName);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(Pos('  TZaehler = class(TComponent)', mText) > 0, mText);
  Assert.IsTrue(Pos('  published', mText) > 0, mText);
  Assert.IsTrue(Pos('RegisterComponents(''Firma'', [TZaehler]);', mText) > 0, mText);
  // In der .dpk unter contains, nicht unter requires.
  Assert.IsTrue(Pos('contains'#13#10'  Main in ''Main.pas'','#13#10'  Zaehler in ''Zaehler.pas'';',
    mHost.WrittenFiles[1].Text) > 0, mHost.WrittenFiles[1].Text);
  Assert.IsTrue(Pos('<DCCReference Include="Zaehler.pas"/>', mHost.WrittenFiles[2].Text) > 0);
  Assert.AreEqual(mHost.WrittenFiles[0].FileName, mHost.ShowAfterWrite);
  // Ohne Einstellung: Palettenseite "Eigene".
  mHost.PaletteValue := '';
  Assert.IsTrue(Run('/component TZaehler2', mKeep, mEdits));
  Assert.IsTrue(Pos('RegisterComponents(''Eigene'', [TZaehler2]);', mHost.WrittenFiles[0].Text) > 0);
end;

procedure TProjectCommandsTests.ComponentFollowsLineBreakAndStyle;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mStyle: TFormatStyle;
  mText, mUri: string;
begin
  // #299 (#121, #43): Zeilenende der Datei des Befehls und Einrückung nach dem Formatstil.
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.Info.FileName := '';
  mHost.Files.Remove('App.dproj');
  mUri := TDocumentUris.FromPath(TPath.Combine(GetCurrentDir, 'Main.pas'));
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Format(cFormUnit, ['/component TZaehler']),
    TTextPosition.Create(10, 0), TSlashEnvironment.Create(nil, nil, nil, '', mUri, mKeep), mEdits));
  mText := mHost.WrittenFiles[0].Text;
  Assert.AreEqual(0, Pos(#13, mText), 'LF wie die Datei des Befehls');
  Assert.IsTrue(Pos(#10'  TZaehler = class(TComponent)'#10'  private'#10, mText) > 0, mText);
  mStyle := TFormatStyle.Default;
  mStyle.IndentSize := 4;
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(StringReplace(Format(cFormUnit, ['/component TZaehler2']),
    #10, #13#10, [rfReplaceAll]), TTextPosition.Create(10, 0),
    TSlashEnvironment.Create(nil, nil, nil, '', mUri, mKeep).WithStyle(mStyle), mEdits));
  mText := mHost.WrittenFiles[0].Text;
  Assert.IsTrue(Pos(#13#10'    TZaehler2 = class(TComponent)'#13#10'    private'#13#10, mText) > 0, mText);
  Assert.IsTrue(Pos(#13#10'    RegisterComponents(', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TProjectCommandsTests.ComponentAncestorFromIndex;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mIndex: ISymbolIndex;
  mText: string;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  // Ohne Projekt: nur die Unit, Vorfahr samt Unit aus dem Index.
  mHost.Info.FileName := '';
  mHost.Files.Remove('App.dproj');
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Vcl.StdCtrls;'#10'interface'#10'type'#10 +
    '  TButton = class(TObject)'#10'  end;'#10'implementation'#10'end.', 'C:\Lib\Vcl.StdCtrls.pas', nil));
  Assert.IsTrue(RunWithIndex('/component TMyButton : TButton', mKeep, mIndex, mEdits));
  Assert.AreEqual(1, Integer(Length(mHost.WrittenFiles)));
  mText := mHost.WrittenFiles[0].Text;
  Assert.IsTrue(Pos('  System.SysUtils, System.Classes, Vcl.StdCtrls;', mText) > 0, mText);
  Assert.IsTrue(Pos('  TMyButton = class(TButton)', mText) > 0, mText);
  Assert.IsTrue(SameFile('MyButton.pas', mHost.WrittenFiles[0].FileName), mHost.WrittenFiles[0].FileName);
end;

procedure TProjectCommandsTests.ComponentWrongPlaceFails;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  // Kein Name, unbekannter Vorfahr, ohne Editor.
  Assert.IsFalse(Run('/component', mKeep, mEdits));
  Assert.IsFalse(Run('/component TA : TUnbekannt', mKeep, mEdits));
  Assert.IsFalse(Run('/component TA', nil, mEdits));
  Assert.AreEqual(0, Integer(Length(mHost.WrittenFiles)));
  mProblems := TSlashCommandRegistry.Shared.Problems(Format(cFormUnit, ['/component TA : TUnbekannt']), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
end;

const
  cEventLib =
    'unit Vcl.Lib;'#10'interface'#10'type'#10 +
    '  TNotifyEvent = procedure(Sender: TObject) of object;'#10 +
    '  TCloseQueryEvent = procedure(Sender: TObject; var CanClose: Boolean) of object;'#10 +
    '  THelpEvent = function(Command: Word; Data: NativeInt; var CallHelp: Boolean): Boolean of object;'#10 +
    '  TControl = class'#10'  published'#10'    property OnClick: TNotifyEvent read FOnClick write FOnClick;'#10 +
    '  end;'#10'  TButton = class(TControl)'#10'  end;'#10'  TForm = class(TControl)'#10'  published'#10 +
    '    property OnCreate: TNotifyEvent read FOnCreate write FOnCreate;'#10 +
    '    property OnCloseQuery: TCloseQueryEvent read FOnCloseQuery write FOnCloseQuery;'#10 +
    '    property OnHelp: THelpEvent read FOnHelp write FOnHelp;'#10'  end;'#10 +
    'implementation'#10'end.';

  cEventUnit =
    'unit Main;'#10 +                                       // 0
    'interface'#10 +                                        // 1
    'uses Vcl.Lib;'#10 +                                    // 2
    'type'#10 +                                             // 3
    '  TForm1 = class(TForm)'#10 +                          // 4
    '    Button1: TButton;'#10 +                            // 5
    '    procedure Button1Click(Sender: TObject);'#10 +     // 6
    '  private'#10 +                                       // 7
    '  end;'#10 +                                           // 8
    'implementation'#10 +                                   // 9
    'procedure TForm1.Button1Click(Sender: TObject);'#10 +  // 10
    'begin'#10 +                                            // 11
    '  %s'#10 +                                             // 12 Befehl
    'end;'#10 +                                             // 13
    'end.';

  cEventForm =
    'object Form1: TForm1'#13#10 +
    '  Caption = ''Haupt'''#13#10 +
    '  object Button1: TButton'#13#10 +
    '    Left = 8'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

function EventIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(cEventLib, 'C:\Lib\Vcl.Lib.pas', nil));
end;

function RunEvent(const ACommand: string; const AHost: ISlashHost; out AText: string): Boolean;
var
  mEdits: TArray<TRuleEdit>;
  mTable: TLineTable;
  mIndex, mNext, mStart, mStop: Integer;
  mSwap: TRuleEdit;
begin
  AText := Format(cEventUnit, [ACommand]);
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(13, 0),
    TSlashEnvironment.Create(nil, nil, EventIndex, '', TDocumentUris.FromPath(TPath.Combine(GetCurrentDir,
    'Main.pas')), AHost), mEdits);
  // Von hinten anwenden, damit frühere Positionen gültig bleiben.
  mTable := TLineTable.Build(AText);
  for mIndex := 0 to High(mEdits) do
  begin
    for mNext := mIndex + 1 to High(mEdits) do
    begin
      if mTable.OffsetAt(mEdits[mNext].Range.StartPos) > mTable.OffsetAt(mEdits[mIndex].Range.StartPos) then
      begin
        mSwap := mEdits[mIndex];
        mEdits[mIndex] := mEdits[mNext];
        mEdits[mNext] := mSwap;
      end;
    end;
  end;
  for mIndex := 0 to High(mEdits) do
  begin
    mStart := mTable.OffsetAt(mEdits[mIndex].Range.StartPos);
    mStop := mTable.OffsetAt(mEdits[mIndex].Range.EndPos);
    AText := Copy(AText, 1, mStart) + mEdits[mIndex].NewText + Copy(AText, mStop + 1, MaxInt);
  end;
end;

procedure TProjectCommandsTests.EventForFormAndComponent;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mText: string;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.Files.Remove('Main.dfm');
  mHost.Files.Add('Main.dfm', cEventForm);
  // Ereignis des Formulars: FormCreate im ersten Abschnitt, Zuweisung hinter Caption.
  Assert.IsTrue(RunEvent('/event OnCreate', mKeep, mText), '/event OnCreate');
  Assert.IsTrue(Pos('    procedure Button1Click(Sender: TObject);'#10'    procedure FormCreate(Sender: TObject);'#10 +
    '  private', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure TForm1.FormCreate(Sender: TObject);'#10'begin'#10#10'end;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
  Assert.AreEqual(1, Integer(Length(mHost.WrittenFiles)));
  Assert.AreEqual('object Form1: TForm1'#13#10'  Caption = ''Haupt'''#13#10'  OnCreate = FormCreate'#13#10 +
    '  object Button1: TButton'#13#10'    Left = 8'#13#10'  end'#13#10'end'#13#10, mHost.WrittenFiles[0].Text);
  // var-Parameter und Funktionen übernehmen die Signatur des Typs.
  Assert.IsTrue(RunEvent('/event OnCloseQuery', mKeep, mText), '/event OnCloseQuery');
  Assert.IsTrue(Pos('procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);', mText) > 0, mText);
  Assert.IsTrue(RunEvent('/event OnHelp', mKeep, mText), '/event OnHelp');
  Assert.IsTrue(Pos('function TForm1.FormHelp(Command: Word; Data: NativeInt; var CallHelp: Boolean): Boolean;',
    mText) > 0, mText);
  // Komponente: Button1Click gibt es schon als Methode, also Button1Click2; Zuweisung im Objekt Button1.
  Assert.IsTrue(RunEvent('/event Button1.OnClick', mKeep, mText), '/event Button1.OnClick');
  Assert.IsTrue(Pos('    procedure Button1Click2(Sender: TObject);', mText) > 0, mText);
  Assert.IsTrue(Pos('    Left = 8'#13#10'    OnClick = Button1Click2'#13#10'  end', mHost.WrittenFiles[0].Text) > 0,
    mHost.WrittenFiles[0].Text);
end;

procedure TProjectCommandsTests.EventWrongPlaceFails;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mText: string;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  // Main.dfm weist Button1.OnClick schon zu.
  Assert.IsFalse(RunEvent('/event Button1.OnClick', mKeep, mText));
  Assert.IsFalse(RunEvent('/event Button2.OnClick', mKeep, mText));
  Assert.IsFalse(RunEvent('/event Button1.OnGibtsNicht', mKeep, mText));
  Assert.IsFalse(RunEvent('/event Click', mKeep, mText));
  Assert.IsFalse(RunEvent('/event OnCreate', nil, mText));
  mHost.Files.Remove('Main.dfm');
  Assert.IsFalse(RunEvent('/event OnCreate', mKeep, mText));
  Assert.AreEqual(0, Integer(Length(mHost.WrittenFiles)));
end;

{ /test }

const
  cKundenUnit =
    'unit Kunden;'#13#10 +                                     // 0
    'interface'#13#10 +                                        // 1
    'type'#13#10 +                                             // 2
    '  TKunde = class'#13#10 +                                 // 3
    '  private'#13#10 +                                        // 4
    '    function Pruefe: Boolean;'#13#10 +                    // 5
    '  public'#13#10 +                                         // 6
    '    function Berechne(A: Integer): Integer;'#13#10 +      // 7
    '  end;'#13#10 +                                           // 8
    'implementation'#13#10 +                                   // 9
    'function TKunde.Pruefe: Boolean;'#13#10 +                 // 10
    'begin'#13#10 +                                            // 11
    '  %s'#13#10 +                                             // 12 Befehl in Pruefe
    '  Result := True;'#13#10 +                                // 13
    'end;'#13#10 +                                             // 14
    'function TKunde.Berechne(A: Integer): Integer;'#13#10 +   // 15
    'begin'#13#10 +                                            // 16
    '  %s'#13#10 +                                             // 17 Befehl in Berechne
    '  Result := A;'#13#10 +                                   // 18
    'end;'#13#10 +                                             // 19
    'end.'#13#10;

  cKundenTests =
    'unit Kunden.Tests;'#13#10 +
    'interface'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'type'#13#10 +
    '  [TestFixture]'#13#10 +
    '  TKundeTests = class'#13#10 +
    '  public'#13#10 +
    '    [Test]'#13#10 +
    '    procedure TestBerechne;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TKundeTests.TestBerechne;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'initialization'#13#10 +
    '  TDUnitX.RegisterTestFixture(TKundeTests);'#13#10 +
    'end.'#13#10;

  cTestProgramText =
    'program AppTests;'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'begin'#13#10 +
    'end.'#13#10;

function RunTest(const AText: string; ALine: Integer; const AHost: ISlashHost; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  mProblems: TArray<TSlashProblem>;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0),
    TSlashEnvironment.Create(nil, nil, nil, '', TDocumentUris.FromPath(TPath.Combine(GetCurrentDir, 'Kunden.pas')),
    AHost), AEdits);
  AReason := '';
  if not Result then
  begin
    mProblems := TSlashCommandRegistry.Shared.Problems(AText, nil);
    if Length(mProblems) > 0 then
    begin
      AReason := mProblems[0].Message;
    end;
  end;
end;

procedure TProjectCommandsTests.TestCreatesTestUnit;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mReason, mText: string;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.Files.Add('AppTests.dpr', cTestProgramText);
  mHost.Files.Add('AppTests.dproj', cDproj);
  mHost.TestTarget.UnitName := 'Kunden.Tests';
  mHost.TestTarget.FileName := TPath.Combine(GetCurrentDir, 'Kunden.Tests.pas');
  mHost.TestTarget.TestProgram := TPath.Combine(GetCurrentDir, 'AppTests.dpr');
  // Private Methode: das Gerüst hat nur TestBerechne, /test ergänzt TestPruefe.
  Assert.IsTrue(RunTest(Format(cKundenUnit, ['/test', '']), 12, mKeep, mEdits, mReason), mReason);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(3, Integer(Length(mHost.WrittenFiles)));
  Assert.IsTrue(mHost.WrittenFiles[0].New);
  mText := mHost.WrittenFiles[0].Text;
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, '    procedure TestBerechne;'), mText);
  Assert.IsTrue(ContainsStr(mText, '    [Test]'#13#10'    procedure TestPruefe;'#13#10'  end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'procedure TKundeTests.TestPruefe;'#13#10'begin'#13#10 +
    '  Assert.Fail(''Test für TKunde.Pruefe fehlt noch'');'), mText);
  Assert.IsTrue(ContainsStr(mText, '  Kunden;'), mText);
  Assert.IsTrue(ContainsStr(mHost.WrittenFiles[1].Text, 'Kunden.Tests in ''Kunden.Tests.pas'''),
    mHost.WrittenFiles[1].Text);
  Assert.IsTrue(ContainsStr(mHost.WrittenFiles[2].Text, '<DCCReference Include="Kunden.Tests.pas"/>'),
    mHost.WrittenFiles[2].Text);
  Assert.IsTrue(SameFile('Kunden.Tests.pas', mHost.ShowAfterWrite), mHost.ShowAfterWrite);
end;

procedure TProjectCommandsTests.TestAddsToExistingTestUnit;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mReason, mText: string;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.Files.Add('Kunden.Tests.pas', cKundenTests);
  mHost.TestTarget.UnitName := 'Kunden.Tests';
  mHost.TestTarget.FileName := TPath.Combine(GetCurrentDir, 'Kunden.Tests.pas');
  mHost.TestTarget.Exists := True;
  // TestBerechne gibt es: der neue Test heißt TestBerechne2; Kunden kommt ins uses.
  Assert.IsTrue(RunTest(Format(cKundenUnit, ['', '/test']), 17, mKeep, mEdits, mReason), mReason);
  Assert.AreEqual(1, Integer(Length(mHost.WrittenFiles)));
  Assert.IsFalse(mHost.WrittenFiles[0].New);
  mText := mHost.WrittenFiles[0].Text;
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, '    procedure TestBerechne;'#13#10'    [Test]'#13#10 +
    '    procedure TestBerechne2;'#13#10'  end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'procedure TKundeTests.TestBerechne2;'), mText);
  // Entwurf (#1226): Die Testklasse hat kein Feld vom Typ TKunde, also ein lokales Objekt mit Aufruf.
  Assert.IsTrue(ContainsStr(mText, '  Subject := TKunde.Create;'), mText);
  Assert.IsTrue(ContainsStr(mText, '    Actual := Subject.Berechne(A);'), mText);
  Assert.IsTrue(ContainsStr(mText, '    Assert.AreEqual(0, Actual);'), mText);
  Assert.IsTrue(ContainsStr(mText, '  DUnitX.TestFramework,'#13#10'  Kunden;'), mText);
  Assert.IsTrue(Pos('procedure TKundeTests.TestBerechne2;', mText) < Pos('initialization', mText), mText);
end;

procedure TProjectCommandsTests.TestWrongPlaceFails;
var
  mHost: TFakeHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mReason, mText: string;
begin
  mHost := TFakeHost.Create;
  mKeep := mHost;
  mHost.TestTarget.FileName := TPath.Combine(GetCurrentDir, 'Kunden.Tests.pas');
  // In der Klassendeklaration statt im Rumpf einer Methode.
  mText := StringReplace(Format(cKundenUnit, ['', '']), '  private'#13#10, '  private'#13#10'    /test'#13#10, []);
  Assert.IsFalse(RunTest(mText, 5, mKeep, mEdits, mReason));
  Assert.IsTrue(ContainsStr(mReason, 'Rumpf'), mReason);
  Assert.AreEqual(0, Integer(Length(mHost.WrittenFiles)));
  // Ohne Testprojekt: nichts wird geschrieben.
  mHost.TestReason := 'Kein Testprojekt gefunden';
  Assert.IsFalse(RunTest(Format(cKundenUnit, ['/test', '']), 12, mKeep, mEdits, mReason));
  Assert.AreEqual(0, Integer(Length(mHost.WrittenFiles)));
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectCommandsTests);

end.
