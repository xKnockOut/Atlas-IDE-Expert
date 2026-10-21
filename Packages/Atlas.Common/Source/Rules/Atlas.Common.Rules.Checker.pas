unit Atlas.Common.Rules.Checker;

// Prüft einen Dateitext ohne Editor: Syntaxfehler des Parsers (Regel
// "syntax", immer Fehler mit hoher Konfidenz) und alle Prüfregeln über die
// Engine. Grundlage für den Kommandozeilen-Linter (#95).
// Für die Baseline (#97) liefert CheckText auf Wunsch die Routinen der Datei
// aus demselben Syntaxbaum mit, damit nicht zweimal geparst wird.
// Syntaxfehler und Regeln sehen nur die aktiven {$IFDEF}-Zweige (#845, #860),
// wie im Editor: TCheckSource bringt die Symbole des Projekts (Plattform,
// Konfiguration, .dproj-Defines), den Dateinamen und den Include-Resolver mit,
// damit $DEFINE aus {$I datei.inc} wirken. Ohne Angabe gelten die
// Vordefinitionen von Delphi 13 für Win32.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Baseline;

const
  SyntaxRuleId = 'syntax';

type
  /// <summary>Treffer einer geprüften Datei.</summary>
  TCheckedFile = record
    /// <summary>Pfad relativ zum Ordner der Konfiguration, mit "\" oder "/".</summary>
    Path: string;
    /// <summary>Vollständiger Pfad für SARIF (#95); '' = unbekannt, dann gilt Path.</summary>
    FullPath: string;
    Findings: TArray<TRuleFinding>;
    /// <summary>Für SARIF (#97): alle Treffer mit Fingerabdrücken und Zustand gegenüber der Baseline, samt der
    /// unveränderten und nicht mehr gefundenen. Leer = SARIF nimmt Findings ohne Fingerabdrücke.</summary>
    Marks: TArray<TBaselineMark>;
  end;

  /// <summary>Woher die Symbole einer geprüften Datei kommen (#860).</summary>
  TCheckSource = record
    /// <summary>Vollständiger Pfad der Datei; Ausgangspunkt für {$I}.</summary>
    FileName: string;
    /// <summary>Symbole des Projekts; leer = Vordefinitionen (Win32, Delphi 13).</summary>
    Defines: TArray<string>;
    /// <summary>Sucht {$I}-Dateien; nil = nicht lesen.</summary>
    ResolveInclude: TIncludeResolver;
    /// <summary>Ohne Projekt, Datei und Include-Dateien.</summary>
    class function Default: TCheckSource; static;
    class function Create(const AFileName: string; const ADefines: TArray<string>;
      const AResolveInclude: TIncludeResolver): TCheckSource; static;
    /// <summary>Präprozessor-Optionen wie beim Editor-Baum.</summary>
    function Options: TPreprocessorOptions;
  end;

  /// <summary>Quelle der Symbole je Datei, etwa aus dem Projekt des MCP-Servers.</summary>
  TCheckSourceFunc = reference to function(const AFileName: string): TCheckSource;

  TFileChecker = class
  public
    /// <summary>Beschreibung der eingebauten Syntaxprüfung.</summary>
    class function SyntaxDescriptor: TRuleDescriptor; static;
    /// <summary>Treffer für AText; leer, wenn ARelativePath global ausgeschlossen ist.</summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string): TArray<TRuleFinding>; overload; static;
    /// <summary>Wie oben, dazu die Routinen und Abschnitte der Datei (Baseline, #97).</summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; out AScopes: TFindingScopes): TArray<TRuleFinding>; overload; static;
    /// <summary>Wie oben mit den Symbolen und Include-Dateien aus ASource (#860).</summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; const ASource: TCheckSource): TArray<TRuleFinding>; overload; static;
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; const ASource: TCheckSource;
      out AScopes: TFindingScopes): TArray<TRuleFinding>; overload; static;
    /// <summary>ASource(AFileName), ohne Quelle TCheckSource.Default.</summary>
    class function SourceOf(const ASource: TCheckSourceFunc; const AFileName: string): TCheckSource; static;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Engine;

{ TCheckSource }

class function TCheckSource.Default: TCheckSource;
begin
  Result := Create('', nil, nil);
end;

class function TCheckSource.Create(const AFileName: string; const ADefines: TArray<string>;
  const AResolveInclude: TIncludeResolver): TCheckSource;
begin
  Result.FileName := AFileName;
  Result.Defines := ADefines;
  Result.ResolveInclude := AResolveInclude;
end;

function TCheckSource.Options: TPreprocessorOptions;
begin
  Result := TPascalPreprocessor.EditorOptions(Defines, FileName, ResolveInclude);
end;

{ TFileChecker }

class function TFileChecker.SyntaxDescriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SyntaxRuleId, TRuleSeverity.Error, 'Syntaxfehler des Parsers');
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string): TArray<TRuleFinding>;
var
  Scopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, TCheckSource.Default, Scopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; out AScopes: TFindingScopes): TArray<TRuleFinding>;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, TCheckSource.Default, AScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const ASource: TCheckSource): TArray<TRuleFinding>;
var
  Scopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, ASource, Scopes);
end;

class function TFileChecker.SourceOf(const ASource: TCheckSourceFunc; const AFileName: string): TCheckSource;
begin
  if Assigned(ASource) then
    Result := ASource(AFileName)
  else
    Result := TCheckSource.Default;
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const ASource: TCheckSource;
  out AScopes: TFindingScopes): TArray<TRuleFinding>;
var
  Tree: TSyntaxTree;
  Processed: TPreprocessorResult;
  Context: TRuleContext;
  Diagnostic: TSyntaxDiagnostic;
  Finding: TRuleFinding;
  Syntax: TArray<TRuleFinding>;
begin
  AScopes := TFindingScopes.FromTree(nil);
  if (ARelativePath <> '') and ASettings.IsExcluded(ARelativePath) then
    Exit(nil);
  // Baum nur aus den aktiven Zweigen wie im Editor: Inaktive Zweige erzeugen keine Syntaxfehler und keine
  // Regeltreffer.
  Tree := TPascalParser.ParseActive(AText, ASource.Options, nil, Processed);
  try
    AScopes := TFindingScopes.FromTree(Tree);
    Syntax := nil;
    if ASettings.RuleSeverity(SyntaxRuleId, TRuleSeverity.Error) <> TRuleSeverity.Off then
      for Diagnostic in Tree.Diagnostics do
      begin
        Finding := Default(TRuleFinding);
        Finding.RuleId := SyntaxRuleId;
        Finding.Range := TTextRange.Create(Diagnostic.StartPos, Diagnostic.EndPos);
        Finding.Message := Diagnostic.Message;
        Finding.Severity := ASettings.RuleSeverity(SyntaxRuleId, TRuleSeverity.Error);
        Finding.Confidence := TRuleConfidence.High;
        Syntax := Syntax + [Finding];
      end;
    Context := Default(TRuleContext);
    Context.RelativePath := ARelativePath;
    Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(ARelativePath, '/', '\', [rfReplaceAll])), '');
    Context.Text := AText;
    Context.Tree := Tree;
    Context.FileName := ASource.FileName;
    Result := Syntax + TRuleEngine.Run(ARules, ASettings, Context);
  finally
    Tree.Free;
  end;
end;

end.
