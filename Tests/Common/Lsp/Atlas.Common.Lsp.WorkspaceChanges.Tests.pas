unit Atlas.Common.Lsp.WorkspaceChanges.Tests;

// Gemeinsamer Baustein der Umbauten mit mehreren Dateien (#103, #664):
// Zusammenfassen je Datei, neue Dateien, Eintrag ins Projekt (.dpr und
// .dproj, ohne Projekt nur ein Hinweis) und das WorkspaceEdit samt
// Änderungsanmerkung, gelöschte Dateien (#716).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Lsp.WorkspaceChanges;

type
  [TestFixture]
  TWorkspaceChangesTests = class
  public
    [Test]
    procedure MergesEditsOfSameFile;
    [Test]
    procedure IgnoresEmptyEdits;
    [Test]
    procedure RegisterWithoutProjectWarns;
    [Test]
    procedure RegisterAddsProgramAndProject;
    [Test]
    procedure RegisterSkipsKnownReference;
    [Test]
    procedure JsonCreatesFilesFirstWithAnnotation;
    [Test]
    procedure JsonWithoutAnnotation;
    [Test]
    procedure JsonDeletesFilesLast;
  end;

implementation

uses
  Atlas.Common.Lsp.References,
  Atlas.Common.Editing.ChangeSignature;

const
  ProgramFile = 'C:\P\Projekt.dpr';
  ProjectFile = 'C:\P\Projekt.dproj';
  NewFile = 'C:\P\Kunden.Schnittstellen.pas';
  TextProgram =
    'program Projekt;'#10'uses'#10'  Lager in ''Lager.pas'';'#10'begin'#10'end.'#10;
  TextProject =
    '<Project>'#10'  <ItemGroup>'#10'    <DelphiCompile Include="Projekt.dpr"/>'#10 +
    '    <DCCReference Include="Lager.pas"/>'#10'  </ItemGroup>'#10'</Project>'#10;

function Edit(ALine: Integer; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0), AText);
end;

function Project: TProjectInfo;
begin
  Result := Default(TProjectInfo);
  Result.FileName := ProjectFile;
  Result.MainSource := ProgramFile;
end;

function Reader(const AProjectText: string): TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, ProgramFile) then
        AText := TextProgram
      else if SameText(AFileName, ProjectFile) then
        AText := AProjectText
      else
        Result := False;
    end;
end;

procedure TWorkspaceChangesTests.MergesEditsOfSameFile;
var
  Changes: TWorkspaceChanges;
begin
  Changes := TWorkspaceChanges.Create;
  try
    Changes.Add('C:\P\A.pas', [Edit(1, 'x')]);
    Changes.Add('c:\p\a.pas', [Edit(2, 'y'), Edit(3, 'z')]);
    Changes.Add('C:\P\B.pas', [Edit(0, 'b')]);
    Changes.CreateFile(NewFile, 'unit Neu;');
    Assert.AreEqual(2, Integer(Length(Changes.Files)));
    Assert.AreEqual(3, Integer(Length(Changes.EditsOf('C:\P\A.pas'))));
    Assert.AreEqual(0, Integer(Length(Changes.EditsOf('C:\P\C.pas'))));
    Assert.AreEqual(5, Changes.EditCount);
    Assert.AreEqual(3, Changes.FileCount);
  finally
    Changes.Free;
  end;
end;

procedure TWorkspaceChangesTests.IgnoresEmptyEdits;
var
  Changes: TWorkspaceChanges;
begin
  Changes := TWorkspaceChanges.Create;
  try
    Changes.Add('C:\P\A.pas', nil);
    Assert.AreEqual(0, Changes.FileCount);
    Assert.AreEqual(0, Changes.EditCount);
  finally
    Changes.Free;
  end;
end;

procedure TWorkspaceChangesTests.RegisterWithoutProjectWarns;
var
  Changes: TWorkspaceChanges;
begin
  Changes := TWorkspaceChanges.Create;
  try
    Changes.RegisterUnit(False, Default(TProjectInfo), nil, NewFile, 'Kunden.Schnittstellen');
    Assert.AreEqual(0, Changes.FileCount);
    Assert.AreEqual(1, Integer(Length(Changes.Warnings)));
    Assert.Contains(Changes.Warnings[0], 'Kein Projekt');
  finally
    Changes.Free;
  end;
end;

procedure TWorkspaceChangesTests.RegisterAddsProgramAndProject;
var
  Changes: TWorkspaceChanges;
begin
  Changes := TWorkspaceChanges.Create;
  try
    Changes.RegisterUnit(True, Project, Reader(TextProject), NewFile, 'Kunden.Schnittstellen');
    Assert.AreEqual(0, Integer(Length(Changes.Warnings)));
    Assert.AreEqual(2, Changes.FileCount);
    Assert.Contains(TChangeSignature.ApplyEdits(TextProgram, Changes.EditsOf(ProgramFile)),
      'Kunden.Schnittstellen in ''Kunden.Schnittstellen.pas''');
    Assert.Contains(TChangeSignature.ApplyEdits(TextProject, Changes.EditsOf(ProjectFile)),
      '<DCCReference Include="Kunden.Schnittstellen.pas"/>');
  finally
    Changes.Free;
  end;
end;

procedure TWorkspaceChangesTests.RegisterSkipsKnownReference;
var
  Changes: TWorkspaceChanges;
begin
  Changes := TWorkspaceChanges.Create;
  try
    Changes.RegisterUnit(True, Project,
      Reader(StringReplace(TextProject, 'Lager.pas', 'Kunden.Schnittstellen.pas', [])), NewFile,
      'Kunden.Schnittstellen');
    Assert.AreEqual(1, Changes.FileCount);
    Assert.AreEqual(0, Integer(Length(Changes.EditsOf(ProjectFile))));
  finally
    Changes.Free;
  end;
end;

procedure TWorkspaceChangesTests.JsonCreatesFilesFirstWithAnnotation;
var
  Changes: TWorkspaceChanges;
  Json, First, Annotation: TJSONObject;
  List: TJSONArray;
begin
  Changes := TWorkspaceChanges.Create;
  Json := nil;
  try
    Changes.Add('C:\P\A.pas', [Edit(1, 'x')]);
    Changes.CreateFile(NewFile, 'unit Neu;');
    Json := Changes.ToJson('probe', 'Probe', 'Beschreibung');
    List := Json.GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual(3, Integer(List.Count));
    First := List.Items[0] as TJSONObject;
    Assert.AreEqual('create', First.GetValue('kind').Value);
    Assert.AreEqual('probe', First.GetValue('annotationId').Value);
    Assert.AreEqual('unit Neu;', (((List.Items[1] as TJSONObject).GetValue('edits') as TJSONArray).Items[0] as
      TJSONObject).GetValue('newText').Value);
    Annotation := (Json.GetValue('changeAnnotations') as TJSONObject).GetValue('probe') as TJSONObject;
    Assert.AreEqual('Probe', Annotation.GetValue('label').Value);
    Assert.IsTrue((Annotation.GetValue('needsConfirmation') as TJSONBool).AsBoolean);
  finally
    Json.Free;
    Changes.Free;
  end;
end;

procedure TWorkspaceChangesTests.JsonWithoutAnnotation;
var
  Changes: TWorkspaceChanges;
  Json, Item: TJSONObject;
  Warnings: TJSONArray;
begin
  Changes := TWorkspaceChanges.Create;
  Json := nil;
  Warnings := nil;
  try
    Changes.Add('C:\P\A.pas', [Edit(1, 'x')]);
    Changes.Warn('Hinweis');
    Json := Changes.ToJson;
    Assert.IsNull(Json.GetValue('changeAnnotations'));
    Item := ((((Json.GetValue('documentChanges') as TJSONArray).Items[0] as TJSONObject).GetValue('edits') as
      TJSONArray).Items[0]) as TJSONObject;
    Assert.IsNull(Item.GetValue('annotationId'));
    Warnings := Changes.WarningsJson;
    Assert.AreEqual(1, Integer(Warnings.Count));
  finally
    Warnings.Free;
    Json.Free;
    Changes.Free;
  end;
end;

procedure TWorkspaceChangesTests.JsonDeletesFilesLast;
var
  Changes: TWorkspaceChanges;
  Json, Item: TJSONObject;
  Items: TJSONArray;
begin
  Changes := TWorkspaceChanges.Create;
  Json := nil;
  try
    Changes.DeleteFile('C:\P\Alt.pas');
    Changes.Add('C:\P\A.pas', [Edit(1, 'x')]);
    Assert.AreEqual(2, Changes.FileCount);
    Assert.AreEqual(2, Changes.EditCount);
    Assert.AreEqual(1, Integer(Length(Changes.Deleted)));
    Json := Changes.ToJson('safeDelete', 'Sicher loeschen', '1 Datei');
    Items := Json.GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual(2, Integer(Items.Count));
    Item := Items.Items[1] as TJSONObject;
    Assert.AreEqual('delete', Item.GetValue('kind').Value);
    Assert.IsTrue(Item.GetValue('uri').Value.EndsWith('Alt.pas'));
    Assert.AreEqual('safeDelete', Item.GetValue('annotationId').Value);
    Assert.IsTrue(((Item.GetValue('options') as TJSONObject).GetValue('ignoreIfNotExists') as TJSONBool).AsBoolean);
  finally
    Json.Free;
    Changes.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TWorkspaceChangesTests);

end.
