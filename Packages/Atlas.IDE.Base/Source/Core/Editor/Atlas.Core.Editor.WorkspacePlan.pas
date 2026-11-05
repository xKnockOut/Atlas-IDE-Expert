unit Atlas.Core.Editor.WorkspacePlan;

// Planung eines WorkspaceEdits (#397, #721, #274) ohne IDE: Dateioperationen (anlegen, umbenennen, löschen)
// zusammenführen, Änderungen an neuen Dateien in deren Inhalt rechnen und festlegen, welche vorhandenen
// Dateien welche Änderungen bekommen. Was offen ist, ob es ein Formular im Designer ist und wie geschrieben
// wird, entscheidet danach TAtlasIdeWorkspaceEdit (S-03b). Fehler stehen in Error; dann ist der Plan zu
// verwerfen, geändert ist noch nichts.
//   - Eine neue Datei, die im selben Edit wieder gelöscht oder umbenannt wird, entfällt.
//   - Eine entfernte Datei, die im selben Edit neu angelegt wird, bleibt und bekommt den neuen Inhalt
//     (Base); ebenso ein vorhandenes Ziel, das eine Operation überschreibt.
//   - Ändert das Edit eine .dproj (neue Testunit, #274) und ist dieses Projekt geladen, kommen neue Units
//     in dieses Projekt und die Änderungen am Projekt entfallen (die IDE trägt sie selbst ein).

interface

uses
  System.SysUtils,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Undo.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Nicht geöffnete Dateien: im Editor öffnen oder auf die Platte schreiben.</summary>
  TAtlasUnopenedPolicy = (OpenInEditor, WriteToDisk);
{$SCOPEDENUMS OFF}

  TAtlasUnopenedPolicies = class
  public
    /// <summary>Aus der Einstellung „Für Änderungen öffnen“ (OpenForEdits).</summary>
    class function FromSetting(AOpenForEdits: Boolean): TAtlasUnopenedPolicy; static;
  end;

  /// <summary>Datei, die angelegt (Created) oder entfernt (Deleted) wird.</summary>
  TAtlasPlannedOperation = record
    Kind: TAtlasFileChangeKind;
    FileName: string;
    Project: string;
    /// <summary>Created: Inhalt nach allen Änderungen; Deleted: Inhalt vorher.</summary>
    Content: TAtlasTextFileContent;
  end;

  /// <summary>Textänderungen an einer vorhandenen Datei.</summary>
  TAtlasPlannedEdit = record
    FileName: string;
    Edits: TArray<TLspTextEdit>;
    /// <summary>Durch eine Operation ersetzt: Edits gelten für Base statt für den aktuellen Inhalt.</summary>
    HasBase: Boolean;
    Base: string;
  end;

  TAtlasEditPlan = record
    /// <summary>Ohne entfallene (angelegt und im selben Edit wieder entfernt).</summary>
    Creates: TArray<TAtlasPlannedOperation>;
    Removes: TArray<TAtlasPlannedOperation>;
    Files: TArray<TAtlasPlannedEdit>;
    /// <summary>Edit ohne die Änderungen am geladenen Projekt (#274).</summary>
    Edit: TLspWorkspaceEdit;
    /// <summary>Zahl der Textänderungen, die in neue Dateien gingen.</summary>
    CreatedEdits: Integer;
    /// <summary>"Datei.pas: Grund" oder ''.</summary>
    Error: string;
  end;

  /// <summary>Was der Planer über Dateien und Projekte wissen muss; in der IDE TAtlasIdeEditEnvironment.</summary>
  IAtlasEditEnvironment = interface
    ['{7A9F35E4-0FD4-4DD2-9F8D-1B75CDA6E1C1}']
    /// <summary>Datei auf der Platte oder offener Puffer.</summary>
    function Exists(const AFileName: string): Boolean;
    function IsDirectory(const AFileName: string): Boolean;
    /// <summary>Wie IAtlasUndoTarget.Read: Puffer, Designer oder Platte; False, wenn sie fehlt.</summary>
    function Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
    /// <summary>Kodierung der Datei auf der Platte (Text leer); UTF-8 mit BOM, wenn sie fehlt.</summary>
    function DiskEncoding(const AFileName: string): TAtlasTextFileContent;
    /// <summary>Projektdatei des Projekts, das AFileName enthält; '' wenn keins.</summary>
    function ProjectOfFile(const AFileName: string): string;
    /// <summary>Aktives Projekt für eine neue Unit; '' wenn keins passt.</summary>
    function ProjectForNewFile(const AFileName: string): string;
    /// <summary>Ist die Projektdatei in der IDE geladen?</summary>
    function ProjectLoaded(const AProjectFile: string): Boolean;
  end;

  TAtlasEditPlanner = class
  public
    class function Plan(const AEdit: TLspWorkspaceEdit; const AEnvironment: IAtlasEditEnvironment):
      TAtlasEditPlan; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TWorkspacePlanText = (FileNotFound, AlreadyExists, AtlasDoesNotDeleteFolders, IsBeingDeleted);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TWorkspacePlanText] of string = (
    ('Datei nicht gefunden',
     '%s existiert bereits',
     'Ordner löscht Atlas nicht',
     'wird gelöscht'),
    ('File not found',
     '%s already exists',
     'Atlas does not delete folders',
     'is being deleted'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TWorkspacePlanText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

type
  /// <summary>Vorhandene Datei, die eine Operation ersetzt: Änderungen gelten für Base.</summary>
  TReplacedFile = record
    FileName: string;
    Base: string;
  end;

  /// <summary>Arbeitsstand einer Planung; lebt nur während TAtlasEditPlanner.Plan.</summary>
  TPlanBuilder = class
  private
    FEnvironment: IAtlasEditEnvironment;
    FCreates: TList<TAtlasPlannedOperation>;
    FRemoves: TList<TAtlasPlannedOperation>;
    /// <summary>Neue Dateien: Schlüssel -> Index in FCreates.</summary>
    FPending: TDictionary<string, Integer>;
    /// <summary>Entfernte Dateien: Schlüssel -> Index in FRemoves.</summary>
    FGone: TDictionary<string, Integer>;
    FReplaced: TDictionary<string, TReplacedFile>;
    FOwner: string;
    FOwnerLoaded: Boolean;
    function Content(const AFileName, AText: string): TAtlasTextFileContent;
    function Exists(const AFileName: string): Boolean;
    function ReadCurrent(const AFileName: string): TAtlasTextFileContent;
    procedure Replace(const AFileName, ABase: string);
    procedure AddCreate(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
    procedure AddRemove(const AFileName: string);
    procedure DropCreate(const AFileName: string);
    procedure PlanCreate(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
    /// <summary>Ziel existiert schon: True = ersetzen, False = Operation auslassen.</summary>
    function MayReplace(const AFileName: string; const AOperation: TLspFileOperation): Boolean;
    procedure SetTarget(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
    /// <summary>Projekt für eine neue Datei: das des Edits (#274) oder das aktive.</summary>
    function NewFileProject(const AFileName: string): string;
    procedure PlanCreateFile(const AOperation: TLspFileOperation);
    /// <summary>Umbenennen: Inhalt, Kodierung und Projekt wandern zum neuen Namen.</summary>
    procedure PlanMove(const AOperation: TLspFileOperation);
    procedure PlanRename(const AOperation: TLspFileOperation);
    procedure PlanDelete(const AOperation: TLspFileOperation);
    procedure PlanOperation(const AOperation: TLspFileOperation);
    /// <summary>Änderungen an einer neuen Datei in deren Inhalt; False mit APlan.Error, wenn sie scheitern.
    /// </summary>
    function EditCreated(const AFileEdits: TLspFileEdits; var APlan: TAtlasEditPlan): Boolean;
    /// <summary>Textänderungen je Datei nach AFiles; False mit APlan.Error.</summary>
    function CollectEdits(const AFiles: TArray<TLspFileEdits>; AList: TList<TAtlasPlannedEdit>;
      var APlan: TAtlasEditPlan): Boolean;
    /// <summary>Ersetzte Dateien ohne eigene Textänderungen bekommen einen Eintrag.</summary>
    procedure AddReplaced(AList: TList<TAtlasPlannedEdit>);
    /// <summary>Ersetzte Dateien: neuer Inhalt als Basis der Änderungen.</summary>
    procedure SetBases(AList: TList<TAtlasPlannedEdit>);
    /// <summary>Änderungen an neuen Dateien in deren Inhalt, die übrigen in APlan.Files; ersetzte Dateien ohne
    /// eigene Änderungen bekommen einen Eintrag. False mit APlan.Error, wenn eine Datei gelöscht wird.</summary>
    function PlanTexts(const AFiles: TArray<TLspFileEdits>; var APlan: TAtlasEditPlan): Boolean;
    function Operations(AList: TList<TAtlasPlannedOperation>): TArray<TAtlasPlannedOperation>;
  public
    constructor Create(const AEnvironment: IAtlasEditEnvironment);
    destructor Destroy; override;
    function Build(const AEdit: TLspWorkspaceEdit): TAtlasEditPlan;
  end;

function KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function Failure(const AFileName, AReason: string): string;
begin
  Result := Format('%s: %s', [ExtractFileName(AFileName), AReason]);
end;

{ TAtlasUnopenedPolicies }

class function TAtlasUnopenedPolicies.FromSetting(AOpenForEdits: Boolean): TAtlasUnopenedPolicy;
begin
  if AOpenForEdits then
  begin
    Result := TAtlasUnopenedPolicy.OpenInEditor;
  end
  else
  begin
    Result := TAtlasUnopenedPolicy.WriteToDisk;
  end;
end;

{ TPlanBuilder }

constructor TPlanBuilder.Create(const AEnvironment: IAtlasEditEnvironment);
begin
  inherited Create;
  FEnvironment := AEnvironment;
  FCreates := TList<TAtlasPlannedOperation>.Create;
  FRemoves := TList<TAtlasPlannedOperation>.Create;
  FPending := TDictionary<string, Integer>.Create;
  FGone := TDictionary<string, Integer>.Create;
  FReplaced := TDictionary<string, TReplacedFile>.Create;
end;

destructor TPlanBuilder.Destroy;
begin
  FReplaced.Free;
  FGone.Free;
  FPending.Free;
  FRemoves.Free;
  FCreates.Free;
  inherited;
end;

function TPlanBuilder.Content(const AFileName, AText: string): TAtlasTextFileContent;
begin
  Result := FEnvironment.DiskEncoding(AFileName);
  Result.Text := AText;
end;

function TPlanBuilder.Exists(const AFileName: string): Boolean;
begin
  Result := FPending.ContainsKey(KeyOf(AFileName)) or
    (FEnvironment.Exists(AFileName) and not FGone.ContainsKey(KeyOf(AFileName)));
end;

function TPlanBuilder.ReadCurrent(const AFileName: string): TAtlasTextFileContent;
var
  Item: TReplacedFile;
begin
  if FPending.ContainsKey(KeyOf(AFileName)) then
  begin
    Exit(FCreates[FPending[KeyOf(AFileName)]].Content);
  end;
  if not FEnvironment.Read(AFileName, Result) then
  begin
    raise ELspEditError.Create(UiText(TWorkspacePlanText.FileNotFound));
  end;
  if FReplaced.TryGetValue(KeyOf(AFileName), Item) then
  begin
    Result.Text := Item.Base;
  end;
end;

procedure TPlanBuilder.Replace(const AFileName, ABase: string);
var
  Item: TReplacedFile;
begin
  Item.FileName := AFileName;
  Item.Base := ABase;
  FReplaced.AddOrSetValue(KeyOf(AFileName), Item);
end;

procedure TPlanBuilder.AddCreate(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
var
  Created: TAtlasPlannedOperation;
begin
  Created := Default(TAtlasPlannedOperation);
  Created.Kind := TAtlasFileChangeKind.Created;
  Created.FileName := AFileName;
  Created.Project := AProject;
  Created.Content := AContent;
  FPending.AddOrSetValue(KeyOf(AFileName), FCreates.Add(Created));
end;

procedure TPlanBuilder.AddRemove(const AFileName: string);
var
  Removed: TAtlasPlannedOperation;
begin
  Removed := Default(TAtlasPlannedOperation);
  Removed.Kind := TAtlasFileChangeKind.Deleted;
  Removed.FileName := AFileName;
  Removed.Project := FEnvironment.ProjectOfFile(AFileName);
  Removed.Content := ReadCurrent(AFileName);
  FGone.AddOrSetValue(KeyOf(AFileName), FRemoves.Add(Removed));
  FReplaced.Remove(KeyOf(AFileName));
end;

procedure TPlanBuilder.DropCreate(const AFileName: string);
var
  Dropped: TAtlasPlannedOperation;
begin
  // Angelegt und im selben Edit wieder gelöscht bzw. umbenannt: die Anlage entfällt.
  Dropped := FCreates[FPending[KeyOf(AFileName)]];
  Dropped.FileName := '';
  FCreates[FPending[KeyOf(AFileName)]] := Dropped;
  FPending.Remove(KeyOf(AFileName));
end;

procedure TPlanBuilder.PlanCreate(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
var
  Revived: TAtlasPlannedOperation;
begin
  if FGone.ContainsKey(KeyOf(AFileName)) then
  begin
    // Vorher im selben Edit entfernt: Die Datei bleibt und bekommt den neuen Inhalt.
    Revived := FRemoves[FGone[KeyOf(AFileName)]];
    Revived.FileName := '';
    FRemoves[FGone[KeyOf(AFileName)]] := Revived;
    FGone.Remove(KeyOf(AFileName));
    Replace(AFileName, AContent.Text);
  end
  else
  begin
    AddCreate(AFileName, AProject, AContent);
  end;
end;

function TPlanBuilder.MayReplace(const AFileName: string; const AOperation: TLspFileOperation): Boolean;
begin
  if AOperation.Overwrite then
  begin
    Exit(True);
  end;
  if AOperation.IgnoreIfExists then
  begin
    Exit(False);
  end;
  raise ELspEditError.CreateFmt(UiText(TWorkspacePlanText.AlreadyExists), [ExtractFileName(AFileName)]);
end;

procedure TPlanBuilder.SetTarget(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
var
  Changed: TAtlasPlannedOperation;
begin
  // Neuer Inhalt für ein Ziel, das existiert (Überschreiben) oder neu ist.
  if FPending.ContainsKey(KeyOf(AFileName)) then
  begin
    Changed := FCreates[FPending[KeyOf(AFileName)]];
    Changed.Content.Text := AContent.Text;
    FCreates[FPending[KeyOf(AFileName)]] := Changed;
  end
  else if Exists(AFileName) then
  begin
    Replace(AFileName, AContent.Text);
  end
  else
  begin
    PlanCreate(AFileName, AProject, AContent);
  end;
end;

function TPlanBuilder.NewFileProject(const AFileName: string): string;
begin
  if FOwner = '' then
  begin
    Result := FEnvironment.ProjectForNewFile(AFileName);
  end
  else if FOwnerLoaded and SameText(ExtractFileExt(AFileName), '.pas') then
  begin
    Result := FOwner;
  end
  else
  begin
    Result := '';
  end;
end;

procedure TPlanBuilder.PlanCreateFile(const AOperation: TLspFileOperation);
begin
  if not Exists(AOperation.FileName) or MayReplace(AOperation.FileName, AOperation) then
  begin
    SetTarget(AOperation.FileName, NewFileProject(AOperation.FileName), Content(AOperation.FileName, ''));
  end;
end;

procedure TPlanBuilder.PlanMove(const AOperation: TLspFileOperation);
var
  mSource: TAtlasTextFileContent;
  mProject: string;
begin
  mSource := ReadCurrent(AOperation.FileName);
  if FPending.ContainsKey(KeyOf(AOperation.FileName)) then
  begin
    mProject := FCreates[FPending[KeyOf(AOperation.FileName)]].Project;
    DropCreate(AOperation.FileName);
  end
  else
  begin
    mProject := FEnvironment.ProjectOfFile(AOperation.FileName);
    AddRemove(AOperation.FileName);
  end;
  // Kodierung und Zeilenenden wandern mit (#121); das Projekt bleibt.
  SetTarget(AOperation.NewFileName, mProject, mSource);
end;

procedure TPlanBuilder.PlanRename(const AOperation: TLspFileOperation);
begin
  if not Exists(AOperation.FileName) then
  begin
    raise ELspEditError.Create(UiText(TWorkspacePlanText.FileNotFound));
  end;
  if not SameText(AOperation.FileName, AOperation.NewFileName) and
    (not Exists(AOperation.NewFileName) or MayReplace(AOperation.NewFileName, AOperation)) then
  begin
    PlanMove(AOperation);
  end;
end;

procedure TPlanBuilder.PlanDelete(const AOperation: TLspFileOperation);
begin
  if FPending.ContainsKey(KeyOf(AOperation.FileName)) then
  begin
    DropCreate(AOperation.FileName);
  end
  else if FEnvironment.IsDirectory(AOperation.FileName) then
  begin
    raise ELspEditError.Create(UiText(TWorkspacePlanText.AtlasDoesNotDeleteFolders));
  end
  else if Exists(AOperation.FileName) then
  begin
    AddRemove(AOperation.FileName);
  end
  else if not AOperation.IgnoreIfNotExists then
  begin
    raise ELspEditError.Create(UiText(TWorkspacePlanText.FileNotFound));
  end;
end;

procedure TPlanBuilder.PlanOperation(const AOperation: TLspFileOperation);
begin
  case AOperation.Kind of
    TLspFileOperationKind.Create:
      PlanCreateFile(AOperation);
    TLspFileOperationKind.Rename:
      PlanRename(AOperation);
    TLspFileOperationKind.Delete:
      PlanDelete(AOperation);
  end;
end;

function TPlanBuilder.EditCreated(const AFileEdits: TLspFileEdits; var APlan: TAtlasEditPlan): Boolean;
var
  mIndex: Integer;
  mPlanned: TAtlasPlannedOperation;
begin
  mIndex := FPending[KeyOf(AFileEdits.FileName)];
  mPlanned := FCreates[mIndex];
  Result := True;
  try
    mPlanned.Content.Text := TLspEdits.Apply(mPlanned.Content.Text, AFileEdits.Edits);
  except
    on E: Exception do
    begin
      APlan.Error := Failure(AFileEdits.FileName, E.Message);
      Result := False;
    end;
  end;
  if Result then
  begin
    FCreates[mIndex] := mPlanned;
    Inc(APlan.CreatedEdits, Length(AFileEdits.Edits));
  end;
end;

function TPlanBuilder.CollectEdits(const AFiles: TArray<TLspFileEdits>; AList: TList<TAtlasPlannedEdit>;
  var APlan: TAtlasEditPlan): Boolean;
var
  mIndex: Integer;
  mEntry: TAtlasPlannedEdit;
begin
  Result := True;
  mIndex := 0;
  while Result and (mIndex <= High(AFiles)) do
  begin
    if FGone.ContainsKey(KeyOf(AFiles[mIndex].FileName)) then
    begin
      APlan.Error := Failure(AFiles[mIndex].FileName, UiText(TWorkspacePlanText.IsBeingDeleted));
      Result := False;
    end
    else if FPending.ContainsKey(KeyOf(AFiles[mIndex].FileName)) then
    begin
      // Neue Datei: Die Änderungen gehen in ihren Inhalt.
      Result := EditCreated(AFiles[mIndex], APlan);
    end
    else
    begin
      mEntry := Default(TAtlasPlannedEdit);
      mEntry.FileName := AFiles[mIndex].FileName;
      mEntry.Edits := AFiles[mIndex].Edits;
      AList.Add(mEntry);
    end;
    Inc(mIndex);
  end;
end;

procedure TPlanBuilder.AddReplaced(AList: TList<TAtlasPlannedEdit>);
var
  mExisting: TReplacedFile;
  mEntry: TAtlasPlannedEdit;
  mListed: Boolean;
begin
  for mExisting in FReplaced.Values do
  begin
    mListed := False;
    for mEntry in AList do
    begin
      mListed := mListed or SameText(mEntry.FileName, mExisting.FileName);
    end;
    if not mListed then
    begin
      mEntry := Default(TAtlasPlannedEdit);
      mEntry.FileName := mExisting.FileName;
      AList.Add(mEntry);
    end;
  end;
end;

procedure TPlanBuilder.SetBases(AList: TList<TAtlasPlannedEdit>);
var
  mIndex: Integer;
  mEntry: TAtlasPlannedEdit;
  mReplacement: TReplacedFile;
begin
  for mIndex := 0 to AList.Count - 1 do
  begin
    mEntry := AList[mIndex];
    mEntry.HasBase := FReplaced.TryGetValue(KeyOf(mEntry.FileName), mReplacement);
    if mEntry.HasBase then
    begin
      mEntry.Base := mReplacement.Base;
    end;
    AList[mIndex] := mEntry;
  end;
end;

function TPlanBuilder.PlanTexts(const AFiles: TArray<TLspFileEdits>; var APlan: TAtlasEditPlan): Boolean;
var
  mFiles: TList<TAtlasPlannedEdit>;
begin
  mFiles := TList<TAtlasPlannedEdit>.Create;
  try
    Result := CollectEdits(AFiles, mFiles, APlan);
    if Result then
    begin
      AddReplaced(mFiles);
      SetBases(mFiles);
      APlan.Files := mFiles.ToArray;
    end;
  finally
    mFiles.Free;
  end;
end;

function TPlanBuilder.Operations(AList: TList<TAtlasPlannedOperation>): TArray<TAtlasPlannedOperation>;
var
  Kept: TList<TAtlasPlannedOperation>;
  Item: TAtlasPlannedOperation;
begin
  Result := nil;
  Kept := TList<TAtlasPlannedOperation>.Create;
  try
    for Item in AList do
    begin
      if Item.FileName <> '' then
      begin
        Kept.Add(Item);
      end;
    end;
    Result := Kept.ToArray;
  finally
    Kept.Free;
  end;
end;

function TPlanBuilder.Build(const AEdit: TLspWorkspaceEdit): TAtlasEditPlan;
var
  Operation: TLspFileOperation;
begin
  Result := Default(TAtlasEditPlan);
  Result.Edit := AEdit;
  FOwner := AEdit.ProjectFile;
  FOwnerLoaded := (FOwner <> '') and (Length(AEdit.Operations) > 0) and FEnvironment.ProjectLoaded(FOwner);
  if FOwnerLoaded then
  begin
    Result.Edit := AEdit.WithoutProject(FOwner);
  end;
  for Operation in Result.Edit.Operations do
    try
      PlanOperation(Operation);
    except
      on E: Exception do
      begin
        Result.Error := Failure(Operation.FileName, E.Message);
        Exit;
      end;
    end;
  if not PlanTexts(Result.Edit.Files, Result) then
  begin
    Exit;
  end;
  Result.Creates := Operations(FCreates);
  Result.Removes := Operations(FRemoves);
end;

{ TAtlasEditPlanner }

class function TAtlasEditPlanner.Plan(const AEdit: TLspWorkspaceEdit;
  const AEnvironment: IAtlasEditEnvironment): TAtlasEditPlan;
var
  Builder: TPlanBuilder;
begin
  Builder := TPlanBuilder.Create(AEnvironment);
  try
    Result := Builder.Build(AEdit);
  finally
    Builder.Free;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Editor.WorkspacePlan', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
