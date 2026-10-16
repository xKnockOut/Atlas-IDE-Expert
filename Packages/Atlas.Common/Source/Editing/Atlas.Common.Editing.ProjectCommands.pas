unit Atlas.Common.Editing.ProjectCommands;

// Schnellbefehle für Projekt und Navigation (#301) im Rahmen aus #293:
//   /define SYMBOL     SYMBOL in DCC_Define der aktiven Konfiguration der .dproj
//   /define! SYMBOL    dasselbe in der Basiskonfiguration, gilt damit für alle
//   /searchpath Pfad   Ordner relativ zur .dproj in DCC_UnitSearchPath der Basis
//   /config Release Win64  Konfiguration und Plattform umschalten (#46)
//   /dfm               aus Ereignis-Handler bzw. Formularmethode in die DFM springen
//   /unit Name         neue Unit neben der Datei anlegen, in .dpr/.dpk und .dproj
//                      eintragen und öffnen (#297)
//   /open Unit         Unit aus Index, Projekt oder Suchpfad öffnen (#297)
// Die Befehle prüfen alles vorab; Schreiben, Umschalten und Springen laufen
// erst nach Erfolg über ISlashHost (TSlashContext.Defer). Ohne Host (Prüfung
// stehen gebliebener Zeilen) passen sie nicht.

interface

uses
  Atlas.Common.Editing.SlashCommands;

/// <summary>Trägt /define, /define!, /searchpath, /config, /dfm, /unit und /open in ARegistry ein.</summary>
procedure RegisterProjectCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.DprojEditor,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UnitTemplates,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Editing.CommandSource,
  Atlas.Text.Lines;

/// <summary>Projekt und .dproj-Text zur Datei des Befehls; False mit Grund.</summary>
function LoadProject(const AContext: TSlashContext; out AProject: TProjectInfo; out AText, AReason: string): Boolean;
begin
  AText := '';
  if AContext.Host = nil then
    Exit(Fail(Format('/%s braucht ein geladenes Projekt', [AContext.Name]), AReason));
  if not AContext.Host.Project(AContext.Uri, AProject) then
    Exit(Fail('Zu dieser Datei ist keine .dproj geladen', AReason));
  if not AContext.Host.ReadFile(AProject.FileName, AText) then
    Exit(Fail(Format('%s lässt sich nicht lesen', [ExtractFileName(AProject.FileName)]), AReason));
  Result := True;
end;

/// <summary>Trägt AValue in AProperty der Konfiguration AConfig ein und merkt das Schreiben vor.</summary>
function AddToProject(const AContext: TSlashContext; const AProject: TProjectInfo; const AText, AConfig,
  AProperty, AValue: string; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Key, NewText, Uri: string;
  Host: ISlashHost;
  Source: TCommandSource;
begin
  Key := TDprojEditor.ConfigKey(AText, AConfig);
  if Key = '' then
    Exit(Fail(Format('Konfiguration %s steht nicht in %s', [AConfig, ExtractFileName(AProject.FileName)]),
      AReason));
  case TDprojEditor.AddToList(AText, Key, AProperty, AValue, NewText) of
    TDprojEditResult.Present:
      Exit(Fail(Format('%s steht schon in %s (%s)', [AValue, AProperty, AConfig]), AReason));
    TDprojEditResult.NoGroup:
      Exit(Fail(Format('%s hat keinen Abschnitt für %s', [ExtractFileName(AProject.FileName), AConfig]),
        AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    AEdits := [Source.RemoveCommand];
  finally
    Source.Free;
  end;
  Host := AContext.Host;
  Uri := AContext.Uri;
  AContext.Defer(
    procedure
    begin
      Host.WriteProject(Uri, NewText);
    end);
  Result := True;
end;

{ /define }

function ExecuteDefine(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Project: TProjectInfo;
  Text, Config: string;
begin
  AEdits := nil;
  if not IsValidIdent(AContext.Arguments) then
    Exit(Fail('Erwartet wird ein Symbol, z. B. /define TEST', AReason));
  if not LoadProject(AContext, Project, Text, AReason) then
    Exit(False);
  if EndsStr('!', AContext.Name) then
    Config := 'Base'
  else
    Config := Project.Config;
  Result := AddToProject(AContext, Project, Text, Config, 'DCC_Define', AContext.Arguments, AEdits, AReason);
end;

{ /searchpath }

function ExecuteSearchPath(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Project: TProjectInfo;
  Text, Path: string;
begin
  AEdits := nil;
  Path := AContext.Arguments;
  if (Length(Path) >= 2) and CharInSet(Path[1], ['''', '"']) and (Path[Length(Path)] = Path[1]) then
    Path := Copy(Path, 2, Length(Path) - 2);
  if Path = '' then
    Exit(Fail('Erwartet wird ein Ordner relativ zur .dproj, z. B. /searchpath Source\Common', AReason));
  if not LoadProject(AContext, Project, Text, AReason) then
    Exit(False);
  if not AContext.Host.DirectoryExists(TProjectPaths.Combine(TProjectPaths.DirectoryOf(Project.FileName), Path)) then
    Exit(Fail(Format('Den Ordner %s gibt es nicht', [Path]), AReason));
  Result := AddToProject(AContext, Project, Text, 'Base', 'DCC_UnitSearchPath', Path, AEdits, AReason);
end;

{ /config }

function ExecuteConfig(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Project: TProjectInfo;
  Word, Config, Platform, Uri: string;
  Host: ISlashHost;
  Source: TCommandSource;
begin
  AEdits := nil;
  if AContext.Arguments = '' then
    Exit(Fail('Erwartet werden Konfiguration und/oder Plattform, z. B. /config Release Win64', AReason));
  if AContext.Host = nil then
    Exit(Fail('/config braucht ein geladenes Projekt', AReason));
  if not AContext.Host.Project(AContext.Uri, Project) then
    Exit(Fail('Zu dieser Datei ist keine .dproj geladen', AReason));
  Config := '';
  Platform := '';
  // Reihenfolge egal: jedes Wort ist entweder Konfiguration oder Plattform des Projekts.
  for Word in AContext.Arguments.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
    if (Config = '') and (IndexText(Word, Project.Configs) >= 0) then
      Config := Project.Configs[IndexText(Word, Project.Configs)]
    else if (Platform = '') and (IndexText(Word, Project.Platforms) >= 0) then
      Platform := Project.Platforms[IndexText(Word, Project.Platforms)]
    else
      Exit(Fail(Format('%s ist weder Konfiguration (%s) noch Plattform (%s)',
        [Word, string.Join(', ', Project.Configs), string.Join(', ', Project.Platforms)]), AReason));
  Source := TCommandSource.Create(AContext);
  try
    AEdits := [Source.RemoveCommand];
  finally
    Source.Free;
  end;
  Host := AContext.Host;
  Uri := AContext.Uri;
  AContext.Defer(
    procedure
    begin
      Host.SelectBuild(Uri, Config, Platform);
    end);
  Result := True;
end;

{ /dfm }

/// <summary>Ereignis mit Wert AMethod in AObject oder darunter; False ohne.</summary>
function FindEvent(AObject: TDfmObject; const AMethod: string; out ARange: TTextRange): Boolean;
var
  Prop: TDfmProperty;
  Child: TDfmObject;
begin
  for Prop in AObject.Properties do
    if Prop.IsEvent and SameText(Trim(Prop.Value), AMethod) then
    begin
      ARange := TTextRange.Create(Prop.NameRange.StartPos.Line, Prop.NameRange.StartPos.Character,
        Prop.ValueRange.EndPos.Line, Prop.ValueRange.EndPos.Character);
      Exit(True);
    end;
  for Child in AObject.Children do
    if FindEvent(Child, AMethod, ARange) then
      Exit(True);
  Result := False;
end;

function ExecuteDfm(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Method, FileName, FormFile, FormText, Extension: string;
  Document: TDfmDocument;
  Target: TTextRange;
  Host: ISlashHost;
begin
  AEdits := nil;
  if AContext.Host = nil then
    Exit(Fail('/dfm braucht den Editor', AReason));
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if (Routine = nil) or (Pos('.', Routine.Name) = 0) then
      Exit(Fail('/dfm gilt nur in einer Methode der Formularklasse', AReason));
    Method := Copy(Routine.Name, LastDelimiter('.', Routine.Name) + 1, MaxInt);
    FileName := TDocumentUris.ToPath(AContext.Uri);
    FormFile := '';
    for Extension in TArray<string>.Create('.dfm', '.fmx') do
      if (FormFile = '') and AContext.Host.ReadFile(ChangeFileExt(FileName, Extension), FormText) then
        FormFile := ChangeFileExt(FileName, Extension);
    if FormFile = '' then
      Exit(Fail('Neben der Unit liegt keine .dfm oder .fmx', AReason));
    Document := TDfmParser.Parse(FormText);
    try
      if Document.Root = nil then
        Exit(Fail(Format('%s ist keine Text-DFM', [ExtractFileName(FormFile)]), AReason));
      // Ereignis-Handler: zur Zuweisung; sonst Formularmethode: zum Formular selbst.
      if not FindEvent(Document.Root, Method, Target) then
        Target := Document.Root.NameRange;
    finally
      Document.Free;
    end;
    AEdits := [Source.RemoveCommand];
  finally
    Source.Free;
  end;
  Host := AContext.Host;
  AContext.Defer(
    procedure
    begin
      Host.ShowDocument(FormFile, Target);
    end);
  Result := True;
end;

{ /unit }

/// <summary>AText mit AEdit angewandt.</summary>
function Applied(const AText: string; const AEdit: TTextEdit): string;
var
  Table: TLineTable;
  Start, Stop: Integer;
begin
  Table := TLineTable.Build(AText);
  Start := Table.OffsetAt(AEdit.Range.StartPos);
  Stop := Table.OffsetAt(AEdit.Range.EndPos);
  Result := Copy(AText, 1, Start) + AEdit.NewText + Copy(AText, Stop + 1, MaxInt);
end;

/// <summary>Name ohne Endung .pas; '' wenn kein gültiger (auch gepunkteter) Bezeichner.</summary>
function UnitNameOf(const AArguments: string): string;
begin
  Result := Trim(AArguments);
  if EndsText('.pas', Result) then
    Result := Copy(Result, 1, Length(Result) - 4);
  if not IsValidIdent(Result, True) then
    Result := '';
end;

/// <summary>Leere Unit wie Datei > Neu > Unit der IDE.</summary>
function NewUnitText(const AUnitName: string): string;
const
  LB = #13#10;
begin
  Result := 'unit ' + AUnitName + ';' + LB + LB + 'interface' + LB + LB + 'implementation' + LB + LB + 'end.' + LB;
end;

function ExecuteUnit(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Project: TProjectInfo;
  ProjectText, Name, Folder, FileName, Existing, MainText, Uri: string;
  Item: TProjectUnit;
  Edit: TTextEdit;
  Files: TArray<TSlashFile>;
  Host: ISlashHost;
  Source: TCommandSource;
begin
  AEdits := nil;
  Name := UnitNameOf(AContext.Arguments);
  if Name = '' then
    Exit(Fail('Erwartet wird ein Unit-Name, z. B. /unit Kunden.Daten', AReason));
  if not LoadProject(AContext, Project, ProjectText, AReason) then
    Exit(False);
  for Item in Project.Units do
    if SameText(Item.Name, Name) then
      Exit(Fail(Format('%s steht schon im Projekt', [Name]), AReason));
  // Neben die Datei des Befehls, ohne Datei neben die .dproj.
  if AContext.Uri <> '' then
    Folder := TProjectPaths.DirectoryOf(TDocumentUris.ToPath(AContext.Uri))
  else
    Folder := TProjectPaths.DirectoryOf(Project.FileName);
  FileName := TProjectPaths.Combine(Folder, Name + '.pas');
  if AContext.Host.ReadFile(FileName, Existing) then
    Exit(Fail(Format('%s gibt es schon', [ExtractFileName(FileName)]), AReason));
  Files := [TSlashFile.Create(FileName, NewUnitText(Name), True)];
  // Hauptdatei: uses der .dpr bzw. contains der .dpk.
  if (Project.MainSource <> '') and AContext.Host.ReadFile(Project.MainSource, MainText) then
  begin
    if not TUnitTemplates.UnitProgramEdit(MainText, Name,
      TTestUnits.RelativePath(TProjectPaths.DirectoryOf(Project.MainSource), FileName), Edit) then
      Exit(Fail(Format('%s hat kein uses bzw. contains für %s', [ExtractFileName(Project.MainSource), Name]),
        AReason));
    Files := Files + [TSlashFile.Create(Project.MainSource, Applied(MainText, Edit), False)];
  end;
  if not TUnitTemplates.ProjectEdit(ProjectText,
    TTestUnits.RelativePath(TProjectPaths.DirectoryOf(Project.FileName), FileName), '', TFormKind.Form, False,
    Edit) then
    Exit(Fail(Format('%s hat keinen Platz für DCCReference', [ExtractFileName(Project.FileName)]), AReason));
  Files := Files + [TSlashFile.Create(Project.FileName, Applied(ProjectText, Edit), False)];
  Source := TCommandSource.Create(AContext);
  try
    AEdits := [Source.RemoveCommand];
  finally
    Source.Free;
  end;
  Host := AContext.Host;
  Uri := AContext.Uri;
  AContext.Defer(
    procedure
    begin
      Host.WriteFiles(Uri, Files, FileName);
    end);
  Result := True;
end;

{ /open }

/// <summary>Datei der Unit AName: Index, eingetragene Units, dann Ordner der Datei und Suchpfade (auch mit
/// Namespace-Präfix); False ohne.</summary>
function FindUnitFile(const AContext: TSlashContext; const AName: string; out AFileName: string): Boolean;
var
  Indexed: TUnitIndex;
  Project: TProjectInfo;
  HasProject: Boolean;
  Item: TProjectUnit;
  Folders, Names: TArray<string>;
  Folder, Name, Namespace, Text: string;
begin
  AFileName := '';
  Names := [AName];
  HasProject := AContext.Host.Project(AContext.Uri, Project);
  if HasProject then
    for Namespace in Project.Namespaces do
      Names := Names + [Namespace + '.' + AName];
  for Namespace in AContext.Namespaces do
    Names := Names + [Namespace + '.' + AName];
  if AContext.Index <> nil then
    for Name in Names do
      if AContext.Index.FindUnit(Name, Indexed) and (Indexed.FileName <> '') then
      begin
        AFileName := Indexed.FileName;
        Exit(True);
      end;
  Folders := nil;
  if AContext.Uri <> '' then
    Folders := [TProjectPaths.DirectoryOf(TDocumentUris.ToPath(AContext.Uri))];
  if HasProject then
  begin
    for Item in Project.Units do
      for Name in Names do
        if SameText(Item.Name, Name) and (Item.FileName <> '') then
        begin
          AFileName := Item.FileName;
          Exit(True);
        end;
    Folders := Folders + [TProjectPaths.DirectoryOf(Project.FileName)] + Project.SearchPaths;
  end;
  for Folder in Folders do
    for Name in Names do
      if AContext.Host.ReadFile(TProjectPaths.Combine(Folder, Name + '.pas'), Text) then
      begin
        AFileName := TProjectPaths.Combine(Folder, Name + '.pas');
        Exit(True);
      end;
  Result := False;
end;

function ExecuteOpen(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Name, FileName: string;
  Host: ISlashHost;
  Source: TCommandSource;
begin
  AEdits := nil;
  Name := UnitNameOf(AContext.Arguments);
  if Name = '' then
    Exit(Fail('Erwartet wird ein Unit-Name, z. B. /open System.SysUtils', AReason));
  if AContext.Host = nil then
    Exit(Fail('/open braucht den Editor', AReason));
  if not FindUnitFile(AContext, Name, FileName) then
    Exit(Fail(Format('Die Unit %s steht weder im Index noch im Suchpfad', [Name]), AReason));
  Source := TCommandSource.Create(AContext);
  try
    AEdits := [Source.RemoveCommand];
  finally
    Source.Free;
  end;
  Host := AContext.Host;
  AContext.Defer(
    procedure
    begin
      Host.ShowDocument(FileName, TTextRange.Create(0, 0, 0, 0));
    end);
  Result := True;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterProjectCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('define', 'Symbol in DCC_Define der aktiven Konfiguration eintragen', '/define TEST',
    ExecuteDefine));
  ARegistry.Register(Command('define!', 'Symbol in DCC_Define aller Konfigurationen eintragen', '/define! TEST',
    ExecuteDefine));
  ARegistry.Register(Command('searchpath', 'Ordner in den Suchpfad des Projekts eintragen',
    '/searchpath Source\Common', ExecuteSearchPath));
  ARegistry.Register(Command('config', 'Konfiguration und Plattform umschalten', '/config Release Win64',
    ExecuteConfig));
  ARegistry.Register(Command('dfm', 'Zur Stelle in der Formulardatei springen', '/dfm', ExecuteDfm));
  ARegistry.Register(Command('unit', 'Neue Unit anlegen, ins Projekt eintragen und öffnen', '/unit Kunden.Daten',
    ExecuteUnit));
  ARegistry.Register(Command('open', 'Unit aus dem Suchpfad öffnen', '/open System.SysUtils', ExecuteOpen));
end;

end.
