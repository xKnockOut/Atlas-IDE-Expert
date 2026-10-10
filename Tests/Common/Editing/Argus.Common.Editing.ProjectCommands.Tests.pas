unit Argus.Common.Editing.ProjectCommands.Tests;

// Tests für die Schnellbefehle /define, /searchpath, /config und /dfm (#301)
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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Argus.Common.Documents.Contract,
  Argus.Common.Documents.Uris,
  Argus.Common.Projects.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Editing.SlashCommands;

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
    constructor Create;
    destructor Destroy; override;
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    procedure WriteProject(const AUri, AText: string);
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
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

initialization
  TDUnitX.RegisterTestFixture(TProjectCommandsTests);

end.
