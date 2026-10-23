unit Atlas.Common.Rules.Checker;

// Prüft einen Dateitext ohne Editor: Syntaxfehler des Parsers (Regel
// "syntax", Fehler mit hoher Konfidenz, Meldungen mit Compilercode, #1022) und alle Prüfregeln über die
// Engine. Grundlage für den Kommandozeilen-Linter (#95).
// Für die Baseline (#97) liefert CheckText auf Wunsch die Routinen der Datei
// aus demselben Syntaxbaum mit, damit nicht zweimal geparst wird.
// Gehört die Datei zu einem Package (contains einer .dpk), erfahren die Regeln
// das über TCheckProject (queue-nil-in-package, #943).
// Syntaxfehler und Regeln sehen nur die aktiven {$IFDEF}-Zweige (#845, #860),
// wie im Editor: TCheckSource bringt die Symbole des Projekts (Plattform,
// Konfiguration, .dproj-Defines), den Dateinamen und den Include-Resolver mit,
// damit $DEFINE aus {$I datei.inc} wirken. Ohne Angabe gelten die
// Vordefinitionen von Delphi 13 für Win32.
// Sprachmerkmale, die der Sprachstand des Projekts nicht kennt (#109), meldet die
// Regel "language-feature" (#1126); Maßstab ist die ältere aus delphiVersion und
// minDelphiVersion. Editor, Linter und MCP nutzen dieselbe Funktion.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Projects.PackageReader;

const
  SyntaxRuleId = 'syntax';
  LanguageFeatureRuleId = 'language-feature';

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

  /// <summary>Projekt einer geprüften Datei (#943); Default = unbekannt.</summary>
  TCheckProject = record
    Application: TRuleApplicationKind;
    /// <summary>Name ohne Endung, z. B. Atlas.IDE.Expert.</summary>
    Name: string;
    /// <summary>Automatisch erzeugte Formulare in der Reihenfolge der .dpr (#956).</summary>
    AutoCreateForms: TArray<string>;
    /// <summary>Absoluter Pfad der geprüften Datei (#1054); '' = unbekannt. Damit sehen die Regeln die
    /// Formulardatei daneben (FormText) und lesen Dateien neben der Unit (ReadFile) wie im Server.</summary>
    FileName: string;
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
    /// <summary>Syntaxfehler als Treffer der Regel "syntax" mit Schweregrad aus ASettings und den
    /// Korrekturen des Parsers (#1022); leer, wenn die Regel oder ihre Gruppe abgeschaltet ist.
    /// Gemeinsam für Linter, Diagnosen und Schnellkorrekturen im Editor.</summary>
    class function SyntaxFindings(const ADiagnostics: TArray<TSyntaxDiagnostic>;
      const ASettings: TServerSettings): TArray<TRuleFinding>; static;
    /// <summary>Beschreibung der Regel language-feature (#1126).</summary>
    class function LanguageFeatureDescriptor: TRuleDescriptor; static;
    /// <summary>Sprachmerkmale in ATree, die ALanguageLevel nicht kennt, als Treffer der Regel
    /// language-feature (#1126) mit Schweregrad aus ASettings; ohne die in AInactive beginnenden. Leer ohne
    /// gültigen Sprachstand oder wenn die Regel oder ihre Gruppe abgeschaltet ist.</summary>
    class function LanguageFeatureFindings(ATree: TSyntaxTree; const ASettings: TServerSettings;
      const ALanguageLevel: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>; static;
    /// <summary>Sprachstand für Prüfungen ohne Editor: die ältere aus delphiVersion und minDelphiVersion.
    /// </summary>
    class function LanguageLevelOf(const ASettings: TServerSettings): string; static;
    /// <summary>Treffer für AText; leer, wenn ARelativePath global ausgeschlossen ist.</summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string): TArray<TRuleFinding>; overload; static;
    /// <summary>Wie oben, dazu die Routinen und Abschnitte der Datei (Baseline, #97).</summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; out AScopes: TFindingScopes): TArray<TRuleFinding>; overload; static;
    /// <summary>Wie oben für eine Datei des Projekts AProject (#943).</summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; const AProject: TCheckProject): TArray<TRuleFinding>; overload; static;
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; const AProject: TCheckProject; out AScopes: TFindingScopes):
      TArray<TRuleFinding>; overload; static;
    /// <summary>Das Package aus APackages, dessen contains die Unit AUnitName nennt; sonst Default.</summary>
    class function PackageOf(const APackages: TArray<TPackageSource>; const AUnitName: string): TCheckProject;
      static;
    /// <summary>Wie oben mit den Symbolen und Include-Dateien aus ASource (#860).</summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; const ASource: TCheckSource): TArray<TRuleFinding>; overload; static;
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; const ASource: TCheckSource;
      out AScopes: TFindingScopes): TArray<TRuleFinding>; overload; static;
    /// <summary>ASource(AFileName), ohne Quelle TCheckSource.Default.</summary>
    class function SourceOf(const ASource: TCheckSourceFunc; const AFileName: string): TCheckSource; static;
    /// <summary>Wie oben mit Projekt (#943) und Symbolen (#860) zugleich; alle anderen Fassungen rufen diese.
    /// </summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; const AProject: TCheckProject; const ASource: TCheckSource;
      out AScopes: TFindingScopes): TArray<TRuleFinding>; overload; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Rules.Engine;

/// <summary>Formulardatei neben AFileName und Dateizugriff relativ zu ihrem Ordner, wie im Server (#1054).</summary>
procedure SetFiles(var AContext: TRuleContext; const AFileName: string);
var
  Folder, Extension: string;
  FileFormat: TFileFormat;
begin
  AContext.FileName := AFileName;
  if SameText(ExtractFileExt(AFileName), '.pas') then
    for Extension in TArray<string>.Create('.dfm', '.fmx') do
      if TFile.Exists(ChangeFileExt(AFileName, Extension)) then
      begin
        try
          AContext.FormText := TFileEncoding.LoadFromFile(ChangeFileExt(AFileName, Extension), FileFormat);
          AContext.FormFile := ChangeFileExt(AFileName, Extension);
        except
          on EInOutError do
            AContext.FormText := '';
          on EStreamError do
            AContext.FormText := '';
        end;
        Break;
      end;
  Folder := ExtractFilePath(AFileName);
  AContext.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(Folder, AName));
      if Result then
      try
        AData := TFile.ReadAllBytes(TPath.Combine(Folder, AName));
      except
        on EInOutError do
          Result := False;
        on EStreamError do
          Result := False;
      end;
    end;
end;

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

class function TFileChecker.SyntaxFindings(const ADiagnostics: TArray<TSyntaxDiagnostic>;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
var
  Diagnostic: TSyntaxDiagnostic;
  Finding: TRuleFinding;
  Severity: TRuleSeverity;
begin
  Result := nil;
  Severity := ASettings.RuleSeverity(SyntaxRuleId, TRuleSeverity.Error);
  // Auch Syntaxfehler gehören zu einer Gruppe (#909, seit #1022 „Compiler vorab“).
  if (Severity = TRuleSeverity.Off) or TRuleEngine.GroupOff(SyntaxRuleId, ASettings) then
    Exit;
  for Diagnostic in ADiagnostics do
  begin
    Finding := Default(TRuleFinding);
    Finding.RuleId := SyntaxRuleId;
    Finding.Range := TTextRange.Create(Diagnostic.StartPos, Diagnostic.EndPos);
    Finding.Message := Diagnostic.Message;
    Finding.Severity := Severity;
    Finding.Confidence := TRuleConfidence.High;
    if Diagnostic.FixTitle <> '' then
      Finding.Fixes := [TRuleFix.Create(Diagnostic.FixTitle, Diagnostic.FixEdits, Diagnostic.FixSafe)];
    Result := Result + [Finding];
  end;
end;

class function TFileChecker.LanguageFeatureDescriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LanguageFeatureRuleId, TRuleSeverity.Warning,
    'Sprachmerkmal einer neueren Delphi-Version');
end;

class function TFileChecker.LanguageFeatureFindings(ATree: TSyntaxTree; const ASettings: TServerSettings;
  const ALanguageLevel: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
var
  Feature: TLanguageFeatureFinding;
  Finding: TRuleFinding;
  Severity: TRuleSeverity;
begin
  Result := nil;
  Severity := ASettings.RuleSeverity(LanguageFeatureRuleId, TRuleSeverity.Warning);
  if (Severity = TRuleSeverity.Off) or TRuleEngine.GroupOff(LanguageFeatureRuleId, ASettings) then
    Exit;
  for Feature in TLanguageFeatures.Check(ATree, ALanguageLevel, AInactive) do
  begin
    Finding := Default(TRuleFinding);
    Finding.RuleId := LanguageFeatureRuleId;
    Finding.Range := TTextRange.Create(Feature.StartPos, Feature.EndPos);
    Finding.Message := Feature.Message;
    Finding.Severity := Severity;
    Finding.Confidence := TRuleConfidence.High;
    Result := Result + [Finding];
  end;
end;

class function TFileChecker.LanguageLevelOf(const ASettings: TServerSettings): string;
begin
  Result := TLanguageFeatures.LanguageLevel(ASettings.DelphiVersion, ASettings.MinDelphiVersion);
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
  Result := CheckText(ARules, ASettings, ARelativePath, AText, Default(TCheckProject), TCheckSource.Default,
    AScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const AProject: TCheckProject): TArray<TRuleFinding>;
var
  Scopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, AProject, TCheckSource.Default, Scopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const AProject: TCheckProject; out AScopes: TFindingScopes):
  TArray<TRuleFinding>;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, AProject, TCheckSource.Default, AScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const ASource: TCheckSource): TArray<TRuleFinding>;
var
  Scopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, Default(TCheckProject), ASource, Scopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const ASource: TCheckSource;
  out AScopes: TFindingScopes): TArray<TRuleFinding>;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, Default(TCheckProject), ASource, AScopes);
end;

class function TFileChecker.SourceOf(const ASource: TCheckSourceFunc; const AFileName: string): TCheckSource;
begin
  if Assigned(ASource) then
    Result := ASource(AFileName)
  else
    Result := TCheckSource.Default;
end;

class function TFileChecker.PackageOf(const APackages: TArray<TPackageSource>; const AUnitName: string):
  TCheckProject;
var
  Source: TPackageSource;
begin
  Result := Default(TCheckProject);
  for Source in APackages do
    if Source.IsPackage and (Source.ContainsIndex(AUnitName) >= 0) then
    begin
      Result.Application := TRuleApplicationKind.Package;
      Result.Name := Source.Name;
      Exit;
    end;
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const AProject: TCheckProject; const ASource: TCheckSource;
  out AScopes: TFindingScopes): TArray<TRuleFinding>;
var
  Tree: TSyntaxTree;
  Processed: TPreprocessorResult;
  Context: TRuleContext;
  Syntax: TArray<TRuleFinding>;
  FileName: string;
begin
  AScopes := TFindingScopes.FromTree(nil);
  if (ARelativePath <> '') and ASettings.IsExcluded(ARelativePath) then
    Exit(nil);
  // Baum nur aus den aktiven Zweigen wie im Editor: Inaktive Zweige erzeugen keine Syntaxfehler und keine
  // Regeltreffer.
  Tree := TSyntaxTreeCache.ParseActive(AText, ASource.Options, nil, Processed);
  try
    AScopes := TFindingScopes.FromTree(Tree);
    // Der Baum enthält nur die aktiven Zweige: Inaktive erzeugen keine Syntaxfehler.
    Syntax := SyntaxFindings(Tree.Diagnostics, ASettings) +
      LanguageFeatureFindings(Tree, ASettings, LanguageLevelOf(ASettings), nil);
    Context := Default(TRuleContext);
    Context.RelativePath := ARelativePath;
    Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(ARelativePath, '/', '\', [rfReplaceAll])), '');
    Context.Text := AText;
    Context.Tree := Tree;
    Context.Application := AProject.Application;
    Context.ProjectName := AProject.Name;
    Context.AutoCreateForms := AProject.AutoCreateForms;
    // Pfad aus dem Projekt (#1054), sonst aus der Symbolquelle (#860): Formulardatei und Nachbardateien.
    FileName := AProject.FileName;
    if FileName = '' then
      FileName := ASource.FileName;
    if FileName <> '' then
      SetFiles(Context, FileName);
    Result := Syntax + TRuleEngine.Run(ARules, ASettings, Context);
  finally
    Tree.Free;
  end;
end;

end.
