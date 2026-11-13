unit Atlas.UI.Debug.SettingsSection;

// Abschnitt „Debuggen“ des Moduls Debugger im Optionsdialog (#1456; vorher
// Atlas.UI.Settings.Page.Debug in Base): Modulschalter, Werte im Hover, Visualisierer (#835), eigene
// Wertdarstellungen (#854), gezielt hineinspringen (#836), Schrittfilter (#850), nächstes Ereignis (#856),
// Erklärungen (#840, #865), Auswerten (#784), Exceptions (#517, #783), eigener Code (#578) und Werte im
// Editor (#508). Felder, die mehrere Werte in einer Einstellung sammeln (Arten), liest und schreibt der
// Abschnitt selbst; Listen in Textfeldern bindet die Seite und der Abschnitt bringt sie beim Speichern in die
// einheitliche Form.

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Text.StepFilter,
  Atlas.UI.Settings.Section;

type
  TAtlasDebugSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.debug';
    cAreaId = 'Debuggen';
  private
    FVisualizerKinds: array[TAtlasVisualizerKind] of TCheckBox;
    FVisualizerNameFields: TEdit;
    FStepFilterKinds: array[TStepFilterKind] of TCheckBox;
    FStepFilterPatterns: TEdit;
    FBreakOnNextEventExcluded: TEdit;
    FOwnCodeFolders: TEdit;
    procedure BuildVisualizers;
    procedure BuildStepping;
    procedure BuildMore;
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
    procedure Load(const AValues: IAtlasSettingsValues); override;
    procedure Save(const AValues: IAtlasSettingsValues); override;
    procedure Close; override;
    /// <summary>Zum Testen: Haken einer Art.</summary>
    function VisualizerKindCheck(AKind: TAtlasVisualizerKind): TCheckBox;
    function StepFilterKindCheck(AKind: TStepFilterKind): TCheckBox;
    property VisualizerNameFieldsEdit: TEdit read FVisualizerNameFields;
    property StepFilterPatternsEdit: TEdit read FStepFilterPatterns;
    property BreakOnNextEventExcludedEdit: TEdit read FBreakOnNextEventExcluded;
    property OwnCodeFoldersEdit: TEdit read FOwnCodeFolders;
  end;

implementation

uses
  Atlas.Core.Settings.EventBreakNames,
  Atlas.Core.Settings.FolderList,
  Atlas.Core.Debug.EventLog,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings;

const
  cVisualizerTypesKey = 'debug.visualizers.types';
  cVisualizerNameFieldsKey = 'debug.visualizers.nameFields';
  cStepFilterKindsKey = 'debug.stepFilters.kinds';
  cStepFilterPatternsKey = 'debug.stepFilters.patterns';
  cBreakExcludedKey = 'debug.breakOnNextEvent.excluded';
  cOwnCodeFoldersKey = 'debug.ownCodeFolders';
  cEventLogColorsKey = 'debug.eventLogColors';

{ TAtlasDebugSettingsSection }

function TAtlasDebugSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasDebugSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasDebugSettingsSection.BuildRows;
begin
  ModuleSwitch('debug.enabled');
  // Variablenwerte im Hover beim Debuggen (#891).
  Switch('debug.hoverValues', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugHoverValues));
  BuildVisualizers;
  BuildStepping;
  BuildMore;
end;

procedure TAtlasDebugSettingsSection.BuildVisualizers;
const
  cKinds: array[TAtlasVisualizerKind] of TAtlasTextId = (TAtlasTextId.DebugVisualizerKindLists,
    TAtlasTextId.DebugVisualizerKindDictionaries, TAtlasTextId.DebugVisualizerKindDataSets,
    TAtlasTextId.DebugVisualizerKindBytes, TAtlasTextId.DebugVisualizerKindJson,
    TAtlasTextId.DebugVisualizerKindColors, TAtlasTextId.DebugVisualizerKindGuid,
    TAtlasTextId.DebugVisualizerKindGeometry, TAtlasTextId.DebugVisualizerKindGraphics);
var
  mKind: TAtlasVisualizerKind;
  mEvaluation: TAtlasVisualizerEvaluation;
  mValues: TArray<string>;
begin
  // Visualisierer für häufige Typen (#835): Hauptschalter, Arten, Namensfelder, Grenzen, Auswertung.
  Switch('debug.visualizers', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugVisualizers));
  for mKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    FVisualizerKinds[mKind] := OwnCheck(TAtlasStrings.Text(cKinds[mKind]), [cVisualizerTypesKey]);
  end;
  FVisualizerNameFields := Line(cVisualizerNameFieldsKey,
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugVisualizerNameFields));
  Number('debug.visualizers.maxLength', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugVisualizerMaxLength));
  Number('debug.visualizers.timeoutMs', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugVisualizerTimeout));
  Number('debug.visualizers.maxImagePixels',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugVisualizerMaxImagePixels));
  mValues := nil;
  for mEvaluation := Low(TAtlasVisualizerEvaluation) to High(TAtlasVisualizerEvaluation) do
  begin
    mValues := mValues + [TAtlasVisualizerSettings.cEvaluationNames[mEvaluation]];
  end;
  Choice('debug.visualizers.evaluation', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugVisualizerEvaluation),
    [TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugVisualizerEvaluationFields),
    TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugVisualizerEvaluationProperties),
    TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugVisualizerEvaluationCalls)], mValues);
  // Eigene Wertdarstellungen (#854): Schalter und Aufrufe in Vorlagen.
  Switch('debug.displayRules', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugDisplayRules));
  Switch('debug.displayRules.allowCalls', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugDisplayRulesAllowCalls));
end;

procedure TAtlasDebugSettingsSection.BuildStepping;
const
  cKinds: array[TStepFilterKind] of TAtlasTextId = (TAtlasTextId.StepFilterKindGetters,
    TAtlasTextId.StepFilterKindSetters, TAtlasTextId.StepFilterKindTrivial,
    TAtlasTextId.StepFilterKindOperators, TAtlasTextId.StepFilterKindEmptyConstructors);
var
  mKind: TStepFilterKind;
begin
  // Gezielt hineinspringen (#836) und Schrittfilter beim Hineinspringen (#850): Schalter, Arten, Muster.
  Switch('debug.stepIntoTarget', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugStepIntoTarget));
  Switch('debug.stepFilters', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugStepFilters));
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FStepFilterKinds[mKind] := OwnCheck(TAtlasStrings.Text(cKinds[mKind]), [cStepFilterKindsKey]);
  end;
  FStepFilterPatterns := Line(cStepFilterPatternsKey,
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugStepFilterPatterns));
  Key('debug.stepIntoTarget.key', TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand));
  // Beim nächsten Ereignis anhalten (#856): Schalter und ausgenommene Ereignisse.
  Switch('debug.breakOnNextEvent', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugBreakOnNextEvent));
  FBreakOnNextEventExcluded := Line(cBreakExcludedKey,
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugBreakOnNextEventExcluded));
  // Haltepunkte, die nicht greifen werden (#577).
  Switch('debug.checkBreakpoints', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugCheckBreakpoints));
  // Haltepunkt nur für ein Objekt (#857).
  Switch('debug.instanceBreakpoints', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugInstanceBreakpoints));
  // Haltepunkt-Sätze (#586).
  Switch('debug.breakpointSetPerBranch',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugBreakpointSetPerBranch));
  // Bis hier ausführen per Klick (#851).
  Switch('debug.runToClick', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugRunToClick));
  // Haltepunktfenster mit Suche, Etiketten und Trefferzahlen (#863).
  Switch('debug.breakpointsWindow', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugBreakpointsWindow));
  // Haltepunkte wandern mit dem Code (#841).
  Switch('debug.breakpointAnchors', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugBreakpointAnchors));
  // Abhängige Haltepunkte und Trefferbedingungen (#864).
  Switch('debug.breakpointRules', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugBreakpointRules));
end;

procedure TAtlasDebugSettingsSection.BuildMore;
begin
  // „kein Zugriff auf Wert“ erklären (#840), Vervollständigung in Debugger-Dialogen (#538), Fenster „Auswerten“
  // (#784), Zugriffsverletzung erklären (#865).
  Switch('debug.explainUnavailable', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugExplainUnavailable));
  Switch('debug.completionInDialogs', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugCompletionInDialogs));
  Switch('debug.evaluateWindow', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugEvaluateWindow));
  Switch('debug.evaluateWindow.replaceCtrlF7',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugEvaluateReplaceCtrlF7));
  Switch('debug.explainAccessViolation',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugExplainAccessViolation));
  Switch('debug.explainAccessViolation.allowCalls',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugExplainAccessViolationAllowCalls));
  // Modul der Fehleradresse (#1820).
  Switch('debug.moduleOfAddress', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugModuleOfAddress));
  // Was wartet worauf? (#587).
  Switch('debug.deadlocks', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugDeadlocks));
  // Leckbericht am Programmende (#1875).
  Switch('debug.leakReport', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugLeakReport));
  Switch('debug.leakReport.compare', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugLeakReportCompare));
  Switch('debug.leakReport.window', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugLeakReportWindow));
  // Parallele Aufrufstapel (#837).
  Switch('debug.parallelStacks', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugParallelStacks));
  // Threads im Quelltext (#852).
  Switch('debug.threadsInSource', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugThreadsInSource));
  // Threads einfrieren (#852, experimentell).
  Switch('debug.threadFreeze', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugThreadFreeze));
  // Herkunft eingereihter Methoden (#859, experimentell).
  Switch('debug.asyncOrigin', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugAsyncOrigin));
  Number('debug.asyncOrigin.maxPerSite',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugAsyncOriginMaxPerSite));
  Line('debug.parallelStacks.waitRoutines',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugParallelStacksWaitRoutines));
  Number('debug.parallelStacks.maxThreads',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugParallelStacksMaxThreads));

  // Exception-Verlauf (#517), nur eigener Code (#578), Exception-Leiste (#783), Werte im Editor (#508).
  Switch('debug.exceptionHistory', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugExceptionHistory));
  Switch('debug.justMyCode', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugJustMyCode));
  FOwnCodeFolders := Line(cOwnCodeFoldersKey, TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugOwnCodeFolders));
  Switch('debug.exceptionBanner', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugExceptionBanner));
  Switch('debug.exceptionBanner.ignoreAtLocation',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugExceptionBannerIgnoreAtLocation));
  Switch('debug.inlineValues', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugInlineValues));
  Number('debug.inlineValuesPerLine', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugInlineValuesPerLine));
  // „Warum bin ich hier?“ (#1878).
  Switch('debug.whyHere', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugWhyHere));
  Number('debug.whyHere.depth', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugWhyHereDepth));
  // Ereignisprotokoll (#580).
  Switch('debug.eventLog', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugEventLog));
  Line(cEventLogColorsKey, TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugEventLogColors));
  Switch('debug.logpoints', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugLogpoints));
  Line('debug.logpointPrefix', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugLogpointPrefix));
  Switch('debug.noSourcePage', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugNoSourcePage));
  Line('debug.noSourcePage.ignoredUnits', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugNoSourceIgnored));
  Switch('debug.restart', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugRestart));
  Switch('debug.restart.reenableBreakpoints', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugRestartReenable));
  // Erneut anhängen (#2171).
  Switch('debug.reattach', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugReattach));
  Key('debug.reattach.key', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugReattachKey));
  Number('debug.reattach.waitIntervalMs', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugReattachWait));
  // Startverbünde (#867).
  Switch('debug.launchGroups', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugLaunchGroups));
  Switch('debug.pinnedValues', TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugPinnedValues));
end;

function TAtlasDebugSettingsSection.VisualizerKindCheck(AKind: TAtlasVisualizerKind): TCheckBox;
begin
  Result := FVisualizerKinds[AKind];
end;

function TAtlasDebugSettingsSection.StepFilterKindCheck(AKind: TStepFilterKind): TCheckBox;
begin
  Result := FStepFilterKinds[AKind];
end;

procedure TAtlasDebugSettingsSection.Load(const AValues: IAtlasSettingsValues);
var
  mVisualizerKind: TAtlasVisualizerKind;
  mStepFilterKind: TStepFilterKind;
  mVisualizerKinds: TAtlasVisualizerKinds;
  mStepFilterKinds: TStepFilterKinds;
begin
  if Closed then
  begin
    Exit;
  end;
  mVisualizerKinds := TAtlasVisualizerSettings.ParseKinds(AValues.ReadString(cVisualizerTypesKey));
  for mVisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    FVisualizerKinds[mVisualizerKind].Checked := mVisualizerKind in mVisualizerKinds;
  end;
  mStepFilterKinds := TStepFilterNames.ParseKinds(AValues.ReadString(cStepFilterKindsKey));
  for mStepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FStepFilterKinds[mStepFilterKind].Checked := mStepFilterKind in mStepFilterKinds;
  end;
end;

procedure TAtlasDebugSettingsSection.Save(const AValues: IAtlasSettingsValues);
var
  mVisualizerKind: TAtlasVisualizerKind;
  mStepFilterKind: TStepFilterKind;
  mVisualizerKinds: TAtlasVisualizerKinds;
  mStepFilterKinds: TStepFilterKinds;
begin
  if Closed then
  begin
    Exit;
  end;
  mVisualizerKinds := [];
  for mVisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    if FVisualizerKinds[mVisualizerKind].Checked then
    begin
      Include(mVisualizerKinds, mVisualizerKind);
    end;
  end;
  AValues.WriteString(cVisualizerTypesKey, TAtlasVisualizerSettings.KindsText(mVisualizerKinds));
  mStepFilterKinds := [];
  for mStepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    if FStepFilterKinds[mStepFilterKind].Checked then
    begin
      Include(mStepFilterKinds, mStepFilterKind);
    end;
  end;
  AValues.WriteString(cStepFilterKindsKey, TStepFilterNames.KindsText(mStepFilterKinds));
  // Die Seite hat die Textfelder gespeichert; hier nur die einheitliche Form.
  AValues.WriteString(cVisualizerNameFieldsKey,
    TAtlasVisualizerSettings.NormalizeNameFields(AValues.ReadString(cVisualizerNameFieldsKey)));
  AValues.WriteString(cStepFilterPatternsKey,
    TStepFilterNames.NormalizePatterns(AValues.ReadString(cStepFilterPatternsKey)));
  AValues.WriteString(cBreakExcludedKey,
    TAtlasEventBreakSettings.NormalizeExcluded(AValues.ReadString(cBreakExcludedKey)));
  AValues.WriteString(cOwnCodeFoldersKey, TAtlasFolderList.Text(AValues.ReadString(cOwnCodeFoldersKey)));
  AValues.WriteString(cEventLogColorsKey, TAtlasEventColors.Normalize(AValues.ReadString(cEventLogColorsKey)));
end;

procedure TAtlasDebugSettingsSection.Close;
var
  mVisualizerKind: TAtlasVisualizerKind;
  mStepFilterKind: TStepFilterKind;
begin
  // Die Elemente gehören der Seite: nur die Verweise lösen.
  for mVisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    FVisualizerKinds[mVisualizerKind] := nil;
  end;
  for mStepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FStepFilterKinds[mStepFilterKind] := nil;
  end;
  FVisualizerNameFields := nil;
  FStepFilterPatterns := nil;
  FBreakOnNextEventExcluded := nil;
  FOwnCodeFolders := nil;
  inherited Close;
end;

end.
