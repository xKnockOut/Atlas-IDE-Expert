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
    FDeleted: TArray<string>;
    FWarnings: TArray<string>;
  public
    /// <summary>Änderungen an AFileName; ohne Änderungen nichts.</summary>
    procedure Add(const AFileName: string; const AEdits: TArray<TTextEdit>);
    /// <summary>Neue Datei mit AText.</summary>
    procedure CreateFile(const AFileName, AText: string);
    /// <summary>AFileName löschen (#716); fehlt sie, bleibt es ohne Fehler (ignoreIfNotExists).</summary>
    procedure DeleteFile(const AFileName: string);
    procedure Warn(const AWarning: string);
    /// <summary>Die neue Unit ANewFile (Name AUnitName) ins Projekt eintragen; ohne Projekt nur ein Hinweis.
    /// </summary>
    procedure RegisterUnit(AHasProject: Boolean; const AProject: TProjectInfo; const AReadText: TReferenceReadText;
      const ANewFile, AUnitName: string);
    /// <summary>Änderungen an AFileName bisher.</summary>
    function EditsOf(const AFileName: string): TArray<TTextEdit>;
    /// <summary>Anzahl der Änderungen und der Dateien (neue und gelöschte eingeschlossen).</summary>
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
    property Deleted: TArray<string> read FDeleted;
    property Warnings: TArray<string> read FWarnings;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Editing.UnitTemplates,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TWorkspaceChangesText = (NoProjectLoadedTheNew, HasNoUsesOrContains);

const
  cTexts: array[TWorkspaceChangesText] of TAtlasText = (
    (De: 'Kein Projekt geladen: Die neue Unit steht in keiner .dpr, .dpk oder .dproj.';
     En: 'No project loaded: the new unit is in no .dpr, .dpk or .dproj.'),
    (De: '%s hat kein uses bzw. contains für die neue Unit'; En: '%s has no uses or contains for the new unit'));

{$SCOPEDENUMS OFF}

{ TWorkspaceChanges }

procedure TWorkspaceChanges.Add(const AFileName: string; const AEdits: TArray<TTextEdit>);
var
  mIndex: Integer;
  mItem: TWorkspaceFileEdits;
begin
  if AEdits = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FFiles) do
  begin
    if SameText(FFiles[mIndex].FileName, AFileName) then
    begin
      FFiles[mIndex].Edits := FFiles[mIndex].Edits + AEdits;
      Exit;
    end;
  end;
  mItem.FileName := AFileName;
  mItem.Edits := AEdits;
  FFiles := FFiles + [mItem];
end;

procedure TWorkspaceChanges.CreateFile(const AFileName, AText: string);
var
  mItem: TWorkspaceNewFile;
begin
  mItem.FileName := AFileName;
  mItem.Text := AText;
  FCreated := FCreated + [mItem];
end;

procedure TWorkspaceChanges.DeleteFile(const AFileName: string);
begin
  FDeleted := FDeleted + [AFileName];
end;

procedure TWorkspaceChanges.Warn(const AWarning: string);
begin
  FWarnings := FWarnings + [AWarning];
end;

function TWorkspaceChanges.EditsOf(const AFileName: string): TArray<TTextEdit>;
var
  mItem: TWorkspaceFileEdits;
begin
  for mItem in FFiles do
  begin
    if SameText(mItem.FileName, AFileName) then
    begin
      Exit(mItem.Edits);
    end;
  end;
  Result := nil;
end;

function TWorkspaceChanges.EditCount: Integer;
var
  mItem: TWorkspaceFileEdits;
begin
  Result := Length(FCreated) + Length(FDeleted);
  for mItem in FFiles do
  begin
    Inc(Result, Length(mItem.Edits));
  end;
end;

function TWorkspaceChanges.FileCount: Integer;
begin
  Result := Length(FFiles) + Length(FCreated) + Length(FDeleted);
end;

procedure TWorkspaceChanges.RegisterUnit(AHasProject: Boolean; const AProject: TProjectInfo;
  const AReadText: TReferenceReadText; const ANewFile, AUnitName: string);
var
  mText, mRelative, mProjectFile: string;
  mEdit: TTextEdit;
begin
  if not AHasProject then
  begin
    Warn(cTexts[TWorkspaceChangesText.NoProjectLoadedTheNew].Text);
    Exit;
  end;
  if (AProject.MainSource <> '') and Assigned(AReadText) and AReadText(AProject.MainSource, mText) then
  begin
    mRelative := TTestUnits.RelativePath(TProjectPaths.DirectoryOf(AProject.MainSource), ANewFile);
    if TUnitTemplates.UnitProgramEdit(mText, AUnitName, mRelative, mEdit) then
    begin
      Add(AProject.MainSource, [mEdit]);
    end
    else
    begin
      Warn(cTexts[TWorkspaceChangesText.HasNoUsesOrContains].Fmt([ExtractFileName(AProject.MainSource)]));
    end;
  end;
  mProjectFile := AProject.FileName;
  if Assigned(AReadText) and AReadText(mProjectFile, mText) then
  begin
    mRelative := TTestUnits.RelativePath(TProjectPaths.DirectoryOf(mProjectFile), ANewFile);
    if (Pos('"' + mRelative + '"', mText) = 0) and
      TUnitTemplates.ProjectEdit(mText, mRelative, '', TFormKind.Form, False, mEdit) then
    begin
      Add(mProjectFile, [mEdit]);
    end;
  end;
end;

function DocumentEdit(const AUri: string; const AEdits: TArray<TTextEdit>; const AAnnotationId: string): TJSONObject;
var
  mDocument, mItem: TJSONObject;
  mEdits: TJSONArray;
  mEdit: TTextEdit;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', AUri);
  mDocument.AddPair('version', TJSONNull.Create);
  mEdits := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    if AAnnotationId <> '' then
    begin
      mItem.AddPair('annotationId', AAnnotationId);
    end;
    mEdits.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', mDocument);
  Result.AddPair('edits', mEdits);
end;

function TWorkspaceChanges.ToJson(const AAnnotationId, ALabel, ADescription: string): TJSONObject;
var
  mChanges: TJSONArray;
  mCreation, mOptions, mAnnotation, mAnnotations: TJSONObject;
  mNewFile: TWorkspaceNewFile;
  mFileEdits: TWorkspaceFileEdits;
  mUri, mDeleted: string;
begin
  mChanges := TJSONArray.Create;
  for mNewFile in FCreated do
  begin
    mUri := TDocumentUris.FromPath(mNewFile.FileName);
    mCreation := TJSONObject.Create;
    mCreation.AddPair('kind', 'create');
    mCreation.AddPair('uri', mUri);
    mOptions := TJSONObject.Create;
    mOptions.AddPair('ignoreIfExists', TJSONBool.Create(False));
    mCreation.AddPair('options', mOptions);
    if AAnnotationId <> '' then
    begin
      mCreation.AddPair('annotationId', AAnnotationId);
    end;
    mChanges.AddElement(mCreation);
    mChanges.AddElement(DocumentEdit(mUri, [TTextEdit.Create(TTextRange.Create(0, 0, 0, 0), mNewFile.Text)],
      AAnnotationId));
  end;
  for mFileEdits in FFiles do
  begin
    mChanges.AddElement(DocumentEdit(TDocumentUris.FromPath(mFileEdits.FileName), mFileEdits.Edits, AAnnotationId));
  end;
  // Gelöschte Dateien zuletzt: Änderungen an anderen Dateien (uses) stehen davor.
  for mDeleted in FDeleted do
  begin
    mCreation := TJSONObject.Create;
    mCreation.AddPair('kind', 'delete');
    mCreation.AddPair('uri', TDocumentUris.FromPath(mDeleted));
    mOptions := TJSONObject.Create;
    mOptions.AddPair('ignoreIfNotExists', TJSONBool.Create(True));
    mCreation.AddPair('options', mOptions);
    if AAnnotationId <> '' then
    begin
      mCreation.AddPair('annotationId', AAnnotationId);
    end;
    mChanges.AddElement(mCreation);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', mChanges);
  if AAnnotationId <> '' then
  begin
    mAnnotation := TJSONObject.Create;
    mAnnotation.AddPair('label', ALabel);
    mAnnotation.AddPair('needsConfirmation', TJSONBool.Create(True));
    mAnnotation.AddPair('description', ADescription);
    mAnnotations := TJSONObject.Create;
    mAnnotations.AddPair(AAnnotationId, mAnnotation);
    Result.AddPair('changeAnnotations', mAnnotations);
  end;
end;

function TWorkspaceChanges.ToJson: TJSONObject;
begin
  Result := ToJson('', '', '');
end;

function TWorkspaceChanges.WarningsJson: TJSONArray;
var
  mWarning: string;
begin
  Result := TJSONArray.Create;
  for mWarning in FWarnings do
  begin
    Result.Add(mWarning);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.WorkspaceChanges', cTexts);

end.
