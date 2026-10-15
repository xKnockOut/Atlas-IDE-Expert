unit Atlas.Common.Rules.Checker;

// Prüft einen Dateitext ohne Editor: Syntaxfehler des Parsers (Regel
// "syntax", immer Fehler mit hoher Konfidenz) und alle Prüfregeln über die
// Engine. Grundlage für den Kommandozeilen-Linter (#95).
// Für die Baseline (#97) liefert CheckText auf Wunsch die Routinen der Datei
// aus demselben Syntaxbaum mit, damit nicht zweimal geparst wird.

interface

uses
  System.SysUtils,
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
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Engine;

class function TFileChecker.SyntaxDescriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SyntaxRuleId, TRuleSeverity.Error, 'Syntaxfehler des Parsers');
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
var
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Diagnostic: TSyntaxDiagnostic;
  Finding: TRuleFinding;
  Syntax: TArray<TRuleFinding>;
begin
  AScopes := TFindingScopes.FromTree(nil);
  if (ARelativePath <> '') and ASettings.IsExcluded(ARelativePath) then
    Exit(nil);
  Tree := TSyntaxTreeCache.Parse(AText);
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
    Result := Syntax + TRuleEngine.Run(ARules, ASettings, Context);
  finally
    Tree.Free;
  end;
end;

end.
