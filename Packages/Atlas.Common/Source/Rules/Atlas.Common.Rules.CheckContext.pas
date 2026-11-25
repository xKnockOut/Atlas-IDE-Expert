unit Atlas.Common.Rules.CheckContext;

// Was die Prüfregeln für ein Dokument brauchen (Regeln, Einstellungen, Baseline, Dienste, Umfeld der Datei)
// und der Lauf der Regeln darüber, mit dem gemeinsamen Speicher der Treffer (Atlas.Common.Findings.Memo).
// Die Komposition baut das Umfeld je Dokument; Diagnose, Code-Aktionen, Baselines und die Befehle des
// Sprachservers rechnen damit dieselben Treffer.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Findings.Memo,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Findings.Baseline;

type
  /// <summary>Was die Prüfregeln für ein Dokument brauchen.</summary>
  TRuleCheckContext = record
    Rules: TArray<IRule>;
    Settings: TServerSettings;
    /// <summary>Pfad relativ zum Ordner der Konfiguration, '' wenn unbekannt.</summary>
    RelativePath: string;
    /// <summary>Bekannte Treffer, die ausgeblendet werden (#97); nil = keine Baseline.</summary>
    Baseline: IRuleBaseline;
    /// <summary>Index, Nachladen, Unit-Suche, Packages, Projekte der Gruppe und Namenskonvention (#1112);
    /// derselbe Weg wie bei MCP und Linter.</summary>
    Services: TRuleServices;
    /// <summary>Formulardatei neben der Unit (#123); '' ohne.</summary>
    FormText: string;
    /// <summary>Pfad der Formulardatei (#309); '' ohne.</summary>
    FormFile: string;
    /// <summary>Dateien neben der Unit, z. B. .dcr (#114); nil = keine.</summary>
    ReadFile: TRuleFileReader;
    /// <summary>Gibt es eine Datei neben der Unit (#1379)? nil = unbekannt.</summary>
    FileExists: TRuleFileExists;
    /// <summary>Absoluter Pfad der Datei (#46).</summary>
    FileName: string;
    /// <summary>Anwendungsart des Projekts der Datei (#926); Unknown ohne Projekt.</summary>
    Application: TRuleApplicationKind;
    /// <summary>Name des Projekts ohne Endung (#943); '' ohne Projekt.</summary>
    ProjectName: string;
    /// <summary>Automatisch erzeugte Formulare in der Reihenfolge der .dpr (#956); nil ohne Projekt.</summary>
    AutoCreateForms: TArray<string>;
    /// <summary>Pfad der .dpr zu AutoCreateForms (#1055); '' ohne Projekt.</summary>
    ProjectMainSource: string;
    /// <summary>Abbruch zwischen den Prüfregeln; nil = nie. Setzt Compute.</summary>
    Cancelled: TRuleCancelled;
    /// <summary>Prüfung für den Editor (TRuleContext.Live, #896); die Komposition setzt es.</summary>
    Live: Boolean;
    /// <summary>Zuletzt gerechnete Treffer je Datei und Text: Die Diagnose legt ab, die Code-Aktion liest
    /// (2.0-stable); nil = keine.</summary>
    Memo: IRuleFindingsMemo;
    /// <summary>Treffer der Prüfregeln für AText (Baum ATree), ohne die Baseline abzuziehen; so prüft auch
    /// atlas.updateBaseline (#97). Leer ohne Regeln.</summary>
    function Findings(const AText: string; ATree: TSyntaxTree): TArray<TRuleFinding>;
    /// <summary>Wie Findings über Memo (#1761): Treffer am selben Text aus dem Memo, nach Warten auf einen
    /// laufenden Lauf am selben Text oder selbst gerechnet und abgelegt. Ohne Memo wie Findings.
    /// AWaitCancelled (nil = nie) beendet nur das Warten auf einen fremden Lauf (ERuleCheckCancelled).</summary>
    function SharedFindings(const AText: string; ATree: TSyntaxTree;
      const AWaitCancelled: TRuleCancelled): TArray<TRuleFinding>;
    /// <summary>Treffer aus Memo ohne eigenen Lauf (IRuleFindingsMemo.Await): abgelegte oder die eines laufenden
    /// Laufs am selben Text. False ohne beides. Ohne Memo, Dateiname oder Regeln wie Findings.</summary>
    function CachedFindings(const AText: string; ATree: TSyntaxTree; const AWaitCancelled: TRuleCancelled;
      out AFindings: TArray<TRuleFinding>): Boolean;
  end;

  /// <summary>Regeln und Einstellungen für AUri; False = keine Regeln prüfen. Hintergrund-Thread.</summary>
  TRuleContextProvider = reference to function(const AUri: string; out AContext: TRuleCheckContext): Boolean;

  TRuleContexts = class
  public
    /// <summary>Umfeld von AProvider für AUri; ohne eins (auch AProvider nil) die Vorgaben und False.</summary>
    class function Lookup(const AProvider: TRuleContextProvider; const AUri: string;
      out AContext: TRuleCheckContext): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Engine;

{ TRuleCheckContext }

function TRuleCheckContext.Findings(const AText: string; ATree: TSyntaxTree): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
begin
  if Length(Rules) = 0 then
  begin
    Exit(nil);
  end;
  mContext := Default(TRuleContext);
  mContext.RelativePath := RelativePath;
  mContext.UnitName := ChangeFileExt(ExtractFileName(StringReplace(RelativePath, '/', '\', [rfReplaceAll])), '');
  mContext.Text := AText;
  mContext.Tree := ATree;
  Services.ApplyTo(mContext);
  mContext.FormText := FormText;
  mContext.FormFile := FormFile;
  mContext.ReadFile := ReadFile;
  mContext.FileExists := FileExists;
  mContext.FileName := FileName;
  mContext.Application := Application;
  mContext.ProjectName := ProjectName;
  mContext.AutoCreateForms := AutoCreateForms;
  mContext.ProjectMainSource := ProjectMainSource;
  mContext.Cancelled := Cancelled;
  mContext.Live := Live;
  Result := TRuleEngine.Run(Rules, Settings, mContext);
end;

/// <summary>Lauf der Prüfregeln für Obtain.</summary>
function RuleRun(const AText: string; ATree: TSyntaxTree; const AContext: TRuleCheckContext): TRuleFindingsRun;
begin
  Result :=
    function: TArray<TRuleFinding>
    begin
      Result := AContext.Findings(AText, ATree);
    end;
end;

function TRuleCheckContext.SharedFindings(const AText: string; ATree: TSyntaxTree;
  const AWaitCancelled: TRuleCancelled): TArray<TRuleFinding>;
begin
  if (Memo = nil) or (FileName = '') or (Length(Rules) = 0) then
  begin
    Exit(Findings(AText, ATree));
  end;
  Result := Memo.Obtain(FileName, AText, RuleRun(AText, ATree, Self), AWaitCancelled);
end;

{ TRuleContexts }

class function TRuleContexts.Lookup(const AProvider: TRuleContextProvider; const AUri: string;
  out AContext: TRuleCheckContext): Boolean;
begin
  AContext := Default(TRuleCheckContext);
  Result := Assigned(AProvider) and AProvider(AUri, AContext);
  if not Result then
  begin
    AContext := Default(TRuleCheckContext);
  end;
end;

function TRuleCheckContext.CachedFindings(const AText: string; ATree: TSyntaxTree;
  const AWaitCancelled: TRuleCancelled; out AFindings: TArray<TRuleFinding>): Boolean;
begin
  if (Memo = nil) or (FileName = '') or (Length(Rules) = 0) then
  begin
    AFindings := Findings(AText, ATree);
    Exit(True);
  end;
  Result := Memo.Await(FileName, AText, AWaitCancelled, AFindings);
end;

end.
