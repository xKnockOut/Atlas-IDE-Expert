unit Atlas.UI.Settings.Page.EditorCode;

// Reiter „Editor“, zweiter Teil: Bearbeiten (neu zugewiesene Variablen, Methodenreihenfolge, Übersichtsleiste,
// Kommentare, Anweisungen, Einfügemarken, Fehlertext, Lesezeichen).

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
  /// Übersichtsleiste, Kommentare, Anweisungen, Einfügemarken, Fehlertext, Lesezeichen).</summary>
  TAtlasSettingsEditorCodePart = class(TAtlasSettingsPagePart)
  private
    /// <summary>Fehlertext am Zeilenende (#509): aus, nur Fehler, Fehler und Warnungen, alle.</summary>
    FInlineDiagnostics: TAtlasChoiceBox;
    FQuickBookmarkChordWait: TEdit;
    FQuickBookmarksScope: TAtlasChoiceBox;
    FReassignedTargets: array[TAtlasReassignedTarget] of TCheckBox;
    FReassignedStyle: TAtlasChoiceBox;
    FReassignedColor: TEdit;
    FMethodPlacement: TAtlasChoiceBox;
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
    property QuickBookmarkChordWaitEdit: TEdit read FQuickBookmarkChordWait;
    property QuickBookmarksScopeBox: TAtlasChoiceBox read FQuickBookmarksScope;
    property ReassignedStyleBox: TAtlasChoiceBox read FReassignedStyle;
    property ReassignedColorEdit: TEdit read FReassignedColor;
    /// <summary>Zum Testen: Methodenrümpfe in Deklarationsreihenfolge (#660).</summary>
    property MethodPlacementBox: TAtlasChoiceBox read FMethodPlacement;
    /// <summary>Zum Testen: Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).</summary>
    property InlineDiagnostics: TAtlasChoiceBox read FInlineDiagnostics;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  Atlas.UI.Strings,
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
    [TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementDeclaration),
    TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementAlphabetical),
    TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementOff)]);
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
    TAtlasStrings.Text(TAtlasTextId.SettingsBeginEndMultiLine), TAtlasStrings.Text(TAtlasTextId.SettingsBeginEndNever)]);
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
  // Persönliche Notizen an Codezeilen (#545).
  BindCheck('Notes', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNotes)));
  // Benannte Lesezeichen (#622): Funktion und Ablage für das Team; die Taste steht bei den Editorbefehlen.
  BindCheck('BookmarksNamed', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBookmarksNamed)));
  BindCheck('BookmarksShared', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBookmarksShared)));
  // Schnelle Lesezeichen (#1104): Spalte, Tasten, Akkord-Wartezeit, Sprungbereich, Übernahme der IDE-Lesezeichen.
  BindCheck('QuickBookmarks', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarks)));
  BindCheck('QuickBookmarksGutter', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksGutter)));
  BindCheck('QuickBookmarksGutterClick', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksGutterClick)));
  BindCheck('QuickBookmarksNumberedKeys', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksNumberedKeys)));
  BindKey('QuickBookmarkKey', AddKey(TAtlasStrings.Text(TAtlasTextId.QuickBookmarkToggleCommand)));
  FQuickBookmarkChordWait := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarkChordWait));
  // Reihenfolge wie AtlasQuickBookmarkScopes.
  FQuickBookmarksScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksScopeProject),
    TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksScopeFile)]);
  BindCheck('QuickBookmarksImportIde', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksImportIde)));
end;

procedure TAtlasSettingsEditorCodePart.Build3;
begin
  BindCheck('CodeLensTestUnit', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensTestUnit)));
  BindCheck('CodeLensMetrics', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensMetrics)));
  BindCheck('Metrics', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMetricsAll)));
  BindCheck('CodeLensTests', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensTests)));
  BindCheck('TodoList', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTodoList)));
  BindCheck('BaselineUpdate', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBaselineUpdate)));
  BindCheck('MetricsReport', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMetricsReport)));
  BindCheck('DfmPropertyRules', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDfmPropertyRules)));
end;

function TAtlasSettingsEditorCodePart.ReassignedTargetCheck(ATarget: TAtlasReassignedTarget): TCheckBox;
begin
  Result := FReassignedTargets[ATarget];
end;

procedure TAtlasSettingsEditorCodePart.BindMarks;
var
  Kind: TAtlasOverviewKind;
  Target: TAtlasReassignedTarget;
begin
  FPage.Bind('InlineDiagnostics', FInlineDiagnostics);
  for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
  begin
    FPage.Marks.Bind(FReassignedTargets[Target], ['ReassignedTargets']);
  end;
  FPage.Marks.Bind(FReassignedStyle, ['ReassignedStyle']);
  FPage.Marks.Bind(FReassignedColor, ['ReassignedColor']);
  FPage.Marks.Bind(FMethodPlacement, ['MethodPlacement']);
  for Kind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
  begin
    FPage.Marks.Bind(FOverviewKinds[Kind], ['OverviewRulerKinds']);
  end;
  FPage.Marks.Bind(FContinueCommentsBlockPrefix, ['ContinueCommentsBlockPrefix']);
  FPage.Marks.Bind(FCompleteStatementBeginEnd, ['CompleteStatementBeginEnd']);
  FPage.Marks.Bind(FCompleteStatementTryKind, ['CompleteStatementTryKind']);
  FPage.Marks.Bind(FMultiCursorModifier, ['MultiCursorModifier']);
  FPage.Marks.Bind(FSmartPaste, ['SmartPaste']);
  FPage.Marks.Bind(FInlineDiagnostics, ['InlineDiagnostics']);
  FPage.Marks.Bind(FQuickBookmarkChordWait, ['QuickBookmarkChordWait']);
  FPage.Marks.Bind(FQuickBookmarksScope, ['QuickBookmarksScope']);
end;

procedure TAtlasSettingsEditorCodePart.Load(const ASettings: TAtlasPluginSettings);
var
  Kind: TAtlasOverviewKind;
  Kinds: TAtlasOverviewKinds;
  Target: TAtlasReassignedTarget;
  Targets: TAtlasReassignedTargets;
begin
  Targets := TAtlasReassignedNames.ParseTargets(ASettings.ReassignedTargets);
  for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
  begin
    FReassignedTargets[Target].Checked := Target in Targets;
  end;
  FReassignedStyle.Choice := Ord(TAtlasReassignedNames.StyleOf(ASettings.ReassignedStyle));
  FReassignedColor.Text := ASettings.ReassignedColor;
  FMethodPlacement.Choice := Max(0, IndexText(ASettings.MethodPlacement, AtlasMethodPlacements));
  Kinds := TAtlasOverview.Kinds(ASettings.OverviewRulerKinds);
  for Kind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
  begin
    FOverviewKinds[Kind].Checked := Kind in Kinds;
  end;
  FContinueCommentsBlockPrefix.Text := ASettings.ContinueCommentsBlockPrefix;
  // Reihenfolge der Auswahl: always, multiLine, never bzw. finally, except, ask.
  FCompleteStatementBeginEnd.Choice := 1;
  if ASettings.CompleteStatementBeginEnd = TAtlasPluginSettings.BeginEndAlways then
  begin
    FCompleteStatementBeginEnd.Choice := 0;
  end
  else if ASettings.CompleteStatementBeginEnd = TAtlasPluginSettings.BeginEndNever then
  begin
    FCompleteStatementBeginEnd.Choice := 2;
  end;
  FCompleteStatementTryKind.Choice := 0;
  if ASettings.CompleteStatementTryKind = TAtlasPluginSettings.TryKindExcept then
  begin
    FCompleteStatementTryKind.Choice := 1;
  end
  else if ASettings.CompleteStatementTryKind = TAtlasPluginSettings.TryKindAsk then
  begin
    FCompleteStatementTryKind.Choice := 2;
  end;
  FSmartPaste.Choice := Max(0, IndexText(ASettings.SmartPaste, ['off', 'uses', 'indent', 'both']));
  FMultiCursorModifier.Choice := 0;
  if ASettings.MultiCursorModifier = TAtlasPluginSettings.MultiCursorModifierCtrl then
  begin
    FMultiCursorModifier.Choice := 1;
  end;
  FInlineDiagnostics.Choice := Ord(TAtlasInlineDiagnostics.ModeOf(ASettings.InlineDiagnostics));
  FQuickBookmarkChordWait.Text := IntToStr(ASettings.QuickBookmarkChordWait);
  FQuickBookmarksScope.Choice := Max(0, IndexText(ASettings.QuickBookmarksScope, AtlasQuickBookmarkScopes));
end;

procedure TAtlasSettingsEditorCodePart.Save(var ASettings: TAtlasPluginSettings);
var
  Kind: TAtlasOverviewKind;
  Kinds: TAtlasOverviewKinds;
  Target: TAtlasReassignedTarget;
  Targets: TAtlasReassignedTargets;
begin
  Targets := [];
  for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
  begin
    if FReassignedTargets[Target].Checked then
    begin
      Include(Targets, Target);
    end;
  end;
  ASettings.ReassignedTargets := TAtlasReassignedNames.TargetsText(Targets);
  ASettings.ReassignedStyle := TAtlasReassignedNames.Styles[TAtlasReassignedStyle(EnsureRange(
    FReassignedStyle.Choice, 0, Ord(High(TAtlasReassignedStyle))))];
  ASettings.ReassignedColor := TAtlasReassignedNames.NormalizeColor(FReassignedColor.Text);
  ASettings.MethodPlacement := AtlasMethodPlacements[EnsureRange(FMethodPlacement.Choice, 0,
    High(AtlasMethodPlacements))];
  Kinds := [];
  for Kind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
  begin
    if FOverviewKinds[Kind].Checked then
    begin
      Include(Kinds, Kind);
    end;
  end;
  ASettings.OverviewRulerKinds := TAtlasOverview.KindsText(Kinds);
  // Leerraum am Rand gehört zum Präfix (' * ').
  ASettings.ContinueCommentsBlockPrefix := FContinueCommentsBlockPrefix.Text;
  case FCompleteStatementBeginEnd.Choice of
    0:
      ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.BeginEndAlways;
    2:
      ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.BeginEndNever;
  else
    ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.BeginEndMultiLine;
  end;
  case FCompleteStatementTryKind.Choice of
    1:
      ASettings.CompleteStatementTryKind := TAtlasPluginSettings.TryKindExcept;
    2:
      ASettings.CompleteStatementTryKind := TAtlasPluginSettings.TryKindAsk;
  else
    ASettings.CompleteStatementTryKind := TAtlasPluginSettings.TryKindFinally;
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
  ASettings.MultiCursorModifier := TAtlasPluginSettings.MultiCursorModifierAlt;
  if FMultiCursorModifier.Choice = 1 then
  begin
    ASettings.MultiCursorModifier := TAtlasPluginSettings.MultiCursorModifierCtrl;
  end;
  ASettings.InlineDiagnostics := TAtlasInlineDiagnostics.ModeName(
    TAtlasInlineDiagnosticsMode(EnsureRange(FInlineDiagnostics.Choice, 0, Ord(High(TAtlasInlineDiagnosticsMode)))));
  ASettings.QuickBookmarkChordWait := EnsureRange(StrToIntDef(Trim(FQuickBookmarkChordWait.Text),
    ASettings.QuickBookmarkChordWait), 0, TAtlasPluginSettings.MaxQuickChordWait);
  ASettings.QuickBookmarksScope := AtlasQuickBookmarkScopes[EnsureRange(FQuickBookmarksScope.Choice, 0,
    High(AtlasQuickBookmarkScopes))];
end;

end.
