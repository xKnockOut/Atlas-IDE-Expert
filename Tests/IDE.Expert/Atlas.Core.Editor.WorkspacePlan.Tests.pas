unit Atlas.Core.Editor.WorkspacePlan.Tests;

// Planung von WorkspaceEdits ohne IDE (S-03b, #397, #721, #274): Dateioperationen, neue Dateien,
// ersetzte Ziele und die Fehlerpfade. Die Umgebung ist ein Fake mit Dateien im Speicher.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWorkspacePlanTests = class
  public
    [Test]
    procedure CreateThenEditGoesIntoContent;
    [Test]
    procedure CreateExistingFailsWithoutFlags;
    [Test]
    procedure CreateExistingIgnoreIfExistsSkips;
    [Test]
    procedure CreateExistingOverwriteReplaces;
    [Test]
    procedure RenameMovesContentEncodingAndProject;
    [Test]
    procedure RenameToSameNameIsNoop;
    [Test]
    procedure RenameOfCreatedFileKeepsCreate;
    [Test]
    procedure DeleteOfCreatedFileDropsCreate;
    [Test]
    procedure DeleteMissingFails;
    [Test]
    procedure DeleteMissingIgnoreIfNotExists;
    [Test]
    procedure DeleteFolderFails;
    [Test]
    procedure EditOnDeletedFileFails;
    [Test]
    procedure RemoveThenCreateRevivesAsReplace;
    [Test]
    procedure ReplacedFileWithoutEditsGetsEntry;
    [Test]
    procedure NewUnitGoesIntoLoadedOwnerProject;
    [Test]
    procedure NewFileUsesActiveProjectWithoutOwner;
    [Test]
    procedure PolicyFromSetting;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Editor.WorkspacePlan;

type
  TFakeEnvironment = class(TInterfacedObject, IAtlasEditEnvironment)
  private
    FFiles: TDictionary<string, string>;
    FProjects: TDictionary<string, string>;
    FLoaded: TList<string>;
    FFolders: TList<string>;
  public
    ActiveProject: string;
    constructor Create;
    destructor Destroy; override;
    procedure AddFile(const AFileName, AText: string); overload;
    procedure AddFile(const AFileName, AText, AProject: string); overload;
    procedure AddFolder(const AFolder: string);
    procedure AddLoadedProject(const AProjectFile: string);
    function Exists(const AFileName: string): Boolean;
    function IsDirectory(const AFileName: string): Boolean;
    function Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
    function DiskEncoding(const AFileName: string): TAtlasTextFileContent;
    function ProjectOfFile(const AFileName: string): string;
    function ProjectForNewFile(const AFileName: string): string;
    function ProjectLoaded(const AProjectFile: string): Boolean;
  end;

constructor TFakeEnvironment.Create;
begin
  inherited Create;
  FFiles := TDictionary<string, string>.Create;
  FProjects := TDictionary<string, string>.Create;
  FLoaded := TList<string>.Create;
  FFolders := TList<string>.Create;
end;

destructor TFakeEnvironment.Destroy;
begin
  FFolders.Free;
  FLoaded.Free;
  FProjects.Free;
  FFiles.Free;
  inherited;
end;

procedure TFakeEnvironment.AddFile(const AFileName, AText: string);
begin
  FFiles.AddOrSetValue(LowerCase(AFileName), AText);
end;

procedure TFakeEnvironment.AddFile(const AFileName, AText, AProject: string);
begin
  AddFile(AFileName, AText);
  FProjects.AddOrSetValue(LowerCase(AFileName), AProject);
end;

procedure TFakeEnvironment.AddFolder(const AFolder: string);
begin
  FFolders.Add(LowerCase(AFolder));
end;

procedure TFakeEnvironment.AddLoadedProject(const AProjectFile: string);
begin
  FLoaded.Add(LowerCase(AProjectFile));
end;

function TFakeEnvironment.Exists(const AFileName: string): Boolean;
begin
  Result := FFiles.ContainsKey(LowerCase(AFileName));
end;

function TFakeEnvironment.IsDirectory(const AFileName: string): Boolean;
begin
  Result := FFolders.Contains(LowerCase(AFileName));
end;

function TFakeEnvironment.Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
var
  Text: string;
begin
  AContent := Default(TAtlasTextFileContent);
  Result := FFiles.TryGetValue(LowerCase(AFileName), Text);
  if not Result then
    Exit;
  AContent.Text := Text;
  // Kennzeichen, dass die Kodierung der Quelle mitwandert.
  AContent.Encoding := TAtlasTextEncoding.Ansi;
  AContent.CodePage := 1252;
end;

function TFakeEnvironment.DiskEncoding(const AFileName: string): TAtlasTextFileContent;
begin
  Result := Default(TAtlasTextFileContent);
  Result.Encoding := TAtlasTextEncoding.Utf8Bom;
end;

function TFakeEnvironment.ProjectOfFile(const AFileName: string): string;
begin
  if not FProjects.TryGetValue(LowerCase(AFileName), Result) then
    Result := '';
end;

function TFakeEnvironment.ProjectForNewFile(const AFileName: string): string;
begin
  Result := ActiveProject;
end;

function TFakeEnvironment.ProjectLoaded(const AProjectFile: string): Boolean;
begin
  Result := FLoaded.Contains(LowerCase(AProjectFile));
end;

function Insert(ALine, ACharacter: Integer; const AText: string): TLspTextEdit;
begin
  Result := Default(TLspTextEdit);
  Result.StartPos := TLspTextPosition.Create(ALine, ACharacter);
  Result.EndPos := Result.StartPos;
  Result.NewText := AText;
end;

function FileEdits(const AFileName: string; const AEdits: TArray<TLspTextEdit>): TLspFileEdits;
begin
  Result := Default(TLspFileEdits);
  Result.FileName := AFileName;
  Result.Edits := AEdits;
end;

function Operation(AKind: TLspFileOperationKind; const AFileName: string): TLspFileOperation; overload;
begin
  Result := Default(TLspFileOperation);
  Result.Kind := AKind;
  Result.FileName := AFileName;
end;

function Operation(AKind: TLspFileOperationKind; const AFileName, ANewFileName: string): TLspFileOperation; overload;
begin
  Result := Operation(AKind, AFileName);
  Result.NewFileName := ANewFileName;
end;

function Edit(const AOperations: TArray<TLspFileOperation>; const AFiles: TArray<TLspFileEdits>): TLspWorkspaceEdit;
begin
  Result := Default(TLspWorkspaceEdit);
  Result.Operations := AOperations;
  Result.Files := AFiles;
end;

function Plan(const AEdit: TLspWorkspaceEdit; AEnvironment: TFakeEnvironment): TAtlasEditPlan;
var
  Environment: IAtlasEditEnvironment;
begin
  Environment := AEnvironment;
  Result := TAtlasEditPlanner.Plan(AEdit, Environment);
end;

procedure TWorkspacePlanTests.CreateThenEditGoesIntoContent;
var
  Planned: TAtlasEditPlan;
begin
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\P\Neu.pas')],
    [FileEdits('C:\P\Neu.pas', [Insert(0, 0, 'unit Neu;')])]), TFakeEnvironment.Create);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(1, Integer(Length(Planned.Creates)));
  Assert.AreEqual('unit Neu;', Planned.Creates[0].Content.Text);
  Assert.IsTrue(Planned.Creates[0].Kind = TAtlasFileChangeKind.Created);
  Assert.AreEqual(1, Planned.CreatedEdits);
  Assert.AreEqual(0, Integer(Length(Planned.Files)));
end;

procedure TWorkspacePlanTests.CreateExistingFailsWithoutFlags;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\P\Alt.pas')], nil), Environment);
  Assert.AreEqual('Alt.pas: Alt.pas existiert bereits', Planned.Error);
end;

procedure TWorkspacePlanTests.CreateExistingIgnoreIfExistsSkips;
var
  Environment: TFakeEnvironment;
  Change: TLspFileOperation;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  Change := Operation(TLspFileOperationKind.Create, 'C:\P\Alt.pas');
  Change.IgnoreIfExists := True;
  Planned := Plan(Edit([Change], nil), Environment);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(0, Integer(Length(Planned.Creates)));
  Assert.AreEqual(0, Integer(Length(Planned.Files)));
end;

procedure TWorkspacePlanTests.CreateExistingOverwriteReplaces;
var
  Environment: TFakeEnvironment;
  Change: TLspFileOperation;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  Change := Operation(TLspFileOperationKind.Create, 'C:\P\Alt.pas');
  Change.Overwrite := True;
  Planned := Plan(Edit([Change], [FileEdits('C:\P\Alt.pas', [Insert(0, 0, 'neu')])]), Environment);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(0, Integer(Length(Planned.Creates)));
  Assert.AreEqual(1, Integer(Length(Planned.Files)));
  Assert.IsTrue(Planned.Files[0].HasBase);
  Assert.AreEqual('', Planned.Files[0].Base);
  Assert.AreEqual(1, Integer(Length(Planned.Files[0].Edits)));
end;

procedure TWorkspacePlanTests.RenameMovesContentEncodingAndProject;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFile('C:\P\Alt.pas', 'unit Alt;', 'C:\P\P.dproj');
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Rename, 'C:\P\Alt.pas', 'C:\P\Neu.pas')], nil), Environment);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(1, Integer(Length(Planned.Removes)));
  Assert.AreEqual('C:\P\Alt.pas', Planned.Removes[0].FileName);
  Assert.AreEqual('C:\P\P.dproj', Planned.Removes[0].Project);
  Assert.AreEqual('unit Alt;', Planned.Removes[0].Content.Text);
  Assert.AreEqual(1, Integer(Length(Planned.Creates)));
  Assert.AreEqual('C:\P\Neu.pas', Planned.Creates[0].FileName);
  Assert.AreEqual('C:\P\P.dproj', Planned.Creates[0].Project);
  Assert.AreEqual('unit Alt;', Planned.Creates[0].Content.Text);
  Assert.IsTrue(Planned.Creates[0].Content.Encoding = TAtlasTextEncoding.Ansi);
  Assert.AreEqual(1252, Planned.Creates[0].Content.CodePage);
end;

procedure TWorkspacePlanTests.RenameToSameNameIsNoop;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Rename, 'C:\P\Alt.pas', 'c:\p\ALT.pas')], nil), Environment);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(0, Integer(Length(Planned.Creates)));
  Assert.AreEqual(0, Integer(Length(Planned.Removes)));
end;

procedure TWorkspacePlanTests.RenameOfCreatedFileKeepsCreate;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.ActiveProject := 'C:\P\P.dproj';
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\P\A.pas'),
    Operation(TLspFileOperationKind.Rename, 'C:\P\A.pas', 'C:\P\B.pas')],
    [FileEdits('C:\P\B.pas', [Insert(0, 0, 'unit B;')])]), Environment);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(1, Integer(Length(Planned.Creates)));
  Assert.AreEqual('C:\P\B.pas', Planned.Creates[0].FileName);
  Assert.AreEqual('C:\P\P.dproj', Planned.Creates[0].Project);
  Assert.AreEqual('unit B;', Planned.Creates[0].Content.Text);
  Assert.AreEqual(0, Integer(Length(Planned.Removes)));
end;

procedure TWorkspacePlanTests.DeleteOfCreatedFileDropsCreate;
var
  Planned: TAtlasEditPlan;
begin
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\P\A.pas'),
    Operation(TLspFileOperationKind.Delete, 'C:\P\A.pas')], nil), TFakeEnvironment.Create);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(0, Integer(Length(Planned.Creates)));
  Assert.AreEqual(0, Integer(Length(Planned.Removes)));
end;

procedure TWorkspacePlanTests.DeleteMissingFails;
var
  Planned: TAtlasEditPlan;
begin
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Delete, 'C:\P\Weg.pas')], nil), TFakeEnvironment.Create);
  Assert.AreEqual('Weg.pas: Datei nicht gefunden', Planned.Error);
end;

procedure TWorkspacePlanTests.DeleteMissingIgnoreIfNotExists;
var
  Change: TLspFileOperation;
  Planned: TAtlasEditPlan;
begin
  Change := Operation(TLspFileOperationKind.Delete, 'C:\P\Weg.pas');
  Change.IgnoreIfNotExists := True;
  Planned := Plan(Edit([Change], nil), TFakeEnvironment.Create);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(0, Integer(Length(Planned.Removes)));
end;

procedure TWorkspacePlanTests.DeleteFolderFails;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFolder('C:\P\Ordner');
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Delete, 'C:\P\Ordner')], nil), Environment);
  Assert.AreEqual('Ordner: Ordner löscht Atlas nicht', Planned.Error);
end;

procedure TWorkspacePlanTests.EditOnDeletedFileFails;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Delete, 'C:\P\Alt.pas')],
    [FileEdits('C:\P\Alt.pas', [Insert(0, 0, 'x')])]), Environment);
  Assert.AreEqual('Alt.pas: wird gelöscht', Planned.Error);
end;

procedure TWorkspacePlanTests.RemoveThenCreateRevivesAsReplace;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Delete, 'C:\P\Alt.pas'),
    Operation(TLspFileOperationKind.Create, 'C:\P\Alt.pas')],
    [FileEdits('C:\P\Alt.pas', [Insert(0, 0, 'unit Neu;')])]), Environment);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(0, Integer(Length(Planned.Removes)));
  Assert.AreEqual(0, Integer(Length(Planned.Creates)));
  Assert.AreEqual(1, Integer(Length(Planned.Files)));
  Assert.IsTrue(Planned.Files[0].HasBase);
  Assert.AreEqual('', Planned.Files[0].Base);
end;

procedure TWorkspacePlanTests.ReplacedFileWithoutEditsGetsEntry;
var
  Environment: TFakeEnvironment;
  Change: TLspFileOperation;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.AddFile('C:\P\A.pas', 'unit A;');
  Environment.AddFile('C:\P\B.pas', 'unit B;');
  Change := Operation(TLspFileOperationKind.Rename, 'C:\P\A.pas', 'C:\P\B.pas');
  Change.Overwrite := True;
  Planned := Plan(Edit([Change], nil), Environment);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(1, Integer(Length(Planned.Files)));
  Assert.AreEqual('C:\P\B.pas', Planned.Files[0].FileName);
  Assert.IsTrue(Planned.Files[0].HasBase);
  Assert.AreEqual('unit A;', Planned.Files[0].Base);
  Assert.AreEqual(0, Integer(Length(Planned.Files[0].Edits)));
  Assert.AreEqual(1, Integer(Length(Planned.Removes)));
end;

procedure TWorkspacePlanTests.NewUnitGoesIntoLoadedOwnerProject;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.ActiveProject := 'C:\Aktiv\Aktiv.dproj';
  Environment.AddFile('C:\T\Tests.dproj', '<Project/>');
  Environment.AddFile('C:\T\Tests.dpr', 'program Tests;');
  Environment.AddLoadedProject('C:\T\Tests.dproj');
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\T\Neu.Tests.pas')],
    [FileEdits('C:\T\Tests.dproj', [Insert(0, 0, 'x')]), FileEdits('C:\T\Tests.dpr', [Insert(0, 0, 'y')])]),
    Environment);
  Assert.AreEqual('', Planned.Error);
  Assert.AreEqual(1, Integer(Length(Planned.Creates)));
  Assert.AreEqual('C:\T\Tests.dproj', Planned.Creates[0].Project);
  // Die IDE trägt die Unit selbst ein: Änderungen an .dproj und .dpr entfallen.
  Assert.AreEqual(0, Integer(Length(Planned.Files)));
  Assert.AreEqual(0, Integer(Length(Planned.Edit.Files)));
end;

procedure TWorkspacePlanTests.NewFileUsesActiveProjectWithoutOwner;
var
  Environment: TFakeEnvironment;
  Planned: TAtlasEditPlan;
begin
  Environment := TFakeEnvironment.Create;
  Environment.ActiveProject := 'C:\Aktiv\Aktiv.dproj';
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\Aktiv\Neu.pas')], nil), Environment);
  Assert.AreEqual('C:\Aktiv\Aktiv.dproj', Planned.Creates[0].Project);
  // Owner nicht geladen: Änderungen am Projekt bleiben, die neue Unit kommt in kein Projekt.
  Environment := TFakeEnvironment.Create;
  Environment.ActiveProject := 'C:\Aktiv\Aktiv.dproj';
  Environment.AddFile('C:\T\Tests.dproj', '<Project/>');
  Planned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\T\Neu.Tests.pas')],
    [FileEdits('C:\T\Tests.dproj', [Insert(0, 0, 'x')])]), Environment);
  Assert.AreEqual('', Planned.Creates[0].Project);
  Assert.AreEqual(1, Integer(Length(Planned.Files)));
  Assert.IsFalse(Planned.Files[0].HasBase);
end;

procedure TWorkspacePlanTests.PolicyFromSetting;
begin
  Assert.IsTrue(TAtlasUnopenedPolicies.FromSetting(True) = TAtlasUnopenedPolicy.OpenInEditor);
  Assert.IsTrue(TAtlasUnopenedPolicies.FromSetting(False) = TAtlasUnopenedPolicy.WriteToDisk);
end;

initialization
  TDUnitX.RegisterTestFixture(TWorkspacePlanTests);

end.
