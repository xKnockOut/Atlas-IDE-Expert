unit Atlas.Tests.RuleAssert;

// Testhilfe für Prüfregeln: parst einen Quelltext, führt eine Regel über die
// Engine aus und prüft Treffer. Jede Regel braucht mindestens einen
// positiven (Treffer) und einen negativen Testfall (kein Treffer).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract;

type
  // ARule ohne const: Tests übergeben TXyzRule.Create direkt. Bei const zählt
  // niemand die Referenz, und das temporäre Array in TRuleEngine.Run gibt die
  // Regel frei, bevor sie hier weiter benutzt wird (Zugriffsverletzung).
  TRuleAssert = class
  public
    /// <summary>Treffer von ARule auf ASource mit Einstellungen aus AConfigJson ('' = Vorgaben).</summary>
    class function Findings(ARule: IRule; const ASource: string): TArray<TRuleFinding>; overload; static;
    class function Findings(ARule: IRule; const ASource: string; const AConfigJson: string): TArray<TRuleFinding>;
      overload; static;
    class function Findings(ARule: IRule; const ASource: string;
      const AConfigJson: string; const ARelativePath: string): TArray<TRuleFinding>; overload; static;
    /// <summary>Treffer von ARule auf ASource, gelesen wie im Editor mit den Symbolen der Plattform APlatform
    /// ("Win32", "Win64"; TSyntaxTree.Platform, #1380).</summary>
    class function PlatformFindings(ARule: IRule; const ASource, APlatform: string): TArray<TRuleFinding>; static;
    /// <summary>Treffer von ARule auf ASource in einem Projekt der Anwendungsart AApplication (#926).</summary>
    class function ApplicationFindings(ARule: IRule; const ASource: string;
      AApplication: TRuleApplicationKind): TArray<TRuleFinding>; static;
    /// <summary>Treffer von ARule auf ASource als Unit des Packages AProjectName (#943) mit Einstellungen aus
    /// AConfigJson ('' = Vorgaben) unter ARelativePath.</summary>
    class function PackageFindings(ARule: IRule; const ASource, AProjectName, AConfigJson,
      ARelativePath: string): TArray<TRuleFinding>; static;
    /// <summary>Treffer von ARule auf ASource mit der Formulardatei AFormText daneben (#123).</summary>
    class function FormFindings(const ARule: IRule; const ASource, AFormText: string): TArray<TRuleFinding>;
      overload; static;
    /// <summary>Wie FormFindings, mit Einstellungen aus AConfigJson (z. B. für Regeln, die aus sind).</summary>
    class function FormFindings(const ARule: IRule; const ASource, AFormText, AConfigJson: string):
      TArray<TRuleFinding>; overload; static;
    /// <summary>Treffer von ARule auf ASource als Unit eines Projekts, dessen .dpr die Formulare AForms in dieser
    /// Reihenfolge erzeugt (#956), mit Formulardatei AFormText und Einstellungen aus AConfigJson unter
    /// ARelativePath.</summary>
    class function AutoCreateFindings(ARule: IRule; const ASource, AFormText: string; const AForms: TArray<string>;
      const AConfigJson, ARelativePath: string): TArray<TRuleFinding>; static;
    /// <summary>Treffer von ARule auf ASource als Datei AFileName (absolut) mit der Unit-Suche AUnits (#1016),
    /// Einstellungen aus AConfigJson ('' = Vorgaben) unter ARelativePath.</summary>
    class function UnitFindings(ARule: IRule; const ASource, AFileName: string; const AUnits: IRuleUnitLookup;
      const AConfigJson, ARelativePath: string): TArray<TRuleFinding>; static;
    /// <summary>Treffer von ARule auf ASource mit dem Symbolindex AIndex (#1019), Einstellungen aus AConfigJson
    /// ('' = Vorgaben) unter ARelativePath.</summary>
    class function IndexFindings(ARule: IRule; const ASource: string; const AIndex: ISymbolIndex;
      const AConfigJson, ARelativePath: string): TArray<TRuleFinding>; static;
    /// <summary>Treffer von ARule mit dem vorbereiteten Kontext AContext (#1054): Tree wird aus AContext.Text
    /// geparst; Einstellungen aus AConfigJson ('' = Vorgaben).</summary>
    class function ContextFindings(ARule: IRule; const AContext: TRuleContext;
      const AConfigJson: string): TArray<TRuleFinding>; static;
    /// <summary>Positiver Testfall: genau ACount Treffer.</summary>
    class procedure Reports(ARule: IRule; const ASource: string); overload; static;
    class procedure Reports(ARule: IRule; const ASource: string; ACount: Integer); overload; static;
    /// <summary>Negativer Testfall: kein Treffer.</summary>
    class procedure Silent(ARule: IRule; const ASource: string); static;
    /// <summary>Treffer aller ARules in einem Lauf der Engine (gemeinsamer Ableitungscache).</summary>
    class function FindingsOfAll(const ARules: TArray<IRule>; const ASource, AConfigJson: string):
      TArray<TRuleFinding>; static;
    /// <summary>
    ///   Ein gemeinsamer Lauf aller ARules liefert dieselben Treffer (Regel, Bereich, Meldung, Korrekturen)
    ///   wie je ein Lauf je Regel; Ergebnis ist die Trefferzahl. Prüft, dass der geteilte
    ///   Ableitungscache das Verhalten nicht ändert.
    /// </summary>
    class function SameAsSeparateRuns(const ARules: TArray<IRule>; const ASource, AConfigJson: string): Integer;
      overload;
      static;
    class function SameAsSeparateRuns(const ARules: TArray<IRule>; const ASource: string): Integer; overload; static;
  end;

  /// <summary>Testregel ohne Treffer: ruft beim Prüfen AOnCheck auf (zählen, warten, abbrechen).</summary>
  TCallbackRule = class(TInterfacedObject, IRule)
  private
    FId: string;
    FOnCheck: TProc;
  public
    constructor Create(const AId: string; const AOnCheck: TProc);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Rules.Engine;

class function TRuleAssert.Findings(ARule: IRule; const ASource: string): TArray<TRuleFinding>;
begin
  Result := Findings(ARule, ASource, '', '');
end;

class function TRuleAssert.Findings(ARule: IRule; const ASource: string;
  const AConfigJson: string): TArray<TRuleFinding>;
begin
  Result := Findings(ARule, ASource, AConfigJson, '');
end;

class function TRuleAssert.Findings(ARule: IRule; const ASource, AConfigJson,
  ARelativePath: string): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  if AConfigJson = '' then
  begin
    mSettings := TServerSettings.Default;
  end
  else
  begin
    mSettings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := ARelativePath;
    // Wie Rules.Checker: relative Pfade haben '/', ExtractFileName kennt unter Windows nur '\'.
    mContext.UnitName := ChangeFileExt(ExtractFileName(StringReplace(ARelativePath, '/', '\', [rfReplaceAll])), '');
    mContext.Text := ASource;
    mContext.Tree := mTree;
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

class function TRuleAssert.PlatformFindings(ARule: IRule; const ASource, APlatform: string): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.ParseActive(ASource, TPascalPreprocessor.PredefinedSymbols(APlatform, 37.0));
  try
    mContext := Default(TRuleContext);
    mContext.Text := ASource;
    mContext.Tree := mTree;
    Result := TRuleEngine.Run([ARule], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
end;

class function TRuleAssert.ApplicationFindings(ARule: IRule; const ASource: string;
  AApplication: TRuleApplicationKind): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.Application := AApplication;
    Result := TRuleEngine.Run([ARule], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
end;

class function TRuleAssert.PackageFindings(ARule: IRule; const ASource, AProjectName, AConfigJson,
  ARelativePath: string): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  if AConfigJson = '' then
  begin
    mSettings := TServerSettings.Default;
  end
  else
  begin
    mSettings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := ARelativePath;
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.Application := TRuleApplicationKind.Package;
    mContext.ProjectName := AProjectName;
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

class function TRuleAssert.FormFindings(const ARule: IRule; const ASource, AFormText: string): TArray<TRuleFinding>;
begin
  Result := FormFindings(ARule, ASource, AFormText, '');
end;

class function TRuleAssert.FormFindings(const ARule: IRule; const ASource, AFormText, AConfigJson: string):
  TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  if AConfigJson = '' then
  begin
    mSettings := TServerSettings.Default;
  end
  else
  begin
    mSettings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.FormText := AFormText;
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

class function TRuleAssert.AutoCreateFindings(ARule: IRule; const ASource, AFormText: string;
  const AForms: TArray<string>; const AConfigJson, ARelativePath: string): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  if AConfigJson = '' then
  begin
    mSettings := TServerSettings.Default;
  end
  else
  begin
    mSettings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := ARelativePath;
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.FormText := AFormText;
    mContext.AutoCreateForms := AForms;
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

class function TRuleAssert.ContextFindings(ARule: IRule; const AContext: TRuleContext;
  const AConfigJson: string): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  if AConfigJson = '' then
  begin
    mSettings := TServerSettings.Default;
  end
  else
  begin
    mSettings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  mTree := TPascalParser.Parse(AContext.Text);
  try
    mContext := AContext;
    mContext.Tree := mTree;
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

class function TRuleAssert.UnitFindings(ARule: IRule; const ASource, AFileName: string;
  const AUnits: IRuleUnitLookup; const AConfigJson, ARelativePath: string): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  if AConfigJson = '' then
  begin
    mSettings := TServerSettings.Default;
  end
  else
  begin
    mSettings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := ARelativePath;
    mContext.FileName := AFileName;
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.Units := AUnits;
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

class function TRuleAssert.IndexFindings(ARule: IRule; const ASource: string; const AIndex: ISymbolIndex;
  const AConfigJson, ARelativePath: string): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  if AConfigJson = '' then
  begin
    mSettings := TServerSettings.Default;
  end
  else
  begin
    mSettings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := ARelativePath;
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.Index := AIndex;
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

class procedure TRuleAssert.Reports(ARule: IRule; const ASource: string);
begin
  Reports(ARule, ASource, 1);
end;

class procedure TRuleAssert.Reports(ARule: IRule; const ASource: string; ACount: Integer);
begin
  Assert.AreEqual(ACount, Integer(Length(Findings(ARule, ASource))),
    'Treffer von ' + ARule.Descriptor.Id);
end;

class procedure TRuleAssert.Silent(ARule: IRule; const ASource: string);
begin
  Reports(ARule, ASource, 0);
end;

class function TRuleAssert.FindingsOfAll(const ARules: TArray<IRule>; const ASource,
  AConfigJson: string): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  if AConfigJson = '' then
  begin
    mSettings := TServerSettings.Default;
  end
  else
  begin
    mSettings := TConfigurationParser.Parse(AConfigJson, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := ASource;
    mContext.Tree := mTree;
    Result := TRuleEngine.Run(ARules, mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

/// <summary>Vergleichbarer Text eines Treffers mit Bereich, Meldung und Korrekturen.</summary>
function FindingKey(const AFinding: TRuleFinding): string;

  function RangeText(const ARange: TTextRange): string;
  begin
    Result := Format('%d:%d-%d:%d', [ARange.StartPos.Line, ARange.StartPos.Character, ARange.EndPos.Line,
      ARange.EndPos.Character]);
  end;

var
  mFix: TRuleFix;
  mEdit: TRuleEdit;
begin
  Result := AFinding.RuleId + '@' + RangeText(AFinding.Range) + ' ' + AFinding.Message;
  for mFix in AFinding.Fixes do
  begin
    Result := Result + ' | ' + mFix.Title;
    for mEdit in mFix.Edits do
    begin
      Result := Result + ' [' + RangeText(mEdit.Range) + '=' + mEdit.NewText + ']';
    end;
  end;
end;

class function TRuleAssert.SameAsSeparateRuns(const ARules: TArray<IRule>; const ASource,
  AConfigJson: string): Integer;
var
  mCombined, mSeparate: TList<string>;
  mFinding: TRuleFinding;
  mRule: IRule;
  mIndex: Integer;
begin
  mCombined := TList<string>.Create;
  mSeparate := TList<string>.Create;
  try
    for mFinding in FindingsOfAll(ARules, ASource, AConfigJson) do
    begin
      mCombined.Add(FindingKey(mFinding));
    end;
    for mRule in ARules do
    begin
      for mFinding in FindingsOfAll([mRule], ASource, AConfigJson) do
      begin
        mSeparate.Add(FindingKey(mFinding));
      end;
    end;
    mCombined.Sort;
    mSeparate.Sort;
    Assert.AreEqual(mSeparate.Count, mCombined.Count, 'Trefferzahl gemeinsam/einzeln');
    for mIndex := 0 to mCombined.Count - 1 do
    begin
      Assert.AreEqual(mSeparate[mIndex], mCombined[mIndex]);
    end;
    Result := mCombined.Count;
  finally
    mSeparate.Free;
    mCombined.Free;
  end;
end;

class function TRuleAssert.SameAsSeparateRuns(const ARules: TArray<IRule>; const ASource: string): Integer;
begin
  Result := SameAsSeparateRuns(ARules, ASource, '');
end;

{ TCallbackRule }

constructor TCallbackRule.Create(const AId: string; const AOnCheck: TProc);
begin
  inherited Create;
  FId := AId;
  FOnCheck := AOnCheck;
end;

function TCallbackRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FId, TRuleSeverity.Warning, 'Testregel');
end;

procedure TCallbackRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FOnCheck();
end;

end.
