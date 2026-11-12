unit Atlas.UI.Settings.Page.EditorCode;

// Reiter „Editor“, zweiter Teil: Bearbeiten (neu zugewiesene Variablen, Methodenreihenfolge, Übersichtsleiste,
// Kommentare, Anweisungen, Einfügemarken, Fehlertext, Code Lens).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Settings.Reassigned,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Editor“, zweiter Teil: Bearbeiten (neu zugewiesene Variablen, Methodenreihenfolge,
  /// Übersichtsleiste, Kommentare, Anweisungen, Einfügemarken, Fehlertext, Code Lens).</summary>
  TAtlasSettingsEditorCodePart = class(TAtlasSettingsPagePart)
  private
    /// <summary>Fehlertext am Zeilenende (#509): aus, nur Fehler, Fehler und Warnungen, alle.</summary>
    FInlineDiagnostics: TAtlasChoiceBox;
    FReassignedTargets: array[TAtlasReassignedTarget] of TCheckBox;
    FReassignedStyle: TAtlasChoiceBox;
    FReassignedColor: TEdit;
    FMethodPlacement: TAtlasChoiceBox;
    /// <summary>Regionen beim Öffnen (#1814): unverändert, zu, auf oder aus.</summary>
    FRegionFolds: TAtlasChoiceBox;
    FOverviewKinds: array[TAtlasOverviewKind] of TCheckBox;
    FContinueCommentsBlockPrefix: TEdit;
    FCompleteStatementBeginEnd: TAtlasChoiceBox;
    FCompleteStatementTryKind: TAtlasChoiceBox;
    FSmartPaste: TAtlasChoiceBox;
    FMultiCursorModifier: TAtlasChoiceBox;
    procedure Save2(var ASettings: TAtlasPluginSettings);
  public
    procedure Build;
    procedure Build2;
    procedure Build3;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>Zum Testen: Häkchen je Art, Linie und Farbe (#712).</summary>
    function ReassignedTargetCheck(ATarget: TAtlasReassignedTarget): TCheckBox;
    property ContinueCommentsBlockPrefix: TEdit read FContinueCommentsBlockPrefix;
    property CompleteStatementBeginEnd: TAtlasChoiceBox read FCompleteStatementBeginEnd;
    property CompleteStatementTryKind: TAtlasChoiceBox read FCompleteStatementTryKind;
    property SmartPaste: TAtlasChoiceBox read FSmartPaste;
    property MultiCursorModifier: TAtlasChoiceBox read FMultiCursorModifier;
    property ReassignedStyleBox: TAtlasChoiceBox read FReassignedStyle;
    property ReassignedColorEdit: TEdit read FReassignedColor;
    /// <summary>Zum Testen: Methodenrümpfe in Deklarationsreihenfolge (#660).</summary>
    property MethodPlacementBox: TAtlasChoiceBox read FMethodPlacement;
    /// <summary>Zum Testen: Regionen beim Öffnen (#1814).</summary>
    property RegionFoldsBox: TAtlasChoiceBox read FRegionFolds;
    /// <summary>Zum Testen: Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).</summary>
    property InlineDiagnostics: TAtlasChoiceBox read FInlineDiagnostics;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Editor.RegionFolds,
  Atlas.Core.Settings.Plugin.Store,
  Atlas.Core.Problems.InlineHints;

{ TAtlasSettingsEditorCodePart }

procedure TAtlasSettingsEditorCodePart.Build;
begin
  // Austrittspunkte hervorheben (#698).
  BindCheck('ExitPoints', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExitPoints)));
  BindCheck('ExitPointsExceptions',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExitPointsExceptions)));
  BindCheck('ExitPointsLoops', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExitPointsLoops)));
  BindCheck('ExitPointsBadge', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExitPointsBadge)));
  // Neu zugewiesene Variablen (#712): an/aus, je Art ein Häkchen, Linie und Farbe.
  BindCheck('Reassigned', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassigned)));
  FReassignedTargets[TAtlasReassignedTarget.Locals] :=
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedLocals));
  FReassignedTargets[TAtlasReassignedTarget.LoopVars] :=
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedLoopVars));
  FReassignedTargets[TAtlasReassignedTarget.ValueParams] :=
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedValueParams));
  FReassignedTargets[TAtlasReassignedTarget.VarParams] :=
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedVarParams));
  FReassignedTargets[TAtlasReassignedTarget.Fields] :=
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedFields));
  FReassignedStyle := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedStyle),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedStyleDotted),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedStyleSolid),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedStyleWavy)]);
  FReassignedColor := AddTextLine(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReassignedColor));
  // Typ des markierten Ausdrucks (#689): an/aus, Umwandlungen, Wert und Kürzel.
  BindCheck('ExpressionType', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExpressionType)));
  BindCheck('ExpressionTypeConversions',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExpressionTypeConversions)));
  BindCheck('ExpressionTypeConstValue',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExpressionTypeConstValue)));
  BindKey('ExpressionTypeKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ExpressionTypeCommand)));
  // Methodenrümpfe in Deklarationsreihenfolge (#660): wie die Deklaration, alphabetisch oder aus.
  FMethodPlacement := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMethodPlacement),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMethodPlacementGrouped),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMethodPlacementDeclaration),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMethodPlacementAlphabetical),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMethodPlacementOff)]);
  // Regionen beim Öffnen (#1814).
  FRegionFolds := AddChoice(TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.Setting), TAtlasRegionFoldsTexts.Choices);
  // Übersichtsleiste (#519): an/aus und je Art ein Häkchen.
  BindCheck('OverviewRuler', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOverviewRuler)));
  FOverviewKinds[TAtlasOverviewKind.Diagnostics] :=
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOverviewDiagnostics));
  FOverviewKinds[TAtlasOverviewKind.Search] := AddCheck(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsOverviewSearch));
  FOverviewKinds[TAtlasOverviewKind.Changes] := AddCheck(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsOverviewChanges));
  FOverviewKinds[TAtlasOverviewKind.Breakpoints] :=
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOverviewBreakpoints));
  // Kommentar beim Enter fortsetzen (#696).
  BindCheck('ContinueComments', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsContinueComments)));
  BindCheck('ContinueCommentsLineComments',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsContinueCommentsLineComments)));
  BindCheck('ContinueCommentsLists',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsContinueCommentsLists)));
  FContinueCommentsBlockPrefix := AddTextLine(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsContinueCommentsBlockPrefix));
  // Markierung beim Tippen umschließen (#672).
  BindCheck('WrapSelection', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsWrapSelection)));
  BindText('WrapSelectionChars',
    AddTextLine(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsWrapSelectionChars)));
end;

procedure TAtlasSettingsEditorCodePart.Build2;
begin
  // Anweisung vervollständigen (#697).
  BindCheck('CompleteStatement', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCompleteStatement)));
  BindKey('CompleteStatementKey', AddKey(TAtlasStrings.Text(TAtlasTextId.CompleteStatementCommand)));
  FCompleteStatementBeginEnd := AddChoice(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsCompleteStatementBeginEnd),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBeginEndAlways),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBeginEndMultiLine),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBeginEndNever)]);
  FCompleteStatementTryKind := AddChoice(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsCompleteStatementTryKind),
    [TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryFinally),
    TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryExcept),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTryKindAsk)]);
  BindCheck('CompleteStatementMethodBody',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCompleteStatementMethodBody)));
  // Formatieren (#43).
  BindCheck('FormatCode', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFormatCode)));
  BindKey('FormatCodeKey', AddKey(TAtlasStrings.Text(TAtlasTextId.FormatCodeCommand)));
  // Muster fortsetzen (#671).
  BindCheck('ContinuePattern', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsContinuePattern)));
  BindText('ContinuePatternMinLines',
    AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsContinuePatternMinLines)));
  // Mehrere Einfügemarken (#589, experimentell).
  BindCheck('MultiCursor', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursor)));
  FMultiCursorModifier := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursorModifier),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursorAlt),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursorCtrl)]);
  BindKey('MultiCursorNextKey', AddKey(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursorNext)));
  BindKey('MultiCursorSkipKey', AddKey(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursorSkip)));
  BindKey('MultiCursorLineEndsKey',
    AddKey(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursorLineEnds)));
  BindKey('MultiCursorAboveKey', AddKey(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursorAbove)));
  BindKey('MultiCursorBelowKey', AddKey(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMultiCursorBelow)));
  // Bezeichner live mitziehen (#658, experimentell).
  BindCheck('LinkedEditing', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsLinkedEditing)));
  // Einfügen mit uses-Ergänzung (#515, experimentell).
  FSmartPaste := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSmartPaste),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSmartPasteOff),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSmartPasteUses),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSmartPasteIndent),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSmartPasteBoth)]);
  FOverviewKinds[TAtlasOverviewKind.Bookmarks] := AddCheck(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsOverviewBookmarks));
  FOverviewKinds[TAtlasOverviewKind.Cursor] := AddCheck(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsOverviewCursor));
  // Rekursionssymbole im Rand (#623).
  BindCheck('RecursionMarkers', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsRecursionMarkers)));
  BindText('RecursionMarkersDepth',
    AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsRecursionMarkersDepth)));
  // Fehlertext am Zeilenende (#509); die Reihenfolge folgt TAtlasInlineDiagnosticsMode.
  FInlineDiagnostics := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlineDiagnostics),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlineDiagnosticsOff),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlineDiagnosticsErrors),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlineDiagnosticsWarnings),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlineDiagnosticsAll)]);
  // Marken folgen ihrer Zeile sofort (#1818).
  BindCheck('TrackLines', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTrackLines)));
end;

procedure TAtlasSettingsEditorCodePart.Build3;
begin
  BindCheck('CodeLensTestUnit', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCodeLensTestUnit)));
  BindCheck('Metrics', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMetricsAll)));
  BindCheck('TodoList', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTodoList)));
  BindCheck('MetricsReport', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMetricsReport)));
end;

function TAtlasSettingsEditorCodePart.ReassignedTargetCheck(ATarget: TAtlasReassignedTarget): TCheckBox;
begin
  Result := FReassignedTargets[ATarget];
end;

procedure TAtlasSettingsEditorCodePart.BindMarks;
var
  mKind: TAtlasOverviewKind;
  mTarget: TAtlasReassignedTarget;
begin
  FPage.Bind('InlineDiagnostics', FInlineDiagnostics);
  for mTarget := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
  begin
    FPage.Marks.Bind(FReassignedTargets[mTarget], ['ReassignedTargets']);
  end;
  FPage.Marks.Bind(FReassignedStyle, ['ReassignedStyle']);
  FPage.Marks.Bind(FReassignedColor, ['ReassignedColor']);
  FPage.Marks.Bind(FMethodPlacement, ['MethodPlacement']);
  FPage.Marks.Bind(FRegionFolds, ['RegionFolds']);
  for mKind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
  begin
    FPage.Marks.Bind(FOverviewKinds[mKind], ['OverviewRulerKinds']);
  end;
  FPage.Marks.Bind(FContinueCommentsBlockPrefix, ['ContinueCommentsBlockPrefix']);
  FPage.Marks.Bind(FCompleteStatementBeginEnd, ['CompleteStatementBeginEnd']);
  FPage.Marks.Bind(FCompleteStatementTryKind, ['CompleteStatementTryKind']);
  FPage.Marks.Bind(FMultiCursorModifier, ['MultiCursorModifier']);
  FPage.Marks.Bind(FSmartPaste, ['SmartPaste']);
  FPage.Marks.Bind(FInlineDiagnostics, ['InlineDiagnostics']);
end;

procedure TAtlasSettingsEditorCodePart.Load(const ASettings: TAtlasPluginSettings);
var
  mKind: TAtlasOverviewKind;
  mKinds: TAtlasOverviewKinds;
  mTarget: TAtlasReassignedTarget;
  mTargets: TAtlasReassignedTargets;
begin
  mTargets := TAtlasReassignedNames.ParseTargets(ASettings.ReassignedTargets);
  for mTarget := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
  begin
    FReassignedTargets[mTarget].Checked := mTarget in mTargets;
  end;
  FReassignedStyle.Choice := Ord(TAtlasReassignedNames.StyleOf(ASettings.ReassignedStyle));
  FReassignedColor.Text := ASettings.ReassignedColor;
  FMethodPlacement.Choice := Max(0, IndexText(ASettings.MethodPlacement, cAtlasMethodPlacements));
  FRegionFolds.Choice := Max(0, IndexText(ASettings.RegionFolds, cAtlasRegionFoldModes));
  mKinds := TAtlasOverview.Kinds(ASettings.OverviewRulerKinds);
  for mKind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
  begin
    FOverviewKinds[mKind].Checked := mKind in mKinds;
  end;
  FContinueCommentsBlockPrefix.Text := ASettings.ContinueCommentsBlockPrefix;
  // Reihenfolge der Auswahl: always, multiLine, never bzw. finally, except, ask.
  FCompleteStatementBeginEnd.Choice := 1;
  if ASettings.CompleteStatementBeginEnd = TAtlasPluginSettings.cBeginEndAlways then
  begin
    FCompleteStatementBeginEnd.Choice := 0;
  end
  else if ASettings.CompleteStatementBeginEnd = TAtlasPluginSettings.cBeginEndNever then
  begin
    FCompleteStatementBeginEnd.Choice := 2;
  end;
  FCompleteStatementTryKind.Choice := 0;
  if ASettings.CompleteStatementTryKind = TAtlasPluginSettings.cTryKindExcept then
  begin
    FCompleteStatementTryKind.Choice := 1;
  end
  else if ASettings.CompleteStatementTryKind = TAtlasPluginSettings.cTryKindAsk then
  begin
    FCompleteStatementTryKind.Choice := 2;
  end;
  FSmartPaste.Choice := Max(0, IndexText(ASettings.SmartPaste, ['off', 'uses', 'indent', 'both']));
  FMultiCursorModifier.Choice := 0;
  if ASettings.MultiCursorModifier = TAtlasPluginSettings.cMultiCursorModifierCtrl then
  begin
    FMultiCursorModifier.Choice := 1;
  end;
  FInlineDiagnostics.Choice := Ord(TAtlasInlineDiagnostics.ModeOf(ASettings.InlineDiagnostics));
end;

procedure TAtlasSettingsEditorCodePart.Save(var ASettings: TAtlasPluginSettings);
var
  mKind: TAtlasOverviewKind;
  mKinds: TAtlasOverviewKinds;
  mTarget: TAtlasReassignedTarget;
  mTargets: TAtlasReassignedTargets;
begin
  mTargets := [];
  for mTarget := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
  begin
    if FReassignedTargets[mTarget].Checked then
    begin
      Include(mTargets, mTarget);
    end;
  end;
  ASettings.ReassignedTargets := TAtlasReassignedNames.TargetsText(mTargets);
  ASettings.ReassignedStyle := TAtlasReassignedNames.cStyles[TAtlasReassignedStyle(EnsureRange(
    FReassignedStyle.Choice, 0, Ord(High(TAtlasReassignedStyle))))];
  ASettings.ReassignedColor := TAtlasReassignedNames.NormalizeColor(FReassignedColor.Text);
  ASettings.MethodPlacement := cAtlasMethodPlacements[EnsureRange(FMethodPlacement.Choice, 0,
    High(cAtlasMethodPlacements))];
  mKinds := [];
  for mKind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
  begin
    if FOverviewKinds[mKind].Checked then
    begin
      Include(mKinds, mKind);
    end;
  end;
  ASettings.OverviewRulerKinds := TAtlasOverview.KindsText(mKinds);
  // Leerraum am Rand gehört zum Präfix (' * ').
  ASettings.ContinueCommentsBlockPrefix := FContinueCommentsBlockPrefix.Text;
  case FCompleteStatementBeginEnd.Choice of
    0:
      ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.cBeginEndAlways;
    2:
      ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.cBeginEndNever;
  else
    ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.cBeginEndMultiLine;
  end;
  case FCompleteStatementTryKind.Choice of
    1:
      ASettings.CompleteStatementTryKind := TAtlasPluginSettings.cTryKindExcept;
    2:
      ASettings.CompleteStatementTryKind := TAtlasPluginSettings.cTryKindAsk;
  else
    ASettings.CompleteStatementTryKind := TAtlasPluginSettings.cTryKindFinally;
  end;
  ASettings.SmartPaste := 'off';
  case FSmartPaste.Choice of
    1:
      ASettings.SmartPaste := 'uses';
    2:
      ASettings.SmartPaste := 'indent';
    3:
      ASettings.SmartPaste := 'both';
  end;
  Save2(ASettings);
end;

procedure TAtlasSettingsEditorCodePart.Save2(var ASettings: TAtlasPluginSettings);
begin
  ASettings.RegionFolds := cAtlasRegionFoldModes[EnsureRange(FRegionFolds.Choice, 0, High(cAtlasRegionFoldModes))];
  ASettings.MultiCursorModifier := TAtlasPluginSettings.cMultiCursorModifierAlt;
  if FMultiCursorModifier.Choice = 1 then
  begin
    ASettings.MultiCursorModifier := TAtlasPluginSettings.cMultiCursorModifierCtrl;
  end;
  ASettings.InlineDiagnostics := TAtlasInlineDiagnostics.ModeName(
    TAtlasInlineDiagnosticsMode(EnsureRange(FInlineDiagnostics.Choice, 0, Ord(High(TAtlasInlineDiagnosticsMode)))));
end;

end.
