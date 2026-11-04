unit Atlas.Common.Mcp.Prompts;

// MCP-Prompts und Ressourcen mit Vorlage (#1357). Prompts sind fertige
// Arbeitsabläufe, die Claude Code als Schrägstrich-Befehle anzeigt
// (/mcp__delphi__unit_review UI.Auftrag). prompts/get liefert eine Nachricht
// mit Anleitung und den Ergebnissen der nötigen Werkzeuge, damit Claude nicht
// erst einzeln nachfragen muss:
//
//   unit_review (unit)          Gliederung, Befunde, Metriken über Grenzwert, ungenutzter Code, Konventionen
//   explain_form (file)         Komponentenbaum, Ereignis-Handler mit Rümpfen, Datenbindungen
//   write_tests (name)          Deklaration, Aufrufer, Auswirkungen samt vorhandener Tests, DUnitX-Konventionen
//   fix_finding (file, line, rule)  Erklärung, Codeausschnitt, verfügbare Korrekturen
//   prepare_commit (base)       geänderte Dateien, neue Befunde in geänderten Zeilen, betroffene Tests, Präfix
//   mcp.customPrompts          eigene Prompts aus atlas.json mit Platzhaltern {argument} und include
//
// Vorlagen (Inhalt Markdown, höchstens MaxResourceBytes):
//   delphi://unit/{name}  delphi://form/{file}  delphi://findings/{file}  und delphi://build/last
//
// Die Daten kommen über TMcpServer.InvokeTool von denselben Werkzeugen wie
// tools/call: abgeschaltete (mcp.disabledTools) und im eingeschränkten Modus
// (--restricted) nicht lesende Werkzeuge fehlen mit Begründung, und die
// Anleitungen bieten dann keine schreibenden Schritte an. Unit- und
// Dateiargumente prüft der Aufrufer über ResolveUnit/ResolveFile wie
// Pfadparameter (#99). Die Anleitungen sind deutsch, mit
// mcp.promptLanguage = en englisch.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IndexTools;

type
  /// <summary>Geänderte Datei für prepare_commit mit den Befunden in geänderten Zeilen.</summary>
  TMcpChangedFile = record
    /// <summary>Pfad relativ zum Arbeitsordner.</summary>
    Path: string;
    Findings: TArray<TRuleFinding>;
  end;

  /// <summary>Änderungen laut Versionsverwaltung für prepare_commit.</summary>
  TMcpChangeSet = record
    /// <summary>Name der Versionsverwaltung, z. B. Git.</summary>
    Vcs: string;
    /// <summary>Vergleichsbasis, z. B. HEAD oder main.</summary>
    Base: string;
    Files: TArray<TMcpChangedFile>;
    /// <summary>Präfix des aktuellen Issues (issues.commitPattern, vom Plugin in atlas-commit-prefix); '' ohne.
    /// </summary>
    CommitPrefix: string;
    /// <summary>Grund, wenn sich die Änderungen nicht ermitteln ließen; sonst ''.</summary>
    Error: string;
  end;

  /// <summary>ABase: '' = nicht eingecheckte Änderungen gegenüber HEAD, sonst seit der Abzweigung von ABase.</summary>
  TMcpChangesFunc = reference to function(const ABase: string): TMcpChangeSet;

  TMcpPrompts = class
  public const
    /// <summary>Größte Ressource aus einer Vorlage (UTF-8).</summary>
    MaxResourceBytes = 64 * 1024;
    /// <summary>Größter eingebetteter Abschnitt eines Prompts (UTF-8).</summary>
    MaxSectionBytes = 32 * 1024;
    /// <summary>Zeilen vor und nach der Zeile eines Befunds im Codeausschnitt von fix_finding.</summary>
    SnippetContext = 8;
    ConventionsUri = 'delphi://conventions';
  private
    FServer: TMcpServer;
    FSettings: TFunc<TServerSettings>;
    FReadText: TMcpReadText;
    FResolveUnit: TFunc<string, string>;
    FResolveFile: TFunc<string, string>;
    FChanges: TMcpChangesFunc;
    FEnglish: Boolean;
    function Say(const AGerman, AEnglish: string): string;
    function ToolSection(const ATitle, ATool: string; const AArguments: TJSONObject): string; overload;
    function ToolSection(const ATitle, ATool, AName, AValue: string): string; overload;
    function ConventionsSection: string;
    function FormFile(const AFile: string): string;
    function Builtin: TArray<TMcpPrompt>;
    function Custom: TArray<TMcpPrompt>;
    function UnitReview(const AArguments: TDictionary<string, string>): string;
    function ExplainForm(const AArguments: TDictionary<string, string>): string;
    function WriteTests(const AArguments: TDictionary<string, string>): string;
    function FixFinding(const AArguments: TDictionary<string, string>): string;
    function PrepareCommit(const AArguments: TDictionary<string, string>): string;
    function RunCustom(const APrompt: TMcpCustomPrompt; const AArguments: TDictionary<string, string>): string;
    function IncludeSection(const AInclude: string; const AArguments: TDictionary<string, string>): string;
    function UnitResource(const AName: string): string;
    function FormResource(const AFile: string): string;
    function FindingsResource(const AFile: string): string;
    function BuildResource: string;
    function ToolText(const ATool: string; const AArguments: TJSONObject): string;
    procedure UseLanguage;
  public
    /// <summary>AServer: Werkzeuge und Ressourcen, an die die Prompts sich hängen; gehört dem Aufrufer.
    /// ASettings: wirksame Einstellungen, bei jedem Aufruf neu gelesen.</summary>
    constructor Create(AServer: TMcpServer; const ASettings: TFunc<TServerSettings>);
    /// <summary>Registriert Prompts, Vorlagen und delphi://build/last am Server.</summary>
    procedure Register;
    /// <summary>Text auf höchstens AMaxBytes (UTF-8) gekürzt, an einem Zeilenende, mit Hinweis auf ATool für alles
    /// ('' = ohne Werkzeug).</summary>
    class function Limit(const AText: string; AMaxBytes: Integer; const ATool: string): string; static;
    /// <summary>Platzhalter {name} durch die Argumente ersetzt; unbekannte bleiben stehen.</summary>
    class function Substitute(const AText: string; const AArguments: TDictionary<string, string>): string; static;
    /// <summary>interface-Teil einer Unit (vom Schlüsselwort bis vor implementation); '' ohne.</summary>
    class function InterfacePart(const AText: string): string; static;
    /// <summary>Rümpfe der Ereignis-Handler eines Formulars aus der zugehörigen Unit, je Handler mit Zeile;
    /// fehlende Handler mit Hinweis.</summary>
    class function HandlerBodies(const AFormText, AUnitText: string): string; static;
    /// <summary>Datenbindungen eines Formulars: DataSource, DataField, Connection … je Komponente, dazu
    /// LiveBindings-Verknüpfungen.</summary>
    class function DataBindings(const AFormText: string): string; static;
    /// <summary>Codeausschnitt um ALine (ab 1) mit Zeilennummern, die Zeile mit "&gt;" markiert.</summary>
    class function Snippet(const ALines: TArray<string>; ALine, AContext: Integer): string; static;
    /// <summary>Geänderte Dateien und Befunde in geänderten Zeilen als Markdown.</summary>
    class function ChangeReport(const AChanges: TMcpChangeSet; AEnglish: Boolean): string; static;
    /// <summary>Unit-Name oder Pfad → geprüfte Datei; EMcpToolError mit Begründung, wenn die Unit fehlt oder
    /// außerhalb der erlaubten Ordner liegt (#99).</summary>
    property ResolveUnit: TFunc<string, string> read FResolveUnit write FResolveUnit;
    /// <summary>Pfad → geprüfte Datei wie TMcpPathGuard.Resolve.</summary>
    property ResolveFile: TFunc<string, string> read FResolveFile write FResolveFile;
    property ReadText: TMcpReadText read FReadText write FReadText;
    /// <summary>Änderungen für prepare_commit; ohne Ereignis meldet der Prompt, dass sie fehlen.</summary>
    property Changes: TMcpChangesFunc read FChanges write FChanges;
  end;

implementation

uses
  System.StrUtils,
  System.Classes,
  Atlas.Text.Lines,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Output;

function Utf8Length(const AText: string): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(AText);
end;

function StringArgs(const AName, AValue: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair(AName, AValue);
end;

function IncomingCalls(const AName: string): TJSONObject;
begin
  Result := StringArgs('name', AName);
  Result.AddPair('direction', 'incoming');
end;

/// <summary>base, wenn angegeben.</summary>
function BaseArgs(const ABase: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  if ABase <> '' then
  begin
    Result.AddPair('base', ABase);
  end;
end;

/// <summary>file und line, dazu rule, wenn angegeben.</summary>
function FindingArgs(const AFile: string; ALine: Integer; const ARule: string): TJSONObject;
begin
  Result := StringArgs('file', AFile);
  Result.AddPair('line', TJSONNumber.Create(ALine));
  if ARule <> '' then
  begin
    Result.AddPair('rule', ARule);
  end;
end;

function Argument(const AArguments: TDictionary<string, string>; const AName: string): string;
begin
  if not AArguments.TryGetValue(AName, Result) then
  begin
    Result := '';
  end;
end;

function PromptArgument(const AName, ADescription: string; ARequired: Boolean): TMcpPromptArgument;
begin
  Result := TMcpPromptArgument.Create(AName, ADescription, ARequired);
end;

{ TMcpPrompts }

constructor TMcpPrompts.Create(AServer: TMcpServer; const ASettings: TFunc<TServerSettings>);
begin
  inherited Create;
  FServer := AServer;
  FSettings := ASettings;
end;

procedure TMcpPrompts.UseLanguage;
begin
  FEnglish := SameText(FSettings().McpPromptLanguage, 'en');
end;

/// <summary>Deutscher oder englischer Text je nach mcp.promptLanguage.</summary>
function SayIn(AEnglish: Boolean; const AGerman, AEnglishText: string): string;
begin
  if AEnglish then
  begin
    Result := AEnglishText;
  end
  else
  begin
    Result := AGerman;
  end;
end;

/// <summary>Abschnitt mit Überschrift, Inhalt auf TMcpPrompts.MaxSectionBytes gekürzt.</summary>
function Section(const ATitle, ABody: string): string;
begin
  Result := '## ' + ATitle + sLineBreak + sLineBreak + TMcpPrompts.Limit(TrimRight(ABody), TMcpPrompts.MaxSectionBytes,
    '');
end;

/// <summary>Datei der Unit AUnit über AResolve; EMcpToolError ohne Auflösung.</summary>
function UnitFile(const AResolve: TFunc<string, string>; const AUnit: string): string;
begin
  if not Assigned(AResolve) then
  begin
    raise EMcpToolError.CreateFmt('Unit "%s" lässt sich hier nicht auflösen', [AUnit]);
  end;
  Result := AResolve(AUnit);
end;

/// <summary>Geprüfte Datei AFile über AResolve; EMcpToolError ohne Auflösung.</summary>
function CheckedFile(const AResolve: TFunc<string, string>; const AFile: string): string;
begin
  if not Assigned(AResolve) then
  begin
    raise EMcpToolError.CreateFmt('Datei "%s" lässt sich hier nicht auflösen', [AFile]);
  end;
  Result := AResolve(AFile);
end;

/// <summary>Zeilen der Datei über AReadText; nil, wenn sie sich nicht lesen lässt.</summary>
function ReadLines(const AReadText: TMcpReadText; const AFileName: string): TArray<string>;
var
  mText: string;
begin
  Result := nil;
  if Assigned(AReadText) and AReadText(AFileName, mText) then
  begin
    Result := TTextLines.SplitLines(mText);
  end;
end;

function Intro(AEnglish: Boolean; const AText: string): string;
begin
  Result := AText + sLineBreak + sLineBreak + SayIn(AEnglish,
    'Die Daten unten hat der Atlas-Server eben ermittelt. Rufe dafür keine Werkzeuge erneut auf; frage nur nach, ' +
    'was hier fehlt.',
    'The Atlas server has just collected the data below. Do not call tools again for it; only ask for what is ' +
    'missing here.');
end;

function ReadOnlyNote(AEnglish: Boolean): string;
begin
  Result := SayIn(AEnglish, 'Eingeschränkter Modus (--restricted): Ändere keine Dateien, schreibe Vorschläge als ' +
    'Diff in die Antwort.', 'Restricted mode (--restricted): do not change any files, put suggestions as a diff ' +
    'into your answer.');
end;

function TMcpPrompts.Say(const AGerman, AEnglish: string): string;
begin
  if FEnglish then
  begin
    Result := AEnglish;
  end
  else
  begin
    Result := AGerman;
  end;
end;

class function TMcpPrompts.Limit(const AText: string; AMaxBytes: Integer; const ATool: string): string;
var
  mNote: string;
  mCount, mBytes, mTarget, mBreak: Integer;
begin
  if Utf8Length(AText) <= AMaxBytes then
  begin
    Exit(AText);
  end;
  if ATool <> '' then
  begin
    mNote := Format(sLineBreak + sLineBreak + '… gekürzt auf %d KB; vollständig mit %s.', [AMaxBytes div 1024, ATool]);
  end
  else
  begin
    mNote := Format(sLineBreak + sLineBreak + '… gekürzt auf %d KB.', [AMaxBytes div 1024]);
  end;
  mTarget := AMaxBytes - Utf8Length(mNote);
  mCount := Length(AText);
  if mCount > mTarget then
  begin
    mCount := mTarget;
  end;
  mBytes := Utf8Length(Copy(AText, 1, mCount));
  while (mCount > 0) and (mBytes > mTarget) do
  begin
    // Umlaute und andere Zeichen brauchen mehr als ein Byte: in Schritten an das Ziel heran.
    if (mBytes - mTarget) div 2 > 1 then
    begin
      Dec(mCount, (mBytes - mTarget) div 2);
    end
    else
    begin
      Dec(mCount);
    end;
    mBytes := Utf8Length(Copy(AText, 1, mCount));
  end;
  // Keine halbe Zeile am Ende.
  mBreak := mCount;
  while (mBreak > 0) and (AText[mBreak] <> #10) do
  begin
    Dec(mBreak);
  end;
  if mBreak > 0 then
  begin
    mCount := mBreak - 1;
  end;
  Result := TrimRight(Copy(AText, 1, mCount)) + mNote;
end;

class function TMcpPrompts.Substitute(const AText: string; const AArguments: TDictionary<string, string>): string;
var
  mPair: TPair<string, string>;
begin
  Result := AText;
  for mPair in AArguments do
  begin
    Result := StringReplace(Result, '{' + mPair.Key + '}', mPair.Value, [rfReplaceAll]);
  end;
end;

function LinesOf(const ALines: TArray<string>; AFirst, ALast: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := AFirst to ALast do
    begin
      if (mIndex >= 0) and (mIndex < Length(ALines)) then
      begin
        mBuilder.Append(ALines[mIndex]).Append(sLineBreak);
      end;
    end;
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

class function TMcpPrompts.InterfacePart(const AText: string): string;
var
  mTree: TSyntaxTree;
  mSection: TSyntaxNode;
begin
  Result := '';
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    if (mTree = nil) or (mTree.Root = nil) then
    begin
      Exit;
    end;
    mSection := mTree.Root.FindChild(TSyntaxKind.InterfaceSection);
    if mSection <> nil then
    begin
      Result := LinesOf(TTextLines.SplitLines(AText), mSection.StartPos.Line, mSection.EndPos.Line);
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Ereignisse aller Komponenten: Handlername → "Komponente.Ereignis, …" in der Reihenfolge der Datei.
/// </summary>
procedure CollectEvents(AObject: TDfmObject; AHandlers: TList<string>; AUses: TDictionary<string, string>);
var
  mProperty: TDfmProperty;
  mChild: TDfmObject;
  mKey, mWhere, mKnown: string;
begin
  for mProperty in AObject.Properties do
  begin
    if mProperty.IsEvent and (Trim(mProperty.Value) <> '') then
    begin
      mKey := Trim(mProperty.Value);
      mWhere := AObject.Name + '.' + mProperty.Name;
      if AUses.TryGetValue(LowerCase(mKey), mKnown) then
      begin
        AUses[LowerCase(mKey)] := mKnown + ', ' + mWhere;
      end
      else
      begin
        AUses.Add(LowerCase(mKey), mWhere);
        AHandlers.Add(mKey);
      end;
    end;
  end;
  for mChild in AObject.Children do
  begin
    CollectEvents(mChild, AHandlers, AUses);
  end;
end;

/// <summary>Routine AName im implementation-Teil ASection; nil ohne.</summary>
function FindRoutine(ASection: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if (ASection[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(ASection[mIndex].Name, AName) then
    begin
      Exit(ASection[mIndex]);
    end;
  end;
end;

/// <summary>Ein Handler mit seinen Verwendungen AWhere und, wenn gefunden, dem Rumpf aus ALines.</summary>
procedure AppendHandler(ABuilder: TStringBuilder; const AHandler, AWhere: string; ARoutine: TSyntaxNode;
  const ALines: TArray<string>);
begin
  if ABuilder.Length > 0 then
  begin
    ABuilder.Append(sLineBreak).Append(sLineBreak);
  end;
  ABuilder.Append(Format('%s (%s)', [AHandler, AWhere]));
  if ARoutine = nil then
  begin
    ABuilder.Append(sLineBreak).Append('  Implementierung nicht gefunden.');
    Exit;
  end;
  ABuilder.Append(Format(', Zeile %d:', [ARoutine.StartPos.Line + 1])).Append(sLineBreak)
    .Append('```pascal').Append(sLineBreak)
    .Append(LinesOf(ALines, ARoutine.StartPos.Line, ARoutine.EndPos.Line)).Append(sLineBreak)
    .Append('```');
end;

class function TMcpPrompts.HandlerBodies(const AFormText, AUnitText: string): string;
var
  mDocument: TDfmDocument;
  mTree: TSyntaxTree;
  mSection: TSyntaxNode;
  mHandlers: TList<string>;
  mUses: TDictionary<string, string>;
  mLines: TArray<string>;
  mBuilder: TStringBuilder;
  mHandler: string;
begin
  mDocument := TDfmParser.Parse(AFormText);
  mHandlers := TList<string>.Create;
  mUses := TDictionary<string, string>.Create;
  mBuilder := TStringBuilder.Create;
  mTree := nil;
  try
    if mDocument.Root <> nil then
    begin
      CollectEvents(mDocument.Root, mHandlers, mUses);
    end;
    if mHandlers.Count = 0 then
    begin
      Exit('');
    end;
    mLines := TTextLines.SplitLines(AUnitText);
    mSection := nil;
    if AUnitText <> '' then
    begin
      mTree := TSyntaxTreeCache.Parse(AUnitText);
    end;
    if (mTree <> nil) and (mTree.Root <> nil) then
    begin
      mSection := mTree.Root.FindChild(TSyntaxKind.ImplementationSection);
    end;
    for mHandler in mHandlers do
    begin
      AppendHandler(mBuilder, mHandler, mUses[LowerCase(mHandler)],
        FindRoutine(mSection, mDocument.Root.TypeName + '.' + mHandler), mLines);
    end;
    Result := mBuilder.ToString;
  finally
    mTree.Free;
    mBuilder.Free;
    mUses.Free;
    mHandlers.Free;
    mDocument.Free;
  end;
end;

/// <summary>Bindet die Eigenschaft eine Komponente an Daten? Datenbank-Steuerelemente, Datenmengen und
/// LiveBindings (TLink…, TBind…).</summary>
function IsBindingProperty(const ATypeName, AName: string): Boolean;
const
  cNames: array[0..17] of string = ('DataSource', 'DataSet', 'DataField', 'FieldName', 'Connection',
    'MasterSource', 'MasterFields', 'IndexFieldNames', 'LookupDataSet', 'LookupKeyFields', 'LookupResultField',
    'KeyFields', 'ListSource', 'ListField', 'KeyField', 'SourceComponent', 'SourceMemberName', 'ControlComponent');
var
  mName: string;
begin
  for mName in cNames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  // Bei LiveBindings heißt das Ziel einfach Control (TLinkControlToField, TLinkListControlToField).
  Result := SameText(AName, 'Control') and (StartsText('TLink', ATypeName) or StartsText('TBind', ATypeName));
end;

procedure CollectBindings(AObject: TDfmObject; ABuilder: TStringBuilder);
var
  mProperty: TDfmProperty;
  mChild: TDfmObject;
  mLine: string;
begin
  mLine := '';
  for mProperty in AObject.Properties do
  begin
    if IsBindingProperty(AObject.TypeName, mProperty.Name) then
    begin
      if mLine <> '' then
      begin
        mLine := mLine + ', ';
      end;
      mLine := mLine + mProperty.Name + ' = ' + Trim(mProperty.Value);
    end;
  end;
  if mLine <> '' then
  begin
    ABuilder.Append(Format('- %s: %s – %s', [AObject.Name, AObject.TypeName, mLine])).Append(sLineBreak);
  end;
  for mChild in AObject.Children do
  begin
    CollectBindings(mChild, ABuilder);
  end;
end;

class function TMcpPrompts.DataBindings(const AFormText: string): string;
var
  mDocument: TDfmDocument;
  mBuilder: TStringBuilder;
begin
  mDocument := TDfmParser.Parse(AFormText);
  mBuilder := TStringBuilder.Create;
  try
    if mDocument.Root <> nil then
    begin
      CollectBindings(mDocument.Root, mBuilder);
    end;
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
    mDocument.Free;
  end;
end;

class function TMcpPrompts.Snippet(const ALines: TArray<string>; ALine, AContext: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex, mFirst, mLast: Integer;
  mMarker: string;
begin
  mFirst := ALine - AContext;
  if mFirst < 1 then
  begin
    mFirst := 1;
  end;
  mLast := ALine + AContext;
  if mLast > Length(ALines) then
  begin
    mLast := Length(ALines);
  end;
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := mFirst to mLast do
    begin
      mMarker := ' ';
      if mIndex = ALine then
      begin
        mMarker := '>';
      end;
      mBuilder.Append(Format('%s%5d  %s', [mMarker, mIndex, ALines[mIndex - 1]])).Append(sLineBreak);
    end;
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

class function TMcpPrompts.ChangeReport(const AChanges: TMcpChangeSet; AEnglish: Boolean): string;
var
  mBuilder: TStringBuilder;
  mFile: TMcpChangedFile;
  mFinding: TRuleFinding;
  mCount: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mCount := 0;
    for mFile in AChanges.Files do
    begin
      Inc(mCount, Length(mFile.Findings));
    end;
    if AEnglish then
    begin
      mBuilder.Append(Format('%s, compared with %s: %d changed files, %d new findings in changed lines.',
        [AChanges.Vcs, AChanges.Base, Length(AChanges.Files), mCount]));
    end
    else
    begin
      mBuilder.Append(Format('%s, verglichen mit %s: %d geänderte Dateien, %d neue Befunde in geänderten Zeilen.',
        [AChanges.Vcs, AChanges.Base, Length(AChanges.Files), mCount]));
    end;
    mBuilder.Append(sLineBreak);
    for mFile in AChanges.Files do
    begin
      mBuilder.Append(sLineBreak).Append('- ').Append(mFile.Path);
      for mFinding in mFile.Findings do
      begin
        mBuilder.Append(sLineBreak).Append(Format('  - %d:%d: %s [%s] %s', [mFinding.Range.StartPos.Line + 1,
          mFinding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(mFinding.Severity), mFinding.RuleId,
          mFinding.Message]));
      end;
    end;
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

function TMcpPrompts.ToolSection(const ATitle, ATool: string; const AArguments: TJSONObject): string;
var
  mText: string;
begin
  try
    if FServer.InvokeTool(ATool, AArguments, mText) then
    begin
      Result := '## ' + ATitle + ' (' + ATool + ')' + sLineBreak + sLineBreak +
        Limit(TrimRight(mText), MaxSectionBytes, ATool);
    end
    else
    begin
      Result := '## ' + ATitle + ' (' + ATool + ')' + sLineBreak + sLineBreak +
        Say('Nicht verfügbar: ', 'Not available: ') + mText;
    end;
  finally
    AArguments.Free;
  end;
end;

function TMcpPrompts.ToolSection(const ATitle, ATool, AName, AValue: string): string;
begin
  Result := ToolSection(ATitle, ATool, StringArgs(AName, AValue));
end;

function TMcpPrompts.ToolText(const ATool: string; const AArguments: TJSONObject): string;
begin
  try
    if not FServer.InvokeTool(ATool, AArguments, Result) then
    begin
      raise EMcpToolError.Create(Result);
    end;
  finally
    AArguments.Free;
  end;
end;

function TMcpPrompts.ConventionsSection: string;
var
  mText: string;
begin
  if FServer.ReadResourceText(ConventionsUri, mText) then
  begin
    Result := Section(Say('Projektkonventionen', 'Project conventions') + ' (' + ConventionsUri + ')', mText);
  end
  else
  begin
    Result := Section(Say('Projektkonventionen', 'Project conventions'),
      Say('Nicht verfügbar.', 'Not available.'));
  end;
end;


function TMcpPrompts.FormFile(const AFile: string): string;
var
  mText: string;
begin
  Result := CheckedFile(FResolveFile, AFile);
  if SameText(ExtractFileExt(Result), '.pas') then
  begin
    if Assigned(FReadText) and FReadText(ChangeFileExt(Result, '.dfm'), mText) then
    begin
      Result := ChangeFileExt(Result, '.dfm');
    end
    else
    begin
      Result := ChangeFileExt(Result, '.fmx');
    end;
  end;
  if not TDfmParser.IsFormFile(Result) then
  begin
    raise EMcpToolError.CreateFmt('"%s" ist keine Formulardatei (.dfm, .fmx oder die .pas dazu)', [AFile]);
  end;
end;



function TMcpPrompts.UnitReview(const AArguments: TDictionary<string, string>): string;
var
  mUnit, mFile, mSteps: string;
begin
  UseLanguage;
  mUnit := Argument(AArguments, 'unit');
  mFile := UnitFile(FResolveUnit, mUnit);
  mSteps := Say(
    '1. Ordne die Punkte nach Schweregrad: Fehler, Warnungen, dann Hinweise und Stil. Fasse gleichartige zusammen.' +
    sLineBreak +
    '2. Nenne je Punkt Datei:Zeile, die Ursache und einen konkreten Vorschlag mit Codeausschnitt.' + sLineBreak +
    '3. Beziehe Metriken über dem Grenzwert, ungenutzten Code und die Projektkonventionen ein.' + sLineBreak,
    '1. Order the points by severity: errors, warnings, then hints and style. Group similar ones.' + sLineBreak +
    '2. For each point give file:line, the cause and a concrete suggestion with a code snippet.' + sLineBreak +
    '3. Take methods above the metric limits, unused code and the project conventions into account.' + sLineBreak);
  if FServer.Restricted then
  begin
    mSteps := mSteps + '4. ' + ReadOnlyNote(FEnglish) + Say(' Prüfe jeden Vorschlag mit check_code.',
      ' Check every suggestion with check_code.');
  end
  else
  begin
    mSteps := mSteps + Say('4. Prüfe jede Änderung vor dem Schreiben mit check_code und ändere erst nach Rückfrage.',
      '4. Check every change with check_code before writing it, and only change code after asking.');
  end;
  Result := Intro(FEnglish, Format(Say('Führe ein Code-Review der Unit %s (%s) durch.', 'Review the unit %s (%s).'),
    [mUnit, mFile])) + sLineBreak + sLineBreak + mSteps + sLineBreak + sLineBreak +
    ToolSection(Say('Gliederung', 'Outline'), 'get_unit_outline', 'unit', mFile) + sLineBreak + sLineBreak +
    ToolSection(Say('Befunde', 'Findings'), 'get_diagnostics', 'file', mFile) + sLineBreak + sLineBreak +
    ToolSection(Say('Metriken über Grenzwert', 'Metrics above limits'), 'get_metrics', 'file', mFile) +
    sLineBreak + sLineBreak +
    ToolSection(Say('Ungenutzter Code', 'Unused code'), 'find_unused_code', 'file', mFile) + sLineBreak +
    sLineBreak + ConventionsSection;
end;

function TMcpPrompts.ExplainForm(const AArguments: TDictionary<string, string>): string;
var
  mFile, mFormText, mUnitText, mBodies, mBindings: string;
begin
  UseLanguage;
  mFile := FormFile(Argument(AArguments, 'file'));
  if not Assigned(FReadText) or not FReadText(mFile, mFormText) then
  begin
    raise EMcpToolError.CreateFmt('Formulardatei "%s" nicht gefunden', [mFile]);
  end;
  if not FReadText(ChangeFileExt(mFile, '.pas'), mUnitText) then
  begin
    mUnitText := '';
  end;
  mBodies := HandlerBodies(mFormText, mUnitText);
  if mBodies = '' then
  begin
    mBodies := Say('Keine Ereignis-Handler.', 'No event handlers.');
  end;
  mBindings := DataBindings(mFormText);
  if mBindings = '' then
  begin
    mBindings := Say('Keine Datenbindungen.', 'No data bindings.');
  end;
  Result := Intro(FEnglish, Format(Say('Erkläre das Formular %s.', 'Explain the form %s.'), [mFile])) + sLineBreak +
    sLineBreak + Say(
    '1. Wozu dient das Formular, welche Bereiche hat es (Komponentenbaum)?' + sLineBreak +
    '2. Was tun die Ereignis-Handler, in welcher Reihenfolge laufen sie typischerweise?' + sLineBreak +
    '3. Woher kommen die Daten (Datenbindungen) und wohin fließen sie?' + sLineBreak +
    '4. Was fällt auf (Logik im Formular, doppelte Handler, fehlende Freigaben)? Nenne Komponenten beim Namen.',
    '1. What is the form for, which areas does it have (component tree)?' + sLineBreak +
    '2. What do the event handlers do, in which order do they typically run?' + sLineBreak +
    '3. Where does the data come from (data bindings) and where does it go?' + sLineBreak +
    '4. What stands out (logic in the form, duplicate handlers, missing frees)? Name components.') +
    sLineBreak + sLineBreak +
    ToolSection(Say('Komponentenbaum', 'Component tree'), 'get_dfm_info', 'file', mFile) + sLineBreak +
    sLineBreak + Section(Say('Ereignis-Handler', 'Event handlers'), mBodies) + sLineBreak + sLineBreak +
    Section(Say('Datenbindungen', 'Data bindings'), mBindings);
end;

function TMcpPrompts.WriteTests(const AArguments: TDictionary<string, string>): string;
var
  mName, mSteps, mConventions, mFolder, mProject: string;
  mSettings: TServerSettings;
begin
  UseLanguage;
  mName := Argument(AArguments, 'name');
  mSettings := FSettings();
  mFolder := mSettings.TestUnits.Folder;
  if mFolder = '' then
  begin
    mFolder := Say('Ordner des Testprojekts', 'folder of the test project');
  end;
  mProject := mSettings.TestUnits.Project;
  if mProject = '' then
  begin
    mProject := Say('automatisch erkannt', 'detected automatically');
  end;
  mConventions := Format(Say(
    'Name der Testunit: %s ({unit} = getestete Unit). Ordner neuer Testunits: %s. Testprojekt: %s.' + sLineBreak +
    'DUnitX: [TestFixture] je Klasse, [Test] je Methode, Assert.AreEqual(Erwartet, Ist), Fixture in initialization ' +
    'mit TDUnitX.RegisterTestFixture registrieren; eine neue Testunit gehört auch ins Testprojekt (.dpr und .dproj).',
    'Test unit name: %s ({unit} = unit under test). Folder for new test units: %s. Test project: %s.' + sLineBreak +
    'DUnitX: [TestFixture] per class, [Test] per method, Assert.AreEqual(Expected, Actual), register the fixture ' +
    'with TDUnitX.RegisterTestFixture in initialization; a new test unit also goes into the test project (.dpr ' +
    'and .dproj).'), [mSettings.TestUnits.Pattern, mFolder, mProject]);
  mSteps := Say(
    '1. Lege Testmethoden für normale Fälle, Grenzfälle und Fehlerfälle an; vorhandene Tests (unten) nicht doppeln.' +
    sLineBreak + '2. Schreibe sie in die passende Testunit nach den Konventionen unten.' + sLineBreak,
    '1. Add test methods for normal cases, edge cases and error cases; do not duplicate the existing tests below.' +
    sLineBreak + '2. Put them into the matching test unit following the conventions below.' + sLineBreak);
  if FServer.Restricted then
  begin
    mSteps := mSteps + '3. ' + ReadOnlyNote(FEnglish);
  end
  else if FServer.ToolAvailable('run_tests') then
  begin
    mSteps := mSteps + Say('3. Prüfe den Code mit check_code, dann führe die neuen Tests mit run_tests aus ' +
      '(tests: Unit.Fixture.Methode) und behebe Fehlschläge.', '3. Check the code with check_code, then run the ' +
      'new tests with run_tests (tests: Unit.Fixture.Method) and fix failures.');
  end
  else
  begin
    mSteps := mSteps + Say('3. Prüfe den Code mit check_code; run_tests ist hier nicht verfügbar, nenne die Tests ' +
      'zum Ausführen.', '3. Check the code with check_code; run_tests is not available here, list the tests to run.');
  end;
  Result := Intro(FEnglish, Format(Say('Schreibe DUnitX-Tests für %s.', 'Write DUnitX tests for %s.'), [mName])) +
    sLineBreak + sLineBreak + mSteps + sLineBreak + sLineBreak +
    ToolSection(Say('Deklaration', 'Declaration'), 'get_declaration', 'name', mName) + sLineBreak + sLineBreak +
    ToolSection(Say('Aufrufer', 'Callers'), 'get_call_hierarchy', IncomingCalls(mName)) + sLineBreak + sLineBreak +
    ToolSection(Say('Auswirkungen und vorhandene Tests', 'Impact and existing tests'), 'get_impact', 'name',
    mName) + sLineBreak + sLineBreak + Section(Say('DUnitX-Konventionen des Projekts', 'DUnitX conventions of ' +
    'the project'), mConventions);
end;

function TMcpPrompts.FixFinding(const AArguments: TDictionary<string, string>): string;
var
  mFile, mRule, mSteps, mSnippet: string;
  mLine: Integer;
  mLines: TArray<string>;
begin
  UseLanguage;
  mFile := CheckedFile(FResolveFile, Argument(AArguments, 'file'));
  if not TryStrToInt(Argument(AArguments, 'line'), mLine) or (mLine < 1) then
  begin
    raise EMcpToolError.Create(Say('"line" muss eine Zeilennummer ab 1 sein', '"line" must be a line number from 1'));
  end;
  mRule := Argument(AArguments, 'rule');
  mLines := ReadLines(FReadText, mFile);
  if mLines = nil then
  begin
    raise EMcpToolError.CreateFmt(Say('%s ist nicht lesbar', '%s cannot be read'), [mFile]);
  end;
  if mLine > Length(mLines) then
  begin
    raise EMcpToolError.CreateFmt(Say('%s hat nur %d Zeilen', '%s has only %d lines'), [mFile, Length(mLines)]);
  end;
  mSnippet := '```pascal' + sLineBreak + Snippet(mLines, mLine, SnippetContext) + sLineBreak + '```';
  mSteps := Say('1. Erkläre zuerst die Ursache des Befunds in diesem Code, nicht nur die Regel.' + sLineBreak,
    '1. First explain the cause of the finding in this code, not just the rule.' + sLineBreak);
  if FServer.Restricted or not FServer.ToolAvailable('apply_code_action') then
  begin
    mSteps := mSteps + Say('2. Schlage die Korrektur als Diff vor und prüfe sie mit check_code.',
      '2. Suggest the fix as a diff and check it with check_code.') + sLineBreak + '3. ' + ReadOnlyNote(FEnglish);
  end
  else
  begin
    mSteps := mSteps + Say('2. Behebe die Ursache: mit einer der Korrekturen unten (apply_code_action mit title, ' +
      'erst dryRun) oder von Hand.' + sLineBreak + '3. Prüfe das Ergebnis mit check_code, bevor du schreibst.',
      '2. Fix the cause: with one of the fixes below (apply_code_action with title, dryRun first) or by hand.' +
      sLineBreak + '3. Check the result with check_code before writing.');
  end;
  Result := Intro(FEnglish, Format(Say('Behebe den Befund in %s, Zeile %d%s.', 'Fix the finding in %s, line %d%s.'),
    [mFile, mLine, IfThen(mRule <> '', ' (' + mRule + ')', '')])) + sLineBreak + sLineBreak + mSteps +
    sLineBreak + sLineBreak + ToolSection(Say('Befund', 'Finding'), 'explain_finding',
    FindingArgs(mFile, mLine, mRule)) + sLineBreak +
    sLineBreak + Section(Say('Codeausschnitt', 'Code snippet'), mSnippet);
  // Die Korrekturen zu listen schreibt nichts, gehört aber zu einem schreibenden Werkzeug: im eingeschränkten Modus
  // nicht anbieten (#99).
  if not FServer.Restricted and FServer.ToolAvailable('apply_code_action') then
  begin
    Result := Result + sLineBreak + sLineBreak + ToolSection(Say('Verfügbare Korrekturen', 'Available fixes'),
      'apply_code_action', FindingArgs(mFile, mLine, ''));
  end;
end;

/// <summary>Schritte von prepare_commit: Befunde, Tests, Commit-Nachricht (mit APrefix) und Freigabe.</summary>
function CommitSteps(AEnglish, ARestricted: Boolean; const APrefix: string): string;
begin
  Result := SayIn(AEnglish,
    '1. Prüfe die Befunde in den geänderten Zeilen: Fehler und Warnungen vor dem Commit beheben, den Rest nennen.' +
    sLineBreak + '2. Nenne die betroffenen Tests, die vor dem Commit laufen sollten.' + sLineBreak,
    '1. Review the findings in the changed lines: fix errors and warnings before committing, list the rest.' +
    sLineBreak + '2. List the affected tests that should run before the commit.' + sLineBreak);
  if APrefix <> '' then
  begin
    Result := Result + Format(SayIn(AEnglish, '3. Schreibe eine Commit-Nachricht, die mit "%s" beginnt: erste ' +
      'Zeile kurz, danach was und warum.', '3. Write a commit message starting with "%s": a short first line, ' +
      'then what and why.'), [APrefix]);
  end
  else
  begin
    Result := Result + SayIn(AEnglish, '3. Schreibe eine Commit-Nachricht: erste Zeile kurz, danach was und warum.',
      '3. Write a commit message: a short first line, then what and why.');
  end;
  if ARestricted then
  begin
    Result := Result + sLineBreak + '4. ' + ReadOnlyNote(AEnglish) + SayIn(AEnglish, ' Committe nicht.',
      ' Do not commit.');
  end
  else
  begin
    Result := Result + sLineBreak + SayIn(AEnglish, '4. Committe erst, wenn der Benutzer zustimmt.',
      '4. Only commit once the user agrees.');
  end;
end;

function CommitIntro(AEnglish: Boolean; const ABase: string): string;
begin
  if ABase = '' then
  begin
    Result := Intro(AEnglish, SayIn(AEnglish, 'Bereite den Commit der nicht eingecheckten Änderungen vor.',
      'Prepare the commit of the uncommitted changes.'));
  end
  else
  begin
    Result := Intro(AEnglish, Format(SayIn(AEnglish, 'Bereite den Commit der Änderungen seit %s vor.',
      'Prepare the commit of the changes since %s.'), [ABase]));
  end;
end;

/// <summary>Abschnitt mit den geänderten Dateien und neuen Befunden bzw. dem Grund, warum sie fehlen.</summary>
function ChangesSection(AEnglish: Boolean; const AChanges: TMcpChangeSet): string;
begin
  if AChanges.Error <> '' then
  begin
    Result := Section(SayIn(AEnglish, 'Geänderte Dateien', 'Changed files'), SayIn(AEnglish, 'Nicht verfügbar: ',
      'Not available: ') + AChanges.Error);
  end
  else
  begin
    Result := Section(SayIn(AEnglish, 'Geänderte Dateien und neue Befunde', 'Changed files and new findings'),
      TMcpPrompts.ChangeReport(AChanges, AEnglish));
  end;
end;

function PrefixSection(AEnglish: Boolean; const APrefix: string): string;
begin
  Result := Section(SayIn(AEnglish, 'Commit-Präfix', 'Commit prefix'), Format(SayIn(AEnglish,
    '"%s" (aktuelles Issue, issues.commitPattern)', '"%s" (current issue, issues.commitPattern)'), [APrefix]));
end;

function TMcpPrompts.PrepareCommit(const AArguments: TDictionary<string, string>): string;
var
  mBase: string;
  mChanges: TMcpChangeSet;
begin
  UseLanguage;
  mBase := Argument(AArguments, 'base');
  if Assigned(FChanges) then
  begin
    mChanges := FChanges(mBase);
  end
  else
  begin
    mChanges := Default(TMcpChangeSet);
    mChanges.Error := Say('Keine Versionsverwaltung angebunden.', 'No version control connected.');
  end;
  Result := CommitIntro(FEnglish, mBase) + sLineBreak + sLineBreak +
    CommitSteps(FEnglish, FServer.Restricted, mChanges.CommitPrefix) + sLineBreak + sLineBreak +
    ChangesSection(FEnglish, mChanges);
  // Betroffene Tests aus den Änderungen (#1353), sobald der Server das Werkzeug hat.
  if FServer.ToolAvailable('get_affected_tests') then
  begin
    Result := Result + sLineBreak + sLineBreak + ToolSection(Say('Betroffene Tests', 'Affected tests'),
      'get_affected_tests', BaseArgs(mBase));
  end
  else
  begin
    Result := Result + sLineBreak + sLineBreak + Section(Say('Betroffene Tests', 'Affected tests'), Say(
      'Ermittle sie mit get_impact für die geänderten Methoden.', 'Find them with get_impact for the changed ' +
      'methods.'));
  end;
  if mChanges.CommitPrefix <> '' then
  begin
    Result := Result + sLineBreak + sLineBreak + PrefixSection(FEnglish, mChanges.CommitPrefix);
  end;
end;

/// <summary>Einbindbarer Inhalt AInclude, der ein Werkzeug mit "unit" oder "file" aufruft: Titel, Werkzeug und
/// Name des Arguments; False für andere.</summary>
function TryFileTool(AEnglish: Boolean; const AInclude: string; out ATitle, ATool, AArgument: string): Boolean;
const
  cIncludes: array[0..6] of string = ('outline', 'dependencies', 'diagnostics', 'metrics', 'unused', 'todos',
    'form');
  cGerman: array[0..6] of string = ('Gliederung', 'Abhängigkeiten', 'Befunde', 'Metriken über Grenzwert',
    'Ungenutzter Code', 'TODO', 'Komponentenbaum');
  cEnglish: array[0..6] of string = ('Outline', 'Dependencies', 'Findings', 'Metrics above limits', 'Unused code',
    'TODO', 'Component tree');
  cTools: array[0..6] of string = ('get_unit_outline', 'get_unit_dependencies', 'get_diagnostics', 'get_metrics',
    'find_unused_code', 'get_todos', 'get_dfm_info');
  cArguments: array[0..6] of string = ('unit', 'unit', 'file', 'file', 'file', 'file', 'file');
var
  mIndex: Integer;
begin
  ATitle := '';
  ATool := '';
  AArgument := '';
  for mIndex := Low(cIncludes) to High(cIncludes) do
  begin
    if AInclude = cIncludes[mIndex] then
    begin
      ATitle := SayIn(AEnglish, cGerman[mIndex], cEnglish[mIndex]);
      ATool := cTools[mIndex];
      AArgument := cArguments[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

function TMcpPrompts.IncludeSection(const AInclude: string; const AArguments: TDictionary<string, string>): string;
var
  mFile, mUnit, mName, mTitle, mTool, mArgument: string;
begin
  mFile := Argument(AArguments, 'file');
  mUnit := Argument(AArguments, 'unit');
  mName := Argument(AArguments, 'name');
  // Datei-Werkzeuge nehmen auch eine Unit (über ResolveUnit), Unit-Werkzeuge auch einen Pfad.
  if (mFile = '') and (mUnit <> '') then
  begin
    mFile := UnitFile(FResolveUnit, mUnit);
  end;
  if mUnit = '' then
  begin
    mUnit := mFile;
  end;
  if mName = '' then
  begin
    mName := mUnit;
  end;
  if AInclude = 'conventions' then
  begin
    Result := ConventionsSection;
  end
  else if AInclude = 'lastBuild' then
  begin
    Result := ToolSection(Say('Letzter Build', 'Last build'), 'get_last_build', TJSONObject.Create);
  end
  else if (AInclude = 'impact') and (mName = '') then
  begin
    Result := Section(AInclude, Format(Say('"%s" braucht ein Argument "name".', '"%s" needs an argument ' +
      '"name".'), [AInclude]));
  end
  else if AInclude = 'impact' then
  begin
    Result := ToolSection(Say('Auswirkungen', 'Impact'), 'get_impact', 'name', mName);
  end
  else if mFile = '' then
  begin
    Result := Section(AInclude, Format(Say('"%s" braucht ein Argument "file" oder "unit".', '"%s" needs an ' +
      'argument "file" or "unit".'), [AInclude]));
  end
  else if not TryFileTool(FEnglish, AInclude, mTitle, mTool, mArgument) then
  begin
    Result := Section(AInclude, Say('Unbekannter Inhalt.', 'Unknown content.'));
  end
  else if mArgument = 'unit' then
  begin
    Result := ToolSection(mTitle, mTool, mArgument, mUnit);
  end
  else
  begin
    Result := ToolSection(mTitle, mTool, mArgument, mFile);
  end;
end;

function TMcpPrompts.RunCustom(const APrompt: TMcpCustomPrompt;
  const AArguments: TDictionary<string, string>): string;
var
  mInclude: string;
begin
  UseLanguage;
  Result := Substitute(APrompt.Text, AArguments);
  if FServer.Restricted then
  begin
    Result := Result + sLineBreak + sLineBreak + ReadOnlyNote(FEnglish);
  end;
  for mInclude in APrompt.Include do
  begin
    Result := Result + sLineBreak + sLineBreak + IncludeSection(mInclude, AArguments);
  end;
end;

function MakePrompt(const AName, ADescription: string; const AArguments: TArray<TMcpPromptArgument>;
  const AHandler: TMcpPromptHandler): TMcpPrompt;
begin
  Result.Name := AName;
  Result.Description := ADescription;
  Result.Arguments := AArguments;
  Result.Handler := AHandler;
end;

function TMcpPrompts.Builtin: TArray<TMcpPrompt>;
begin
  Result := nil;
  Result := Result + [MakePrompt('unit_review',
    Say('Code-Review einer Unit: Gliederung, Befunde, Metriken über Grenzwert, ungenutzter Code und ' +
    'Projektkonventionen in einer Nachricht.', 'Code review of a unit: outline, findings, metrics above limits, ' +
    'unused code and project conventions in one message.'),
    TArray<TMcpPromptArgument>.Create(PromptArgument('unit', Say('Unit-Name (UI.Auftrag) oder Pfad der ' +
    '.pas-Datei', 'Unit name (UI.Order) or path of the .pas file'), True)),
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := UnitReview(AArguments);
    end)];
  Result := Result + [MakePrompt('explain_form',
    Say('Erklärt ein Formular: Komponentenbaum, Ereignis-Handler mit Rümpfen und Datenbindungen.',
    'Explains a form: component tree, event handlers with bodies and data bindings.'),
    TArray<TMcpPromptArgument>.Create(PromptArgument('file', Say('Pfad der .dfm/.fmx oder der .pas dazu',
    'Path of the .dfm/.fmx or its .pas'), True)),
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := ExplainForm(AArguments);
    end)];
  Result := Result + [MakePrompt('write_tests',
    Say('Neue DUnitX-Tests für ein Symbol: Deklaration, Aufrufer, vorhandene Tests und Testkonventionen des ' +
    'Projekts.', 'New DUnitX tests for a symbol: declaration, callers, existing tests and the test conventions ' +
    'of the project.'),
    TArray<TMcpPromptArgument>.Create(PromptArgument('name', Say('Symbol, am besten qualifiziert (TFoo.Bar)',
    'Symbol, preferably qualified (TFoo.Bar)'), True)),
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := WriteTests(AArguments);
    end)];
  Result := Result + [MakePrompt('fix_finding',
    Say('Behebt einen Befund: Erklärung, Codeausschnitt und verfügbare Korrekturen; erst die Ursache, dann die ' +
    'Korrektur, dann check_code.', 'Fixes a finding: explanation, code snippet and available fixes; first the ' +
    'cause, then the fix, then check_code.'),
    TArray<TMcpPromptArgument>.Create(
    PromptArgument('file', Say('Pfad der Unit (relativ zum Projekt oder absolut)', 'Path of the unit (relative ' +
    'to the project or absolute)'), True),
    PromptArgument('line', Say('Zeile des Befunds (ab 1)', 'Line of the finding (from 1)'), True),
    PromptArgument('rule', Say('Optional: nur diese Regel', 'Optional: only this rule'), False)),
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := FixFinding(AArguments);
    end)];
  Result := Result + [MakePrompt('prepare_commit',
    Say('Bereitet einen Commit vor: geänderte Dateien, neue Befunde nur in geänderten Zeilen, betroffene Tests ' +
    'und Commit-Präfix des aktuellen Issues.', 'Prepares a commit: changed files, new findings in changed lines ' +
    'only, affected tests and the commit prefix of the current issue.'),
    TArray<TMcpPromptArgument>.Create(PromptArgument('base', Say('Optional: Vergleichsbasis, z. B. main; leer = ' +
    'nicht eingecheckte Änderungen', 'Optional: base to compare with, e.g. main; empty = uncommitted changes'),
    False)),
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := PrepareCommit(AArguments);
    end)];
end;

/// <summary>Eigene Methode: jede Methodenreferenz fängt ihren eigenen Prompt ein, nicht die Schleifenvariable.
/// </summary>
function CustomHandler(APrompts: TMcpPrompts; const APrompt: TMcpCustomPrompt): TMcpPromptHandler;
begin
  Result :=
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := APrompts.RunCustom(APrompt, AArguments);
    end;
end;

function TMcpPrompts.Custom: TArray<TMcpPrompt>;
var
  mCustom: TMcpCustomPrompt;
  mArgument: TMcpCustomPromptArgument;
  mPrompt: TMcpPrompt;
begin
  Result := nil;
  for mCustom in FSettings().McpCustomPrompts do
  begin
    mPrompt.Name := mCustom.Name;
    mPrompt.Description := mCustom.Description;
    mPrompt.Arguments := nil;
    for mArgument in mCustom.Arguments do
    begin
      mPrompt.Arguments := mPrompt.Arguments + [PromptArgument(mArgument.Name, mArgument.Description,
        mArgument.Required)];
    end;
    mPrompt.Handler := CustomHandler(Self, mCustom);
    Result := Result + [mPrompt];
  end;
end;

function TMcpPrompts.UnitResource(const AName: string): string;
var
  mFile, mText, mInterface: string;
begin
  UseLanguage;
  mFile := UnitFile(FResolveUnit, AName);
  Result := '# Unit ' + AName + sLineBreak + sLineBreak + mFile + sLineBreak + sLineBreak + '## ' +
    Say('Gliederung', 'Outline') + sLineBreak + sLineBreak + ToolText('get_unit_outline', StringArgs('unit', mFile));
  if Assigned(FReadText) and FReadText(mFile, mText) then
  begin
    mInterface := InterfacePart(mText);
    if mInterface <> '' then
    begin
      Result := Result + sLineBreak + sLineBreak + '## interface' + sLineBreak + sLineBreak + '```pascal' +
        sLineBreak + mInterface + sLineBreak + '```';
    end;
  end;
  Result := Limit(Result, MaxResourceBytes, 'get_unit_outline / get_declaration');
end;

function TMcpPrompts.FormResource(const AFile: string): string;
var
  mFile: string;
begin
  UseLanguage;
  mFile := FormFile(AFile);
  Result := Limit('# ' + Say('Formular ', 'Form ') + mFile + sLineBreak + sLineBreak +
    ToolText('get_dfm_info', StringArgs('file', mFile)), MaxResourceBytes, 'get_dfm_info');
end;

function TMcpPrompts.FindingsResource(const AFile: string): string;
var
  mFile: string;
begin
  UseLanguage;
  mFile := CheckedFile(FResolveFile, AFile);
  Result := Limit('# ' + Say('Befunde ', 'Findings ') + mFile + sLineBreak + sLineBreak +
    ToolText('get_diagnostics', StringArgs('file', mFile)), MaxResourceBytes, 'get_diagnostics');
end;

function TMcpPrompts.BuildResource: string;
begin
  UseLanguage;
  Result := Limit('# ' + Say('Letzter Build', 'Last build') + sLineBreak + sLineBreak +
    ToolText('get_last_build', TJSONObject.Create), MaxResourceBytes, 'get_last_build');
end;

procedure TMcpPrompts.Register;
begin
  FServer.OnPrompts :=
    function: TArray<TMcpPrompt>
    begin
      UseLanguage;
      Result := Builtin + Custom;
    end;
  FServer.OnPromptsEnabled :=
    function: Boolean
    begin
      Result := FSettings().McpPrompts;
    end;
  FServer.AddResourceTemplate('delphi://unit/{name}', 'Unit',
    'Gliederung und interface-Teil einer Unit des Projekts als Markdown (höchstens 64 KB).', 'text/markdown',
    function(const AValue: string): string
    begin
      Result := UnitResource(AValue);
    end);
  FServer.AddResourceTemplate('delphi://form/{file}', 'Formular',
    'Komponentenbaum eines Formulars (.dfm/.fmx oder die .pas dazu) als Markdown.', 'text/markdown',
    function(const AValue: string): string
    begin
      Result := FormResource(AValue);
    end);
  FServer.AddResourceTemplate('delphi://findings/{file}', 'Befunde',
    'Syntaxfehler und Befunde der Prüfregeln einer Datei als Markdown.', 'text/markdown',
    function(const AValue: string): string
    begin
      Result := FindingsResource(AValue);
    end);
  FServer.AddPromptResource('delphi://build/last', 'Letzter Build',
    'Ergebnis und Compilermeldungen des letzten Builds in der IDE wie get_last_build.', 'text/markdown',
    function: string
    begin
      Result := BuildResource;
    end);
end;

end.
