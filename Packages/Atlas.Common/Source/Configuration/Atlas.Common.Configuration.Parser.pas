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
  BooleanRuleOptions: array[0..7] of string = ('allowCommented', 'requireElse', 'ignoreStrings', 'ignoreComments',
    'includeRecords', 'includeFormVariables', 'checkUses', 'ignoreOverrides');
  /// <summary>Optionen von Prüfregeln, die eine Liste von Texten sein müssen (#909).</summary>
  StringListRuleOptions: array[0..13] of string = ('countNames', 'mutatingMethods', 'ignoreMethods', 'ignoreTypes',
    'methods', 'allowIn', 'functions', 'sources', 'ignore', 'assertPatterns', 'selfRegistering', 'swallow', 'calls',
    'allowTables');
  /// <summary>Optionen von Prüfregeln, die eine Liste von Zahlen sein müssen (#937).</summary>
  NumberListRuleOptions: array[0..0] of string = ('allowed');
  /// <summary>Optionen von Prüfregeln, die ein Text sein müssen (#926).</summary>
  StringRuleOptions: array[0..4] of string = ('template', 'replacement', 'wrapper', 'okMarker', 'searchPaths');

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
    procedure ReadUsesKeep(ANode: TJsonNode);
    procedure ReadSlashCommands(ANode: TJsonNode);
    procedure ReadCompleteBlocks(ANode: TJsonNode);
    procedure ReadExperimental(ANode: TJsonNode);
    procedure ReadSortUses(ANode: TJsonNode);
    procedure ReadInlayHints(ANode: TJsonNode);
    procedure ReadCodeLens(ANode: TJsonNode);
    procedure CheckTodoKeywords(ANode: TJsonNode);
    procedure ReadHints(ANode: TJsonNode);
    procedure ReadDirectives(ANode: TJsonNode);
    procedure ReadStringLiteral(ANode: TJsonNode);
    procedure ReadMemberOrder(ANode: TJsonNode);
    procedure ReadTestUnits(ANode: TJsonNode);
    procedure ReadDfmPropertyRules(ANode: TJsonNode);
    function ReadDfmPropertyRule(ANode: TJsonNode; out ARule: TDfmPropertyRule): Boolean;
    procedure ReadHighlight(ANode: TJsonNode);
    procedure ReadRefactoring(ANode: TJsonNode);
    procedure ReadCompiler(ANode: TJsonNode);
    procedure ReadVcs(ANode: TJsonNode);
    procedure ReadCompletion(ANode: TJsonNode);
    procedure ReadDiagnostics(ANode: TJsonNode);
    procedure ReadIndex(ANode: TJsonNode);
    procedure ReadFormat(ANode: TJsonNode);
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
          // Kleinste gemeldete Record-Größe von managed-param-without-const (#975).
          else if (Value.Keys[Inner] = 'minRecordSize') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
            ReportNode(Value[Inner], '"minRecordSize" muss eine ganze Zahl ab 1 sein')
          // Kürzeste gemeldete Wartezeit von blocking-call-in-main-thread (#959).
          else if (Value.Keys[Inner] = 'maxSleepMs') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 0)) then
            ReportNode(Value[Inner], '"maxSleepMs" muss eine ganze Zahl ab 0 sein')
          // Marken der Regel todo-comment (#68); die Regel und get_todos lesen sie aus den Optionen.
          else if Value.Keys[Inner] = 'keywords' then
            CheckTodoKeywords(Value[Inner])
          // Schalter der Regeln (#909), z. B. allowCommented von empty-statement.
          else if (IndexStr(Value.Keys[Inner], BooleanRuleOptions) >= 0) and (Value[Inner].Kind <> TJsonKind.Boolean_) then
            ReportNode(Value[Inner], Format('"%s" muss true oder false sein', [Value.Keys[Inner]]))
          else if (IndexStr(Value.Keys[Inner], StringListRuleOptions) >= 0) and not IsStringList(Value[Inner]) then
            ReportNode(Value[Inner], Format('"%s" muss eine Liste von Texten sein', [Value.Keys[Inner]]))
          else if (IndexStr(Value.Keys[Inner], NumberListRuleOptions) >= 0) and not IsNumberList(Value[Inner]) then
            ReportNode(Value[Inner], Format('"%s" muss eine Liste von Zahlen sein', [Value.Keys[Inner]]))
          else if (IndexStr(Value.Keys[Inner], StringRuleOptions) >= 0) and (Value[Inner].Kind <> TJsonKind.String_) then
            ReportNode(Value[Inner], Format('"%s" muss ein Text sein', [Value.Keys[Inner]]))
          // Suchquelle von uses-unit-not-found (#1016).
          else if (Value.Keys[Inner] = 'searchPaths') and
            (IndexStr(Value[Inner].Value, ['project', 'atlas', 'both']) < 0) then
            ReportNode(Value[Inner], '"searchPaths" muss "project", "atlas" oder "both" sein')
          // Transaktionspaare von transaction-without-rollback (#965).
          else if (Value.Keys[Inner] = 'pairs') and (Rule.Id = 'transaction-without-rollback') then
          begin
            if not IsPairList(Value[Inner], ['start', 'commit', 'rollback']) then
              ReportNode(Value[Inner], '"pairs" muss eine Liste von Objekten mit "start", "commit" und "rollback" sein');
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
    else
      ReportNode(ANode[Index], Format('Unbekannte Einstellung "mcp.%s"', [ANode.Keys[Index]]));
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
  Index, Lines: Integer;
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
    else if Key = 'invertBoolean' then
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InvertBoolean)
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
var
  Index: Integer;
  Key, Text: string;
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

procedure TValidator.ReadFormat(ANode: TJsonNode);
var
  Index, Size: Integer;
  Key: string;
  Value: TJsonNode;
  Settings: TFormatStyle;

  procedure ReadBoolean(var ATarget: Boolean; AKey: TFormatKey);
  begin
    if ExpectBoolean(Value, Key, ATarget) then
      Include(Settings.Given, AKey);
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
  Settings := TFormatStyle.Default;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Value := ANode[Index];
    if Key = 'indentSize' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Size) and (Size >= 1) and (Size <= 16) then
      begin
        Settings.IndentSize := Size;
        Include(Settings.Given, TFormatKey.IndentSize);
      end
      else
        ReportNode(Value, '"indentSize" muss eine ganze Zahl von 1 bis 16 sein');
    end
    else if Key = 'useTabs' then
      ReadBoolean(Settings.UseTabs, TFormatKey.UseTabs)
    else if Key = 'trimTrailingWhitespace' then
      ReadBoolean(Settings.TrimTrailingWhitespace, TFormatKey.TrimTrailingWhitespace)
    else if Key = 'insertFinalNewline' then
      ReadBoolean(Settings.InsertFinalNewline, TFormatKey.InsertFinalNewline)
    else if Key = 'spaceAroundAssignment' then
      ReadBoolean(Settings.SpaceAroundAssignment, TFormatKey.SpaceAroundAssignment)
    else if Key = 'spaceAfterComma' then
      ReadBoolean(Settings.SpaceAfterComma, TFormatKey.SpaceAfterComma)
    else if Key = 'keywordCase' then
    begin
      if (Value.Kind = TJsonKind.String_) and (Value.Value = 'preserve') then
        Settings.KeywordCase := TKeywordCase.Preserve
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'lower') then
        Settings.KeywordCase := TKeywordCase.Lower
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'upper') then
        Settings.KeywordCase := TKeywordCase.Upper
      else
      begin
        ReportNode(Value, 'Erlaubt sind "preserve", "lower" und "upper"');
        Continue;
      end;
      Include(Settings.Given, TFormatKey.KeywordCase);
    end
    else if Key = 'endOfLine' then
    begin
      if (Value.Kind = TJsonKind.String_) and (Value.Value = 'lf') then
        Settings.EndOfLine := #10
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'crlf') then
        Settings.EndOfLine := #13#10
      else
      begin
        ReportNode(Value, 'Erlaubt sind "lf" und "crlf"');
        Continue;
      end;
      Include(Settings.Given, TFormatKey.EndOfLine);
    end
    else if Key = 'reindent' then
      ExpectBoolean(Value, Key, Settings.Reindent)
    else if Key = 'beginPlacement' then
      ReadPlacement(Settings.BeginPlacement)
    else if Key = 'elsePlacement' then
      ReadPlacement(Settings.ElsePlacement)
    else if Key = 'maxLineLength' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Size) and (Size >= 0) and (Size <= 1000) then
      begin
        Settings.MaxLineLength := Size;
        Include(Settings.Given, TFormatKey.MaxLineLength);
      end
      else
        ReportNode(Value, '"maxLineLength" muss eine ganze Zahl von 0 bis 1000 sein');
    end
    else if Key = 'alignAssignments' then
      ExpectBoolean(Value, Key, Settings.AlignAssignments)
    else if Key = 'alignDeclarations' then
      ExpectBoolean(Value, Key, Settings.AlignDeclarations)
    else if Key = 'alignComments' then
      ExpectBoolean(Value, Key, Settings.AlignComments)
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "format.%s"', [Key]), False);
  end;
  FSettings.Formatting := Settings;
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
  Key: string;
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
      Result.McpDisabledTools := FileSettings.McpDisabledTools;
      Result.McpGlobalSettings := FileSettings.McpGlobalSettings;
    end
    else if Key = 'minConfidence' then
    begin
      Result.MinConfidence := FileSettings.MinConfidence;
      Result.MinConfidenceGiven := FileSettings.MinConfidenceGiven;
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
    else if Key = 'dfmPropertyRules' then
      Result.DfmPropertyRules := FileSettings.DfmPropertyRules
    else if Key = 'highlight' then
      Result.Highlight := FileSettings.Highlight
    else if Key = 'compiler' then
      Result.Compiler := FileSettings.Compiler
    else if Key = 'vcs' then
      Result.VcsProvider := FileSettings.VcsProvider
    else if Key = 'completion' then
      Result.Completion := FileSettings.Completion
    else if Key = 'refactoring' then
      Result.Refactoring := FileSettings.Refactoring
    else if Key = 'diagnostics' then
    begin
      Result.DiagnosticsLog := FileSettings.DiagnosticsLog;
      Result.DiagnosticsLogDays := FileSettings.DiagnosticsLogDays;
      Result.DiagnosticsLogMapFile := FileSettings.DiagnosticsLogMapFile;
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
