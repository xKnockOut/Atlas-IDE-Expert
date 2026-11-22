unit Atlas.Common.Findings.Contract;

// Contract des Platform-Features Findings: Befunde einer Prüfung als reine Werte, mit Korrekturen
// und weiteren Stellen. Prüfregeln erzeugen sie, Sprachserver, MCP und Ausgaben reichen sie weiter;
// keiner von ihnen muss dafür die Prüfregeln einbinden.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract;

type
  /// <summary>Edits einer weiteren Datei einer Korrektur (#1105).</summary>
  TRuleFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  /// <summary>Code-Aktion zu einem Treffer.</summary>
  TRuleFix = record
    Title: string;
    Edits: TArray<TTextEdit>;
    /// <summary>Sicher ohne Rückfrage anwendbar, z. B. beim Speichern über source.fixAll (#182).
    /// Jede Regel entscheidet das für ihre Korrekturen selbst.</summary>
    Safe: Boolean;
    /// <summary>Eine von mehreren gleichwertigen Korrekturen (#125): keine wird als bevorzugt angeboten.</summary>
    Alternative: Boolean;
    /// <summary>Datei, die die Edits ändern, z. B. die Formulardatei neben der Unit (#309);
    /// '' = die geprüfte Datei.</summary>
    FileName: string;
    /// <summary>Sprung statt Änderung (#915): der Client setzt den Cursor auf JumpTo in der geprüften Datei,
    /// z. B. zur Freigabe bei use-after-free. Edits bleiben leer.</summary>
    HasJump: Boolean;
    JumpTo: TTextPosition;
    /// <summary>Nach dem Sprung öffnet der Client den Parameter-Hint an JumpTo (#1007).</summary>
    OpensSignature: Boolean;
    /// <summary>Edits in weiteren Dateien zusätzlich zu FileName, z. B. Verwendungen eines öffentlichen Felds in
    /// anderen Units (#1105); nil = keine. Solche Korrekturen sind nie Safe.</summary>
    OtherFiles: TArray<TRuleFileEdits>;
    /// <summary>Aktion „Graph zeigen“ statt Änderung (#896): der Client öffnet die Unit-Beziehungen (#593) der
    /// geprüften Datei. Edits bleiben leer.</summary>
    ShowsUnitRelations: Boolean;
    constructor Create(const ATitle: string; const AEdits: TArray<TTextEdit>; ASafe: Boolean); overload;
    /// <summary>Wie oben mit ASafe = False.</summary>
    constructor Create(const ATitle: string; const AEdits: TArray<TTextEdit>); overload;
    /// <summary>Aktion, die nur zu ATarget springt (#915).</summary>
    class function Jump(const ATitle: string; const ATarget: TTextPosition): TRuleFix; static;
    /// <summary>Aktion, die zu ATarget (in den Klammern eines Aufrufs) springt und dort den Parameter-Hint öffnet
    /// (#1007).</summary>
    class function SignatureHelp(const ATitle: string; const ATarget: TTextPosition): TRuleFix; static;
    /// <summary>Aktion, die die Unit-Beziehungen der geprüften Datei zeigt (#896).</summary>
    class function UnitRelations(const ATitle: string): TRuleFix; static;
  end;

  /// <summary>Weitere Stelle zu einem Treffer (#896), beim Client als relatedInformation: z. B. der uses-Eintrag
  /// jeder Kante eines Unit-Zyklus. Message ist die Beschriftung im Befund-Hover.</summary>
  TRuleRelated = record
    FileName: string;
    Range: TTextRange;
    Message: string;
  end;

  /// <summary>Ein Treffer einer Regel. Severity setzt die Engine.</summary>
  TRuleFinding = record
    RuleId: string;
    Range: TTextRange;
    Message: string;
    Severity: TRuleSeverity;
    Confidence: TRuleConfidence;
    Fixes: TArray<TRuleFix>;
    /// <summary>Zusatz für den Befund-Hover, z. B. der durchsuchte Bereich (#1102); '' ohne.</summary>
    Details: string;
    /// <summary>Weitere Stellen (#896), z. B. die uses-Einträge eines Zyklus; nil ohne.</summary>
    Related: TArray<TRuleRelated>;
  end;

  /// <summary>Ein Befund für einen Auftrag an einen KI-Assistenten (#2570): Datei, wie sie im Text erscheint,
  /// Quelltext und Befund.</summary>
  TFindingPromptItem = record
    FileName: string;
    Text: string;
    Finding: TRuleFinding;
    /// <summary>Compilermeldung ohne Atlas-Regel: ohne Konfidenz und ohne Korrekturwerkzeug.</summary>
    Compiler: Boolean;
    class function Create(const AFinding: TRuleFinding; const AFileName, AText: string): TFindingPromptItem; static;
  end;

  /// <summary>True, wenn die Prüfung abgebrochen werden soll (Zeitlimit, Dokument geändert).</summary>
  TRuleCancelled = reference to function: Boolean;

  /// <summary>Die Prüfung wurde über TRuleCancelled abgebrochen; es gibt kein Ergebnis.</summary>
  ERuleCheckCancelled = class(Exception);

const
  /// <summary>Regel der ungenutzten uses (#1135); der Editor zeigt die Einträge selbst und fragt die Unterdrückung
  /// unter dieser Kennung. Gleich cUnusedUsesRuleId der Regel (Rules.Builtin.DeadCode, Test FindingIdsMatchRuleIds).
  /// </summary>
  cUnusedUsesFindingId = 'unused-uses';
  /// <summary>Regel der uses, die nur die implementation braucht (#1136); wie cUnusedUsesFindingId.</summary>
  cUsesOnlyInImplementationFindingId = 'uses-only-in-implementation';

/// <summary>Kennwort der Konfidenz: "hoch", "mittel", "niedrig".</summary>
function ConfidenceText(AConfidence: TRuleConfidence): string;
/// <summary>
///   Kennung der Konfidenz für Maschinen: "high", "medium", "low". Steht als
///   eigenes Feld neben der Meldung (LSP data.confidence, JSON, SARIF), nie im
///   Meldungstext (#144).
/// </summary>
function ConfidenceName(AConfidence: TRuleConfidence): string;

implementation

{ TFindingPromptItem }

class function TFindingPromptItem.Create(const AFinding: TRuleFinding;
  const AFileName, AText: string): TFindingPromptItem;
begin
  Result := Default(TFindingPromptItem);
  Result.Finding := AFinding;
  Result.FileName := AFileName;
  Result.Text := AText;
end;

function ConfidenceText(AConfidence: TRuleConfidence): string;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Result := 'niedrig';
    TRuleConfidence.Medium:
      Result := 'mittel';
  else
    Result := 'hoch';
  end;
end;

function ConfidenceName(AConfidence: TRuleConfidence): string;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Result := 'low';
    TRuleConfidence.Medium:
      Result := 'medium';
  else
    Result := 'high';
  end;
end;

{ TRuleFix }

constructor TRuleFix.Create(const ATitle: string; const AEdits: TArray<TTextEdit>; ASafe: Boolean);
begin
  Title := ATitle;
  Edits := AEdits;
  Safe := ASafe;
  Alternative := False;
  FileName := '';
  HasJump := False;
  JumpTo := Default(TTextPosition);
  // Ein Record-Konstruktor setzt nichts von selbst; ohne diese Zeilen trüge ein Sprung zufällig den
  // Parameter-Hint (#1007) oder Edits fremder Dateien (#1105).
  OpensSignature := False;
  OtherFiles := nil;
  ShowsUnitRelations := False;
end;

constructor TRuleFix.Create(const ATitle: string; const AEdits: TArray<TTextEdit>);
begin
  Self := TRuleFix.Create(ATitle, AEdits, False);
end;

class function TRuleFix.Jump(const ATitle: string; const ATarget: TTextPosition): TRuleFix;
begin
  Result := TRuleFix.Create(ATitle, nil);
  Result.HasJump := True;
  Result.JumpTo := ATarget;
end;

class function TRuleFix.SignatureHelp(const ATitle: string; const ATarget: TTextPosition): TRuleFix;
begin
  Result := Jump(ATitle, ATarget);
  Result.OpensSignature := True;
end;

class function TRuleFix.UnitRelations(const ATitle: string): TRuleFix;
begin
  Result := TRuleFix.Create(ATitle, nil);
  Result.ShowsUnitRelations := True;
end;

end.
