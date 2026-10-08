unit BDLsp.Common.Configuration.Parser;

// Liest delphi-lsp.json und prüft sie. Fehlerhafte Einträge werden mit
// Position gemeldet und ignoriert; der Rest gilt trotzdem. Bei einem
// Syntaxfehler gelten die Vorgaben.
//
// ParseLayered führt Einstellungen aus dem Editor (z. B. VS-Code-Settings)
// mit delphi-lsp.json zusammen: Jeder Schlüssel, den die Datei setzt, hat
// Vorrang; Regeln werden je Regel-Id zusammengeführt.

interface

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract;

type
  TConfigurationParser = class
  public
    class function Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings; static;
    /// <summary>Editor-Einstellungen (JSON, '' = keine) unter delphi-lsp.json (Text, '' = keine Datei).
    /// AIssues betreffen nur die Datei.</summary>
    class function ParseLayered(const AEditorText, AFileText: string;
      out AIssues: TArray<TConfigurationIssue>): TServerSettings; static;
    /// <summary>Schweregrad aus dem Text ("off", "hint", "info", "information", "warning", "error").</summary>
    class function TryParseSeverity(const AValue: string; out ASeverity: TRuleSeverity): Boolean; static;
    /// <summary>Konfidenz aus dem Text ("low", "medium", "high").</summary>
    class function TryParseConfidence(const AValue: string; out AConfidence: TRuleConfidence): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Internals.JsonTree;

type
  TValidator = class
  private
    FText: string;
    FIssues: TList<TConfigurationIssue>;
    FSettings: TServerSettings;
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
    procedure ReadInlayHints(ANode: TJsonNode);
    procedure ReadCompiler(ANode: TJsonNode);
    procedure ReadCompletion(ANode: TJsonNode);
    procedure ReadCompleteBlocks(ANode: TJsonNode);
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
  FIssues := TList<TConfigurationIssue>.Create;
  FSettings := TServerSettings.Default;
end;

destructor TValidator.Destroy;
begin
  FIssues.Free;
  inherited;
end;

function TValidator.PositionAt(AOffset: Integer): TTextPosition;
var
  Index: Integer;
  Line: Integer;
  LineStart: Integer;
begin
  Line := 0;
  LineStart := 0;
  Index := 0;
  while (Index < AOffset) and (Index < Length(FText)) do
  begin
    if FText[Index + 1] = #13 then
    begin
      if (Index + 1 < Length(FText)) and (FText[Index + 2] = #10) then
        Inc(Index);
      Inc(Line);
      LineStart := Index + 1;
    end
    else if FText[Index + 1] = #10 then
    begin
      Inc(Line);
      LineStart := Index + 1;
    end;
    Inc(Index);
  end;
  Result := TTextPosition.Create(Line, AOffset - LineStart);
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

function TValidator.ParseRules(ANode: TJsonNode; const AName: string; out ARules: TArray<TRuleSetting>): Boolean;
var
  Index: Integer;
  Inner: Integer;
  Value: TJsonNode;
  Rule: TRuleSetting;
  Rules: TList<TRuleSetting>;
  Severity: TRuleSeverity;
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
      Rule.Id := ANode.Keys[Index];
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

procedure TValidator.ReadCompiler(ANode: TJsonNode);
var
  Index: Integer;
  Key: string;
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
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "compiler.%s"', [Key]), False);
  end;
end;

procedure TValidator.ReadCompleteBlocks(ANode: TJsonNode);
const
  Names: array[TBlockKind] of string = ('begin', 'try', 'case', 'record', 'class', 'repeat');
var
  Index: Integer;
  Key: string;
  Kind: TBlockKind;
  Known, Enabled: Boolean;
begin
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    ReportNode(ANode, '"completeBlocks" muss ein Objekt sein');
    Exit;
  end;
  for Index := 0 to ANode.Count - 1 do
  begin
    Key := ANode.Keys[Index];
    Known := False;
    for Kind := Low(TBlockKind) to High(TBlockKind) do
      if Key = Names[Kind] then
      begin
        Known := True;
        Enabled := Kind in FSettings.CompleteBlocks;
        if ExpectBoolean(ANode[Index], Key, Enabled) then
          if Enabled then
            Include(FSettings.CompleteBlocks, Kind)
          else
            Exclude(FSettings.CompleteBlocks, Kind);
      end;
    if not Known then
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "completeBlocks.%s"', [Key]), False);
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
    else
      Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2,
        Format('Unbekannte Einstellung "completion.%s"', [Key]), False);
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
            FSettings.DelphiVersion := BdsVersionOf(Text);
      end
      else if Key = 'language' then
      begin
        if ExpectString(Value, Key, Text) then
          if (Text = 'de') or (Text = 'en') then
            FSettings.Language := Text
          else
            ReportNode(Value, 'Erlaubt sind "de" und "en"');
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
      else if Key = 'exclude' then
        ReadExclude(Value)
      else if Key = 'minConfidence' then
      begin
        if ExpectString(Value, Key, Text) then
          if not TConfigurationParser.TryParseConfidence(Text, FSettings.MinConfidence) then
            ReportNode(Value, 'Erlaubt sind "low", "medium" und "high"');
      end
      else if Key = 'inlayHints' then
        ReadInlayHints(Value)
      else if Key = 'compiler' then
        ReadCompiler(Value)
      else if Key = 'completion' then
        ReadCompletion(Value)
      else if Key = 'completeBlocks' then
        ReadCompleteBlocks(Value)
      else if Key = 'usesCommand' then
        ExpectBoolean(Value, Key, FSettings.UsesCommand)
      else if Key = 'sortUses' then
        ExpectBoolean(Value, Key, FSettings.SortUses)
      else if Key = 'memoryBudgetMb' then
      begin
        if (Value.Kind = TJsonKind.Number) and TryStrToInt(Value.Value, Budget) and (Budget >= 0) then
          FSettings.MemoryBudgetMb := Budget
        else
          ReportNode(Value, '"memoryBudgetMb" muss eine ganze Zahl ab 0 sein');
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
      Result.DelphiVersion := FileSettings.DelphiVersion
    else if Key = 'language' then
      Result.Language := FileSettings.Language
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
    else if Key = 'exclude' then
      Result.Exclude := FileSettings.Exclude
    else if Key = 'minConfidence' then
      Result.MinConfidence := FileSettings.MinConfidence
    else if Key = 'format' then
    begin
      Result.Format := FileSettings.Format;
      Result.Formatting := FileSettings.Formatting;
    end
    else if Key = 'inlayHints' then
      Result.InlayHints := FileSettings.InlayHints
    else if Key = 'compiler' then
      Result.Compiler := FileSettings.Compiler
    else if Key = 'completion' then
      Result.Completion := FileSettings.Completion
    else if Key = 'completeBlocks' then
      Result.CompleteBlocks := FileSettings.CompleteBlocks
    else if Key = 'usesCommand' then
      Result.UsesCommand := FileSettings.UsesCommand
    else if Key = 'sortUses' then
      Result.SortUses := FileSettings.SortUses
    else if Key = 'memoryBudgetMb' then
      Result.MemoryBudgetMb := FileSettings.MemoryBudgetMb;
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
