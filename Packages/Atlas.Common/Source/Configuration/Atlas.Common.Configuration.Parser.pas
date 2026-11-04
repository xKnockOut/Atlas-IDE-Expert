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
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Configuration.Internals.Reader,
  Atlas.Common.Configuration.Internals.GeneralOptions,
  Atlas.Common.Configuration.Internals.RuleOptions,
  Atlas.Common.Configuration.Internals.McpOptions,
  Atlas.Common.Configuration.Internals.EditorOptions,
  Atlas.Common.Configuration.Internals.RefactoringOptions,
  Atlas.Common.Configuration.Internals.WorkflowOptions,
  Atlas.Common.Configuration.Internals.AnalysisOptions,
  Atlas.Common.Configuration.Internals.ProjectOptions;

/// <summary>Alle Abschnitte der obersten Ebene, je Thema in einer eigenen Unit.</summary>
function AllSections: TArray<TConfigurationSection>;
begin
  Result := GeneralSections + RuleSections + McpSections + EditorSections + RefactoringSections + WorkflowSections +
    AnalysisSections + ProjectSections;
end;

/// <summary>Abschnitt zum Schlüssel AKey; False, wenn es keinen gibt.</summary>
function FindSection(const ASections: TArray<TConfigurationSection>; const AKey: string;
  out ASection: TConfigurationSection): Boolean;
var
  mSection: TConfigurationSection;
begin
  for mSection in ASections do
  begin
    if mSection.Section = AKey then
    begin
      ASection := mSection;
      Exit(True);
    end;
  end;
  ASection := Default(TConfigurationSection);
  Result := False;
end;

/// <summary>Wurzel oder nil nach gemeldetem Syntaxfehler.</summary>
function ParseRoot(AReader: TConfigurationReader): TJsonNode;
begin
  try
    Result := TJsonTree.Parse(AReader.Text);
  except
    on E: EJsonTreeError do
    begin
      AReader.Report(E.Offset, E.Offset + 1, 'JSON-Fehler: ' + E.Message, True);
      Result := nil;
    end;
  end;
end;

/// <summary>Liest alle Schlüssel der Wurzel über ihre Abschnitte; unbekannte werden als Warnung gemeldet.</summary>
procedure ReadSections(AReader: TConfigurationReader; ARoot: TJsonNode; var ASettings: TServerSettings);
var
  mSections: TArray<TConfigurationSection>;
  mSection: TConfigurationSection;
  mIndex: Integer;
  mKey: string;
begin
  mSections := AllSections;
  for mIndex := 0 to ARoot.Count - 1 do
  begin
    mKey := ARoot.Keys[mIndex];
    if not FindSection(mSections, mKey, mSection) then
    begin
      AReader.Report(ARoot.KeyStarts[mIndex], ARoot.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Einstellung "%s"', [mKey]), False);
    end
    else if Assigned(mSection.Read) then
    begin
      mSection.Read(AReader, ARoot[mIndex], ASettings);
    end;
  end;
end;

/// <summary>Profilnamen erst prüfen, wenn auch "profiles" gelesen ist.</summary>
procedure CheckProfiles(AReader: TConfigurationReader; ARoot: TJsonNode; var ASettings: TServerSettings);
var
  mName: string;
  mProfile: TRuleProfile;
  mTestNode: TJsonNode;
begin
  for mName in TArray<string>.Create(ASettings.Profile, ASettings.CliProfile) do
  begin
    if (AReader.ProfileNode <> nil) and not ASettings.IsKnownProfile(mName) then
    begin
      AReader.ReportNode(AReader.ProfileNode, Format('Unbekanntes Profil "%s"; eingebaut: %s, sonst unter ' +
        '"profiles" anlegen', [mName, string.Join(', ', BuiltinProfileNames)]));
    end;
  end;
  mTestNode := AReader.TestProfileNode;
  if (mTestNode <> nil) and ASettings.IsKnownProfile(mTestNode.Value) then
  begin
    ASettings.TestProfile := mTestNode.Value;
  end
  else if mTestNode <> nil then
  begin
    AReader.ReportNode(mTestNode, Format('Unbekanntes Profil "%s"', [mTestNode.Value]));
  end;
  for mProfile in ASettings.Profiles do
  begin
    if not ASettings.IsKnownProfile(mProfile.Extends) then
    begin
      AReader.ReportNode(ARoot, Format('Profil "%s" erweitert das unbekannte Profil "%s"', [mProfile.Name,
        mProfile.Extends]));
    end;
  end;
end;

/// <summary>Liest AText in ASettings; Meldungen sammelt AReader.</summary>
procedure ReadConfiguration(AReader: TConfigurationReader; var ASettings: TServerSettings);
var
  mRoot: TJsonNode;
begin
  mRoot := ParseRoot(AReader);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    if mRoot.Kind <> TJsonKind.Object_ then
    begin
      AReader.ReportNode(mRoot, 'Die Konfiguration muss ein JSON-Objekt sein');
      Exit;
    end;
    ReadSections(AReader, mRoot, ASettings);
    CheckProfiles(AReader, mRoot, ASettings);
  finally
    mRoot.Free;
  end;
end;

{ TConfigurationParser }

class function TConfigurationParser.TryParseConfidence(const AValue: string;
  out AConfidence: TRuleConfidence): Boolean;
begin
  Result := TryParseRuleConfidence(AValue, AConfidence);
end;

class function TConfigurationParser.TryParseSeverity(const AValue: string; out ASeverity: TRuleSeverity): Boolean;
begin
  Result := TryParseRuleSeverity(AValue, ASeverity);
end;

// Schlüssel der obersten Ebene; leer bei Syntaxfehler.
function RootKeys(const AText: string): TArray<string>;
var
  mRoot: TJsonNode;
  mIndex: Integer;
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
        Result := Result + [mRoot.Keys[mIndex]];
      end;
    end;
  finally
    mRoot.Free;
  end;
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

/// <summary>Letzter Index des Schlüssels AKey in ANode; -1, wenn es ihn nicht gibt.</summary>
function LastKeyIndex(ANode: TJsonNode; const AKey: string): Integer;
begin
  Result := ANode.Count - 1;
  while (Result >= 0) and (ANode.Keys[Result] <> AKey) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Schlüssel der unteren Ebene, die die obere nicht setzt, mit ihrem Text.</summary>
function LowerOnlyParts(const ALowerText: string; ALower, AUpper: TJsonNode): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ALower.Count - 1 do
  begin
    if LastKeyIndex(AUpper, ALower.Keys[mIndex]) < 0 then
    begin
      Result := Result + [QuoteKey(ALower.Keys[mIndex]) + ': ' + NodeText(ALowerText, ALower[mIndex])];
    end;
  end;
end;

function MergeObjects(const ALowerText: string; ALower: TJsonNode; const AUpperText: string;
  AUpper: TJsonNode): string;
var
  mIndex, mOther: Integer;
  mParts: TArray<string>;
  mValue: string;
begin
  mParts := LowerOnlyParts(ALowerText, ALower, AUpper);
  for mIndex := 0 to AUpper.Count - 1 do
  begin
    mOther := LastKeyIndex(ALower, AUpper.Keys[mIndex]);
    if (mOther >= 0) and (ALower[mOther].Kind = TJsonKind.Object_) and (AUpper[mIndex].Kind = TJsonKind.Object_) then
    begin
      mValue := MergeObjects(ALowerText, ALower[mOther], AUpperText, AUpper[mIndex]);
    end
    else
    begin
      mValue := NodeText(AUpperText, AUpper[mIndex]);
    end;
    mParts := mParts + [QuoteKey(AUpper.Keys[mIndex]) + ': ' + mValue];
  end;
  Result := '{' + string.Join(', ', mParts) + '}';
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
  mFileSettings: TServerSettings;
  mIgnored: TArray<TConfigurationIssue>;
  mSections: TArray<TConfigurationSection>;
  mSection: TConfigurationSection;
  mKey: string;
begin
  AIssues := nil;
  mFileSettings := TServerSettings.Default;
  if AFileText <> '' then
  begin
    mFileSettings := Parse(AFileText, AIssues);
  end;
  if Trim(AEditorText) = '' then
  begin
    Exit(mFileSettings);
  end;
  // Unbekannte Schlüssel wie serverPath gehören dem Editor; ihre Meldungen entfallen.
  Result := Parse(AEditorText, mIgnored);
  mSections := AllSections;
  // Jeder Abschnitt, den die Datei setzt, hat Vorrang; wie, weiß der Abschnitt (rules je Regel-Id).
  for mKey in RootKeys(AFileText) do
  begin
    if FindSection(mSections, mKey, mSection) and Assigned(mSection.Take) then
    begin
      mSection.Take(mFileSettings, AFileText, Result);
    end;
  end;
end;

class function TConfigurationParser.Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings;
var
  mReader: TConfigurationReader;
begin
  Result := TServerSettings.Default;
  mReader := TConfigurationReader.Create(AText);
  try
    ReadConfiguration(mReader, Result);
    AIssues := mReader.Issues;
  finally
    mReader.Free;
  end;
end;

end.
