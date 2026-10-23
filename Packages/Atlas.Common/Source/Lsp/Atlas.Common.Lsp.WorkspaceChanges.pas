unit Atlas.Common.Lsp.WorkspaceChanges;

// Gemeinsamer Baustein der Umbauten, die mehrere Dateien ändern und neue Units
// anlegen („Klasse verschieben“ #103, „Interface herauslösen“ #664,
// „Basisklasse herauslösen“ #713, „Mitglied verschieben“ #675):
//   - sammelt Änderungen je Datei (Änderungen derselben Datei werden
//     zusammengefasst) und neue Dateien samt Inhalt,
//   - trägt eine neue Unit ins Projekt ein (uses bzw. contains der .dpr/.dpk
//     mit relativem Pfad, DCCReference der .dproj) und meldet, wenn das nicht
//     geht,
//   - erzeugt das WorkspaceEdit mit documentChanges (erst die neuen Dateien)
//     und optional einer Änderungsanmerkung für die Vorschau.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Lsp.References;

type
  TWorkspaceFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  TWorkspaceNewFile = record
    FileName: string;
    Text: string;
  end;

  TWorkspaceChanges = class
  private
    FFiles: TArray<TWorkspaceFileEdits>;
    FCreated: TArray<TWorkspaceNewFile>;
    FWarnings: TArray<string>;
  public
    /// <summary>Änderungen an AFileName; ohne Änderungen nichts.</summary>
    procedure Add(const AFileName: string; const AEdits: TArray<TTextEdit>);
    /// <summary>Neue Datei mit AText.</summary>
    procedure CreateFile(const AFileName, AText: string);
    procedure Warn(const AWarning: string);
    /// <summary>Die neue Unit ANewFile (Name AUnitName) ins Projekt eintragen; ohne Projekt nur ein Hinweis.
    /// </summary>
    procedure RegisterUnit(AHasProject: Boolean; const AProject: TProjectInfo; const AReadText: TReferenceReadText;
      const ANewFile, AUnitName: string);
    /// <summary>Änderungen an AFileName bisher.</summary>
    function EditsOf(const AFileName: string): TArray<TTextEdit>;
    /// <summary>Anzahl der Änderungen und der Dateien (neue eingeschlossen).</summary>
    function EditCount: Integer;
    function FileCount: Integer;
    /// <summary>WorkspaceEdit; mit AAnnotationId tragen alle Änderungen diese Anmerkung (needsConfirmation) mit
    /// ALabel und ADescription. Der Aufrufer übernimmt das Objekt.</summary>
    function ToJson(const AAnnotationId, ALabel, ADescription: string): TJSONObject; overload;
    function ToJson: TJSONObject; overload;
    /// <summary>Hinweise als JSON-Array. Der Aufrufer übernimmt das Objekt.</summary>
    function WarningsJson: TJSONArray;
    property Files: TArray<TWorkspaceFileEdits> read FFiles;
    property Created: TArray<TWorkspaceNewFile> read FCreated;
    property Warnings: TArray<string> read FWarnings;
  end;

implementation

uses
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Editing.UnitTemplates,
  Atlas.Common.Lsp.Positions;

{ TWorkspaceChanges }

procedure TWorkspaceChanges.Add(const AFileName: string; const AEdits: TArray<TTextEdit>);
var
  Index: Integer;
  Item: TWorkspaceFileEdits;
begin
  if AEdits = nil then
    Exit;
  for Index := 0 to High(FFiles) do
    if SameText(FFiles[Index].FileName, AFileName) then
    begin
      FFiles[Index].Edits := FFiles[Index].Edits + AEdits;
      Exit;
    end;
  Item.FileName := AFileName;
  Item.Edits := AEdits;
  FFiles := FFiles + [Item];
end;

procedure TWorkspaceChanges.CreateFile(const AFileName, AText: string);
var
  Item: TWorkspaceNewFile;
begin
  Item.FileName := AFileName;
  Item.Text := AText;
  FCreated := FCreated + [Item];
end;

procedure TWorkspaceChanges.Warn(const AWarning: string);
begin
  FWarnings := FWarnings + [AWarning];
end;

function TWorkspaceChanges.EditsOf(const AFileName: string): TArray<TTextEdit>;
var
  Item: TWorkspaceFileEdits;
begin
  for Item in FFiles do
    if SameText(Item.FileName, AFileName) then
      Exit(Item.Edits);
  Result := nil;
end;

function TWorkspaceChanges.EditCount: Integer;
var
  Item: TWorkspaceFileEdits;
begin
  Result := Length(FCreated);
  for Item in FFiles do
    Inc(Result, Length(Item.Edits));
end;

function TWorkspaceChanges.FileCount: Integer;
begin
  Result := Length(FFiles) + Length(FCreated);
end;

procedure TWorkspaceChanges.RegisterUnit(AHasProject: Boolean; const AProject: TProjectInfo;
  const AReadText: TReferenceReadText; const ANewFile, AUnitName: string);
var
  Text, Relative, ProjectFile: string;
  Edit: TTextEdit;
begin
  if not AHasProject then
  begin
    Warn('Kein Projekt geladen: Die neue Unit steht in keiner .dpr, .dpk oder .dproj.');
    Exit;
  end;
  if (AProject.MainSource <> '') and Assigned(AReadText) and AReadText(AProject.MainSource, Text) then
  begin
    Relative := TTestUnits.RelativePath(TProjectPaths.DirectoryOf(AProject.MainSource), ANewFile);
    if TUnitTemplates.UnitProgramEdit(Text, AUnitName, Relative, Edit) then
      Add(AProject.MainSource, [Edit])
    else
      Warn(Format('%s hat kein uses bzw. contains für die neue Unit', [ExtractFileName(AProject.MainSource)]));
  end;
  ProjectFile := AProject.FileName;
  if Assigned(AReadText) and AReadText(ProjectFile, Text) then
  begin
    Relative := TTestUnits.RelativePath(TProjectPaths.DirectoryOf(ProjectFile), ANewFile);
    if (Pos('"' + Relative + '"', Text) = 0) and
      TUnitTemplates.ProjectEdit(Text, Relative, '', TFormKind.Form, False, Edit) then
      Add(ProjectFile, [Edit]);
  end;
end;

function DocumentEdit(const AUri: string; const AEdits: TArray<TTextEdit>; const AAnnotationId: string): TJSONObject;
var
  Document, Item: TJSONObject;
  Edits: TJSONArray;
  Edit: TTextEdit;
begin
  Document := TJSONObject.Create;
  Document.AddPair('uri', AUri);
  Document.AddPair('version', TJSONNull.Create);
  Edits := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    if AAnnotationId <> '' then
      Item.AddPair('annotationId', AAnnotationId);
    Edits.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Edits);
end;

function TWorkspaceChanges.ToJson(const AAnnotationId, ALabel, ADescription: string): TJSONObject;
var
  Changes: TJSONArray;
  Creation, Options, Annotation, Annotations: TJSONObject;
  NewFile: TWorkspaceNewFile;
  FileEdits: TWorkspaceFileEdits;
  Uri: string;
begin
  Changes := TJSONArray.Create;
  for NewFile in FCreated do
  begin
    Uri := TDocumentUris.FromPath(NewFile.FileName);
    Creation := TJSONObject.Create;
    Creation.AddPair('kind', 'create');
    Creation.AddPair('uri', Uri);
    Options := TJSONObject.Create;
    Options.AddPair('ignoreIfExists', TJSONBool.Create(False));
    Creation.AddPair('options', Options);
    if AAnnotationId <> '' then
      Creation.AddPair('annotationId', AAnnotationId);
    Changes.AddElement(Creation);
    Changes.AddElement(DocumentEdit(Uri, [TTextEdit.Create(TTextRange.Create(0, 0, 0, 0), NewFile.Text)],
      AAnnotationId));
  end;
  for FileEdits in FFiles do
    Changes.AddElement(DocumentEdit(TDocumentUris.FromPath(FileEdits.FileName), FileEdits.Edits, AAnnotationId));
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', Changes);
  if AAnnotationId <> '' then
  begin
    Annotation := TJSONObject.Create;
    Annotation.AddPair('label', ALabel);
    Annotation.AddPair('needsConfirmation', TJSONBool.Create(True));
    Annotation.AddPair('description', ADescription);
    Annotations := TJSONObject.Create;
    Annotations.AddPair(AAnnotationId, Annotation);
    Result.AddPair('changeAnnotations', Annotations);
  end;
end;

function TWorkspaceChanges.ToJson: TJSONObject;
begin
  Result := ToJson('', '', '');
end;

function TWorkspaceChanges.WarningsJson: TJSONArray;
var
  Warning: string;
begin
  Result := TJSONArray.Create;
  for Warning in FWarnings do
    Result.Add(Warning);
end;

end.
