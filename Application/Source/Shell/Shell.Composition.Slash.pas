unit Shell.Composition.Slash;

// Internals-Rolle Shell: der Host der Schnellbefehle (#297). Legt TShellSlashHost an und beantwortet dessen
// Fragen: Kopfvorlage (#56), Einstellungen slashCommands.* (#299, #304), Testunit für /test (#295),
// Regeltreffer einer Zeile für /ignore, /fix und /explain (#297, #300). Die Komposition reicht Ordner,
// Quelltext, Einstellungen, Prüfkontext und uses-Umfeld als Dienste herein.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.ResourceStringCommands,
  Shell.SlashHost;

type
  TShellSlashSettingsFunc = reference to function(const AUri: string): TServerSettings;
  /// <summary>Einstellungen des Ordners von AUri; False ohne Ordner.</summary>
  TShellSlashWorkspaceSettingsFunc = reference to function(const AUri: string;
    out ASettings: TServerSettings): Boolean;
  TShellSlashTestContextFunc = reference to function(const AUri: string; out AContext: TTestUnitContext): Boolean;

  /// <summary>Was der Host der Schnellbefehle von der Komposition braucht.</summary>
  TShellSlashServices = record
    Transport: IJsonRpcTransport;
    Logger: ILogger;
    Dispatcher: TJsonRpcDispatcher;
    WorkspaceOf: TWorkspaceOfFunc;
    ReadText: TReadTextFunc;
    /// <summary>Kann der Client applyEdit (#397)?</summary>
    ClientAppliesEdits: TFunc<Boolean>;
    /// <summary>Neu laden nur im Thread der Nachrichtenschleife.</summary>
    RunInLoop: TJsonRpcScheduler;
    /// <summary>Wirksame Einstellungen zur Datei, ohne Ordner die losen.</summary>
    SettingsFor: TShellSlashSettingsFunc;
    WorkspaceSettingsOf: TShellSlashWorkspaceSettingsFunc;
    TestUnitContextFor: TShellSlashTestContextFunc;
    RuleContextFor: TRuleContextProvider;
    UsesContextFor: TSlashUsesContextFunc;
  end;

  /// <summary>Host der Schnellbefehle mit seinen Quellen. Lebt länger als jeder Nutzer des Hosts.</summary>
  TShellSlash = class
  private
    FServices: TShellSlashServices;
    FHost: ISlashHost;
    FResourceStringWrite: TResourceStringWrite;
    function HeaderTemplateOf(const AUri: string): string;
    function SettingOf(const AUri, AName: string): string;
    function TestUnitOf(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
    function FindingsAt(const AUri, AText: string; ALine: Integer; out AFindings: TArray<TSlashFinding>): Boolean;
  public
    constructor Create(const AServices: TShellSlashServices);
    destructor Destroy; override;
    /// <summary>Kennungen der Prüfregeln, die in Zeile ALine von AText treffen (/ignore, #297); False ohne
    /// Prüfregeln für die Datei.</summary>
    function RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
    property Host: ISlashHost read FHost;
    /// <summary>Schreibt einen resourcestring in eine andere Unit (#473); über den Host.</summary>
    property ResourceStringWrite: TResourceStringWrite read FResourceStringWrite;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TSlashCompositionText = (NoWorkspace, NoUnit, IsTest);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TSlashCompositionText] of TAtlasText = (
    (De: 'Datei gehört zu keinem Arbeitsbereich'; En: 'File belongs to no workspace'),
    (De: 'Die Datei ist keine Unit'; En: 'The file is not a unit'),
    (De: 'Die Datei ist selbst eine Testunit'; En: 'The file is a test unit itself'));

/// <summary>Schreibt eine resourcestring-Unit (#473) über den Slash-Host AHost. Eigene Routine, damit die Closure
/// nur AHost einfängt.</summary>
function ResourceStringWriteFor(const AHost: ISlashHost): TResourceStringWrite;
begin
  Result :=
    procedure(const AFileName, ANewText: string; const AEdit: TTextEdit)
    begin
      (AHost as TShellSlashHost).EditFile(TDocumentUris.FromPath(AFileName), AFileName, ANewText, AEdit);
    end;
end;

/// <summary>Abschnitt für neue Interface-Methoden als Text der Schnellbefehle.</summary>
function InterfaceSectionText(ASection: TCompletionInterfaceSection): string;
begin
  case ASection of
    TCompletionInterfaceSection.Private:
      Result := 'private';
    TCompletionInterfaceSection.Protected:
      Result := 'protected';
  else
    Result := 'public';
  end;
end;

/// <summary>Einstellung AName aus classCompletion (#1834) als Text; leer, wenn es sie nicht gibt.</summary>
function ClassCompletionValue(const ASettings: TClassCompletionSettings; const AName: string): string;
begin
  Result := '';
  if AName = TSlashSettings.cTypeComment then
  begin
    Result := ASettings.TypeComment;
  end
  else if AName = TSlashSettings.cBodyStubs then
  begin
    Result := LowerCase(BoolToStr(ASettings.BodyStubs, True));
  end
  else if AName = TSlashSettings.cLifecycleFirst then
  begin
    Result := LowerCase(BoolToStr(ASettings.LifecycleFirst, True));
  end;
end;

/// <summary>Einstellung AName der Schnellbefehle als Text; leer, wenn es sie nicht gibt.</summary>
function SlashSettingValue(const ASettings: TServerSettings; const AName: string): string;
begin
  Result := '';
  if AName = TSlashSettings.cLogCall then
  begin
    Result := ASettings.SlashLogCall;
  end
  else if AName = TSlashSettings.cTodoOwner then
  begin
    Result := ASettings.SlashTodoOwner;
  end
  else if AName = TSlashSettings.cTodoCategory then
  begin
    Result := ASettings.SlashTodoCategory;
  end
  else if AName = TSlashSettings.cSortUsesRemoveUnused then
  begin
    Result := LowerCase(BoolToStr(ASettings.SlashSortUsesRemoveUnused, True));
  end
  else if AName = TSlashSettings.cEnumHelper then
  begin
    Result := LowerCase(BoolToStr(ASettings.SlashEnumHelper, True));
  end
  else if AName = TSlashSettings.cSetHelper then
  begin
    Result := LowerCase(BoolToStr(ASettings.SlashSetHelper, True));
  end
  else if AName = TSlashSettings.cComponentPalette then
  begin
    Result := ASettings.SlashComponentPalette;
  end
  else if AName = TSlashSettings.cInterfaceSection then
  begin
    Result := InterfaceSectionText(ASettings.Completion.InterfaceSection);
  end
  else
  begin
    Result := ClassCompletionValue(ASettings.ClassCompletion, AName);
  end;
end;

constructor TShellSlash.Create(const AServices: TShellSlashServices);
var
  mHost: TShellSlashHost;
begin
  inherited Create;
  FServices := AServices;
  mHost := TShellSlashHost.Create(TShellSlashSources.New(FServices.WorkspaceOf, FServices.ReadText,
    HeaderTemplateOf), FServices.Transport, FServices.Logger, FServices.Dispatcher, FServices.ClientAppliesEdits);
  // Die Schnittstelle hält den Host am Leben.
  FHost := mHost;
  mHost.RunInLoop := FServices.RunInLoop;
  // Testunit für /test (#295): dieselbe Suche wie die Code-Aktion aus #274.
  mHost.TestUnitOf := TestUnitOf;
  // Protokollaufruf (#304) und Palettenseite (#299) aus der atlas.json des Ordners.
  mHost.SettingOf := SettingOf;
  // /ignore und /sortuses (#297): Regeltreffer der Zeile und ungenutzte uses.
  mHost.RuleIdsOf := RuleIdsAt;
  mHost.UsesContextOf := FServices.UsesContextFor;
  mHost.FindingsOf := FindingsAt;
  FResourceStringWrite := ResourceStringWriteFor(FHost);
end;

destructor TShellSlash.Destroy;
begin
  FResourceStringWrite := nil;
  FHost := nil;
  inherited Destroy;
end;

function TShellSlash.HeaderTemplateOf(const AUri: string): string;
var
  mSettings: TServerSettings;
begin
  if not FServices.WorkspaceSettingsOf(AUri, mSettings) then
  begin
    Result := '';
    Exit;
  end;
  // Eigene Vorlage der Schnellbefehle, sonst die der Regel file-header (#56).
  Result := mSettings.SlashHeaderTemplate;
  if Result = '' then
  begin
    Result := TFileHeaderRule.Template(TRuleEngine.RuleOptions('file-header', mSettings));
  end;
end;

function TShellSlash.SettingOf(const AUri, AName: string): string;
begin
  Result := SlashSettingValue(FServices.SettingsFor(AUri), AName);
end;

function TShellSlash.TestUnitOf(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
var
  mContext: TTestUnitContext;
  mTarget: TTestUnitTarget;
begin
  ATarget := Default(TSlashTestUnit);
  if not FServices.TestUnitContextFor(AUri, mContext) then
  begin
    ATarget.Reason := cTexts[TSlashCompositionText.NoWorkspace].Text;
    Result := False;
    Exit;
  end;
  mTarget := TLspTestUnits.Resolve(TDocumentUris.ToPath(AUri), AText, -1, mContext);
  ATarget.UnitName := mTarget.Counterpart;
  ATarget.TestProgram := mContext.TestProgram;
  if mTarget.UnitName = '' then
  begin
    ATarget.Reason := cTexts[TSlashCompositionText.NoUnit].Text;
  end
  else if mTarget.IsTest then
  begin
    ATarget.Reason := cTexts[TSlashCompositionText.IsTest].Text;
  end
  else if mTarget.CounterpartFile <> '' then
  begin
    ATarget.FileName := mTarget.CounterpartFile;
    ATarget.Exists := True;
  end
  else if mTarget.CanCreate then
  begin
    ATarget.FileName := mTarget.NewFile;
  end
  else
  begin
    ATarget.Reason := mTarget.Reason;
  end;
  Result := ATarget.Reason = '';
end;

function TShellSlash.RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
var
  mContext: TRuleCheckContext;
  mTree: TSyntaxTree;
  mFinding: TRuleFinding;
begin
  AIds := nil;
  Result := FServices.RuleContextFor(AUri, mContext);
  if not Result then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    for mFinding in TLspSyntaxDiagnostics.RuleFindings(AText, mTree, mContext) do
    begin
      if (mFinding.Range.StartPos.Line = ALine) and not SameText(mFinding.RuleId, 'slash-command') and
        not MatchText(mFinding.RuleId, AIds) then
      begin
        AIds := AIds + [mFinding.RuleId];
      end;
    end;
  finally
    mTree.Free;
  end;
end;

function TShellSlash.FindingsAt(const AUri, AText: string; ALine: Integer;
  out AFindings: TArray<TSlashFinding>): Boolean;
var
  mContext: TRuleCheckContext;
  mTree: TSyntaxTree;
  mCatalog: TRuleCatalog;
  mFinding: TRuleFinding;
  mEntry: TRuleCatalogEntry;
  mItem: TSlashFinding;
  mAction: TCodeAction;
begin
  AFindings := nil;
  Result := FServices.RuleContextFor(AUri, mContext);
  if not Result then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(AText);
  // Erklärung in der Sprache der Texte (#1458); der geteilte Katalog gehört dem Prozess.
  mCatalog := TRuleCatalog.Localized;
  try
    for mFinding in TLspSyntaxDiagnostics.RuleFindings(AText, mTree, mContext) do
    begin
      if (mFinding.Range.StartPos.Line <> ALine) or SameText(mFinding.RuleId, 'slash-command') then
      begin
        Continue;
      end;
      mItem := Default(TSlashFinding);
      mItem.RuleId := mFinding.RuleId;
      mItem.Message := mFinding.Message;
      if mCatalog.TryFind(mFinding.RuleId, mEntry) then
      begin
        mItem.Explanation := TRuleCatalog.Explanation(mEntry, #10);
      end;
      // Nur als sicher markierte Korrekturen, wie beim Speichern (#182).
      if TRuleCodeActions.FixAll([mFinding], mAction) then
      begin
        mItem.SafeFix := mAction.Edits;
      end;
      AFindings := AFindings + [mItem];
    end;
  finally
    mTree.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.Slash', cTexts);

end.
