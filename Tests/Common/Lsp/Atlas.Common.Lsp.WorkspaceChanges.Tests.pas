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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Editing.ChangeSignature;

const
  cProgramFile = 'C:\P\Projekt.dpr';
  cProjectFile = 'C:\P\Projekt.dproj';
  cNewFile = 'C:\P\Kunden.Schnittstellen.pas';
  cTextProgram =
    'program Projekt;'#10'uses'#10'  Lager in ''Lager.pas'';'#10'begin'#10'end.'#10;
  cTextProject =
    '<Project>'#10'  <ItemGroup>'#10'    <DelphiCompile Include="Projekt.dpr"/>'#10 +
    '    <DCCReference Include="Lager.pas"/>'#10'  </ItemGroup>'#10'</Project>'#10;

function Edit(ALine: Integer; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0), AText);
end;

function Project: TProjectInfo;
begin
  Result := Default(TProjectInfo);
  Result.FileName := cProjectFile;
  Result.MainSource := cProgramFile;
end;

function Reader(const AProjectText: string): TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, cProgramFile) then
      begin
        AText := cTextProgram;
      end
      else if SameText(AFileName, cProjectFile) then
      begin
        AText := AProjectText;
      end
      else
      begin
        Result := False;
      end;
    end;
end;

procedure TWorkspaceChangesTests.MergesEditsOfSameFile;
var
  mChanges: TWorkspaceChanges;
begin
  mChanges := TWorkspaceChanges.Create;
  try
    mChanges.Add('C:\P\A.pas', [Edit(1, 'x')]);
    mChanges.Add('c:\p\a.pas', [Edit(2, 'y'), Edit(3, 'z')]);
    mChanges.Add('C:\P\B.pas', [Edit(0, 'b')]);
    mChanges.CreateFile(cNewFile, 'unit Neu;');
    Assert.AreEqual(2, Integer(Length(mChanges.Files)));
    Assert.AreEqual(3, Integer(Length(mChanges.EditsOf('C:\P\A.pas'))));
    Assert.AreEqual(0, Integer(Length(mChanges.EditsOf('C:\P\C.pas'))));
    Assert.AreEqual(5, mChanges.EditCount);
    Assert.AreEqual(3, mChanges.FileCount);
  finally
    mChanges.Free;
  end;
end;

procedure TWorkspaceChangesTests.IgnoresEmptyEdits;
var
  mChanges: TWorkspaceChanges;
begin
  mChanges := TWorkspaceChanges.Create;
  try
    mChanges.Add('C:\P\A.pas', nil);
    Assert.AreEqual(0, mChanges.FileCount);
    Assert.AreEqual(0, mChanges.EditCount);
  finally
    mChanges.Free;
  end;
end;

procedure TWorkspaceChangesTests.RegisterWithoutProjectWarns;
var
  mChanges: TWorkspaceChanges;
begin
  mChanges := TWorkspaceChanges.Create;
  try
    mChanges.RegisterUnit(False, Default(TProjectInfo), nil, cNewFile, 'Kunden.Schnittstellen');
    Assert.AreEqual(0, mChanges.FileCount);
    Assert.AreEqual(1, Integer(Length(mChanges.Warnings)));
    Assert.Contains(mChanges.Warnings[0], 'Kein Projekt');
  finally
    mChanges.Free;
  end;
end;

procedure TWorkspaceChangesTests.RegisterAddsProgramAndProject;
var
  mChanges: TWorkspaceChanges;
begin
  mChanges := TWorkspaceChanges.Create;
  try
    mChanges.RegisterUnit(True, Project, Reader(cTextProject), cNewFile, 'Kunden.Schnittstellen');
    Assert.AreEqual(0, Integer(Length(mChanges.Warnings)));
    Assert.AreEqual(2, mChanges.FileCount);
    Assert.Contains(TChangeSignature.ApplyEdits(cTextProgram, mChanges.EditsOf(cProgramFile)),
      'Kunden.Schnittstellen in ''Kunden.Schnittstellen.pas''');
    Assert.Contains(TChangeSignature.ApplyEdits(cTextProject, mChanges.EditsOf(cProjectFile)),
      '<DCCReference Include="Kunden.Schnittstellen.pas"/>');
  finally
    mChanges.Free;
  end;
end;

procedure TWorkspaceChangesTests.RegisterSkipsKnownReference;
var
  mChanges: TWorkspaceChanges;
begin
  mChanges := TWorkspaceChanges.Create;
  try
    mChanges.RegisterUnit(True, Project,
      Reader(StringReplace(cTextProject, 'Lager.pas', 'Kunden.Schnittstellen.pas', [])), cNewFile,
      'Kunden.Schnittstellen');
    Assert.AreEqual(1, mChanges.FileCount);
    Assert.AreEqual(0, Integer(Length(mChanges.EditsOf(cProjectFile))));
  finally
    mChanges.Free;
  end;
end;

procedure TWorkspaceChangesTests.JsonCreatesFilesFirstWithAnnotation;
var
  mChanges: TWorkspaceChanges;
  mJson, mFirst, mAnnotation: TJSONObject;
  mList: TJSONArray;
begin
  mChanges := TWorkspaceChanges.Create;
  mJson := nil;
  try
    mChanges.Add('C:\P\A.pas', [Edit(1, 'x')]);
    mChanges.CreateFile(cNewFile, 'unit Neu;');
    mJson := mChanges.ToJson('probe', 'Probe', 'Beschreibung');
    mList := mJson.GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual(3, Integer(mList.Count));
    mFirst := mList.Items[0] as TJSONObject;
    Assert.AreEqual('create', mFirst.GetValue('kind').Value);
    Assert.AreEqual('probe', mFirst.GetValue('annotationId').Value);
    Assert.AreEqual('unit Neu;', (((mList.Items[1] as TJSONObject).GetValue('edits') as TJSONArray).Items[0] as
      TJSONObject).GetValue('newText').Value);
    mAnnotation := (mJson.GetValue('changeAnnotations') as TJSONObject).GetValue('probe') as TJSONObject;
    Assert.AreEqual('Probe', mAnnotation.GetValue('label').Value);
    Assert.IsTrue((mAnnotation.GetValue('needsConfirmation') as TJSONBool).AsBoolean);
  finally
    mJson.Free;
    mChanges.Free;
  end;
end;

procedure TWorkspaceChangesTests.JsonWithoutAnnotation;
var
  mChanges: TWorkspaceChanges;
  mJson, mItem: TJSONObject;
  mWarnings: TJSONArray;
begin
  mChanges := TWorkspaceChanges.Create;
  mJson := nil;
  mWarnings := nil;
  try
    mChanges.Add('C:\P\A.pas', [Edit(1, 'x')]);
    mChanges.Warn('Hinweis');
    mJson := mChanges.ToJson;
    Assert.IsNull(mJson.GetValue('changeAnnotations'));
    mItem := ((((mJson.GetValue('documentChanges') as TJSONArray).Items[0] as TJSONObject).GetValue('edits') as
      TJSONArray).Items[0]) as TJSONObject;
    Assert.IsNull(mItem.GetValue('annotationId'));
    mWarnings := mChanges.WarningsJson;
    Assert.AreEqual(1, Integer(mWarnings.Count));
  finally
    mWarnings.Free;
    mJson.Free;
    mChanges.Free;
  end;
end;

procedure TWorkspaceChangesTests.JsonDeletesFilesLast;
var
  mChanges: TWorkspaceChanges;
  mJson, mItem: TJSONObject;
  mItems: TJSONArray;
begin
  mChanges := TWorkspaceChanges.Create;
  mJson := nil;
  try
    mChanges.DeleteFile('C:\P\Alt.pas');
    mChanges.Add('C:\P\A.pas', [Edit(1, 'x')]);
    Assert.AreEqual(2, mChanges.FileCount);
    Assert.AreEqual(2, mChanges.EditCount);
    Assert.AreEqual(1, Integer(Length(mChanges.Deleted)));
    mJson := mChanges.ToJson('safeDelete', 'Sicher loeschen', '1 Datei');
    mItems := mJson.GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual(2, Integer(mItems.Count));
    mItem := mItems.Items[1] as TJSONObject;
    Assert.AreEqual('delete', mItem.GetValue('kind').Value);
    Assert.IsTrue(mItem.GetValue('uri').Value.EndsWith('Alt.pas'));
    Assert.AreEqual('safeDelete', mItem.GetValue('annotationId').Value);
    Assert.IsTrue(((mItem.GetValue('options') as TJSONObject).GetValue('ignoreIfNotExists') as TJSONBool).AsBoolean);
  finally
    mJson.Free;
    mChanges.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TWorkspaceChangesTests);

end.
