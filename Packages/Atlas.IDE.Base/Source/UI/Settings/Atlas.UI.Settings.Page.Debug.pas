unit Atlas.UI.Settings.Page.Debug;

// Reiter „Debuggen“: Visualisierer, Schrittfilter, Ereignisse und eigener Code.

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Text.StepFilter,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Debuggen“: Visualisierer, Schrittfilter, Ereignisse und eigener Code.</summary>
  TAtlasSettingsDebugPart = class(TAtlasSettingsPagePart)
  private
    FDebugVisualizerKinds: array[TAtlasVisualizerKind] of TCheckBox;
    FDebugVisualizerNameFields: TEdit;
    FDebugVisualizerMaxLength: TEdit;
    FDebugVisualizerTimeout: TEdit;
    FDebugVisualizerMaxImagePixels: TEdit;
    FDebugVisualizerEvaluation: TAtlasChoiceBox;
    FDebugStepFilterKinds: array[TStepFilterKind] of TCheckBox;
    FDebugStepFilterPatterns: TEdit;
    FDebugBreakOnNextEventExcluded: TEdit;
    FDebugExplainAccessViolationAllowCalls: TCheckBox;
    FDebugExceptionBannerIgnoreAtLocation: TCheckBox;
    FDebugOwnCodeFolders: TEdit;
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    function DebugStepFilterKindCheck(AKind: TStepFilterKind): TCheckBox;
    function DebugVisualizerKindCheck(AKind: TAtlasVisualizerKind): TCheckBox;
    property DebugVisualizerNameFieldsEdit: TEdit read FDebugVisualizerNameFields;
    property DebugVisualizerMaxLengthEdit: TEdit read FDebugVisualizerMaxLength;
    property DebugVisualizerEvaluationBox: TAtlasChoiceBox read FDebugVisualizerEvaluation;
    property DebugStepFilterPatternsEdit: TEdit read FDebugStepFilterPatterns;
    property DebugBreakOnNextEventExcludedEdit: TEdit read FDebugBreakOnNextEventExcluded;
    property DebugExplainAccessViolationAllowCallsCheck: TCheckBox read FDebugExplainAccessViolationAllowCalls;
    property DebugExceptionBannerIgnoreAtLocationCheck: TCheckBox read FDebugExceptionBannerIgnoreAtLocation;
    property DebugOwnCodeFoldersEdit: TEdit read FDebugOwnCodeFolders;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Settings.EventBreakNames,
  Atlas.UI.Strings,
  Atlas.Core.Settings.FolderList;

{ TAtlasSettingsDebugPart }

procedure TAtlasSettingsDebugPart.Build;
begin
  // Einzelnen Test im Debugger starten (#585); die Code Lens dazu steht unter Editor (codeLens.tests).
  AddSheet(TAtlasTextId.SettingsTabDebug);
  AddModuleSwitch('DebugEnabled');
  BindCheck('TestDebug', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestDebug)));
  BindCheck('TestBreakAtStart', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestBreakAtStart)));
  // Variablenwerte im Hover beim Debuggen (#891).
  BindCheck('DebugHoverValues', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugHoverValues)));
  // Visualisierer für häufige Typen (#835): Hauptschalter, Arten, Namensfelder, Grenzen, Auswertung.
  BindCheck('DebugVisualizers', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizers)));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Lists] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindLists));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Dictionaries] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindDictionaries));
  FDebugVisualizerKinds[TAtlasVisualizerKind.DataSets] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindDataSets));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Bytes] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindBytes));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Json] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindJson));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Colors] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindColors));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Guid] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindGuid));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Geometry] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindGeometry));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Graphics] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindGraphics));
  FDebugVisualizerNameFields := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerNameFields));
  FDebugVisualizerMaxLength := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerMaxLength));
  FDebugVisualizerTimeout := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerTimeout));
  FDebugVisualizerMaxImagePixels := AddNumber(
    TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerMaxImagePixels));
  FDebugVisualizerEvaluation := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerEvaluation),
    [TAtlasStrings.Text(TAtlasTextId.DebugVisualizerEvaluationFields),
    TAtlasStrings.Text(TAtlasTextId.DebugVisualizerEvaluationProperties),
    TAtlasStrings.Text(TAtlasTextId.DebugVisualizerEvaluationCalls)]);
  // Eigene Wertdarstellungen (#854): Schalter und Aufrufe in Vorlagen.
  BindCheck('DebugDisplayRules', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugDisplayRules)));
  BindCheck('DebugDisplayRulesAllowCalls', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugDisplayRulesAllowCalls)));
  // Gezielt hineinspringen (#836): Schalter und Tastenkürzel.
  BindCheck('DebugStepIntoTarget', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugStepIntoTarget)));
  // Schrittfilter beim Hineinspringen (#850): Schalter, Arten, Muster.
  BindCheck('DebugStepFilters', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugStepFilters)));
  FDebugStepFilterKinds[TStepFilterKind.Getters] := AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindGetters));
  FDebugStepFilterKinds[TStepFilterKind.Setters] := AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindSetters));
  FDebugStepFilterKinds[TStepFilterKind.Trivial] := AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindTrivial));
  FDebugStepFilterKinds[TStepFilterKind.Operators] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindOperators));
  FDebugStepFilterKinds[TStepFilterKind.EmptyConstructors] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindEmptyConstructors));
end;

procedure TAtlasSettingsDebugPart.Build2;
begin
  FDebugStepFilterPatterns := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsDebugStepFilterPatterns));
  BindKey('DebugStepIntoTargetKey', AddKey(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand)));
  // Beim nächsten Ereignis anhalten (#856): Schalter und ausgenommene Ereignisse.
  BindCheck('DebugBreakOnNextEvent', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugBreakOnNextEvent)));
  FDebugBreakOnNextEventExcluded := AddTextLine(
    TAtlasStrings.Text(TAtlasTextId.SettingsDebugBreakOnNextEventExcluded));
  // „kein Zugriff auf Wert“ erklären (#840).
  BindCheck('DebugExplainUnavailable', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExplainUnavailable)));
  // Vervollständigung in Debugger-Dialogen (#538).
  BindCheck('DebugCompletionInDialogs', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugCompletionInDialogs)));
  // Fenster „Auswerten“ (#784).
  BindCheck('DebugEvaluateWindow', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugEvaluateWindow)));
  BindCheck('DebugEvaluateReplaceCtrlF7', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugEvaluateReplaceCtrlF7)));
  // Zugriffsverletzung erklären (#865)
  BindCheck('DebugExplainAccessViolation', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExplainAccessViolation)));
  FDebugExplainAccessViolationAllowCalls :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExplainAccessViolationAllowCalls));
  // Exception-Verlauf beim Debuggen (#517).
  BindCheck('DebugExceptionHistory', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExceptionHistory)));
  // Nur eigener Code beim Debuggen (#578).
  BindCheck('DebugJustMyCode', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugJustMyCode)));
  FDebugOwnCodeFolders := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsDebugOwnCodeFolders));
  // Exception-Leiste beim Debuggen (#783).
  BindCheck('DebugExceptionBanner', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExceptionBanner)));
  FDebugExceptionBannerIgnoreAtLocation :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExceptionBannerIgnoreAtLocation));
  // Werte im Editor beim Debuggen (#508).
  BindCheck('DebugInlineValues', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugInlineValues)));
  BindText('DebugInlineValuesPerLine', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDebugInlineValuesPerLine)));
end;

procedure TAtlasSettingsDebugPart.BindMarks;
var
  VisualizerKind: TAtlasVisualizerKind;
  StepFilterKind: TStepFilterKind;
begin
  for VisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    FPage.Marks.Bind(FDebugVisualizerKinds[VisualizerKind], ['DebugVisualizerTypes']);
  end;
  FPage.Marks.Bind(FDebugVisualizerNameFields, ['DebugVisualizerNameFields']);
  FPage.Marks.Bind(FDebugVisualizerMaxLength, ['DebugVisualizerMaxLength']);
  FPage.Marks.Bind(FDebugVisualizerTimeout, ['DebugVisualizerTimeoutMs']);
  FPage.Marks.Bind(FDebugVisualizerMaxImagePixels, ['DebugVisualizerMaxImagePixels']);
  FPage.Marks.Bind(FDebugVisualizerEvaluation, ['DebugVisualizerEvaluation']);
  for StepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FPage.Marks.Bind(FDebugStepFilterKinds[StepFilterKind], ['DebugStepFilterKinds']);
  end;
  FPage.Marks.Bind(FDebugStepFilterPatterns, ['DebugStepFilterPatterns']);
  FPage.Marks.Bind(FDebugBreakOnNextEventExcluded, ['DebugBreakOnNextEventExcluded']);
  FPage.Marks.Bind(FDebugExplainAccessViolationAllowCalls, ['DebugExplainAccessViolationAllowCalls']);
  FPage.Marks.Bind(FDebugExceptionBannerIgnoreAtLocation, ['DebugExceptionBannerIgnoreAtLocation']);
  FPage.Marks.Bind(FDebugOwnCodeFolders, ['DebugOwnCodeFolders']);
end;

function TAtlasSettingsDebugPart.DebugVisualizerKindCheck(AKind: TAtlasVisualizerKind): TCheckBox;
begin
  Result := FDebugVisualizerKinds[AKind];
end;

function TAtlasSettingsDebugPart.DebugStepFilterKindCheck(AKind: TStepFilterKind): TCheckBox;
begin
  Result := FDebugStepFilterKinds[AKind];
end;

procedure TAtlasSettingsDebugPart.Load(const ASettings: TAtlasPluginSettings);
var
  VisualizerKind: TAtlasVisualizerKind;
  StepFilterKind: TStepFilterKind;
  VisualizerKinds: TAtlasVisualizerKinds;
  StepFilterKinds: TStepFilterKinds;
begin
  VisualizerKinds := TAtlasVisualizerSettings.ParseKinds(ASettings.DebugVisualizerTypes);
  for VisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    FDebugVisualizerKinds[VisualizerKind].Checked := VisualizerKind in VisualizerKinds;
  end;
  FDebugVisualizerNameFields.Text := ASettings.DebugVisualizerNameFields;
  FDebugVisualizerMaxLength.Text := IntToStr(ASettings.DebugVisualizerMaxLength);
  FDebugVisualizerTimeout.Text := IntToStr(ASettings.DebugVisualizerTimeoutMs);
  FDebugVisualizerMaxImagePixels.Text := IntToStr(ASettings.DebugVisualizerMaxImagePixels);
  FDebugVisualizerEvaluation.Choice := Ord(TAtlasVisualizerSettings.ParseEvaluation(ASettings.DebugVisualizerEvaluation));
  StepFilterKinds := TStepFilterNames.ParseKinds(ASettings.DebugStepFilterKinds);
  for StepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FDebugStepFilterKinds[StepFilterKind].Checked := StepFilterKind in StepFilterKinds;
  end;
  FDebugStepFilterPatterns.Text := ASettings.DebugStepFilterPatterns;
  FDebugBreakOnNextEventExcluded.Text := ASettings.DebugBreakOnNextEventExcluded;
  FDebugExplainAccessViolationAllowCalls.Checked := ASettings.DebugExplainAccessViolationAllowCalls;
  FDebugExceptionBannerIgnoreAtLocation.Checked := ASettings.DebugExceptionBannerIgnoreAtLocation;
  FDebugOwnCodeFolders.Text := ASettings.DebugOwnCodeFolders;
end;

procedure TAtlasSettingsDebugPart.Save(var ASettings: TAtlasPluginSettings);
var
  VisualizerKind: TAtlasVisualizerKind;
  StepFilterKind: TStepFilterKind;
  VisualizerKinds: TAtlasVisualizerKinds;
  StepFilterKinds: TStepFilterKinds;
begin
  VisualizerKinds := [];
  for VisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    if FDebugVisualizerKinds[VisualizerKind].Checked then
    begin
      Include(VisualizerKinds, VisualizerKind);
    end;
  end;
  ASettings.DebugVisualizerTypes := TAtlasVisualizerSettings.KindsText(VisualizerKinds);
  ASettings.DebugVisualizerNameFields := TAtlasVisualizerSettings.NormalizeNameFields(FDebugVisualizerNameFields.Text);
  ASettings.DebugVisualizerMaxLength := StrToIntDef(Trim(FDebugVisualizerMaxLength.Text),
    ASettings.DebugVisualizerMaxLength);
  ASettings.DebugVisualizerTimeoutMs := StrToIntDef(Trim(FDebugVisualizerTimeout.Text),
    ASettings.DebugVisualizerTimeoutMs);
  ASettings.DebugVisualizerMaxImagePixels := StrToIntDef(Trim(FDebugVisualizerMaxImagePixels.Text),
    ASettings.DebugVisualizerMaxImagePixels);
  ASettings.DebugVisualizerEvaluation := TAtlasVisualizerSettings.EvaluationNames[TAtlasVisualizerEvaluation(
    EnsureRange(FDebugVisualizerEvaluation.Choice, 0, Ord(High(TAtlasVisualizerEvaluation))))];
  StepFilterKinds := [];
  for StepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    if FDebugStepFilterKinds[StepFilterKind].Checked then
    begin
      Include(StepFilterKinds, StepFilterKind);
    end;
  end;
  ASettings.DebugStepFilterKinds := TStepFilterNames.KindsText(StepFilterKinds);
  ASettings.DebugStepFilterPatterns := TStepFilterNames.NormalizePatterns(FDebugStepFilterPatterns.Text);
  ASettings.DebugBreakOnNextEventExcluded := TAtlasEventBreakSettings.NormalizeExcluded(FDebugBreakOnNextEventExcluded.Text);
  ASettings.DebugExplainAccessViolationAllowCalls := FDebugExplainAccessViolationAllowCalls.Checked;
  ASettings.DebugExceptionBannerIgnoreAtLocation := FDebugExceptionBannerIgnoreAtLocation.Checked;
  ASettings.DebugOwnCodeFolders := TAtlasFolderList.Text(FDebugOwnCodeFolders.Text);
end;

end.
