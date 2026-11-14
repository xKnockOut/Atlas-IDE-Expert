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
  mText: string;
begin
  AContent := Default(TAtlasTextFileContent);
  Result := FFiles.TryGetValue(LowerCase(AFileName), mText);
  if not Result then
  begin
    Exit;
  end;
  AContent.Text := mText;
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
  begin
    Result := '';
  end;
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
  mEnvironment: IAtlasEditEnvironment;
begin
  mEnvironment := AEnvironment;
  Result := TAtlasEditPlanner.Plan(AEdit, mEnvironment);
end;

procedure TWorkspacePlanTests.CreateThenEditGoesIntoContent;
var
  mPlanned: TAtlasEditPlan;
begin
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\P\Neu.pas')],
    [FileEdits('C:\P\Neu.pas', [Insert(0, 0, 'unit Neu;')])]), TFakeEnvironment.Create);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(1, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual('unit Neu;', mPlanned.Creates[0].Content.Text);
  Assert.AreEqual<TAtlasFileChangeKind>(TAtlasFileChangeKind.Created, mPlanned.Creates[0].Kind);
  Assert.AreEqual(1, mPlanned.CreatedEdits);
  Assert.AreEqual(0, Integer(Length(mPlanned.Files)));
end;

procedure TWorkspacePlanTests.CreateExistingFailsWithoutFlags;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\P\Alt.pas')], nil), mEnvironment);
  Assert.AreEqual('Alt.pas: Alt.pas existiert bereits', mPlanned.Error);
end;

procedure TWorkspacePlanTests.CreateExistingIgnoreIfExistsSkips;
var
  mEnvironment: TFakeEnvironment;
  mChange: TLspFileOperation;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  mChange := Operation(TLspFileOperationKind.Create, 'C:\P\Alt.pas');
  mChange.IgnoreIfExists := True;
  mPlanned := Plan(Edit([mChange], nil), mEnvironment);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(0, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual(0, Integer(Length(mPlanned.Files)));
end;

procedure TWorkspacePlanTests.CreateExistingOverwriteReplaces;
var
  mEnvironment: TFakeEnvironment;
  mChange: TLspFileOperation;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  mChange := Operation(TLspFileOperationKind.Create, 'C:\P\Alt.pas');
  mChange.Overwrite := True;
  mPlanned := Plan(Edit([mChange], [FileEdits('C:\P\Alt.pas', [Insert(0, 0, 'neu')])]), mEnvironment);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(0, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual(1, Integer(Length(mPlanned.Files)));
  Assert.IsTrue(mPlanned.Files[0].HasBase);
  Assert.AreEqual('', mPlanned.Files[0].Base);
  Assert.AreEqual(1, Integer(Length(mPlanned.Files[0].Edits)));
end;

procedure TWorkspacePlanTests.RenameMovesContentEncodingAndProject;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFile('C:\P\Alt.pas', 'unit Alt;', 'C:\P\P.dproj');
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Rename, 'C:\P\Alt.pas', 'C:\P\Neu.pas')], nil), mEnvironment);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(1, Integer(Length(mPlanned.Removes)));
  Assert.AreEqual('C:\P\Alt.pas', mPlanned.Removes[0].FileName);
  Assert.AreEqual('C:\P\P.dproj', mPlanned.Removes[0].Project);
  Assert.AreEqual('unit Alt;', mPlanned.Removes[0].Content.Text);
  Assert.AreEqual(1, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual('C:\P\Neu.pas', mPlanned.Creates[0].FileName);
  Assert.AreEqual('C:\P\P.dproj', mPlanned.Creates[0].Project);
  Assert.AreEqual('unit Alt;', mPlanned.Creates[0].Content.Text);
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Ansi, mPlanned.Creates[0].Content.Encoding);
  Assert.AreEqual(1252, mPlanned.Creates[0].Content.CodePage);
end;

procedure TWorkspacePlanTests.RenameToSameNameIsNoop;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Rename, 'C:\P\Alt.pas', 'c:\p\ALT.pas')], nil), mEnvironment);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(0, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual(0, Integer(Length(mPlanned.Removes)));
end;

procedure TWorkspacePlanTests.RenameOfCreatedFileKeepsCreate;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.ActiveProject := 'C:\P\P.dproj';
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\P\A.pas'),
    Operation(TLspFileOperationKind.Rename, 'C:\P\A.pas', 'C:\P\B.pas')],
    [FileEdits('C:\P\B.pas', [Insert(0, 0, 'unit B;')])]), mEnvironment);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(1, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual('C:\P\B.pas', mPlanned.Creates[0].FileName);
  Assert.AreEqual('C:\P\P.dproj', mPlanned.Creates[0].Project);
  Assert.AreEqual('unit B;', mPlanned.Creates[0].Content.Text);
  Assert.AreEqual(0, Integer(Length(mPlanned.Removes)));
end;

procedure TWorkspacePlanTests.DeleteOfCreatedFileDropsCreate;
var
  mPlanned: TAtlasEditPlan;
begin
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\P\A.pas'),
    Operation(TLspFileOperationKind.Delete, 'C:\P\A.pas')], nil), TFakeEnvironment.Create);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(0, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual(0, Integer(Length(mPlanned.Removes)));
end;

procedure TWorkspacePlanTests.DeleteMissingFails;
var
  mPlanned: TAtlasEditPlan;
begin
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Delete, 'C:\P\Weg.pas')], nil), TFakeEnvironment.Create);
  Assert.AreEqual('Weg.pas: Datei nicht gefunden', mPlanned.Error);
end;

procedure TWorkspacePlanTests.DeleteMissingIgnoreIfNotExists;
var
  mChange: TLspFileOperation;
  mPlanned: TAtlasEditPlan;
begin
  mChange := Operation(TLspFileOperationKind.Delete, 'C:\P\Weg.pas');
  mChange.IgnoreIfNotExists := True;
  mPlanned := Plan(Edit([mChange], nil), TFakeEnvironment.Create);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(0, Integer(Length(mPlanned.Removes)));
end;

procedure TWorkspacePlanTests.DeleteFolderFails;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFolder('C:\P\Ordner');
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Delete, 'C:\P\Ordner')], nil), mEnvironment);
  Assert.AreEqual('Ordner: Ordner löscht Atlas nicht', mPlanned.Error);
end;

procedure TWorkspacePlanTests.EditOnDeletedFileFails;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Delete, 'C:\P\Alt.pas')],
    [FileEdits('C:\P\Alt.pas', [Insert(0, 0, 'x')])]), mEnvironment);
  Assert.AreEqual('Alt.pas: wird gelöscht', mPlanned.Error);
end;

procedure TWorkspacePlanTests.RemoveThenCreateRevivesAsReplace;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFile('C:\P\Alt.pas', 'unit Alt;');
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Delete, 'C:\P\Alt.pas'),
    Operation(TLspFileOperationKind.Create, 'C:\P\Alt.pas')],
    [FileEdits('C:\P\Alt.pas', [Insert(0, 0, 'unit Neu;')])]), mEnvironment);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(0, Integer(Length(mPlanned.Removes)));
  Assert.AreEqual(0, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual(1, Integer(Length(mPlanned.Files)));
  Assert.IsTrue(mPlanned.Files[0].HasBase);
  Assert.AreEqual('', mPlanned.Files[0].Base);
end;

procedure TWorkspacePlanTests.ReplacedFileWithoutEditsGetsEntry;
var
  mEnvironment: TFakeEnvironment;
  mChange: TLspFileOperation;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.AddFile('C:\P\A.pas', 'unit A;');
  mEnvironment.AddFile('C:\P\B.pas', 'unit B;');
  mChange := Operation(TLspFileOperationKind.Rename, 'C:\P\A.pas', 'C:\P\B.pas');
  mChange.Overwrite := True;
  mPlanned := Plan(Edit([mChange], nil), mEnvironment);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(1, Integer(Length(mPlanned.Files)));
  Assert.AreEqual('C:\P\B.pas', mPlanned.Files[0].FileName);
  Assert.IsTrue(mPlanned.Files[0].HasBase);
  Assert.AreEqual('unit A;', mPlanned.Files[0].Base);
  Assert.AreEqual(0, Integer(Length(mPlanned.Files[0].Edits)));
  Assert.AreEqual(1, Integer(Length(mPlanned.Removes)));
end;

procedure TWorkspacePlanTests.NewUnitGoesIntoLoadedOwnerProject;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.ActiveProject := 'C:\Aktiv\Aktiv.dproj';
  mEnvironment.AddFile('C:\T\Tests.dproj', '<Project/>');
  mEnvironment.AddFile('C:\T\Tests.dpr', 'program Tests;');
  mEnvironment.AddLoadedProject('C:\T\Tests.dproj');
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\T\Neu.Tests.pas')],
    [FileEdits('C:\T\Tests.dproj', [Insert(0, 0, 'x')]), FileEdits('C:\T\Tests.dpr', [Insert(0, 0, 'y')])]),
    mEnvironment);
  Assert.AreEqual('', mPlanned.Error);
  Assert.AreEqual(1, Integer(Length(mPlanned.Creates)));
  Assert.AreEqual('C:\T\Tests.dproj', mPlanned.Creates[0].Project);
  // Die IDE trägt die Unit selbst ein: Änderungen an .dproj und .dpr entfallen.
  Assert.AreEqual(0, Integer(Length(mPlanned.Files)));
  Assert.AreEqual(0, Integer(Length(mPlanned.Edit.Files)));
end;

procedure TWorkspacePlanTests.NewFileUsesActiveProjectWithoutOwner;
var
  mEnvironment: TFakeEnvironment;
  mPlanned: TAtlasEditPlan;
begin
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.ActiveProject := 'C:\Aktiv\Aktiv.dproj';
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\Aktiv\Neu.pas')], nil), mEnvironment);
  Assert.AreEqual('C:\Aktiv\Aktiv.dproj', mPlanned.Creates[0].Project);
  // Owner nicht geladen: Änderungen am Projekt bleiben, die neue Unit kommt in kein Projekt.
  mEnvironment := TFakeEnvironment.Create;
  mEnvironment.ActiveProject := 'C:\Aktiv\Aktiv.dproj';
  mEnvironment.AddFile('C:\T\Tests.dproj', '<Project/>');
  mPlanned := Plan(Edit([Operation(TLspFileOperationKind.Create, 'C:\T\Neu.Tests.pas')],
    [FileEdits('C:\T\Tests.dproj', [Insert(0, 0, 'x')])]), mEnvironment);
  Assert.AreEqual('', mPlanned.Creates[0].Project);
  Assert.AreEqual(1, Integer(Length(mPlanned.Files)));
  Assert.IsFalse(mPlanned.Files[0].HasBase);
end;

procedure TWorkspacePlanTests.PolicyFromSetting;
begin
  Assert.AreEqual<TAtlasUnopenedPolicy>(TAtlasUnopenedPolicy.OpenInEditor, TAtlasUnopenedPolicies.FromSetting(True));
  Assert.AreEqual<TAtlasUnopenedPolicy>(TAtlasUnopenedPolicy.WriteToDisk, TAtlasUnopenedPolicies.FromSetting(False));
end;

initialization
  TDUnitX.RegisterTestFixture(TWorkspacePlanTests);

end.
