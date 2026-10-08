unit BDLsp.Common.Lsp.FileOperations;

// Dateioperationen im Editor (#181):
// - workspace/willRenameFiles: vor dem Umbenennen einer .pas-Datei unit-Zeile,
//   alle uses (auch "in 'Pfad'" in .dpr/.dpk) und DCCReference-Einträge der
//   .dproj anpassen. Der Editor wendet das WorkspaceEdit an; Kodierung und
//   Zeilenenden der Dateien bleiben dabei, wie sie sind.
// - workspace/didCreateFiles: eine neue, leere .pas-Datei erhält über
//   workspace/applyEdit ein Unit-Gerüst mit dem Namen aus dem Dateinamen.
// - workspace/didDeleteFiles: verbliebene Verweise auf eine gelöschte Unit
//   werden als Warnung gemeldet (window/showMessage).

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Lsp.References;

type
  /// <summary>Sendet eine Nachricht an den Client und gibt sie frei.</summary>
  TClientMessageSink = reference to procedure(AMessage: TJSONObject);

  TFileEdit = record
    FileName: string;
    Range: TTextRange;
    NewText: string;
  end;

  /// <summary>Verbliebener Verweis auf eine gelöschte Unit.</summary>
  TUnitReference = record
    FileName: string;
    Range: TTextRange;
  end;

  TLspFileOperations = class
  public const
    WillRenameMethod = 'workspace/willRenameFiles';
    DidCreateMethod = 'workspace/didCreateFiles';
    DidDeleteMethod = 'workspace/didDeleteFiles';
    ApplyEditMethod = 'workspace/applyEdit';
    ShowMessageMethod = 'window/showMessage';
  private
    FReadText: TReferenceReadText;
    FSources: TReferenceFilesProvider;
    FProjects: TReferenceFilesProvider;
    FSend: TClientMessageSink;
    FRequestId: Integer;
    function Files(const AProvider: TReferenceFilesProvider): TArray<string>;
    function HandleWillRename(const AParams: TJSONValue): TJSONValue;
    procedure HandleDidCreate(const AParams: TJSONValue);
    procedure HandleDidDelete(const AParams: TJSONValue);
  public
    /// <summary>ASources: Pascal-Dateien des Projekts; AProjects: .dproj und Hauptdateien (.dpr, .dpk).</summary>
    constructor Create(const AReadText: TReferenceReadText; const ASources, AProjects: TReferenceFilesProvider;
      const ASend: TClientMessageSink);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Inhalt von workspace.fileOperations.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Edits für das Umbenennen von AOldFile in ANewFile; leer für andere Dateien als .pas.</summary>
    class function RenameEdits(const AOldFile, ANewFile: string; const ASources, AProjects: TArray<string>;
      const AReadText: TReferenceReadText): TArray<TFileEdit>; static;
    /// <summary>Verweise auf die Unit von ADeletedFile in den übrigen Dateien.</summary>
    class function References(const ADeletedFile: string; const ASources, AProjects: TArray<string>;
      const AReadText: TReferenceReadText): TArray<TUnitReference>; static;
    /// <summary>Gerüst für AFileName, wenn es eine leere .pas-Datei ist; sonst False.</summary>
    class function SkeletonFor(const AFileName: string; const AReadText: TReferenceReadText;
      out AText: string): Boolean; static;
    /// <summary>WorkspaceEdit (changes) aus AEdits. Der Aufrufer übernimmt das Objekt.</summary>
    class function WorkspaceEdit(const AEdits: TArray<TFileEdit>): TJSONObject; static;
  end;

implementation

uses
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Messages,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Editing.UnitFiles;

const
  // window/showMessage: MessageType.Warning
  WarningMessageType = 2;
  MaxListedReferences = 10;

function FileFilter(const AGlob: string): TJSONObject;
var
  Pattern: TJSONObject;
begin
  Pattern := TJSONObject.Create;
  Pattern.AddPair('glob', AGlob);
  Pattern.AddPair('matches', 'file');
  Result := TJSONObject.Create;
  Result.AddPair('pattern', Pattern);
end;

function Registration: TJSONObject;
var
  Filters: TJSONArray;
begin
  Filters := TJSONArray.Create;
  Filters.AddElement(FileFilter('**/*.pas'));
  Result := TJSONObject.Create;
  Result.AddPair('filters', Filters);
end;

/// <summary>Pfade aus params.files[].<AField> (file-URIs).</summary>
function ReadPaths(const AParams: TJSONValue; const AField: string): TArray<string>;
var
  List: TJSONArray;
  Item: TJSONValue;
  Uri: string;
begin
  Result := nil;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('files', List)) then
    Exit;
  for Item in List do
    if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>(AField, Uri) then
      Result := Result + [TDocumentUris.ToPath(Uri)];
end;

function Contains(const AFiles: TArray<string>; const AFileName: string): Boolean;
var
  FileName: string;
begin
  for FileName in AFiles do
    if SameText(FileName, AFileName) then
      Exit(True);
  Result := False;
end;

/// <summary>Pascal-Dateien ohne Doppelungen, dazu .dpr/.dpk aus AProjects und AExtra.</summary>
function PascalFiles(const ASources, AProjects: TArray<string>; const AExtra: string): TArray<string>;
var
  FileName: string;
begin
  Result := nil;
  for FileName in ASources + AProjects + [AExtra] do
    if (FileName <> '') and not SameText(ExtractFileExt(FileName), '.dproj') and not Contains(Result, FileName) then
      Result := Result + [FileName];
end;

function FileEdit(const AFileName: string; const AEdit: TRuleEdit): TFileEdit;
begin
  Result.FileName := AFileName;
  Result.Range := AEdit.Range;
  Result.NewText := AEdit.NewText;
end;

{ TLspFileOperations }

constructor TLspFileOperations.Create(const AReadText: TReferenceReadText;
  const ASources, AProjects: TReferenceFilesProvider; const ASend: TClientMessageSink);
begin
  inherited Create;
  FReadText := AReadText;
  FSources := ASources;
  FProjects := AProjects;
  FSend := ASend;
end;

procedure TLspFileOperations.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterRequest(WillRenameMethod, HandleWillRename);
  ADispatcher.RegisterNotification(DidCreateMethod, HandleDidCreate);
  ADispatcher.RegisterNotification(DidDeleteMethod, HandleDidDelete);
end;

class function TLspFileOperations.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('willRename', Registration);
  Result.AddPair('didCreate', Registration);
  Result.AddPair('didDelete', Registration);
end;

function TLspFileOperations.Files(const AProvider: TReferenceFilesProvider): TArray<string>;
begin
  if Assigned(AProvider) then
    Result := AProvider()
  else
    Result := nil;
end;

class function TLspFileOperations.RenameEdits(const AOldFile, ANewFile: string;
  const ASources, AProjects: TArray<string>; const AReadText: TReferenceReadText): TArray<TFileEdit>;
var
  OldName, NewName, FileName, Text: string;
  Sources: TArray<string>;
  Edit: TRuleEdit;
begin
  Result := nil;
  if not (TUnitFiles.IsUnitFile(AOldFile) and TUnitFiles.IsUnitFile(ANewFile)) then
    Exit;
  OldName := TUnitFiles.UnitNameOf(AOldFile);
  NewName := TUnitFiles.UnitNameOf(ANewFile);
  // Die umbenannte Datei selbst zählt mit, auch wenn sie nicht zum Projekt gehört.
  Sources := PascalFiles(ASources, AProjects, AOldFile);
  for FileName in Sources do
    if AReadText(FileName, Text) and (Pos(LowerCase(OldName), LowerCase(Text)) > 0) then
      for Edit in TUnitFiles.RenameEdits(TPascalLexer.Tokenize(Text), OldName, NewName) do
        Result := Result + [FileEdit(FileName, Edit)];
  for FileName in AProjects do
    if SameText(ExtractFileExt(FileName), '.dproj') and AReadText(FileName, Text) then
      for Edit in TUnitFiles.ProjectFileEdits(Text, AOldFile, ANewFile) do
        Result := Result + [FileEdit(FileName, Edit)];
end;

class function TLspFileOperations.References(const ADeletedFile: string; const ASources, AProjects: TArray<string>;
  const AReadText: TReferenceReadText): TArray<TUnitReference>;
var
  UnitName, FileName, Text: string;
  Range: TTextRange;
  Reference: TUnitReference;
begin
  Result := nil;
  if not TUnitFiles.IsUnitFile(ADeletedFile) then
    Exit;
  UnitName := TUnitFiles.UnitNameOf(ADeletedFile);
  for FileName in PascalFiles(ASources, AProjects, '') do
  begin
    if SameText(FileName, ADeletedFile) or not AReadText(FileName, Text) or
      (Pos(LowerCase(UnitName), LowerCase(Text)) = 0) then
      Continue;
    for Range in TUnitFiles.References(TPascalLexer.Tokenize(Text), UnitName) do
    begin
      Reference.FileName := FileName;
      Reference.Range := Range;
      Result := Result + [Reference];
    end;
  end;
end;

class function TLspFileOperations.SkeletonFor(const AFileName: string; const AReadText: TReferenceReadText;
  out AText: string): Boolean;
var
  Existing: string;
begin
  AText := '';
  // Kopierte oder aus einer Vorlage erzeugte Dateien haben schon Inhalt.
  Result := TUnitFiles.IsUnitFile(AFileName) and AReadText(AFileName, Existing) and (Trim(Existing) = '');
  if Result then
    AText := TUnitFiles.Skeleton(TUnitFiles.UnitNameOf(AFileName), #13#10);
end;

class function TLspFileOperations.WorkspaceEdit(const AEdits: TArray<TFileEdit>): TJSONObject;
var
  Changes, Item: TJSONObject;
  List: TJSONArray;
  Edit: TFileEdit;
  Uri: string;
begin
  Changes := TJSONObject.Create;
  try
    for Edit in AEdits do
    begin
      Uri := TDocumentUris.FromPath(Edit.FileName);
      List := Changes.GetValue(Uri) as TJSONArray;
      if List = nil then
      begin
        List := TJSONArray.Create;
        Changes.AddPair(Uri, List);
      end;
      Item := TJSONObject.Create;
      Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
      Item.AddPair('newText', Edit.NewText);
      List.AddElement(Item);
    end;
    Result := TJSONObject.Create;
  except
    Changes.Free;
    raise;
  end;
  Result.AddPair('changes', Changes);
end;

function TLspFileOperations.HandleWillRename(const AParams: TJSONValue): TJSONValue;
var
  OldFiles, NewFiles, Sources, Projects: TArray<string>;
  Edits: TArray<TFileEdit>;
  Index: Integer;
begin
  OldFiles := ReadPaths(AParams, 'oldUri');
  NewFiles := ReadPaths(AParams, 'newUri');
  if Length(OldFiles) <> Length(NewFiles) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Jeder Eintrag in "files" braucht "oldUri" und "newUri" in ' + WillRenameMethod);
  Sources := Files(FSources);
  Projects := Files(FProjects);
  Edits := nil;
  for Index := 0 to High(OldFiles) do
    Edits := Edits + RenameEdits(OldFiles[Index], NewFiles[Index], Sources, Projects, FReadText);
  if Edits = nil then
    Exit(TJSONNull.Create);
  Result := WorkspaceEdit(Edits);
end;

procedure TLspFileOperations.HandleDidCreate(const AParams: TJSONValue);
var
  FileName, Text: string;
  Edit: TFileEdit;
  Params, Request: TJSONObject;
begin
  if not Assigned(FSend) then
    Exit;
  for FileName in ReadPaths(AParams, 'uri') do
  begin
    if not SkeletonFor(FileName, FReadText, Text) then
      Continue;
    Edit.FileName := FileName;
    Edit.Range := TTextRange.Create(0, 0, 0, 0);
    Edit.NewText := Text;
    Params := TJSONObject.Create;
    Params.AddPair('label', 'Unit-Gerüst');
    Params.AddPair('edit', WorkspaceEdit([Edit]));
    // Die Antwort des Clients wertet der Dispatcher nicht aus; die id muss nur eindeutig sein.
    Inc(FRequestId);
    Request := TJsonRpcMessages.Notification(ApplyEditMethod, Params);
    Request.AddPair('id', 'bdlsp-create-' + IntToStr(FRequestId));
    FSend(Request);
  end;
end;

procedure TLspFileOperations.HandleDidDelete(const AParams: TJSONValue);
var
  FileName, Text: string;
  Found: TArray<TUnitReference>;
  Index: Integer;
  Params: TJSONObject;
begin
  if not Assigned(FSend) then
    Exit;
  for FileName in ReadPaths(AParams, 'uri') do
  begin
    Found := References(FileName, Files(FSources), Files(FProjects), FReadText);
    if Found = nil then
      Continue;
    Text := Format('Unit "%s" wurde gelöscht, wird aber noch verwendet in:', [TUnitFiles.UnitNameOf(FileName)]);
    for Index := 0 to High(Found) do
    begin
      if Index = MaxListedReferences then
      begin
        Text := Text + Format(' und %d weiteren', [Length(Found) - Index]);
        Break;
      end;
      Text := Text + Format(' %s (Zeile %d)', [ExtractFileName(Found[Index].FileName),
        Found[Index].Range.StartPos.Line + 1]);
      if Index < High(Found) then
        Text := Text + ',';
    end;
    Params := TJSONObject.Create;
    Params.AddPair('type', TJSONNumber.Create(WarningMessageType));
    Params.AddPair('message', Text);
    FSend(TJsonRpcMessages.Notification(ShowMessageMethod, Params));
  end;
end;

end.
