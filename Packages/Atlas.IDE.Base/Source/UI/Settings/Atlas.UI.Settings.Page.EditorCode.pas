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
  Atlas.UI.Editor.RegionFolds,
  Atlas.Core.Settings.Plugin.Store,
  Atlas.Core.Problems.InlineHints;

{ TAtlasSettingsEditorCodePart }

procedure TAtlasSettingsEditorCodePart.Build;
begin
  // Austrittspunkte hervorheben (#698).
  BindCheck('ExitPoints', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExitPoints)));
  BindCheck('ExitPointsExceptions', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExitPointsExceptions)));
  BindCheck('ExitPointsLoops', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExitPointsLoops)));
  BindCheck('ExitPointsBadge', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExitPointsBadge)));
  // Neu zugewiesene Variablen (#712): an/aus, je Art ein Häkchen, Linie und Farbe.
  BindCheck('Reassigned', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassigned)));
  FReassignedTargets[TAtlasReassignedTarget.Locals] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedLocals));
  FReassignedTargets[TAtlasReassignedTarget.LoopVars] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedLoopVars));
  FReassignedTargets[TAtlasReassignedTarget.ValueParams] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedValueParams));
  FReassignedTargets[TAtlasReassignedTarget.VarParams] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedVarParams));
  FReassignedTargets[TAtlasReassignedTarget.Fields] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedFields));
  FReassignedStyle := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedStyle),
    [TAtlasStrings.Text(TAtlasTextId.SettingsReassignedStyleDotted),
    TAtlasStrings.Text(TAtlasTextId.SettingsReassignedStyleSolid),
    TAtlasStrings.Text(TAtlasTextId.SettingsReassignedStyleWavy)]);
  FReassignedColor := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedColor));
  // Typ des markierten Ausdrucks (#689): an/aus, Umwandlungen, Wert und Kürzel.
  BindCheck('ExpressionType', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExpressionType)));
  BindCheck('ExpressionTypeConversions', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExpressionTypeConversions)));
  BindCheck('ExpressionTypeConstValue', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExpressionTypeConstValue)));
  BindKey('ExpressionTypeKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ExpressionTypeCommand)));
  // Methodenrümpfe in Deklarationsreihenfolge (#660): wie die Deklaration, alphabetisch oder aus.
  FMethodPlacement := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacement),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementGrouped),
    TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementDeclaration),
    TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementAlphabetical),
    TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementOff)]);
  // Regionen beim Öffnen (#1814).
  FRegionFolds := AddChoice(TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.Setting), TAtlasRegionFoldsTexts.Choices);
  // Übersichtsleiste (#519): an/aus und je Art ein Häkchen.
  BindCheck('OverviewRuler', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewRuler)));
  FOverviewKinds[TAtlasOverviewKind.Diagnostics] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewDiagnostics));
  FOverviewKinds[TAtlasOverviewKind.Search] := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewSearch));
  FOverviewKinds[TAtlasOverviewKind.Changes] := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewChanges));
  FOverviewKinds[TAtlasOverviewKind.Breakpoints] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewBreakpoints));
  // Kommentar beim Enter fortsetzen (#696).
  BindCheck('ContinueComments', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsContinueComments)));
  BindCheck('ContinueCommentsLineComments', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsContinueCommentsLineComments)));
  BindCheck('ContinueCommentsLists', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsContinueCommentsLists)));
  FContinueCommentsBlockPrefix := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsContinueCommentsBlockPrefix));
  // Markierung beim Tippen umschließen (#672).
  BindCheck('WrapSelection', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWrapSelection)));
  BindText('WrapSelectionChars', AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWrapSelectionChars)));
  // Anweisung vervollständigen (#697).
  BindCheck('CompleteStatement', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCompleteStatement)));
  BindKey('CompleteStatementKey', AddKey(TAtlasStrings.Text(TAtlasTextId.CompleteStatementCommand)));
  FCompleteStatementBeginEnd := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsCompleteStatementBeginEnd),
    [TAtlasStrings.Text(TAtlasTextId.SettingsBeginEndAlways),
    TAtlasStrings.Text(TAtlasTextId.SettingsBeginEndMultiLine),
      TAtlasStrings.Text(TAtlasTextId.SettingsBeginEndNever)]);
end;

procedure TAtlasSettingsEditorCodePart.Build2;
begin
  FCompleteStatementTryKind := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsCompleteStatementTryKind),
    [TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryFinally),
    TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryExcept), TAtlasStrings.Text(TAtlasTextId.SettingsTryKindAsk)]);
  BindCheck('CompleteStatementMethodBody', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCompleteStatementMethodBody)));
  // Formatieren (#43).
  BindCheck('FormatCode', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFormatCode)));
  BindKey('FormatCodeKey', AddKey(TAtlasStrings.Text(TAtlasTextId.FormatCodeCommand)));
  // Muster fortsetzen (#671).
  BindCheck('ContinuePattern', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsContinuePattern)));
  BindText('ContinuePatternMinLines', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsContinuePatternMinLines)));
  // Mehrere Einfügemarken (#589, experimentell).
  BindCheck('MultiCursor', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursor)));
  FMultiCursorModifier := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorModifier),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorAlt),
    TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorCtrl)]);
  BindKey('MultiCursorNextKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorNext)));
  BindKey('MultiCursorSkipKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorSkip)));
  BindKey('MultiCursorLineEndsKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorLineEnds)));
  BindKey('MultiCursorAboveKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorAbove)));
  BindKey('MultiCursorBelowKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorBelow)));
  // Bezeichner live mitziehen (#658, experimentell).
  BindCheck('LinkedEditing', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsLinkedEditing)));
  // Einfügen mit uses-Ergänzung (#515, experimentell).
  FSmartPaste := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsSmartPaste),
    [TAtlasStrings.Text(TAtlasTextId.SettingsSmartPasteOff), TAtlasStrings.Text(TAtlasTextId.SettingsSmartPasteUses),
    TAtlasStrings.Text(TAtlasTextId.SettingsSmartPasteIndent),
    TAtlasStrings.Text(TAtlasTextId.SettingsSmartPasteBoth)]);
  FOverviewKinds[TAtlasOverviewKind.Bookmarks] := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewBookmarks));
  FOverviewKinds[TAtlasOverviewKind.Cursor] := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewCursor));
  // Rekursionssymbole im Rand (#623).
  BindCheck('RecursionMarkers', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsRecursionMarkers)));
  BindText('RecursionMarkersDepth', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsRecursionMarkersDepth)));
  // Fehlertext am Zeilenende (#509); die Reihenfolge folgt TAtlasInlineDiagnosticsMode.
  FInlineDiagnostics := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnostics),
    [TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnosticsOff),
    TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnosticsErrors),
    TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnosticsWarnings),
    TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnosticsAll)]);
  // Marken folgen ihrer Zeile sofort (#1818).
  BindCheck('TrackLines', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTrackLines)));
end;

procedure TAtlasSettingsEditorCodePart.Build3;
begin
  BindCheck('CodeLensTestUnit', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensTestUnit)));
  BindCheck('Metrics', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMetricsAll)));
  BindCheck('TodoList', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTodoList)));
  BindCheck('MetricsReport', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMetricsReport)));
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
