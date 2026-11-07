unit Atlas.Common.Rules.Checker;

// Prüft einen Dateitext ohne Editor: Syntaxfehler des Parsers (Regel
// "syntax", Fehler mit hoher Konfidenz, Meldungen mit Compilercode, #1022) und alle Prüfregeln über die
// Engine. Grundlage für den Kommandozeilen-Linter (#95).
// Für die Baseline (#97) liefert CheckText auf Wunsch die Routinen der Datei
// aus demselben Syntaxbaum mit, damit nicht zweimal geparst wird.
// Gehört die Datei zu einem Package (contains einer .dpk), erfahren die Regeln
// das über TCheckProject (queue-nil-in-package, #943). Den Symbolindex und die
// übrigen Projektdienste bringt TCheckProject.Services mit (#1112), wie im Server.
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
  cSyntaxRuleId = 'syntax';
  cLanguageFeatureRuleId = 'language-feature';

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
    /// <summary>Pfad der .dpr zu AutoCreateForms (#1055); '' = unbekannt.</summary>
    ProjectMainSource: string;
    /// <summary>Index und weitere Dienste des Projekts (#1112); Default = ohne Index.</summary>
    Services: TRuleServices;
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
  /// <summary>Projekt und Dienste (Index, #1112) je Datei, etwa aus den Arbeitsbereichen des MCP-Servers.</summary>
  TCheckProjectFunc = reference to function(const AFileName: string): TCheckProject;

  /// <summary>Herkunft einer geprüften Datei: Projekt (#943) und Symbole samt Include-Dateien (#860).</summary>
  TCheckOrigin = record
    Project: TCheckProject;
    Source: TCheckSource;
    class function Make(const AProject: TCheckProject; const ASource: TCheckSource): TCheckOrigin; static;
    /// <summary>Projekt und Quelle für AFileName aus AProject und ASource; nil wie TFileChecker.ProjectOf und
    /// TFileChecker.SourceOf.</summary>
    class function ForFile(const AProject: TCheckProjectFunc; const ASource: TCheckSourceFunc;
      const AFileName: string): TCheckOrigin; static;
  end;

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
    /// <summary>AProject(AFileName), ohne Quelle nur der Dateiname (ohne Index).</summary>
    class function ProjectOf(const AProject: TCheckProjectFunc; const AFileName: string): TCheckProject; static;
    /// <summary>Wie oben mit Projekt (#943) und Symbolen (#860) zugleich; alle anderen Fassungen rufen diese.
    /// </summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string; const AOrigin: TCheckOrigin; out AScopes: TFindingScopes):
      TArray<TRuleFinding>; overload; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TCheckerText = (SyntaxTitle, NewerFeatureTitle);

const
  cTexts: array[TCheckerText] of TAtlasText = (
    (De: 'Syntaxfehler des Parsers'; En: 'Syntax error of the parser'),
    (De: 'Sprachmerkmal einer neueren Delphi-Version'; En: 'Language feature of a newer Delphi version'));

{$SCOPEDENUMS OFF}

/// <summary>Formulardatei (.dfm, sonst .fmx) neben einer .pas-Datei; leer ohne oder wenn nicht lesbar.</summary>
procedure LoadForm(var AContext: TRuleContext; const AFileName: string);
var
  mExtension: string;
  mFileFormat: TFileFormat;
begin
  if not SameText(ExtractFileExt(AFileName), '.pas') then
  begin
    Exit;
  end;
  for mExtension in TArray<string>.Create('.dfm', '.fmx') do
  begin
    if TFile.Exists(ChangeFileExt(AFileName, mExtension)) then
    begin
      try
        AContext.FormText := TFileEncoding.LoadFromFile(ChangeFileExt(AFileName, mExtension), mFileFormat);
        AContext.FormFile := ChangeFileExt(AFileName, mExtension);
      except
        on EInOutError do
          AContext.FormText := '';
        on EStreamError do
          AContext.FormText := '';
      end;
      Exit;
    end;
  end;
end;

/// <summary>Liest Dateien relativ zu AFolder; False, wenn sie fehlen oder nicht lesbar sind.</summary>
function FolderReader(const AFolder: string): TRuleFileReader;
begin
  Result :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(AFolder, AName));
      if Result then
      try
        AData := TFile.ReadAllBytes(TPath.Combine(AFolder, AName));
      except
        on EInOutError do
          Result := False;
        on EStreamError do
          Result := False;
      end;
    end;
end;

/// <summary>Prüft, ob es eine Datei relativ zu AFolder gibt (fehlende Dateien aus {$I} und {$R}, #1379).</summary>
function FolderExists(const AFolder: string): TRuleFileExists;
begin
  Result :=
    function(const AName: string): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(AFolder, AName));
    end;
end;

/// <summary>Formulardatei neben AFileName und Dateizugriff relativ zu ihrem Ordner, wie im Server (#1054).</summary>
procedure SetFiles(var AContext: TRuleContext; const AFileName: string);
begin
  AContext.FileName := AFileName;
  LoadForm(AContext, AFileName);
  AContext.ReadFile := FolderReader(ExtractFilePath(AFileName));
  AContext.FileExists := FolderExists(ExtractFilePath(AFileName));
end;

{ TCheckOrigin }

class function TCheckOrigin.Make(const AProject: TCheckProject; const ASource: TCheckSource): TCheckOrigin;
begin
  Result.Project := AProject;
  Result.Source := ASource;
end;

class function TCheckOrigin.ForFile(const AProject: TCheckProjectFunc; const ASource: TCheckSourceFunc;
  const AFileName: string): TCheckOrigin;
begin
  Result := Make(TFileChecker.ProjectOf(AProject, AFileName), TFileChecker.SourceOf(ASource, AFileName));
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
  Result := TRuleDescriptor.Create(cSyntaxRuleId, TRuleSeverity.Error, cTexts[TCheckerText.SyntaxTitle].Text);
end;

class function TFileChecker.SyntaxFindings(const ADiagnostics: TArray<TSyntaxDiagnostic>;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
var
  mDiagnostic: TSyntaxDiagnostic;
  mFinding: TRuleFinding;
  mSeverity: TRuleSeverity;
begin
  Result := nil;
  mSeverity := ASettings.RuleSeverity(cSyntaxRuleId, TRuleSeverity.Error);
  // Auch Syntaxfehler gehören zu einer Gruppe (#909, seit #1022 „Compiler vorab“).
  if (mSeverity = TRuleSeverity.Off) or TRuleEngine.GroupOff(cSyntaxRuleId, ASettings) then
  begin
    Exit;
  end;
  for mDiagnostic in ADiagnostics do
  begin
    mFinding := Default(TRuleFinding);
    mFinding.RuleId := cSyntaxRuleId;
    mFinding.Range := TTextRange.Create(mDiagnostic.StartPos, mDiagnostic.EndPos);
    mFinding.Message := mDiagnostic.Message;
    mFinding.Severity := mSeverity;
    mFinding.Confidence := TRuleConfidence.High;
    if mDiagnostic.FixTitle <> '' then
    begin
      mFinding.Fixes := [TRuleFix.Create(mDiagnostic.FixTitle, mDiagnostic.FixEdits, mDiagnostic.FixSafe)];
    end;
    Result := Result + [mFinding];
  end;
end;

class function TFileChecker.LanguageFeatureDescriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLanguageFeatureRuleId, TRuleSeverity.Warning,
    cTexts[TCheckerText.NewerFeatureTitle].Text);
end;

class function TFileChecker.LanguageFeatureFindings(ATree: TSyntaxTree; const ASettings: TServerSettings;
  const ALanguageLevel: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
var
  mFeature: TLanguageFeatureFinding;
  mFinding: TRuleFinding;
  mSeverity: TRuleSeverity;
begin
  Result := nil;
  mSeverity := ASettings.RuleSeverity(cLanguageFeatureRuleId, TRuleSeverity.Warning);
  if (mSeverity = TRuleSeverity.Off) or TRuleEngine.GroupOff(cLanguageFeatureRuleId, ASettings) then
  begin
    Exit;
  end;
  for mFeature in TLanguageFeatures.Check(ATree, ALanguageLevel, AInactive) do
  begin
    // Bedingungsausdrücke meldet die Regel conditional-expression-version (#684) als Fehler mit Korrektur.
    if mFeature.Feature = TLanguageFeature.IfExpression then
    begin
      Continue;
    end;
    mFinding := Default(TRuleFinding);
    mFinding.RuleId := cLanguageFeatureRuleId;
    mFinding.Range := TTextRange.Create(mFeature.StartPos, mFeature.EndPos);
    mFinding.Message := mFeature.Message;
    mFinding.Severity := mSeverity;
    mFinding.Confidence := TRuleConfidence.High;
    Result := Result + [mFinding];
  end;
end;

class function TFileChecker.LanguageLevelOf(const ASettings: TServerSettings): string;
begin
  Result := TLanguageFeatures.LanguageLevel(ASettings.DelphiVersion, ASettings.MinDelphiVersion);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, TCheckSource.Default, mScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; out AScopes: TFindingScopes): TArray<TRuleFinding>;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText,
    TCheckOrigin.Make(Default(TCheckProject), TCheckSource.Default), AScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const AProject: TCheckProject): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText,
    TCheckOrigin.Make(AProject, TCheckSource.Default), mScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const AProject: TCheckProject; out AScopes: TFindingScopes):
  TArray<TRuleFinding>;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText,
    TCheckOrigin.Make(AProject, TCheckSource.Default), AScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const ASource: TCheckSource): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText,
    TCheckOrigin.Make(Default(TCheckProject), ASource), mScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const ASource: TCheckSource;
  out AScopes: TFindingScopes): TArray<TRuleFinding>;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText,
    TCheckOrigin.Make(Default(TCheckProject), ASource), AScopes);
end;

class function TFileChecker.SourceOf(const ASource: TCheckSourceFunc; const AFileName: string): TCheckSource;
begin
  if Assigned(ASource) then
  begin
    Result := ASource(AFileName);
  end
  else
  begin
    Result := TCheckSource.Default;
  end;
end;

class function TFileChecker.ProjectOf(const AProject: TCheckProjectFunc; const AFileName: string): TCheckProject;
begin
  if Assigned(AProject) then
  begin
    Result := AProject(AFileName);
  end
  else
  begin
    Result := Default(TCheckProject);
    Result.FileName := AFileName;
  end;
end;

class function TFileChecker.PackageOf(const APackages: TArray<TPackageSource>; const AUnitName: string):
  TCheckProject;
var
  mSource: TPackageSource;
begin
  Result := Default(TCheckProject);
  for mSource in APackages do
  begin
    if mSource.IsPackage and (mSource.ContainsIndex(AUnitName) >= 0) then
    begin
      Result.Application := TRuleApplicationKind.Package;
      Result.Name := mSource.Name;
      Exit;
    end;
  end;
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const AOrigin: TCheckOrigin; out AScopes: TFindingScopes):
  TArray<TRuleFinding>;
var
  mTree: TSyntaxTree;
  mProcessed: TPreprocessorResult;
  mContext: TRuleContext;
  mSyntax: TArray<TRuleFinding>;
  mFileName: string;
begin
  AScopes := TFindingScopes.FromTree(nil);
  if (ARelativePath <> '') and ASettings.IsExcluded(ARelativePath) then
  begin
    Exit(nil);
  end;
  // Baum nur aus den aktiven Zweigen wie im Editor: Inaktive Zweige erzeugen keine Syntaxfehler und keine
  // Regeltreffer.
  mTree := TSyntaxTreeCache.ParseActive(AText, AOrigin.Source.Options, nil, mProcessed);
  try
    AScopes := TFindingScopes.FromTree(mTree);
    // Der Baum enthält nur die aktiven Zweige: Inaktive erzeugen keine Syntaxfehler.
    mSyntax := SyntaxFindings(mTree.Diagnostics, ASettings) +
      LanguageFeatureFindings(mTree, ASettings, LanguageLevelOf(ASettings), nil);
    mContext := Default(TRuleContext);
    mContext.RelativePath := ARelativePath;
    mContext.UnitName := ChangeFileExt(ExtractFileName(StringReplace(ARelativePath, '/', '\', [rfReplaceAll])), '');
    mContext.Text := AText;
    mContext.Tree := mTree;
    // Inaktive Zweige für Regeln, die selbst über die Token gehen (unused-uses, #1352).
    mContext.InactiveRanges := TPascalPreprocessor.MainInactive(mProcessed);
    mContext.Application := AOrigin.Project.Application;
    mContext.ProjectName := AOrigin.Project.Name;
    mContext.AutoCreateForms := AOrigin.Project.AutoCreateForms;
    mContext.ProjectMainSource := AOrigin.Project.ProjectMainSource;
    // Index und Projektdienste auf demselben Weg wie im Server (#1112).
    AOrigin.Project.Services.ApplyTo(mContext);
    // Pfad aus dem Projekt (#1054), sonst aus der Symbolquelle (#860): Formulardatei und Nachbardateien.
    mFileName := AOrigin.Project.FileName;
    if mFileName = '' then
    begin
      mFileName := AOrigin.Source.FileName;
    end;
    if mFileName <> '' then
    begin
      SetFiles(mContext, mFileName);
    end;
    Result := mSyntax + TRuleEngine.Run(ARules, ASettings, mContext);
  finally
    mTree.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Checker', cTexts);

end.
