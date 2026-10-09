unit Argus.Common.Configuration.Contract;

// Contract des Platform-Features Configuration: die Einstellungen aus
// argus.json im Projektordner.
//
// Beispiel:
//   {
//     "delphiVersion": "37.0",
//     "language": "de",
//     "project": "App.dproj", "config": "Debug", "platform": "Win64",
//     "rules": { "unused-variable": "warning", "with-statement": { "severity": "off" } },
//     "exclude": ["ThirdParty/**", "Generated/*.pas"],
//     "format": { "indent": 2 }
//   }

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Argus.Common.Documents.Contract;

type
  /// <summary>Schweregrad einer Prüfregel; Default = Vorgabe der Regel.</summary>
  TRuleSeverity = (Default, Off, Hint, Information, Warning, Error);

  /// <summary>Beweislage eines Regeltreffers; begrenzt den Schweregrad.</summary>
  TRuleConfidence = (Low, Medium, High);

  TRuleSetting = record
    Id: string;
    Severity: TRuleSeverity;
    /// <summary>Weitere Optionen der Regel als JSON-Objekt (Text), sonst ''.</summary>
    Options: string;
  end;

  /// <summary>Inlay Hints im Editor (#35).</summary>
  TInlayHintSettings = record
    /// <summary>Parameternamen vor Argumenten.</summary>
    ParameterNames: Boolean;
    /// <summary>Abgeleiteter Typ bei var X := ….</summary>
    InferredTypes: Boolean;
    /// <summary>Hinter dem end langer Blöcke anzeigen, was dort endet.</summary>
    EndMarkers: Boolean;
    /// <summary>Mindestlänge eines Blocks in Zeilen für eine Endmarkierung.</summary>
    EndMarkerMinLines: Integer;
    class function Default: TInlayHintSettings; static;
  end;

  {$SCOPEDENUMS ON}
  TKeywordCase = (Preserve, Lower, Upper);
  /// <summary>Schlüssel im Block "format", die ausdrücklich gesetzt sind.</summary>
  TFormatKey = (IndentSize, UseTabs, KeywordCase, TrimTrailingWhitespace, InsertFinalNewline,
    SpaceAroundAssignment, SpaceAfterComma, EndOfLine);
  {$SCOPEDENUMS OFF}
  TFormatKeys = set of TFormatKey;

  /// <summary>Formatierung (#43). Given sagt, welche Werte aus argus.json bzw. dem
  /// Editor stammen; nur die haben Vorrang vor .editorconfig.</summary>
  TFormatStyle = record
    IndentSize: Integer;
    UseTabs: Boolean;
    KeywordCase: TKeywordCase;
    TrimTrailingWhitespace: Boolean;
    InsertFinalNewline: Boolean;
    /// <summary>Genau ein Leerzeichen vor und nach :=.</summary>
    SpaceAroundAssignment: Boolean;
    /// <summary>Genau ein Leerzeichen nach Kommas.</summary>
    SpaceAfterComma: Boolean;
    /// <summary>'' = beibehalten, sonst #10 oder #13#10.</summary>
    EndOfLine: string;
    Given: TFormatKeys;
    class function Default: TFormatStyle; static;
  end;

  /// <summary>Compiler-Anbindung (#40).</summary>
  TCompilerSettings = record
    /// <summary>Nach dem Speichern einer Quelldatei im Hintergrund kompilieren.</summary>
    OnSave: Boolean;
    class function Default: TCompilerSettings; static;
  end;

  TServerSettings = record
    /// <summary>Delphi-Version wie in der Registry, z. B. "37.0"; '' = passend zur ProjectVersion der .dproj, sonst neueste installierte (#47).</summary>
    DelphiVersion: string;
    /// <summary>Sprache der Meldungen, "de" oder "en".</summary>
    Language: string;
    /// <summary>Projektdatei relativ zum Ordner der Konfiguration; '' = automatisch suchen.</summary>
    Project: string;
    Config: string;
    Platform: string;
    Rules: TArray<TRuleSetting>;
    /// <summary>Treffer unter dieser Konfidenz werden ausgeblendet; Vorgabe Medium.</summary>
    MinConfidence: TRuleConfidence;
    /// <summary>Glob-Muster relativ zum Ordner der Konfiguration (*, **, ?).</summary>
    Exclude: TArray<string>;
    /// <summary>Formatierungsstil als JSON-Objekt (Text), sonst ''.</summary>
    Format: string;
    /// <summary>Ausgewerteter Block "format" (#43).</summary>
    Formatting: TFormatStyle;
    InlayHints: TInlayHintSettings;
    Compiler: TCompilerSettings;
    /// <summary>Obergrenze für den Symbolindex in MB; 0 = unbegrenzt (#185).</summary>
    MemoryBudgetMb: Integer;
    /// <summary>Vorgaben, wenn keine Konfigurationsdatei existiert.</summary>
    class function Default: TServerSettings; static;
    /// <summary>Schweregrad aus der Konfiguration oder ADefault.</summary>
    function RuleSeverity(const ARuleId: string; ADefault: TRuleSeverity): TRuleSeverity;
    /// <summary>True, wenn der Pfad (relativ zum Ordner der Konfiguration, "/" oder "\") ausgeschlossen ist.</summary>
    function IsExcluded(const ARelativePath: string): Boolean;
    /// <summary>True, wenn die Regel in "rules" steht und nicht abgeschaltet ist.</summary>
    function IsRuleEnabledExplicitly(const ARuleId: string): Boolean;
  end;

  /// <summary>Fehler oder Warnung beim Lesen der Konfiguration, mit Position in der Datei.</summary>
  TConfigurationIssue = record
    Range: TTextRange;
    Message: string;
    IsError: Boolean;
  end;

  TConfigurationChangedEvent = reference to procedure(const ASettings: TServerSettings);

const
  ConfigurationFileName = 'argus.json';
  /// <summary>Name vor der Umbenennung in Argus (#403); gilt, solange argus.json fehlt.</summary>
  LegacyConfigurationFileName = 'delphi-lsp.json';

/// <summary>True für argus.json und den früheren Namen (ohne Pfad, ohne Groß-/Kleinschreibung).</summary>
function IsConfigurationFileName(const AFileName: string): Boolean;

/// <summary>Pfad von AFileName im Ordner ADirectory. Fehlt die Datei und existiert nur
/// ALegacyFileName, dann dessen Pfad (Abwärtskompatibilität, #403).</summary>
function ExistingOrLegacyFile(const ADirectory, AFileName, ALegacyFileName: string): string;

/// <summary>Glob-Vergleich: * ohne Trenner, ** über Ordner, ? ein Zeichen; ohne Groß-/Kleinschreibung.</summary>
function MatchesGlob(const APattern, APath: string): Boolean;

implementation

function IsConfigurationFileName(const AFileName: string): Boolean;
begin
  Result := SameText(AFileName, ConfigurationFileName) or SameText(AFileName, LegacyConfigurationFileName);
end;

function ExistingOrLegacyFile(const ADirectory, AFileName, ALegacyFileName: string): string;
var
  Legacy: string;
begin
  Result := IncludeTrailingPathDelimiter(ADirectory) + AFileName;
  if FileExists(Result) then
    Exit;
  Legacy := IncludeTrailingPathDelimiter(ADirectory) + ALegacyFileName;
  if FileExists(Legacy) then
    Result := Legacy;
end;

function NormalizeSlashes(const APath: string): string;
begin
  Result := LowerCase(StringReplace(APath, '\', '/', [rfReplaceAll]));
  while (Result <> '') and (Result[1] = '/') do
    Delete(Result, 1, 1);
  if Copy(Result, 1, 2) = './' then
    Delete(Result, 1, 2);
end;

function MatchAt(const APattern: string; APatternIndex: Integer; const APath: string; APathIndex: Integer): Boolean;
var
  Index: Integer;
begin
  while APatternIndex <= Length(APattern) do
  begin
    case APattern[APatternIndex] of
      '*':
        begin
          if (APatternIndex < Length(APattern)) and (APattern[APatternIndex + 1] = '*') then
          begin
            // "**/" passt auch auf keinen Ordner.
            Inc(APatternIndex, 2);
            if (APatternIndex <= Length(APattern)) and (APattern[APatternIndex] = '/') then
            begin
              if MatchAt(APattern, APatternIndex + 1, APath, APathIndex) then
                Exit(True);
            end;
            for Index := APathIndex to Length(APath) + 1 do
              if MatchAt(APattern, APatternIndex, APath, Index) then
                Exit(True);
            Exit(False);
          end;
          Inc(APatternIndex);
          for Index := APathIndex to Length(APath) + 1 do
          begin
            if MatchAt(APattern, APatternIndex, APath, Index) then
              Exit(True);
            if (Index <= Length(APath)) and (APath[Index] = '/') then
              Exit(False);
          end;
          Exit(False);
        end;
      '?':
        begin
          if (APathIndex > Length(APath)) or (APath[APathIndex] = '/') then
            Exit(False);
          Inc(APatternIndex);
          Inc(APathIndex);
        end;
    else
      if (APathIndex > Length(APath)) or (APattern[APatternIndex] <> APath[APathIndex]) then
        Exit(False);
      Inc(APatternIndex);
      Inc(APathIndex);
    end;
  end;
  Result := APathIndex > Length(APath);
end;

function MatchesGlob(const APattern, APath: string): Boolean;
var
  Pattern: string;
begin
  Pattern := NormalizeSlashes(APattern);
  // Ein Ordnername ohne Platzhalter schließt alles darunter aus.
  if (Pattern <> '') and (Pattern[Length(Pattern)] = '/') then
    Pattern := Pattern + '**';
  Result := MatchAt(Pattern, 1, NormalizeSlashes(APath), 1) or
    ((Pos('*', Pattern) = 0) and (Pos('?', Pattern) = 0) and MatchAt(Pattern + '/**', 1, NormalizeSlashes(APath), 1));
end;

{ TInlayHintSettings }

class function TInlayHintSettings.Default: TInlayHintSettings;
begin
  Result.ParameterNames := True;
  Result.InferredTypes := True;
  Result.EndMarkers := True;
  Result.EndMarkerMinLines := 20;
end;

{ TFormatStyle }

class function TFormatStyle.Default: TFormatStyle;
begin
  Result.IndentSize := 2;
  Result.UseTabs := False;
  Result.KeywordCase := TKeywordCase.Preserve;
  Result.TrimTrailingWhitespace := True;
  Result.InsertFinalNewline := False;
  Result.SpaceAroundAssignment := True;
  Result.SpaceAfterComma := True;
  Result.EndOfLine := '';
  Result.Given := [];
end;

{ TCompilerSettings }

class function TCompilerSettings.Default: TCompilerSettings;
begin
  Result.OnSave := True;
end;

{ TServerSettings }

class function TServerSettings.Default: TServerSettings;
begin
  Result.DelphiVersion := '';
  Result.Language := 'de';
  Result.Project := '';
  Result.Config := '';
  Result.Platform := '';
  Result.Rules := nil;
  Result.MinConfidence := TRuleConfidence.Medium;
  Result.Exclude := nil;
  Result.Format := '';
  Result.Formatting := TFormatStyle.Default;
  Result.InlayHints := TInlayHintSettings.Default;
  Result.Compiler := TCompilerSettings.Default;
  Result.MemoryBudgetMb := 0;
end;

function TServerSettings.IsRuleEnabledExplicitly(const ARuleId: string): Boolean;
var
  Rule: TRuleSetting;
begin
  for Rule in Rules do
    if SameText(Rule.Id, ARuleId) then
      Exit(Rule.Severity <> TRuleSeverity.Off);
  Result := False;
end;

function TServerSettings.RuleSeverity(const ARuleId: string; ADefault: TRuleSeverity): TRuleSeverity;
var
  Rule: TRuleSetting;
begin
  for Rule in Rules do
    if SameText(Rule.Id, ARuleId) and (Rule.Severity <> TRuleSeverity.Default) then
      Exit(Rule.Severity);
  Result := ADefault;
end;

function TServerSettings.IsExcluded(const ARelativePath: string): Boolean;
var
  Pattern: string;
begin
  for Pattern in Exclude do
    if MatchesGlob(Pattern, ARelativePath) then
      Exit(True);
  Result := False;
end;

end.
