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
//   /component TMyButton : TButton  Komponenten-Unit mit Register anlegen, in
//                      .dpk bzw. .dpr und .dproj eintragen und öffnen (#299)
//   /test              DUnitX-Test für die Methode um den Cursor in der Testunit
//                      (#295); legt sie wie die Code-Aktion aus #274 an, wenn sie fehlt
// Die Befehle prüfen alles vorab; Schreiben, Umschalten und Springen laufen
// erst nach Erfolg über ISlashHost (TSlashContext.Defer). Ohne Host (Prüfung
// stehen gebliebener Zeilen) passen sie nicht.

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /define, /define!, /searchpath, /config, /dfm, /unit, /open, /component und /test über ARegister
/// ein.</summary>
procedure RegisterProjectCommands(const ARegister: TSlashRegister);

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
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
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

/// <summary>Neue Unit im Stil des Projekts (#299, #121, #43): Zeilenende aus format.endOfLine bzw. der Datei
/// des Befehls, Einrückung je Ebene (Vorlagen rücken mit zwei Leerzeichen ein) und Schreibweise nach dem
/// Formatstil.</summary>
function StyledUnitText(const AContext: TSlashContext; const AText: string): string;
var
  Style: TFormatStyle;
  Lines: TArray<string>;
  LevelUnit: string;
  Index, Spaces: Integer;
begin
  Style := AContext.Style;
  if Style.EndOfLine = '' then
  begin
    if (Pos(#10, AContext.Text) > 0) and (Pos(#13#10, AContext.Text) = 0) then
      Style.EndOfLine := #10
    else
      Style.EndOfLine := #13#10;
  end;
  if Style.UseTabs then
    LevelUnit := #9
  else if Style.IndentSize >= 1 then
    LevelUnit := StringOfChar(' ', Style.IndentSize)
  else
    LevelUnit := '  ';
  Lines := TTextLines.SplitLines(AText);
  if LevelUnit <> '  ' then
    for Index := 0 to High(Lines) do
    begin
      Spaces := 0;
      while (Spaces < Length(Lines[Index])) and (Lines[Index][Spaces + 1] = ' ') do
        Inc(Spaces);
      if Spaces < Length(Lines[Index]) then
        Lines[Index] := DupeString(LevelUnit, Spaces div 2) + StringOfChar(' ', Spaces mod 2) +
          Copy(Lines[Index], Spaces + 1, MaxInt);
    end;
  Result := TTextLines.JoinLines(Lines, Style.EndOfLine);
  Result := TFormatter.FormatText(Result, TPascalLexer.Tokenize(Result), Style);
end;

/// <summary>Legt AFileName neben der Datei des Befehls mit AText an, trägt sie in .dpr/.dpk und .dproj ein,
/// wenn ein Projekt geladen ist, und öffnet sie danach. ANeedsProject: ohne Projekt nicht anlegen.</summary>
function AddNewUnit(const AContext: TSlashContext; const AName, AText: string; ANeedsProject: Boolean;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Project: TProjectInfo;
  HasProject: Boolean;
  ProjectText, Folder, FileName, Existing, MainText, Uri: string;
  Item: TProjectUnit;
  Edit: TTextEdit;
  Files: TArray<TSlashFile>;
  Host: ISlashHost;
  Source: TCommandSource;
begin
  AEdits := nil;
  if ANeedsProject then
  begin
    if not LoadProject(AContext, Project, ProjectText, AReason) then
      Exit(False);
    HasProject := True;
  end
  else
  begin
    if AContext.Host = nil then
      Exit(Fail(Format('/%s braucht den Editor', [AContext.Name]), AReason));
    HasProject := AContext.Host.Project(AContext.Uri, Project) and
      AContext.Host.ReadFile(Project.FileName, ProjectText);
  end;
  if HasProject then
    for Item in Project.Units do
      if SameText(Item.Name, AName) then
        Exit(Fail(Format('%s steht schon im Projekt', [AName]), AReason));
  // Neben die Datei des Befehls, ohne Datei neben die .dproj.
  if AContext.Uri <> '' then
    Folder := TProjectPaths.DirectoryOf(TDocumentUris.ToPath(AContext.Uri))
  else if HasProject then
    Folder := TProjectPaths.DirectoryOf(Project.FileName)
  else
    Exit(Fail(Format('/%s braucht eine gespeicherte Datei', [AContext.Name]), AReason));
  FileName := TProjectPaths.Combine(Folder, AName + '.pas');
  if AContext.Host.ReadFile(FileName, Existing) then
    Exit(Fail(Format('%s gibt es schon', [ExtractFileName(FileName)]), AReason));
  Files := [TSlashFile.Create(FileName, StyledUnitText(AContext, AText), True)];
  if HasProject then
  begin
    // Hauptdatei: uses der .dpr bzw. contains der .dpk.
    if (Project.MainSource <> '') and AContext.Host.ReadFile(Project.MainSource, MainText) then
    begin
      if not TUnitTemplates.UnitProgramEdit(MainText, AName,
        TTestUnits.RelativePath(TProjectPaths.DirectoryOf(Project.MainSource), FileName), Edit) then
        Exit(Fail(Format('%s hat kein uses bzw. contains für %s', [ExtractFileName(Project.MainSource), AName]),
          AReason));
      Files := Files + [TSlashFile.Create(Project.MainSource, Applied(MainText, Edit), False)];
    end;
    if not TUnitTemplates.ProjectEdit(ProjectText,
      TTestUnits.RelativePath(TProjectPaths.DirectoryOf(Project.FileName), FileName), '', TFormKind.Form, False,
      Edit) then
      Exit(Fail(Format('%s hat keinen Platz für DCCReference', [ExtractFileName(Project.FileName)]), AReason));
    Files := Files + [TSlashFile.Create(Project.FileName, Applied(ProjectText, Edit), False)];
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
      Host.WriteFiles(Uri, Files, FileName);
    end);
  Result := True;
end;

function ExecuteUnit(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Name: string;
begin
  AEdits := nil;
  Name := UnitNameOf(AContext.Arguments);
  if Name = '' then
    Exit(Fail('Erwartet wird ein Unit-Name, z. B. /unit Kunden.Daten', AReason));
  Result := AddNewUnit(AContext, Name, NewUnitText(Name), True, AEdits, AReason);
end;

{ /component }

/// <summary>Unit, die die Klasse AClassName deklariert, aus dem Index; '' ohne.</summary>
function ClassUnit(const AContext: TSlashContext; const AClassName: string): string;
var
  Location: TSymbolLocation;
begin
  Result := '';
  if AContext.Index = nil then
    Exit;
  for Location in AContext.Index.FindSymbols(AClassName) do
    if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') and
      (Location.UnitName <> '') then
      Exit(Location.UnitName);
end;

function ExecuteComponent(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
const
  Usage = 'Erwartet wird /component TMyButton : TButton';
var
  ClassName, Ancestor, AncestorUnit, UnitName, Palette: string;
  Colon: Integer;
begin
  AEdits := nil;
  Colon := Pos(':', AContext.Arguments);
  if Colon > 0 then
  begin
    ClassName := Trim(Copy(AContext.Arguments, 1, Colon - 1));
    Ancestor := Trim(Copy(AContext.Arguments, Colon + 1, MaxInt));
  end
  else
  begin
    ClassName := Trim(AContext.Arguments);
    Ancestor := 'TComponent';
  end;
  if not IsValidIdent(ClassName) or not IsValidIdent(Ancestor, True) then
    Exit(Fail(Usage, AReason));
  // TComponent steht in System.Classes, das das Gerüst immer einträgt.
  AncestorUnit := '';
  if not SameText(Ancestor, 'TComponent') then
  begin
    AncestorUnit := ClassUnit(AContext, Ancestor);
    if AncestorUnit = '' then
      Exit(Fail(Format('Die Klasse %s kennt der Index nicht', [Ancestor]), AReason));
    if SameText(AncestorUnit, 'System.Classes') or SameText(AncestorUnit, 'System.SysUtils') then
      AncestorUnit := '';
  end;
  UnitName := TUnitTemplates.InstanceName(ClassName);
  Palette := '';
  if AContext.Host <> nil then
    Palette := Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.ComponentPalette));
  if Palette = '' then
    Palette := TSlashSettings.DefaultPalette;
  Result := AddNewUnit(AContext, UnitName, TUnitTemplates.ComponentUnit(UnitName, ClassName, Ancestor,
    AncestorUnit, Palette, #13#10), False, AEdits, AReason);
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

{ /test }

/// <summary>Zeile von "end" der Klassendeklaration ASymbol; -1 ohne.</summary>
function ClassEndLine(const ALines: TArray<string>; const ASymbol: TIndexSymbol): Integer;
begin
  Result := ASymbol.Range.EndPos.Line;
  if Result > High(ALines) then
    Result := High(ALines);
  while (Result > ASymbol.Range.StartPos.Line) and not StartsText('end', TrimLeft(ALines[Result])) do
    Dec(Result);
  if Result <= ASymbol.Range.StartPos.Line then
    Result := -1;
end;

/// <summary>Zeile, vor der neue Rümpfe stehen: initialization, finalization bzw. "end."; -1 ohne.</summary>
function BodyLine(const ALines: TArray<string>): Integer;
var
  Index: Integer;
  Line: string;
begin
  Result := -1;
  for Index := High(ALines) downto 0 do
  begin
    Line := LowerCase(Trim(ALines[Index]));
    if (Result < 0) and Line.StartsWith('end.') then
      Result := Index
    else if (Result >= 0) and ((Line = 'initialization') or (Line = 'finalization')) then
      Result := Index;
  end;
end;

/// <summary>Trägt in die Testunit AText den Test ATestName (nummeriert, wenn es ihn gibt) für ATarget in die
/// Testklasse AFixture ein, samt Rumpf und AUnitName im uses. AOnlyIfMissing: einen vorhandenen Test
/// gleichen Namens nicht noch einmal anlegen (frisches Gerüst).</summary>
function AddTestMethod(const AText, AFixture, ATestName, ATarget, AUnitName: string; AOnlyIfMissing: Boolean;
  out ANewText, AReason: string): Boolean;
var
  Tree: TSyntaxTree;
  Index: TUnitIndex;
  Symbol, Fixture: TIndexSymbol;
  Found: Boolean;
  Lines: TArray<string>;
  Names: TArray<string>;
  LineBreak, Name, Indent: string;
  EndLine, Body, Number: Integer;
  Tokens: TArray<TPascalToken>;
  UsesEdit: TTextEdit;
  HasUses: Boolean;
begin
  ANewText := '';
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    Index := TIndexExtractor.Extract(Tree, '');
  finally
    Tree.Free;
  end;
  Found := False;
  Fixture := Default(TIndexSymbol);
  for Symbol in Index.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') then
    begin
      if SameText(Symbol.Name, AFixture) then
      begin
        Fixture := Symbol;
        Found := True;
        Break;
      end;
      if not Found then
      begin
        Fixture := Symbol;
        Found := True;
      end;
    end;
  if not Found then
    Exit(Fail('Die Testunit hat keine Testklasse', AReason));
  Names := nil;
  for Symbol in Index.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Method) and SameText(Symbol.Container, Fixture.Name) then
      Names := Names + [Symbol.Name];
  Name := ATestName;
  if MatchText(Name, Names) and AOnlyIfMissing then
  begin
    ANewText := AText;
    Exit(True);
  end;
  Number := 1;
  while MatchText(Name, Names) do
  begin
    Inc(Number);
    Name := ATestName + IntToStr(Number);
  end;
  LineBreak := TTextLines.LineBreakOf(AText);
  Lines := AText.Split([LineBreak]);
  EndLine := ClassEndLine(Lines, Fixture);
  Body := BodyLine(Lines);
  if (EndLine < 0) or (Body < 0) then
    Exit(Fail('Testklasse oder Ende der Testunit nicht gefunden', AReason));
  // uses vor dem Einfügen bestimmen; der Edit liegt vor allen anderen Stellen.
  Tokens := TPascalLexer.Tokenize(AText);
  HasUses := TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Tokens), AUnitName, nil) or
    not TUsesClauses.AddUnit(Tokens, TLineTable.Build(AText).OffsetAt(Fixture.Range.StartPos), AUnitName, LineBreak,
    UsesEdit);
  Indent := Copy(Lines[EndLine], 1, Length(Lines[EndLine]) - Length(TrimLeft(Lines[EndLine]))) + '  ';
  Lines[Body] := 'procedure ' + Fixture.Name + '.' + Name + ';' + LineBreak + 'begin' + LineBreak +
    '  Assert.Fail(' + QuotedStr('Test für ' + ATarget + ' fehlt noch') + ');' + LineBreak + 'end;' + LineBreak +
    LineBreak + Lines[Body];
  Lines[EndLine] := Indent + '[Test]' + LineBreak + Indent + 'procedure ' + Name + ';' + LineBreak + Lines[EndLine];
  ANewText := string.Join(LineBreak, Lines);
  if not HasUses then
    ANewText := Applied(ANewText, UsesEdit);
  Result := True;
end;

function ExecuteTest(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Target: TSlashTestUnit;
  RoutineName, ClassName, MethodName, UnitName, TestText, NewText, MainText, ProjectFile, ProjectText,
    Relative, Uri: string;
  Dot, Bracket: Integer;
  Files: TArray<TSlashFile>;
  Edit: TTextEdit;
  Host: ISlashHost;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/test gilt nur im Rumpf einer Methode oder Routine', AReason));
    if AContext.Host = nil then
      Exit(Fail('/test braucht den Editor', AReason));
    RoutineName := Routine.Name;
    Dot := LastDelimiter('.', RoutineName);
    ClassName := Copy(RoutineName, 1, Dot - 1);
    MethodName := Copy(RoutineName, Dot + 1, MaxInt);
    Bracket := Pos('<', ClassName);
    if Bracket > 0 then
      ClassName := Copy(ClassName, 1, Bracket - 1);
    UnitName := Source.UnitIndex.UnitName;
    if (UnitName = '') or (MethodName = '') then
      Exit(Fail('/test gilt nur in einer Unit', AReason));
    if not AContext.Host.TestUnit(AContext.Uri, Source.Text, Target) then
      Exit(Fail(Target.Reason, AReason));
    if Target.Exists then
    begin
      if not AContext.Host.ReadFile(Target.FileName, TestText) then
        Exit(Fail(Format('%s lässt sich nicht lesen', [ExtractFileName(Target.FileName)]), AReason));
    end
    else
      TestText := TTestUnits.UnitText(Target.UnitName, Source.UnitIndex, ClassName, #13#10);
    if ClassName <> '' then
      RoutineName := ClassName + '.' + MethodName;
    if not AddTestMethod(TestText, TTestUnits.FixtureName(ClassName, UnitName), 'Test' + MethodName, RoutineName,
      UnitName, not Target.Exists, NewText, AReason) then
      Exit(False);
    Files := [TSlashFile.Create(Target.FileName, NewText, not Target.Exists)];
    if not Target.Exists then
    begin
      // Ins Testprojekt wie die Code-Aktion aus #274: uses der .dpr und DCCReference der .dproj.
      Relative := TTestUnits.RelativePath(TProjectPaths.DirectoryOf(Target.TestProgram), Target.FileName);
      if AContext.Host.ReadFile(Target.TestProgram, MainText) and
        TUnitTemplates.UnitProgramEdit(MainText, Target.UnitName, Relative, Edit) then
        Files := Files + [TSlashFile.Create(Target.TestProgram, Applied(MainText, Edit), False)];
      ProjectFile := ChangeFileExt(Target.TestProgram, '.dproj');
      if AContext.Host.ReadFile(ProjectFile, ProjectText) and (Pos('"' + Relative + '"', ProjectText) = 0) and
        TUnitTemplates.ProjectEdit(ProjectText, Relative, '', TFormKind.Form, False, Edit) then
        Files := Files + [TSlashFile.Create(ProjectFile, Applied(ProjectText, Edit), False)];
    end;
    AEdits := [Source.RemoveCommand];
  finally
    Source.Free;
  end;
  Host := AContext.Host;
  Uri := AContext.Uri;
  AContext.Defer(
    procedure
    begin
      Host.WriteFiles(Uri, Files, Target.FileName);
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

procedure RegisterProjectCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('define', 'Symbol in DCC_Define der aktiven Konfiguration eintragen', '/define TEST',
    ExecuteDefine));
  ARegister(Command('define!', 'Symbol in DCC_Define aller Konfigurationen eintragen', '/define! TEST',
    ExecuteDefine));
  ARegister(Command('searchpath', 'Ordner in den Suchpfad des Projekts eintragen',
    '/searchpath Source\Common', ExecuteSearchPath));
  ARegister(Command('config', 'Konfiguration und Plattform umschalten', '/config Release Win64',
    ExecuteConfig));
  ARegister(Command('dfm', 'Zur Stelle in der Formulardatei springen', '/dfm', ExecuteDfm));
  ARegister(Command('unit', 'Neue Unit anlegen, ins Projekt eintragen und öffnen', '/unit Kunden.Daten',
    ExecuteUnit));
  ARegister(Command('open', 'Unit aus dem Suchpfad öffnen', '/open System.SysUtils', ExecuteOpen));
  ARegister(Command('component', 'Neue Komponenten-Unit mit Register anlegen und ins Projekt eintragen',
    '/component TMyButton : TButton', ExecuteComponent));
  ARegister(Command('test', 'DUnitX-Test für die aktuelle Methode anlegen, Testunit bei Bedarf',
    '/test', ExecuteTest));
end;

end.
