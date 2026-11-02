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
    procedure ReadServer(ANode: TJsonNode);
    procedure ReadIndex(ANode: TJsonNode);
    procedure ReadArchitecture(ANode: TJsonNode);
    procedure ReadQuery(ANode: TJsonNode);
    procedure ReadRuleChecks(ANode: TJsonNode);
    procedure ReadQueries(ANode: TJsonNode);
    function ReadSavedQuery(ANode: TJsonNode; out AQuery: TSavedQuery): Boolean;
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
  begin
    AStop := AStart + 1;
  end;
  if AStop > Length(FText) then
  begin
    AStop := Length(FText);
  end;
  if AStart > AStop then
  begin
    AStart := AStop;
  end;
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
  begin
    AValue := ANode.Value;
  end
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
  begin
    FSettings.Rules := Rules;
  end;
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
  begin
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Item := ANode[Index];
    if Item.Kind <> TJsonKind.Object_ then
    begin
      Exit(False);
    end;
    Found := 0;
    for Inner := 0 to Item.Count - 1 do
    begin
      if (IndexStr(Item.Keys[Inner], AKeys) >= 0) and (Item[Inner].Kind = TJsonKind.String_) then
      begin
        Inc(Found);
      end;
    end;
    if Found <> Length(AKeys) then
    begin
      Exit(False);
    end;
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
  begin
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Item := ANode[Index];
    if Item.Kind = TJsonKind.String_ then
    begin
      Arrow := Pos('>', Item.Value);
      if (Arrow <= 1) or (Arrow >= Length(Item.Value)) then
      begin
        Exit(False);
      end;
      Continue;
    end;
    if Item.Kind <> TJsonKind.Object_ then
    begin
      Exit(False);
    end;
    Found := 0;
    for Inner := 0 to Item.Count - 1 do
    begin
      if ((Item.Keys[Inner] = 'open') or (Item.Keys[Inner] = 'close')) and (Item[Inner].Kind = TJsonKind.String_) then
      begin
        Inc(Found);
      end;
    end;
    if Found <> 2 then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Array, dessen Einträge alle Texte sind.</summary>
function IsNumberList(ANode: TJsonNode): Boolean;
var
  Index: Integer;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if Result then
  begin
    for Index := 0 to ANode.Count - 1 do
    begin
      if ANode[Index].Kind <> TJsonKind.Number then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function IsStringList(ANode: TJsonNode): Boolean;
var
  Index: Integer;
begin
  Result := ANode.Kind = TJsonKind.Array_;
  if Result then
  begin
    for Index := 0 to ANode.Count - 1 do
    begin
      if ANode[Index].Kind <> TJsonKind.String_ then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Liste von Texten, jeder aus AAllowed.</summary>
function IsStringListOf(ANode: TJsonNode; const AAllowed: array of string): Boolean;
var
  Index: Integer;
begin
  Result := IsStringList(ANode);
  if Result then
  begin
    for Index := 0 to ANode.Count - 1 do
    begin
      if IndexStr(ANode[Index].Value, AAllowed) < 0 then
      begin
        Exit(False);
      end;
    end;
  end;
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
        begin
          if Value.Keys[Inner] = 'severity' then
          begin
            if (Value[Inner].Kind <> TJsonKind.String_) or
              not TConfigurationParser.TryParseSeverity(Value[Inner].Value, Severity) then
            begin
              ReportNode(Value[Inner], 'Unbekannter Schweregrad; erlaubt: off, hint, info, warning, error');
            end
            else
            begin
              Rule.Severity := Severity;
            end;
          end
          // Grenzwert der Metrik-Regeln (#66); die Regel liest ihn aus den Optionen.
          else if (Value.Keys[Inner] = 'max') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
          begin
            ReportNode(Value[Inner], '"max" muss eine ganze Zahl ab 1 sein');
          end
          // Mindestzahl der Zeilen von commented-out-code (#942).
          else if (Value.Keys[Inner] = 'minLines') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
          begin
            ReportNode(Value[Inner], '"minLines" muss eine ganze Zahl ab 1 sein');
          end
          // Mindestzahl der Vergleiche von string-if-chain (#1066) bzw. der Zweige von prefer-case (#646).
          else if (Value.Keys[Inner] = 'min') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 2)) then
          begin
            ReportNode(Value[Inner], '"min" muss eine ganze Zahl ab 2 sein');
          end
          // Kleinste gemeldete Record-Größe von managed-param-without-const (#975).
          else if (Value.Keys[Inner] = 'minRecordSize') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
          begin
            ReportNode(Value[Inner], '"minRecordSize" muss eine ganze Zahl ab 1 sein');
          end
          // Kürzeste gemeldete Wartezeit von blocking-call-in-main-thread (#959).
          else if (Value.Keys[Inner] = 'maxSleepMs') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 0)) then
          begin
            ReportNode(Value[Inner], '"maxSleepMs" muss eine ganze Zahl ab 0 sein');
          end
          // Höchstlänge des vertauschten Literals von pos-arguments-swapped (#1045).
          else if (Value.Keys[Inner] = 'maxLiteralLength') and not ((Value[Inner].Kind = TJsonKind.Number) and
            TryStrToInt(Value[Inner].Value, Limit) and (Limit >= 1)) then
          begin
            ReportNode(Value[Inner], '"maxLiteralLength" muss eine ganze Zahl ab 1 sein');
          end
          // Marken der Regel todo-comment (#68); die Regel und get_todos lesen sie aus den Optionen.
          else if Value.Keys[Inner] = 'keywords' then
          begin
            CheckTodoKeywords(Value[Inner]);
          end
          // Schalter der Regeln (#909), z. B. allowCommented von empty-statement.
          else if (IndexStr(Value.Keys[Inner], BooleanRuleOptions) >= 0) and (Value[Inner].Kind <> TJsonKind.Boolean_) then
          begin
            ReportNode(Value[Inner], Format('"%s" muss true oder false sein', [Value.Keys[Inner]]));
          end
          else if (IndexStr(Value.Keys[Inner], StringListRuleOptions) >= 0) and not IsStringList(Value[Inner]) then
          begin
            ReportNode(Value[Inner], Format('"%s" muss eine Liste von Texten sein', [Value.Keys[Inner]]));
          end
          // allowed von inherited-wrong-method (#1050) sind Paare "Methode>geerbte Methode", sonst Zahlen.
          else if (Value.Keys[Inner] = 'allowed') and (Rule.Id = 'inherited-wrong-method') then
          begin
            if not IsStringList(Value[Inner]) then
            begin
              ReportNode(Value[Inner], '"allowed" muss eine Liste von Texten sein');
            end;
          end
          else if (IndexStr(Value.Keys[Inner], NumberListRuleOptions) >= 0) and not IsNumberList(Value[Inner]) then
          begin
            ReportNode(Value[Inner], Format('"%s" muss eine Liste von Zahlen sein', [Value.Keys[Inner]]));
          end
          else if (IndexStr(Value.Keys[Inner], StringRuleOptions) >= 0) and (Value[Inner].Kind <> TJsonKind.String_) then
          begin
            ReportNode(Value[Inner], Format('"%s" muss ein Text sein', [Value.Keys[Inner]]));
          end
          // Stufe T der Gruppe „Compiler vorab“ (#1024).
          else if (Value.Keys[Inner] = 'typeLevel') and
            ((Value[Inner].Kind <> TJsonKind.String_) or (IndexStr(Value[Inner].Value, ['certain', 'off']) < 0)) then
          begin
            ReportNode(Value[Inner], '"typeLevel" muss "certain" oder "off" sein');
          end
          // Arten von deprecated-symbol (#1018).
          else if (Value.Keys[Inner] = 'kinds') and (Rule.Id = 'deprecated-symbol') and
            not IsStringListOf(Value[Inner], DeprecationKinds) then
          begin
            ReportNode(Value[Inner], '"kinds" darf nur "deprecated", "experimental", "platform" und "library" enthalten');
          end
          // Verbotene Symbole von forbidden-symbol (#1133).
          else if (Value.Keys[Inner] = 'symbols') and (Rule.Id = 'forbidden-symbol') then
          begin
            CheckForbiddenSymbols(Value[Inner]);
          end
          // Suchquelle von uses-unit-not-found (#1016).
          else if (Value.Keys[Inner] = 'searchPaths') and
            (IndexStr(Value[Inner].Value, ['project', 'atlas', 'both']) < 0) then
          begin
            ReportNode(Value[Inner], '"searchPaths" muss "project", "atlas" oder "both" sein');
          end
          // Kodierung der Korrektur von load-without-encoding (#1061).
          else if (Value.Keys[Inner] = 'defaultEncoding') and
            (IndexText(Value[Inner].Value, ['UTF8', 'Unicode', 'BigEndianUnicode', 'ANSI', 'ASCII', 'UTF7',
            'Default']) < 0) then
          begin
            ReportNode(Value[Inner],
              '"defaultEncoding" muss UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 oder Default sein');
          end
          // Transaktionspaare von transaction-without-rollback (#965).
          else if (Value.Keys[Inner] = 'pairs') and (Rule.Id = 'transaction-without-rollback') then
          begin
            if not IsPairList(Value[Inner], ['start', 'commit', 'rollback']) then
            begin
              ReportNode(Value[Inner], '"pairs" muss eine Liste von Objekten mit "start", "commit" und "rollback" sein');
            end;
          end
          // Paare von handle-leak (#1088): auch als Text "Öffnen>Schließen".
          else if (Value.Keys[Inner] = 'pairs') and (Rule.Id = 'handle-leak') then
          begin
            if not IsArrowPairList(Value[Inner]) then
            begin
              ReportNode(Value[Inner], '"pairs" muss eine Liste von Texten "Öffnen>Schließen" oder von Objekten mit ' +
                '"open" und "close" sein');
            end;
          end
          else if (Value.Keys[Inner] = 'pairs') and not IsPairList(Value[Inner], ['open', 'close']) then
          begin
            ReportNode(Value[Inner], '"pairs" muss eine Liste von Objekten mit "open" und "close" sein');
          end
          // Paare von ota-notifier-not-removed (#944).
          else if (Value.Keys[Inner] = 'registerPairs') and not IsPairList(Value[Inner], ['open', 'close']) then
          begin
            ReportNode(Value[Inner], '"registerPairs" muss eine Liste von Objekten mit "open" und "close" sein');
          end;
        end;
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
  begin
    if ExpectString(ANode[Index], AName, Value) then
    begin
      AItems := AItems + [Value];
    end;
  end;
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
  begin
    if ANode.Keys[Index] = 'editor' then
    begin
      if ExpectString(ANode[Index], 'profile.editor', Text) then
      begin
        FSettings.Profile := Text;
      end;
    end
    else if ANode.Keys[Index] = 'cli' then
    begin
      if ExpectString(ANode[Index], 'profile.cli', Text) then
      begin
        FSettings.CliProfile := Text;
      end;
    end
    else
    begin
      ReportNode(ANode[Index], Format('Unbekannter Schlüssel "%s"; erlaubt: editor, cli', [ANode.Keys[Index]]));
    end;
  end;
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
      begin
        ExpectString(Value[Inner], 'extends', Profile.Extends);
      end
      else if Key = 'categories' then
      begin
        ParseStrings(Value[Inner], 'categories', Profile.Categories);
      end
      else if Key = 'rules' then
      begin
        ParseRules(Value[Inner], 'rules', Profile.Rules);
      end
      else
      begin
        ReportNode(Value[Inner], Format('Unbekannter Schlüssel "%s"; erlaubt: extends, categories, rules', [Key]));
      end;
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
      begin
        ParseStrings(Value[Inner], 'files', Item.Files);
      end
      else if Key = 'rules' then
      begin
        ParseRules(Value[Inner], 'rules', Item.Rules);
      end
      else
      begin
        ReportNode(Value[Inner], Format('Unbekannter Schlüssel "%s"; erlaubt: files, rules', [Key]));
      end;
    end;
    if Item.Files = nil then
    begin
      ReportNode(Value, 'Pfadregel ohne "files"');
    end
    else
    begin
      FSettings.Overrides := FSettings.Overrides + [Item];
    end;
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
  begin
    if ExpectString(ANode[Index], 'usesKeep', Value) then
    begin
      FSettings.UsesKeep := FSettings.UsesKeep + [Value];
    end;
  end;
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
      begin
        if ExpectString(ANode[Index][Item], 'deadCode.' + Key, Value) then
        begin
          Values := Values + [Value];
        end;
      end;
      if Key = 'keepAttributes' then
      begin
        FSettings.DeadCodeKeepAttributes := Values;
      end
      else
      begin
        FSettings.DeadCodeKeepPatterns := Values;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "deadCode.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.SlashCommands);
    end
    else if Key = 'disabled' then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[Index], '"slashCommands.disabled" muss eine Liste von Befehlsnamen sein');
        Continue;
      end;
      FSettings.SlashCommandsDisabled := nil;
      for Item := 0 to ANode[Index].Count - 1 do
      begin
        if ExpectString(ANode[Index][Item], 'disabled', Value) then
        begin
          FSettings.SlashCommandsDisabled := FSettings.SlashCommandsDisabled + [Value];
        end;
      end;
    end
    else if Key = 'headerTemplate' then
    begin
      ExpectString(ANode[Index], 'headerTemplate', FSettings.SlashHeaderTemplate);
    end
    else if Key = 'logCall' then
    begin
      ExpectString(ANode[Index], 'logCall', FSettings.SlashLogCall);
    end
    else if Key = 'componentPalette' then
    begin
      ExpectString(ANode[Index], 'componentPalette', FSettings.SlashComponentPalette);
    end
    else if Key = 'todoOwner' then
    begin
      ExpectString(ANode[Index], 'todoOwner', FSettings.SlashTodoOwner);
    end
    else if Key = 'todoCategory' then
    begin
      ExpectString(ANode[Index], 'todoCategory', FSettings.SlashTodoCategory);
    end
    else if Key = 'sortUsesRemoveUnused' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.SlashSortUsesRemoveUnused);
    end
    else if Key = 'enumHelper' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.SlashEnumHelper);
    end
    else if Key = 'setHelper' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.SlashSetHelper);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "slashCommands.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.CompleteBlocksDocComment);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "completeBlocks.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.ExperimentalEnabled);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "experimental.%s"', [Key]), False);
    end;
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
  begin
    ReportNode(ANode, 'Erlaubt sind true, false, "alphabetic" und "namespace"');
  end;
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
    begin
      if ExpectString(ANode[Index], 'exclude', Value) then
      begin
        Items.Add(Value);
      end;
    end;
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
  begin
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
        begin
          if ExpectString(ANode[Index][Item], 'disabledTools', Value) then
          begin
            Items.Add(Value);
          end;
        end;
        FSettings.McpDisabledTools := Items.ToArray;
      finally
        Items.Free;
      end;
    end
    else if ANode.Keys[Index] = 'globalSettings' then
    begin
      ExpectBoolean(ANode[Index], 'globalSettings', FSettings.McpGlobalSettings);
    end
    else if ANode.Keys[Index] = 'prompts' then
    begin
      ExpectBoolean(ANode[Index], 'prompts', FSettings.McpPrompts);
    end
    else if ANode.Keys[Index] = 'promptLanguage' then
    begin
      if ExpectString(ANode[Index], 'promptLanguage', Value) then
      begin
        if (Value = 'de') or (Value = 'en') then
        begin
          FSettings.McpPromptLanguage := Value;
        end
        else
        begin
          ReportNode(ANode[Index], '"mcp.promptLanguage" ist "de" oder "en"');
        end;
      end;
    end
    else if ANode.Keys[Index] = 'customPrompts' then
    begin
      ReadMcpCustomPrompts(ANode[Index]);
    end
    else
    begin
      ReportNode(ANode[Index], Format('Unbekannte Einstellung "mcp.%s"', [ANode.Keys[Index]]));
    end;
  end;
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
  begin
    if ANode.Keys[mIndex] = 'minConfidence' then
    begin
      // Sammelkorrekturen (#1352) nie unter mittlerer Konfidenz.
      if ExpectString(ANode[mIndex], 'fix.minConfidence', mText) then
      begin
        if TConfigurationParser.TryParseConfidence(mText, mConfidence) and (mConfidence <> TRuleConfidence.Low) then
        begin
          FSettings.FixMinConfidence := mConfidence;
        end
        else
        begin
          ReportNode(ANode[mIndex], 'Erlaubt sind "medium" und "high"');
        end;
      end;
    end
    else
    begin
      ReportNode(ANode[mIndex], Format('Unbekannte Einstellung "fix.%s"', [ANode.Keys[mIndex]]));
    end;
  end;
end;

/// <summary>Name eines Prompts oder Arguments: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-".</summary>
function IsPromptName(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AName <> '') and CharInSet(AName[1], ['A'..'Z', 'a'..'z']);
  for mIndex := 2 to Length(AName) do
  begin
    if not CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
    begin
      Exit(False);
    end;
  end;
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
    begin
      if ReadMcpCustomPrompt(ANode[mIndex], mPrompt) then
      begin
        if mNames.IndexOf(LowerCase(mPrompt.Name)) >= 0 then
        begin
          ReportNode(ANode[mIndex], Format('Den Prompt "%s" gibt es schon', [mPrompt.Name]));
        end
        else
        begin
          mNames.Add(LowerCase(mPrompt.Name));
          FSettings.McpCustomPrompts := FSettings.McpCustomPrompts + [mPrompt];
        end;
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
      begin
        ReportNode(ANode[mIndex], 'Name eines Arguments: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-"');
      end;
    end
    else if mKey = 'description' then
    begin
      ExpectString(ANode[mIndex], mKey, AArgument.Description);
    end
    else if mKey = 'required' then
    begin
      ExpectBoolean(ANode[mIndex], mKey, AArgument.Required);
    end
    else
    begin
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Angabe "%s" in einem Argument', [mKey]), False);
    end;
  end;
  Result := IsPromptName(AArgument.Name);
  if AArgument.Name = '' then
  begin
    ReportNode(ANode, 'Argument ohne "name"');
  end;
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
      begin
        ReportNode(ANode[mIndex], 'Name eines Prompts: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-"');
      end;
    end
    else if mKey = 'description' then
    begin
      ExpectString(ANode[mIndex], mKey, APrompt.Description);
    end
    else if mKey = 'text' then
    begin
      if ExpectString(ANode[mIndex], mKey, APrompt.Text) then
      begin
        mTextNode := ANode[mIndex];
      end;
    end
    else if mKey = 'arguments' then
    begin
      if ANode[mIndex].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[mIndex], '"arguments" muss eine Liste von Argumenten sein');
      end
      else
      begin
        for mItem := 0 to ANode[mIndex].Count - 1 do
        begin
          if ReadMcpPromptArgument(ANode[mIndex][mItem], mArgument) then
          begin
            APrompt.Arguments := APrompt.Arguments + [mArgument];
          end;
        end;
      end;
    end
    else if mKey = 'include' then
    begin
      if ANode[mIndex].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[mIndex], '"include" muss eine Liste sein, z. B. ["diagnostics", "metrics"]');
      end
      else
      begin
        for mItem := 0 to ANode[mIndex].Count - 1 do
        begin
          if ExpectString(ANode[mIndex][mItem], 'include', mValue) then
          begin
            if TMcpCustomPrompt.IsKnownInclude(mValue) then
            begin
              APrompt.Include := APrompt.Include + [mValue];
            end
            else
            begin
              ReportNode(ANode[mIndex][mItem], Format('Unbekannter Inhalt "%s"; erlaubt: %s',
                [mValue, string.Join(', ', TMcpCustomPrompt.KnownIncludes)]));
            end;
          end;
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Angabe "%s" in einem Prompt', [mKey]), False);
    end;
  end;
  if APrompt.Name = '' then
  begin
    ReportNode(ANode, 'Prompt ohne "name"');
  end;
  if Trim(APrompt.Text) = '' then
  begin
    ReportNode(ANode, 'Prompt ohne "text"');
  end;
  // Platzhalter ohne passendes Argument bleiben stehen; ein Hinweis, damit der Tippfehler auffällt.
  if mTextNode <> nil then
  begin
    mStart := Pos('{', APrompt.Text);
    while mStart > 0 do
    begin
      mStop := Pos('}', APrompt.Text, mStart + 1);
      if mStop = 0 then
      begin
        Break;
      end;
      mPlaceholder := Copy(APrompt.Text, mStart + 1, mStop - mStart - 1);
      if IsPromptName(mPlaceholder) then
      begin
        mKnown := False;
        for mArgument in APrompt.Arguments do
        begin
          if mArgument.Name = mPlaceholder then
          begin
            mKnown := True;
          end;
        end;
        if not mKnown then
        begin
          Report(mTextNode.Start, mTextNode.Stop, Format('Platzhalter "{%s}" hat kein Argument', [mPlaceholder]),
            False);
        end;
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
  begin
    AValue := ANode.Value = 'true';
  end
  else
  begin
    ReportNode(ANode, Format('"%s" muss true oder false sein', [AName]));
  end;
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
    begin
      ExpectBoolean(Value, Key, FSettings.InlayHints.ParameterNames);
    end
    else if Key = 'inferredTypes' then
    begin
      ExpectBoolean(Value, Key, FSettings.InlayHints.InferredTypes);
    end
    else if Key = 'endMarkers' then
    begin
      ExpectBoolean(Value, Key, FSettings.InlayHints.EndMarkers);
    end
    else if Key = 'includeDefines' then
    begin
      ExpectBoolean(Value, Key, FSettings.InlayHints.IncludeDefines);
    end
    else if Key = 'controlChars' then
    begin
      ExpectBoolean(Value, Key, FSettings.InlayHints.ControlChars);
    end
    else if Key = 'endMarkerMinLines' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Lines) and (Lines >= 1) then
      begin
        FSettings.InlayHints.EndMarkerMinLines := Lines;
      end
      else
      begin
        ReportNode(Value, '"endMarkerMinLines" muss eine ganze Zahl ab 1 sein');
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "inlayHints.%s"', [Key]), False);
    end;
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
    begin
      Keyword := Trim(ANode[Index].Value);
    end;
    Valid := (Keyword <> '') and not SameText(Keyword, 'DONE');
    for Position := 1 to Length(Keyword) do
    begin
      if not CharInSet(Keyword[Position], ['A'..'Z', 'a'..'z']) then
      begin
        Valid := False;
      end;
    end;
    if not Valid then
    begin
      ReportNode(ANode[Index], 'Eine Marke besteht nur aus Buchstaben und ist nicht DONE, z. B. "HACK"');
    end;
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
        begin
          ReportNode(mValue, '"name" muss ein nicht leerer Text sein');
        end;
      end
      else if mKey = 'kind' then
      begin
        if (mValue.Kind <> TJsonKind.String_) or (IndexText(mValue.Value, ForbiddenSymbolKinds) < 0) then
        begin
          ReportNode(mValue, '"kind" muss routine, type, constant, field, property, enumValue oder identifier sein');
        end;
      end
      else if (mKey = 'message') or (mKey = 'replacement') then
      begin
        if mValue.Kind <> TJsonKind.String_ then
        begin
          ReportNode(mValue, Format('"%s" muss ein Text sein', [mKey]));
        end;
      end
      else if mKey = 'severity' then
      begin
        if (mValue.Kind <> TJsonKind.String_) or not TConfigurationParser.TryParseSeverity(mValue.Value, mSeverity) then
        begin
          ReportNode(mValue, 'Unbekannter Schweregrad; erlaubt: off, hint, info, warning, error');
        end;
      end
      else if (mKey = 'units') or (mKey = 'firstArgument') or (mKey = 'allowFirstArgument') then
      begin
        if not IsStringList(mValue) then
        begin
          ReportNode(mValue, Format('"%s" muss eine Liste von Texten sein', [mKey]));
        end;
      end
      else
      begin
        ReportNode(mValue, Format('Unbekannter Schlüssel "%s"; erlaubt: name, kind, message, replacement, ' +
          'severity, units, firstArgument, allowFirstArgument', [mKey]));
      end;
    end;
    if not mHasName then
    begin
      ReportNode(mItem, 'Eintrag von "symbols" ohne "name"');
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.CodeLens.Metrics);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "codeLens.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.References.Inferred);
    end
    else if Key = 'textMatches' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.References.TextMatches);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "references.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(Value, Key, FSettings.Navigation.SymbolPath);
    end
    else if Key = 'impact' then
    begin
      ExpectBoolean(Value, Key, FSettings.Navigation.Impact);
    end
    else if Key = 'impactDepth' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Depth) and (Depth >= 1) and (Depth <= 5) then
      begin
        FSettings.Navigation.ImpactDepth := Depth;
      end
      else
      begin
        ReportNode(Value, '"impactDepth" muss eine ganze Zahl von 1 bis 5 sein');
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "navigation.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Directives.Completion);
    end
    else if Key = 'hover' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Directives.Hover);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "directives.%s"', [Key]), False);
    end;
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
      begin
        if (Text = THintSettings.ExpandCollapsed) or (Text = THintSettings.ExpandLast) or
          (Text = THintSettings.ExpandExpanded) then
        begin
          FSettings.Hints.XmlDocExpand := Text;
          ExpandSet := True;
        end
        else
        begin
          ReportNode(Value, '"xmlDocExpand" muss "collapsed", "last" oder "expanded" sein');
        end;
      end;
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
        begin
          if Full then
          begin
            FSettings.Hints.XmlDocExpand := THintSettings.ExpandExpanded;
          end
          else
          begin
            FSettings.Hints.XmlDocExpand := THintSettings.ExpandCollapsed;
          end;
        end;
      end;
    end
    else if Key = 'xmlDocMaxLines' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Lines) and (Lines >= 0) and
        (Lines <= THintSettings.MaxXmlDocLines) then
      begin
        FSettings.Hints.XmlDocMaxLines := Lines;
      end
      else
      begin
        ReportNode(Value, Format('"xmlDocMaxLines" muss eine ganze Zahl von 0 bis %d sein',
          [THintSettings.MaxXmlDocLines]));
      end;
    end
    else if Key = 'publishedMembers' then
    begin
      ExpectBoolean(Value, Key, FSettings.Hints.PublishedMembers);
    end
    else if Key = 'rationale' then
    begin
      ExpectBoolean(Value, Key, FSettings.Hints.Rationale);
    end
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
      begin
        if ExpectString(Value[Item], 'rationaleMarkers', Text) then
        begin
          if Trim(Text) = '' then
          begin
            ReportNode(Value[Item], '"rationaleMarkers" darf keine leere Marke enthalten');
          end
          else
          begin
            FSettings.Hints.RationaleMarkers := FSettings.Hints.RationaleMarkers + [Trim(Text)];
          end;
        end;
      end;
    end
    else if Key = 'adrFolder' then
    begin
      if ExpectString(Value, Key, Text) then
      begin
        FSettings.Hints.AdrFolder := Trim(Text);
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "hints.%s"', [Key]), False);
    end;
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
        begin
          if Text = Styles[Style] then
          begin
            FSettings.StringLiteral.Style := Style;
            Found := True;
          end;
        end;
        if not Found then
        begin
          ReportNode(Value, 'Erlaubt sind "auto", "multiline" und "concat"');
        end;
      end;
    end
    else if Key = 'lineBreak' then
    begin
      if ExpectString(Value, Key, Text) then
      begin
        Found := False;
        for Break_ := Low(TStringLiteralBreak) to High(TStringLiteralBreak) do
        begin
          if Text = Breaks[Break_] then
          begin
            FSettings.StringLiteral.LineBreak := Break_;
            Found := True;
          end;
        end;
        if not Found then
        begin
          ReportNode(Value, 'Erlaubt sind "sLineBreak", "#13#10", "#10", "space" und "none"');
        end;
      end;
    end
    else if Key = 'maxLineLength' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Length_) and (Length_ >= 0) then
      begin
        FSettings.StringLiteral.MaxLineLength := Length_;
      end
      else
      begin
        ReportNode(Value, '"maxLineLength" muss eine ganze Zahl ab 0 sein');
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "stringLiteral.%s"', [Key]), False);
    end;
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
  begin
    if ReadDfmPropertyRule(ANode[Index], Rule) then
    begin
      FSettings.DfmPropertyRules := FSettings.DfmPropertyRules + [Rule];
    end;
  end;
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
    begin
      ExpectString(Value, Key, ARule.Value);
    end
    else if Key = 'message' then
    begin
      ExpectString(Value, Key, ARule.Message);
    end
    else if Key = 'condition' then
    begin
      if not ExpectString(Value, Key, Text) then
      begin
        Continue;
      end;
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
      begin
        ReportNode(Value, Format('Unbekannter Schweregrad "%s"; erlaubt: off, hint, info, warning, error', [Text]));
      end;
    end
    else if Key = 'includeDescendants' then
    begin
      ExpectBoolean(Value, Key, ARule.IncludeDescendants);
    end
    else if Key = 'fix' then
    begin
      if not ExpectString(Value, Key, Text) then
      begin
        Continue;
      end;
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
      begin
        if ExpectString(Value[Item], 'exclude', Text) then
        begin
          ARule.Exclude := ARule.Exclude + [Text];
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Angabe "%s" in einer Eigenschaftsregel', [Key]), False);
    end;
  end;
  Result := (ARule.ClassName <> '') and (ARule.PropertyPath <> '');
  if not Result then
  begin
    ReportNode(ANode, 'Eine Eigenschaftsregel braucht "class" und "property"');
  end
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
      begin
        if ExpectString(Value[Item], Key, Text) then
        begin
          if ((Key = 'sections') and not MatchText(Text, SectionNames)) or
            ((Key = 'members') and not MatchText(Text, MemberNames)) then
          begin
            ReportNode(Value[Item], Format('Unbekannter Eintrag "%s" in "memberOrder.%s"', [Text, Key]));
          end
          else
          begin
            Names := Names + [LowerCase(Text)];
          end;
        end;
      end;
      if Key = 'sections' then
      begin
        FSettings.MemberOrder.Sections := Names;
      end
      else
      begin
        FSettings.MemberOrder.Members := Names;
      end;
    end
    else if Key = 'sortFields' then
    begin
      ExpectBoolean(Value, Key, FSettings.MemberOrder.SortFields);
    end
    else if Key = 'sortPublished' then
    begin
      ExpectBoolean(Value, Key, FSettings.MemberOrder.SortPublished);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "memberOrder.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(mValue, mKey, FSettings.Tests.Affected);
    end
    else if mKey = 'affectedDepth' then
    begin
      if (mValue.Kind = TJsonKind.Number) and TryStrToInt(mValue.Value, mDepth) and
        (mDepth >= TTestsSettings.MinAffectedDepth) and (mDepth <= TTestsSettings.MaxAffectedDepth) then
      begin
        FSettings.Tests.AffectedDepth := mDepth;
      end
      else
      begin
        ReportNode(mValue, '"affectedDepth" muss eine ganze Zahl von 1 bis 5 sein');
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Einstellung "tests.%s"', [mKey]), False);
    end;
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
        begin
          ReportNode(Value, '"testUnits.pattern" muss {unit} enthalten');
        end
        else
        begin
          FSettings.TestUnits.Pattern := Text;
        end;
      end;
    end
    else if Key = 'folder' then
    begin
      if ExpectString(Value, Key, Text) then
      begin
        FSettings.TestUnits.Folder := Text;
      end;
    end
    else if Key = 'project' then
    begin
      if ExpectString(Value, Key, Text) then
      begin
        if (Text <> '') and not MatchText(ExtractFileExt(Text), ['.dproj', '.dpr']) then
        begin
          ReportNode(Value, '"testUnits.project" muss eine .dproj oder .dpr sein');
        end
        else
        begin
          FSettings.TestUnits.Project := Text;
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "testUnits.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(Node, Key, FSettings.Highlight.BlockPairs);
    end
    else if Key = 'directives' then
    begin
      ExpectBoolean(Node, Key, FSettings.Highlight.Directives);
    end
    else if Key = 'exitPoints' then
    begin
      ExpectBoolean(Node, Key, FSettings.Highlight.ExitPoints);
    end
    else if Key = 'exitKeywords' then
    begin
      if Node.Kind <> TJsonKind.Array_ then
      begin
        ReportNode(Node, '"exitKeywords" muss eine Liste von Namen sein');
        Continue;
      end;
      FSettings.Highlight.ExitKeywords := nil;
      for Item := 0 to Node.Count - 1 do
      begin
        if ExpectString(Node[Item], 'exitKeywords', Value) then
        begin
          FSettings.Highlight.ExitKeywords := FSettings.Highlight.ExitKeywords + [Value];
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "highlight.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineVar);
    end
    else if Key = 'changeSignature' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ChangeSignature);
    end
    else if Key = 'newParameter' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if SameText(Value, 'overload') or SameText(Value, 'updateCallers') then
        begin
          FSettings.Refactoring.NewParameterOverload := SameText(Value, 'overload');
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.newParameter" muss "overload" oder "updateCallers" sein');
        end;
      end;
    end
    else if Key = 'virtualOverload' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.VirtualOverload);
    end
    else if Key = 'syncSignatures' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.SyncSignatures);
    end
    else if Key = 'forwardDeclaration' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ForwardDeclaration);
    end
    else if Key = 'tryFinally' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.TryFinally);
    end
    else if Key = 'classActions' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ClassActions);
    end
    else if Key = 'explicitType' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ExplicitType);
    end
    else if Key = 'compilerFixes' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.CompilerFixes);
    end
    else if Key = 'missingUnit' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MissingUnit);
    end
    else if Key = 'disableWarning' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.DisableWarning);
    end
    else if Key = 'disableWarningReason' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.DisableWarningReason);
    end
    else if Key = 'extract' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.Extract);
    end
    else if Key = 'completeCase' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.CompleteCase);
    end
    else if Key = 'resolveWith' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ResolveWith);
    end
    else if Key = 'inline' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineCode);
    end
    else if Key = 'moveClass' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MoveClass);
    end
    else if Key = 'unitRenameFollowUp' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if SameText(Value, 'ask') or SameText(Value, 'off') then
        begin
          FSettings.Refactoring.UnitRenameFollowUp := SameText(Value, 'ask');
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.unitRenameFollowUp" muss "ask" oder "off" sein');
        end;
      end;
    end
    else if Key = 'createMethod' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.CreateMethod);
    end
    else if Key = 'createMethodSection' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if MatchText(Value, ['private', 'protected', 'public']) then
        begin
          FSettings.Refactoring.CreateMethodSection := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.createMethodSection" muss "private", "protected" oder "public" sein');
        end;
      end;
    end
    else if Key = 'createMethodCaret' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if SameText(Value, 'call') or SameText(Value, 'body') then
        begin
          FSettings.Refactoring.CreateMethodCaretInBody := SameText(Value, 'body');
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.createMethodCaret" muss "call" oder "body" sein');
        end;
      end;
    end
    else if Key = 'constParameters' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ConstParameters);
    end
    else if Key = 'propertyFromAccessors' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.PropertyFromAccessors);
    end
    else if Key = 'propertyFromAccessorsPrefixes' then
    begin
      if ANode[Index].Kind <> TJsonKind.Array_ then
      begin
        ReportNode(ANode[Index], '"refactoring.propertyFromAccessorsPrefixes" muss eine Liste von Präfixen sein');
      end
      else
      begin
        FSettings.Refactoring.PropertyFromAccessorsPrefixes := nil;
        for Item := 0 to ANode[Index].Count - 1 do
        begin
          if ExpectString(ANode[Index][Item], Key, Value) and (Trim(Value) <> '') then
          begin
            FSettings.Refactoring.PropertyFromAccessorsPrefixes :=
              FSettings.Refactoring.PropertyFromAccessorsPrefixes + [Trim(Value)];
          end;
        end;
      end;
    end
    else if Key = 'propertyFromAccessorsReplaceCalls' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if MatchText(Value, ['ask', 'always', 'never']) then
        begin
          FSettings.Refactoring.PropertyFromAccessorsReplaceCalls := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.propertyFromAccessorsReplaceCalls" muss "ask", "always" oder ' +
            '"never" sein');
        end;
      end;
    end
    else if Key = 'propertyFromAccessorsSection' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if MatchText(Value, ['accessor', 'public', 'published']) then
        begin
          FSettings.Refactoring.PropertyFromAccessorsSection := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.propertyFromAccessorsSection" muss "accessor", "public" oder ' +
            '"published" sein');
        end;
      end;
    end
    else if Key = 'propertyFromAccessorsHideAccessors' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if MatchText(Value, ['off', 'private', 'protected']) then
        begin
          FSettings.Refactoring.PropertyFromAccessorsHideAccessors := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.propertyFromAccessorsHideAccessors" muss "off", "private" oder ' +
            '"protected" sein');
        end;
      end;
    end
    else if Key = 'freeFields' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.FreeFields);
    end
    else if Key = 'freeFieldsStyle' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if SameText(Value, 'free') then
        begin
          FSettings.Refactoring.FreeFieldsStyle := 'free';
        end
        else if SameText(Value, 'freeAndNil') then
        begin
          FSettings.Refactoring.FreeFieldsStyle := 'freeAndNil';
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.freeFieldsStyle" muss "free" oder "freeAndNil" sein');
        end;
      end;
    end
    else if Key = 'suggestConst' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.SuggestConst);
    end
    else if Key = 'invertBoolean' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InvertBoolean);
    end
    else if Key = 'varBlock' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.VarBlock);
    end
    else if Key = 'varBlockMerge' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.VarBlockMerge);
    end
    else if Key = 'varBlockSort' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if MatchText(Value, ['usage', 'alpha', 'none']) then
        begin
          FSettings.Refactoring.VarBlockSort := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.varBlockSort" muss "usage", "alpha" oder "none" sein');
        end;
      end;
    end
    else if Key = 'invertBooleanAntonyms' then
    begin
      // {"Hidden": "Visible"}: Name → Gegenteil, beide Richtungen.
      if ANode[Index].Kind <> TJsonKind.Object_ then
      begin
        ReportNode(ANode[Index], '"refactoring.invertBooleanAntonyms" muss ein Objekt wie {"Hidden": "Visible"} sein');
      end
      else
      begin
        FSettings.Refactoring.InvertBooleanAntonyms := nil;
        for Item := 0 to ANode[Index].Count - 1 do
        begin
          if ExpectString(ANode[Index][Item], Key, Value) then
          begin
            if IsValidIdent(ANode[Index].Keys[Item]) and IsValidIdent(Trim(Value)) then
            begin
              FSettings.Refactoring.InvertBooleanAntonyms := FSettings.Refactoring.InvertBooleanAntonyms +
                [ANode[Index].Keys[Item] + '=' + Trim(Value)];
            end
            else
            begin
              ReportNode(ANode[Index][Item], Format('"refactoring.invertBooleanAntonyms": "%s" und "%s" müssen ' +
                'Bezeichner sein', [ANode[Index].Keys[Item], Value]));
            end;
          end;
        end;
      end;
    end
    else if Key = 'invertBooleanFallbackPrefix' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if IsValidIdent(Trim(Value)) then
        begin
          FSettings.Refactoring.InvertBooleanFallbackPrefix := Trim(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.invertBooleanFallbackPrefix" muss ein Bezeichner wie "Not" sein');
        end;
      end;
    end
    else if Key = 'invertBooleanIncludeDfm' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InvertBooleanIncludeDfm);
    end
    else if Key = 'ifCase' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.IfCase);
    end
    else if Key = 'conditions' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.Conditions);
    end
    else if Key = 'conditionalExpression' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ConditionalExpression);
    end
    else if Key = 'nestedRoutine' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.NestedRoutine);
    end
    else if Key = 'promoteVariable' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.PromoteVariable);
    end
    else if Key = 'anonymousMethod' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.AnonymousMethod);
    end
    else if Key = 'anonymousMethodDeferredCapture' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if SameText(Value, 'forward') then
        begin
          FSettings.Refactoring.AnonymousMethodDeferredCapture := 'forward';
        end
        else if SameText(Value, 'fields') then
        begin
          FSettings.Refactoring.AnonymousMethodDeferredCapture := 'fields';
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.anonymousMethodDeferredCapture" muss "forward" oder "fields" sein');
        end;
      end;
    end
    else if Key = 'methodKind' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MethodKind);
    end
    else if Key = 'methodKindMarker' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MethodKindMarker);
    end
    else if Key = 'methodKindStatic' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MethodKindStatic);
    end
    else if Key = 'typeAlias' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.TypeAlias);
    end
    else if Key = 'typeAliasScope' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if SameText(Value, 'here') or SameText(Value, 'unit') or SameText(Value, 'project') then
        begin
          FSettings.Refactoring.TypeAliasScope := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.typeAliasScope" muss "here", "unit" oder "project" sein');
        end;
      end;
    end
    else if Key = 'enumTables' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.EnumTables);
    end
    else if Key = 'enumTablesResourceStrings' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.EnumTablesResourceStrings);
    end
    else if Key = 'overloads' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.Overloads);
    end
    else if Key = 'extractInterface' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ExtractInterface);
    end
    else if Key = 'extractSuperclass' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.ExtractSuperclass);
    end
    else if Key = 'extractSuperclassTarget' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if SameText(Value, 'sameUnit') then
        begin
          FSettings.Refactoring.ExtractSuperclassTarget := 'sameUnit';
        end
        else if SameText(Value, 'newUnit') then
        begin
          FSettings.Refactoring.ExtractSuperclassTarget := 'newUnit';
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.extractSuperclassTarget" muss "sameUnit" oder "newUnit" sein');
        end;
      end;
    end
    else if Key = 'extractSuperclassNameSuffix' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if IsValidIdent(Trim(Value)) then
        begin
          FSettings.Refactoring.ExtractSuperclassNameSuffix := Trim(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.extractSuperclassNameSuffix" muss ein Bezeichner wie "Base" sein');
        end;
      end;
    end
    else if Key = 'extractSuperclassMethodMode' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if MatchText(Value, ['move', 'abstract']) then
        begin
          FSettings.Refactoring.ExtractSuperclassMethodMode := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.extractSuperclassMethodMode" muss "move" oder "abstract" sein');
        end;
      end;
    end
    else if Key = 'extractSuperclassRaiseVisibility' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if SameText(Value, 'protected') then
        begin
          FSettings.Refactoring.ExtractSuperclassRaiseVisibility := 'protected';
        end
        else if SameText(Value, 'strictProtected') then
        begin
          FSettings.Refactoring.ExtractSuperclassRaiseVisibility := 'strictProtected';
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.extractSuperclassRaiseVisibility" muss "protected" oder ' +
            '"strictProtected" sein');
        end;
      end;
    end
    else if Key = 'moveMember' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.MoveMember);
    end
    else if Key = 'inlineAccessor' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineAccessor);
    end
    else if Key = 'inlineAccessorEqualityCheck' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineAccessorEqualityCheck);
    end
    else if Key = 'inlineAccessorBulk' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineAccessorBulk);
    end
    else if Key = 'inlineAccessorDiagnostic' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.InlineAccessorDiagnostic);
    end
    else if Key = 'safeDelete' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.SafeDelete);
    end
    else if Key = 'safeDeletePreviewWhenUnused' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Refactoring.SafeDeletePreviewWhenUnused);
    end
    else if Key = 'safeDeleteCascade' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if MatchText(Value, ['ask', 'always', 'never']) then
        begin
          FSettings.Refactoring.SafeDeleteCascade := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.safeDeleteCascade" muss "ask", "always" oder "never" sein');
        end;
      end;
    end
    else if Key = 'safeDeleteIncludeOverrides' then
    begin
      if ExpectString(ANode[Index], Key, Value) then
      begin
        if MatchText(Value, ['ask', 'always', 'never']) then
        begin
          FSettings.Refactoring.SafeDeleteIncludeOverrides := LowerCase(Value);
        end
        else
        begin
          ReportNode(ANode[Index], '"refactoring.safeDeleteIncludeOverrides" muss "ask", "always" oder "never" sein');
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "refactoring.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Compiler.OnSave);
    end
    else if Key = 'backend' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
      begin
        if Text = 'auto' then
        begin
          FSettings.Compiler.Backend := TCompilerBackendSetting.Auto;
        end
        else if Text = 'dcc' then
        begin
          FSettings.Compiler.Backend := TCompilerBackendSetting.Dcc;
        end
        else if Text = 'ide' then
        begin
          FSettings.Compiler.Backend := TCompilerBackendSetting.Ide;
        end
        else if Text = 'off' then
        begin
          FSettings.Compiler.Backend := TCompilerBackendSetting.Off;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "auto", "dcc", "ide" und "off"');
        end;
      end;
    end
    else if Key = 'ideCommand' then
    begin
      ExpectString(ANode[Index], Key, FSettings.Compiler.IdeCommand);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "compiler.%s"', [Key]), False);
    end;
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
      begin
        ExpectString(AToolNode[mIndex], mKey, APath);
      end
      else
      begin
        Report(AToolNode.KeyStarts[mIndex], AToolNode.KeyStarts[mIndex] + Length(mKey) + 2,
          Format('Unbekannte Einstellung "vcs.%s.%s"', [AName, mKey]), False);
      end;
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
      begin
        if MatchStr(Text, ['auto', 'git', 'svn', 'off']) then
        begin
          FSettings.VcsProvider := Text;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "auto", "git", "svn" und "off"');
        end;
      end;
    end
    else if Key = 'git' then
    begin
      ReadTool(ANode[Index], Key, FSettings.VcsGitPath);
    end
    else if Key = 'svn' then
    begin
      ReadTool(ANode[Index], Key, FSettings.VcsSvnPath);
    end
    else if Key = 'projects' then
    begin
      ReadVcsProjects(ANode[Index]);
    end
    else if Key = 'timeoutSeconds' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, mSeconds) and (mSeconds >= 1) and
        (mSeconds <= 300) then
      begin
        FSettings.VcsTimeoutSeconds := mSeconds;
      end
      else
      begin
        ReportNode(ANode[Index], '"vcs.timeoutSeconds" muss eine ganze Zahl von 1 bis 300 sein');
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "vcs.%s"', [Key]), False);
    end;
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
      begin
        if Text = 'fuzzy' then
        begin
          FSettings.Completion.Matching := TCompletionMatching.Fuzzy;
        end
        else if Text = 'prefix' then
        begin
          FSettings.Completion.Matching := TCompletionMatching.Prefix;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "fuzzy" und "prefix"');
        end;
      end;
    end
    else if Key = 'interfaceSection' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
      begin
        if Text = 'private' then
        begin
          FSettings.Completion.InterfaceSection := TCompletionInterfaceSection.Private;
        end
        else if Text = 'protected' then
        begin
          FSettings.Completion.InterfaceSection := TCompletionInterfaceSection.Protected;
        end
        else if Text = 'public' then
        begin
          FSettings.Completion.InterfaceSection := TCompletionInterfaceSection.Public;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "private", "protected" und "public"');
        end;
      end;
    end
    else if Key = 'senderCast' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
      begin
        if Text = 'as' then
        begin
          FSettings.Completion.SenderCast := TCompletionSenderCast.AsOperator;
        end
        else if Text = 'cast' then
        begin
          FSettings.Completion.SenderCast := TCompletionSenderCast.HardCast;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "as" und "cast"');
        end;
      end;
    end
    else if Key = 'offerTryFinally' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.OfferTryFinally);
    end
    else if Key = 'keywords' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.Keywords);
    end
    else if Key = 'postfixTemplates' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.PostfixTemplates);
    end
    else if Key = 'genericConstraints' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.GenericConstraints);
    end
    else if Key = 'nameSuggestions' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.NameSuggestions);
    end
    else if Key = 'createAccessors' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.CreateAccessors);
    end
    else if Key = 'accessorSection' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
      begin
        if Text = 'private' then
        begin
          FSettings.Completion.AccessorSection := TCompletionAccessorSection.Private;
        end
        else if Text = 'protected' then
        begin
          FSettings.Completion.AccessorSection := TCompletionAccessorSection.Protected;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "private" und "protected"');
        end;
      end;
    end
    else if Key = 'resourceStrings' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.ResourceStrings);
    end
    else if Key = 'assignAllFields' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.AssignAllFields);
    end
    else if Key = 'usesDetails' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.UsesDetails);
    end
    else if Key = 'inheritedCall' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.InheritedCall);
    end
    else if Key = 'attributes' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.Attributes);
    end
    else if Key = 'anonymousMethods' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.AnonymousMethods);
    end
    else if Key = 'withOrigin' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.WithOrigin);
    end
    else if Key = 'exceptionClasses' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.ExceptionClasses);
    end
    else if Key = 'syntaxNotice' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.SyntaxNotice);
    end
    else if Key = 'sameNameVariants' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.SameNameVariants);
    end
    else if Key = 'showFmxUnits' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.Completion.ShowFmxUnits);
    end
    else if Key = 'sameNameInsert' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
      begin
        if Text = 'prefix' then
        begin
          FSettings.Completion.SameNameInsert := TCompletionSameNameInsert.Prefix;
        end
        else if Text = 'uses' then
        begin
          FSettings.Completion.SameNameInsert := TCompletionSameNameInsert.Uses_;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "prefix" und "uses"');
        end;
      end;
    end
    else if Key = 'typeConversion' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
      begin
        if Text = 'off' then
        begin
          FSettings.Completion.TypeConversion := TCompletionTypeConversion.Off;
        end
        else if Text = 'helper' then
        begin
          FSettings.Completion.TypeConversion := TCompletionTypeConversion.Helper;
        end
        else if Text = 'function' then
        begin
          FSettings.Completion.TypeConversion := TCompletionTypeConversion.Function_;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "off", "helper" und "function"');
        end;
      end;
    end
    else if Key = 'resourceStringUnit' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
      begin
        if (Text = '') or IsValidIdent(Text, True) then
        begin
          FSettings.Completion.ResourceStringUnit := Text;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erwartet wird ein Unit-Name wie "App.Texte" oder ""');
        end;
      end;
    end
    else if Key = 'freeStyle' then
    begin
      if ExpectString(ANode[Index], Key, Text) then
      begin
        if Text = 'free' then
        begin
          FSettings.Completion.FreeStyle := TCompletionFreeStyle.Free;
        end
        else if Text = 'freeAndNil' then
        begin
          FSettings.Completion.FreeStyle := TCompletionFreeStyle.FreeAndNil;
        end
        else
        begin
          ReportNode(ANode[Index], 'Erlaubt sind "free" und "freeAndNil"');
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "completion.%s"', [Key]), False);
    end;
  end;
end;

procedure TValidator.ReadServer(ANode: TJsonNode);
var
  Index: Integer;
  Key: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"server" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    if Key = 'crashCases' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.ServerCrashCases);
    end
    else if Key = 'crashSkip' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.ServerCrashSkip);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "server.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsLog);
    end
    else if Key = 'logDays' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, Days) and (Days >= 1) and
        (Days <= 365) then
      begin
        FSettings.DiagnosticsLogDays := Days;
      end
      else
      begin
        ReportNode(ANode[Index], '"diagnostics.logDays" muss eine ganze Zahl von 1 bis 365 sein');
      end;
    end
    else if Key = 'logMapFile' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsLogMapFile);
    end
    else if Key = 'usesCycleLive' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsUsesCycleLive);
    end
    else if Key = 'usesCycleImplementation' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsUsesCycleImplementation);
    end
    else if Key = 'librarySources' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.DiagnosticsLibrarySources);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "diagnostics.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.IndexProjectGroup);
    end
    else if Key = 'searchPaths' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.IndexSearchPaths);
    end
    else if Key = 'libraryPaths' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.IndexLibraryPaths);
    end
    else if Key = 'usages' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.IndexUsages);
    end
    else if Key = 'removeOrphans' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.IndexRemoveOrphans);
    end
    else if Key = 'cacheMaxAgeDays' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, Number) and (Number >= 0) and
        (Number <= 3650) then
      begin
        FSettings.IndexCacheMaxAgeDays := Number;
      end
      else
      begin
        ReportNode(ANode[Index], '"index.cacheMaxAgeDays" muss eine ganze Zahl von 0 bis 3650 sein');
      end;
    end
    else if Key = 'cacheMaxMb' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, Number) and (Number >= 0) and
        (Number <= 1048576) then
      begin
        FSettings.IndexCacheMaxMb := Number;
      end
      else
      begin
        ReportNode(ANode[Index], '"index.cacheMaxMb" muss eine ganze Zahl von 0 bis 1048576 sein');
      end;
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
      begin
        if ExpectString(ANode[Index][Item], 'index.exclude', Value) then
        begin
          FSettings.IndexExclude := FSettings.IndexExclude + [Value];
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "index.%s"', [Key]), False);
    end;
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
    begin
      ExpectBoolean(ANode[mIndex], mKey, FSettings.HotspotsEnabled);
    end
    else if mKey = 'months' then
    begin
      if (ANode[mIndex].Kind = TJsonKind.Number) and TryStrToInt(ANode[mIndex].Value, mNumber) and (mNumber >= 1) and
        (mNumber <= 60) then
      begin
        FSettings.HotspotsMonths := mNumber;
      end
      else
      begin
        ReportNode(ANode[mIndex], '"hotspots.months" muss eine ganze Zahl von 1 bis 60 sein');
      end;
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
          begin
            FSettings.HotspotsCouplingMinCommits := mNumber;
          end
          else
          begin
            ReportNode(ANode[mIndex][mInner],
              '"hotspots.coupling.minCommits" muss eine ganze Zahl von 2 bis 1000 sein');
          end;
        end
        else
        begin
          Report(ANode[mIndex].KeyStarts[mInner], ANode[mIndex].KeyStarts[mInner] + Length(mInnerKey) + 2,
            Format('Unbekannte Einstellung "hotspots.coupling.%s"', [mInnerKey]), False);
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Einstellung "hotspots.%s"', [mKey]), False);
    end;
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
    begin
      AValue := mNumber;
    end
    else
    begin
      ReportNode(AValueNode, Format('"architecture.grouping.%s" muss eine Zahl von %s sein', [AName, ARange]));
    end;
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
      begin
        ReadNumber(AGroupNode[mIndex], mKey, '0,2 bis 5,0', 0.2, 5, FSettings.ArchitectureGroupingResolution);
      end
      else if mKey = 'maxShare' then
      begin
        ReadNumber(AGroupNode[mIndex], mKey, '0 bis 0,9', 0, 0.9, FSettings.ArchitectureGroupingMaxShare);
      end
      else if mKey = 'minCohesion' then
      begin
        ReadNumber(AGroupNode[mIndex], mKey, '0 bis 1', 0, 1, FSettings.ArchitectureGroupingMinCohesion);
      end
      else if mKey = 'foundations' then
      begin
        if (AGroupNode[mIndex].Kind = TJsonKind.String_) and ((AGroupNode[mIndex].Value = 'group') or
          (AGroupNode[mIndex].Value = 'attach') or (AGroupNode[mIndex].Value = 'separate')) then
        begin
          FSettings.ArchitectureGroupingFoundations := AGroupNode[mIndex].Value;
        end
        else
        begin
          ReportNode(AGroupNode[mIndex],
            '"architecture.grouping.foundations" muss "group", "attach" oder "separate" sein');
        end;
      end
      else if mKey = 'showResolutionSlider' then
      begin
        ExpectBoolean(AGroupNode[mIndex], mKey, FSettings.ArchitectureGroupingShowResolutionSlider);
      end
      else if mKey = 'keepPrevious' then
      begin
        ExpectBoolean(AGroupNode[mIndex], mKey, FSettings.ArchitectureGroupingKeepPrevious);
      end
      else
      begin
        Report(AGroupNode.KeyStarts[mIndex], AGroupNode.KeyStarts[mIndex] + Length(mKey) + 2,
          Format('Unbekannte Einstellung "architecture.grouping.%s"', [mKey]), False);
      end;
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
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.ArchitectureEnabled);
    end
    else if Key = 'scope' then
    begin
      if (ANode[Index].Kind = TJsonKind.String_) and ((ANode[Index].Value = 'project') or
        (ANode[Index].Value = 'projectGroup')) then
      begin
        FSettings.ArchitectureScope := ANode[Index].Value;
      end
      else
      begin
        ReportNode(ANode[Index], '"architecture.scope" muss "project" oder "projectGroup" sein');
      end;
    end
    else if Key = 'includeLibraryUnits' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.ArchitectureIncludeLibraryUnits);
    end
    else if Key = 'centralUnits' then
    begin
      if (ANode[Index].Kind = TJsonKind.Number) and TryStrToInt(ANode[Index].Value, Number) and (Number >= 5) and
        (Number <= 100) then
      begin
        FSettings.ArchitectureCentralUnits := Number;
      end
      else
      begin
        ReportNode(ANode[Index], '"architecture.centralUnits" muss eine ganze Zahl von 5 bis 100 sein');
      end;
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
      begin
        if ExpectString(ANode[Index][Item], 'architecture.exclude', Value) then
        begin
          FSettings.ArchitectureExclude := FSettings.ArchitectureExclude + [Value];
        end;
      end;
    end
    else if Key = 'baseline' then
    begin
      if ExpectString(ANode[Index], 'architecture.baseline', Value) then
      begin
        FSettings.ArchitectureBaseline := Trim(Value);
      end;
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
      begin
        if ExpectString(ANode[Index][Item], 'architecture.failOn', Value) then
        begin
          if (Value = 'newCycle') or (Value = 'newCrossLink') or (Value = 'subsystemChange') or
            (Value = 'centralGrowth') then
          begin
            FSettings.ArchitectureFailOn := FSettings.ArchitectureFailOn + [Value];
          end
          else
          begin
            ReportNode(ANode[Index][Item], Format('"architecture.failOn": unbekannte Abweichung "%s" (erlaubt: ' +
              'newCycle, newCrossLink, subsystemChange, centralGrowth)', [Value]));
          end;
        end;
      end;
    end
    else if Key = 'explainAssignment' then
    begin
      ExpectBoolean(ANode[Index], Key, FSettings.ArchitectureExplainAssignment);
    end
    else if Key = 'grouping' then
    begin
      ReadGrouping(ANode[Index]);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "architecture.%s"', [Key]), False);
    end;
  end;
end;

procedure TValidator.ReadQuery(ANode: TJsonNode);
var
  mIndex: Integer;
  mKey: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"query" muss ein Objekt sein');
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    if mKey = 'enabled' then
    begin
      ExpectBoolean(ANode[mIndex], mKey, FSettings.QueryEnabled);
    end
    else
    begin
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Einstellung "query.%s"', [mKey]), False);
    end;
  end;
end;

procedure TValidator.ReadRuleChecks(ANode: TJsonNode);
var
  mIndex: Integer;
  mKey: string;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"ruleChecks" muss ein Objekt sein');
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    if mKey = 'enabled' then
    begin
      ExpectBoolean(ANode[mIndex], mKey, FSettings.RuleChecksEnabled);
    end
    else
    begin
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Einstellung "ruleChecks.%s"', [mKey]), False);
    end;
  end;
end;

procedure TValidator.ReadQueries(ANode: TJsonNode);
var
  mIndex, mOther: Integer;
  mQuery: TSavedQuery;
  mDuplicate: Boolean;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    ReportNode(ANode, '"queries" muss eine Liste von Abfragen sein');
    Exit;
  end;
  FSettings.Queries := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if not ReadSavedQuery(ANode[mIndex], mQuery) then
    begin
      Continue;
    end;
    // Der Name ist die Kennung der Regel query:<name> und von --query @<name>: zweimal derselbe wäre mehrdeutig.
    mDuplicate := False;
    for mOther := 0 to High(FSettings.Queries) do
    begin
      if SameText(FSettings.Queries[mOther].Name, mQuery.Name) then
      begin
        mDuplicate := True;
      end;
    end;
    if mDuplicate then
    begin
      ReportNode(ANode[mIndex], Format('Abfrage "%s" ist doppelt; es gilt die erste', [mQuery.Name]));
    end
    else
    begin
      FSettings.Queries := FSettings.Queries + [mQuery];
    end;
  end;
end;

function TValidator.ReadSavedQuery(ANode: TJsonNode; out AQuery: TSavedQuery): Boolean;
var
  mIndex, mChar: Integer;
  mKey, mText: string;
  mValue: TJsonNode;
begin
  AQuery := Default(TSavedQuery);
  AQuery.Severity := TRuleSeverity.Warning;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, 'Eine gespeicherte Abfrage muss ein Objekt sein: { "name": …, "query": … }');
    Exit(False);
  end;
  AQuery.Range := TTextRange.Create(PositionAt(ANode.Start), PositionAt(ANode.Start + 1));
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    mValue := ANode[mIndex];
    if mKey = 'name' then
    begin
      if ExpectString(mValue, mKey, mText) then
      begin
        AQuery.Name := Trim(mText);
        for mChar := 1 to Length(AQuery.Name) do
        begin
          if not CharInSet(AQuery.Name[mChar], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
          begin
            ReportNode(mValue, 'Der Name einer Abfrage besteht aus Buchstaben, Ziffern, "-", "_" und "."');
            AQuery.Name := '';
            Break;
          end;
        end;
      end;
    end
    else if mKey = 'query' then
    begin
      if ExpectString(mValue, mKey, mText) then
      begin
        AQuery.Query := Trim(mText);
        AQuery.QueryRange := TTextRange.Create(PositionAt(mValue.Start + 1 + Length(mText) - Length(TrimLeft(mText))),
          PositionAt(mValue.Stop));
      end;
    end
    else if mKey = 'description' then
    begin
      ExpectString(mValue, mKey, AQuery.Description);
    end
    else if mKey = 'failIfAny' then
    begin
      ExpectBoolean(mValue, mKey, AQuery.FailIfAny);
    end
    else if mKey = 'severity' then
    begin
      if ExpectString(mValue, mKey, mText) and (not TConfigurationParser.TryParseSeverity(mText, AQuery.Severity) or
        (AQuery.Severity = TRuleSeverity.Default)) then
      begin
        ReportNode(mValue, Format('Unbekannter Schweregrad "%s"; erlaubt: off, hint, info, warning, error', [mText]));
        AQuery.Severity := TRuleSeverity.Warning;
      end;
    end
    else if mKey = 'message' then
    begin
      ExpectString(mValue, mKey, AQuery.Message);
    end
    else
    begin
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Angabe "%s" in einer gespeicherten Abfrage', [mKey]), False);
    end;
  end;
  if AQuery.Name = '' then
  begin
    ReportNode(ANode, 'Eine gespeicherte Abfrage braucht "name"');
  end
  else if AQuery.Query = '' then
  begin
    ReportNode(ANode, Format('Abfrage "%s" braucht "query"', [AQuery.Name]));
  end;
  Result := (AQuery.Name <> '') and (AQuery.Query <> '');
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
    begin
      Include(mSettings.Given, AKey);
    end;
  end;

  procedure ReadPlacement(var ATarget: TBlockPlacement);
  begin
    if (Value.Kind = TJsonKind.String_) and (Value.Value = 'preserve') then
    begin
      ATarget := TBlockPlacement.Preserve;
    end
    else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'newLine') then
    begin
      ATarget := TBlockPlacement.NewLine;
    end
    else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'sameLine') then
    begin
      ATarget := TBlockPlacement.SameLine;
    end
    else
    begin
      ReportNode(Value, 'Erlaubt sind "preserve", "newLine" und "sameLine"');
    end;
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
      begin
        ReportNode(Value, '"indentSize" muss eine ganze Zahl von 1 bis 16 sein');
      end;
    end
    else if Key = 'useTabs' then
    begin
      ReadBoolean(mSettings.UseTabs, TFormatKey.UseTabs);
    end
    else if Key = 'trimTrailingWhitespace' then
    begin
      ReadBoolean(mSettings.TrimTrailingWhitespace, TFormatKey.TrimTrailingWhitespace);
    end
    else if Key = 'insertFinalNewline' then
    begin
      ReadBoolean(mSettings.InsertFinalNewline, TFormatKey.InsertFinalNewline);
    end
    else if Key = 'spaceAroundAssignment' then
    begin
      ReadBoolean(mSettings.SpaceAroundAssignment, TFormatKey.SpaceAroundAssignment);
    end
    else if Key = 'spaceAfterComma' then
    begin
      ReadBoolean(mSettings.SpaceAfterComma, TFormatKey.SpaceAfterComma);
    end
    else if Key = 'keywordCase' then
    begin
      if (Value.Kind = TJsonKind.String_) and (Value.Value = 'preserve') then
      begin
        mSettings.KeywordCase := TKeywordCase.Preserve;
      end
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'lower') then
      begin
        mSettings.KeywordCase := TKeywordCase.Lower;
      end
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'upper') then
      begin
        mSettings.KeywordCase := TKeywordCase.Upper;
      end
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
      begin
        mSettings.EndOfLine := #10;
      end
      else if (Value.Kind = TJsonKind.String_) and (Value.Value = 'crlf') then
      begin
        mSettings.EndOfLine := #13#10;
      end
      else
      begin
        ReportNode(Value, 'Erlaubt sind "lf" und "crlf"');
        Continue;
      end;
      Include(mSettings.Given, TFormatKey.EndOfLine);
    end
    else if Key = 'reindent' then
    begin
      ExpectBoolean(Value, Key, mSettings.Reindent);
    end
    else if Key = 'beginPlacement' then
    begin
      ReadPlacement(mSettings.BeginPlacement);
    end
    else if Key = 'elsePlacement' then
    begin
      ReadPlacement(mSettings.ElsePlacement);
    end
    else if Key = 'maxLineLength' then
    begin
      if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Size) and (Size >= 0) and (Size <= 1000) then
      begin
        mSettings.MaxLineLength := Size;
        Include(mSettings.Given, TFormatKey.MaxLineLength);
      end
      else
      begin
        ReportNode(Value, '"maxLineLength" muss eine ganze Zahl von 0 bis 1000 sein');
      end;
    end
    else if Key = 'alignAssignments' then
    begin
      ExpectBoolean(Value, Key, mSettings.AlignAssignments);
    end
    else if Key = 'alignDeclarations' then
    begin
      ExpectBoolean(Value, Key, mSettings.AlignDeclarations);
    end
    else if Key = 'alignComments' then
    begin
      ExpectBoolean(Value, Key, mSettings.AlignComments);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "format.%s"', [Key]), False);
    end;
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
    begin
      ReportNode(ANode, 'Erlaubt sind "dcc", "pwsh", "msbuild", "generic", "none" oder ein Objekt mit "regex"');
    end;
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
      begin
        if Text = '' then
        begin
          ReportNode(ANode[Index], '"regex" darf nicht leer sein');
        end
        else
        begin
          HasRegex := True;
        end;
      end;
    end
    else if Key = 'severity' then
    begin
      if ExpectString(ANode[Index], 'severity', Text) and (IndexStr(Text, ['error', 'warning', 'info']) < 0) then
      begin
        ReportNode(ANode[Index], 'Erlaubt sind "error", "warning" und "info"');
      end;
    end
    else if Key = 'severityMap' then
    begin
      if ANode[Index].Kind <> TJsonKind.Object_ then
      begin
        ReportNode(ANode[Index], '"severityMap" muss ein Objekt Wort → error, warning oder info sein');
        Continue;
      end;
      for Item := 0 to ANode[Index].Count - 1 do
      begin
        if ExpectString(ANode[Index][Item], 'severityMap', Text) and
          (IndexStr(Text, ['error', 'warning', 'info']) < 0) then
        begin
          ReportNode(ANode[Index][Item], 'Erlaubt sind "error", "warning" und "info"');
        end;
      end;
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Angabe "%s" im Muster; erlaubt: regex, severity, severityMap', [Key]), False);
    end;
  end;
  if not HasRegex then
  begin
    ReportNode(ANode, 'Eigenes Muster ohne "regex"');
  end;
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
            begin
              ReportNode(Value, Format('Die Aufgabe "%s" gibt es schon', [Trim(Text)]));
            end
            else
            begin
              Names.Add(AnsiLowerCase(Trim(Text)));
            end;
          end;
        end
        else if Key = 'command' then
        begin
          HasCommand := ExpectString(Value, 'command', Text) and (Trim(Text) <> '');
        end
        else if (Key = 'cwd') or (Key = 'key') then
        begin
          ExpectString(Value, Key, Text);
        end
        else if Key = 'args' then
        begin
          if Value.Kind <> TJsonKind.Array_ then
          begin
            ReportNode(Value, '"args" muss eine Liste von Texten sein');
          end
          else
          begin
            for Item := 0 to Value.Count - 1 do
            begin
              if Value[Item].Kind <> TJsonKind.Number then
              begin
                ExpectString(Value[Item], 'args', Text);
              end;
            end;
          end;
        end
        else if Key = 'env' then
        begin
          if Value.Kind <> TJsonKind.Object_ then
          begin
            ReportNode(Value, '"env" muss ein Objekt Name → Wert sein');
          end
          else
          begin
            for Item := 0 to Value.Count - 1 do
            begin
              ExpectString(Value[Item], 'env', Text);
            end;
          end;
        end
        else if Key = 'group' then
        begin
          if ExpectString(Value, 'group', Text) and (IndexStr(Text, ['check', 'build', 'test', 'other']) < 0) then
          begin
            ReportNode(Value, 'Erlaubt sind "check", "build", "test" und "other"');
          end;
        end
        else if Key = 'beforeBuild' then
        begin
          if ExpectString(Value, 'beforeBuild', Text) and (IndexStr(Text, ['off', 'warn', 'block']) < 0) then
          begin
            ReportNode(Value, 'Erlaubt sind "off", "warn" und "block"');
          end;
        end
        else if Key = 'timeoutSec' then
        begin
          if not ((Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Number) and (Number >= 0) and
            (Number <= 86400)) then
          begin
            ReportNode(Value, '"timeoutSec" muss eine ganze Zahl von 0 bis 86400 sein');
          end;
        end
        else if Key = 'matcher' then
        begin
          ReadTaskMatcher(Value);
        end
        else
        begin
          Report(Task.KeyStarts[Inner], Task.KeyStarts[Inner] + Length(Key) + 2,
            Format('Unbekannte Angabe "%s" in einer Aufgabe', [Key]), False);
        end;
      end;
      if not HasName then
      begin
        ReportNode(Task, 'Aufgabe ohne "name"');
      end;
      if not HasCommand then
      begin
        ReportNode(Task, 'Aufgabe ohne "command"');
      end;
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
    begin
      ReadIssueConnections(ANode[Index]);
    end
    else if Key = 'projects' then
    begin
      ReadIssueProjects(ANode[Index]);
    end
    else if Key = 'queries' then
    begin
      ReadIssueQueries(ANode[Index]);
    end
    else
    begin
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "issues.%s"', [Key]), False);
    end;
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
  begin
    Exit;
  end;
  Host := Copy(AUrl, 9, MaxInt);
  Slash := Pos('/', Host);
  if Slash > 0 then
  begin
    Host := Copy(Host, 1, Slash - 1);
  end;
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
  begin
    if ANode[Index].Kind <> TJsonKind.String_ then
    begin
      ReportNode(ANode[Index], 'Ein Zustand in "endStates" ist ein Text');
    end;
  end;
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
            begin
              ReportNode(Value, Format('Die Verbindung "%s" gibt es schon', [Trim(Text)]));
            end
            else
            begin
              Names.Add(AnsiLowerCase(Trim(Text)));
            end;
          end;
        end
        else if Key = 'provider' then
        begin
          HasProvider := ExpectString(Value, 'provider', Text) and (Trim(Text) <> '');
        end
        else if Key = 'url' then
        begin
          if ExpectString(Value, 'url', Text) then
          begin
            HasUrl := True;
            // Das Token geht nur über https und nie mit Benutzer in der Adresse an den Tracker.
            if not IsTrackerUrl(Trim(Text)) then
            begin
              ReportNode(Value, 'Nur https-Adressen ohne Benutzer, z. B. "https://youtrack.firma.de"');
            end;
          end;
        end
        else if Key = 'language' then
        begin
          // Sprache der Oberfläche (#1263), vom Plugin bei „Prüfen“ erkannt.
          if ExpectString(Value, 'language', Text) and (Text <> 'de') and (Text <> 'en') then
          begin
            ReportNode(Value, '"language" ist "de" oder "en"');
          end;
        end
        // Zustand beim Beginnen und Beenden je Verbindung (#1266).
        else if (Key = 'stateField') or (Key = 'assigneeField') or (Key = 'startState') then
        begin
          ExpectString(Value, Key, Text);
        end
        else if Key = 'endStates' then
        begin
          ReadIssueEndStates(Value);
        end
        else
        begin
          Report(Connection.KeyStarts[Inner], Connection.KeyStarts[Inner] + Length(Key) + 2,
            Format('Unbekannte Angabe "%s" in einer Verbindung', [Key]), False);
        end;
      end;
      if not HasName then
      begin
        ReportNode(Connection, 'Verbindung ohne "name"');
      end;
      if not HasProvider then
      begin
        ReportNode(Connection, 'Verbindung ohne "provider"');
      end;
      if not HasUrl then
      begin
        ReportNode(Connection, 'Verbindung ohne "url"');
      end;
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
            begin
              Delete(mText, Length(mText), 1);
            end;
            if mMatches.IndexOf(mText) >= 0 then
            begin
              ReportNode(mValue, 'Für diesen Pfad gibt es schon eine Zuordnung');
            end
            else
            begin
              mMatches.Add(mText);
            end;
          end;
        end
        else if mKey = 'provider' then
        begin
          if ExpectString(mValue, 'provider', mText) and not MatchStr(mText, ['auto', 'git', 'svn', 'off']) then
          begin
            ReportNode(mValue, 'Erlaubt sind "auto", "git", "svn" und "off"');
          end;
        end
        else if mKey = 'mainBranch' then
        begin
          if ExpectString(mValue, 'mainBranch', mText) and (Trim(mText).IndexOfAny([' ', #9]) >= 0) then
          begin
            ReportNode(mValue, 'Ein Branch-Name enthält keine Leerzeichen');
          end;
        end
        else
        begin
          Report(mMapping.KeyStarts[mInner], mMapping.KeyStarts[mInner] + Length(mKey) + 2,
            Format('Unbekannte Angabe "%s" in einer Zuordnung', [mKey]), False);
        end;
      end;
      if not mHasMatch then
      begin
        ReportNode(mMapping, 'Zuordnung ohne "match" (Pfad einer .dproj, .groupproj oder eines Ordners)');
      end;
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
            begin
              Delete(Text, Length(Text), 1);
            end;
            if Matches.IndexOf(Text) >= 0 then
            begin
              ReportNode(Value, 'Für diesen Pfad gibt es schon eine Zuordnung');
            end
            else
            begin
              Matches.Add(Text);
            end;
          end;
        end
        else if Key = 'connection' then
        begin
          HasConnection := ExpectString(Value, 'connection', Text) and (Trim(Text) <> '');
        end
        else if Key = 'project' then
        begin
          ExpectString(Value, 'project', Text);
        end
        else
        begin
          Report(Mapping.KeyStarts[Inner], Mapping.KeyStarts[Inner] + Length(Key) + 2,
            Format('Unbekannte Angabe "%s" in einer Zuordnung', [Key]), False);
        end;
      end;
      if not HasMatch then
      begin
        ReportNode(Mapping, 'Zuordnung ohne "match" (Pfad einer .dproj, .groupproj oder eines Ordners)');
      end;
      if not HasConnection then
      begin
        ReportNode(Mapping, 'Zuordnung ohne "connection"');
      end;
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
            begin
              ReportNode(Value, Format('Die Abfrage "%s" gibt es schon', [Trim(Text)]));
            end
            else
            begin
              Names.Add(AnsiLowerCase(Trim(Text)));
            end;
          end;
        end
        else if Key = 'query' then
        begin
          HasQuery := ExpectString(Value, 'query', Text) and (Trim(Text) <> '');
        end
        else if (Key = 'connection') or (Key = 'project') then
        begin
          ExpectString(Value, Key, Text);
        end
        else
        begin
          Report(Query.KeyStarts[Inner], Query.KeyStarts[Inner] + Length(Key) + 2,
            Format('Unbekannte Angabe "%s" in einer Abfrage', [Key]), False);
        end;
      end;
      if not HasName then
      begin
        ReportNode(Query, 'Abfrage ohne "name"');
      end;
      if not HasQuery then
      begin
        ReportNode(Query, 'Abfrage ohne "query"');
      end;
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
  begin
    Exit;
  end;
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
        begin
          if Text = '' then
          begin
            FSettings.DelphiVersion := '';
          end
          else if BdsVersionOf(Text) = '' then
          begin
            ReportNode(Value, 'Unbekannte Delphi-Version; erwartet z. B. "13" oder "37.0" für Delphi 13, "12" oder "23.0" für Delphi 12');
          end
          else
          begin
            FSettings.DelphiVersion := BdsVersionOf(Text);
            FSettings.DelphiVersionRange := TTextRange.Create(PositionAt(Value.Start), PositionAt(Value.Stop));
          end;
        end;
      end
      else if Key = 'minDelphiVersion' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          if Text = '' then
          begin
            FSettings.MinDelphiVersion := '';
          end
          else if BdsVersionOf(Text) = '' then
          begin
            ReportNode(Value, 'Unbekannte Delphi-Version; erwartet z. B. "12" oder "23.0" für Delphi 12, "11" oder "22.0" für Delphi 11');
          end
          else
          begin
            FSettings.MinDelphiVersion := BdsVersionOf(Text);
          end;
        end;
      end
      else if Key = 'language' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          if (Text = 'de') or (Text = 'en') then
          begin
            FSettings.Language := Text;
          end
          else
          begin
            ReportNode(Value, 'Erlaubt sind "de" und "en"');
          end;
        end;
      end
      else if Key = 'encoding' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          if not TFileEncoding.ParseCodePage(Text, FSettings.DefaultEncoding) then
          begin
            FSettings.DefaultEncoding := TFileEncoding.Utf8CodePage;
            ReportNode(Value, 'Unbekannte Kodierung; erwartet "utf-8" oder eine ANSI-Codepage wie "1252" oder "windows-1250"');
          end;
        end;
      end
      else if Key = 'project' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          FSettings.Project := Text;
        end;
      end
      else if Key = 'config' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          FSettings.Config := Text;
        end;
      end
      else if Key = 'platform' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          FSettings.Platform := Text;
        end;
      end
      else if Key = 'rules' then
      begin
        ReadRules(Value);
      end
      else if Key = 'profile' then
      begin
        ProfileNode := Value;
        ReadProfile(Value);
      end
      else if Key = 'profiles' then
      begin
        ReadProfiles(Value);
      end
      else if Key = 'overrides' then
      begin
        ReadOverrides(Value);
      end
      else if Key = 'excludeTests' then
      begin
        ExpectBoolean(Value, Key, FSettings.ExcludeTests);
      end
      else if Key = 'testProfile' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          if FSettings.IsKnownProfile(Text) or (Text = '') then
          begin
            FSettings.TestProfile := Text;
          end
          else
          begin
            FTestProfileNode := Value;
          end;
        end;
      end
      else if Key = 'exclude' then
      begin
        ReadExclude(Value);
      end
      else if Key = 'mcp' then
      begin
        ReadMcp(Value);
      end
      else if Key = 'fix' then
      begin
        ReadFix(Value);
      end
      else if Key = 'minConfidence' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          if TConfigurationParser.TryParseConfidence(Text, FSettings.MinConfidence) then
          begin
            FSettings.MinConfidenceGiven := True;
          end
          else
          begin
            ReportNode(Value, 'Erlaubt sind "low", "medium" und "high"');
          end;
        end;
      end
      else if Key = 'inlayHints' then
      begin
        ReadInlayHints(Value);
      end
      else if Key = 'codeLens' then
      begin
        ReadCodeLens(Value);
      end
      else if Key = 'references' then
      begin
        ReadReferences(Value);
      end
      else if Key = 'navigation' then
      begin
        ReadNavigation(Value);
      end
      else if Key = 'hints' then
      begin
        ReadHints(Value);
      end
      else if Key = 'directives' then
      begin
        ReadDirectives(Value);
      end
      else if Key = 'stringLiteral' then
      begin
        ReadStringLiteral(Value);
      end
      else if Key = 'memberOrder' then
      begin
        ReadMemberOrder(Value);
      end
      else if Key = 'testUnits' then
      begin
        ReadTestUnits(Value);
      end
      else if Key = 'tests' then
      begin
        ReadTests(Value);
      end
      else if Key = 'dfmPropertyRules' then
      begin
        ReadDfmPropertyRules(Value);
      end
      else if Key = 'highlight' then
      begin
        ReadHighlight(Value);
      end
      else if Key = 'compiler' then
      begin
        ReadCompiler(Value);
      end
      else if Key = 'vcs' then
      begin
        ReadVcs(Value);
      end
      else if Key = 'completion' then
      begin
        ReadCompletion(Value);
      end
      else if Key = 'refactoring' then
      begin
        ReadRefactoring(Value);
      end
      else if Key = 'diagnostics' then
      begin
        ReadDiagnostics(Value);
      end
      else if Key = 'server' then
      begin
        ReadServer(Value);
      end
      else if Key = 'index' then
      begin
        ReadIndex(Value);
      end
      else if Key = 'architecture' then
      begin
        ReadArchitecture(Value);
      end
      else if Key = 'query' then
      begin
        ReadQuery(Value);
      end
      else if Key = 'ruleChecks' then
      begin
        ReadRuleChecks(Value);
      end
      else if Key = 'queries' then
      begin
        ReadQueries(Value);
      end
      else if Key = 'hotspots' then
      begin
        ReadHotspots(Value);
      end
      else if Key = 'usesCommand' then
      begin
        ExpectBoolean(Value, Key, FSettings.UsesCommand);
      end
      else if Key = 'completeBlocks' then
      begin
        ReadCompleteBlocks(Value);
      end
      else if Key = 'experimental' then
      begin
        ReadExperimental(Value);
      end
      else if Key = 'metrics' then
      begin
        ExpectBoolean(Value, Key, FSettings.Metrics);
      end
      else if Key = 'slashCommands' then
      begin
        ReadSlashCommands(Value);
      end
      else if Key = 'sortUses' then
      begin
        ReadSortUses(Value);
      end
      else if Key = 'usesKeep' then
      begin
        ReadUsesKeep(Value);
      end
      else if Key = 'deadCode' then
      begin
        ReadDeadCode(Value);
      end
      else if Key = 'memoryBudgetMb' then
      begin
        if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Budget) and (Budget >= 0) then
        begin
          FSettings.MemoryBudgetMb := Budget;
        end
        else
        begin
          ReportNode(Value, '"memoryBudgetMb" muss eine ganze Zahl ab 0 sein');
        end;
      end
      else if Key = 'requestTimeoutMs' then
      begin
        if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Budget) and (Budget >= 1000) then
        begin
          FSettings.RequestTimeoutMs := Budget;
        end
        else
        begin
          ReportNode(Value, '"requestTimeoutMs" muss eine ganze Zahl ab 1000 sein');
        end;
      end
      else if Key = 'logLevel' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          if MatchStr(Text, ['debug', 'info', 'warning', 'error']) then
          begin
            FSettings.LogLevel := Text;
          end
          else
          begin
            ReportNode(Value, 'Erlaubt sind "debug", "info", "warning" und "error"');
          end;
        end;
      end
      else if Key = 'logFile' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          FSettings.LogFile := Text;
        end;
      end
      else if Key = 'traceFile' then
      begin
        if ExpectString(Value, Key, Text) then
        begin
          FSettings.TraceFile := Text;
        end;
      end
      else if Key = 'tasks' then
      begin
        ReadTasks(Value);
      end
      else if Key = 'issues' then
      begin
        ReadIssues(Value);
      end
      else if Key = 'format' then
      begin
        if Value.Kind = TJsonKind.Object_ then
        begin
          FSettings.Format := Copy(FText, Value.Start + 1, Value.Stop - Value.Start);
          ReadFormat(Value);
        end
        else
        begin
          ReportNode(Value, '"format" muss ein Objekt sein');
        end;
      end
      else if Key <> '$schema' then
      begin
        Report(Root.KeyStarts[Index], Root.KeyStarts[Index] + Length(Key) + 2,
          Format('Unbekannte Einstellung "%s"', [Key]), False);
      end;
    end;
    // Profilnamen erst prüfen, wenn auch "profiles" gelesen ist.
    ProfileNames := [FSettings.Profile, FSettings.CliProfile];
    for Text in ProfileNames do
    begin
      if (ProfileNode <> nil) and not FSettings.IsKnownProfile(Text) then
      begin
        ReportNode(ProfileNode, Format('Unbekanntes Profil "%s"; eingebaut: %s, sonst unter "profiles" anlegen',
          [Text, string.Join(', ', BuiltinProfileNames)]));
      end;
    end;
    if FTestProfileNode <> nil then
    begin
      if FSettings.IsKnownProfile(FTestProfileNode.Value) then
      begin
        FSettings.TestProfile := FTestProfileNode.Value;
      end
      else
      begin
        ReportNode(FTestProfileNode, Format('Unbekanntes Profil "%s"', [FTestProfileNode.Value]));
      end;
    end;
    for Profile in FSettings.Profiles do
    begin
      if not FSettings.IsKnownProfile(Profile.Extends) then
      begin
        ReportNode(Root, Format('Profil "%s" erweitert das unbekannte Profil "%s"', [Profile.Name, Profile.Extends]));
      end;
    end;
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
  begin
    AConfidence := TRuleConfidence.Low;
  end
  else if Value = 'medium' then
  begin
    AConfidence := TRuleConfidence.Medium;
  end
  else if Value = 'high' then
  begin
    AConfidence := TRuleConfidence.High;
  end
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
  begin
    ASeverity := TRuleSeverity.Off;
  end
  else if Value = 'hint' then
  begin
    ASeverity := TRuleSeverity.Hint;
  end
  else if (Value = 'info') or (Value = 'information') then
  begin
    ASeverity := TRuleSeverity.Information;
  end
  else if Value = 'warning' then
  begin
    ASeverity := TRuleSeverity.Warning;
  end
  else if Value = 'error' then
  begin
    ASeverity := TRuleSeverity.Error;
  end
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
    begin
      for Index := 0 to Root.Count - 1 do
      begin
        Result := Result + [Root.Keys[Index]];
      end;
    end;
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
    begin
      for mIndex := 0 to mRoot.Count - 1 do
      begin
        if (mRoot.Keys[mIndex] = AKey) and (mRoot[mIndex].Kind = TJsonKind.Object_) then
        begin
          for mInner := 0 to mRoot[mIndex].Count - 1 do
          begin
            Result := Result + [mRoot[mIndex].Keys[mInner]];
          end;
        end;
      end;
    end;
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
    begin
      if SameText(FileRule.Id, EditorRule.Id) then
      begin
        Overridden := True;
      end;
    end;
    if not Overridden then
    begin
      Result := Result + [EditorRule];
    end;
  end;
  Result := Result + AFile;
end;

function QuoteKey(const AKey: string): string;
var
  Ch: Char;
begin
  Result := '"';
  for Ch in AKey do
  begin
    if (Ch = '"') or (Ch = '\') then
    begin
      Result := Result + '\' + Ch;
    end
    else if Ord(Ch) < 32 then
    begin
      Result := Result + Format('\u%.4x', [Ord(Ch)]);
    end
    else
    begin
      Result := Result + Ch;
    end;
  end;
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
    begin
      if AUpper.Keys[Other] = ALower.Keys[Index] then
      begin
        Found := True;
      end;
    end;
    if not Found then
    begin
      Parts := Parts + [QuoteKey(ALower.Keys[Index]) + ': ' + NodeText(ALowerText, ALower[Index])];
    end;
  end;
  for Index := 0 to AUpper.Count - 1 do
  begin
    Other := ALower.Count - 1;
    while (Other >= 0) and (ALower.Keys[Other] <> AUpper.Keys[Index]) do
    begin
      Dec(Other);
    end;
    if (Other >= 0) and (ALower[Other].Kind = TJsonKind.Object_) and (AUpper[Index].Kind = TJsonKind.Object_) then
    begin
      Parts := Parts + [QuoteKey(AUpper.Keys[Index]) + ': ' +
        MergeObjects(ALowerText, ALower[Other], AUpperText, AUpper[Index])];
    end
    else
    begin
      Parts := Parts + [QuoteKey(AUpper.Keys[Index]) + ': ' + NodeText(AUpperText, AUpper[Index])];
    end;
  end;
  Result := '{' + string.Join(', ', Parts) + '}';
end;

function ParseObject(const AText: string): TJsonNode;
begin
  Result := nil;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  try
    Result := TJsonTree.Parse(AText);
  except
    on EJsonTreeError do
      Exit(nil);
  end;
  if Result.Kind <> TJsonKind.Object_ then
  begin
    FreeAndNil(Result);
  end;
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
      begin
        Exit('');
      end;
      Exit(AUpper);
    end;
    if Upper = nil then
    begin
      Exit(ALower);
    end;
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
  begin
    FileSettings := Parse(AFileText, AIssues);
  end
  else
  begin
    FileSettings := TServerSettings.Default;
  end;
  if Trim(AEditorText) = '' then
  begin
    Exit(FileSettings);
  end;
  // Unbekannte Schlüssel wie serverPath gehören dem Editor; ihre Meldungen entfallen.
  Result := Parse(AEditorText, Ignored);
  if AFileText = '' then
  begin
    Exit;
  end;
  for Key in RootKeys(AFileText) do
  begin
    if Key = 'delphiVersion' then
    begin
      Result.DelphiVersion := FileSettings.DelphiVersion;
      Result.DelphiVersionRange := FileSettings.DelphiVersionRange;
    end
    else if Key = 'minDelphiVersion' then
    begin
      Result.MinDelphiVersion := FileSettings.MinDelphiVersion;
    end
    else if Key = 'language' then
    begin
      Result.Language := FileSettings.Language;
    end
    else if Key = 'encoding' then
    begin
      Result.DefaultEncoding := FileSettings.DefaultEncoding;
    end
    else if Key = 'project' then
    begin
      Result.Project := FileSettings.Project;
    end
    else if Key = 'config' then
    begin
      Result.Config := FileSettings.Config;
    end
    else if Key = 'platform' then
    begin
      Result.Platform := FileSettings.Platform;
    end
    else if Key = 'rules' then
    begin
      Result.Rules := MergeRules(Result.Rules, FileSettings.Rules);
    end
    else if Key = 'profile' then
    begin
      Result.Profile := FileSettings.Profile;
      Result.CliProfile := FileSettings.CliProfile;
    end
    else if Key = 'profiles' then
    begin
      Result.Profiles := FileSettings.Profiles;
    end
    else if Key = 'overrides' then
    begin
      Result.Overrides := FileSettings.Overrides;
    end
    else if Key = 'excludeTests' then
    begin
      Result.ExcludeTests := FileSettings.ExcludeTests;
    end
    else if Key = 'testProfile' then
    begin
      Result.TestProfile := FileSettings.TestProfile;
    end
    else if Key = 'exclude' then
    begin
      Result.Exclude := FileSettings.Exclude;
    end
    else if Key = 'mcp' then
    begin
      // Gemischtes Objekt (global und Projekt): nur die Glieder, die die Datei nennt, sonst überschriebe etwa
      // mcp.customPrompts aus atlas.json das globale mcp.prompts mit der Vorgabe (#1357).
      for Member in MemberKeys(AFileText, 'mcp') do
      begin
        if Member = 'disabledTools' then
        begin
          Result.McpDisabledTools := FileSettings.McpDisabledTools;
        end
        else if Member = 'globalSettings' then
        begin
          Result.McpGlobalSettings := FileSettings.McpGlobalSettings;
        end
        else if Member = 'prompts' then
        begin
          Result.McpPrompts := FileSettings.McpPrompts;
        end
        else if Member = 'promptLanguage' then
        begin
          Result.McpPromptLanguage := FileSettings.McpPromptLanguage;
        end
        else if Member = 'customPrompts' then
        begin
          Result.McpCustomPrompts := FileSettings.McpCustomPrompts;
        end;
      end;
    end
    else if Key = 'minConfidence' then
    begin
      Result.MinConfidence := FileSettings.MinConfidence;
      Result.MinConfidenceGiven := FileSettings.MinConfidenceGiven;
    end
    else if Key = 'fix' then
    begin
      Result.FixMinConfidence := FileSettings.FixMinConfidence;
    end
    else if Key = 'tasks' then
    begin
      Result.Tasks := FileSettings.Tasks;
    end
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
    begin
      Result.InlayHints := FileSettings.InlayHints;
    end
    else if Key = 'codeLens' then
    begin
      Result.CodeLens := FileSettings.CodeLens;
    end
    else if Key = 'references' then
    begin
      Result.References := FileSettings.References;
    end
    else if Key = 'navigation' then
    begin
      Result.Navigation := FileSettings.Navigation;
    end
    else if Key = 'hints' then
    begin
      Result.Hints := FileSettings.Hints;
    end
    else if Key = 'directives' then
    begin
      Result.Directives := FileSettings.Directives;
    end
    else if Key = 'stringLiteral' then
    begin
      Result.StringLiteral := FileSettings.StringLiteral;
    end
    else if Key = 'memberOrder' then
    begin
      Result.MemberOrder := FileSettings.MemberOrder;
    end
    else if Key = 'testUnits' then
    begin
      Result.TestUnits := FileSettings.TestUnits;
    end
    else if Key = 'tests' then
    begin
      Result.Tests := FileSettings.Tests;
    end
    else if Key = 'dfmPropertyRules' then
    begin
      Result.DfmPropertyRules := FileSettings.DfmPropertyRules;
    end
    else if Key = 'highlight' then
    begin
      Result.Highlight := FileSettings.Highlight;
    end
    else if Key = 'compiler' then
    begin
      Result.Compiler := FileSettings.Compiler;
    end
    else if Key = 'vcs' then
    begin
      Result.VcsProvider := FileSettings.VcsProvider;
      Result.VcsGitPath := FileSettings.VcsGitPath;
      Result.VcsSvnPath := FileSettings.VcsSvnPath;
      Result.VcsTimeoutSeconds := FileSettings.VcsTimeoutSeconds;
      Result.VcsProjects := FileSettings.VcsProjects;
    end
    else if Key = 'completion' then
    begin
      Result.Completion := FileSettings.Completion;
    end
    else if Key = 'refactoring' then
    begin
      Result.Refactoring := FileSettings.Refactoring;
    end
    else if Key = 'diagnostics' then
    begin
      Result.DiagnosticsLog := FileSettings.DiagnosticsLog;
      Result.DiagnosticsLogDays := FileSettings.DiagnosticsLogDays;
      Result.DiagnosticsLogMapFile := FileSettings.DiagnosticsLogMapFile;
      Result.DiagnosticsUsesCycleLive := FileSettings.DiagnosticsUsesCycleLive;
      Result.DiagnosticsUsesCycleImplementation := FileSettings.DiagnosticsUsesCycleImplementation;
      Result.DiagnosticsLibrarySources := FileSettings.DiagnosticsLibrarySources;
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
    else if Key = 'query' then
    begin
      Result.QueryEnabled := FileSettings.QueryEnabled;
    end
    else if Key = 'ruleChecks' then
    begin
      Result.RuleChecksEnabled := FileSettings.RuleChecksEnabled;
    end
    else if Key = 'queries' then
    begin
      Result.Queries := FileSettings.Queries;
    end
    else if Key = 'usesCommand' then
    begin
      Result.UsesCommand := FileSettings.UsesCommand;
    end
    else if Key = 'completeBlocks' then
    begin
      Result.CompleteBlocksDocComment := FileSettings.CompleteBlocksDocComment;
    end
    else if Key = 'experimental' then
    begin
      Result.ExperimentalEnabled := FileSettings.ExperimentalEnabled;
    end
    else if Key = 'metrics' then
    begin
      Result.Metrics := FileSettings.Metrics;
    end
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
    begin
      Result.UsesKeep := FileSettings.UsesKeep;
    end
    else if Key = 'deadCode' then
    begin
      Result.DeadCodeKeepAttributes := FileSettings.DeadCodeKeepAttributes;
      Result.DeadCodeKeepPatterns := FileSettings.DeadCodeKeepPatterns;
    end
    else if Key = 'memoryBudgetMb' then
    begin
      Result.MemoryBudgetMb := FileSettings.MemoryBudgetMb;
    end
    else if Key = 'requestTimeoutMs' then
    begin
      Result.RequestTimeoutMs := FileSettings.RequestTimeoutMs;
    end
    else if Key = 'server' then
    begin
      Result.ServerCrashCases := FileSettings.ServerCrashCases;
      Result.ServerCrashSkip := FileSettings.ServerCrashSkip;
    end
    else if Key = 'logLevel' then
    begin
      Result.LogLevel := FileSettings.LogLevel;
    end
    else if Key = 'logFile' then
    begin
      Result.LogFile := FileSettings.LogFile;
    end
    else if Key = 'traceFile' then
    begin
      Result.TraceFile := FileSettings.TraceFile;
    end;
  end;
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
