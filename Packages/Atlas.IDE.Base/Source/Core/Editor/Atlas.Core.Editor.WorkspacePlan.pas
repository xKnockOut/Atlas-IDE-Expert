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
  System.Generics.Collections;

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
    procedure PlanOperation(const AOperation: TLspFileOperation);
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
    Result := TAtlasUnopenedPolicy.OpenInEditor
  else
    Result := TAtlasUnopenedPolicy.WriteToDisk;
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
    Exit(FCreates[FPending[KeyOf(AFileName)]].Content);
  if not FEnvironment.Read(AFileName, Result) then
    raise ELspEditError.Create('Datei nicht gefunden');
  if FReplaced.TryGetValue(KeyOf(AFileName), Item) then
    Result.Text := Item.Base;
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
    AddCreate(AFileName, AProject, AContent);
end;

function TPlanBuilder.MayReplace(const AFileName: string; const AOperation: TLspFileOperation): Boolean;
begin
  if AOperation.Overwrite then
    Exit(True);
  if AOperation.IgnoreIfExists then
    Exit(False);
  raise ELspEditError.CreateFmt('%s existiert bereits', [ExtractFileName(AFileName)]);
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
    Replace(AFileName, AContent.Text)
  else
    PlanCreate(AFileName, AProject, AContent);
end;

function TPlanBuilder.NewFileProject(const AFileName: string): string;
begin
  if FOwner = '' then
    Result := FEnvironment.ProjectForNewFile(AFileName)
  else if FOwnerLoaded and SameText(ExtractFileExt(AFileName), '.pas') then
    Result := FOwner
  else
    Result := '';
end;

procedure TPlanBuilder.PlanOperation(const AOperation: TLspFileOperation);
var
  Source: TAtlasTextFileContent;
  Project: string;
begin
  case AOperation.Kind of
    TLspFileOperationKind.Create:
      begin
        if Exists(AOperation.FileName) and not MayReplace(AOperation.FileName, AOperation) then
          Exit;
        SetTarget(AOperation.FileName, NewFileProject(AOperation.FileName), Content(AOperation.FileName, ''));
      end;
    TLspFileOperationKind.Rename:
      begin
        if not Exists(AOperation.FileName) then
          raise ELspEditError.Create('Datei nicht gefunden');
        if SameText(AOperation.FileName, AOperation.NewFileName) then
          Exit;
        if Exists(AOperation.NewFileName) and not MayReplace(AOperation.NewFileName, AOperation) then
          Exit;
        Source := ReadCurrent(AOperation.FileName);
        if FPending.ContainsKey(KeyOf(AOperation.FileName)) then
        begin
          Project := FCreates[FPending[KeyOf(AOperation.FileName)]].Project;
          DropCreate(AOperation.FileName);
        end
        else
        begin
          Project := FEnvironment.ProjectOfFile(AOperation.FileName);
          AddRemove(AOperation.FileName);
        end;
        // Kodierung und Zeilenenden wandern mit (#121); das Projekt bleibt.
        SetTarget(AOperation.NewFileName, Project, Source);
      end;
    TLspFileOperationKind.Delete:
      begin
        if FPending.ContainsKey(KeyOf(AOperation.FileName)) then
        begin
          DropCreate(AOperation.FileName);
          Exit;
        end;
        if FEnvironment.IsDirectory(AOperation.FileName) then
          raise ELspEditError.Create('Ordner löscht Atlas nicht');
        if not Exists(AOperation.FileName) then
        begin
          if AOperation.IgnoreIfNotExists then
            Exit;
          raise ELspEditError.Create('Datei nicht gefunden');
        end;
        AddRemove(AOperation.FileName);
      end;
  end;
end;

function TPlanBuilder.PlanTexts(const AFiles: TArray<TLspFileEdits>; var APlan: TAtlasEditPlan): Boolean;
var
  Files: TList<TAtlasPlannedEdit>;
  FileEdits: TLspFileEdits;
  Planned: TAtlasPlannedOperation;
  Entry: TAtlasPlannedEdit;
  Existing, Replacement: TReplacedFile;
  Index: Integer;
  Listed: Boolean;
begin
  Result := False;
  Files := TList<TAtlasPlannedEdit>.Create;
  try
    for FileEdits in AFiles do
    begin
      if FGone.ContainsKey(KeyOf(FileEdits.FileName)) then
      begin
        APlan.Error := Failure(FileEdits.FileName, 'wird gelöscht');
        Exit;
      end;
      if FPending.ContainsKey(KeyOf(FileEdits.FileName)) then
      begin
        // Neue Datei: Die Änderungen gehen in ihren Inhalt.
        Index := FPending[KeyOf(FileEdits.FileName)];
        Planned := FCreates[Index];
        try
          Planned.Content.Text := TLspEdits.Apply(Planned.Content.Text, FileEdits.Edits);
        except
          on E: Exception do
          begin
            APlan.Error := Failure(FileEdits.FileName, E.Message);
            Exit;
          end;
        end;
        FCreates[Index] := Planned;
        Inc(APlan.CreatedEdits, Length(FileEdits.Edits));
        Continue;
      end;
      Entry := Default(TAtlasPlannedEdit);
      Entry.FileName := FileEdits.FileName;
      Entry.Edits := FileEdits.Edits;
      Files.Add(Entry);
    end;
    // Ersetzte Dateien ohne eigene Textänderungen bekommen den neuen Inhalt ebenso.
    for Existing in FReplaced.Values do
    begin
      Listed := False;
      for Entry in Files do
        if SameText(Entry.FileName, Existing.FileName) then
          Listed := True;
      if not Listed then
      begin
        Entry := Default(TAtlasPlannedEdit);
        Entry.FileName := Existing.FileName;
        Files.Add(Entry);
      end;
    end;
    for Index := 0 to Files.Count - 1 do
    begin
      Entry := Files[Index];
      Entry.HasBase := FReplaced.TryGetValue(KeyOf(Entry.FileName), Replacement);
      if Entry.HasBase then
        Entry.Base := Replacement.Base;
      Files[Index] := Entry;
    end;
    APlan.Files := Files.ToArray;
    Result := True;
  finally
    Files.Free;
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
      if Item.FileName <> '' then
        Kept.Add(Item);
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
    Result.Edit := AEdit.WithoutProject(FOwner);
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
    Exit;
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

end.
