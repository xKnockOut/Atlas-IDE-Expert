unit BDLsp.Common.Configuration.Contract;

// Contract des Platform-Features Configuration: die Einstellungen aus
// delphi-lsp.json im Projektordner.
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
  BDLsp.Common.Documents.Contract;

type
  /// <summary>Schweregrad einer Prüfregel; Default = Vorgabe der Regel.</summary>
  TRuleSeverity = (Default, Off, Hint, Information, Warning, Error);

  TRuleSetting = record
    Id: string;
    Severity: TRuleSeverity;
    /// <summary>Weitere Optionen der Regel als JSON-Objekt (Text), sonst ''.</summary>
    Options: string;
  end;

  TServerSettings = record
    /// <summary>Delphi-Version wie in der Registry, z. B. "37.0"; '' = neueste installierte.</summary>
    DelphiVersion: string;
    /// <summary>Sprache der Meldungen, "de" oder "en".</summary>
    Language: string;
    /// <summary>Projektdatei relativ zum Ordner der Konfiguration; '' = automatisch suchen.</summary>
    Project: string;
    Config: string;
    Platform: string;
    Rules: TArray<TRuleSetting>;
    /// <summary>Glob-Muster relativ zum Ordner der Konfiguration (*, **, ?).</summary>
    Exclude: TArray<string>;
    /// <summary>Formatierungsstil als JSON-Objekt (Text), sonst ''.</summary>
    Format: string;
    /// <summary>Vorgaben, wenn keine Konfigurationsdatei existiert.</summary>
    class function Default: TServerSettings; static;
    /// <summary>Schweregrad aus der Konfiguration oder ADefault.</summary>
    function RuleSeverity(const ARuleId: string; ADefault: TRuleSeverity): TRuleSeverity;
    /// <summary>True, wenn der Pfad (relativ zum Ordner der Konfiguration, "/" oder "\") ausgeschlossen ist.</summary>
    function IsExcluded(const ARelativePath: string): Boolean;
  end;

  /// <summary>Fehler oder Warnung beim Lesen der Konfiguration, mit Position in der Datei.</summary>
  TConfigurationIssue = record
    Range: TTextRange;
    Message: string;
    IsError: Boolean;
  end;

  TConfigurationChangedEvent = reference to procedure(const ASettings: TServerSettings);

const
  ConfigurationFileName = 'delphi-lsp.json';

/// <summary>Glob-Vergleich: * ohne Trenner, ** über Ordner, ? ein Zeichen; ohne Groß-/Kleinschreibung.</summary>
function MatchesGlob(const APattern, APath: string): Boolean;

implementation

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

{ TServerSettings }

class function TServerSettings.Default: TServerSettings;
begin
  Result.DelphiVersion := '';
  Result.Language := 'de';
  Result.Project := '';
  Result.Config := '';
  Result.Platform := '';
  Result.Rules := nil;
  Result.Exclude := nil;
  Result.Format := '';
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
