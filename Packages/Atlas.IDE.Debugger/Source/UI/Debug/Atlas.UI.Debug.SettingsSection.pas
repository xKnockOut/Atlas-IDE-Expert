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
    procedure BuildRestartRows;
    /// <summary>Werte beim Halt: Fenster „Variablen“, Vorhersage, Werte ändern, Debug-Hover.</summary>
    procedure BuildStopValues;
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
  Atlas.UI.Debug.Leaks.Strings,
  Atlas.UI.Debug.Settings.Strings,
  Atlas.UI.Debug.Values.Strings,
  Atlas.UI.Debug.Stepping.Strings,
  Atlas.UI.Debug.VariablesStrings,
  Atlas.UI.Debug.Memory.Strings,
  Atlas.UI.Debug.Note.Strings,
  Atlas.UI.Debug.Profile.Strings;

const
  cVisualizerTypesKey = 'debug.visualizers.types';
  cVisualizerNameFieldsKey = 'debug.visualizers.nameFields';
  cStepFilterKindsKey = 'debug.stepFilters.kinds';
  cStepFilterPatternsKey = 'debug.stepFilters.patterns';
  cBreakExcludedKey = 'debug.breakOnNextEvent.excluded';
  cOwnCodeFoldersKey = 'debug.ownCodeFolders';
  cEventLogColorsKey = 'debug.eventLogColors';

{ TAtlasDebugSettingsSection }

procedure TAtlasDebugSettingsSection.BuildRows;
begin
  ModuleSwitch('debug.enabled');
  // Variablenwerte im Hover beim Debuggen (#891).
  Switch('debug.hoverValues', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugHoverValues));
  BuildVisualizers;
  BuildStepping;
  BuildMore;
  BuildRestartRows;
end;

function TAtlasDebugSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasDebugSettingsSection.AreaId: string;
begin
  Result := cAreaId;
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

procedure TAtlasDebugSettingsSection.BuildVisualizers;
const
  cKinds: array[TAtlasVisualizerKind] of TAtlasValuesTextId = (TAtlasValuesTextId.DebugVisualizerKindLists,
    TAtlasValuesTextId.DebugVisualizerKindDictionaries, TAtlasValuesTextId.DebugVisualizerKindDataSets,
    TAtlasValuesTextId.DebugVisualizerKindBytes, TAtlasValuesTextId.DebugVisualizerKindJson,
    TAtlasValuesTextId.DebugVisualizerKindColors, TAtlasValuesTextId.DebugVisualizerKindGuid,
    TAtlasValuesTextId.DebugVisualizerKindGeometry, TAtlasValuesTextId.DebugVisualizerKindGraphics);
var
  mKind: TAtlasVisualizerKind;
  mEvaluation: TAtlasVisualizerEvaluation;
  mValues: TArray<string>;
begin
  // Visualisierer für häufige Typen (#835): Hauptschalter, Arten, Namensfelder, Grenzen, Auswertung.
  Switch('debug.visualizers', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugVisualizers));
  for mKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    FVisualizerKinds[mKind] := OwnCheck(TAtlasValuesStrings.Text(cKinds[mKind]), [cVisualizerTypesKey]);
  end;
  FVisualizerNameFields := Line(cVisualizerNameFieldsKey,
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugVisualizerNameFields));
  Number('debug.visualizers.maxLength',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugVisualizerMaxLength));
  Number('debug.visualizers.timeoutMs',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugVisualizerTimeout));
  Number('debug.visualizers.maxImagePixels',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugVisualizerMaxImagePixels));
  mValues := nil;
  for mEvaluation := Low(TAtlasVisualizerEvaluation) to High(TAtlasVisualizerEvaluation) do
  begin
    mValues := mValues + [TAtlasVisualizerSettings.cEvaluationNames[mEvaluation]];
  end;
  Choice('debug.visualizers.evaluation',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugVisualizerEvaluation),
    [TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugVisualizerEvaluationFields),
    TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugVisualizerEvaluationProperties),
    TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugVisualizerEvaluationCalls)], mValues);
  // Eigene Wertdarstellungen (#854): Schalter und Aufrufe in Vorlagen.
  Switch('debug.displayRules', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugDisplayRules));
  Switch('debug.displayRules.allowCalls',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugDisplayRulesAllowCalls));
end;

procedure TAtlasDebugSettingsSection.BuildStepping;
const
  cKinds: array[TStepFilterKind] of TAtlasSteppingTextId = (TAtlasSteppingTextId.StepFilterKindGetters,
    TAtlasSteppingTextId.StepFilterKindSetters, TAtlasSteppingTextId.StepFilterKindTrivial,
    TAtlasSteppingTextId.StepFilterKindOperators, TAtlasSteppingTextId.StepFilterKindEmptyConstructors);
var
  mKind: TStepFilterKind;
begin
  // Gezielt hineinspringen (#836) und Schrittfilter beim Hineinspringen (#850): Schalter, Arten, Muster.
  Switch('debug.stepIntoTarget',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugStepIntoTarget));
  Switch('debug.stepFilters', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugStepFilters));
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FStepFilterKinds[mKind] := OwnCheck(TAtlasSteppingStrings.Text(cKinds[mKind]), [cStepFilterKindsKey]);
  end;
  FStepFilterPatterns := Line(cStepFilterPatternsKey,
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugStepFilterPatterns));
  Key('debug.stepIntoTarget.key', TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand));
  // Beim nächsten Ereignis anhalten (#856): Schalter und ausgenommene Ereignisse.
  Switch('debug.breakOnNextEvent',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugBreakOnNextEvent));
  FBreakOnNextEventExcluded := Line(cBreakExcludedKey,
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugBreakOnNextEventExcluded));
  // Haltepunkte, die nicht greifen werden (#577).
  Switch('debug.checkBreakpoints',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugCheckBreakpoints));
  // Haltepunkte auf Methoden nach Muster (#855).
  Switch('debug.methodBreakpoints',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugMethodBreakpoints));
  // Haltepunkt nur für ein Objekt (#857).
  Switch('debug.instanceBreakpoints',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugInstanceBreakpoints));
  // Anhalten, wenn sich ein Feld ändert (#584).
  Switch('debug.dataBreakpoints',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugDataBreakpoints));
  // Haltepunkt-Sätze (#586).
  Switch('debug.breakpointSetPerBranch',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugBreakpointSetPerBranch));
  // Bis hier ausführen per Klick (#851).
  Switch('debug.runToClick', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugRunToClick));
  // Ausführungspfeil ziehen (#871, experimentell).
  Switch('debug.dragNextStatement',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugDragNextStatement));
  // Haltepunktfenster mit Suche, Etiketten und Trefferzahlen (#863).
  Switch('debug.breakpointsWindow',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugBreakpointsWindow));
  // Haltepunkte wandern mit dem Code (#841).
  Switch('debug.breakpointAnchors',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugBreakpointAnchors));
  // Abhängige Haltepunkte und Trefferbedingungen (#864).
  Switch('debug.breakpointRules',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugBreakpointRules));
end;

procedure TAtlasDebugSettingsSection.BuildMore;
begin
  // „kein Zugriff auf Wert“ erklären (#840), Vervollständigung in Debugger-Dialogen (#538), Fenster „Auswerten“
  // (#784), Zugriffsverletzung erklären (#865).
  Switch('debug.explainUnavailable',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugExplainUnavailable));
  Switch('debug.completionInDialogs',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugCompletionInDialogs));
  Switch('debug.evaluateWindow',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugEvaluateWindow));
  Switch('debug.evaluateWindow.replaceCtrlF7',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugEvaluateReplaceCtrlF7));
  Switch('debug.explainAccessViolation',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugExplainAccessViolation));
  Switch('debug.explainAccessViolation.allowCalls',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugExplainAccessViolationAllowCalls));
  // Modul der Fehleradresse (#1820).
  Switch('debug.moduleOfAddress',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugModuleOfAddress));
  // Was wartet worauf? (#587).
  Switch('debug.deadlocks', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugDeadlocks));
  // Leckbericht am Programmende (#1875).
  Switch('debug.leakReport', TAtlasLeaksStrings.Text(TAtlasLeaksTextId.SettingsDebugLeakReport));
  Switch('debug.leakReport.compare', TAtlasLeaksStrings.Text(TAtlasLeaksTextId.SettingsDebugLeakReportCompare));
  Switch('debug.leakReport.window', TAtlasLeaksStrings.Text(TAtlasLeaksTextId.SettingsDebugLeakReportWindow));
  // Parallele Aufrufstapel (#837).
  Switch('debug.parallelStacks',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugParallelStacks));
  // Fenster „Aufrufstapel“ (#843).
  Switch('debug.callStackWindow',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugCallStackWindow));
  Switch('debug.callStackWindow.evaluateParams',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugCallStackWindowEvaluateParams));
  // Threads im Quelltext (#852).
  Switch('debug.threadsInSource',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugThreadsInSource));
  // Threads einfrieren (#852, experimentell).
  Switch('debug.threadFreeze', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugThreadFreeze));
  // Herkunft eingereihter Methoden (#859, experimentell).
  Switch('debug.asyncOrigin', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugAsyncOrigin));
  Number('debug.asyncOrigin.maxPerSite',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugAsyncOriginMaxPerSite));
  Line('debug.parallelStacks.waitRoutines',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugParallelStacksWaitRoutines));
  Number('debug.parallelStacks.maxThreads',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugParallelStacksMaxThreads));

  // Exception-Verlauf (#517), nur eigener Code (#578), Exception-Leiste (#783), Werte im Editor (#508).
  Switch('debug.exceptionHistory',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugExceptionHistory));
  Switch('debug.justMyCode', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugJustMyCode));
  FOwnCodeFolders := Line(cOwnCodeFoldersKey,
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugOwnCodeFolders));
  Switch('debug.exceptionBanner',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugExceptionBanner));
  Switch('debug.exceptionBanner.ignoreAtLocation',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugExceptionBannerIgnoreAtLocation));
  Switch('debug.inlineValues', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugInlineValues));
  Number('debug.inlineValuesPerLine',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugInlineValuesPerLine));
  // „Warum bin ich hier?“ (#1878).
  Switch('debug.whyHere', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugWhyHere));
  Number('debug.whyHere.depth', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugWhyHereDepth));
  // Laufzeit zwischen Haltepunkten (#579).
  Switch('debug.showElapsed', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugShowElapsed));
  BuildStopValues;
  // Ereignisprotokoll (#580).
  Switch('debug.eventLog', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugEventLog));
  Line(cEventLogColorsKey, TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugEventLogColors));
  Switch('debug.logpoints', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugLogpoints));
  Line('debug.logpointPrefix', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugLogpointPrefix));
  Switch('debug.noSourcePage', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugNoSourcePage));
  Line('debug.noSourcePage.ignoredUnits',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugNoSourceIgnored));
end;

procedure TAtlasDebugSettingsSection.BuildRestartRows;
begin
  // Neu starten, erneut anhängen (#2171), Startverbünde (#867), Speicherverlauf (#858), Profiler (#2057),
  // Debug-Zustand festhalten (#582).
  Switch('debug.restart', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugRestart));
  Switch('debug.restart.reenableBreakpoints',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugRestartReenable));
  // Erneut anhängen (#2171).
  Switch('debug.reattach', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugReattach));
  Key('debug.reattach.key', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugReattachKey));
  Number('debug.reattach.waitIntervalMs',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugReattachWait));
  // Startverbünde (#867).
  Switch('debug.launchGroups', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugLaunchGroups));
  Switch('debug.pinnedValues', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugPinnedValues));
  // Speicherverlauf (#858).
  Switch('debug.memoryTimeline', TAtlasMemoryStrings.Text(TAtlasMemoryTextId.SettingsDebugMemoryTimeline));
  Number('debug.memoryTimeline.intervalMs',
    TAtlasMemoryStrings.Text(TAtlasMemoryTextId.SettingsDebugMemoryTimelineInterval));
  // Profiler (#2057, experimentell).
  Switch('debug.profiler', TAtlasProfileStrings.Text(TAtlasProfileTextId.SettingsDebugProfiler));
  Number('debug.profiler.intervalMs', TAtlasProfileStrings.Text(TAtlasProfileTextId.SettingsDebugProfilerInterval));
  Switch('debug.memoryTimeline.objectCount',
    TAtlasMemoryStrings.Text(TAtlasMemoryTextId.SettingsDebugMemoryTimelineObjectCount));
  // Debug-Zustand festhalten (#582).
  Switch('debug.note', TAtlasNoteStrings.Text(TAtlasNoteTextId.SettingsNote));
  Switch('debug.note.saveFile', TAtlasNoteStrings.Text(TAtlasNoteTextId.SettingsNoteSaveFile));
end;

procedure TAtlasDebugSettingsSection.BuildStopValues;
begin
  // Fenster „Variablen“ (#853).
  Switch('debug.variablesWindow', TAtlasVariablesStrings.Text(TAtlasVariablesTextId.SettingsDebugVariablesWindow));
  Number('debug.variablesWindow.searchDepth',
    TAtlasVariablesStrings.Text(TAtlasVariablesTextId.SettingsDebugVariablesSearchDepth));
  Number('debug.variablesWindow.searchLimit',
    TAtlasVariablesStrings.Text(TAtlasVariablesTextId.SettingsDebugVariablesSearchLimit));
  // Bedingungen vorausschauen (#2169).
  Switch('debug.predictConditions', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugPredict));
  Switch('debug.predictConditions.dimSkipped',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugPredictDim));
  Number('debug.predictConditions.lines',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugPredictLines));
  // Werte ändern (#868).
  Switch('debug.editValues', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugEditValues));
  // Debug-Hover aufklappen und Änderungen markieren (#895).
  Switch('debug.hoverExpand', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugHoverExpand));
  Number('debug.hoverMaxChildren',
    TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugHoverMaxChildren));
  Switch('debug.hoverChanges', TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId.SettingsDebugHoverChanges));
end;

function TAtlasDebugSettingsSection.VisualizerKindCheck(AKind: TAtlasVisualizerKind): TCheckBox;
begin
  Result := FVisualizerKinds[AKind];
end;

function TAtlasDebugSettingsSection.StepFilterKindCheck(AKind: TStepFilterKind): TCheckBox;
begin
  Result := FStepFilterKinds[AKind];
end;

end.
