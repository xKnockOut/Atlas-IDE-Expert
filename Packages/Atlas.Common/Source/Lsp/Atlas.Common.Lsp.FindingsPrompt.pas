unit Atlas.Common.Lsp.FindingsPrompt;

// Auftrag für einen KI-Assistenten aus markierten Befunden (#2570), Fenster „Atlas-Prüfung“ „Als Auftrag für
// KI-Assistenten kopieren“.
//
// Befehl atlas.server.findingsPrompt über workspace/executeCommand:
//   Argumente [{"findings": [{"file": Pfad, "line": Zeile ab 0, "character": Spalte ab 0, "rule": Regel bzw.
//   Meldungsnummer, "message": Meldung, "severity": "error" | "warning" | "info" | "hint", "compiler": true bei
//   Compilermeldungen}, …], "limit": Höchstzahl (optional, Vorgabe TFindingPrompt.cDefaultLimit)}].
//   Antwort {"text": Markdown aus TFindingPrompt.Many, "count": Anzahl Befunde}.
// Den Text liest der Server wie die Prüfung (offene Dokumente vor der Platte), damit Zeilennummern zum Editor
// passen. Jede Datei wird einmal geprüft; ein Befund derselben Regel in derselben Zeile liefert Konfidenz und weitere
// Stellen (#896). Fehlt er (Compilermeldung, inzwischen geänderter Text), gelten die Angaben des Plugins.
// Schreibt nichts.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Lsp.Baseline;

type
  TLspFindingsPrompt = class
  public const
    cCommand = 'atlas.server.findingsPrompt';
  private
    FCheckFor: TLspBaselineCheckFunc;
    FReadText: TLspBaselineRead;
  public
    /// <summary>ACheckFor prüft eine Datei wie der Editor (nur Pascal-Quelltext), AReadText liest jede andere.
    /// </summary>
    constructor Create(const ACheckFor: TLspBaselineCheckFunc; const AReadText: TLspBaselineRead);
    /// <summary>Befehl atlas.server.findingsPrompt; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFindingsPromptText = (Arguments);

const
  cTexts: array[TFindingsPromptText] of TAtlasText = (
    (De: 'Argumente: [{"findings": [{"file", "line", "character", "rule", "message", "severity"}, …]}]';
     En: 'Arguments: [{"findings": [{"file", "line", "character", "rule", "message", "severity"}, …]}]'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Geprüfte bzw. gelesene Datei: Pfad für den Auftrag, Text und Befunde der Prüfung.</summary>
  TPromptSource = record
    Read: Boolean;
    Check: TLspBaselineCheck;
  end;

{ TLspFindingsPrompt }

constructor TLspFindingsPrompt.Create(const ACheckFor: TLspBaselineCheckFunc; const AReadText: TLspBaselineRead);
begin
  inherited Create;
  FCheckFor := ACheckFor;
  FReadText := AReadText;
end;

/// <summary>Befund aus den Angaben des Plugins.</summary>
function ClientFinding(AItem: TJSONObject): TRuleFinding;
var
  mLine, mCharacter: Integer;
  mSeverity: TRuleSeverity;
begin
  Result := Default(TRuleFinding);
  mLine := AItem.GetValue<Integer>('line', 0);
  mCharacter := AItem.GetValue<Integer>('character', 0);
  Result.Range := TTextRange.Create(mLine, mCharacter, mLine, mCharacter);
  Result.RuleId := AItem.GetValue<string>('rule', '');
  Result.Message := AItem.GetValue<string>('message', '');
  Result.Confidence := TRuleConfidence.High;
  Result.Severity := TRuleSeverity.Warning;
  if TConfigurationParser.TryParseSeverity(AItem.GetValue<string>('severity', ''), mSeverity) then
  begin
    Result.Severity := mSeverity;
  end;
end;

/// <summary>Befund der Prüfung mit derselben Regel in derselben Zeile; False ohne.</summary>
function TryChecked(const AFindings: TArray<TRuleFinding>; const AClient: TRuleFinding;
  out AFinding: TRuleFinding): Boolean;
var
  mFinding: TRuleFinding;
begin
  for mFinding in AFindings do
  begin
    if SameText(mFinding.RuleId, AClient.RuleId) and
      (mFinding.Range.StartPos.Line = AClient.Range.StartPos.Line) then
    begin
      AFinding := mFinding;
      Exit(True);
    end;
  end;
  AFinding := Default(TRuleFinding);
  Result := False;
end;

/// <summary>Text und Befunde von AFileName, je Datei einmal geprüft bzw. gelesen.</summary>
function SourceOf(const ACheckFor: TLspBaselineCheckFunc; const AReadText: TLspBaselineRead;
  const AFileName: string; ASources: TDictionary<string, TPromptSource>): TPromptSource;
begin
  if ASources.TryGetValue(AFileName, Result) then
  begin
    Exit;
  end;
  Result := Default(TPromptSource);
  Result.Read := Assigned(ACheckFor) and ACheckFor(AFileName, Result.Check);
  if not Result.Read then
  begin
    Result.Check := Default(TLspBaselineCheck);
    Result.Read := Assigned(AReadText) and AReadText(AFileName, Result.Check.Text);
  end;
  ASources.Add(AFileName, Result);
end;

/// <summary>Eintrag für den Auftrag: Befund der Prüfung, sonst die Angaben des Plugins; Pfad relativ zur
/// Konfiguration, wenn bekannt.</summary>
function ItemOf(const ACheckFor: TLspBaselineCheckFunc; const AReadText: TLspBaselineRead; AItem: TJSONObject;
  ASources: TDictionary<string, TPromptSource>): TFindingPromptItem;
var
  mFileName: string;
  mSource: TPromptSource;
  mClient, mFinding: TRuleFinding;
begin
  mFileName := AItem.GetValue<string>('file', '');
  mSource := SourceOf(ACheckFor, AReadText, mFileName, ASources);
  Result := Default(TFindingPromptItem);
  Result.Compiler := AItem.GetValue<Boolean>('compiler', False);
  mClient := ClientFinding(AItem);
  Result.Finding := mClient;
  if TryChecked(mSource.Check.Findings, mClient, mFinding) then
  begin
    Result.Finding := mFinding;
  end;
  Result.Text := mSource.Check.Text;
  Result.FileName := mSource.Check.RelativePath;
  if Result.FileName = '' then
  begin
    Result.FileName := mFileName;
  end;
end;

function TLspFindingsPrompt.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mArguments: TJSONObject;
  mFindings: TJSONArray;
  mSources: TDictionary<string, TPromptSource>;
  mItems: TArray<TFindingPromptItem>;
  mValue: TJSONValue;
  mAnswer: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONObject) or
    not (TJSONObject(AArguments.Items[0]).GetValue('findings') is TJSONArray) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TFindingsPromptText.Arguments].Text);
  end;
  mArguments := TJSONObject(AArguments.Items[0]);
  mFindings := TJSONArray(mArguments.GetValue('findings'));
  mItems := nil;
  mSources := TDictionary<string, TPromptSource>.Create;
  try
    for mValue in mFindings do
    begin
      if mValue is TJSONObject then
      begin
        mItems := mItems + [ItemOf(FCheckFor, FReadText, TJSONObject(mValue), mSources)];
      end;
    end;
  finally
    mSources.Free;
  end;
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('text', TFindingPrompt.Many(mItems, TFindingPrompt.SharedCatalog, TFindingPrompt.cDefaultContext,
    mArguments.GetValue<Integer>('limit', TFindingPrompt.cDefaultLimit)));
  mAnswer.AddPair('count', TJSONNumber.Create(Length(mItems)));
  Result := mAnswer;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.FindingsPrompt', cTexts);

end.
