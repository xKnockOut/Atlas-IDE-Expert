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
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TProjectCommandsText = (NoDprojIsLoadedFor, CannotBeRead, ConfigurationIsNotIn, HasNoSectionFor, ExpectedIsASymbolE,
    ExpectedIsAFolderRelative, TheFolderDoesNotExist, ExpectedAreConfigurationAndOr, IsNeitherAConfigurationNor,
    DfmNeedsTheEditor, DfmOnlyAppliesInA, ThereIsNoDfmOr, IsNotATextDFM, NeedsTheEditor, NeedsASavedFile,
    HasNoUsesOrContains, HasNoRoomForDCCReference, ExpectedIsAUnitName, TheIndexDoesNotKnow, ExpectedIsAUnitName2,
    OpenNeedsTheEditor, TheUnitIsNeitherIn, TestForStillMissing, TheTestUnitHasNo, TestClassOrEndOf,
    TestOnlyAppliesInThe, TestNeedsTheEditor, TestOnlyAppliesInA, AddASymbolToDCC, AddAFolderToThe,
    SwitchConfigurationAndPlatform, JumpToThePositionIn, CreateANewUnitAdd, OpenAUnitFromThe, CreateANewComponentUnit,
    CreateADUnitXTestFor, NeedsALoadedProject, IsAlreadyIn, ConfigNeedsALoadedProject, IsAlreadyInTheProject,
    AlreadyExists, AddASymbolToDCC2, UnitCustomersData, ExpectedIsComponentTMyButtonTButton);

const
  cTexts: array[TProjectCommandsText] of TAtlasText = (
    (De: 'Zu dieser Datei ist keine .dproj geladen'; En: 'No .dproj is loaded for this file'),
    (De: '%s lässt sich nicht lesen'; En: '%s cannot be read'),
    (De: 'Konfiguration %s steht nicht in %s'; En: 'Configuration %s is not in %s'),
    (De: '%s hat keinen Abschnitt für %s'; En: '%s has no section for %s'),
    (De: 'Erwartet wird ein Symbol, z. B. /define TEST'; En: 'Expected is a symbol, e.g. /define TEST'),
    (De: 'Erwartet wird ein Ordner relativ zur .dproj, z. B. /searchpath Source\Common';
     En: 'Expected is a folder relative to the .dproj, e.g. /searchpath Source\Common'),
    (De: 'Den Ordner %s gibt es nicht'; En: 'The folder %s does not exist'),
    (De: 'Erwartet werden Konfiguration und/oder Plattform, z. B. /config Release Win64';
     En: 'Expected are configuration and/or platform, e.g. /config Release Win64'),
    (De: '%s ist weder Konfiguration (%s) noch Plattform (%s)';
     En: '%s is neither a configuration (%s) nor a platform (%s)'),
    (De: '/dfm braucht den Editor'; En: '/dfm needs the editor'),
    (De: '/dfm gilt nur in einer Methode der Formularklasse'; En: '/dfm only applies in a method of the form class'),
    (De: 'Neben der Unit liegt keine .dfm oder .fmx'; En: 'There is no .dfm or .fmx next to the unit'),
    (De: '%s ist keine Text-DFM'; En: '%s is not a text DFM'),
    (De: '/%s braucht den Editor'; En: '/%s needs the editor'),
    (De: '/%s braucht eine gespeicherte Datei'; En: '/%s needs a saved file'),
    (De: '%s hat kein uses bzw. contains für %s'; En: '%s has no uses or contains for %s'),
    (De: '%s hat keinen Platz für DCCReference'; En: '%s has no room for DCCReference'),
    (De: 'Erwartet wird ein Unit-Name, z. B. /unit Kunden.Daten';
     En: 'Expected is a unit name, e.g. /unit Customers.Data'),
    (De: 'Die Klasse %s kennt der Index nicht'; En: 'The index does not know the class %s'),
    (De: 'Erwartet wird ein Unit-Name, z. B. /open System.SysUtils';
     En: 'Expected is a unit name, e.g. /open System.SysUtils'),
    (De: '/open braucht den Editor'; En: '/open needs the editor'),
    (De: 'Die Unit %s steht weder im Index noch im Suchpfad';
     En: 'The unit %s is neither in the index nor in the search path'),
    (De: 'Test für %s fehlt noch'; En: 'Test for %s still missing'),
    (De: 'Die Testunit hat keine Testklasse'; En: 'The test unit has no test class'),
    (De: 'Testklasse oder Ende der Testunit nicht gefunden'; En: 'Test class or end of the test unit not found'),
    (De: '/test gilt nur im Rumpf einer Methode oder Routine';
     En: '/test only applies in the body of a method or routine'),
    (De: '/test braucht den Editor'; En: '/test needs the editor'),
    (De: '/test gilt nur in einer Unit'; En: '/test only applies in a unit'),
    (De: 'Symbol in DCC_Define der aktiven Konfiguration eintragen';
     En: 'Add a symbol to DCC_Define of the active configuration'),
    (De: 'Ordner in den Suchpfad des Projekts eintragen'; En: 'Add a folder to the search path of the project'),
    (De: 'Konfiguration und Plattform umschalten'; En: 'Switch configuration and platform'),
    (De: 'Zur Stelle in der Formulardatei springen'; En: 'Jump to the position in the form file'),
    (De: 'Neue Unit anlegen, ins Projekt eintragen und öffnen';
     En: 'Create a new unit, add it to the project and open it'),
    (De: 'Unit aus dem Suchpfad öffnen'; En: 'Open a unit from the search path'),
    (De: 'Neue Komponenten-Unit mit Register anlegen und ins Projekt eintragen';
     En: 'Create a new component unit with Register and add it to the project'),
    (De: 'DUnitX-Test für die aktuelle Methode anlegen, Testunit bei Bedarf';
     En: 'Create a DUnitX test for the current method, test unit if needed'),
    (De: '/%s braucht ein geladenes Projekt'; En: '/%s needs a loaded project'),
    (De: '%s steht schon in %s (%s)'; En: '%s is already in %s (%s)'),
    (De: '/config braucht ein geladenes Projekt'; En: '/config needs a loaded project'),
    (De: '%s steht schon im Projekt'; En: '%s is already in the project'),
    (De: '%s gibt es schon'; En: '%s already exists'),
    (De: 'Symbol in DCC_Define aller Konfigurationen eintragen';
     En: 'Add a symbol to DCC_Define of all configurations'),
    (De: '/unit Kunden.Daten'; En: '/unit Customers.Data'),
    (De: 'Erwartet wird /component TMyButton : TButton'; En: 'Expected is /component TMyButton : TButton'));

{$SCOPEDENUMS OFF}

/// <summary>Projekt und .dproj-Text zur Datei des Befehls; False mit Grund.</summary>
function LoadProject(const AContext: TSlashContext; out AProject: TProjectInfo; out AText, AReason: string): Boolean;
begin
  AText := '';
  if AContext.Host = nil then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.NeedsALoadedProject].Fmt([AContext.Name]), AReason));
  end;
  if not AContext.Host.Project(AContext.Uri, AProject) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.NoDprojIsLoadedFor].Text, AReason));
  end;
  if not AContext.Host.ReadFile(AProject.FileName, AText) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.CannotBeRead].Fmt([ExtractFileName(AProject.FileName)]), AReason));
  end;
  Result := True;
end;

type
  /// <summary>Eintrag in eine Liste der .dproj: Wert AValue in die Eigenschaft PropertyName der Konfiguration
  /// Config.</summary>
  TListEntry = record
    Config: string;
    PropertyName: string;
    Value: string;
    class function Create(const AConfig, APropertyName, AValue: string): TListEntry; static;
  end;

class function TListEntry.Create(const AConfig, APropertyName, AValue: string): TListEntry;
begin
  Result.Config := AConfig;
  Result.PropertyName := APropertyName;
  Result.Value := AValue;
end;

/// <summary>Edit, der die Befehlszeile entfernt.</summary>
function CommandRemoval(const AContext: TSlashContext): TArray<TTextEdit>;
var
  mSource: TCommandSource;
begin
  mSource := TCommandSource.Create(AContext);
  try
    Result := [mSource.RemoveCommand];
  finally
    mSource.Free;
  end;
end;

/// <summary>Merkt vor, AFiles über den Host zu schreiben und AOpen danach zu öffnen.</summary>
procedure WriteFilesLater(const AContext: TSlashContext; const AFiles: TArray<TSlashFile>; const AOpen: string);
var
  mHost: ISlashHost;
  mUri, mOpen: string;
  mFiles: TArray<TSlashFile>;
begin
  mHost := AContext.Host;
  mUri := AContext.Uri;
  mFiles := AFiles;
  mOpen := AOpen;
  AContext.Defer(
    procedure
    begin
      mHost.WriteFiles(mUri, mFiles, mOpen);
    end);
end;

/// <summary>Trägt AEntry in die .dproj AText ein und merkt das Schreiben vor.</summary>
function AddToProject(const AContext: TSlashContext; const AProject: TProjectInfo; const AText: string;
  const AEntry: TListEntry; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mKey, mNewText, mUri: string;
  mHost: ISlashHost;
begin
  mKey := TDprojEditor.ConfigKey(AText, AEntry.Config);
  if mKey = '' then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.ConfigurationIsNotIn].Fmt([AEntry.Config,
      ExtractFileName(AProject.FileName)]),
      AReason));
  end;
  case TDprojEditor.AddToList(AText, mKey, AEntry.PropertyName, AEntry.Value, mNewText) of
    TDprojEditResult.Present:
      Exit(Fail(cTexts[TProjectCommandsText.IsAlreadyIn].Fmt([AEntry.Value, AEntry.PropertyName, AEntry.Config]),
        AReason));
    TDprojEditResult.NoGroup:
      Exit(Fail(cTexts[TProjectCommandsText.HasNoSectionFor].Fmt([ExtractFileName(AProject.FileName), AEntry.Config]),
        AReason));
  end;
  AEdits := CommandRemoval(AContext);
  mHost := AContext.Host;
  mUri := AContext.Uri;
  AContext.Defer(
    procedure
    begin
      mHost.WriteProject(mUri, mNewText);
    end);
  Result := True;
end;

{ /define }

function ExecuteDefine(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mProject: TProjectInfo;
  mText, mConfig: string;
begin
  AEdits := nil;
  if not IsValidIdent(AContext.Arguments) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.ExpectedIsASymbolE].Text, AReason));
  end;
  if not LoadProject(AContext, mProject, mText, AReason) then
  begin
    Exit(False);
  end;
  if EndsStr('!', AContext.Name) then
  begin
    mConfig := 'Base';
  end
  else
  begin
    mConfig := mProject.Config;
  end;
  Result := AddToProject(AContext, mProject, mText, TListEntry.Create(mConfig, 'DCC_Define', AContext.Arguments), AEdits,
    AReason);
end;

{ /searchpath }

function ExecuteSearchPath(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mProject: TProjectInfo;
  mText, mPath: string;
begin
  AEdits := nil;
  mPath := AContext.Arguments;
  if (Length(mPath) >= 2) and CharInSet(mPath[1], ['''', '"']) and (mPath[Length(mPath)] = mPath[1]) then
  begin
    mPath := Copy(mPath, 2, Length(mPath) - 2);
  end;
  if mPath = '' then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.ExpectedIsAFolderRelative].Text, AReason));
  end;
  if not LoadProject(AContext, mProject, mText, AReason) then
  begin
    Exit(False);
  end;
  if not AContext.Host.DirectoryExists(TProjectPaths.Combine(TProjectPaths.DirectoryOf(mProject.FileName), mPath)) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.TheFolderDoesNotExist].Fmt([mPath]), AReason));
  end;
  Result := AddToProject(AContext, mProject, mText, TListEntry.Create('Base', 'DCC_UnitSearchPath', mPath), AEdits,
    AReason);
end;

{ /config }

function ExecuteConfig(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mProject: TProjectInfo;
  mWord, mConfig, mPlatform, mUri: string;
  mHost: ISlashHost;
  mSource: TCommandSource;
begin
  AEdits := nil;
  if AContext.Arguments = '' then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.ExpectedAreConfigurationAndOr].Text, AReason));
  end;
  if AContext.Host = nil then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.ConfigNeedsALoadedProject].Text, AReason));
  end;
  if not AContext.Host.Project(AContext.Uri, mProject) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.NoDprojIsLoadedFor].Text, AReason));
  end;
  mConfig := '';
  mPlatform := '';
  // Reihenfolge egal: jedes Wort ist entweder Konfiguration oder Plattform des Projekts.
  for mWord in AContext.Arguments.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    if (mConfig = '') and (IndexText(mWord, mProject.Configs) >= 0) then
    begin
      mConfig := mProject.Configs[IndexText(mWord, mProject.Configs)];
    end
    else if (mPlatform = '') and (IndexText(mWord, mProject.Platforms) >= 0) then
    begin
      mPlatform := mProject.Platforms[IndexText(mWord, mProject.Platforms)];
    end
    else
    begin
      Exit(Fail(cTexts[TProjectCommandsText.IsNeitherAConfigurationNor].Fmt([mWord, string.Join(', ', mProject.Configs),
        string.Join(', ', mProject.Platforms)]), AReason));
    end;
  end;
  mSource := TCommandSource.Create(AContext);
  try
    AEdits := [mSource.RemoveCommand];
  finally
    mSource.Free;
  end;
  mHost := AContext.Host;
  mUri := AContext.Uri;
  AContext.Defer(
    procedure
    begin
      mHost.SelectBuild(mUri, mConfig, mPlatform);
    end);
  Result := True;
end;

{ /dfm }

/// <summary>Ereignis mit Wert AMethod in AObject oder darunter; False ohne.</summary>
function FindEvent(AObject: TDfmObject; const AMethod: string; out ARange: TTextRange): Boolean;
var
  mProp: TDfmProperty;
  mChild: TDfmObject;
begin
  for mProp in AObject.Properties do
  begin
    if mProp.IsEvent and SameText(Trim(mProp.Value), AMethod) then
    begin
      ARange := TTextRange.Create(mProp.NameRange.StartPos.Line, mProp.NameRange.StartPos.Character,
        mProp.ValueRange.EndPos.Line, mProp.ValueRange.EndPos.Character);
      Exit(True);
    end;
  end;
  for mChild in AObject.Children do
  begin
    if FindEvent(mChild, AMethod, ARange) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ExecuteDfm(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mMethod, mFileName, mFormFile, mFormText, mExtension: string;
  mDocument: TDfmDocument;
  mTarget: TTextRange;
  mHost: ISlashHost;
begin
  AEdits := nil;
  if AContext.Host = nil then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.DfmNeedsTheEditor].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if (mRoutine = nil) or (Pos('.', mRoutine.Name) = 0) then
    begin
      Exit(Fail(cTexts[TProjectCommandsText.DfmOnlyAppliesInA].Text, AReason));
    end;
    mMethod := Copy(mRoutine.Name, LastDelimiter('.', mRoutine.Name) + 1, MaxInt);
    mFileName := TDocumentUris.ToPath(AContext.Uri);
    mFormFile := '';
    for mExtension in TArray<string>.Create('.dfm', '.fmx') do
    begin
      if (mFormFile = '') and AContext.Host.ReadFile(ChangeFileExt(mFileName, mExtension), mFormText) then
      begin
        mFormFile := ChangeFileExt(mFileName, mExtension);
      end;
    end;
    if mFormFile = '' then
    begin
      Exit(Fail(cTexts[TProjectCommandsText.ThereIsNoDfmOr].Text, AReason));
    end;
    mDocument := TDfmParser.Parse(mFormText);
    try
      if mDocument.Root = nil then
      begin
        Exit(Fail(cTexts[TProjectCommandsText.IsNotATextDFM].Fmt([ExtractFileName(mFormFile)]), AReason));
      end;
      // Ereignis-Handler: zur Zuweisung; sonst Formularmethode: zum Formular selbst.
      if not FindEvent(mDocument.Root, mMethod, mTarget) then
      begin
        mTarget := mDocument.Root.NameRange;
      end;
    finally
      mDocument.Free;
    end;
    AEdits := [mSource.RemoveCommand];
  finally
    mSource.Free;
  end;
  mHost := AContext.Host;
  AContext.Defer(
    procedure
    begin
      mHost.ShowDocument(mFormFile, mTarget);
    end);
  Result := True;
end;

{ /unit }

/// <summary>AText mit AEdit angewandt.</summary>
function Applied(const AText: string; const AEdit: TTextEdit): string;
var
  mTable: TLineTable;
  mStart, mStop: Integer;
begin
  mTable := TLineTable.Build(AText);
  mStart := mTable.OffsetAt(AEdit.Range.StartPos);
  mStop := mTable.OffsetAt(AEdit.Range.EndPos);
  Result := Copy(AText, 1, mStart) + AEdit.NewText + Copy(AText, mStop + 1, MaxInt);
end;

/// <summary>Name ohne Endung .pas; '' wenn kein gültiger (auch gepunkteter) Bezeichner.</summary>
function UnitNameOf(const AArguments: string): string;
begin
  Result := Trim(AArguments);
  if EndsText('.pas', Result) then
  begin
    Result := Copy(Result, 1, Length(Result) - 4);
  end;
  if not IsValidIdent(Result, True) then
  begin
    Result := '';
  end;
end;

/// <summary>Leere Unit wie Datei > Neu > Unit der IDE.</summary>
function NewUnitText(const AUnitName: string): string;
const
  cLB = #13#10;
begin
  Result := 'unit ' + AUnitName + ';' + cLB + cLB + 'interface' + cLB + cLB + 'implementation' + cLB + cLB + 'end.' + cLB;
end;

/// <summary>Zeilenende für neue Units: format.endOfLine, sonst das der Datei des Befehls (CRLF ohne
/// LF-Datei).</summary>
function EndOfLineFor(const AContext: TSlashContext): string;
begin
  Result := AContext.Style.EndOfLine;
  if Result = '' then
  begin
    Result := #13#10;
    if (Pos(#10, AContext.Text) > 0) and (Pos(#13#10, AContext.Text) = 0) then
    begin
      Result := #10;
    end;
  end;
end;

/// <summary>Einrückung je Ebene nach dem Formatstil: Tabulator, IndentSize Leerzeichen oder zwei.</summary>
function LevelUnitOf(const AStyle: TFormatStyle): string;
begin
  if AStyle.UseTabs then
  begin
    Result := #9;
  end
  else if AStyle.IndentSize >= 1 then
  begin
    Result := StringOfChar(' ', AStyle.IndentSize);
  end
  else
  begin
    Result := '  ';
  end;
end;

/// <summary>ALine mit ALevelUnit je zwei führenden Leerzeichen; Leerzeilen bleiben, wie sie sind.</summary>
function ReindentedLine(const ALine, ALevelUnit: string): string;
var
  mSpaces: Integer;
begin
  mSpaces := 0;
  while (mSpaces < Length(ALine)) and (ALine[mSpaces + 1] = ' ') do
  begin
    Inc(mSpaces);
  end;
  Result := ALine;
  if mSpaces < Length(ALine) then
  begin
    Result := DupeString(ALevelUnit, mSpaces div 2) + StringOfChar(' ', mSpaces mod 2) + Copy(ALine, mSpaces + 1,
      MaxInt);
  end;
end;

/// <summary>Neue Unit im Stil des Projekts (#299, #121, #43): Zeilenende aus format.endOfLine bzw. der Datei
/// des Befehls, Einrückung je Ebene (Vorlagen rücken mit zwei Leerzeichen ein) und Schreibweise nach dem
/// Formatstil.</summary>
function StyledUnitText(const AContext: TSlashContext; const AText: string): string;
var
  mStyle: TFormatStyle;
  mLines: TArray<string>;
  mLevelUnit: string;
  mIndex: Integer;
begin
  mStyle := AContext.Style;
  mStyle.EndOfLine := EndOfLineFor(AContext);
  mLevelUnit := LevelUnitOf(mStyle);
  mLines := TTextLines.SplitLines(AText);
  if mLevelUnit <> '  ' then
  begin
    for mIndex := 0 to High(mLines) do
    begin
      mLines[mIndex] := ReindentedLine(mLines[mIndex], mLevelUnit);
    end;
  end;
  Result := TTextLines.JoinLines(mLines, mStyle.EndOfLine);
  Result := TFormatter.FormatText(Result, TPascalLexer.Tokenize(Result), mStyle);
end;

type
  /// <summary>Projekt zur Datei des Befehls für /unit und /component; Loaded = Projekt und .dproj-Text da.</summary>
  TUnitProject = record
    Info: TProjectInfo;
    Text: string;
    Loaded: Boolean;
  end;

/// <summary>Steht die Unit AName schon im Projekt AInfo?</summary>
function InProject(const AInfo: TProjectInfo; const AName: string): Boolean;
var
  mItem: TProjectUnit;
begin
  for mItem in AInfo.Units do
  begin
    if SameText(mItem.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Lädt das Projekt nach AProject; ANeedsProject: ohne Projekt nicht anlegen. Grund, wenn die Unit AName
/// nicht angelegt werden kann, sonst ''.</summary>
function LoadUnitProject(const AContext: TSlashContext; const AName: string; ANeedsProject: Boolean;
  out AProject: TUnitProject): string;
var
  mReason: string;
begin
  AProject := Default(TUnitProject);
  Result := '';
  if ANeedsProject then
  begin
    AProject.Loaded := LoadProject(AContext, AProject.Info, AProject.Text, mReason);
    if not AProject.Loaded then
    begin
      Result := mReason;
    end;
  end
  else if AContext.Host = nil then
  begin
    Result := cTexts[TProjectCommandsText.NeedsTheEditor].Fmt([AContext.Name]);
  end
  else
  begin
    AProject.Loaded := AContext.Host.Project(AContext.Uri, AProject.Info) and
      AContext.Host.ReadFile(AProject.Info.FileName, AProject.Text);
  end;
  if (Result = '') and AProject.Loaded and InProject(AProject.Info, AName) then
  begin
    Result := cTexts[TProjectCommandsText.IsAlreadyInTheProject].Fmt([AName]);
  end;
end;

/// <summary>Datei der neuen Unit AName neben der Datei des Befehls, ohne Datei neben der .dproj. Grund, wenn sie
/// sich nicht anlegen lässt, sonst ''.</summary>
function NewUnitFileIssue(const AContext: TSlashContext; const AProject: TUnitProject; const AName: string;
  out AFileName: string): string;
var
  mFolder, mExisting: string;
begin
  AFileName := '';
  if AContext.Uri <> '' then
  begin
    mFolder := TProjectPaths.DirectoryOf(TDocumentUris.ToPath(AContext.Uri));
  end
  else if AProject.Loaded then
  begin
    mFolder := TProjectPaths.DirectoryOf(AProject.Info.FileName);
  end
  else
  begin
    Exit(cTexts[TProjectCommandsText.NeedsASavedFile].Fmt([AContext.Name]));
  end;
  AFileName := TProjectPaths.Combine(mFolder, AName + '.pas');
  Result := '';
  if AContext.Host.ReadFile(AFileName, mExisting) then
  begin
    Result := cTexts[TProjectCommandsText.AlreadyExists].Fmt([ExtractFileName(AFileName)]);
  end;
end;

/// <summary>Hängt die geänderte Hauptdatei (uses der .dpr bzw. contains der .dpk) und .dproj für die Unit AName in
/// AFileName an AFiles an. Grund, wenn das nicht geht, sonst ''.</summary>
function ProjectFileEdits(const AContext: TSlashContext; const AProject: TUnitProject; const AName,
  AFileName: string; var AFiles: TArray<TSlashFile>): string;
var
  mMainSource, mMainText: string;
  mEdit: TTextEdit;
begin
  Result := '';
  if not AProject.Loaded then
  begin
    Exit;
  end;
  mMainSource := AProject.Info.MainSource;
  if (mMainSource <> '') and AContext.Host.ReadFile(mMainSource, mMainText) then
  begin
    if not TUnitTemplates.UnitProgramEdit(mMainText, AName,
      TTestUnits.RelativePath(TProjectPaths.DirectoryOf(mMainSource), AFileName), mEdit) then
    begin
      Exit(cTexts[TProjectCommandsText.HasNoUsesOrContains].Fmt([ExtractFileName(mMainSource), AName]));
    end;
    AFiles := AFiles + [TSlashFile.Create(mMainSource, Applied(mMainText, mEdit), False)];
  end;
  if TUnitTemplates.ProjectEdit(AProject.Text,
    TTestUnits.RelativePath(TProjectPaths.DirectoryOf(AProject.Info.FileName), AFileName), '', TFormKind.Form,
    False, mEdit) then
  begin
    AFiles := AFiles + [TSlashFile.Create(AProject.Info.FileName, Applied(AProject.Text, mEdit), False)];
  end
  else
  begin
    Result := cTexts[TProjectCommandsText.HasNoRoomForDCCReference].Fmt([ExtractFileName(AProject.Info.FileName)]);
  end;
end;

/// <summary>Legt AName neben der Datei des Befehls mit AText an, trägt sie in .dpr/.dpk und .dproj ein,
/// wenn ein Projekt geladen ist, und öffnet sie danach. ANeedsProject: ohne Projekt nicht anlegen.</summary>
function AddNewUnit(const AContext: TSlashContext; const AName, AText: string; ANeedsProject: Boolean;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mProject: TUnitProject;
  mFileName: string;
  mFiles: TArray<TSlashFile>;
begin
  AEdits := nil;
  AReason := LoadUnitProject(AContext, AName, ANeedsProject, mProject);
  if AReason = '' then
  begin
    AReason := NewUnitFileIssue(AContext, mProject, AName, mFileName);
  end;
  if AReason = '' then
  begin
    mFiles := [TSlashFile.Create(mFileName, StyledUnitText(AContext, AText), True)];
    AReason := ProjectFileEdits(AContext, mProject, AName, mFileName, mFiles);
  end;
  Result := AReason = '';
  if Result then
  begin
    AEdits := CommandRemoval(AContext);
    WriteFilesLater(AContext, mFiles, mFileName);
  end;
end;

function ExecuteUnit(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mName: string;
begin
  AEdits := nil;
  mName := UnitNameOf(AContext.Arguments);
  if mName = '' then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.ExpectedIsAUnitName].Text, AReason));
  end;
  Result := AddNewUnit(AContext, mName, NewUnitText(mName), True, AEdits, AReason);
end;

{ /component }

/// <summary>Unit, die die Klasse AClassName deklariert, aus dem Index; '' ohne.</summary>
function ClassUnit(const AContext: TSlashContext; const AClassName: string): string;
var
  mLocation: TSymbolLocation;
begin
  Result := '';
  if AContext.Index = nil then
  begin
    Exit;
  end;
  for mLocation in AContext.Index.FindSymbols(AClassName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') and
      (mLocation.UnitName <> '') then
    begin
      Exit(mLocation.UnitName);
    end;
  end;
end;

function ExecuteComponent(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mClassName, mAncestor, mAncestorUnit, mUnitName, mPalette: string;
  mColon: Integer;
begin
  AEdits := nil;
  mColon := Pos(':', AContext.Arguments);
  if mColon > 0 then
  begin
    mClassName := Trim(Copy(AContext.Arguments, 1, mColon - 1));
    mAncestor := Trim(Copy(AContext.Arguments, mColon + 1, MaxInt));
  end
  else
  begin
    mClassName := Trim(AContext.Arguments);
    mAncestor := 'TComponent';
  end;
  if not IsValidIdent(mClassName) or not IsValidIdent(mAncestor, True) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.ExpectedIsComponentTMyButtonTButton].Text, AReason));
  end;
  // TComponent steht in System.Classes, das das Gerüst immer einträgt.
  mAncestorUnit := '';
  if not SameText(mAncestor, 'TComponent') then
  begin
    mAncestorUnit := ClassUnit(AContext, mAncestor);
    if mAncestorUnit = '' then
    begin
      Exit(Fail(cTexts[TProjectCommandsText.TheIndexDoesNotKnow].Fmt([mAncestor]), AReason));
    end;
    if SameText(mAncestorUnit, 'System.Classes') or SameText(mAncestorUnit, 'System.SysUtils') then
    begin
      mAncestorUnit := '';
    end;
  end;
  mUnitName := TUnitTemplates.InstanceName(mClassName);
  mPalette := '';
  if AContext.Host <> nil then
  begin
    mPalette := Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.cComponentPalette));
  end;
  if mPalette = '' then
  begin
    mPalette := TSlashSettings.cDefaultPalette;
  end;
  Result := AddNewUnit(AContext, mUnitName, TUnitTemplates.ComponentUnit(mUnitName, mClassName, mAncestor,
    mAncestorUnit, mPalette, #13#10), False, AEdits, AReason);
end;

{ /open }

/// <summary>Namen, unter denen die Unit AName stehen kann: AName und mit den Namespace-Präfixen von Projekt und
/// Einstellungen.</summary>
function CandidateNames(const AContext: TSlashContext; const AProject: TProjectInfo; AHasProject: Boolean;
  const AName: string): TArray<string>;
var
  mNamespace: string;
begin
  Result := [AName];
  if AHasProject then
  begin
    for mNamespace in AProject.Namespaces do
    begin
      Result := Result + [mNamespace + '.' + AName];
    end;
  end;
  for mNamespace in AContext.Namespaces do
  begin
    Result := Result + [mNamespace + '.' + AName];
  end;
end;

/// <summary>Datei der ersten Unit aus ANames im Index; False ohne.</summary>
function IndexedFile(const AContext: TSlashContext; const ANames: TArray<string>; out AFileName: string): Boolean;
var
  mIndexed: TUnitIndex;
  mName: string;
begin
  AFileName := '';
  if AContext.Index = nil then
  begin
    Exit(False);
  end;
  for mName in ANames do
  begin
    if AContext.Index.FindUnit(mName, mIndexed) and (mIndexed.FileName <> '') then
    begin
      AFileName := mIndexed.FileName;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Datei der ersten im Projekt eingetragenen Unit mit einem Namen aus ANames; False ohne.</summary>
function ProjectUnitFile(const AProject: TProjectInfo; const ANames: TArray<string>; out AFileName: string): Boolean;
var
  mItem: TProjectUnit;
begin
  AFileName := '';
  for mItem in AProject.Units do
  begin
    if (mItem.FileName <> '') and MatchText(mItem.Name, ANames) then
    begin
      AFileName := mItem.FileName;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ordner, in denen /open sucht: der der Datei, dann der der .dproj und die Suchpfade.</summary>
function SearchFolders(const AContext: TSlashContext; const AProject: TProjectInfo;
  AHasProject: Boolean): TArray<string>;
begin
  Result := nil;
  if AContext.Uri <> '' then
  begin
    Result := [TProjectPaths.DirectoryOf(TDocumentUris.ToPath(AContext.Uri))];
  end;
  if AHasProject then
  begin
    Result := Result + [TProjectPaths.DirectoryOf(AProject.FileName)] + AProject.SearchPaths;
  end;
end;

/// <summary>Erste lesbare Datei Name.pas in den Ordnern AFolders; False ohne.</summary>
function FolderFile(const AContext: TSlashContext; const AFolders, ANames: TArray<string>;
  out AFileName: string): Boolean;
var
  mFolder, mName, mText: string;
begin
  AFileName := '';
  for mFolder in AFolders do
  begin
    for mName in ANames do
    begin
      if AContext.Host.ReadFile(TProjectPaths.Combine(mFolder, mName + '.pas'), mText) then
      begin
        AFileName := TProjectPaths.Combine(mFolder, mName + '.pas');
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Datei der Unit AName: Index, eingetragene Units, dann Ordner der Datei und Suchpfade (auch mit
/// Namespace-Präfix); False ohne.</summary>
function FindUnitFile(const AContext: TSlashContext; const AName: string; out AFileName: string): Boolean;
var
  mProject: TProjectInfo;
  mHasProject: Boolean;
  mNames: TArray<string>;
begin
  mHasProject := AContext.Host.Project(AContext.Uri, mProject);
  mNames := CandidateNames(AContext, mProject, mHasProject, AName);
  Result := IndexedFile(AContext, mNames, AFileName);
  if not Result and mHasProject then
  begin
    Result := ProjectUnitFile(mProject, mNames, AFileName);
  end;
  if not Result then
  begin
    Result := FolderFile(AContext, SearchFolders(AContext, mProject, mHasProject), mNames, AFileName);
  end;
end;

function ExecuteOpen(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mName, mFileName: string;
  mHost: ISlashHost;
  mSource: TCommandSource;
begin
  AEdits := nil;
  mName := UnitNameOf(AContext.Arguments);
  if mName = '' then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.ExpectedIsAUnitName2].Text, AReason));
  end;
  if AContext.Host = nil then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.OpenNeedsTheEditor].Text, AReason));
  end;
  if not FindUnitFile(AContext, mName, mFileName) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.TheUnitIsNeitherIn].Fmt([mName]), AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    AEdits := [mSource.RemoveCommand];
  finally
    mSource.Free;
  end;
  mHost := AContext.Host;
  AContext.Defer(
    procedure
    begin
      mHost.ShowDocument(mFileName, TTextRange.Create(0, 0, 0, 0));
    end);
  Result := True;
end;

{ /test }

/// <summary>Zeile von "end" der Klassendeklaration ASymbol; -1 ohne.</summary>
function ClassEndLine(const ALines: TArray<string>; const ASymbol: TIndexSymbol): Integer;
begin
  Result := ASymbol.Range.EndPos.Line;
  if Result > High(ALines) then
  begin
    Result := High(ALines);
  end;
  while (Result > ASymbol.Range.StartPos.Line) and not StartsText('end', TrimLeft(ALines[Result])) do
  begin
    Dec(Result);
  end;
  if Result <= ASymbol.Range.StartPos.Line then
  begin
    Result := -1;
  end;
end;

/// <summary>Zeile, vor der neue Rümpfe stehen: initialization, finalization bzw. "end."; -1 ohne.</summary>
function BodyLine(const ALines: TArray<string>): Integer;
var
  mIndex: Integer;
  mLine: string;
begin
  Result := -1;
  for mIndex := High(ALines) downto 0 do
  begin
    mLine := LowerCase(Trim(ALines[mIndex]));
    if (Result < 0) and mLine.StartsWith('end.') then
    begin
      Result := mIndex;
    end
    else if (Result >= 0) and ((mLine = 'initialization') or (mLine = 'finalization')) then
    begin
      Result := mIndex;
    end;
  end;
end;

type
  /// <summary>Test, den /test einträgt: Name ATestName in der Testklasse Fixture für die Routine Target; UnitName
  /// kommt ins uses. OnlyIfMissing: einen vorhandenen Test gleichen Namens nicht noch einmal anlegen.</summary>
  TTestRequest = record
    Fixture: string;
    TestName: string;
    Target: string;
    UnitName: string;
    OnlyIfMissing: Boolean;
    class function Create(const AFixture, ATestName, ATarget, AUnitName: string;
      AOnlyIfMissing: Boolean): TTestRequest; static;
  end;

class function TTestRequest.Create(const AFixture, ATestName, ATarget, AUnitName: string;
  AOnlyIfMissing: Boolean): TTestRequest;
begin
  Result.Fixture := AFixture;
  Result.TestName := ATestName;
  Result.Target := ATarget;
  Result.UnitName := AUnitName;
  Result.OnlyIfMissing := AOnlyIfMissing;
end;

/// <summary>Index der Unit AText.</summary>
function UnitIndexOf(const AText: string): TUnitIndex;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TIndexExtractor.Extract(mTree, '');
  finally
    mTree.Free;
  end;
end;

/// <summary>Testklasse: die Klasse AFixture, sonst die erste Klasse der Unit; False ohne Klasse.</summary>
function FixtureSymbol(const AIndex: TUnitIndex; const AFixture: string; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  ASymbol := Default(TIndexSymbol);
  Result := False;
  for mSymbol in AIndex.Symbols do
  begin
    if (mSymbol.Kind <> TIndexSymbolKind.ClassType) or (mSymbol.Container <> '') then
    begin
      Continue;
    end;
    if SameText(mSymbol.Name, AFixture) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
    if not Result then
    begin
      ASymbol := mSymbol;
      Result := True;
    end;
  end;
end;

/// <summary>Namen der Methoden der Klasse AFixture.</summary>
function FixtureMethods(const AIndex: TUnitIndex; const AFixture: string): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in AIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Method) and SameText(mSymbol.Container, AFixture) then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

/// <summary>ATestName, bei Gleichnamigen in ANames nummeriert (ATestName2, ATestName3 …).</summary>
function FreeTestName(const ATestName: string; const ANames: TArray<string>): string;
var
  mNumber: Integer;
begin
  Result := ATestName;
  mNumber := 1;
  while MatchText(Result, ANames) do
  begin
    Inc(mNumber);
    Result := ATestName + IntToStr(mNumber);
  end;
end;

/// <summary>Edit, der AUnitName ins uses von AText einträgt; False, wenn sie dort schon steht oder kein Platz ist.
/// Vor dem Einfügen bestimmt; der Edit liegt vor allen anderen Stellen.</summary>
function UsesEditFor(const AText: string; const AFixture: TIndexSymbol; const AUnitName, ALineBreak: string;
  out AEdit: TTextEdit): Boolean;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  Result := not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(mTokens), AUnitName, nil) and
    TUsesClauses.AddUnit(mTokens, TLineTable.Build(AText).OffsetAt(AFixture.Range.StartPos), AUnitName, ALineBreak,
    AEdit);
end;

/// <summary>Rumpf des Tests AName der Klasse AFixture für ATarget vor der Zeile ALine.</summary>
function TestBodyText(const AFixture, AName, ATarget, ALineBreak, ALine: string): string;
begin
  Result := 'procedure ' + AFixture + '.' + AName + ';' + ALineBreak + 'begin' + ALineBreak + '  Assert.Fail(' +
    QuotedStr(cTexts[TProjectCommandsText.TestForStillMissing].Fmt([ATarget])) + ');' + ALineBreak + 'end;' +
      ALineBreak + ALineBreak + ALine;
end;

/// <summary>Deklaration des Tests AName vor der Zeile AEndLine ("end" der Klasse), eine Ebene tiefer.</summary>
function TestDeclarationText(const AName, ALineBreak, AEndLine: string): string;
var
  mIndent: string;
begin
  mIndent := Copy(AEndLine, 1, Length(AEndLine) - Length(TrimLeft(AEndLine))) + '  ';
  Result := mIndent + '[Test]' + ALineBreak + mIndent + 'procedure ' + AName + ';' + ALineBreak + AEndLine;
end;

/// <summary>Trägt in die Testunit AText den Test aus ARequest (nummeriert, wenn es ihn gibt) in die Testklasse
/// ein, samt Rumpf und Unit im uses.</summary>
function AddTestMethod(const AText: string; const ARequest: TTestRequest; out ANewText, AReason: string): Boolean;
var
  mIndex: TUnitIndex;
  mFixture: TIndexSymbol;
  mNames, mLines: TArray<string>;
  mLineBreak, mName: string;
  mEndLine, mBody: Integer;
  mUsesEdit: TTextEdit;
  mNeedsUses: Boolean;
begin
  ANewText := '';
  mIndex := UnitIndexOf(AText);
  if not FixtureSymbol(mIndex, ARequest.Fixture, mFixture) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.TheTestUnitHasNo].Text, AReason));
  end;
  mNames := FixtureMethods(mIndex, mFixture.Name);
  if MatchText(ARequest.TestName, mNames) and ARequest.OnlyIfMissing then
  begin
    ANewText := AText;
    Exit(True);
  end;
  mName := FreeTestName(ARequest.TestName, mNames);
  mLineBreak := TTextLines.LineBreakOf(AText);
  mLines := AText.Split([mLineBreak]);
  mEndLine := ClassEndLine(mLines, mFixture);
  mBody := BodyLine(mLines);
  if (mEndLine < 0) or (mBody < 0) then
  begin
    Exit(Fail(cTexts[TProjectCommandsText.TestClassOrEndOf].Text, AReason));
  end;
  mNeedsUses := UsesEditFor(AText, mFixture, ARequest.UnitName, mLineBreak, mUsesEdit);
  mLines[mBody] := TestBodyText(mFixture.Name, mName, ARequest.Target, mLineBreak, mLines[mBody]);
  mLines[mEndLine] := TestDeclarationText(mName, mLineBreak, mLines[mEndLine]);
  ANewText := string.Join(mLineBreak, mLines);
  if mNeedsUses then
  begin
    ANewText := Applied(ANewText, mUsesEdit);
  end;
  Result := True;
end;

type
  /// <summary>Ziel von /test: Testunit, Klasse und Methode der Routine (RoutineName wie deklariert) und Unit.</summary>
  TTestPlan = record
    Target: TSlashTestUnit;
    RoutineName: string;
    ClassName: string;
    MethodName: string;
    UnitName: string;
  end;

/// <summary>Teilt AName (Klasse.Methode) in Klasse ohne generische Parameter und Methode.</summary>
procedure SplitRoutineName(const AName: string; out AClassName, AMethodName: string);
var
  mDot, mBracket: Integer;
begin
  mDot := LastDelimiter('.', AName);
  AClassName := Copy(AName, 1, mDot - 1);
  AMethodName := Copy(AName, mDot + 1, MaxInt);
  mBracket := Pos('<', AClassName);
  if mBracket > 0 then
  begin
    AClassName := Copy(AClassName, 1, mBracket - 1);
  end;
end;

/// <summary>Füllt APlan für die Routine um den Cursor; Grund, wenn /test dort nicht gilt, sonst ''.</summary>
function TestPlanIssue(ASource: TCommandSource; const AContext: TSlashContext; out APlan: TTestPlan): string;
var
  mRoutine: TSyntaxNode;
begin
  APlan := Default(TTestPlan);
  mRoutine := ASource.RoutineAt;
  if mRoutine = nil then
  begin
    Exit(cTexts[TProjectCommandsText.TestOnlyAppliesInThe].Text);
  end;
  if AContext.Host = nil then
  begin
    Exit(cTexts[TProjectCommandsText.TestNeedsTheEditor].Text);
  end;
  APlan.RoutineName := mRoutine.Name;
  SplitRoutineName(mRoutine.Name, APlan.ClassName, APlan.MethodName);
  APlan.UnitName := ASource.UnitIndex.UnitName;
  if (APlan.UnitName = '') or (APlan.MethodName = '') then
  begin
    Exit(cTexts[TProjectCommandsText.TestOnlyAppliesInA].Text);
  end;
  Result := '';
  if not AContext.Host.TestUnit(AContext.Uri, ASource.Text, APlan.Target) then
  begin
    Result := APlan.Target.Reason;
  end;
end;

/// <summary>Text der Testunit: gelesen, wenn es sie gibt, sonst ein frisches Gerüst. Grund, wenn sie sich nicht
/// lesen lässt, sonst ''.</summary>
function TestUnitText(const AContext: TSlashContext; ASource: TCommandSource; const APlan: TTestPlan;
  out AText: string): string;
begin
  Result := '';
  AText := '';
  if not APlan.Target.Exists then
  begin
    AText := TTestUnits.UnitText(APlan.Target.UnitName, ASource.UnitIndex, APlan.ClassName, #13#10);
  end
  else if not AContext.Host.ReadFile(APlan.Target.FileName, AText) then
  begin
    Result := cTexts[TProjectCommandsText.CannotBeRead].Fmt([ExtractFileName(APlan.Target.FileName)]);
  end;
end;

/// <summary>Name der getesteten Routine: Klasse.Methode ohne generische Parameter, sonst wie deklariert.</summary>
function TestedName(const APlan: TTestPlan): string;
begin
  Result := APlan.RoutineName;
  if APlan.ClassName <> '' then
  begin
    Result := APlan.ClassName + '.' + APlan.MethodName;
  end;
end;

/// <summary>Neue Testunit ins Testprojekt wie die Code-Aktion aus #274: uses der .dpr und DCCReference der
/// .dproj. Leer, wenn es die Testunit schon gibt.</summary>
function TestProjectFiles(const AContext: TSlashContext; const ATarget: TSlashTestUnit): TArray<TSlashFile>;
var
  mRelative, mMainText, mProjectFile, mProjectText: string;
  mEdit: TTextEdit;
begin
  Result := nil;
  if ATarget.Exists then
  begin
    Exit;
  end;
  mRelative := TTestUnits.RelativePath(TProjectPaths.DirectoryOf(ATarget.TestProgram), ATarget.FileName);
  if AContext.Host.ReadFile(ATarget.TestProgram, mMainText) and
    TUnitTemplates.UnitProgramEdit(mMainText, ATarget.UnitName, mRelative, mEdit) then
  begin
    Result := Result + [TSlashFile.Create(ATarget.TestProgram, Applied(mMainText, mEdit), False)];
  end;
  mProjectFile := ChangeFileExt(ATarget.TestProgram, '.dproj');
  if AContext.Host.ReadFile(mProjectFile, mProjectText) and (Pos('"' + mRelative + '"', mProjectText) = 0) and
    TUnitTemplates.ProjectEdit(mProjectText, mRelative, '', TFormKind.Form, False, mEdit) then
  begin
    Result := Result + [TSlashFile.Create(mProjectFile, Applied(mProjectText, mEdit), False)];
  end;
end;

function ExecuteTest(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mPlan: TTestPlan;
  mTestText, mNewText: string;
  mFiles: TArray<TSlashFile>;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    AReason := TestPlanIssue(mSource, AContext, mPlan);
    if AReason = '' then
    begin
      AReason := TestUnitText(AContext, mSource, mPlan, mTestText);
    end;
    Result := AReason = '';
    if Result then
    begin
      Result := AddTestMethod(mTestText, TTestRequest.Create(TTestUnits.FixtureName(mPlan.ClassName, mPlan.UnitName),
        'Test' + mPlan.MethodName, TestedName(mPlan), mPlan.UnitName, not mPlan.Target.Exists), mNewText, AReason);
    end;
    if Result then
    begin
      mFiles := [TSlashFile.Create(mPlan.Target.FileName, mNewText, not mPlan.Target.Exists)];
      mFiles := mFiles + TestProjectFiles(AContext, mPlan.Target);
      AEdits := [mSource.RemoveCommand];
      WriteFilesLater(AContext, mFiles, mPlan.Target.FileName);
    end;
  finally
    mSource.Free;
  end;
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
  ARegister(Command('define', cTexts[TProjectCommandsText.AddASymbolToDCC].Text, '/define TEST',
    ExecuteDefine));
  ARegister(Command('define!', cTexts[TProjectCommandsText.AddASymbolToDCC2].Text, '/define! TEST',
    ExecuteDefine));
  ARegister(Command('searchpath', cTexts[TProjectCommandsText.AddAFolderToThe].Text,
    '/searchpath Source\Common', ExecuteSearchPath));
  ARegister(Command('config', cTexts[TProjectCommandsText.SwitchConfigurationAndPlatform].Text, '/config Release Win64',
    ExecuteConfig));
  ARegister(Command('dfm', cTexts[TProjectCommandsText.JumpToThePositionIn].Text, '/dfm', ExecuteDfm));
  ARegister(Command('unit', cTexts[TProjectCommandsText.CreateANewUnitAdd].Text,
    cTexts[TProjectCommandsText.UnitCustomersData].Text,
    ExecuteUnit));
  ARegister(Command('open', cTexts[TProjectCommandsText.OpenAUnitFromThe].Text, '/open System.SysUtils', ExecuteOpen));
  ARegister(Command('component', cTexts[TProjectCommandsText.CreateANewComponentUnit].Text,
    '/component TMyButton : TButton', ExecuteComponent));
  ARegister(Command('test', cTexts[TProjectCommandsText.CreateADUnitXTestFor].Text,
    '/test', ExecuteTest));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ProjectCommands', cTexts);

end.
