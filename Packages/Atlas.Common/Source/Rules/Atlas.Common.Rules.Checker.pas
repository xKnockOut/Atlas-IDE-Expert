unit Atlas.Common.Rules.Checker;

// Prüft einen Dateitext ohne Editor: Syntaxfehler des Parsers (Regel
// "syntax", immer Fehler mit hoher Konfidenz) und alle Prüfregeln über die
// Engine. Grundlage für den Kommandozeilen-Linter (#95).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract;

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
  end;

  TFileChecker = class
  public
    /// <summary>Beschreibung der eingebauten Syntaxprüfung.</summary>
    class function SyntaxDescriptor: TRuleDescriptor; static;
    /// <summary>Treffer für AText; leer, wenn ARelativePath global ausgeschlossen ist.</summary>
    class function CheckText(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AText: string): TArray<TRuleFinding>; static;
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
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Diagnostic: TSyntaxDiagnostic;
  Finding: TRuleFinding;
  Syntax: TArray<TRuleFinding>;
begin
  if (ARelativePath <> '') and ASettings.IsExcluded(ARelativePath) then
    Exit(nil);
  Tree := TSyntaxTreeCache.Parse(AText);
  try
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
