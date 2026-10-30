unit Atlas.Common.Configuration.Parser;

// Liest atlas.json und prüft sie. Fehlerhafte Einträge werden mit
// Position gemeldet und ignoriert; der Rest gilt trotzdem. Bei einem
// Syntaxfehler gelten die Vorgaben.
//
// ParseLayered führt Einstellungen aus dem Editor (z. B. VS-Code-Settings)
// mit atlas.json zusammen: Jeder Schlüssel, den die Datei setzt, hat
// Vorrang; Regeln werden je Regel-Id zusammengeführt.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract;

type
  TConfigurationParser = class
  public
    class function Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings; static;
    /// <summary>Editor-Einstellungen (JSON, '' = keine) unter atlas.json (Text, '' = keine Datei).
    /// AIssues betreffen nur die Datei.</summary>
    class function ParseLayered(const AEditorText, AFileText: string;
      out AIssues: TArray<TConfigurationIssue>): TServerSettings; static;
    /// <summary>Führt zwei Ebenen im Format von atlas.json zu einem JSON-Text zusammen (#227: globale
    /// Benutzerdatei unter den Editor-Einstellungen). AUpper hat je Schlüssel Vorrang; Objekte (rules,
    /// format …) werden je Schlüssel zusammengeführt, Listen ersetzt. Leerer oder ungültiger Text zählt als
    /// nicht da.</summary>
    class function MergeText(const ALower, AUpper: string): string; static;
    /// <summary>Schweregrad aus dem Text ("off", "hint", "info", "information", "warning", "error").</summary>
    class function TryParseSeverity(const AValue: string; out ASeverity: TRuleSeverity): Boolean; static;
    /// <summary>Konfidenz aus dem Text ("low", "medium", "high").</summary>
    class function TryParseConfidence(const AValue: string; out AConfidence: TRuleConfidence): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Internals.JsonTree;

const
  /// <summary>Optionen von Prüfregeln, die true oder false sein müssen (#909).</summary>
  BooleanRuleOptions: array[0..24] of string = ('allowCommented', 'requireElse', 'ignoreStrings', 'ignoreComments',
    'includeRecords', 'includeFormVariables', 'checkUses', 'allowLazyInit', 'checkRound', 'includeFields',
    'allowSingleLineExit', 'allowSameLine', 'allowComments', 'onlyAfterRaisingCode', 'allowInProgram', 'unitLevel',
    'testsCountAsUse', 'stringLiteralsCountAsUse', 'allowShareMem', 'ignoreOverrides', 'requirePublic',
    'checkReturns', 'checkFree', 'allowFirstElement', 'implementation');
  /// <summary>Optionen von Prüfregeln, die eine Liste von Texten sein müssen (#909).</summary>
  StringListRuleOptions: array[0..33] of string = ('countNames', 'mutatingMethods', 'ignoreMethods', 'ignoreTypes',
    'methods', 'allowIn', 'functions', 'sources', 'ignore', 'assertPatterns', 'selfRegistering', 'swallow', 'calls',
    'allowTables', 'types', 'allowProperties', 'threadSafeTypes', 'switchConstants', 'namePatterns', 'kinds',
    'statements', 'disabledChecks', 'componentClasses', 'visibilities', 'memberKinds', 'projectKinds',
    'keepAttributes', 'keepPatterns', 'allowUnits', 'allow', 'allowAttributes', 'allowTypes',
    'formatMethods', 'unitKinds');
  /// <summary>Erlaubte Einträge von kinds bei deprecated-symbol (#1018).</summary>
  DeprecationKinds: array[0..3] of string = ('deprecated', 'experimental', 'platform', 'library');
  /// <summary>Erlaubte Arten in symbols von forbidden-symbol (#1133); wie TForbiddenSymbolRule.TryParseKind.</summary>
  ForbiddenSymbolKinds: array[0..6] of string = ('routine', 'type', 'constant', 'field', 'property', 'enumValue',
    'identifier');
  /// <summary>Optionen von Prüfregeln, die eine Liste von Zahlen sein müssen (#937).</summary>
  NumberListRuleOptions: array[0..0] of string = ('allowed');
  /// <summary>Optionen von Prüfregeln, die ein Text sein müssen (#926).</summary>
  StringRuleOptions: array[0..10] of string = ('template', 'replacement', 'wrapper', 'okMarker', 'searchPaths',
    'defaultEncoding', 'scope', 'local', 'field', 'parameter', 'constant');

type
  TValidator = class
  private
    FText: string;
    /// <summary>Zeilenindex von FText für die Positionen der Meldungen.</summary>
    FLines: TLineTable;
    FIssues: TList<TConfigurationIssue>;
    FSettings: TServerSettings;
    /// <summary>"testProfile" mit einem Namen, der erst nach "profiles" geprüft werden kann.</summary>
    FTestProfileNode: TJsonNode;
    function PositionAt(AOffset: Integer): TTextPosition;
    procedure Report(AStart, AStop: Integer; const AMessage: string; AIsError: Boolean);
    procedure ReportNode(ANode: TJsonNode; const AMessage: string);
    function ExpectString(ANode: TJsonNode; const AName: string; out AValue: string): Boolean;
    procedure ReadRules(ANode: TJsonNode);
    function ParseRules(ANode: TJsonNode; const AName: string; out ARules: TArray<TRuleSetting>): Boolean;
    function ParseStrings(ANode: TJsonNode; const AName: string; out AItems: TArray<string>): Boolean;
    procedure ReadProfile(ANode: TJsonNode);
    procedure ReadProfiles(ANode: TJsonNode);
    procedure ReadOverrides(ANode: TJsonNode);
    procedure ReadExclude(ANode: TJsonNode);
    procedure ReadMcp(ANode: TJsonNode);
    procedure ReadFix(ANode: TJsonNode);
    procedure ReadUsesKeep(ANode: TJsonNode);
    procedure ReadDeadCode(ANode: TJsonNode);
    procedure ReadSlashCommands(ANode: TJsonNode);
    procedure ReadCompleteBlocks(ANode: TJsonNode);
    procedure ReadExperimental(ANode: TJsonNode);
    procedure ReadSortUses(ANode: TJsonNode);
    procedure ReadInlayHints(ANode: TJsonNode);
    procedure ReadCodeLens(ANode: TJsonNode);
    procedure ReadReferences(ANode: TJsonNode);
    procedure ReadNavigation(ANode: TJsonNode);
    procedure CheckTodoKeywords(ANode: TJsonNode);
    procedure CheckForbiddenSymbols(ANode: TJsonNode);
    procedure ReadHints(ANode: TJsonNode);
    procedure ReadDirectives(ANode: TJsonNode);
    procedure ReadStringLiteral(ANode: TJsonNode);
    procedure ReadMemberOrder(ANode: TJsonNode);
    procedure ReadTestUnits(ANode: TJsonNode);
    procedure ReadTests(ANode: TJsonNode);
    procedure ReadDfmPropertyRules(ANode: TJsonNode);
    function ReadDfmPropertyRule(ANode: TJsonNode; out ARule: TDfmPropertyRule): Boolean;
    procedure ReadHighlight(ANode: TJsonNode);
    procedure ReadRefactoring(ANode: TJsonNode);
    procedure ReadCompiler(ANode: TJsonNode);
    procedure ReadVcs(ANode: TJsonNode);
    procedure ReadCompletion(ANode: TJsonNode);
    procedure ReadDiagnostics(ANode: TJsonNode);
    procedure ReadIndex(ANode: TJsonNode);
    procedure ReadArchitecture(ANode: TJsonNode);
    procedure ReadHotspots(ANode: TJsonNode);
    procedure ReadFormat(ANode: TJsonNode);
    procedure ReadTasks(ANode: TJsonNode);
    procedure ReadIssues(ANode: TJsonNode);
    procedure ReadIssueConnections(ANode: TJsonNode);
    procedure ReadIssueProjects(ANode: TJsonNode);
    procedure ReadIssueQueries(ANode: TJsonNode);
    procedure ReadMcpCustomPrompts(ANode: TJsonNode);
    function ReadMcpCustomPrompt(ANode: TJsonNode; out APrompt: TMcpCustomPrompt): Boolean;
    function ReadMcpPromptArgument(ANode: TJsonNode; out AArgument: TMcpCustomPromptArgument): Boolean;
    procedure ReadVcsProjects(ANode: TJsonNode);
    procedure ReadIssueEndStates(ANode: TJsonNode);
    procedure ReadTaskMatcher(ANode: TJsonNode);
    function ExpectBoolean(ANode: TJsonNode; const AName: string; var AValue: Boolean): Boolean;
    /// <summary>Wurzel oder nil nach gemeldetem Syntaxfehler.</summary>
    function ParseRoot: TJsonNode;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    procedure Run;
    property Settings: TServerSettings read FSettings;
    property Issues: TList<TConfigurationIssue> read FIssues;
  end;

{ TValidator }

constructor TValidator.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FLines := TLineTable.Build(AText);
  FIssues := TList<TConfigurationIssue>.Create;
  FSettings := TServerSettings.Default;
end;

destructor TValidator.Destroy;
begin
  FIssues.Free;
  inherited;
end;

function TValidator.PositionAt(AOffset: Integer): TTextPosition;
begin
  Result := FLines.PositionAt(AOffset);
end;

procedure TValidator.Report(AStart, AStop: Integer; const AMessage: string; AIsError: Boolean);
var
  Issue: TConfigurationIssue;
begin
  if AStop <= AStart then
    AStop := AStart + 1;
  if AStop > Length(FText) then
    AStop := Length(FText);
  if AStart > AStop then
    AStart := AStop;
  Issue.Range := TTextRange.Create(PositionAt(AStart), PositionAt(AStop));
  Issue.Message := AMessage;
  Issue.IsError := AIsError;
  FIssues.Add(Issue);
end;

procedure TValidator.ReportNode(ANode: TJsonNode; const AMessage: string);
begin
  Report(ANode.Start, ANode.Stop, AMessage, True);
end;

function TValidator.ExpectString(ANode: TJsonNode; const AName: string; out AValue: string): Boolean;
begin
  Result := ANode.Kind = TJsonKind.String_;
  if Result then
    AValue := ANode.Value
  else
  begin
    AValue := '';
    ReportNode(ANode, Format('"%s" muss ein String sein', [AName]));
  end;
end;

procedure TValidator.ReadRules(ANode: TJsonNode);
var
  Rules: TArray<TRuleSetting>;
begin
  if ParseRules(ANode, 'rules', Rules) then
    FSettings.Rules := Rules;
end;

/// <summary>Array aus Objekten, die alle Texte AKeys haben: "open" und "close" (pair-without-finally, #930),
/// "start", "commit" und "rollback" (transaction-without-rollback, #965).</summary>
function IsPairList(ANode: TJsonNode; const AKeys: array of string): Boolean;
var
  Index, Inner, Found: Integer;
  Item: TJsonNode;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if not Result then
    Exit;
  for Index := 0 to ANode.Count - 1 do
  begin
    Item := ANode[Index];
    if Item.Kind <> TJsonKind.Object_ then
      Exit(False);
    Found := 0;
    for Inner := 0 to Item.Count - 1 do
      if (IndexStr(Item.Keys[Inner], AKeys) >= 0) and (Item[Inner].Kind = TJsonKind.String_) then
        Inc(Found);
    if Found <> Length(AKeys) then
      Exit(False);
  end;
end;

/// <summary>Array aus Texten "Öffnen>Schließen" oder Objekten mit "open" und "close" (handle-leak, #1088).</summary>
function IsArrowPairList(ANode: TJsonNode): Boolean;
var
  Index, Inner, Arrow, Found: Integer;
  Item: TJsonNode;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if not Result then
    Exit;
  for Index := 0 to ANode.Count - 1 do
  begin
    Item := ANode[Index];
    if Item.Kind = TJsonKind.String_ then
    begin
      Arrow := Pos('>', Item.Value);
      if (Arrow <= 1) or (Arrow >= Length(Item.Value)) then
        Exit(False);
      Continue;
    end;
    if Item.Kind <> TJsonKind.Object_ then
      Exit(False);
    Found := 0;
    for Inner := 0 to Item.Count - 1 do
      if ((Item.Keys[Inner] = 'open') or (Item.Keys[Inner] = 'close')) and (Item[Inner].Kind = TJsonKind.String_) then
        Inc(Found);
    if Found <> 2 then
      Exit(False);
  end;
end;

/// <summary>Array, dessen Einträge alle Texte sind.</summary>
function IsNumberList(ANode: TJsonNode): Boolean;
var
  Index: Integer;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if Result then
    for Index := 0 to ANode.Count - 1 do
      if ANode[Index].Kind <> TJsonKind.Number then
        Exit(False);
end;

function IsStringList(ANode: TJsonNode): Boolean;
var
  Index: Integer;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if Result then
    for Index := 0 to ANode.Count - 1 do
      if ANode[Index].Kind <> TJsonKind.String_ then
        Exit(False);
end;

/// <summary>Liste von Texten, jeder aus AAllowed.</summary>
function IsStringListOf(ANode: TJsonNode; const AAllowed: array of string): Boolean;
var
  Index: Integer;
begin
  Result := IsStringList(ANode);
  if Result then
    for Index := 0 to ANode.Count - 1 do
      if IndexStr(ANode[Index].Value, AAllowed) < 0 then
        Exit(False);
end;

function TValidator.ParseRules(ANode: TJsonNode; const AName: string; out ARules: TArray<TRuleSetting>): Boolean;
var
  Index: Integer;
  Inner: Integer;
  Value: TJsonNode;
  Rule: TRuleSetting;
  Rules: TList<TRuleSetting>;
  Severity: TRuleSeverity;
  Limit: Integer;
begin
  ARules := nil;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, Format('"%s" muss ein Objekt sein: { "regel": "warning" }', [AName]));
    Exit(False);
  end;
  Rules := TList<TRuleSetting>.Create;
  try
    for Index := 0 to ANode.Count - 1 do
    begin
      Value := ANode[Index];
      // Frühere Kennungen gelten für die umbenannte Regel (#910).
      Rule.Id := TRuleIdAliases.Current(ANode.Keys[Index]);
      Rule.Severity := TRuleSeverity.Default;
      Rule.Options := '';
      if Value.Kind = TJsonKind.String_ then
      begin
        if not TConfigurationParser.TryParseSeverity(Value.Value, Severity) then
        begin
          ReportNode(Value, Format('Unbekannter Schweregrad "%s"; erlaubt: off, hint, info, warning, error', [Value.Value]));
          Continue;
        end;
        Rule.Severity := Severity;
      end
      else if Value.Kind = TJsonKind.Object_ then
      begin
        for Inner := 0 to Value.Count - 1 do
          if Value.Keys[Inner] = 'severity' then
          begin
            if (Value[Inner].Kind <> TJsonKind.String_) or
              not TConfigurationParser.TryParseSeverity(Value[Inner].Value, Severity) then
              ReportNode(Value[Inner], 'Unbekannter Schweregrad; erlaubt: off, hint, info, warning, error')
            else
              Rule.Severity := Severity;
          end
          // Grenzwert der Metrik-Regeln (#66); die Regel liest ihn aus den Optionen.
          else if (Value.Keys[Inner] = 'max') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
            ReportNode(Value[Inner], '"max" muss eine ganze Zahl ab 1 sein')
          // Mindestzahl der Zeilen von commented-out-code (#942).
          else if (Value.Keys[Inner] = 'minLines') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
            ReportNode(Value[Inner], '"minLines" muss eine ganze Zahl ab 1 sein')
          // Mindestzahl der Vergleiche von string-if-chain (#1066) bzw. der Zweige von prefer-case (#646).
          else if (Value.Keys[Inner] = 'min') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 2)) then
            ReportNode(Value[Inner], '"min" muss eine ganze Zahl ab 2 sein')
          // Kleinste gemeldete Record-Größe von managed-param-without-const (#975).
          else if (Value.Keys[Inner] = 'minRecordSize') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
            ReportNode(Value[Inner], '"minRecordSize" muss eine ganze Zahl ab 1 sein')
          // Kürzeste gemeldete Wartezeit von blocking-call-in-main-thread (#959).
          else if (Value.Keys[Inner] = 'maxSleepMs') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 0)) then
            ReportNode(Value[Inner], '"maxSleepMs" muss eine ganze Zahl ab 0 sein')
          // Höchstlänge des vertauschten Literals von pos-arguments-swapped (#1045).
          else if (Value.Keys[Inner] = 'maxLiteralLength') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
            ReportNode(Value[Inner], '"maxLiteralLength" muss eine ganze Zahl ab 1 sein')
          // Marken der Regel todo-comment (#68); die Regel und get_todos lesen sie aus den Optionen.
          else if Value.Keys[Inner] = 'keywords' then
            CheckTodoKeywords(Value[Inner])
          // Schalter der Regeln (#909), z. B. allowCommented von empty-statement.
          else if (IndexStr(Value.Keys[Inner], BooleanRuleOptions) >= 0) and (Value[Inner].Kind <> TJsonKind.Boolean_) then
            ReportNode(Value[Inner], Format('"%s" muss true oder false sein', [Value.Keys[Inner]]))
          else if (IndexStr(Value.Keys[Inner], StringListRuleOptions) >= 0) and not IsStringList(Value[Inner]) then
            ReportNode(Value[Inner], Format('"%s" muss eine Liste von Texten sein', [Value.Keys[Inner]]))
          // allowed von inherited-wrong-method (#1050) sind Paare "Methode>geerbte Methode", sonst Zahlen.
          else if (Value.Keys[Inner] = 'allowed') and (Rule.Id = 'inherited-wrong-method') then
          begin
            if not IsStringList(Value[Inner]) then
              ReportNode(Value[Inner], '"allowed" muss eine Liste von Texten sein');
          end
          else if (IndexStr(Value.Keys[Inner], NumberListRuleOptions) >= 0) and not IsNumberList(Value[Inner]) then
            ReportNode(Value[Inner], Format('"%s" muss eine Liste von Zahlen sein', [Value.Keys[Inner]]))
          else if (IndexStr(Value.Keys[Inner], StringRuleOptions) >= 0) and (Value[Inner].Kind <> TJsonKind.String_) then
            ReportNode(Value[Inner], Format('"%s" muss ein Text sein', [Value.Keys[Inner]]))
          // Stufe T der Gruppe „Compiler vorab“ (#1024).
          else if (Value.Keys[Inner] = 'typeLevel') and
            ((Value[Inner].Kind <> TJsonKind.String_) or (IndexStr(Value[Inner].Value, ['certain', 'off']) < 0)) then
            ReportNode(Value[Inner], '"typeLevel" muss "certain" oder "off" sein')
          // Arten von deprecated-symbol (#1018).
          else if (Value.Keys[Inner] = 'kinds') and (Rule.Id = 'deprecated-symbol') and
            not IsStringListOf(Value[Inner], DeprecationKinds) then
            ReportNode(Value[Inner], '"kinds" darf nur "deprecated", "experimental", "platform" und "library" enthalten')
          // Verbotene Symbole von forbidden-symbol (#1133).
          else if (Value.Keys[Inner] = 'symbols') and (Rule.Id = 'forbidden-symbol') then
            CheckForbiddenSymbols(Value[Inner])
          // Suchquelle von uses-unit-not-found (#1016).
          else if (Value.Keys[Inner] = 'searchPaths') and
            (IndexStr(Value[Inner].Value, ['project', 'atlas', 'both']) < 0) then
            ReportNode(Value[Inner], '"searchPaths" muss "project", "atlas" oder "both" sein')
          // Kodierung der Korrektur von load-without-encoding (#1061).
          else if (Value.Keys[Inner] = 'defaultEncoding') and
            (IndexText(Value[Inner].Value, ['UTF8', 'Unicode', 'BigEndianUnicode', 'ANSI', 'ASCII', 'UTF7',
            'Default']) < 0) then
            ReportNode(Value[Inner],
              '"defaultEncoding" muss UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 oder Default sein')
          // Transaktionspaare von transaction-without-rollback (#965).
          else if (Value.Keys[Inner] = 'pairs') and (Rule.Id = 'transaction-without-rollback') then
          begin
            if not IsPairList(Value[Inner], ['start', 'commit', 'rollback']) then
              ReportNode(Value[Inner], '"pairs" muss eine Liste von Objekten mit "start", "commit" und "rollback" sein');
          end
          // Paare von handle-leak (#1088): auch als Text "Öffnen>Schließen".
          else if (Value.Keys[Inner] = 'pairs') and (Rule.Id = 'handle-leak') then
          begin
            if not IsArrowPairList(Value[Inner]) then
              ReportNode(Value[Inner], '"pairs" muss eine Liste von Texten "Öffnen>Schließen" oder von Objekten mit ' +
                '"open" und "close" sein');
          end
          else if (Value.Keys[Inner] = 'pairs') and not IsPairList(Value[Inner], ['open', 'close']) then
            ReportNode(Value[Inner], '"pairs" muss eine Liste von Objekten mit "open" und "close" sein')
          // Paare von ota-notifier-not-removed (#944).
          else if (Value.Keys[Inner] = 'registerPairs') and not IsPairList(Value[Inner], ['open', 'close']) then
            ReportNode(Value[Inner], '"registerPairs" muss eine Liste von Objekten mit "open" und "close" sein');
        Rule.Options := Copy(FText, Value.Start + 1, Value.Stop - Value.Start);
      end
      else
      begin
        ReportNode(Value, 'Regel erwartet einen Schweregrad oder ein Objekt mit "severity"');
        Continue;
      end;
      Rules.Add(Rule);
    end;
    ARules := Rules.ToArray;
    Result := True;
  finally
    Rules.Free;
  end;
end;

function TValidator.ParseStrings(ANode: TJsonNode; const AName: string; out AItems: TArray<string>): Boolean;
var
  Index: Integer;
  Value: string;
begin
  AItems := nil;
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, Format('"%s" muss eine Liste von Texten sein', [AName]));
    Exit(False);
  end;
  for Index := 0 to ANode.Count - 1 do
    if ExpectString(ANode[Index], AName, Value) then
      AItems := AItems + [Value];
  Result := True;
end;

procedure TValidator.ReadProfile(ANode: TJsonNode);
var
  Index: Integer;
  Text: string;
begin
  // "profile": "fast" oder { "editor": "fast", "cli": "strict" }
  if ANode.Kind = TJsonKind.String_ then
  begin
    FSettings.Profile := ANode.Value;
    Exit;
  end;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"profile" erwartet einen Namen oder { "editor": …, "cli": … }');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
    if ANode.Keys[Index] = 'editor' then
    begin
      if ExpectString(ANode[Index], 'profile.editor', Text) then
        FSettings.Profile := Text;
    end
    else if ANode.Keys[Index] = 'cli' then
    begin
      if ExpectString(ANode[Index], 'profile.cli', Text) then
        FSettings.CliProfile := Text;
    end
    else
      ReportNode(ANode[Index], Format('Unbekannter Schlüssel "%s"; erlaubt: editor, cli', [ANode.Keys[Index]]));
end;

procedure TValidator.ReadProfiles(ANode: TJsonNode);
var
  Index: Integer;
  Inner: Integer;
  Value: TJsonNode;
  Profile: TRuleProfile;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"profiles" muss ein Objekt sein: { "name": { "extends": …, "rules": … } }');
    Exit;
  end;
  FSettings.Profiles := nil;
  for Index := 0 to ANode.Count - 1 do
  begin
    Value := ANode[Index];
    if Value.Kind <> TJsonKind.Object_ then
    begin
      ReportNode(Value, 'Ein Profil ist ein Objekt mit "extends", "categories" und "rules"');
      Continue;
    end;
    Profile := Default(TRuleProfile);
    Profile.Name := ANode.Keys[Index];
    for Inner := 0 to Value.Count - 1 do
    begin
      Key := Value.Keys[Inner];
      if Key = 'extends' then
        ExpectString(Value[Inner], 'extends', Profile.Extends)
      else if Key = 'categories' then
        ParseStrings(Value[Inner], 'categories', Profile.Categories)
      else if Key = 'rules' then
        ParseRules(Value[Inner], 'rules', Profile.Rules)
      else
        ReportNode(Value[Inner], Format('Unbekannter Schlüssel "%s"; erlaubt: extends, categories, rules', [Key]));
    end;
    FSettings.Profiles := FSettings.Profiles + [Profile];
  end;
end;

procedure TValidator.ReadOverrides(ANode: TJsonNode);
var
  Index: Integer;
  Inner: Integer;
  Value: TJsonNode;
  Item: TPathOverride;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"overrides" muss eine Liste sein: [{ "files": ["Tests/**"], "rules": { … } }]');
    Exit;
  end;
  FSettings.Overrides := nil;
  for Index := 0 to ANode.Count - 1 do
  begin
    Value := ANode[Index];
    if Value.Kind <> TJsonKind.Object_ then
    begin
      ReportNode(Value, 'Eine Pfadregel ist ein Objekt mit "files" und "rules"');
      Continue;
    end;
    Item := Default(TPathOverride);
    for Inner := 0 to Value.Count - 1 do
    begin
      Key := Value.Keys[Inner];
      if Key = 'files' then
        ParseStrings(Value[Inner], 'files', Item.Files)
      else if Key = 'rules' then
        ParseRules(Value[Inner], 'rules', Item.Rules)
      else
        ReportNode(Value[Inner], Format('Unbekannter Schlüssel "%s"; erlaubt: files, rules', [Key]));
    end;
    if Item.Files = nil then
      ReportNode(Value, 'Pfadregel ohne "files"')
    else
      FSettings.Overrides := FSettings.Overrides + [Item];
  end;
end;

procedure TValidator.ReadUsesKeep(ANode: TJsonNode);
var
  Index: Integer;
  Value: string;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"usesKeep" muss eine Liste von Unit-Namen sein');
    Exit;
  end;
  FSettings.UsesKeep := nil;
  for Index := 0 to ANode.Count - 1 do
    if ExpectString(ANode[Index], 'usesKeep', Value) then
      FSettings.UsesKeep := FSettings.UsesKeep + [Value];
end;

procedure TValidator.ReadDeadCode(ANode: TJsonNode);
var
  Index, Item: Integer;
  Key, Value: string;
  Values: TArray<string>;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"deadCode" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if (Key = 'keepAttributes') or (Key = 'keepPatterns') then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[Index], Format('"deadCode.%s" muss eine Liste von Texten sein', [Key]));
        Continue;
      end;
      Values := nil;
      for Item := 0 to ANode[Index].Count - 1 do
        if ExpectString(ANode[Index][Item], 'deadCode.' + Key, Value) then
          Values := Values + [Value];
      if Key = 'keepAttributes' then
        FSettings.DeadCodeKeepAttributes := Values
      else
        FSettings.DeadCodeKeepPatterns := Values;
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "deadCode.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadSlashCommands(ANode: TJsonNode);
var
  Index, Item: Integer;
  Key, Value: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"slashCommands" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'enabled' then
      ExpectBoolean(ANode[Index], Key, FSettings.SlashCommands)
    else if Key = 'disabled' then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[Index], '"slashCommands.disabled" muss eine Liste von Befehlsnamen sein');
        Continue;
      end;
      FSettings.SlashCommandsDisabled := nil;
      for Item := 0 to ANode[Index].Count - 1 do
        if ExpectString(ANode[Index][Item], 'disabled', Value) then
          FSettings.SlashCommandsDisabled := FSettings.SlashCommandsDisabled + [Value];
    end
    else if Key = 'headerTemplate' then
      ExpectString(ANode[Index], 'headerTemplate', FSettings.SlashHeaderTemplate)
    else if Key = 'logCall' then
      ExpectString(ANode[Index], 'logCall', FSettings.SlashLogCall)
    else if Key = 'componentPalette' then
      ExpectString(ANode[Index], 'componentPalette', FSettings.SlashComponentPalette)
    else if Key = 'todoOwner' then
      ExpectString(ANode[Index], 'todoOwner', FSettings.SlashTodoOwner)
    else if Key = 'todoCategory' then
      ExpectString(ANode[Index], 'todoCategory', FSettings.SlashTodoCategory)
    else if Key = 'sortUsesRemoveUnused' then
      ExpectBoolean(ANode[Index], Key, FSettings.SlashSortUsesRemoveUnused)
    else if Key = 'enumHelper' then
      ExpectBoolean(ANode[Index], Key, FSettings.SlashEnumHelper)
    else if Key = 'setHelper' then
      ExpectBoolean(ANode[Index], Key, FSettings.SlashSetHelper)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "slashCommands.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadCompleteBlocks(ANode: TJsonNode);
var
  Index: Integer;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"completeBlocks" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'docComment' then
      ExpectBoolean(ANode[Index], Key, FSettings.CompleteBlocksDocComment)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "completeBlocks.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadExperimental(ANode: TJsonNode);
var
  Index: Integer;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"experimental" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'enabled' then
      ExpectBoolean(ANode[Index], Key, FSettings.ExperimentalEnabled)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "experimental.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadSortUses(ANode: TJsonNode);
begin
  // true/false wie bisher, "namespace" sortiert gruppiert nach Namespace (#284).
  if ANode.Kind = TJsonKind.Boolean_ then
  begin
    FSettings.SortUses := SameText(ANode.Value, 'true');
    FSettings.SortUsesByNamespace := False;
  end
  else if (ANode.Kind = TJsonKind.String_) and (SameText(ANode.Value, 'alphabetic') or
    SameText(ANode.Value, 'namespace')) then
  begin
    FSettings.SortUses := True;
    FSettings.SortUsesByNamespace := SameText(ANode.Value, 'namespace');
  end
  else
    ReportNode(ANode, 'Erlaubt sind true, false, "alphabetic" und "namespace"');
end;

procedure TValidator.ReadExclude(ANode: TJsonNode);
var
  Index: Integer;
  Items: TList<string>;
  Value: string;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"exclude" muss eine Liste von Mustern sein');
    Exit;
  end;
  Items := TList<string>.Create;
  try
    for Index := 0 to ANode.Count - 1 do
      if ExpectString(ANode[Index], 'exclude', Value) then
        Items.Add(Value);
    FSettings.Exclude := Items.ToArray;
  finally
    Items.Free;
  end;
end;

procedure TValidator.ReadMcp(ANode: TJsonNode);
var
  Index, Item: Integer;
  Items: TList<string>;
  Value: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"mcp" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
    if ANode.Keys[Index] = 'disabledTools' then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[Index], '"disabledTools" muss eine Liste von Werkzeugnamen sein');
        Continue;
      end;
      Items := TList<string>.Create;
      try
        for Item := 0 to ANode[Index].Count - 1 do
          if ExpectString(ANode[Index][Item], 'disabledTools', Value) then
            Items.Add(Value);
        FSettings.McpDisabledTools := Items.ToArray;
      finally
        Items.Free;
      end;
    end
    else if ANode.Keys[Index] = 'globalSettings' then
      ExpectBoolean(ANode[Index], 'globalSettings', FSettings.McpGlobalSettings)
    else if ANode.Keys[Index] = 'prompts' then
      ExpectBoolean(ANode[Index], 'prompts', FSettings.McpPrompts)
    else if ANode.Keys[Index] = 'promptLanguage' then
    begin
      if ExpectString(ANode[Index], 'promptLanguage', Value) then
      begin
        if (Value = 'de') or (Value = 'en') then
          FSettings.McpPromptLanguage := Value
        else
          ReportNode(ANode[Index], '"mcp.promptLanguage" ist "de" oder "en"');
      end;
    end
    else if ANode.Keys[Index] = 'customPrompts' then
      ReadMcpCustomPrompts(ANode[Index])
    else
      ReportNode(ANode[Index], Format('Unbekannte Einstellung "mcp.%s"', [ANode.Keys[Index]]));
end;

procedure TValidator.ReadFix(ANode: TJsonNode);
var
  mIndex: Integer;
  mText: string;
  mConfidence: TRuleConfidence;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"fix" muss ein Objekt sein');
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
    if ANode.Keys[mIndex] = 'minConfidence' then
    begin
      // Sammelkorrekturen (#1352) nie unter mittlerer Konfidenz.
      if ExpectString(ANode[mIndex], 'fix.minConfidence', mText) then
        if TConfigurationParser.TryParseConfidence(mText, mConfidence) and (mConfidence <> TRuleConfidence.Low) then
          FSettings.FixMinConfidence := mConfidence
        else
          ReportNode(ANode[mIndex], 'Erlaubt sind "medium" und "high"');
    end
    else
      ReportNode(ANode[mIndex], Format('Unbekannte Einstellung "fix.%s"', [ANode.Keys[mIndex]]));
end;

/// <summary>Name eines Prompts oder Arguments: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-".</summary>
function IsPromptName(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AName <> '') and CharInSet(AName[1], ['A'..'Z', 'a'..'z']);
  for mIndex := 2 to Length(AName) do
    if not CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
      Exit(False);
end;

procedure TValidator.ReadMcpCustomPrompts(ANode: TJsonNode);
var
  mIndex: Integer;
  mPrompt: TMcpCustomPrompt;
  mNames: TList<string>;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"mcp.customPrompts" muss eine Liste von Prompts sein');
    Exit;
  end;
  FSettings.McpCustomPrompts := nil;
  mNames := TList<string>.Create;
  try
    for mIndex := 0 to ANode.Count - 1 do
      if ReadMcpCustomPrompt(ANode[mIndex], mPrompt) then
      begin
        if mNames.IndexOf(LowerCase(mPrompt.Name)) >= 0 then
          ReportNode(ANode[mIndex], Format('Den Prompt "%s" gibt es schon', [mPrompt.Name]))
        else
        begin
          mNames.Add(LowerCase(mPrompt.Name));
          FSettings.McpCustomPrompts := FSettings.McpCustomPrompts + [mPrompt];
        end;
      end;
  finally
    mNames.Free;
  end;
end;

function TValidator.ReadMcpPromptArgument(ANode: TJsonNode; out AArgument: TMcpCustomPromptArgument): Boolean;
var
  mIndex: Integer;
  mKey: string;
begin
  AArgument := Default(TMcpCustomPromptArgument);
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, 'Ein Argument ist ein Objekt mit "name", "description" und "required"');
    Exit(False);
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    if mKey = 'name' then
    begin
      if ExpectString(ANode[mIndex], mKey, AArgument.Name) and not IsPromptName(AArgument.Name) then
        ReportNode(ANode[mIndex], 'Name eines Arguments: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-"');
    end
    else if mKey = 'description' then
      ExpectString(ANode[mIndex], mKey, AArgument.Description)
    else if mKey = 'required' then
      ExpectBoolean(ANode[mIndex], mKey, AArgument.Required)
    else
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Angabe "%s" in einem Argument', [mKey]), False);
  end;
  Result := IsPromptName(AArgument.Name);
  if AArgument.Name = '' then
    ReportNode(ANode, 'Argument ohne "name"');
end;

function TValidator.ReadMcpCustomPrompt(ANode: TJsonNode; out APrompt: TMcpCustomPrompt): Boolean;
var
  mIndex, mItem, mStart, mStop: Integer;
  mKey, mValue, mPlaceholder: string;
  mArgument: TMcpCustomPromptArgument;
  mTextNode: TJsonNode;
  mKnown: Boolean;
begin
  APrompt := Default(TMcpCustomPrompt);
  mTextNode := nil;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, 'Ein Prompt ist ein Objekt mit "name", "description", "arguments", "text" und "include"');
    Exit(False);
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    if mKey = 'name' then
    begin
      if ExpectString(ANode[mIndex], mKey, APrompt.Name) and not IsPromptName(APrompt.Name) then
        ReportNode(ANode[mIndex], 'Name eines Prompts: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-"');
    end
    else if mKey = 'description' then
      ExpectString(ANode[mIndex], mKey, APrompt.Description)
    else if mKey = 'text' then
    begin
      if ExpectString(ANode[mIndex], mKey, APrompt.Text) then
        mTextNode := ANode[mIndex];
    end
    else if mKey = 'arguments' then
    begin
      if ANode[mIndex].Kind <> TJsonKind.Array_ then
        ReportNode(ANode[mIndex], '"arguments" muss eine Liste von Argumenten sein')
      else
        for mItem := 0 to ANode[mIndex].Count - 1 do
          if ReadMcpPromptArgument(ANode[mIndex][mItem], mArgument) then
            APrompt.Arguments := APrompt.Arguments + [mArgument];
    end
    else if mKey = 'include' then
    begin
      if ANode[mIndex].Kind <> TJsonKind.Array_ then
        ReportNode(ANode[mIndex], '"include" muss eine Liste sein, z. B. ["diagnostics", "metrics"]')
      else
        for mItem := 0 to ANode[mIndex].Count - 1 do
          if ExpectString(ANode[mIndex][mItem], 'include', mValue) then
          begin
            if TMcpCustomPrompt.IsKnownInclude(mValue) then
              APrompt.Include := APrompt.Include + [mValue]
            else
              ReportNode(ANode[mIndex][mItem], Format('Unbekannter Inhalt "%s"; erlaubt: %s',
                [mValue, string.Join(', ', TMcpCustomPrompt.KnownIncludes)]));
          end;
    end
    else
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Angabe "%s" in einem Prompt', [mKey]), False);
  end;
  if APrompt.Name = '' then
    ReportNode(ANode, 'Prompt ohne "name"');
  if Trim(APrompt.Text) = '' then
    ReportNode(ANode, 'Prompt ohne "text"');
  // Platzhalter ohne passendes Argument bleiben stehen; ein Hinweis, damit der Tippfehler auffällt.
  if mTextNode <> nil then
  begin
    mStart := Pos('{', APrompt.Text);
    while mStart > 0 do
    begin
      mStop := Pos('}', APrompt.Text, mStart + 1);
      if mStop = 0 then
        Break;
      mPlaceholder := Copy(APrompt.Text, mStart + 1, mStop - mStart - 1);
      if IsPromptName(mPlaceholder) then
      begin
        mKnown := False;
        for mArgument in APrompt.Arguments do
          if mArgument.Name = mPlaceholder then
            mKnown := True;
        if not mKnown then
          Report(mTextNode.Start, mTextNode.Stop, Format('Platzhalter "{%s}" hat kein Argument', [mPlaceholder]),
            False);
      end;
      mStart := Pos('{', APrompt.Text, mStop + 1);
    end;
  end;
  Result := IsPromptName(APrompt.Name) and (Trim(APrompt.Text) <> '');
end;

function TValidator.ExpectBoolean(ANode: TJsonNode; const AName: string; var AValue: Boolean): Boolean;
begin
  Result := ANode.Kind = TJsonKind.Boolean_;
  if Result then
    AValue := ANode.Value = 'true'
  else
    ReportNode(ANode, Format('"%s" muss true oder false sein', [AName]));
end;

procedure TValidator.ReadInlayHints(ANode: TJsonNode);
var
  Index, Lines: Integer;
  Key: string;
  Value: TJsonNode;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"inlayHints" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if Key = 'parameterNames' then
      ExpectBoolean(Value, Key, FSettings.InlayHints.ParameterNames)
    else if Key = 'inferredTypes' then
      ExpectBoolean(Value, Key, FSettings.InlayHints.InferredTypes)
    else if Key = 'endMarkers' then
      ExpectBoolean(Value, Key, FSettings.InlayHints.EndMarkers)
    else if Key = 'includeDefines' then
      ExpectBoolean(Value, Key, FSettings.InlayHints.IncludeDefines)
    else if Key = 'controlChars' then
      ExpectBoolean(Value, Key, FSettings.InlayHints.ControlChars)
    else if Key = 'endMarkerMinLines' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Lines) and (Lines >= 1) then
        FSettings.InlayHints.EndMarkerMinLines := Lines
      else
        ReportNode(Value, '"endMarkerMinLines" muss eine ganze Zahl ab 1 sein');
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "inlayHints.%s"', [Key]), False);
  end;
end;

procedure TValidator.CheckTodoKeywords(ANode: TJsonNode);
var
  Index, Position: Integer;
  Keyword: string;
  Valid: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"keywords" muss eine Liste von Marken sein, z. B. ["TODO", "FIXME"]');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Keyword := '';
    if ANode[Index].Kind = TJsonKind.String_ then
      Keyword := Trim(ANode[Index].Value);
    Valid := (Keyword <> '') and not SameText(Keyword, 'DONE');
    for Position := 1 to Length(Keyword) do
      if not CharInSet(Keyword[Position], ['A'..'Z', 'a'..'z']) then
        Valid := False;
    if not Valid then
      ReportNode(ANode[Index], 'Eine Marke besteht nur aus Buchstaben und ist nicht DONE, z. B. "HACK"');
  end;
end;

procedure TValidator.CheckForbiddenSymbols(ANode: TJsonNode);
var
  mIndex, mInner: Integer;
  mItem, mValue: TJsonNode;
  mKey: string;
  mSeverity: TRuleSeverity;
  mHasName: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"symbols" muss eine Liste von Objekten mit "name" sein');
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mItem := ANode[mIndex];
    if mItem.Kind <> TJsonKind.Object_ then
    begin
      ReportNode(mItem, 'Ein Eintrag von "symbols" ist ein Objekt mit "name", z. B. {"name": "System.Writeln"}');
      Continue;
    end;
    mHasName := False;
    for mInner := 0 to mItem.Count - 1 do
    begin
      mKey := mItem.Keys[mInner];
      mValue := mItem[mInner];
      if mKey = 'name' then
      begin
        mHasName := True;
        if (mValue.Kind <> TJsonKind.String_) or (Trim(mValue.Value) = '') then
          ReportNode(mValue, '"name" muss ein nicht leerer Text sein');
      end
      else if mKey = 'kind' then
      begin
        if (mValue.Kind <> TJsonKind.String_) or (IndexText(mValue.Value, ForbiddenSymbolKinds) < 0) then
          ReportNode(mValue, '"kind" muss routine, type, constant, field, property, enumValue oder identifier sein');
      end
      else if (mKey = 'message') or (mKey = 'replacement') then
      begin
        if mValue.Kind <> TJsonKind.String_ then
          ReportNode(mValue, Format('"%s" muss ein Text sein', [mKey]));
      end
      else if mKey = 'severity' then
      begin
        if (mValue.Kind <> TJsonKind.String_) or not TConfigurationParser.TryParseSeverity(mValue.Value, mSeverity) then
          ReportNode(mValue, 'Unbekannter Schweregrad; erlaubt: off, hint, info, warning, error');
      end
      else if (mKey = 'units') or (mKey = 'firstArgument') or (mKey = 'allowFirstArgument') then
      begin
        if not IsStringList(mValue) then
          ReportNode(mValue, Format('"%s" muss eine Liste von Texten sein', [mKey]));
      end
      else
        ReportNode(mValue, Format('Unbekannter Schlüssel "%s"; erlaubt: name, kind, message, replacement, ' +
          'severity, units, firstArgument, allowFirstArgument', [mKey]));
    end;
    if not mHasName then
      ReportNode(mItem, 'Eintrag von "symbols" ohne "name"');
  end;
end;

procedure TValidator.ReadCodeLens(ANode: TJsonNode);
var
  Index: Integer;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"codeLens" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'metrics' then
      ExpectBoolean(ANode[Index], Key, FSettings.CodeLens.Metrics)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "codeLens.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadReferences(ANode: TJsonNode);
var
  Index: Integer;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"references" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'inferred' then
      ExpectBoolean(ANode[Index], Key, FSettings.References.Inferred)
    else if Key = 'textMatches' then
      ExpectBoolean(ANode[Index], Key, FSettings.References.TextMatches)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "references.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadNavigation(ANode: TJsonNode);
var
  Index, Depth: Integer;
  Key: string;
  Value: TJsonNode;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"navigation" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if Key = 'symbolPath' then
      ExpectBoolean(Value, Key, FSettings.Navigation.SymbolPath)
    else if Key = 'impact' then
      ExpectBoolean(Value, Key, FSettings.Navigation.Impact)
    else if Key = 'impactDepth' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Depth) and (Depth >= 1) and (Depth <= 5) then
        FSettings.Navigation.ImpactDepth := Depth
      else
        ReportNode(Value, '"impactDepth" muss eine ganze Zahl von 1 bis 5 sein');
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "navigation.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadDirectives(ANode: TJsonNode);
var
  Index: Integer;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"directives" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'completion' then
      ExpectBoolean(ANode[Index], Key, FSettings.Directives.Completion)
    else if Key = 'hover' then
      ExpectBoolean(ANode[Index], Key, FSettings.Directives.Hover)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "directives.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadHints(ANode: TJsonNode);
var
  Index, Lines, Item: Integer;
  Key, Text: string;
  Value: TJsonNode;
  Full, ExpandSet: Boolean;
begin
  ExpandSet := False;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"hints" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if Key = 'xmlDocExpand' then
    begin
      if ExpectString(Value, Key, Text) then
        if (Text = THintSettings.ExpandCollapsed) or (Text = THintSettings.ExpandLast) or
          (Text = THintSettings.ExpandExpanded) then
        begin
          FSettings.Hints.XmlDocExpand := Text;
          ExpandSet := True;
        end
        else
          ReportNode(Value, '"xmlDocExpand" muss "collapsed", "last" oder "expanded" sein');
    end
    else if Key = 'xmlDocFull' then
    begin
      // Veraltet seit #770: true = expanded, false = collapsed, solange xmlDocExpand fehlt.
      Full := True;
      if ExpectBoolean(Value, Key, Full) then
      begin
        Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
          '"hints.xmlDocFull" ist veraltet, stattdessen "hints.xmlDocExpand" verwenden', False);
        if not ExpandSet then
          if Full then
            FSettings.Hints.XmlDocExpand := THintSettings.ExpandExpanded
          else
            FSettings.Hints.XmlDocExpand := THintSettings.ExpandCollapsed;
      end;
    end
    else if Key = 'xmlDocMaxLines' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Lines) and (Lines >= 0) and
        (Lines <= THintSettings.MaxXmlDocLines) then
        FSettings.Hints.XmlDocMaxLines := Lines
      else
        ReportNode(Value, Format('"xmlDocMaxLines" muss eine ganze Zahl von 0 bis %d sein',
          [THintSettings.MaxXmlDocLines]));
    end
    else if Key = 'publishedMembers' then
      ExpectBoolean(Value, Key, FSettings.Hints.PublishedMembers)
    else if Key = 'rationale' then
      ExpectBoolean(Value, Key, FSettings.Hints.Rationale)
    else if Key = 'rationaleMarkers' then
    begin
      // Begründungen (#1123): eigene Marken ersetzen die Vorgabe.
      if Value.Kind <> TJsonKind.Array_ then
      begin
        ReportNode(Value, '"rationaleMarkers" muss eine Liste von Marken sein');
        Continue;
      end;
      FSettings.Hints.RationaleMarkers := nil;
      for Item := 0 to Value.Count - 1 do
        if ExpectString(Value[Item], 'rationaleMarkers', Text) then
          if Trim(Text) = '' then
            ReportNode(Value[Item], '"rationaleMarkers" darf keine leere Marke enthalten')
          else
            FSettings.Hints.RationaleMarkers := FSettings.Hints.RationaleMarkers + [Trim(Text)];
    end
    else if Key = 'adrFolder' then
    begin
      if ExpectString(Value, Key, Text) then
        FSettings.Hints.AdrFolder := Trim(Text);
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "hints.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadStringLiteral(ANode: TJsonNode);
const
  Styles: array[TStringLiteralStyle] of string = ('auto', 'multiline', 'concat');
  Breaks: array[TStringLiteralBreak] of string = ('sLineBreak', '#13#10', '#10', 'space', 'none');
var
  Index, Length_: Integer;
  Key, Text: string;
  Value: TJsonNode;
  Style: TStringLiteralStyle;
  Break_: TStringLiteralBreak;
  Found: Boolean;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"stringLiteral" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if Key = 'style' then
    begin
      if ExpectString(Value, Key, Text) then
      begin
        Found := False;
        for Style := Low(TStringLiteralStyle) to High(TStringLiteralStyle) do
          if Text = Styles[Style] then
          begin
            FSettings.StringLiteral.Style := Style;
            Found := True;
          end;
        if not Found then
          ReportNode(Value, 'Erlaubt sind "auto", "multiline" und "concat"');
      end;
    end
    else if Key = 'lineBreak' then
    begin
      if ExpectString(Value, Key, Text) then
      begin
        Found := False;
        for Break_ := Low(TStringLiteralBreak) to High(TStringLiteralBreak) do
          if Text = Breaks[Break_] then
          begin
            FSettings.StringLiteral.LineBreak := Break_;
            Found := True;
          end;
        if not Found then
          ReportNode(Value, 'Erlaubt sind "sLineBreak", "#13#10", "#10", "space" und "none"');
      end;
    end
    else if Key = 'maxLineLength' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Length_) and (Length_ >= 0) then
        FSettings.StringLiteral.MaxLineLength := Length_
      else
        ReportNode(Value, '"maxLineLength" muss eine ganze Zahl ab 0 sein');
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "stringLiteral.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadDfmPropertyRules(ANode: TJsonNode);
var
  Index: Integer;
  Rule: TDfmPropertyRule;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"dfmPropertyRules" muss eine Liste von Regeln sein');
    Exit;
  end;
  FSettings.DfmPropertyRules := nil;
  for Index := 0 to ANode.Count - 1 do
    if ReadDfmPropertyRule(ANode[Index], Rule) then
      FSettings.DfmPropertyRules := FSettings.DfmPropertyRules + [Rule];
end;

function TValidator.ReadDfmPropertyRule(ANode: TJsonNode; out ARule: TDfmPropertyRule): Boolean;
var
  Index, Item: Integer;
  Key, Text: string;
  Value: TJsonNode;
begin
  ARule := Default(TDfmPropertyRule);
  ARule.Severity := TRuleSeverity.Warning;
  ARule.IncludeDescendants := True;
  ARule.Fix := TDfmFixMode.Prompt;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, 'Eine Eigenschaftsregel muss ein Objekt sein: { "class": …, "property": …, "condition": … }');
    Exit(False);
  end;
  ARule.ClassRange := TTextRange.Create(PositionAt(ANode.Start), PositionAt(ANode.Start + 1));
  ARule.PropertyRange := ARule.ClassRange;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if Key = 'class' then
    begin
      ExpectString(Value, Key, ARule.ClassName);
      ARule.ClassRange := TTextRange.Create(PositionAt(Value.Start), PositionAt(Value.Stop));
    end
    else if Key = 'property' then
    begin
      ExpectString(Value, Key, ARule.PropertyPath);
      ARule.PropertyRange := TTextRange.Create(PositionAt(Value.Start), PositionAt(Value.Stop));
    end
    else if Key = 'value' then
      ExpectString(Value, Key, ARule.Value)
    else if Key = 'message' then
      ExpectString(Value, Key, ARule.Message)
    else if Key = 'condition' then
    begin
      if not ExpectString(Value, Key, Text) then
        Continue;
      case IndexStr(Text, ['=', '<>', 'contains', 'notContains', 'empty', 'notEmpty']) of
        0: ARule.Condition := TDfmCondition.Equal;
        1: ARule.Condition := TDfmCondition.NotEqual;
        2: ARule.Condition := TDfmCondition.Contains;
        3: ARule.Condition := TDfmCondition.NotContains;
        4: ARule.Condition := TDfmCondition.Empty;
        5: ARule.Condition := TDfmCondition.NotEmpty;
      else
        ReportNode(Value, 'Erlaubt sind "=", "<>", "contains", "notContains", "empty" und "notEmpty"');
      end;
    end
    else if Key = 'severity' then
    begin
      if ExpectString(Value, Key, Text) and not TConfigurationParser.TryParseSeverity(Text, ARule.Severity) then
        ReportNode(Value, Format('Unbekannter Schweregrad "%s"; erlaubt: off, hint, info, warning, error', [Text]));
    end
    else if Key = 'includeDescendants' then
      ExpectBoolean(Value, Key, ARule.IncludeDescendants)
    else if Key = 'fix' then
    begin
      if not ExpectString(Value, Key, Text) then
        Continue;
      case IndexStr(Text, ['prompt', 'auto', 'none']) of
        0: ARule.Fix := TDfmFixMode.Prompt;
        1: ARule.Fix := TDfmFixMode.Auto;
        2: ARule.Fix := TDfmFixMode.None;
      else
        ReportNode(Value, 'Erlaubt sind "auto", "prompt" und "none"');
      end;
    end
    else if Key = 'exclude' then
    begin
      if Value.Kind <> TJsonKind.Array_ then
      begin
        ReportNode(Value, '"exclude" muss eine Liste von Glob-Mustern sein');
        Continue;
      end;
      for Item := 0 to Value.Count - 1 do
        if ExpectString(Value[Item], 'exclude', Text) then
          ARule.Exclude := ARule.Exclude + [Text];
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Angabe "%s" in einer Eigenschaftsregel', [Key]), False);
  end;
  Result := (ARule.ClassName <> '') and (ARule.PropertyPath <> '');
  if not Result then
    ReportNode(ANode, 'Eine Eigenschaftsregel braucht "class" und "property"')
  else if (ARule.Condition in [TDfmCondition.Equal, TDfmCondition.NotEqual, TDfmCondition.Contains,
    TDfmCondition.NotContains]) and (ARule.Value = '') then
  begin
    ReportNode(ANode, 'Diese Bedingung braucht einen "value"');
    Result := False;
  end;
end;

procedure TValidator.ReadMemberOrder(ANode: TJsonNode);
const
  SectionNames: array[0..5] of string = ('strict private', 'private', 'strict protected', 'protected', 'public',
    'published');
  MemberNames: array[0..4] of string = ('field', 'constructor', 'destructor', 'method', 'property');
var
  Index, Item: Integer;
  Key, Text: string;
  Value: TJsonNode;
  Names: TArray<string>;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"memberOrder" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if (Key = 'sections') or (Key = 'members') then
    begin
      if Value.Kind <> TJsonKind.Array_ then
      begin
        ReportNode(Value, Format('"memberOrder.%s" muss eine Liste sein', [Key]));
        Continue;
      end;
      Names := nil;
      for Item := 0 to Value.Count - 1 do
        if ExpectString(Value[Item], Key, Text) then
        begin
          if ((Key = 'sections') and not MatchText(Text, SectionNames)) or
            ((Key = 'members') and not MatchText(Text, MemberNames)) then
            ReportNode(Value[Item], Format('Unbekannter Eintrag "%s" in "memberOrder.%s"', [Text, Key]))
          else
            Names := Names + [LowerCase(Text)];
        end;
      if Key = 'sections' then
        FSettings.MemberOrder.Sections := Names
      else
        FSettings.MemberOrder.Members := Names;
    end
    else if Key = 'sortFields' then
      ExpectBoolean(Value, Key, FSettings.MemberOrder.SortFields)
    else if Key = 'sortPublished' then
      ExpectBoolean(Value, Key, FSettings.MemberOrder.SortPublished)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "memberOrder.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadTests(ANode: TJsonNode);
var
  mIndex, mDepth: Integer;
  mKey: string;
  mValue: TJsonNode;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"tests" muss ein Objekt sein');
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    mValue := ANode[mIndex];
    if mKey = 'affected' then
      ExpectBoolean(mValue, mKey, FSettings.Tests.Affected)
    else if mKey = 'affectedDepth' then
    begin
      if (mValue.Kind = TJsonKind.Number) and TryStrToInt(mValue.Value, mDepth) and
        (mDepth >= TTestsSettings.MinAffectedDepth) and (mDepth <= TTestsSettings.MaxAffectedDepth) then
        FSettings.Tests.AffectedDepth := mDepth
      else
        ReportNode(mValue, '"affectedDepth" muss eine ganze Zahl von 1 bis 5 sein');
    end
    else
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Einstellung "tests.%s"', [mKey]), False);
  end;
end;

procedure TValidator.ReadTestUnits(ANode: TJsonNode);
var
  Index: Integer;
  Key, Text: string;
  Value: TJsonNode;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"testUnits" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if Key = 'pattern' then
    begin
      if ExpectString(Value, Key, Text) then
      begin
        // Ohne {unit} hätten alle Units dieselbe Testunit.
        if Pos('{unit}', Text) = 0 then
          ReportNode(Value, '"testUnits.pattern" muss {unit} enthalten')
        else
          FSettings.TestUnits.Pattern := Text;
      end;
    end
    else if Key = 'folder' then
    begin
      if ExpectString(Value, Key, Text) then
        FSettings.TestUnits.Folder := Text;
    end
    else if Key = 'project' then
    begin
      if ExpectString(Value, Key, Text) then
      begin
        if (Text <> '') and not MatchText(ExtractFileExt(Text), ['.dproj', '.dpr']) then
          ReportNode(Value, '"testUnits.project" muss eine .dproj oder .dpr sein')
        else
          FSettings.TestUnits.Project := Text;
      end;
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "testUnits.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadHighlight(ANode: TJsonNode);
var
  Index, Item: Integer;
  Key, Value: string;
  Node: TJsonNode;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"highlight" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Node := ANode[Index];
    if Key = 'blockPairs' then
      ExpectBoolean(Node, Key, FSettings.Highlight.BlockPairs)
    else if Key = 'directives' then
      ExpectBoolean(Node, Key, FSettings.Highlight.Directives)
    else if Key = 'exitPoints' then
      ExpectBoolean(Node, Key, FSettings.Highlight.ExitPoints)
    else if Key = 'exitKeywords' then
    begin
      if Node.Kind <> TJsonKind.Array_ then
      begin
        ReportNode(Node, '"exitKeywords" muss eine Liste von Namen sein');
        Continue;
      end;
      FSettings.Highlight.ExitKeywords := nil;
      for Item := 0 to Node.Count - 1 do
        if ExpectString(Node[Item], 'exitKeywords', Value) then
          FSettings.Highlight.ExitKeywords := FSettings.Highlight.ExitKeywords + [Value];
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "highlight.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadRefactoring(ANode: TJsonNode);
var
  Index, Item: Integer;
  Key, Value: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"refactoring" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'inlineVar' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineVar)
    else if Key = 'changeSignature' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ChangeSignature)
    else if Key = 'newParameter' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if SameText(Value, 'overload') or SameText(Value, 'updateCallers') then
          FSettings.Refactoring.NewParameterOverload := SameText(Value, 'overload')
        else
          ReportNode(ANode[Index], '"refactoring.newParameter" muss "overload" oder "updateCallers" sein');
    end
    else if Key = 'virtualOverload' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.VirtualOverload)
    else if Key = 'syncSignatures' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.SyncSignatures)
    else if Key = 'forwardDeclaration' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ForwardDeclaration)
    else if Key = 'tryFinally' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.TryFinally)
    else if Key = 'classActions' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ClassActions)
    else if Key = 'explicitType' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ExplicitType)
    else if Key = 'compilerFixes' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.CompilerFixes)
    else if Key = 'missingUnit' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MissingUnit)
    else if Key = 'disableWarning' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.DisableWarning)
    else if Key = 'disableWarningReason' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.DisableWarningReason)
    else if Key = 'extract' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.Extract)
    else if Key = 'completeCase' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.CompleteCase)
    else if Key = 'resolveWith' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ResolveWith)
    else if Key = 'inline' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineCode)
    else if Key = 'moveClass' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MoveClass)
    else if Key = 'unitRenameFollowUp' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if SameText(Value, 'ask') or SameText(Value, 'off') then
          FSettings.Refactoring.UnitRenameFollowUp := SameText(Value, 'ask')
        else
          ReportNode(ANode[Index], '"refactoring.unitRenameFollowUp" muss "ask" oder "off" sein');
    end
    else if Key = 'createMethod' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.CreateMethod)
    else if Key = 'createMethodSection' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if MatchText(Value, ['private', 'protected', 'public']) then
          FSettings.Refactoring.CreateMethodSection := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.createMethodSection" muss "private", "protected" oder "public" sein');
    end
    else if Key = 'createMethodCaret' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if SameText(Value, 'call') or SameText(Value, 'body') then
          FSettings.Refactoring.CreateMethodCaretInBody := SameText(Value, 'body')
        else
          ReportNode(ANode[Index], '"refactoring.createMethodCaret" muss "call" oder "body" sein');
    end
    else if Key = 'constParameters' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ConstParameters)
    else if Key = 'propertyFromAccessors' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.PropertyFromAccessors)
    else if Key = 'propertyFromAccessorsPrefixes' then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
        ReportNode(ANode[Index], '"refactoring.propertyFromAccessorsPrefixes" muss eine Liste von Präfixen sein')
      else
      begin
        FSettings.Refactoring.PropertyFromAccessorsPrefixes := nil;
        for Item := 0 to ANode[Index].Count - 1 do
          if ExpectString(ANode[Index][Item], Key, Value) and (Trim(Value) <> '') then
            FSettings.Refactoring.PropertyFromAccessorsPrefixes :=
              FSettings.Refactoring.PropertyFromAccessorsPrefixes + [Trim(Value)];
      end;
    end
    else if Key = 'propertyFromAccessorsReplaceCalls' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if MatchText(Value, ['ask', 'always', 'never']) then
          FSettings.Refactoring.PropertyFromAccessorsReplaceCalls := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.propertyFromAccessorsReplaceCalls" muss "ask", "always" oder ' +
            '"never" sein');
    end
    else if Key = 'propertyFromAccessorsSection' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if MatchText(Value, ['accessor', 'public', 'published']) then
          FSettings.Refactoring.PropertyFromAccessorsSection := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.propertyFromAccessorsSection" muss "accessor", "public" oder ' +
            '"published" sein');
    end
    else if Key = 'propertyFromAccessorsHideAccessors' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if MatchText(Value, ['off', 'private', 'protected']) then
          FSettings.Refactoring.PropertyFromAccessorsHideAccessors := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.propertyFromAccessorsHideAccessors" muss "off", "private" oder ' +
            '"protected" sein');
    end
    else if Key = 'freeFields' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.FreeFields)
    else if Key = 'freeFieldsStyle' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if SameText(Value, 'free') then
          FSettings.Refactoring.FreeFieldsStyle := 'free'
        else if SameText(Value, 'freeAndNil') then
          FSettings.Refactoring.FreeFieldsStyle := 'freeAndNil'
        else
          ReportNode(ANode[Index], '"refactoring.freeFieldsStyle" muss "free" oder "freeAndNil" sein');
    end
    else if Key = 'suggestConst' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.SuggestConst)
    else if Key = 'invertBoolean' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InvertBoolean)
    else if Key = 'varBlock' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.VarBlock)
    else if Key = 'varBlockMerge' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.VarBlockMerge)
    else if Key = 'varBlockSort' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if MatchText(Value, ['usage', 'alpha', 'none']) then
          FSettings.Refactoring.VarBlockSort := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.varBlockSort" muss "usage", "alpha" oder "none" sein');
    end
    else if Key = 'invertBooleanAntonyms' then
    begin
      // {"Hidden": "Visible"}: Name → Gegenteil, beide Richtungen.
      if ANode[Index].Kind <> TJsonKind.Object_ then
        ReportNode(ANode[Index], '"refactoring.invertBooleanAntonyms" muss ein Objekt wie {"Hidden": "Visible"} sein')
      else
      begin
        FSettings.Refactoring.InvertBooleanAntonyms := nil;
        for Item := 0 to ANode[Index].Count - 1 do
          if ExpectString(ANode[Index][Item], Key, Value) then
            if IsValidIdent(ANode[Index].Keys[Item]) and IsValidIdent(Trim(Value)) then
              FSettings.Refactoring.InvertBooleanAntonyms := FSettings.Refactoring.InvertBooleanAntonyms +
                [ANode[Index].Keys[Item] + '=' + Trim(Value)]
            else
              ReportNode(ANode[Index][Item], Format('"refactoring.invertBooleanAntonyms": "%s" und "%s" müssen ' +
                'Bezeichner sein', [ANode[Index].Keys[Item], Value]));
      end;
    end
    else if Key = 'invertBooleanFallbackPrefix' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if IsValidIdent(Trim(Value)) then
          FSettings.Refactoring.InvertBooleanFallbackPrefix := Trim(Value)
        else
          ReportNode(ANode[Index], '"refactoring.invertBooleanFallbackPrefix" muss ein Bezeichner wie "Not" sein');
    end
    else if Key = 'invertBooleanIncludeDfm' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InvertBooleanIncludeDfm)
    else if Key = 'ifCase' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.IfCase)
    else if Key = 'conditions' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.Conditions)
    else if Key = 'conditionalExpression' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ConditionalExpression)
    else if Key = 'nestedRoutine' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.NestedRoutine)
    else if Key = 'promoteVariable' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.PromoteVariable)
    else if Key = 'anonymousMethod' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.AnonymousMethod)
    else if Key = 'anonymousMethodDeferredCapture' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if SameText(Value, 'forward') then
          FSettings.Refactoring.AnonymousMethodDeferredCapture := 'forward'
        else if SameText(Value, 'fields') then
          FSettings.Refactoring.AnonymousMethodDeferredCapture := 'fields'
        else
          ReportNode(ANode[Index], '"refactoring.anonymousMethodDeferredCapture" muss "forward" oder "fields" sein');
    end
    else if Key = 'methodKind' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MethodKind)
    else if Key = 'methodKindMarker' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MethodKindMarker)
    else if Key = 'methodKindStatic' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MethodKindStatic)
    else if Key = 'typeAlias' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.TypeAlias)
    else if Key = 'typeAliasScope' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if SameText(Value, 'here') or SameText(Value, 'unit') or SameText(Value, 'project') then
          FSettings.Refactoring.TypeAliasScope := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.typeAliasScope" muss "here", "unit" oder "project" sein');
    end
    else if Key = 'enumTables' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.EnumTables)
    else if Key = 'enumTablesResourceStrings' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.EnumTablesResourceStrings)
    else if Key = 'extractInterface' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ExtractInterface)
    else if Key = 'extractSuperclass' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ExtractSuperclass)
    else if Key = 'extractSuperclassTarget' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if SameText(Value, 'sameUnit') then
          FSettings.Refactoring.ExtractSuperclassTarget := 'sameUnit'
        else if SameText(Value, 'newUnit') then
          FSettings.Refactoring.ExtractSuperclassTarget := 'newUnit'
        else
          ReportNode(ANode[Index], '"refactoring.extractSuperclassTarget" muss "sameUnit" oder "newUnit" sein');
    end
    else if Key = 'extractSuperclassNameSuffix' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if IsValidIdent(Trim(Value)) then
          FSettings.Refactoring.ExtractSuperclassNameSuffix := Trim(Value)
        else
          ReportNode(ANode[Index], '"refactoring.extractSuperclassNameSuffix" muss ein Bezeichner wie "Base" sein');
    end
    else if Key = 'extractSuperclassMethodMode' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if MatchText(Value, ['move', 'abstract']) then
          FSettings.Refactoring.ExtractSuperclassMethodMode := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.extractSuperclassMethodMode" muss "move" oder "abstract" sein');
    end
    else if Key = 'extractSuperclassRaiseVisibility' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if SameText(Value, 'protected') then
          FSettings.Refactoring.ExtractSuperclassRaiseVisibility := 'protected'
        else if SameText(Value, 'strictProtected') then
          FSettings.Refactoring.ExtractSuperclassRaiseVisibility := 'strictProtected'
        else
          ReportNode(ANode[Index], '"refactoring.extractSuperclassRaiseVisibility" muss "protected" oder ' +
            '"strictProtected" sein');
    end
    else if Key = 'moveMember' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MoveMember)
    else if Key = 'inlineAccessor' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineAccessor)
    else if Key = 'inlineAccessorEqualityCheck' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineAccessorEqualityCheck)
    else if Key = 'inlineAccessorBulk' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineAccessorBulk)
    else if Key = 'inlineAccessorDiagnostic' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineAccessorDiagnostic)
    else if Key = 'safeDelete' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.SafeDelete)
    else if Key = 'safeDeletePreviewWhenUnused' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.SafeDeletePreviewWhenUnused)
    else if Key = 'safeDeleteCascade' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if MatchText(Value, ['ask', 'always', 'never']) then
          FSettings.Refactoring.SafeDeleteCascade := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.safeDeleteCascade" muss "ask", "always" oder "never" sein');
    end
    else if Key = 'safeDeleteIncludeOverrides' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
        if MatchText(Value, ['ask', 'always', 'never']) then
          FSettings.Refactoring.SafeDeleteIncludeOverrides := LowerCase(Value)
        else
          ReportNode(ANode[Index], '"refactoring.safeDeleteIncludeOverrides" muss "ask", "always" oder "never" sein');
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "refactoring.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadCompiler(ANode: TJsonNode);
var
  Index: Integer;
  Key, Text: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"compiler" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'onSave' then
      ExpectBoolean(ANode[Index], Key, FSettings.Compiler.OnSave)
    else if Key = 'backend' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if Text = 'auto' then
          FSettings.Compiler.Backend := TCompilerBackendSetting.Auto
        else if Text = 'dcc' then
          FSettings.Compiler.Backend := TCompilerBackendSetting.Dcc
        else if Text = 'ide' then
          FSettings.Compiler.Backend := TCompilerBackendSetting.Ide
        else if Text = 'off' then
          FSettings.Compiler.Backend := TCompilerBackendSetting.Off
        else
          ReportNode(ANode[Index], 'Erlaubt sind "auto", "dcc", "ide" und "off"');
    end
    else if Key = 'ideCommand' then
      ExpectString(ANode[Index], Key, FSettings.Compiler.IdeCommand)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "compiler.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadVcs(ANode: TJsonNode);

  // vcs.git bzw. vcs.svn (#1285): nur "path", leer = automatisch suchen.
  procedure ReadTool(AToolNode: TJsonNode; const AName: string; var APath: string);
  var
    mIndex: Integer;
    mKey: string;
  begin
    if AToolNode.Kind <> TJsonKind.Object_ then
    begin
      ReportNode(AToolNode, Format('"vcs.%s" muss ein Objekt sein', [AName]));
      Exit;
    end;
    for mIndex := 0 to AToolNode.Count - 1 do
    begin
      mKey := AToolNode.Keys[mIndex];
      if mKey = 'path' then
        ExpectString(AToolNode[mIndex], mKey, APath)
      else
        Report(AToolNode.KeyStarts[mIndex], AToolNode.KeyStarts[mIndex] + Length(mKey) + 2,
          Format('Unbekannte Einstellung "vcs.%s.%s"', [AName, mKey]), False);
    end;
  end;

var
  Index: Integer;
  Key, Text: string;
  mSeconds: Integer;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"vcs" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'provider' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if MatchStr(Text, ['auto', 'git', 'svn', 'off']) then
          FSettings.VcsProvider := Text
        else
          ReportNode(ANode[Index], 'Erlaubt sind "auto", "git", "svn" und "off"');
    end
    else if Key = 'git' then
      ReadTool(ANode[Index], Key, FSettings.VcsGitPath)
    else if Key = 'svn' then
      ReadTool(ANode[Index], Key, FSettings.VcsSvnPath)
    else if Key = 'projects' then
      ReadVcsProjects(ANode[Index])
    else if Key = 'timeoutSeconds' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, mSeconds) and (mSeconds >= 1) and
        (mSeconds <= 300) then
        FSettings.VcsTimeoutSeconds := mSeconds
      else
        ReportNode(ANode[Index], '"vcs.timeoutSeconds" muss eine ganze Zahl von 1 bis 300 sein');
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "vcs.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadCompletion(ANode: TJsonNode);
var
  Index: Integer;
  Key, Text: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"completion" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'matching' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if Text = 'fuzzy' then
          FSettings.Completion.Matching := TCompletionMatching.Fuzzy
        else if Text = 'prefix' then
          FSettings.Completion.Matching := TCompletionMatching.Prefix
        else
          ReportNode(ANode[Index], 'Erlaubt sind "fuzzy" und "prefix"');
    end
    else if Key = 'interfaceSection' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if Text = 'private' then
          FSettings.Completion.InterfaceSection := TCompletionInterfaceSection.Private
        else if Text = 'protected' then
          FSettings.Completion.InterfaceSection := TCompletionInterfaceSection.Protected
        else if Text = 'public' then
          FSettings.Completion.InterfaceSection := TCompletionInterfaceSection.Public
        else
          ReportNode(ANode[Index], 'Erlaubt sind "private", "protected" und "public"');
    end
    else if Key = 'senderCast' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if Text = 'as' then
          FSettings.Completion.SenderCast := TCompletionSenderCast.AsOperator
        else if Text = 'cast' then
          FSettings.Completion.SenderCast := TCompletionSenderCast.HardCast
        else
          ReportNode(ANode[Index], 'Erlaubt sind "as" und "cast"');
    end
    else if Key = 'offerTryFinally' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.OfferTryFinally)
    else if Key = 'keywords' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.Keywords)
    else if Key = 'postfixTemplates' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.PostfixTemplates)
    else if Key = 'genericConstraints' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.GenericConstraints)
    else if Key = 'nameSuggestions' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.NameSuggestions)
    else if Key = 'createAccessors' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.CreateAccessors)
    else if Key = 'accessorSection' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if Text = 'private' then
          FSettings.Completion.AccessorSection := TCompletionAccessorSection.Private
        else if Text = 'protected' then
          FSettings.Completion.AccessorSection := TCompletionAccessorSection.Protected
        else
          ReportNode(ANode[Index], 'Erlaubt sind "private" und "protected"');
    end
    else if Key = 'resourceStrings' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.ResourceStrings)
    else if Key = 'assignAllFields' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.AssignAllFields)
    else if Key = 'usesDetails' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.UsesDetails)
    else if Key = 'inheritedCall' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.InheritedCall)
    else if Key = 'attributes' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.Attributes)
    else if Key = 'anonymousMethods' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.AnonymousMethods)
    else if Key = 'withOrigin' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.WithOrigin)
    else if Key = 'exceptionClasses' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.ExceptionClasses)
    else if Key = 'syntaxNotice' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.SyntaxNotice)
    else if Key = 'sameNameVariants' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.SameNameVariants)
    else if Key = 'showFmxUnits' then
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.ShowFmxUnits)
    else if Key = 'sameNameInsert' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if Text = 'prefix' then
          FSettings.Completion.SameNameInsert := TCompletionSameNameInsert.Prefix
        else if Text = 'uses' then
          FSettings.Completion.SameNameInsert := TCompletionSameNameInsert.Uses_
        else
          ReportNode(ANode[Index], 'Erlaubt sind "prefix" und "uses"');
    end
    else if Key = 'typeConversion' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if Text = 'off' then
          FSettings.Completion.TypeConversion := TCompletionTypeConversion.Off
        else if Text = 'helper' then
          FSettings.Completion.TypeConversion := TCompletionTypeConversion.Helper
        else if Text = 'function' then
          FSettings.Completion.TypeConversion := TCompletionTypeConversion.Function_
        else
          ReportNode(ANode[Index], 'Erlaubt sind "off", "helper" und "function"');
    end
    else if Key = 'resourceStringUnit' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if (Text = '') or IsValidIdent(Text, True) then
          FSettings.Completion.ResourceStringUnit := Text
        else
          ReportNode(ANode[Index], 'Erwartet wird ein Unit-Name wie "App.Texte" oder ""');
    end
    else if Key = 'freeStyle' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
        if Text = 'free' then
          FSettings.Completion.FreeStyle := TCompletionFreeStyle.Free
        else if Text = 'freeAndNil' then
          FSettings.Completion.FreeStyle := TCompletionFreeStyle.FreeAndNil
        else
          ReportNode(ANode[Index], 'Erlaubt sind "free" und "freeAndNil"');
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "completion.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadDiagnostics(ANode: TJsonNode);
var
  Index, Days: Integer;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"diagnostics" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'log' then
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsLog)
    else if Key = 'logDays' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, Days) and (Days >= 1) and
        (Days <= 365) then
        FSettings.DiagnosticsLogDays := Days
      else
        ReportNode(ANode[Index], '"diagnostics.logDays" muss eine ganze Zahl von 1 bis 365 sein');
    end
    else if Key = 'logMapFile' then
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsLogMapFile)
    else if Key = 'usesCycleLive' then
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsUsesCycleLive)
    else if Key = 'usesCycleImplementation' then
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsUsesCycleImplementation)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "diagnostics.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadIndex(ANode: TJsonNode);
var
  Index, Item, Number: Integer;
  Key, Value: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"index" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'projectGroup' then
      ExpectBoolean(ANode[Index], Key, FSettings.IndexProjectGroup)
    else if Key = 'searchPaths' then
      ExpectBoolean(ANode[Index], Key, FSettings.IndexSearchPaths)
    else if Key = 'libraryPaths' then
      ExpectBoolean(ANode[Index], Key, FSettings.IndexLibraryPaths)
    else if Key = 'usages' then
      ExpectBoolean(ANode[Index], Key, FSettings.IndexUsages)
    else if Key = 'removeOrphans' then
      ExpectBoolean(ANode[Index], Key, FSettings.IndexRemoveOrphans)
    else if Key = 'cacheMaxAgeDays' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, Number) and (Number >= 0) and
        (Number <= 3650) then
        FSettings.IndexCacheMaxAgeDays := Number
      else
        ReportNode(ANode[Index], '"index.cacheMaxAgeDays" muss eine ganze Zahl von 0 bis 3650 sein');
    end
    else if Key = 'cacheMaxMb' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, Number) and (Number >= 0) and
        (Number <= 1048576) then
        FSettings.IndexCacheMaxMb := Number
      else
        ReportNode(ANode[Index], '"index.cacheMaxMb" muss eine ganze Zahl von 0 bis 1048576 sein');
    end
    else if Key = 'exclude' then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[Index], '"index.exclude" muss eine Liste von Mustern sein');
        Continue;
      end;
      FSettings.IndexExclude := nil;
      for Item := 0 to ANode[Index].Count - 1 do
        if ExpectString(ANode[Index][Item], 'index.exclude', Value) then
          FSettings.IndexExclude := FSettings.IndexExclude + [Value];
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "index.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadHotspots(ANode: TJsonNode);
var
  mIndex, mInner, mNumber: Integer;
  mKey, mInnerKey: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"hotspots" muss ein Objekt sein');
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    if mKey = 'enabled' then
      ExpectBoolean(ANode[mIndex], mKey, FSettings.HotspotsEnabled)
    else if mKey = 'months' then
    begin
      if (ANode[mIndex].Kind = TJsonKind.Number) and TryStrToInt(ANode[mIndex].Value, mNumber) and (mNumber >= 1) and
        (mNumber <= 60) then
        FSettings.HotspotsMonths := mNumber
      else
        ReportNode(ANode[mIndex], '"hotspots.months" muss eine ganze Zahl von 1 bis 60 sein');
    end
    else if mKey = 'coupling' then
    begin
      if ANode[mIndex].Kind <> TJsonKind.Object_ then
      begin
        ReportNode(ANode[mIndex], '"hotspots.coupling" muss ein Objekt sein');
        Continue;
      end;
      for mInner := 0 to ANode[mIndex].Count - 1 do
      begin
        mInnerKey := ANode[mIndex].Keys[mInner];
        if mInnerKey = 'minCommits' then
        begin
          if (ANode[mIndex][mInner].Kind = TJsonKind.Number) and TryStrToInt(ANode[mIndex][mInner].Value, mNumber) and
            (mNumber >= 2) and (mNumber <= 1000) then
            FSettings.HotspotsCouplingMinCommits := mNumber
          else
            ReportNode(ANode[mIndex][mInner],
              '"hotspots.coupling.minCommits" muss eine ganze Zahl von 2 bis 1000 sein');
        end
        else
          Report(ANode[mIndex].KeyStarts[mInner], ANode[mIndex].KeyStarts[mInner] + Length(mInnerKey) + 2,
            Format('Unbekannte Einstellung "hotspots.coupling.%s"', [mInnerKey]), False);
      end;
    end
    else
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Einstellung "hotspots.%s"', [mKey]), False);
  end;
end;

procedure TValidator.ReadArchitecture(ANode: TJsonNode);

  // Zahl von AMin bis AMax; sonst Fehler mit ARange ("0,2 bis 5,0").
  procedure ReadNumber(AValueNode: TJsonNode; const AName, ARange: string; AMin, AMax: Double; var AValue: Double);
  var
    mNumber: Double;
  begin
    if (AValueNode.Kind = TJsonKind.Number) and TryStrToFloat(AValueNode.Value, mNumber, TFormatSettings.Invariant) and
      (mNumber >= AMin) and (mNumber <= AMax) then
      AValue := mNumber
    else
      ReportNode(AValueNode, Format('"architecture.grouping.%s" muss eine Zahl von %s sein', [AName, ARange]));
  end;

  // architecture.grouping: Gruppierung der Teilsysteme (#1366, #1364, #1365, #1367).
  procedure ReadGrouping(AGroupNode: TJsonNode);
  var
    mIndex: Integer;
    mKey: string;
  begin
    if AGroupNode.Kind <> TJsonKind.Object_ then
    begin
      ReportNode(AGroupNode, '"architecture.grouping" muss ein Objekt sein');
      Exit;
    end;
    for mIndex := 0 to AGroupNode.Count - 1 do
    begin
      mKey := AGroupNode.Keys[mIndex];
      if mKey = 'resolution' then
        ReadNumber(AGroupNode[mIndex], mKey, '0,2 bis 5,0', 0.2, 5, FSettings.ArchitectureGroupingResolution)
      else if mKey = 'maxShare' then
        ReadNumber(AGroupNode[mIndex], mKey, '0 bis 0,9', 0, 0.9, FSettings.ArchitectureGroupingMaxShare)
      else if mKey = 'minCohesion' then
        ReadNumber(AGroupNode[mIndex], mKey, '0 bis 1', 0, 1, FSettings.ArchitectureGroupingMinCohesion)
      else if mKey = 'foundations' then
      begin
        if (AGroupNode[mIndex].Kind = TJsonKind.String_) and ((AGroupNode[mIndex].Value = 'group') or
          (AGroupNode[mIndex].Value = 'attach') or (AGroupNode[mIndex].Value = 'separate')) then
          FSettings.ArchitectureGroupingFoundations := AGroupNode[mIndex].Value
        else
          ReportNode(AGroupNode[mIndex],
            '"architecture.grouping.foundations" muss "group", "attach" oder "separate" sein');
      end
      else if mKey = 'showResolutionSlider' then
        ExpectBoolean(AGroupNode[mIndex], mKey, FSettings.ArchitectureGroupingShowResolutionSlider)
      else if mKey = 'keepPrevious' then
        ExpectBoolean(AGroupNode[mIndex], mKey, FSettings.ArchitectureGroupingKeepPrevious)
      else
        Report(AGroupNode.KeyStarts[mIndex], AGroupNode.KeyStarts[mIndex] + Length(mKey) + 2,
          Format('Unbekannte Einstellung "architecture.grouping.%s"', [mKey]), False);
    end;
  end;

var
  Index, Item, Number: Integer;
  Key, Value: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"architecture" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'enabled' then
      ExpectBoolean(ANode[Index], Key, FSettings.ArchitectureEnabled)
    else if Key = 'scope' then
    begin
      if (ANode[Index].Kind = TJsonKind.String_) and ((ANode[Index].Value = 'project') or
        (ANode[Index].Value = 'projectGroup')) then
        FSettings.ArchitectureScope := ANode[Index].Value
      else
        ReportNode(ANode[Index], '"architecture.scope" muss "project" oder "projectGroup" sein');
    end
    else if Key = 'includeLibraryUnits' then
      ExpectBoolean(ANode[Index], Key, FSettings.ArchitectureIncludeLibraryUnits)
    else if Key = 'centralUnits' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, Number) and (Number >= 5) and
        (Number <= 100) then
        FSettings.ArchitectureCentralUnits := Number
      else
        ReportNode(ANode[Index], '"architecture.centralUnits" muss eine ganze Zahl von 5 bis 100 sein');
    end
    else if Key = 'exclude' then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[Index], '"architecture.exclude" muss eine Liste von Mustern sein');
        Continue;
      end;
      FSettings.ArchitectureExclude := nil;
      for Item := 0 to ANode[Index].Count - 1 do
        if ExpectString(ANode[Index][Item], 'architecture.exclude', Value) then
          FSettings.ArchitectureExclude := FSettings.ArchitectureExclude + [Value];
    end
    else if Key = 'baseline' then
    begin
      if ExpectString(ANode[Index], 'architecture.baseline', Value) then
        FSettings.ArchitectureBaseline := Trim(Value);
    end
    else if Key = 'failOn' then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[Index], '"architecture.failOn" muss eine Liste aus newCycle, newCrossLink, ' +
          'subsystemChange und centralGrowth sein');
        Continue;
      end;
      FSettings.ArchitectureFailOn := nil;
      for Item := 0 to ANode[Index].Count - 1 do
        if ExpectString(ANode[Index][Item], 'architecture.failOn', Value) then
        begin
          if (Value = 'newCycle') or (Value = 'newCrossLink') or (Value = 'subsystemChange') or
            (Value = 'centralGrowth') then
            FSettings.ArchitectureFailOn := FSettings.ArchitectureFailOn + [Value]
          else
            ReportNode(ANode[Index][Item], Format('"architecture.failOn": unbekannte Abweichung "%s" (erlaubt: ' +
              'newCycle, newCrossLink, subsystemChange, centralGrowth)', [Value]));
        end;
    end
    else if Key = 'explainAssignment' then
      ExpectBoolean(ANode[Index], Key, FSettings.ArchitectureExplainAssignment)
    else if Key = 'grouping' then
      ReadGrouping(ANode[Index])
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "architecture.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadFormat(ANode: TJsonNode);
var
  Index, Size: Integer;
  Key: string;
  Value: TJsonNode;
  mSettings: TFormatStyle;

  procedure ReadBoolean(var ATarget: Boolean; AKey: TFormatKey);
  begin
    if ExpectBoolean(Value, Key, ATarget) then
      Include(mSettings.Given, AKey);
  end;

  procedure ReadPlacement(var ATarget: TBlockPlacement);
  begin
    if (Value.Kind = TJsonKind.String_) and (Value.Value = 'preserve') then
      ATarget := TBlockPlacement.Preserve
    else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'newLine') then
      ATarget := TBlockPlacement.NewLine
    else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'sameLine') then
      ATarget := TBlockPlacement.SameLine
    else
      ReportNode(Value, 'Erlaubt sind "preserve", "newLine" und "sameLine"');
  end;

begin
  mSettings := TFormatStyle.Default;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if Key = 'indentSize' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Size) and (Size >= 1) and (Size <= 16) then
      begin
        mSettings.IndentSize := Size;
        Include(mSettings.Given, TFormatKey.IndentSize);
      end
      else
        ReportNode(Value, '"indentSize" muss eine ganze Zahl von 1 bis 16 sein');
    end
    else if Key = 'useTabs' then
      ReadBoolean(mSettings.UseTabs, TFormatKey.UseTabs)
    else if Key = 'trimTrailingWhitespace' then
      ReadBoolean(mSettings.TrimTrailingWhitespace, TFormatKey.TrimTrailingWhitespace)
    else if Key = 'insertFinalNewline' then
      ReadBoolean(mSettings.InsertFinalNewline, TFormatKey.InsertFinalNewline)
    else if Key = 'spaceAroundAssignment' then
      ReadBoolean(mSettings.SpaceAroundAssignment, TFormatKey.SpaceAroundAssignment)
    else if Key = 'spaceAfterComma' then
      ReadBoolean(mSettings.SpaceAfterComma, TFormatKey.SpaceAfterComma)
    else if Key = 'keywordCase' then
    begin
      if (Value.Kind = TJsonKind.String_) and (Value.Value = 'preserve') then
        mSettings.KeywordCase := TKeywordCase.Preserve
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'lower') then
        mSettings.KeywordCase := TKeywordCase.Lower
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'upper') then
        mSettings.KeywordCase := TKeywordCase.Upper
      else
      begin
        ReportNode(Value, 'Erlaubt sind "preserve", "lower" und "upper"');
        Continue;
      end;
      Include(mSettings.Given, TFormatKey.KeywordCase);
    end
    else if Key = 'endOfLine' then
    begin
      if (Value.Kind = TJsonKind.String_) and (Value.Value = 'lf') then
        mSettings.EndOfLine := #10
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'crlf') then
        mSettings.EndOfLine := #13#10
      else
      begin
        ReportNode(Value, 'Erlaubt sind "lf" und "crlf"');
        Continue;
      end;
      Include(mSettings.Given, TFormatKey.EndOfLine);
    end
    else if Key = 'reindent' then
      ExpectBoolean(Value, Key, mSettings.Reindent)
    else if Key = 'beginPlacement' then
      ReadPlacement(mSettings.BeginPlacement)
    else if Key = 'elsePlacement' then
      ReadPlacement(mSettings.ElsePlacement)
    else if Key = 'maxLineLength' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Size) and (Size >= 0) and (Size <= 1000) then
      begin
        mSettings.MaxLineLength := Size;
        Include(mSettings.Given, TFormatKey.MaxLineLength);
      end
      else
        ReportNode(Value, '"maxLineLength" muss eine ganze Zahl von 0 bis 1000 sein');
    end
    else if Key = 'alignAssignments' then
      ExpectBoolean(Value, Key, mSettings.AlignAssignments)
    else if Key = 'alignDeclarations' then
      ExpectBoolean(Value, Key, mSettings.AlignDeclarations)
    else if Key = 'alignComments' then
      ExpectBoolean(Value, Key, mSettings.AlignComments)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "format.%s"', [Key]), False);
  end;
  FSettings.Formatting := mSettings;
end;

procedure TValidator.ReadTaskMatcher(ANode: TJsonNode);
var
  Index, Item: Integer;
  Key, Text: string;
  HasRegex: Boolean;
begin
  if ANode.Kind = TJsonKind.String_ then
  begin
    if IndexStr(ANode.Value, ['dcc', 'pwsh', 'msbuild', 'generic', 'none']) < 0 then
      ReportNode(ANode, 'Erlaubt sind "dcc", "pwsh", "msbuild", "generic", "none" oder ein Objekt mit "regex"');
    Exit;
  end;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"matcher" muss ein Name oder ein Objekt mit "regex" sein');
    Exit;
  end;
  HasRegex := False;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'regex' then
    begin
      if ExpectString(ANode[Index], 'regex', Text) then
        if Text = '' then
          ReportNode(ANode[Index], '"regex" darf nicht leer sein')
        else
          HasRegex := True;
    end
    else if Key = 'severity' then
    begin
      if ExpectString(ANode[Index], 'severity', Text) and (IndexStr(Text, ['error', 'warning', 'info']) < 0) then
        ReportNode(ANode[Index], 'Erlaubt sind "error", "warning" und "info"');
    end
    else if Key = 'severityMap' then
    begin
      if ANode[Index].Kind <> TJsonKind.Object_ then
      begin
        ReportNode(ANode[Index], '"severityMap" muss ein Objekt Wort → error, warning oder info sein');
        Continue;
      end;
      for Item := 0 to ANode[Index].Count - 1 do
        if ExpectString(ANode[Index][Item], 'severityMap', Text) and
          (IndexStr(Text, ['error', 'warning', 'info']) < 0) then
          ReportNode(ANode[Index][Item], 'Erlaubt sind "error", "warning" und "info"');
    end
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Angabe "%s" im Muster; erlaubt: regex, severity, severityMap', [Key]), False);
  end;
  if not HasRegex then
    ReportNode(ANode, 'Eigenes Muster ohne "regex"');
end;

procedure TValidator.ReadTasks(ANode: TJsonNode);
var
  Index, Inner, Item, Number: Integer;
  Task, Value: TJsonNode;
  Key, Text: string;
  Names: TList<string>;
  HasName, HasCommand: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"tasks" muss eine Liste von Aufgaben sein');
    Exit;
  end;
  FSettings.Tasks := Copy(FText, ANode.Start + 1, ANode.Stop - ANode.Start);
  Names := TList<string>.Create;
  try
    for Index := 0 to ANode.Count - 1 do
    begin
      Task := ANode[Index];
      if Task.Kind <> TJsonKind.Object_ then
      begin
        ReportNode(Task, 'Eine Aufgabe ist ein Objekt mit "name" und "command"');
        Continue;
      end;
      HasName := False;
      HasCommand := False;
      for Inner := 0 to Task.Count - 1 do
      begin
        Key := Task.Keys[Inner];
        Value := Task[Inner];
        if Key = 'name' then
        begin
          if ExpectString(Value, 'name', Text) and (Trim(Text) <> '') then
          begin
            HasName := True;
            // Gleicher Name: Die spätere Aufgabe wäre nie erreichbar (Projekt vor global gilt nur zwischen Dateien).
            if Names.IndexOf(AnsiLowerCase(Trim(Text))) >= 0 then
              ReportNode(Value, Format('Die Aufgabe "%s" gibt es schon', [Trim(Text)]))
            else
              Names.Add(AnsiLowerCase(Trim(Text)));
          end;
        end
        else if Key = 'command' then
          HasCommand := ExpectString(Value, 'command', Text) and (Trim(Text) <> '')
        else if (Key = 'cwd') or (Key = 'key') then
          ExpectString(Value, Key, Text)
        else if Key = 'args' then
        begin
          if Value.Kind <> TJsonKind.Array_ then
            ReportNode(Value, '"args" muss eine Liste von Texten sein')
          else
            for Item := 0 to Value.Count - 1 do
              if Value[Item].Kind <> TJsonKind.Number then
                ExpectString(Value[Item], 'args', Text);
        end
        else if Key = 'env' then
        begin
          if Value.Kind <> TJsonKind.Object_ then
            ReportNode(Value, '"env" muss ein Objekt Name → Wert sein')
          else
            for Item := 0 to Value.Count - 1 do
              ExpectString(Value[Item], 'env', Text);
        end
        else if Key = 'group' then
        begin
          if ExpectString(Value, 'group', Text) and (IndexStr(Text, ['check', 'build', 'test', 'other']) < 0) then
            ReportNode(Value, 'Erlaubt sind "check", "build", "test" und "other"');
        end
        else if Key = 'beforeBuild' then
        begin
          if ExpectString(Value, 'beforeBuild', Text) and (IndexStr(Text, ['off', 'warn', 'block']) < 0) then
            ReportNode(Value, 'Erlaubt sind "off", "warn" und "block"');
        end
        else if Key = 'timeoutSec' then
        begin
          if not ((Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Number) and (Number >= 0) and
            (Number <= 86400)) then
            ReportNode(Value, '"timeoutSec" muss eine ganze Zahl von 0 bis 86400 sein');
        end
        else if Key = 'matcher' then
          ReadTaskMatcher(Value)
        else
          Report(Task.KeyStarts[Inner], Task.KeyStarts[Inner] + Length(Key) + 2,
            Format('Unbekannte Angabe "%s" in einer Aufgabe', [Key]), False);
      end;
      if not HasName then
        ReportNode(Task, 'Aufgabe ohne "name"');
      if not HasCommand then
        ReportNode(Task, 'Aufgabe ohne "command"');
    end;
  finally
    Names.Free;
  end;
end;

procedure TValidator.ReadIssues(ANode: TJsonNode);
var
  Index: Integer;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"issues" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'connections' then
      ReadIssueConnections(ANode[Index])
    else if Key = 'projects' then
      ReadIssueProjects(ANode[Index])
    else if Key = 'queries' then
      ReadIssueQueries(ANode[Index])
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "issues.%s"', [Key]), False);
  end;
end;

/// <summary>Adresse eines Trackers: nur https, mit Rechner, ohne Benutzer und Leerzeichen (wie
/// TAtlasTrackerTarget im Plugin).</summary>
function IsTrackerUrl(const AUrl: string): Boolean;
var
  Host: string;
  Slash: Integer;
begin
  Result := False;
  if not SameText(Copy(AUrl, 1, 8), 'https://') then
    Exit;
  Host := Copy(AUrl, 9, MaxInt);
  Slash := Pos('/', Host);
  if Slash > 0 then
    Host := Copy(Host, 1, Slash - 1);
  Result := (Host <> '') and (Pos('@', Host) = 0) and (Pos(' ', AUrl) = 0);
end;

procedure TValidator.ReadIssueEndStates(ANode: TJsonNode);
var
  Index: Integer;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"endStates" muss eine Liste von Zuständen sein, z. B. ["Zur Prüfung", "Erledigt"]');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
    if ANode[Index].Kind <> TJsonKind.String_ then
      ReportNode(ANode[Index], 'Ein Zustand in "endStates" ist ein Text');
end;

procedure TValidator.ReadIssueConnections(ANode: TJsonNode);
var
  Index, Inner: Integer;
  Connection, Value: TJsonNode;
  Key, Text: string;
  Names: TList<string>;
  HasName, HasProvider, HasUrl: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"connections" muss eine Liste von Verbindungen sein');
    Exit;
  end;
  FSettings.IssueConnections := Copy(FText, ANode.Start + 1, ANode.Stop - ANode.Start);
  Names := TList<string>.Create;
  try
    for Index := 0 to ANode.Count - 1 do
    begin
      Connection := ANode[Index];
      if Connection.Kind <> TJsonKind.Object_ then
      begin
        ReportNode(Connection, 'Eine Verbindung ist ein Objekt mit "name", "provider" und "url"');
        Continue;
      end;
      HasName := False;
      HasProvider := False;
      HasUrl := False;
      for Inner := 0 to Connection.Count - 1 do
      begin
        Key := Connection.Keys[Inner];
        Value := Connection[Inner];
        if Key = 'name' then
        begin
          if ExpectString(Value, 'name', Text) and (Trim(Text) <> '') then
          begin
            HasName := True;
            if Names.IndexOf(AnsiLowerCase(Trim(Text))) >= 0 then
              ReportNode(Value, Format('Die Verbindung "%s" gibt es schon', [Trim(Text)]))
            else
              Names.Add(AnsiLowerCase(Trim(Text)));
          end;
        end
        else if Key = 'provider' then
          HasProvider := ExpectString(Value, 'provider', Text) and (Trim(Text) <> '')
        else if Key = 'url' then
        begin
          if ExpectString(Value, 'url', Text) then
          begin
            HasUrl := True;
            // Das Token geht nur über https und nie mit Benutzer in der Adresse an den Tracker.
            if not IsTrackerUrl(Trim(Text)) then
              ReportNode(Value, 'Nur https-Adressen ohne Benutzer, z. B. "https://youtrack.firma.de"');
          end;
        end
        else if Key = 'language' then
        begin
          // Sprache der Oberfläche (#1263), vom Plugin bei „Prüfen“ erkannt.
          if ExpectString(Value, 'language', Text) and (Text <> 'de') and (Text <> 'en') then
            ReportNode(Value, '"language" ist "de" oder "en"');
        end
        // Zustand beim Beginnen und Beenden je Verbindung (#1266).
        else if (Key = 'stateField') or (Key = 'assigneeField') or (Key = 'startState') then
          ExpectString(Value, Key, Text)
        else if Key = 'endStates' then
          ReadIssueEndStates(Value)
        else
          Report(Connection.KeyStarts[Inner], Connection.KeyStarts[Inner] + Length(Key) + 2,
            Format('Unbekannte Angabe "%s" in einer Verbindung', [Key]), False);
      end;
      if not HasName then
        ReportNode(Connection, 'Verbindung ohne "name"');
      if not HasProvider then
        ReportNode(Connection, 'Verbindung ohne "provider"');
      if not HasUrl then
        ReportNode(Connection, 'Verbindung ohne "url"');
    end;
  finally
    Names.Free;
  end;
end;

procedure TValidator.ReadVcsProjects(ANode: TJsonNode);
var
  mIndex, mInner: Integer;
  mMapping, mValue: TJsonNode;
  mKey, mText: string;
  mMatches: TList<string>;
  mHasMatch: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"vcs.projects" muss eine Liste von Zuordnungen sein');
    Exit;
  end;
  FSettings.VcsProjects := Copy(FText, ANode.Start + 1, ANode.Stop - ANode.Start);
  mMatches := TList<string>.Create;
  try
    for mIndex := 0 to ANode.Count - 1 do
    begin
      mMapping := ANode[mIndex];
      if mMapping.Kind <> TJsonKind.Object_ then
      begin
        ReportNode(mMapping, 'Eine Zuordnung ist ein Objekt mit "match", "provider" und "mainBranch"');
        Continue;
      end;
      mHasMatch := False;
      for mInner := 0 to mMapping.Count - 1 do
      begin
        mKey := mMapping.Keys[mInner];
        mValue := mMapping[mInner];
        if mKey = 'match' then
        begin
          if ExpectString(mValue, 'match', mText) and (Trim(mText) <> '') then
          begin
            mHasMatch := True;
            // Wie im Plugin (Atlas.Core.Projects.Matching): ohne Groß-/Kleinschreibung, „/“ wie „\“.
            mText := AnsiLowerCase(Trim(mText)).Replace('/', '\');
            while mText.EndsWith('\') and (Length(mText) > 2) do
              Delete(mText, Length(mText), 1);
            if mMatches.IndexOf(mText) >= 0 then
              ReportNode(mValue, 'Für diesen Pfad gibt es schon eine Zuordnung')
            else
              mMatches.Add(mText);
          end;
        end
        else if mKey = 'provider' then
        begin
          if ExpectString(mValue, 'provider', mText) and not MatchStr(mText, ['auto', 'git', 'svn', 'off']) then
            ReportNode(mValue, 'Erlaubt sind "auto", "git", "svn" und "off"');
        end
        else if mKey = 'mainBranch' then
        begin
          if ExpectString(mValue, 'mainBranch', mText) and (Trim(mText).IndexOfAny([' ', #9]) >= 0) then
            ReportNode(mValue, 'Ein Branch-Name enthält keine Leerzeichen');
        end
        else
          Report(mMapping.KeyStarts[mInner], mMapping.KeyStarts[mInner] + Length(mKey) + 2,
            Format('Unbekannte Angabe "%s" in einer Zuordnung', [mKey]), False);
      end;
      if not mHasMatch then
        ReportNode(mMapping, 'Zuordnung ohne "match" (Pfad einer .dproj, .groupproj oder eines Ordners)');
    end;
  finally
    mMatches.Free;
  end;
end;

procedure TValidator.ReadIssueProjects(ANode: TJsonNode);
var
  Index, Inner: Integer;
  Mapping, Value: TJsonNode;
  Key, Text: string;
  Matches: TList<string>;
  HasMatch, HasConnection: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"projects" muss eine Liste von Zuordnungen sein');
    Exit;
  end;
  FSettings.IssueProjects := Copy(FText, ANode.Start + 1, ANode.Stop - ANode.Start);
  Matches := TList<string>.Create;
  try
    for Index := 0 to ANode.Count - 1 do
    begin
      Mapping := ANode[Index];
      if Mapping.Kind <> TJsonKind.Object_ then
      begin
        ReportNode(Mapping, 'Eine Zuordnung ist ein Objekt mit "match", "connection" und "project"');
        Continue;
      end;
      HasMatch := False;
      HasConnection := False;
      for Inner := 0 to Mapping.Count - 1 do
      begin
        Key := Mapping.Keys[Inner];
        Value := Mapping[Inner];
        if Key = 'match' then
        begin
          if ExpectString(Value, 'match', Text) and (Trim(Text) <> '') then
          begin
            HasMatch := True;
            // Wie im Plugin: ohne Groß-/Kleinschreibung, „/“ wie „\“, ohne „\“ am Ende.
            Text := AnsiLowerCase(Trim(Text)).Replace('/', '\');
            while Text.EndsWith('\') and (Length(Text) > 2) do
              Delete(Text, Length(Text), 1);
            if Matches.IndexOf(Text) >= 0 then
              ReportNode(Value, 'Für diesen Pfad gibt es schon eine Zuordnung')
            else
              Matches.Add(Text);
          end;
        end
        else if Key = 'connection' then
          HasConnection := ExpectString(Value, 'connection', Text) and (Trim(Text) <> '')
        else if Key = 'project' then
          ExpectString(Value, 'project', Text)
        else
          Report(Mapping.KeyStarts[Inner], Mapping.KeyStarts[Inner] + Length(Key) + 2,
            Format('Unbekannte Angabe "%s" in einer Zuordnung', [Key]), False);
      end;
      if not HasMatch then
        ReportNode(Mapping, 'Zuordnung ohne "match" (Pfad einer .dproj, .groupproj oder eines Ordners)');
      if not HasConnection then
        ReportNode(Mapping, 'Zuordnung ohne "connection"');
    end;
  finally
    Matches.Free;
  end;
end;

procedure TValidator.ReadIssueQueries(ANode: TJsonNode);
var
  Index, Inner: Integer;
  Query, Value: TJsonNode;
  Key, Text: string;
  Names: TList<string>;
  HasName, HasQuery: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"queries" muss eine Liste von Abfragen sein');
    Exit;
  end;
  FSettings.IssueQueries := Copy(FText, ANode.Start + 1, ANode.Stop - ANode.Start);
  Names := TList<string>.Create;
  try
    for Index := 0 to ANode.Count - 1 do
    begin
      Query := ANode[Index];
      if Query.Kind <> TJsonKind.Object_ then
      begin
        ReportNode(Query, 'Eine Abfrage ist ein Objekt mit "name" und "query"');
        Continue;
      end;
      HasName := False;
      HasQuery := False;
      for Inner := 0 to Query.Count - 1 do
      begin
        Key := Query.Keys[Inner];
        Value := Query[Inner];
        if Key = 'name' then
        begin
          if ExpectString(Value, 'name', Text) and (Trim(Text) <> '') then
          begin
            HasName := True;
            // Die Klappliste unterscheidet Namen ohne Groß-/Kleinschreibung.
            if Names.IndexOf(AnsiLowerCase(Trim(Text))) >= 0 then
              ReportNode(Value, Format('Die Abfrage "%s" gibt es schon', [Trim(Text)]))
            else
              Names.Add(AnsiLowerCase(Trim(Text)));
          end;
        end
        else if Key = 'query' then
          HasQuery := ExpectString(Value, 'query', Text) and (Trim(Text) <> '')
        else if (Key = 'connection') or (Key = 'project') then
          ExpectString(Value, Key, Text)
        else
          Report(Query.KeyStarts[Inner], Query.KeyStarts[Inner] + Length(Key) + 2,
            Format('Unbekannte Angabe "%s" in einer Abfrage', [Key]), False);
      end;
      if not HasName then
        ReportNode(Query, 'Abfrage ohne "name"');
      if not HasQuery then
        ReportNode(Query, 'Abfrage ohne "query"');
    end;
  finally
    Names.Free;
  end;
end;

function TValidator.ParseRoot: TJsonNode;
begin
  try
    Result := TJsonTree.Parse(FText);
  except
    on E: EJsonTreeError do
    begin
      Report(E.Offset, E.Offset + 1, 'JSON-Fehler: ' + E.Message, True);
      Result := nil;
    end;
  end;
end;

procedure TValidator.Run;
var
  Root: TJsonNode;
  Index: Integer;
  Key: string;
  Value: TJsonNode;
  Text: string;
  Budget: Integer;
  ProfileNode: TJsonNode;
  Profile: TRuleProfile;
  ProfileNames: TArray<string>;
begin
  ProfileNode := nil;
  Root := ParseRoot;
  if Root = nil then
    Exit;
  try
    if Root.Kind <> TJsonKind.Object_ then
    begin
      ReportNode(Root, 'Die Konfiguration muss ein JSON-Objekt sein');
      Exit;
    end;
    for Index := 0 to Root.Count - 1 do
    begin
      Key := Root.Keys[Index];
      Value := Root[Index];
      if Key = 'delphiVersion' then
      begin
        if ExpectString(Value, Key, Text) then
          if Text = '' then
            FSettings.DelphiVersion := ''
          else if BdsVersionOf(Text) = '' then
            ReportNode(Value, 'Unbekannte Delphi-Version; erwartet z. B. "13" oder "37.0" für Delphi 13, "12" oder "23.0" für Delphi 12')
          else
          begin
            FSettings.DelphiVersion := BdsVersionOf(Text);
            FSettings.DelphiVersionRange := TTextRange.Create(PositionAt(Value.Start), PositionAt(Value.Stop));
          end;
      end
      else if Key = 'minDelphiVersion' then
      begin
        if ExpectString(Value, Key, Text) then
          if Text = '' then
            FSettings.MinDelphiVersion := ''
          else if BdsVersionOf(Text) = '' then
            ReportNode(Value, 'Unbekannte Delphi-Version; erwartet z. B. "12" oder "23.0" für Delphi 12, "11" oder "22.0" für Delphi 11')
          else
            FSettings.MinDelphiVersion := BdsVersionOf(Text);
      end
      else if Key = 'language' then
      begin
        if ExpectString(Value, Key, Text) then
          if (Text = 'de') or (Text = 'en') then
            FSettings.Language := Text
          else
            ReportNode(Value, 'Erlaubt sind "de" und "en"');
      end
      else if Key = 'encoding' then
      begin
        if ExpectString(Value, Key, Text) then
          if not TFileEncoding.ParseCodePage(Text, FSettings.DefaultEncoding) then
          begin
            FSettings.DefaultEncoding := TFileEncoding.Utf8CodePage;
            ReportNode(Value, 'Unbekannte Kodierung; erwartet "utf-8" oder eine ANSI-Codepage wie "1252" oder "windows-1250"');
          end;
      end
      else if Key = 'project' then
      begin
        if ExpectString(Value, Key, Text) then
          FSettings.Project := Text;
      end
      else if Key = 'config' then
      begin
        if ExpectString(Value, Key, Text) then
          FSettings.Config := Text;
      end
      else if Key = 'platform' then
      begin
        if ExpectString(Value, Key, Text) then
          FSettings.Platform := Text;
      end
      else if Key = 'rules' then
        ReadRules(Value)
      else if Key = 'profile' then
      begin
        ProfileNode := Value;
        ReadProfile(Value);
      end
      else if Key = 'profiles' then
        ReadProfiles(Value)
      else if Key = 'overrides' then
        ReadOverrides(Value)
      else if Key = 'excludeTests' then
        ExpectBoolean(Value, Key, FSettings.ExcludeTests)
      else if Key = 'testProfile' then
      begin
        if ExpectString(Value, Key, Text) then
          if FSettings.IsKnownProfile(Text) or (Text = '') then
            FSettings.TestProfile := Text
          else
            FTestProfileNode := Value;
      end
      else if Key = 'exclude' then
        ReadExclude(Value)
      else if Key = 'mcp' then
        ReadMcp(Value)
      else if Key = 'fix' then
        ReadFix(Value)
      else if Key = 'minConfidence' then
      begin
        if ExpectString(Value, Key, Text) then
          if TConfigurationParser.TryParseConfidence(Text, FSettings.MinConfidence) then
            FSettings.MinConfidenceGiven := True
          else
            ReportNode(Value, 'Erlaubt sind "low", "medium" und "high"');
      end
      else if Key = 'inlayHints' then
        ReadInlayHints(Value)
      else if Key = 'codeLens' then
        ReadCodeLens(Value)
      else if Key = 'references' then
        ReadReferences(Value)
      else if Key = 'navigation' then
        ReadNavigation(Value)
      else if Key = 'hints' then
        ReadHints(Value)
      else if Key = 'directives' then
        ReadDirectives(Value)
      else if Key = 'stringLiteral' then
        ReadStringLiteral(Value)
      else if Key = 'memberOrder' then
        ReadMemberOrder(Value)
      else if Key = 'testUnits' then
        ReadTestUnits(Value)
      else if Key = 'tests' then
        ReadTests(Value)
      else if Key = 'dfmPropertyRules' then
        ReadDfmPropertyRules(Value)
      else if Key = 'highlight' then
        ReadHighlight(Value)
      else if Key = 'compiler' then
        ReadCompiler(Value)
      else if Key = 'vcs' then
        ReadVcs(Value)
      else if Key = 'completion' then
        ReadCompletion(Value)
      else if Key = 'refactoring' then
        ReadRefactoring(Value)
      else if Key = 'diagnostics' then
        ReadDiagnostics(Value)
      else if Key = 'index' then
        ReadIndex(Value)
      else if Key = 'architecture' then
        ReadArchitecture(Value)
      else if Key = 'hotspots' then
        ReadHotspots(Value)
      else if Key = 'usesCommand' then
        ExpectBoolean(Value, Key, FSettings.UsesCommand)
      else if Key = 'completeBlocks' then
        ReadCompleteBlocks(Value)
      else if Key = 'experimental' then
        ReadExperimental(Value)
      else if Key = 'metrics' then
        ExpectBoolean(Value, Key, FSettings.Metrics)
      else if Key = 'slashCommands' then
        ReadSlashCommands(Value)
      else if Key = 'sortUses' then
        ReadSortUses(Value)
      else if Key = 'usesKeep' then
        ReadUsesKeep(Value)
      else if Key = 'deadCode' then
        ReadDeadCode(Value)
      else if Key = 'memoryBudgetMb' then
      begin
        if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Budget) and (Budget >= 0) then
          FSettings.MemoryBudgetMb := Budget
        else
          ReportNode(Value, '"memoryBudgetMb" muss eine ganze Zahl ab 0 sein');
      end
      else if Key = 'requestTimeoutMs' then
      begin
        if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Budget) and (Budget >= 1000) then
          FSettings.RequestTimeoutMs := Budget
        else
          ReportNode(Value, '"requestTimeoutMs" muss eine ganze Zahl ab 1000 sein');
      end
      else if Key = 'logLevel' then
      begin
        if ExpectString(Value, Key, Text) then
          if MatchStr(Text, ['debug', 'info', 'warning', 'error']) then
            FSettings.LogLevel := Text
          else
            ReportNode(Value, 'Erlaubt sind "debug", "info", "warning" und "error"');
      end
      else if Key = 'logFile' then
      begin
        if ExpectString(Value, Key, Text) then
          FSettings.LogFile := Text;
      end
      else if Key = 'traceFile' then
      begin
        if ExpectString(Value, Key, Text) then
          FSettings.TraceFile := Text;
      end
      else if Key = 'tasks' then
        ReadTasks(Value)
      else if Key = 'issues' then
        ReadIssues(Value)
      else if Key = 'format' then
      begin
        if Value.Kind = TJsonKind.Object_ then
        begin
          FSettings.Format := Copy(FText, Value.Start + 1, Value.Stop - Value.Start);
          ReadFormat(Value);
        end
        else
          ReportNode(Value, '"format" muss ein Objekt sein');
      end
      else if Key <> '$schema' then
        Report(Root.KeyStarts[Index], Root.KeyStarts[Index] + Length(Key) + 2,
          Format('Unbekannte Einstellung "%s"', [Key]), False);
    end;
    // Profilnamen erst prüfen, wenn auch "profiles" gelesen ist.
    ProfileNames := [FSettings.Profile, FSettings.CliProfile];
    for Text in ProfileNames do
      if (ProfileNode <> nil) and not FSettings.IsKnownProfile(Text) then
        ReportNode(ProfileNode, Format('Unbekanntes Profil "%s"; eingebaut: %s, sonst unter "profiles" anlegen',
          [Text, string.Join(', ', BuiltinProfileNames)]));
    if FTestProfileNode <> nil then
      if FSettings.IsKnownProfile(FTestProfileNode.Value) then
        FSettings.TestProfile := FTestProfileNode.Value
      else
        ReportNode(FTestProfileNode, Format('Unbekanntes Profil "%s"', [FTestProfileNode.Value]));
    for Profile in FSettings.Profiles do
      if not FSettings.IsKnownProfile(Profile.Extends) then
        ReportNode(Root, Format('Profil "%s" erweitert das unbekannte Profil "%s"', [Profile.Name, Profile.Extends]));
  finally
    Root.Free;
  end;
end;

{ TConfigurationParser }

class function TConfigurationParser.TryParseConfidence(const AValue: string;
  out AConfidence: TRuleConfidence): Boolean;
var
  Value: string;
begin
  Value := LowerCase(Trim(AValue));
  Result := True;
  if Value = 'low' then
    AConfidence := TRuleConfidence.Low
  else if Value = 'medium' then
    AConfidence := TRuleConfidence.Medium
  else if Value = 'high' then
    AConfidence := TRuleConfidence.High
  else
  begin
    AConfidence := TRuleConfidence.Medium;
    Result := False;
  end;
end;

class function TConfigurationParser.TryParseSeverity(const AValue: string; out ASeverity: TRuleSeverity): Boolean;
var
  Value: string;
begin
  Value := LowerCase(Trim(AValue));
  Result := True;
  if Value = 'off' then
    ASeverity := TRuleSeverity.Off
  else if Value = 'hint' then
    ASeverity := TRuleSeverity.Hint
  else if (Value = 'info') or (Value = 'information') then
    ASeverity := TRuleSeverity.Information
  else if Value = 'warning' then
    ASeverity := TRuleSeverity.Warning
  else if Value = 'error' then
    ASeverity := TRuleSeverity.Error
  else
  begin
    ASeverity := TRuleSeverity.Default;
    Result := False;
  end;
end;

// Schlüssel der obersten Ebene; leer bei Syntaxfehler.
function RootKeys(const AText: string): TArray<string>;
var
  Root: TJsonNode;
  Index: Integer;
begin
  Result := nil;
  try
    Root := TJsonTree.Parse(AText);
  except
    on EJsonTreeError do
      Exit;
  end;
  try
    if Root.Kind = TJsonKind.Object_ then
      for Index := 0 to Root.Count - 1 do
        Result := Result + [Root.Keys[Index]];
  finally
    Root.Free;
  end;
end;

/// <summary>Schlüssel des Objekts AKey unter der Wurzel; nil, wenn es fehlt oder kein Objekt ist.</summary>
function MemberKeys(const AText, AKey: string): TArray<string>;
var
  mRoot: TJsonNode;
  mIndex, mInner: Integer;
begin
  Result := nil;
  try
    mRoot := TJsonTree.Parse(AText);
  except
    on EJsonTreeError do
      Exit;
  end;
  try
    if mRoot.Kind = TJsonKind.Object_ then
      for mIndex := 0 to mRoot.Count - 1 do
        if (mRoot.Keys[mIndex] = AKey) and (mRoot[mIndex].Kind = TJsonKind.Object_) then
          for mInner := 0 to mRoot[mIndex].Count - 1 do
            Result := Result + [mRoot[mIndex].Keys[mInner]];
  finally
    mRoot.Free;
  end;
end;

function MergeRules(const AEditor, AFile: TArray<TRuleSetting>): TArray<TRuleSetting>;
var
  EditorRule, FileRule: TRuleSetting;
  Overridden: Boolean;
begin
  Result := nil;
  for EditorRule in AEditor do
  begin
    Overridden := False;
    for FileRule in AFile do
      if SameText(FileRule.Id, EditorRule.Id) then
        Overridden := True;
    if not Overridden then
      Result := Result + [EditorRule];
  end;
  Result := Result + AFile;
end;

function QuoteKey(const AKey: string): string;
var
  Ch: Char;
begin
  Result := '"';
  for Ch in AKey do
    if (Ch = '"') or (Ch = '\') then
      Result := Result + '\' + Ch
    else if Ord(Ch) < 32 then
      Result := Result + Format('\u%.4x', [Ord(Ch)])
    else
      Result := Result + Ch;
  Result := Result + '"';
end;

function NodeText(const AText: string; ANode: TJsonNode): string;
begin
  Result := Copy(AText, ANode.Start + 1, ANode.Stop - ANode.Start);
end;

function MergeObjects(const ALowerText: string; ALower: TJsonNode; const AUpperText: string;
  AUpper: TJsonNode): string;
var
  Index, Other: Integer;
  Parts: TArray<string>;
  Found: Boolean;
begin
  Parts := nil;
  for Index := 0 to ALower.Count - 1 do
  begin
    Found := False;
    for Other := 0 to AUpper.Count - 1 do
      if AUpper.Keys[Other] = ALower.Keys[Index] then
        Found := True;
    if not Found then
      Parts := Parts + [QuoteKey(ALower.Keys[Index]) + ': ' + NodeText(ALowerText, ALower[Index])];
  end;
  for Index := 0 to AUpper.Count - 1 do
  begin
    Other := ALower.Count - 1;
    while (Other >= 0) and (ALower.Keys[Other] <> AUpper.Keys[Index]) do
      Dec(Other);
    if (Other >= 0) and (ALower[Other].Kind = TJsonKind.Object_) and (AUpper[Index].Kind = TJsonKind.Object_) then
      Parts := Parts + [QuoteKey(AUpper.Keys[Index]) + ': ' +
        MergeObjects(ALowerText, ALower[Other], AUpperText, AUpper[Index])]
    else
      Parts := Parts + [QuoteKey(AUpper.Keys[Index]) + ': ' + NodeText(AUpperText, AUpper[Index])];
  end;
  Result := '{' + string.Join(', ', Parts) + '}';
end;

function ParseObject(const AText: string): TJsonNode;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  try
    Result := TJsonTree.Parse(AText);
  except
    on EJsonTreeError do
      Exit(nil);
  end;
  if Result.Kind <> TJsonKind.Object_ then
    FreeAndNil(Result);
end;

class function TConfigurationParser.MergeText(const ALower, AUpper: string): string;
var
  Lower, Upper: TJsonNode;
begin
  Lower := ParseObject(ALower);
  Upper := ParseObject(AUpper);
  try
    if Lower = nil then
    begin
      if Upper = nil then
        Exit('');
      Exit(AUpper);
    end;
    if Upper = nil then
      Exit(ALower);
    Result := MergeObjects(ALower, Lower, AUpper, Upper);
  finally
    Lower.Free;
    Upper.Free;
  end;
end;

class function TConfigurationParser.ParseLayered(const AEditorText, AFileText: string;
  out AIssues: TArray<TConfigurationIssue>): TServerSettings;
var
  FileSettings: TServerSettings;
  Ignored: TArray<TConfigurationIssue>;
  Key, Member: string;
begin
  AIssues := nil;
  if AFileText <> '' then
    FileSettings := Parse(AFileText, AIssues)
  else
    FileSettings := TServerSettings.Default;
  if Trim(AEditorText) = '' then
    Exit(FileSettings);
  // Unbekannte Schlüssel wie serverPath gehören dem Editor; ihre Meldungen entfallen.
  Result := Parse(AEditorText, Ignored);
  if AFileText = '' then
    Exit;
  for Key in RootKeys(AFileText) do
    if Key = 'delphiVersion' then
    begin
      Result.DelphiVersion := FileSettings.DelphiVersion;
      Result.DelphiVersionRange := FileSettings.DelphiVersionRange;
    end
    else if Key = 'minDelphiVersion' then
      Result.MinDelphiVersion := FileSettings.MinDelphiVersion
    else if Key = 'language' then
      Result.Language := FileSettings.Language
    else if Key = 'encoding' then
      Result.DefaultEncoding := FileSettings.DefaultEncoding
    else if Key = 'project' then
      Result.Project := FileSettings.Project
    else if Key = 'config' then
      Result.Config := FileSettings.Config
    else if Key = 'platform' then
      Result.Platform := FileSettings.Platform
    else if Key = 'rules' then
      Result.Rules := MergeRules(Result.Rules, FileSettings.Rules)
    else if Key = 'profile' then
    begin
      Result.Profile := FileSettings.Profile;
      Result.CliProfile := FileSettings.CliProfile;
    end
    else if Key = 'profiles' then
      Result.Profiles := FileSettings.Profiles
    else if Key = 'overrides' then
      Result.Overrides := FileSettings.Overrides
    else if Key = 'excludeTests' then
      Result.ExcludeTests := FileSettings.ExcludeTests
    else if Key = 'testProfile' then
      Result.TestProfile := FileSettings.TestProfile
    else if Key = 'exclude' then
      Result.Exclude := FileSettings.Exclude
    else if Key = 'mcp' then
    begin
      // Gemischtes Objekt (global und Projekt): nur die Glieder, die die Datei nennt, sonst überschriebe etwa
      // mcp.customPrompts aus atlas.json das globale mcp.prompts mit der Vorgabe (#1357).
      for Member in MemberKeys(AFileText, 'mcp') do
        if Member = 'disabledTools' then
          Result.McpDisabledTools := FileSettings.McpDisabledTools
        else if Member = 'globalSettings' then
          Result.McpGlobalSettings := FileSettings.McpGlobalSettings
        else if Member = 'prompts' then
          Result.McpPrompts := FileSettings.McpPrompts
        else if Member = 'promptLanguage' then
          Result.McpPromptLanguage := FileSettings.McpPromptLanguage
        else if Member = 'customPrompts' then
          Result.McpCustomPrompts := FileSettings.McpCustomPrompts;
    end
    else if Key = 'minConfidence' then
    begin
      Result.MinConfidence := FileSettings.MinConfidence;
      Result.MinConfidenceGiven := FileSettings.MinConfidenceGiven;
    end
    else if Key = 'fix' then
      Result.FixMinConfidence := FileSettings.FixMinConfidence
    else if Key = 'tasks' then
      Result.Tasks := FileSettings.Tasks
    else if Key = 'issues' then
    begin
      Result.IssueConnections := FileSettings.IssueConnections;
      Result.IssueProjects := FileSettings.IssueProjects;
      Result.IssueQueries := FileSettings.IssueQueries;
    end
    else if Key = 'format' then
    begin
      Result.Format := FileSettings.Format;
      Result.Formatting := FileSettings.Formatting;
    end
    else if Key = 'inlayHints' then
      Result.InlayHints := FileSettings.InlayHints
    else if Key = 'codeLens' then
      Result.CodeLens := FileSettings.CodeLens
    else if Key = 'references' then
      Result.References := FileSettings.References
    else if Key = 'navigation' then
      Result.Navigation := FileSettings.Navigation
    else if Key = 'hints' then
      Result.Hints := FileSettings.Hints
    else if Key = 'directives' then
      Result.Directives := FileSettings.Directives
    else if Key = 'stringLiteral' then
      Result.StringLiteral := FileSettings.StringLiteral
    else if Key = 'memberOrder' then
      Result.MemberOrder := FileSettings.MemberOrder
    else if Key = 'testUnits' then
      Result.TestUnits := FileSettings.TestUnits
    else if Key = 'tests' then
      Result.Tests := FileSettings.Tests
    else if Key = 'dfmPropertyRules' then
      Result.DfmPropertyRules := FileSettings.DfmPropertyRules
    else if Key = 'highlight' then
      Result.Highlight := FileSettings.Highlight
    else if Key = 'compiler' then
      Result.Compiler := FileSettings.Compiler
    else if Key = 'vcs' then
    begin
      Result.VcsProvider := FileSettings.VcsProvider;
      Result.VcsGitPath := FileSettings.VcsGitPath;
      Result.VcsSvnPath := FileSettings.VcsSvnPath;
      Result.VcsTimeoutSeconds := FileSettings.VcsTimeoutSeconds;
      Result.VcsProjects := FileSettings.VcsProjects;
    end
    else if Key = 'completion' then
      Result.Completion := FileSettings.Completion
    else if Key = 'refactoring' then
      Result.Refactoring := FileSettings.Refactoring
    else if Key = 'diagnostics' then
    begin
      Result.DiagnosticsLog := FileSettings.DiagnosticsLog;
      Result.DiagnosticsLogDays := FileSettings.DiagnosticsLogDays;
      Result.DiagnosticsLogMapFile := FileSettings.DiagnosticsLogMapFile;
      Result.DiagnosticsUsesCycleLive := FileSettings.DiagnosticsUsesCycleLive;
      Result.DiagnosticsUsesCycleImplementation := FileSettings.DiagnosticsUsesCycleImplementation;
    end
    else if Key = 'index' then
    begin
      Result.IndexProjectGroup := FileSettings.IndexProjectGroup;
      Result.IndexSearchPaths := FileSettings.IndexSearchPaths;
      Result.IndexLibraryPaths := FileSettings.IndexLibraryPaths;
      Result.IndexUsages := FileSettings.IndexUsages;
      Result.IndexExclude := FileSettings.IndexExclude;
      Result.IndexRemoveOrphans := FileSettings.IndexRemoveOrphans;
      Result.IndexCacheMaxAgeDays := FileSettings.IndexCacheMaxAgeDays;
      Result.IndexCacheMaxMb := FileSettings.IndexCacheMaxMb;
    end
    else if Key = 'architecture' then
    begin
      Result.ArchitectureEnabled := FileSettings.ArchitectureEnabled;
      Result.ArchitectureScope := FileSettings.ArchitectureScope;
      Result.ArchitectureIncludeLibraryUnits := FileSettings.ArchitectureIncludeLibraryUnits;
      Result.ArchitectureCentralUnits := FileSettings.ArchitectureCentralUnits;
      Result.ArchitectureExclude := FileSettings.ArchitectureExclude;
      Result.ArchitectureBaseline := FileSettings.ArchitectureBaseline;
      Result.ArchitectureFailOn := FileSettings.ArchitectureFailOn;
      Result.ArchitectureExplainAssignment := FileSettings.ArchitectureExplainAssignment;
      Result.ArchitectureGroupingResolution := FileSettings.ArchitectureGroupingResolution;
      Result.ArchitectureGroupingShowResolutionSlider := FileSettings.ArchitectureGroupingShowResolutionSlider;
      Result.ArchitectureGroupingMaxShare := FileSettings.ArchitectureGroupingMaxShare;
      Result.ArchitectureGroupingMinCohesion := FileSettings.ArchitectureGroupingMinCohesion;
      Result.ArchitectureGroupingFoundations := FileSettings.ArchitectureGroupingFoundations;
      Result.ArchitectureGroupingKeepPrevious := FileSettings.ArchitectureGroupingKeepPrevious;
    end
    else if Key = 'hotspots' then
    begin
      Result.HotspotsEnabled := FileSettings.HotspotsEnabled;
      Result.HotspotsMonths := FileSettings.HotspotsMonths;
      Result.HotspotsCouplingMinCommits := FileSettings.HotspotsCouplingMinCommits;
    end
    else if Key = 'usesCommand' then
      Result.UsesCommand := FileSettings.UsesCommand
    else if Key = 'completeBlocks' then
      Result.CompleteBlocksDocComment := FileSettings.CompleteBlocksDocComment
    else if Key = 'experimental' then
      Result.ExperimentalEnabled := FileSettings.ExperimentalEnabled
    else if Key = 'metrics' then
      Result.Metrics := FileSettings.Metrics
    else if Key = 'slashCommands' then
    begin
      Result.SlashCommands := FileSettings.SlashCommands;
      Result.SlashCommandsDisabled := FileSettings.SlashCommandsDisabled;
      Result.SlashHeaderTemplate := FileSettings.SlashHeaderTemplate;
      Result.SlashLogCall := FileSettings.SlashLogCall;
      Result.SlashComponentPalette := FileSettings.SlashComponentPalette;
      Result.SlashTodoOwner := FileSettings.SlashTodoOwner;
      Result.SlashTodoCategory := FileSettings.SlashTodoCategory;
      Result.SlashSortUsesRemoveUnused := FileSettings.SlashSortUsesRemoveUnused;
      Result.SlashEnumHelper := FileSettings.SlashEnumHelper;
      Result.SlashSetHelper := FileSettings.SlashSetHelper;
    end
    else if Key = 'sortUses' then
    begin
      Result.SortUses := FileSettings.SortUses;
      Result.SortUsesByNamespace := FileSettings.SortUsesByNamespace;
    end
    else if Key = 'usesKeep' then
      Result.UsesKeep := FileSettings.UsesKeep
    else if Key = 'deadCode' then
    begin
      Result.DeadCodeKeepAttributes := FileSettings.DeadCodeKeepAttributes;
      Result.DeadCodeKeepPatterns := FileSettings.DeadCodeKeepPatterns;
    end
    else if Key = 'memoryBudgetMb' then
      Result.MemoryBudgetMb := FileSettings.MemoryBudgetMb
    else if Key = 'requestTimeoutMs' then
      Result.RequestTimeoutMs := FileSettings.RequestTimeoutMs
    else if Key = 'logLevel' then
      Result.LogLevel := FileSettings.LogLevel
    else if Key = 'logFile' then
      Result.LogFile := FileSettings.LogFile
    else if Key = 'traceFile' then
      Result.TraceFile := FileSettings.TraceFile;
end;

class function TConfigurationParser.Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings;
var
  Validator: TValidator;
begin
  Validator := TValidator.Create(AText);
  try
    Validator.Run;
    Result := Validator.Settings;
    AIssues := Validator.Issues.ToArray;
  finally
    Validator.Free;
  end;
end;

end.
