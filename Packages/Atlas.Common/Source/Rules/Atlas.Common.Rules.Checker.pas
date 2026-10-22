unit Atlas.Common.Rules.Checker;

// Prüft einen Dateitext ohne Editor: Syntaxfehler des Parsers (Regel
// "syntax", Fehler mit hoher Konfidenz, Meldungen mit Compilercode, #1022) und alle Prüfregeln über die
// Engine. Grundlage für den Kommandozeilen-Linter (#95).
// Für die Baseline (#97) liefert CheckText auf Wunsch die Routinen der Datei
// aus demselben Syntaxbaum mit, damit nicht zweimal geparst wird.
// Gehört die Datei zu einem Package (contains einer .dpk), erfahren die Regeln
// das über TCheckProject (queue-nil-in-package, #943).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Projects.PackageReader;

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

  /// <summary>Projekt einer geprüften Datei (#943); Default = unbekannt.</summary>
  TCheckProject = record
    Application: TRuleApplicationKind;
    /// <summary>Name ohne Endung, z. B. Atlas.IDE.Expert.</summary>
    Name: string;
    /// <summary>Automatisch erzeugte Formulare in der Reihenfolge der .dpr (#956).</summary>
    AutoCreateForms: TArray<string>;
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
  end;

implementation

uses
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Engine;

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

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string): TArray<TRuleFinding>;
var
  Scopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, Scopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; out AScopes: TFindingScopes): TArray<TRuleFinding>;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, Default(TCheckProject), AScopes);
end;

class function TFileChecker.CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath, AText: string; const AProject: TCheckProject): TArray<TRuleFinding>;
var
  Scopes: TFindingScopes;
begin
  Result := CheckText(ARules, ASettings, ARelativePath, AText, AProject, Scopes);
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
  const ARelativePath, AText: string; const AProject: TCheckProject; out AScopes: TFindingScopes):
  TArray<TRuleFinding>;
var
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Syntax: TArray<TRuleFinding>;
  Active: TArray<TSyntaxDiagnostic>;
begin
  AScopes := TFindingScopes.FromTree(nil);
  if (ARelativePath <> '') and ASettings.IsExcluded(ARelativePath) then
    Exit(nil);
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    AScopes := TFindingScopes.FromTree(Tree);
    // Inaktive Zweige der bedingten Kompilierung erzeugen keine Syntaxfehler.
    if not TPascalParser.ActiveDiagnostics(AText, nil, Active) then
      Active := Tree.Diagnostics;
    Syntax := SyntaxFindings(Active, ASettings);
    Context := Default(TRuleContext);
    Context.RelativePath := ARelativePath;
    Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(ARelativePath, '/', '\', [rfReplaceAll])), '');
    Context.Text := AText;
    Context.Tree := Tree;
    Context.Application := AProject.Application;
    Context.ProjectName := AProject.Name;
    Context.AutoCreateForms := AProject.AutoCreateForms;
    Result := Syntax + TRuleEngine.Run(ARules, ASettings, Context);
  finally
    Tree.Free;
  end;
end;

end.
