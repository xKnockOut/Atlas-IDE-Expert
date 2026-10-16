unit Atlas.Common.Editing.ProjectCommands.Tests;

// Tests für die Schnellbefehle /define, /searchpath, /config und /dfm (#301) sowie /unit und /open (#297)
// mit einem Host, der Dateien im Speicher hält und Aufrufe mitschreibt.

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
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.SlashCommands,
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
  end;

const
  Dproj =
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

  FormUnit =
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

  FormText =
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
  Files.Add('App.dproj', Dproj);
  Files.Add('Main.dfm', FormText);
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
  Pair: TPair<string, string>;
begin
  for Pair in Files do
    if SameFile(Pair.Key, AFileName) then
    begin
      AText := Pair.Value;
      Exit(True);
    end;
  AText := '';
  Result := False;
end;

function TFakeHost.DirectoryExists(const APath: string): Boolean;
var
  Folder: string;
begin
  for Folder in Folders do
    if SameFile(Folder, APath) then
      Exit(True);
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
  if AName = TSlashSettings.LogCall then
    Result := LogCallValue
  else if AName = TSlashSettings.ComponentPalette then
    Result := PaletteValue
  else
    Result := '';
end;

function Run(const ACommand: string; const AHost: ISlashHost; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(Format(FormUnit, [ACommand]), TTextPosition.Create(10, 0), nil,
    nil, AEdits, nil, '', TDocumentUris.FromPath(TPath.Combine(GetCurrentDir, 'Main.pas')), AHost);
end;

procedure TProjectCommandsTests.DefineAddsToActiveConfiguration;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Assert.IsTrue(Run('/define TEST', Keep, Edits));
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(9, Edits[0].Range.StartPos.Line);
  // Ein Diff zeigt nur die DCC_Define-Zeile.
  Assert.AreEqual(StringReplace(Dproj, '>DEBUG;', '>TEST;DEBUG;', []), Host.Written);
end;

procedure TProjectCommandsTests.DefineBangAddsToBase;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Assert.IsTrue(Run('/define! TEST', Keep, Edits));
  Assert.AreEqual(StringReplace(Dproj, '''$(Base)''!=''''">'#13#10, '''$(Base)''!=''''">'#13#10 +
    '        <DCC_Define>TEST;$(DCC_Define)</DCC_Define>'#13#10, []), Host.Written);
end;

procedure TProjectCommandsTests.DefinePresentStays;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Assert.IsFalse(Run('/define DEBUG', Keep, Edits));
  Assert.IsFalse(Run('/define 1X', Keep, Edits));
  Assert.AreEqual('', Host.Written);
end;

procedure TProjectCommandsTests.SearchPathNeedsExistingFolder;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Assert.IsFalse(Run('/searchpath Fehlt', Keep, Edits));
  Assert.AreEqual('', Host.Written);
  Host.Folders := ['Common'];
  Assert.IsTrue(Run('/searchpath ''Common''', Keep, Edits));
  Assert.AreEqual(StringReplace(Dproj, '<DCC_UnitSearchPath>$', '<DCC_UnitSearchPath>Common;$', []),
    Host.Written);
end;

procedure TProjectCommandsTests.ConfigSelectsBuild;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Assert.IsTrue(Run('/config win64 release', Keep, Edits));
  Assert.AreEqual('Release', Host.Config);
  Assert.AreEqual('Win64', Host.Platform);
  Host.Config := '';
  Assert.IsFalse(Run('/config Profil', Keep, Edits));
  Assert.AreEqual('', Host.Config);
end;

procedure TProjectCommandsTests.DfmJumpsToEvent;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Assert.IsTrue(Run('/dfm', Keep, Edits));
  Assert.IsTrue(SameFile('Main.dfm', Host.Shown), Host.Shown);
  Assert.AreEqual(3, Host.Selection.StartPos.Line);
  Assert.AreEqual(4, Host.Selection.StartPos.Character);
  Host.Files.Remove('Main.dfm');
  Host.Shown := '';
  Assert.IsFalse(Run('/dfm', Keep, Edits));
  Assert.AreEqual('', Host.Shown);
end;

procedure TProjectCommandsTests.WithoutHostNothingHappens;
var
  Edits: TArray<TRuleEdit>;
  Problems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(Run('/define TEST', nil, Edits));
  Problems := TSlashCommandRegistry.Shared.Problems(Format(FormUnit, ['/define TEST']), nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
end;

const
  ProgramText =
    'program App;'#13#10 +
    'uses'#13#10 +
    '  Vcl.Forms,'#13#10 +
    '  Main in ''Main.pas'';'#13#10 +
    'begin'#13#10 +
    'end.'#13#10;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TProjectCommandsTests.UnitCreatesAndRegisters;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Host.Info.FileName := TPath.Combine(GetCurrentDir, 'App.dproj');
  Host.Info.MainSource := TPath.Combine(GetCurrentDir, 'App.dpr');
  Host.Files.Add('App.dpr', ProgramText);
  Assert.IsTrue(Run('/unit Kunden.Daten', Keep, Edits));
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(3, Integer(Length(Host.WrittenFiles)));
  // Neue Unit neben Main.pas, parst und wird danach geöffnet.
  Assert.IsTrue(Host.WrittenFiles[0].New);
  Assert.IsTrue(SameFile('Kunden.Daten.pas', Host.WrittenFiles[0].FileName), Host.WrittenFiles[0].FileName);
  Assert.IsTrue(Parses(Host.WrittenFiles[0].Text), Host.WrittenFiles[0].Text);
  Assert.IsTrue(StartsText('unit Kunden.Daten;', Host.WrittenFiles[0].Text));
  Assert.AreEqual(Host.WrittenFiles[0].FileName, Host.ShowAfterWrite);
  // .dpr: Eintrag am Ende des uses.
  Assert.IsFalse(Host.WrittenFiles[1].New);
  Assert.IsTrue(Pos('  Main in ''Main.pas'','#13#10'  Kunden.Daten in ''Kunden.Daten.pas'';',
    Host.WrittenFiles[1].Text) > 0, Host.WrittenFiles[1].Text);
  Assert.IsTrue(Parses(Host.WrittenFiles[1].Text), Host.WrittenFiles[1].Text);
  // .dproj: gültige DCCReference vor der ersten BuildConfiguration (das Projekt hat noch keine).
  Assert.IsTrue(Pos('    <ItemGroup>'#13#10'        <DCCReference Include="Kunden.Daten.pas"/>'#13#10 +
    '        <BuildConfiguration Include="Debug">', Host.WrittenFiles[2].Text) > 0, Host.WrittenFiles[2].Text);
end;

procedure TProjectCommandsTests.UnitWrongPlaceFails;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Host.Info.FileName := TPath.Combine(GetCurrentDir, 'App.dproj');
  // Kein gültiger Name, Datei schon vorhanden, Unit schon im Projekt, ohne Projekt.
  Assert.IsFalse(Run('/unit 1Daten', Keep, Edits));
  Host.Files.Add('Daten.pas', 'unit Daten;');
  Assert.IsFalse(Run('/unit Daten', Keep, Edits));
  Host.Info.Units := [Default(TProjectUnit)];
  Host.Info.Units[0].Name := 'Werkzeug';
  Assert.IsFalse(Run('/unit Werkzeug', Keep, Edits));
  Assert.IsFalse(Run('/unit Neu', nil, Edits));
  Assert.AreEqual(0, Integer(Length(Host.WrittenFiles)));
end;

procedure TProjectCommandsTests.OpenFindsInSearchPath;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Host.Info.SearchPaths := [TPath.Combine(GetCurrentDir, 'Common')];
  Host.Files.Add(TPath.Combine(TPath.Combine(GetCurrentDir, 'Common'), 'Werkzeug.pas'), 'unit Werkzeug;');
  Assert.IsTrue(Run('/open Werkzeug', Keep, Edits));
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.IsTrue(SameFile('Werkzeug.pas', Host.Shown), Host.Shown);
  Assert.AreEqual(0, Host.Selection.StartPos.Line);
  // Mit Namespace des Projekts: /open SysUtils findet System.SysUtils.
  Host.Shown := '';
  Host.Info.Namespaces := ['System'];
  Host.Files.Add(TPath.Combine(GetCurrentDir, 'System.SysUtils.pas'), 'unit System.SysUtils;');
  Assert.IsTrue(Run('/open SysUtils', Keep, Edits));
  Assert.IsTrue(SameFile('System.SysUtils.pas', Host.Shown), Host.Shown);
end;

procedure TProjectCommandsTests.OpenUnknownFails;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Problems: TArray<TSlashProblem>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Assert.IsFalse(Run('/open Fehlt', Keep, Edits));
  Assert.IsFalse(Run('/open', Keep, Edits));
  Assert.IsFalse(Run('/open Werkzeug', nil, Edits));
  Assert.AreEqual('', Host.Shown);
  // Stehen gebliebene Zeile: Hinweis statt Löschen.
  Problems := TSlashCommandRegistry.Shared.Problems(Format(FormUnit, ['/open Fehlt']), nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
end;

/// <summary>FormUnit mit ACommand und angewandten AEdits; von hinten, damit frühere Positionen gültig bleiben.</summary>
function Expanded(const ACommand: string; const AEdits: TArray<TRuleEdit>): string;
var
  Table: TLineTable;
  Index, Start, Stop: Integer;
begin
  Result := Format(FormUnit, [ACommand]);
  for Index := High(AEdits) downto 0 do
  begin
    Table := TLineTable.Build(Result);
    Start := Table.OffsetAt(AEdits[Index].Range.StartPos);
    Stop := Table.OffsetAt(AEdits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start) + AEdits[Index].NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

procedure TProjectCommandsTests.LogUsesConfiguredCall;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  // Ohne Einstellung: OutputDebugString.
  Assert.IsTrue(Run('/log', Keep, Edits));
  Text := Expanded('/log', Edits);
  Assert.IsTrue(Pos('  OutputDebugString(PChar(''Main.TForm1.Button1Click''));', Text) > 0, Text);
  // Routinenname: bekommt den Text als Argument.
  Host.LogCallValue := 'Log.Debug';
  Assert.IsTrue(Run('/log', Keep, Edits));
  Text := Expanded('/log', Edits);
  Assert.IsTrue(Pos('  Log.Debug(''Main.TForm1.Button1Click'');', Text) > 0, Text);
  // Vorlage mit {text}.
  Host.LogCallValue := 'Logger.Send(TLogLevel.Debug, {text});';
  Assert.IsTrue(Run('/log Start', Keep, Edits));
  Text := Expanded('/log Start', Edits);
  Assert.IsTrue(Pos('  Logger.Send(TLogLevel.Debug, ''Main.TForm1.Button1Click: Start'');', Text) > 0, Text);
end;

procedure TProjectCommandsTests.ExceptUsesConfiguredCall;
const
  Body = '/except'#10'  Close;';
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Text: string;
  Problems: TArray<TSlashProblem>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Host.LogCallValue := 'Log.Error';
  Assert.IsTrue(Run(Body, Keep, Edits));
  Text := Expanded(Body, Edits);
  Assert.IsTrue(Pos('      Log.Error(E.ClassName + '': '' + E.Message);'#10'      raise;', Text) > 0, Text);
  // Falscher Ort: außerhalb einer Routine bleibt die Zeile mit Hinweis stehen.
  Problems := TSlashCommandRegistry.Shared.Problems('unit U;'#10'interface'#10'/except'#10'implementation'#10 +
    'end.', nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
end;

const
  PackageText =
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
  Result := TSlashCommandRegistry.Shared.AfterEnter(Format(FormUnit, [ACommand]), TTextPosition.Create(10, 0), nil,
    nil, AEdits, AIndex, '', TDocumentUris.FromPath(TPath.Combine(GetCurrentDir, 'Main.pas')), AHost);
end;

procedure TProjectCommandsTests.ComponentGoesIntoPackage;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  Host.Info.FileName := TPath.Combine(GetCurrentDir, 'Paket.dproj');
  Host.Info.MainSource := TPath.Combine(GetCurrentDir, 'Paket.dpk');
  Host.Files.Add('Paket.dproj', Dproj);
  Host.Files.Add('Paket.dpk', PackageText);
  Host.PaletteValue := 'Firma';
  Assert.IsTrue(Run('/component TZaehler', Keep, Edits));
  Assert.AreEqual(3, Integer(Length(Host.WrittenFiles)));
  Text := Host.WrittenFiles[0].Text;
  Assert.IsTrue(SameFile('Zaehler.pas', Host.WrittenFiles[0].FileName), Host.WrittenFiles[0].FileName);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(Pos('  TZaehler = class(TComponent)', Text) > 0, Text);
  Assert.IsTrue(Pos('  published', Text) > 0, Text);
  Assert.IsTrue(Pos('RegisterComponents(''Firma'', [TZaehler]);', Text) > 0, Text);
  // In der .dpk unter contains, nicht unter requires.
  Assert.IsTrue(Pos('contains'#13#10'  Main in ''Main.pas'','#13#10'  Zaehler in ''Zaehler.pas'';',
    Host.WrittenFiles[1].Text) > 0, Host.WrittenFiles[1].Text);
  Assert.IsTrue(Pos('<DCCReference Include="Zaehler.pas"/>', Host.WrittenFiles[2].Text) > 0);
  Assert.AreEqual(Host.WrittenFiles[0].FileName, Host.ShowAfterWrite);
  // Ohne Einstellung: Palettenseite "Eigene".
  Host.PaletteValue := '';
  Assert.IsTrue(Run('/component TZaehler2', Keep, Edits));
  Assert.IsTrue(Pos('RegisterComponents(''Eigene'', [TZaehler2]);', Host.WrittenFiles[0].Text) > 0);
end;

procedure TProjectCommandsTests.ComponentAncestorFromIndex;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Index: ISymbolIndex;
  Text: string;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  // Ohne Projekt: nur die Unit, Vorfahr samt Unit aus dem Index.
  Host.Info.FileName := '';
  Host.Files.Remove('App.dproj');
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Vcl.StdCtrls;'#10'interface'#10'type'#10 +
    '  TButton = class(TObject)'#10'  end;'#10'implementation'#10'end.', 'C:\Lib\Vcl.StdCtrls.pas', nil));
  Assert.IsTrue(RunWithIndex('/component TMyButton : TButton', Keep, Index, Edits));
  Assert.AreEqual(1, Integer(Length(Host.WrittenFiles)));
  Text := Host.WrittenFiles[0].Text;
  Assert.IsTrue(Pos('  System.SysUtils, System.Classes, Vcl.StdCtrls;', Text) > 0, Text);
  Assert.IsTrue(Pos('  TMyButton = class(TButton)', Text) > 0, Text);
  Assert.IsTrue(SameFile('MyButton.pas', Host.WrittenFiles[0].FileName), Host.WrittenFiles[0].FileName);
end;

procedure TProjectCommandsTests.ComponentWrongPlaceFails;
var
  Host: TFakeHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Problems: TArray<TSlashProblem>;
begin
  Host := TFakeHost.Create;
  Keep := Host;
  // Kein Name, unbekannter Vorfahr, ohne Editor.
  Assert.IsFalse(Run('/component', Keep, Edits));
  Assert.IsFalse(Run('/component TA : TUnbekannt', Keep, Edits));
  Assert.IsFalse(Run('/component TA', nil, Edits));
  Assert.AreEqual(0, Integer(Length(Host.WrittenFiles)));
  Problems := TSlashCommandRegistry.Shared.Problems(Format(FormUnit, ['/component TA : TUnbekannt']), nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectCommandsTests);

end.
