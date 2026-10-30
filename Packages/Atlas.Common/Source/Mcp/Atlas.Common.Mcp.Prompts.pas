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
    function Section(const ATitle, ABody: string): string;
    function ToolSection(const ATitle, ATool: string; const AArguments: TJSONObject): string; overload;
    function ToolSection(const ATitle, ATool, AName, AValue: string): string; overload;
    function ConventionsSection: string;
    function UnitFile(const AUnit: string): string;
    function CheckedFile(const AFile: string): string;
    function FormFile(const AFile: string): string;
    function ReadLines(const AFileName: string): TArray<string>;
    function Intro(const AText: string): string;
    function ReadOnlyNote: string;
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
    Result.AddPair('base', ABase);
end;

/// <summary>file und line, dazu rule, wenn angegeben.</summary>
function FindingArgs(const AFile: string; ALine: Integer; const ARule: string): TJSONObject;
begin
  Result := StringArgs('file', AFile);
  Result.AddPair('line', TJSONNumber.Create(ALine));
  if ARule <> '' then
    Result.AddPair('rule', ARule);
end;

function Argument(const AArguments: TDictionary<string, string>; const AName: string): string;
begin
  if not AArguments.TryGetValue(AName, Result) then
    Result := '';
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

function TMcpPrompts.Say(const AGerman, AEnglish: string): string;
begin
  if FEnglish then
    Result := AEnglish
  else
    Result := AGerman;
end;

class function TMcpPrompts.Limit(const AText: string; AMaxBytes: Integer; const ATool: string): string;
var
  mNote: string;
  mCount, mBytes, mTarget, mBreak: Integer;
begin
  if Utf8Length(AText) <= AMaxBytes then
    Exit(AText);
  if ATool <> '' then
    mNote := Format(sLineBreak + sLineBreak + '… gekürzt auf %d KB; vollständig mit %s.', [AMaxBytes div 1024, ATool])
  else
    mNote := Format(sLineBreak + sLineBreak + '… gekürzt auf %d KB.', [AMaxBytes div 1024]);
  mTarget := AMaxBytes - Utf8Length(mNote);
  mCount := Length(AText);
  if mCount > mTarget then
    mCount := mTarget;
  mBytes := Utf8Length(Copy(AText, 1, mCount));
  while (mCount > 0) and (mBytes > mTarget) do
  begin
    // Umlaute und andere Zeichen brauchen mehr als ein Byte: in Schritten an das Ziel heran.
    if (mBytes - mTarget) div 2 > 1 then
      Dec(mCount, (mBytes - mTarget) div 2)
    else
      Dec(mCount);
    mBytes := Utf8Length(Copy(AText, 1, mCount));
  end;
  // Keine halbe Zeile am Ende.
  mBreak := mCount;
  while (mBreak > 0) and (AText[mBreak] <> #10) do
    Dec(mBreak);
  if mBreak > 0 then
    mCount := mBreak - 1;
  Result := TrimRight(Copy(AText, 1, mCount)) + mNote;
end;

class function TMcpPrompts.Substitute(const AText: string; const AArguments: TDictionary<string, string>): string;
var
  mPair: TPair<string, string>;
begin
  Result := AText;
  for mPair in AArguments do
    Result := StringReplace(Result, '{' + mPair.Key + '}', mPair.Value, [rfReplaceAll]);
end;

function LinesOf(const ALines: TArray<string>; AFirst, ALast: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := AFirst to ALast do
      if (mIndex >= 0) and (mIndex < Length(ALines)) then
        mBuilder.Append(ALines[mIndex]).Append(sLineBreak);
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
      Exit;
    mSection := mTree.Root.FindChild(TSyntaxKind.InterfaceSection);
    if mSection <> nil then
      Result := LinesOf(TTextLines.SplitLines(AText), mSection.StartPos.Line, mSection.EndPos.Line);
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
    if mProperty.IsEvent and (Trim(mProperty.Value) <> '') then
    begin
      mKey := Trim(mProperty.Value);
      mWhere := AObject.Name + '.' + mProperty.Name;
      if AUses.TryGetValue(LowerCase(mKey), mKnown) then
        AUses[LowerCase(mKey)] := mKnown + ', ' + mWhere
      else
      begin
        AUses.Add(LowerCase(mKey), mWhere);
        AHandlers.Add(mKey);
      end;
    end;
  for mChild in AObject.Children do
    CollectEvents(mChild, AHandlers, AUses);
end;

class function TMcpPrompts.HandlerBodies(const AFormText, AUnitText: string): string;
var
  mDocument: TDfmDocument;
  mTree: TSyntaxTree;
  mSection, mRoutine: TSyntaxNode;
  mHandlers: TList<string>;
  mUses: TDictionary<string, string>;
  mLines: TArray<string>;
  mBuilder: TStringBuilder;
  mHandler, mFormClass: string;
  mIndex: Integer;
begin
  mDocument := TDfmParser.Parse(AFormText);
  mHandlers := TList<string>.Create;
  mUses := TDictionary<string, string>.Create;
  mBuilder := TStringBuilder.Create;
  mTree := nil;
  try
    if mDocument.Root = nil then
      Exit('');
    mFormClass := mDocument.Root.TypeName;
    CollectEvents(mDocument.Root, mHandlers, mUses);
    if mHandlers.Count = 0 then
      Exit('');
    mLines := TTextLines.SplitLines(AUnitText);
    mSection := nil;
    if AUnitText <> '' then
    begin
      mTree := TSyntaxTreeCache.Parse(AUnitText);
      if (mTree <> nil) and (mTree.Root <> nil) then
        mSection := mTree.Root.FindChild(TSyntaxKind.ImplementationSection);
    end;
    for mHandler in mHandlers do
    begin
      mRoutine := nil;
      if mSection <> nil then
        for mIndex := 0 to mSection.ChildCount - 1 do
          if (mSection[mIndex].Kind = TSyntaxKind.RoutineDecl) and
            SameText(mSection[mIndex].Name, mFormClass + '.' + mHandler) then
          begin
            mRoutine := mSection[mIndex];
            Break;
          end;
      if mBuilder.Length > 0 then
        mBuilder.Append(sLineBreak).Append(sLineBreak);
      mBuilder.Append(Format('%s (%s)', [mHandler, mUses[LowerCase(mHandler)]]));
      if mRoutine = nil then
        mBuilder.Append(sLineBreak).Append('  Implementierung nicht gefunden.')
      else
        mBuilder.Append(Format(', Zeile %d:', [mRoutine.StartPos.Line + 1])).Append(sLineBreak)
          .Append('```pascal').Append(sLineBreak)
          .Append(LinesOf(mLines, mRoutine.StartPos.Line, mRoutine.EndPos.Line)).Append(sLineBreak)
          .Append('```');
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
    if SameText(mName, AName) then
      Exit(True);
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
    if IsBindingProperty(AObject.TypeName, mProperty.Name) then
    begin
      if mLine <> '' then
        mLine := mLine + ', ';
      mLine := mLine + mProperty.Name + ' = ' + Trim(mProperty.Value);
    end;
  if mLine <> '' then
    ABuilder.Append(Format('- %s: %s – %s', [AObject.Name, AObject.TypeName, mLine])).Append(sLineBreak);
  for mChild in AObject.Children do
    CollectBindings(mChild, ABuilder);
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
      CollectBindings(mDocument.Root, mBuilder);
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
    mFirst := 1;
  mLast := ALine + AContext;
  if mLast > Length(ALines) then
    mLast := Length(ALines);
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := mFirst to mLast do
    begin
      mMarker := ' ';
      if mIndex = ALine then
        mMarker := '>';
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
      Inc(mCount, Length(mFile.Findings));
    if AEnglish then
      mBuilder.Append(Format('%s, compared with %s: %d changed files, %d new findings in changed lines.',
        [AChanges.Vcs, AChanges.Base, Length(AChanges.Files), mCount]))
    else
      mBuilder.Append(Format('%s, verglichen mit %s: %d geänderte Dateien, %d neue Befunde in geänderten Zeilen.',
        [AChanges.Vcs, AChanges.Base, Length(AChanges.Files), mCount]));
    mBuilder.Append(sLineBreak);
    for mFile in AChanges.Files do
    begin
      mBuilder.Append(sLineBreak).Append('- ').Append(mFile.Path);
      for mFinding in mFile.Findings do
        mBuilder.Append(sLineBreak).Append(Format('  - %d:%d: %s [%s] %s', [mFinding.Range.StartPos.Line + 1,
          mFinding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(mFinding.Severity), mFinding.RuleId,
          mFinding.Message]));
    end;
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

function TMcpPrompts.Section(const ATitle, ABody: string): string;
begin
  Result := '## ' + ATitle + sLineBreak + sLineBreak + Limit(TrimRight(ABody), MaxSectionBytes, '');
end;

function TMcpPrompts.ToolSection(const ATitle, ATool: string; const AArguments: TJSONObject): string;
var
  mText: string;
begin
  try
    if FServer.InvokeTool(ATool, AArguments, mText) then
      Result := '## ' + ATitle + ' (' + ATool + ')' + sLineBreak + sLineBreak +
        Limit(TrimRight(mText), MaxSectionBytes, ATool)
    else
      Result := '## ' + ATitle + ' (' + ATool + ')' + sLineBreak + sLineBreak +
        Say('Nicht verfügbar: ', 'Not available: ') + mText;
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
      raise EMcpToolError.Create(Result);
  finally
    AArguments.Free;
  end;
end;

function TMcpPrompts.ConventionsSection: string;
var
  mText: string;
begin
  if FServer.ReadResourceText(ConventionsUri, mText) then
    Result := Section(Say('Projektkonventionen', 'Project conventions') + ' (' + ConventionsUri + ')', mText)
  else
    Result := Section(Say('Projektkonventionen', 'Project conventions'),
      Say('Nicht verfügbar.', 'Not available.'));
end;

function TMcpPrompts.UnitFile(const AUnit: string): string;
begin
  if not Assigned(FResolveUnit) then
    raise EMcpToolError.CreateFmt('Unit "%s" lässt sich hier nicht auflösen', [AUnit]);
  Result := FResolveUnit(AUnit);
end;

function TMcpPrompts.CheckedFile(const AFile: string): string;
begin
  if not Assigned(FResolveFile) then
    raise EMcpToolError.CreateFmt('Datei "%s" lässt sich hier nicht auflösen', [AFile]);
  Result := FResolveFile(AFile);
end;

function TMcpPrompts.FormFile(const AFile: string): string;
var
  mText: string;
begin
  Result := CheckedFile(AFile);
  if SameText(ExtractFileExt(Result), '.pas') then
  begin
    if Assigned(FReadText) and FReadText(ChangeFileExt(Result, '.dfm'), mText) then
      Result := ChangeFileExt(Result, '.dfm')
    else
      Result := ChangeFileExt(Result, '.fmx');
  end;
  if not TDfmParser.IsFormFile(Result) then
    raise EMcpToolError.CreateFmt('"%s" ist keine Formulardatei (.dfm, .fmx oder die .pas dazu)', [AFile]);
end;

function TMcpPrompts.ReadLines(const AFileName: string): TArray<string>;
var
  mText: string;
begin
  Result := nil;
  if Assigned(FReadText) and FReadText(AFileName, mText) then
    Result := TTextLines.SplitLines(mText);
end;

function TMcpPrompts.Intro(const AText: string): string;
begin
  Result := AText + sLineBreak + sLineBreak + Say(
    'Die Daten unten hat der Atlas-Server eben ermittelt. Rufe dafür keine Werkzeuge erneut auf; frage nur nach, ' +
    'was hier fehlt.',
    'The Atlas server has just collected the data below. Do not call tools again for it; only ask for what is ' +
    'missing here.');
end;

function TMcpPrompts.ReadOnlyNote: string;
begin
  Result := Say('Eingeschränkter Modus (--restricted): Ändere keine Dateien, schreibe Vorschläge als Diff in die ' +
    'Antwort.', 'Restricted mode (--restricted): do not change any files, put suggestions as a diff into your ' +
    'answer.');
end;

function TMcpPrompts.UnitReview(const AArguments: TDictionary<string, string>): string;
var
  mUnit, mFile, mSteps: string;
begin
  UseLanguage;
  mUnit := Argument(AArguments, 'unit');
  mFile := UnitFile(mUnit);
  mSteps := Say(
    '1. Ordne die Punkte nach Schweregrad: Fehler, Warnungen, dann Hinweise und Stil. Fasse gleichartige zusammen.' +
    sLineBreak +
    '2. Nenne je Punkt Datei:Zeile, die Ursache und einen konkreten Vorschlag mit Codeausschnitt.' + sLineBreak +
    '3. Beziehe Metriken über dem Grenzwert, ungenutzten Code und die Projektkonventionen ein.' + sLineBreak,
    '1. Order the points by severity: errors, warnings, then hints and style. Group similar ones.' + sLineBreak +
    '2. For each point give file:line, the cause and a concrete suggestion with a code snippet.' + sLineBreak +
    '3. Take methods above the metric limits, unused code and the project conventions into account.' + sLineBreak);
  if FServer.Restricted then
    mSteps := mSteps + '4. ' + ReadOnlyNote + Say(' Prüfe jeden Vorschlag mit check_code.',
      ' Check every suggestion with check_code.')
  else
    mSteps := mSteps + Say('4. Prüfe jede Änderung vor dem Schreiben mit check_code und ändere erst nach Rückfrage.',
      '4. Check every change with check_code before writing it, and only change code after asking.');
  Result := Intro(Format(Say('Führe ein Code-Review der Unit %s (%s) durch.', 'Review the unit %s (%s).'),
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
    raise EMcpToolError.CreateFmt('Formulardatei "%s" nicht gefunden', [mFile]);
  if not FReadText(ChangeFileExt(mFile, '.pas'), mUnitText) then
    mUnitText := '';
  mBodies := HandlerBodies(mFormText, mUnitText);
  if mBodies = '' then
    mBodies := Say('Keine Ereignis-Handler.', 'No event handlers.');
  mBindings := DataBindings(mFormText);
  if mBindings = '' then
    mBindings := Say('Keine Datenbindungen.', 'No data bindings.');
  Result := Intro(Format(Say('Erkläre das Formular %s.', 'Explain the form %s.'), [mFile])) + sLineBreak +
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
  mName, mSteps, mConventions: string;
  mSettings: TServerSettings;
begin
  UseLanguage;
  mName := Argument(AArguments, 'name');
  mSettings := FSettings();
  mConventions := Format(Say(
    'Name der Testunit: %s ({unit} = getestete Unit). Ordner neuer Testunits: %s. Testprojekt: %s.' + sLineBreak +
    'DUnitX: [TestFixture] je Klasse, [Test] je Methode, Assert.AreEqual(Erwartet, Ist), Fixture in initialization ' +
    'mit TDUnitX.RegisterTestFixture registrieren; eine neue Testunit gehört auch ins Testprojekt (.dpr und .dproj).',
    'Test unit name: %s ({unit} = unit under test). Folder for new test units: %s. Test project: %s.' + sLineBreak +
    'DUnitX: [TestFixture] per class, [Test] per method, Assert.AreEqual(Expected, Actual), register the fixture ' +
    'with TDUnitX.RegisterTestFixture in initialization; a new test unit also goes into the test project (.dpr ' +
    'and .dproj).'), [mSettings.TestUnits.Pattern,
    IfThen(mSettings.TestUnits.Folder <> '', mSettings.TestUnits.Folder, Say('Ordner des Testprojekts',
    'folder of the test project')), IfThen(mSettings.TestUnits.Project <> '', mSettings.TestUnits.Project,
    Say('automatisch erkannt', 'detected automatically'))]);
  mSteps := Say(
    '1. Lege Testmethoden für normale Fälle, Grenzfälle und Fehlerfälle an; vorhandene Tests (unten) nicht doppeln.' +
    sLineBreak + '2. Schreibe sie in die passende Testunit nach den Konventionen unten.' + sLineBreak,
    '1. Add test methods for normal cases, edge cases and error cases; do not duplicate the existing tests below.' +
    sLineBreak + '2. Put them into the matching test unit following the conventions below.' + sLineBreak);
  if FServer.Restricted then
    mSteps := mSteps + '3. ' + ReadOnlyNote
  else if FServer.ToolAvailable('run_tests') then
    mSteps := mSteps + Say('3. Prüfe den Code mit check_code, dann führe die neuen Tests mit run_tests aus ' +
      '(tests: Unit.Fixture.Methode) und behebe Fehlschläge.', '3. Check the code with check_code, then run the ' +
      'new tests with run_tests (tests: Unit.Fixture.Method) and fix failures.')
  else
    mSteps := mSteps + Say('3. Prüfe den Code mit check_code; run_tests ist hier nicht verfügbar, nenne die Tests ' +
      'zum Ausführen.', '3. Check the code with check_code; run_tests is not available here, list the tests to run.');
  Result := Intro(Format(Say('Schreibe DUnitX-Tests für %s.', 'Write DUnitX tests for %s.'), [mName])) +
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
  mFile := CheckedFile(Argument(AArguments, 'file'));
  if not TryStrToInt(Argument(AArguments, 'line'), mLine) or (mLine < 1) then
    raise EMcpToolError.Create(Say('"line" muss eine Zeilennummer ab 1 sein', '"line" must be a line number from 1'));
  mRule := Argument(AArguments, 'rule');
  mLines := ReadLines(mFile);
  if mLines = nil then
    raise EMcpToolError.CreateFmt(Say('%s ist nicht lesbar', '%s cannot be read'), [mFile]);
  if mLine > Length(mLines) then
    raise EMcpToolError.CreateFmt(Say('%s hat nur %d Zeilen', '%s has only %d lines'), [mFile, Length(mLines)]);
  mSnippet := '```pascal' + sLineBreak + Snippet(mLines, mLine, SnippetContext) + sLineBreak + '```';
  mSteps := Say('1. Erkläre zuerst die Ursache des Befunds in diesem Code, nicht nur die Regel.' + sLineBreak,
    '1. First explain the cause of the finding in this code, not just the rule.' + sLineBreak);
  if FServer.Restricted or not FServer.ToolAvailable('apply_code_action') then
    mSteps := mSteps + Say('2. Schlage die Korrektur als Diff vor und prüfe sie mit check_code.',
      '2. Suggest the fix as a diff and check it with check_code.') + sLineBreak + '3. ' + ReadOnlyNote
  else
    mSteps := mSteps + Say('2. Behebe die Ursache: mit einer der Korrekturen unten (apply_code_action mit title, ' +
      'erst dryRun) oder von Hand.' + sLineBreak + '3. Prüfe das Ergebnis mit check_code, bevor du schreibst.',
      '2. Fix the cause: with one of the fixes below (apply_code_action with title, dryRun first) or by hand.' +
      sLineBreak + '3. Check the result with check_code before writing.');
  Result := Intro(Format(Say('Behebe den Befund in %s, Zeile %d%s.', 'Fix the finding in %s, line %d%s.'),
    [mFile, mLine, IfThen(mRule <> '', ' (' + mRule + ')', '')])) + sLineBreak + sLineBreak + mSteps +
    sLineBreak + sLineBreak + ToolSection(Say('Befund', 'Finding'), 'explain_finding',
    FindingArgs(mFile, mLine, mRule)) + sLineBreak +
    sLineBreak + Section(Say('Codeausschnitt', 'Code snippet'), mSnippet);
  // Die Korrekturen zu listen schreibt nichts, gehört aber zu einem schreibenden Werkzeug: im eingeschränkten Modus
  // nicht anbieten (#99).
  if not FServer.Restricted and FServer.ToolAvailable('apply_code_action') then
    Result := Result + sLineBreak + sLineBreak + ToolSection(Say('Verfügbare Korrekturen', 'Available fixes'),
      'apply_code_action', FindingArgs(mFile, mLine, ''));
end;

function TMcpPrompts.PrepareCommit(const AArguments: TDictionary<string, string>): string;
var
  mBase, mSteps, mPrefix: string;
  mChanges: TMcpChangeSet;
begin
  UseLanguage;
  mBase := Argument(AArguments, 'base');
  if Assigned(FChanges) then
    mChanges := FChanges(mBase)
  else
  begin
    mChanges := Default(TMcpChangeSet);
    mChanges.Error := Say('Keine Versionsverwaltung angebunden.', 'No version control connected.');
  end;
  mPrefix := mChanges.CommitPrefix;
  mSteps := Say(
    '1. Prüfe die Befunde in den geänderten Zeilen: Fehler und Warnungen vor dem Commit beheben, den Rest nennen.' +
    sLineBreak + '2. Nenne die betroffenen Tests, die vor dem Commit laufen sollten.' + sLineBreak,
    '1. Review the findings in the changed lines: fix errors and warnings before committing, list the rest.' +
    sLineBreak + '2. List the affected tests that should run before the commit.' + sLineBreak);
  if mPrefix <> '' then
    mSteps := mSteps + Format(Say('3. Schreibe eine Commit-Nachricht, die mit "%s" beginnt: erste Zeile kurz, ' +
      'danach was und warum.', '3. Write a commit message starting with "%s": a short first line, then what and why.'),
      [mPrefix])
  else
    mSteps := mSteps + Say('3. Schreibe eine Commit-Nachricht: erste Zeile kurz, danach was und warum.',
      '3. Write a commit message: a short first line, then what and why.');
  if FServer.Restricted then
    mSteps := mSteps + sLineBreak + '4. ' + ReadOnlyNote + Say(' Committe nicht.', ' Do not commit.')
  else
    mSteps := mSteps + sLineBreak + Say('4. Committe erst, wenn der Benutzer zustimmt.',
      '4. Only commit once the user agrees.');
  if mBase = '' then
    Result := Intro(Say('Bereite den Commit der nicht eingecheckten Änderungen vor.',
      'Prepare the commit of the uncommitted changes.'))
  else
    Result := Intro(Format(Say('Bereite den Commit der Änderungen seit %s vor.',
      'Prepare the commit of the changes since %s.'), [mBase]));
  Result := Result + sLineBreak + sLineBreak + mSteps + sLineBreak + sLineBreak;
  if mChanges.Error <> '' then
    Result := Result + Section(Say('Geänderte Dateien', 'Changed files'), Say('Nicht verfügbar: ',
      'Not available: ') + mChanges.Error)
  else
    Result := Result + Section(Say('Geänderte Dateien und neue Befunde', 'Changed files and new findings'),
      ChangeReport(mChanges, FEnglish));
  // Betroffene Tests aus den Änderungen (#1353), sobald der Server das Werkzeug hat.
  if FServer.ToolAvailable('get_affected_tests') then
    Result := Result + sLineBreak + sLineBreak + ToolSection(Say('Betroffene Tests', 'Affected tests'),
      'get_affected_tests', BaseArgs(mBase))
  else
    Result := Result + sLineBreak + sLineBreak + Section(Say('Betroffene Tests', 'Affected tests'), Say(
      'Ermittle sie mit get_impact für die geänderten Methoden.', 'Find them with get_impact for the changed ' +
      'methods.'));
  if mPrefix <> '' then
    Result := Result + sLineBreak + sLineBreak + Section(Say('Commit-Präfix', 'Commit prefix'),
      Format(Say('"%s" (aktuelles Issue, issues.commitPattern)', '"%s" (current issue, issues.commitPattern)'),
      [mPrefix]));
end;

function TMcpPrompts.IncludeSection(const AInclude: string; const AArguments: TDictionary<string, string>): string;
var
  mFile, mUnit, mName: string;
  mMissing: string;
begin
  mFile := Argument(AArguments, 'file');
  mUnit := Argument(AArguments, 'unit');
  mName := Argument(AArguments, 'name');
  // Datei-Werkzeuge nehmen auch eine Unit (über ResolveUnit), Unit-Werkzeuge auch einen Pfad.
  if (mFile = '') and (mUnit <> '') then
    mFile := UnitFile(mUnit);
  if mUnit = '' then
    mUnit := mFile;
  if mName = '' then
    mName := mUnit;
  mMissing := Format(Say('"%s" braucht ein Argument "file" oder "unit".', '"%s" needs an argument "file" or ' +
    '"unit".'), [AInclude]);
  if AInclude = 'conventions' then
    Result := ConventionsSection
  else if AInclude = 'lastBuild' then
    Result := ToolSection(Say('Letzter Build', 'Last build'), 'get_last_build', TJSONObject.Create)
  else if AInclude = 'impact' then
  begin
    if mName = '' then
      Result := Section(AInclude, Format(Say('"%s" braucht ein Argument "name".', '"%s" needs an argument ' +
        '"name".'), [AInclude]))
    else
      Result := ToolSection(Say('Auswirkungen', 'Impact'), 'get_impact', 'name', mName);
  end
  else if mFile = '' then
    Result := Section(AInclude, mMissing)
  else if AInclude = 'outline' then
    Result := ToolSection(Say('Gliederung', 'Outline'), 'get_unit_outline', 'unit', mUnit)
  else if AInclude = 'dependencies' then
    Result := ToolSection(Say('Abhängigkeiten', 'Dependencies'), 'get_unit_dependencies', 'unit', mUnit)
  else if AInclude = 'diagnostics' then
    Result := ToolSection(Say('Befunde', 'Findings'), 'get_diagnostics', 'file', mFile)
  else if AInclude = 'metrics' then
    Result := ToolSection(Say('Metriken über Grenzwert', 'Metrics above limits'), 'get_metrics', 'file', mFile)
  else if AInclude = 'unused' then
    Result := ToolSection(Say('Ungenutzter Code', 'Unused code'), 'find_unused_code', 'file', mFile)
  else if AInclude = 'todos' then
    Result := ToolSection('TODO', 'get_todos', 'file', mFile)
  else if AInclude = 'form' then
    Result := ToolSection(Say('Komponentenbaum', 'Component tree'), 'get_dfm_info', 'file', mFile)
  else
    Result := Section(AInclude, Say('Unbekannter Inhalt.', 'Unknown content.'));
end;

function TMcpPrompts.RunCustom(const APrompt: TMcpCustomPrompt;
  const AArguments: TDictionary<string, string>): string;
var
  mInclude: string;
begin
  UseLanguage;
  Result := Substitute(APrompt.Text, AArguments);
  if FServer.Restricted then
    Result := Result + sLineBreak + sLineBreak + ReadOnlyNote;
  for mInclude in APrompt.Include do
    Result := Result + sLineBreak + sLineBreak + IncludeSection(mInclude, AArguments);
end;

function TMcpPrompts.Builtin: TArray<TMcpPrompt>;
var
  mPrompt: TMcpPrompt;
begin
  Result := nil;
  mPrompt.Name := 'unit_review';
  mPrompt.Description := Say('Code-Review einer Unit: Gliederung, Befunde, Metriken über Grenzwert, ungenutzter ' +
    'Code und Projektkonventionen in einer Nachricht.', 'Code review of a unit: outline, findings, metrics above ' +
    'limits, unused code and project conventions in one message.');
  mPrompt.Arguments := TArray<TMcpPromptArgument>.Create(PromptArgument('unit', Say('Unit-Name (UI.Auftrag) ' +
    'oder Pfad der .pas-Datei', 'Unit name (UI.Order) or path of the .pas file'), True));
  mPrompt.Handler :=
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := UnitReview(AArguments);
    end;
  Result := Result + [mPrompt];
  mPrompt.Name := 'explain_form';
  mPrompt.Description := Say('Erklärt ein Formular: Komponentenbaum, Ereignis-Handler mit Rümpfen und ' +
    'Datenbindungen.', 'Explains a form: component tree, event handlers with bodies and data bindings.');
  mPrompt.Arguments := TArray<TMcpPromptArgument>.Create(PromptArgument('file', Say('Pfad der .dfm/.fmx oder ' +
    'der .pas dazu', 'Path of the .dfm/.fmx or its .pas'), True));
  mPrompt.Handler :=
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := ExplainForm(AArguments);
    end;
  Result := Result + [mPrompt];
  mPrompt.Name := 'write_tests';
  mPrompt.Description := Say('Neue DUnitX-Tests für ein Symbol: Deklaration, Aufrufer, vorhandene Tests und ' +
    'Testkonventionen des Projekts.', 'New DUnitX tests for a symbol: declaration, callers, existing tests and the ' +
    'test conventions of the project.');
  mPrompt.Arguments := TArray<TMcpPromptArgument>.Create(PromptArgument('name', Say('Symbol, am besten ' +
    'qualifiziert (TFoo.Bar)', 'Symbol, preferably qualified (TFoo.Bar)'), True));
  mPrompt.Handler :=
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := WriteTests(AArguments);
    end;
  Result := Result + [mPrompt];
  mPrompt.Name := 'fix_finding';
  mPrompt.Description := Say('Behebt einen Befund: Erklärung, Codeausschnitt und verfügbare Korrekturen; erst die ' +
    'Ursache, dann die Korrektur, dann check_code.', 'Fixes a finding: explanation, code snippet and available ' +
    'fixes; first the cause, then the fix, then check_code.');
  mPrompt.Arguments := TArray<TMcpPromptArgument>.Create(
    PromptArgument('file', Say('Pfad der Unit (relativ zum Projekt oder absolut)', 'Path of the unit (relative ' +
      'to the project or absolute)'), True),
    PromptArgument('line', Say('Zeile des Befunds (ab 1)', 'Line of the finding (from 1)'), True),
    PromptArgument('rule', Say('Optional: nur diese Regel', 'Optional: only this rule'), False));
  mPrompt.Handler :=
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := FixFinding(AArguments);
    end;
  Result := Result + [mPrompt];
  mPrompt.Name := 'prepare_commit';
  mPrompt.Description := Say('Bereitet einen Commit vor: geänderte Dateien, neue Befunde nur in geänderten ' +
    'Zeilen, betroffene Tests und Commit-Präfix des aktuellen Issues.', 'Prepares a commit: changed files, new ' +
    'findings in changed lines only, affected tests and the commit prefix of the current issue.');
  mPrompt.Arguments := TArray<TMcpPromptArgument>.Create(PromptArgument('base', Say('Optional: Vergleichsbasis, ' +
    'z. B. main; leer = nicht eingecheckte Änderungen', 'Optional: base to compare with, e.g. main; empty = ' +
    'uncommitted changes'), False));
  mPrompt.Handler :=
    function(const AArguments: TDictionary<string, string>): string
    begin
      Result := PrepareCommit(AArguments);
    end;
  Result := Result + [mPrompt];
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
      mPrompt.Arguments := mPrompt.Arguments + [PromptArgument(mArgument.Name, mArgument.Description,
        mArgument.Required)];
    mPrompt.Handler := CustomHandler(Self, mCustom);
    Result := Result + [mPrompt];
  end;
end;

function TMcpPrompts.UnitResource(const AName: string): string;
var
  mFile, mText, mInterface: string;
begin
  UseLanguage;
  mFile := UnitFile(AName);
  Result := '# Unit ' + AName + sLineBreak + sLineBreak + mFile + sLineBreak + sLineBreak + '## ' +
    Say('Gliederung', 'Outline') + sLineBreak + sLineBreak + ToolText('get_unit_outline', StringArgs('unit', mFile));
  if Assigned(FReadText) and FReadText(mFile, mText) then
  begin
    mInterface := InterfacePart(mText);
    if mInterface <> '' then
      Result := Result + sLineBreak + sLineBreak + '## interface' + sLineBreak + sLineBreak + '```pascal' +
        sLineBreak + mInterface + sLineBreak + '```';
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
  mFile := CheckedFile(AFile);
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
