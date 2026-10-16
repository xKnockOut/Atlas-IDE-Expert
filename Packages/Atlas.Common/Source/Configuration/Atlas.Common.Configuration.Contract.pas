unit Atlas.Common.Configuration.Contract;

// Contract des Platform-Features Configuration: die Einstellungen aus
// atlas.json im Projektordner.
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
  Atlas.Common.Documents.Contract;

const
  /// <summary>Eingebaute Regelprofile (#146).</summary>
  BuiltinProfileNames: array[0..4] of string = ('standard', 'fast', 'strict', 'security', 'style');

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

  /// <summary>Regelprofil (#146): eingebaut (standard, fast, strict, security, style) oder
  /// eigenes aus "profiles", das ein eingebautes erweitern kann.</summary>
  TRuleProfile = record
    Name: string;
    /// <summary>Eingebautes oder eigenes Profil als Grundlage, '' = standard.</summary>
    Extends: string;
    /// <summary>Nur Regeln dieser Kategorien (bug, vulnerability, code-smell, security-hotspot); leer = alle.</summary>
    Categories: TArray<string>;
    Rules: TArray<TRuleSetting>;
  end;

  /// <summary>Pfadregel (#146): Schweregrade für Dateien, die eines der Muster treffen.
  /// Die Regel-ID "*" steht für alle Regeln.</summary>
  TPathOverride = record
    Files: TArray<string>;
    Rules: TArray<TRuleSetting>;
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

  /// <summary>Code Lens im Editor ("codeLens").</summary>
  TCodeLensSettings = record
    /// <summary>Kennzahlen über jeder Methode (#66): Länge, Tiefe, zyklomatische und kognitive Komplexität,
    /// Parameter.</summary>
    Metrics: Boolean;
    class function Default: TCodeLensSettings; static;
  end;

  /// <summary>Anzeige von XMLDoc in Hover und Detailpanel des Plugins (#654). Der Server bereitet die Doku
  /// immer vollständig auf und gibt die Werte nur weiter.</summary>
  THintSettings = record
  public const
    MaxXmlDocLines = 50;
  public
    /// <summary>XMLDoc vollständig und formatiert; aus = Kurzform (summary 4, remarks 3 Zeilen).</summary>
    XmlDocFull: Boolean;
    /// <summary>Doku-Zeilen, ab denen der Inhalt scrollt; 0 = unbegrenzt.</summary>
    XmlDocMaxLines: Integer;
    class function Default: THintSettings; static;
  end;

  /// <summary>Hervorheben zusammengehöriger Schlüsselwörter (#307).</summary>
  THighlightSettings = record
    /// <summary>Blockpaare (begin/end, try/finally …) und Routinen.</summary>
    BlockPairs: Boolean;
    /// <summary>Zusammengehörige {$IF…}/{$ELSE}/{$ENDIF} und Regionen.</summary>
    Directives: Boolean;
    /// <summary>Ausstiegspunkte einer Routine und Schleifenziele von Break/Continue.</summary>
    ExitPoints: Boolean;
    /// <summary>Was als Ausstiegspunkt gilt, z. B. Exit, raise, Abort, Halt.</summary>
    ExitKeywords: TArray<string>;
    class function Default: THighlightSettings; static;
  end;

  {$SCOPEDENUMS ON}
  TKeywordCase = (Preserve, Lower, Upper);
  /// <summary>Schlüssel im Block "format", die ausdrücklich gesetzt sind.</summary>
  TFormatKey = (IndentSize, UseTabs, KeywordCase, TrimTrailingWhitespace, InsertFinalNewline,
    SpaceAroundAssignment, SpaceAfterComma, EndOfLine);
  /// <summary>"stringLiteral.style" (#312).</summary>
  TStringLiteralStyle = (Auto, Multiline, Concat);
  /// <summary>"stringLiteral.lineBreak": Trenner zwischen verketteten Zeilen (#312).</summary>
  TStringLiteralBreak = (SLineBreak, CrLf, Lf, Space, None);
  {$SCOPEDENUMS OFF}
  TFormatKeys = set of TFormatKey;

  /// <summary>Klartext als String-Literal (#312).</summary>
  TStringLiteralSettings = record
    Style: TStringLiteralStyle;
    LineBreak: TStringLiteralBreak;
    /// <summary>Bei Verkettung lange Zeilen zusätzlich umbrechen; 0 = nicht umbrechen.</summary>
    MaxLineLength: Integer;
    class function Default: TStringLiteralSettings; static;
  end;

  /// <summary>Klassenmitglieder ordnen (#89).</summary>
  TMemberOrderSettings = record
    /// <summary>Sichtbarkeiten in Zielreihenfolge, z. B. 'strict private', 'private', 'public'.</summary>
    Sections: TArray<string>;
    /// <summary>Arten in Zielreihenfolge: field, constructor, destructor, method, property.</summary>
    Members: TArray<string>;
    /// <summary>Abschnitte mit Feldern dürfen die Reihenfolge der Felder (Speicherlayout) ändern.</summary>
    SortFields: Boolean;
    /// <summary>published-Abschnitte umsortieren (Streaming, Objektinspektor).</summary>
    SortPublished: Boolean;
    class function Default: TMemberOrderSettings; static;
  end;

  /// <summary>Testunits (#274, #189): Namensmuster, Ordner neuer Testunits und Testprojekt.</summary>
  TTestUnitSettings = record
    /// <summary>Name der Testunit; {unit} steht für den Namen der getesteten Unit.</summary>
    Pattern: string;
    /// <summary>Ordner neuer Testunits relativ zur Wurzel; leer = Ordner des Testprojekts.</summary>
    Folder: string;
    /// <summary>Testprojekt (.dproj oder .dpr) relativ zur Wurzel; leer = automatisch erkennen.</summary>
    Project: string;
    class function Default: TTestUnitSettings; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Bedingung einer Eigenschaftsregel für Formulardateien (#309).</summary>
  TDfmCondition = (Equal, NotEqual, Contains, NotContains, Empty, NotEmpty);

  /// <summary>Korrektur: auto gilt als sicher (source.fixAll), prompt nur als Code-Aktion, none gar nicht.</summary>
  TDfmFixMode = (Prompt, Auto, None);
  {$SCOPEDENUMS OFF}

  /// <summary>Eigenschaftsregel aus dfmPropertyRules (#309).</summary>
  TDfmPropertyRule = record
    ClassName: string;
    /// <summary>Property-Pfad, auch Font.Name.</summary>
    PropertyPath: string;
    Condition: TDfmCondition;
    Value: string;
    /// <summary>Meldung; '' = aus Klasse, Property, Bedingung und Wert gebildet.</summary>
    Message: string;
    Severity: TRuleSeverity;
    IncludeDescendants: Boolean;
    Fix: TDfmFixMode;
    /// <summary>Glob-Muster für Dateien, die die Regel nicht prüft.</summary>
    Exclude: TArray<string>;
  end;

  /// <summary>Formatierung (#43). Given sagt, welche Werte aus atlas.json bzw. dem
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

  /// <summary>Weg zum Compiler (#261): auto wählt nach der erkannten Ausgabe, dcc = Kommandozeilen-Compiler,
  /// ide = über eine eigene IDE (cc.ps1), off = nie kompilieren.</summary>
  {$SCOPEDENUMS ON}
  TCompilerBackendSetting = (Auto, Dcc, Ide, Off);
  {$SCOPEDENUMS OFF}

  /// <summary>Compiler-Anbindung (#40, #261).</summary>
  TCompilerSettings = record
    /// <summary>Nach dem Speichern einer Quelldatei im Hintergrund kompilieren; Vorgabe aus, weil das
    /// IDE-Plugin selbst prüfen kann (eine Auswahl „Nach dem Speichern“ in den Delphi-Optionen).
    /// Gilt nur für den Kommandozeilen-Compiler, nie für den Weg über die IDE (#261).</summary>
    OnSave: Boolean;
    /// <summary>compiler.backend (#261); Vorgabe Auto.</summary>
    Backend: TCompilerBackendSetting;
    /// <summary>compiler.ideCommand (#261): Pfad zu cc.ps1 für den Weg über die IDE; '' = nicht eingerichtet.</summary>
    IdeCommand: string;
    class function Default: TCompilerSettings; static;
  end;

  /// <summary>Auswahl der Vervollständigung (#229): unscharf oder nur nach Präfix.</summary>
  TCompletionMatching = (Fuzzy, Prefix);

  /// <summary>Abschnitt, in den „Interface implementieren“ die Deklarationen schreibt (#466).</summary>
  {$SCOPEDENUMS ON}
  TCompletionInterfaceSection = (Private, Protected, Public);
  /// <summary>Typumwandlung von Sender (#480): "(Sender as TButton)" oder "TButton(Sender)".</summary>
  TCompletionSenderCast = (AsOperator, HardCast);
  /// <summary>Freigabe im finally von „Freigabe absichern“ (#489): "List.Free" oder "FreeAndNil(List)".</summary>
  TCompletionFreeStyle = (Free, FreeAndNil);
  {$SCOPEDENUMS OFF}

  TCompletionSettings = record
    Matching: TCompletionMatching;
    InterfaceSection: TCompletionInterfaceSection;
    SenderCast: TCompletionSenderCast;
    /// <summary>Nach Übernahme eines Konstruktors try…finally anbieten (#489).</summary>
    OfferTryFinally: Boolean;
    FreeStyle: TCompletionFreeStyle;
    /// <summary>Schlüsselwörter passend zur Stelle vorschlagen (#31).</summary>
    Keywords: Boolean;
    /// <summary>Postfix-Vorlagen (.for, .notnil …) hinter Ausdrücken anbieten (#188).</summary>
    PostfixTemplates: Boolean;
    class function Default: TCompletionSettings; static;
  end;

  /// <summary>Gemeinsame Einstellungen für Code, den Atlas erzeugt (#50, #188).</summary>
  TRefactoringSettings = record
    /// <summary>Inline-Variablen (var X := …) erzeugen, wenn die Sprachversion sie kennt; sonst Eintrag im
    /// var-Abschnitt.</summary>
    InlineVar: Boolean;
    class function Default: TRefactoringSettings; static;
  end;

  TServerSettings = record
    /// <summary>Delphi-Version als BDS-Version der Registry, z. B. "37.0" (Produktnummern wie "12" werden
    /// beim Lesen umgerechnet, siehe BdsVersionOf); '' = passend zur ProjectVersion der .dproj, sonst neueste installierte (#47).</summary>
    DelphiVersion: string;
    /// <summary>Sprache der Meldungen, "de" oder "en".</summary>
    Language: string;
    /// <summary>Vorgabe-Codepage für Dateien ohne BOM, wenn die Erkennung nicht entscheidet (#121);
    /// 65001 = UTF-8 (Standard), sonst eine ANSI-Codepage wie 1250.</summary>
    DefaultEncoding: Integer;
    /// <summary>Projektdatei relativ zum Ordner der Konfiguration; '' = automatisch suchen.</summary>
    Project: string;
    Config: string;
    Platform: string;
    Rules: TArray<TRuleSetting>;
    /// <summary>Aktives Regelprofil im Editor, '' = standard (#146).</summary>
    Profile: string;
    /// <summary>Regelprofil der Kommandozeile, '' = wie Profile.</summary>
    CliProfile: string;
    /// <summary>Eigene Profile aus "profiles".</summary>
    Profiles: TArray<TRuleProfile>;
    /// <summary>Pfadregeln aus "overrides"; spätere Einträge haben Vorrang.</summary>
    Overrides: TArray<TPathOverride>;
    /// <summary>Test-Units und Testprojekte (DUnit, DUnitX) nicht prüfen.</summary>
    ExcludeTests: Boolean;
    /// <summary>Regelprofil für Test-Units und Testprojekte, '' = wie Profile.</summary>
    TestProfile: string;
    /// <summary>Treffer unter dieser Konfidenz werden ausgeblendet; Vorgabe Medium.</summary>
    MinConfidence: TRuleConfidence;
    /// <summary>"minConfidence" steht ausdrücklich in der Konfiguration und geht dem Profil vor (#146).</summary>
    MinConfidenceGiven: Boolean;
    /// <summary>Glob-Muster relativ zum Ordner der Konfiguration (*, **, ?).</summary>
    Exclude: TArray<string>;
    /// <summary>MCP-Werkzeuge, die der Server nicht anbietet (mcp.disabledTools, #99).</summary>
    McpDisabledTools: TArray<string>;
    /// <summary>MCP-Modus liest die globale settings.json (mcp.globalSettings, D-08); Vorgabe True.</summary>
    McpGlobalSettings: Boolean;
    /// <summary>Formatierungsstil als JSON-Objekt (Text), sonst ''.</summary>
    Format: string;
    /// <summary>Ausgewerteter Block "format" (#43).</summary>
    Formatting: TFormatStyle;
    InlayHints: TInlayHintSettings;
    CodeLens: TCodeLensSettings;
    Hints: THintSettings;
    Highlight: THighlightSettings;
    Compiler: TCompilerSettings;
    Completion: TCompletionSettings;
    Refactoring: TRefactoringSettings;
    /// <summary>Schnellbefehl "/uses Unit" nach Enter auswerten (#254); false wirkt wie "uses" in
    /// SlashCommandsDisabled.</summary>
    UsesCommand: Boolean;
    /// <summary>Kennzahlen überhaupt ("metrics", global): false schaltet die Code Lens der Kennzahlen und
    /// alle Regeln metric-* ab. Eine Regel, die das Projekt unter "rules" ausdrücklich setzt, gilt trotzdem.</summary>
    Metrics: Boolean;
    /// <summary>Schnellbefehle mit "/" überhaupt auswerten (#293).</summary>
    SlashCommands: Boolean;
    /// <summary>Abgeschaltete Schnellbefehle ohne "/", z. B. uses.</summary>
    SlashCommandsDisabled: TArray<string>;
    /// <summary>Vorlage für /header mit {unit}, {jahr}, {autor} (#306); '' = Vorlage der Regel file-header.</summary>
    SlashHeaderTemplate: string;
    /// <summary>"uses aufräumen" (source.organizeImports) sortiert alphabetisch; Vorgabe aus,
    /// weil die Reihenfolge die Initialisierung bestimmt (#182).</summary>
    SortUses: Boolean;
    /// <summary>Mit SortUses: nach Namespace gruppiert statt rein alphabetisch (#284).</summary>
    SortUsesByNamespace: Boolean;
    /// <summary>Units, die "ungenutzte uses entfernen" nie entfernt (#284).</summary>
    UsesKeep: TArray<string>;
    /// <summary>Klartext als String-Literal (#312).</summary>
    StringLiteral: TStringLiteralSettings;
    /// <summary>Klassenmitglieder ordnen (#89).</summary>
    MemberOrder: TMemberOrderSettings;
    /// <summary>Testunits anlegen und wechseln (#274, #189).</summary>
    TestUnits: TTestUnitSettings;
    /// <summary>Eigenschaftsregeln für Formulardateien (#309).</summary>
    DfmPropertyRules: TArray<TDfmPropertyRule>;
    /// <summary>Obergrenze für den Symbolindex in MB; 0 = unbegrenzt (#185).</summary>
    MemoryBudgetMb: Integer;
    /// <summary>Zeitlimit für Anfragen in ms (#283); länger laufende werden abgebrochen.</summary>
    RequestTimeoutMs: Integer;
    /// <summary>Anonymisiertes Diagnoselog (#647): schreiben, Aufbewahrung in Tagen und lokale
    /// Zuordnung Kurz-ID → Name (nur für die eigene Analyse).</summary>
    DiagnosticsLog: Boolean;
    DiagnosticsLogDays: Integer;
    DiagnosticsLogMapFile: Boolean;
    /// <summary>Umfang des Index (#648): alle Projekte der Projektgruppe, alle Units der Projekt-Suchpfade und
    /// der Bibliotheks- und Suchpfade der Installation; False = nur über uses erreichbare (bisher).</summary>
    IndexProjectGroup: Boolean;
    IndexSearchPaths: Boolean;
    IndexLibraryPaths: Boolean;
    /// <summary>Verwendungen der Bezeichner in Projekt-Units mit indizieren (#492, für #470).</summary>
    IndexUsages: Boolean;
    /// <summary>Glob-Muster gegen den vollen Pfad ("/" oder ""), die nicht indiziert werden, z. B. **/Demos/**.</summary>
    IndexExclude: TArray<string>;
    /// <summary>Protokoll (#265): Stufe (debug/info/warning/error), Logdatei und Mitschnitt.
    /// Der Server übernimmt sie nicht zur Laufzeit; der Client übergibt sie beim Start als
    /// --log-level, --log und --trace.</summary>
    LogLevel: string;
    LogFile: string;
    TraceFile: string;
    /// <summary>Versionsverwaltung (vcs.provider, #571): "auto", "git", "svn" oder "off".</summary>
    VcsProvider: string;
    /// <summary>True, wenn AFileName unter ein Muster aus IndexExclude fällt.</summary>
    function IsIndexExcluded(const AFileName: string): Boolean;
    /// <summary>Vorgaben, wenn keine Konfigurationsdatei existiert.</summary>
    class function Default: TServerSettings; static;
    /// <summary>Schweregrad aus der Konfiguration oder ADefault.</summary>
    function RuleSeverity(const ARuleId: string; ADefault: TRuleSeverity): TRuleSeverity;
    /// <summary>True, wenn der Pfad (relativ zum Ordner der Konfiguration, "/" oder "\") ausgeschlossen ist.</summary>
    function IsExcluded(const ARelativePath: string): Boolean;
    /// <summary>True, wenn die Regel in "rules" steht und nicht abgeschaltet ist.</summary>
    function IsRuleEnabledExplicitly(const ARuleId: string): Boolean;
    /// <summary>True für '', eingebaute Profile und Profile aus "profiles".</summary>
    function IsKnownProfile(const AName: string): Boolean;
    /// <summary>Eigenes Profil aus "profiles".</summary>
    function TryFindProfile(const AName: string; out AProfile: TRuleProfile): Boolean;
  end;

  /// <summary>Fehler oder Warnung beim Lesen der Konfiguration, mit Position in der Datei.</summary>
  TConfigurationIssue = record
    Range: TTextRange;
    Message: string;
    IsError: Boolean;
  end;

  TConfigurationChangedEvent = reference to procedure(const ASettings: TServerSettings);

const
  ConfigurationFileName = 'atlas.json';
  /// <summary>Name vor der Umbenennung in Atlas (#403); gilt, solange atlas.json fehlt.</summary>
  LegacyConfigurationFileName = 'delphi-lsp.json';

/// <summary>True für atlas.json und den früheren Namen (ohne Pfad, ohne Groß-/Kleinschreibung).</summary>
function IsConfigurationFileName(const AFileName: string): Boolean;

/// <summary>Pfad von AFileName im Ordner ADirectory. Fehlt die Datei und existiert nur
/// ALegacyFileName, dann dessen Pfad (Abwärtskompatibilität, #403).</summary>
function ExistingOrLegacyFile(const ADirectory, AFileName, ALegacyFileName: string): string;

/// <summary>Glob-Vergleich: * ohne Trenner, ** über Ordner, ? ein Zeichen; ohne Groß-/Kleinschreibung.</summary>
function MatchesGlob(const APattern, APath: string): Boolean;

/// <summary>
/// "delphiVersion" als BDS-Version der Registry: Produktnummern ("10.3", "11", "12", "13")
/// werden umgerechnet ("12" -> "23.0"), BDS-Versionen ab 14 bleiben. '' für ungültige Angaben.
/// </summary>
function BdsVersionOf(const AText: string): string;

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

function BdsVersionOf(const AText: string): string;
const
  // Produktnummer -> BDS-Version; 10.x über die Nachkommastelle.
  Products: array[0..7] of array[0..1] of string = (
    ('10', '17.0'), ('10.1', '18.0'), ('10.2', '19.0'), ('10.3', '20.0'), ('10.4', '21.0'),
    ('11', '22.0'), ('12', '23.0'), ('13', '37.0'));
var
  Text: string;
  Value: Double;
  Index: Integer;
begin
  Result := '';
  Text := Trim(AText);
  if not TryStrToFloat(Text, Value, TFormatSettings.Invariant) or (Value <= 0) then
    Exit;
  // BDS-Nummern nur bekannter Versionen: 14.0 (XE6) bis 23.0 (Delphi 12) und 37.0 (Delphi 13).
  // Andere Werte wie "99" sind ein Tippfehler und erzeugen eine Konfigurationswarnung (#109).
  if Value >= 14 then
  begin
    if ((Trunc(Value) >= 14) and (Trunc(Value) <= 23)) or (Trunc(Value) = 37) then
      Result := Text;
    Exit;
  end;
  // "12.0", "12.3" usw. meinen Delphi 12; nur bei 10 zählt die Nachkommastelle.
  if Trunc(Value) <> 10 then
    Text := IntToStr(Trunc(Value))
  else if Pos('.', Text) > 0 then
    Text := '10.' + Copy(Text, Pos('.', Text) + 1, 1);
  if Text = '10.0' then
    Text := '10';
  for Index := Low(Products) to High(Products) do
    if Products[Index][0] = Text then
      Exit(Products[Index][1]);
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

{ TCodeLensSettings }

class function TCodeLensSettings.Default: TCodeLensSettings;
begin
  Result.Metrics := True;
end;

{ TStringLiteralSettings }

class function TStringLiteralSettings.Default: TStringLiteralSettings;
begin
  Result.Style := TStringLiteralStyle.Auto;
  Result.LineBreak := TStringLiteralBreak.SLineBreak;
  Result.MaxLineLength := 0;
end;

{ TMemberOrderSettings }

class function TMemberOrderSettings.Default: TMemberOrderSettings;
begin
  Result.Sections := ['strict private', 'private', 'strict protected', 'protected', 'public', 'published'];
  Result.Members := ['field', 'constructor', 'destructor', 'method', 'property'];
  Result.SortFields := False;
  Result.SortPublished := False;
end;

{ TTestUnitSettings }

class function TTestUnitSettings.Default: TTestUnitSettings;
begin
  Result.Pattern := '{unit}.Tests';
  Result.Folder := '';
  Result.Project := '';
end;

{ THintSettings }

class function THintSettings.Default: THintSettings;
begin
  Result.XmlDocFull := True;
  Result.XmlDocMaxLines := 0;
end;

{ THighlightSettings }

class function THighlightSettings.Default: THighlightSettings;
begin
  Result.BlockPairs := True;
  Result.Directives := True;
  Result.ExitPoints := True;
  Result.ExitKeywords := ['Exit', 'raise', 'Abort', 'Halt'];
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
  Result.OnSave := False;
  Result.Backend := TCompilerBackendSetting.Auto;
  Result.IdeCommand := '';
end;

{ TRefactoringSettings }

class function TRefactoringSettings.Default: TRefactoringSettings;
begin
  Result.InlineVar := True;
end;

{ TCompletionSettings }

class function TCompletionSettings.Default: TCompletionSettings;
begin
  Result.Matching := TCompletionMatching.Fuzzy;
  Result.InterfaceSection := TCompletionInterfaceSection.Public;
  Result.SenderCast := TCompletionSenderCast.AsOperator;
  Result.OfferTryFinally := True;
  Result.FreeStyle := TCompletionFreeStyle.Free;
  Result.Keywords := True;
  Result.PostfixTemplates := True;
end;

{ TServerSettings }

class function TServerSettings.Default: TServerSettings;
begin
  Result.DelphiVersion := '';
  Result.Language := 'de';
  Result.DefaultEncoding := 65001;
  Result.Project := '';
  Result.Config := '';
  Result.Platform := '';
  Result.Rules := nil;
  Result.Profile := '';
  Result.CliProfile := '';
  Result.Profiles := nil;
  Result.Overrides := nil;
  Result.ExcludeTests := False;
  Result.TestProfile := '';
  Result.MinConfidenceGiven := False;
  Result.MinConfidence := TRuleConfidence.Medium;
  Result.Exclude := nil;
  Result.Format := '';
  Result.Formatting := TFormatStyle.Default;
  Result.InlayHints := TInlayHintSettings.Default;
  Result.CodeLens := TCodeLensSettings.Default;
  Result.Hints := THintSettings.Default;
  Result.Highlight := THighlightSettings.Default;
  Result.Compiler := TCompilerSettings.Default;
  Result.Completion := TCompletionSettings.Default;
  Result.Refactoring := TRefactoringSettings.Default;
  Result.UsesCommand := True;
  Result.Metrics := True;
  Result.SlashCommands := True;
  Result.SlashCommandsDisabled := nil;
  Result.SlashHeaderTemplate := '';
  Result.SortUses := False;
  Result.SortUsesByNamespace := False;
  Result.UsesKeep := nil;
  Result.StringLiteral := TStringLiteralSettings.Default;
  Result.MemberOrder := TMemberOrderSettings.Default;
  Result.TestUnits := TTestUnitSettings.Default;
  Result.DfmPropertyRules := nil;
  // Wie die Vorgabe des Plugins (#492): darüber zuerst Verwendungen auslagern.
  Result.MemoryBudgetMb := 768;
  Result.RequestTimeoutMs := 10000;
  Result.DiagnosticsLog := True;
  Result.DiagnosticsLogDays := 7;
  Result.DiagnosticsLogMapFile := False;
  Result.IndexProjectGroup := True;
  Result.McpGlobalSettings := True;
  Result.IndexSearchPaths := True;
  // Bibliothekspfade ganz zu indizieren dauert bei großen Installationen Minuten; nur auf Wunsch.
  Result.IndexLibraryPaths := False;
  Result.IndexUsages := True;
  Result.IndexExclude := nil;
  Result.LogLevel := 'info';
  Result.LogFile := '';
  Result.TraceFile := '';
  Result.VcsProvider := 'auto';
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

function TServerSettings.TryFindProfile(const AName: string; out AProfile: TRuleProfile): Boolean;
var
  Profile: TRuleProfile;
begin
  for Profile in Profiles do
    if SameText(Profile.Name, AName) then
    begin
      AProfile := Profile;
      Exit(True);
    end;
  // Nicht Default(…): innerhalb von TServerSettings träfe das die gleichnamige Klassenfunktion.
  AProfile.Name := '';
  AProfile.Extends := '';
  AProfile.Categories := nil;
  AProfile.Rules := nil;
  Result := False;
end;

function TServerSettings.IsKnownProfile(const AName: string): Boolean;
var
  Name: string;
  Profile: TRuleProfile;
begin
  if AName = '' then
    Exit(True);
  for Name in BuiltinProfileNames do
    if SameText(Name, AName) then
      Exit(True);
  Result := TryFindProfile(AName, Profile);
end;

function TServerSettings.IsIndexExcluded(const AFileName: string): Boolean;
var
  Pattern: string;
begin
  for Pattern in IndexExclude do
    if MatchesGlob(Pattern, AFileName) then
      Exit(True);
  Result := False;
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
