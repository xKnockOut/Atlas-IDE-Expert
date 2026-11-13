unit Atlas.Common.Monitor.Targets;

// Zielliste und gemerkter Stand des Prüffensters von AtlasMonitor (#1900): Ordner, Projekte (.dproj), Gruppen
// (.groupproj) und einzelne Dateien, je Ziel an/aus, dazu Befehl und Optionen. Als JSON in eine eigene Datei
// („Liste speichern“/„Liste laden“) und als Abschnitt "check" in monitor.json, damit das Fenster beim nächsten Start
// so aussieht wie zuletzt. Lesen ist nachsichtig: Unbekanntes wird übergangen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Monitor.Commands;

type
  {$SCOPEDENUMS ON}
  TMonitorTargetKind = (Folder, Project, Group, SourceFile);
  {$SCOPEDENUMS OFF}

  TMonitorTarget = record
    Path: string;
    Enabled: Boolean;
    /// <summary>Art nach der Endung; ohne Endung ein Ordner.</summary>
    function Kind: TMonitorTargetKind;
    function KindText: string;
  end;

  TMonitorTargetList = record
  public const
    cFileExtension = '.atlastargets';
  public
    Items: TArray<TMonitorTarget>;
    /// <summary>Hängt APath an (eingeschaltet); False, wenn es schon in der Liste steht (ohne Groß-/Kleinschreibung).
    /// </summary>
    function Add(const APath: string): Boolean;
    procedure Delete(AIndex: Integer);
    function IndexOf(const APath: string): Integer;
    /// <summary>Pfade der eingeschalteten Ziele in Listenreihenfolge.</summary>
    function EnabledPaths: TArray<string>;
    /// <summary>JSON-Array der Ziele; gehört dem Aufrufer.</summary>
    function ToJson: TJSONArray;
    class function FromJson(AArray: TJSONArray): TMonitorTargetList; static;
    /// <summary>Inhalt einer Listendatei: {"targets": [...]}.</summary>
    function ToText: string;
    class function FromText(const AText: string): TMonitorTargetList; static;
  end;

  /// <summary>Gemerkter Stand des Fensters: Ziele, Befehl, Optionen und der Befehl des Editors für Doppelklick.
  /// </summary>
  TMonitorCheckState = record
  public
    Targets: TMonitorTargetList;
    Command: TMonitorCommand;
    Options: TMonitorOptions;
    /// <summary>Editor für Doppelklick auf einen Befund, z. B. code -g "%file%:%line%:%column%"; '' = das Programm,
    /// das Windows der Endung zuordnet.</summary>
    Editor: string;
    class function Defaults: TMonitorCheckState; static;
    /// <summary>Abschnitt "check" von monitor.json; gehört dem Aufrufer.</summary>
    function ToJson: TJSONObject;
    /// <summary>Stand aus dem Abschnitt; Vorgaben für Fehlendes, auch bei AObject = nil.</summary>
    class function FromJson(AObject: TJSONObject): TMonitorCheckState; static;
    /// <summary>Befehl für den Editor: Platzhalter %file%, %line%, %column% ersetzt; '' ohne Editor.</summary>
    class function EditorCommand(const AEditor, AFileName: string; ALine, AColumn: Integer): string; static;
  end;

implementation

uses
  Atlas.Text.Json,
  Atlas.Common.Localization.Texts;

const
  cTargets = 'targets';
  cPath = 'path';
  cEnabled = 'enabled';
  cCommand = 'command';
  cEditor = 'editor';
  cCommandNames: array[TMonitorCommand] of string = ('check', 'metrics', 'todos', 'format-check', 'format-write',
    'fix-dry-run', 'fix', 'affected-tests', 'architecture', 'architecture-save', 'architecture-compare', 'hotspots',
    'query', 'replay');

  cKindTexts: array[TMonitorTargetKind] of TAtlasText = (
    (De: 'Ordner'; En: 'Folder'),
    (De: 'Projekt'; En: 'Project'),
    (De: 'Projektgruppe'; En: 'Project group'),
    (De: 'Datei'; En: 'File'));

{ TMonitorTarget }

function TMonitorTarget.Kind: TMonitorTargetKind;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(Path));
  if (mExt = '.dproj') or (mExt = '.dpk') or (mExt = '.dpr') then
  begin
    Result := TMonitorTargetKind.Project;
  end
  else if mExt = '.groupproj' then
  begin
    Result := TMonitorTargetKind.Group;
  end
  else if (mExt = '.pas') or (mExt = '.inc') or (mExt = '.dfm') or (mExt = '.fmx') then
  begin
    Result := TMonitorTargetKind.SourceFile;
  end
  else
  begin
    Result := TMonitorTargetKind.Folder;
  end;
end;

function TMonitorTarget.KindText: string;
begin
  Result := cKindTexts[Kind].Text;
end;

{ TMonitorTargetList }

function TMonitorTargetList.IndexOf(const APath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Items) do
  begin
    if SameText(Items[I].Path, APath) then
    begin
      Exit(I);
    end;
  end;
  Result := -1;
end;

function TMonitorTargetList.Add(const APath: string): Boolean;
var
  mTarget: TMonitorTarget;
begin
  Result := (Trim(APath) <> '') and (IndexOf(APath) < 0);
  if Result then
  begin
    mTarget.Path := Trim(APath);
    mTarget.Enabled := True;
    SetLength(Items, Length(Items) + 1);
    Items[High(Items)] := mTarget;
  end;
end;

procedure TMonitorTargetList.Delete(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex > High(Items)) then
  begin
    Exit;
  end;
  for I := AIndex to High(Items) - 1 do
  begin
    Items[I] := Items[I + 1];
  end;
  SetLength(Items, Length(Items) - 1);
end;

function TMonitorTargetList.EnabledPaths: TArray<string>;
var
  mTarget: TMonitorTarget;
  mCount: Integer;
begin
  SetLength(Result, Length(Items));
  mCount := 0;
  for mTarget in Items do
  begin
    if mTarget.Enabled then
    begin
      Result[mCount] := mTarget.Path;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

function TMonitorTargetList.ToJson: TJSONArray;
var
  mTarget: TMonitorTarget;
  mObject: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mTarget in Items do
  begin
    mObject := TJSONObject.Create;
    mObject.AddPair(cPath, mTarget.Path);
    mObject.AddPair(cEnabled, TJSONBool.Create(mTarget.Enabled));
    Result.AddElement(mObject);
  end;
end;

class function TMonitorTargetList.FromJson(AArray: TJSONArray): TMonitorTargetList;
var
  mValue: TJSONValue;
  mObject: TJSONObject;
  mIndex: Integer;
begin
  Result := Default(TMonitorTargetList);
  if AArray = nil then
  begin
    Exit;
  end;
  for mValue in AArray do
  begin
    mObject := TJsonRead.AsObject(mValue);
    if (mObject <> nil) and Result.Add(TJsonRead.Text(mObject, cPath)) then
    begin
      mIndex := High(Result.Items);
      Result.Items[mIndex].Enabled := TJsonRead.FlagOr(mObject, cEnabled, True);
    end;
  end;
end;

function TMonitorTargetList.ToText: string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair(cTargets, ToJson);
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

class function TMonitorTargetList.FromText(const AText: string): TMonitorTargetList;
var
  mRoot: TJSONObject;
begin
  mRoot := TJsonRead.ParseObject(AText);
  try
    Result := FromJson(TJsonRead.Items(mRoot, cTargets));
  finally
    mRoot.Free;
  end;
end;

{ TMonitorCheckState }

class function TMonitorCheckState.Defaults: TMonitorCheckState;
begin
  Result := Default(TMonitorCheckState);
  Result.Command := TMonitorCommand.Check;
end;

/// <summary>Setzt AName auf AValue; leere Werte bleiben weg.</summary>
procedure PutText(AObject: TJSONObject; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AObject.AddPair(AName, AValue);
  end;
end;

/// <summary>Setzt AName nur, wenn AValue an ist.</summary>
procedure PutFlag(AObject: TJSONObject; const AName: string; AValue: Boolean);
begin
  if AValue then
  begin
    AObject.AddPair(AName, TJSONBool.Create(True));
  end;
end;

function OptionsToJson(const AOptions: TMonitorOptions; AObject: TJSONObject): TJSONObject;
begin
  Result := AObject;
  PutText(Result, 'minSeverity', AOptions.MinSeverity);
  PutText(Result, 'rules', AOptions.Rules);
  PutText(Result, 'profile', AOptions.Profile);
  PutText(Result, 'units', AOptions.Units);
  PutFlag(Result, 'changed', AOptions.Changed);
  PutText(Result, 'changedBase', AOptions.ChangedBase);
  PutText(Result, 'diff', AOptions.DiffRef);
  PutFlag(Result, 'includeUncommitted', AOptions.IncludeUncommitted);
  PutFlag(Result, 'changedLines', AOptions.ChangedLines);
  PutText(Result, 'baseline', AOptions.Baseline);
  PutFlag(Result, 'updateBaseline', AOptions.UpdateBaseline);
  PutFlag(Result, 'noIndex', AOptions.NoIndex);
  PutFlag(Result, 'timings', AOptions.Timings);
  PutText(Result, 'fixRules', AOptions.FixRules);
  PutText(Result, 'affectedBase', AOptions.AffectedBase);
  PutText(Result, 'query', AOptions.Query);
  PutText(Result, 'architectureFile', AOptions.ArchitectureFile);
  PutText(Result, 'replayFile', AOptions.ReplayFile);
end;

function OptionsFromJson(AObject: TJSONObject): TMonitorOptions;
begin
  Result := Default(TMonitorOptions);
  Result.MinSeverity := TJsonRead.StrictText(AObject, 'minSeverity');
  Result.Rules := TJsonRead.StrictText(AObject, 'rules');
  Result.Profile := TJsonRead.StrictText(AObject, 'profile');
  Result.Units := TJsonRead.StrictText(AObject, 'units');
  Result.Changed := TJsonRead.FlagOr(AObject, 'changed', False);
  Result.ChangedBase := TJsonRead.StrictText(AObject, 'changedBase');
  Result.DiffRef := TJsonRead.StrictText(AObject, 'diff');
  Result.IncludeUncommitted := TJsonRead.FlagOr(AObject, 'includeUncommitted', False);
  Result.ChangedLines := TJsonRead.FlagOr(AObject, 'changedLines', False);
  Result.Baseline := TJsonRead.StrictText(AObject, 'baseline');
  Result.UpdateBaseline := TJsonRead.FlagOr(AObject, 'updateBaseline', False);
  Result.NoIndex := TJsonRead.FlagOr(AObject, 'noIndex', False);
  Result.Timings := TJsonRead.FlagOr(AObject, 'timings', False);
  Result.FixRules := TJsonRead.StrictText(AObject, 'fixRules');
  Result.AffectedBase := TJsonRead.StrictText(AObject, 'affectedBase');
  Result.Query := TJsonRead.StrictText(AObject, 'query');
  Result.ArchitectureFile := TJsonRead.StrictText(AObject, 'architectureFile');
  Result.ReplayFile := TJsonRead.StrictText(AObject, 'replayFile');
end;

function TMonitorCheckState.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair(cTargets, Targets.ToJson);
  Result.AddPair(cCommand, cCommandNames[Command]);
  OptionsToJson(Options, Result);
  PutText(Result, cEditor, Editor);
end;

class function TMonitorCheckState.FromJson(AObject: TJSONObject): TMonitorCheckState;
var
  mCommand: TMonitorCommand;
  mName: string;
begin
  Result := Defaults;
  if AObject = nil then
  begin
    Exit;
  end;
  Result.Targets := TMonitorTargetList.FromJson(TJsonRead.Items(AObject, cTargets));
  mName := TJsonRead.StrictText(AObject, cCommand);
  for mCommand := Low(TMonitorCommand) to High(TMonitorCommand) do
  begin
    if cCommandNames[mCommand] = mName then
    begin
      Result.Command := mCommand;
    end;
  end;
  Result.Options := OptionsFromJson(AObject);
  Result.Editor := TJsonRead.StrictText(AObject, cEditor);
end;

class function TMonitorCheckState.EditorCommand(const AEditor, AFileName: string; ALine, AColumn: Integer): string;
begin
  Result := '';
  if Trim(AEditor) = '' then
  begin
    Exit;
  end;
  Result := AEditor.Replace('%file%', AFileName, [rfReplaceAll, rfIgnoreCase])
    .Replace('%line%', IntToStr(ALine), [rfReplaceAll, rfIgnoreCase])
    .Replace('%column%', IntToStr(AColumn), [rfReplaceAll, rfIgnoreCase]);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Monitor.Targets', cKindTexts);

end.
