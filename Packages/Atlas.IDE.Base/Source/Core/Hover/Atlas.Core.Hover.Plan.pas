unit Atlas.Core.Hover.Plan;

// Entscheidungen des Hover-Tooltips im Editor (#442), ohne VCL und Open Tools API. Die IDE-Schicht
// (Atlas.IDE.Hover.Editor, Atlas.IDE.Hover.EditorContent) liest Editor, Maus und Einstellungen und ruft nur
// noch diese Funktionen:
//   - TAtlasHoverPlan: Wort unter der Maus und seine Schlüssel, ob der Tooltip etwas zu zeigen hat, neu
//     zugewiesene Variablen (#712), Typkette für die Visualisierer (#835), Erklärung „kein Zugriff“ (#840),
//     Zeile des aufgeklappten Werts als Ziel der Aktionen (#895), Beispiel aus dem Katalog (#145), Kopieren,
//     Kennungen der Aktionen unter Problemen (#621, #896, #909, #1779) und welche Links der Tooltip öffnet (#654).
//   - TAtlasHoverKeys: welche Taste der Tooltip nimmt und was sie tut (#588, #909, #895), Zeitgeber nach dem
//     Bezeichner unter der Maus und beim Verlassen.

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Hover.View,
  Atlas.Core.Problems.Explanation;

type
  /// <summary>Woher Strg+C im Tooltip den Text nimmt.</summary>
  TAtlasHoverCopySource = (
    /// <summary>Markierter Doku-Text (#654).</summary>
    Selection,
    /// <summary>Gezeigte Liste der published-Mitglieder (#110).</summary>
    Members,
    /// <summary>Deklaration.</summary>
    Declaration);

  /// <summary>Was der Bezeichner unter der Maus mit den Zeitgebern macht.</summary>
  TAtlasHoverTrack = (
    /// <summary>Kein Bezeichner: Warten verwerfen, offenen Tooltip verzögert schließen.</summary>
    Leave,
    /// <summary>Derselbe wie im offenen Tooltip: offen lassen.</summary>
    Stay,
    /// <summary>Neuer Bezeichner: Anzeigen neu abwarten, offenen Tooltip verzögert schließen.</summary>
    Restart,
    /// <summary>Derselbe, auf den schon gewartet wird: nichts ändern.</summary>
    Wait);

  /// <summary>Ergebnis des Zeitgebers zum Schließen.</summary>
  TAtlasHoverHideStep = (
    /// <summary>Schließen.</summary>
    Close,
    /// <summary>Angeheftet: offen lassen, nicht weiter prüfen.</summary>
    KeepPinned,
    /// <summary>Maus über dem Tooltip: offen lassen und später wieder prüfen.</summary>
    Recheck);

  /// <summary>Befehl einer Taste im offenen Tooltip.</summary>
  TAtlasHoverKeyCommand = (None, Close, Back, Navigate, Usages, Help, Copy, NextAction, PreviousAction, ApplyFix,
    ActivateAction, DebugUp, DebugDown, DebugExpand, DebugCollapse);

  /// <summary>Zustand des Tooltips, den die Tastenauswahl braucht.</summary>
  TAtlasHoverKeyState = record
    /// <summary>Tooltip sichtbar.</summary>
    Shown: Boolean;
    /// <summary>Angeheftet (#588).</summary>
    Pinned: Boolean;
    /// <summary>Verlauf hat einen vorigen Typ.</summary>
    CanGoBack: Boolean;
    /// <summary>Maus steht über dem Tooltip.</summary>
    MouseOverTip: Boolean;
    /// <summary>Doku-Text markiert (#654).</summary>
    HasSelection: Boolean;
    /// <summary>Ein Befund hat eine Korrektur (#909).</summary>
    HasFix: Boolean;
    /// <summary>Unter einem Befund stehen Aktionen (#909).</summary>
    HasProblemActions: Boolean;
    /// <summary>Eine Aktion unter einem Befund ist markiert.</summary>
    ProblemActionMarked: Boolean;
    /// <summary>Der Wert im Debugger lässt sich aufklappen (#895).</summary>
    DebugExpandable: Boolean;
    /// <summary>Der gezeigte Typ hat einen Fundort.</summary>
    HasLocation: Boolean;
    /// <summary>Der gezeigte Typ hat eine Hilfeseite.</summary>
    HasHelp: Boolean;
  end;

  /// <summary>Inhalt und Aktionen des Tooltips.</summary>
  TAtlasHoverPlan = record
  public
    /// <summary>Bezeichner an AIndex (0-basiert) in AText: Anfang und Ende (exklusiv). False ohne Bezeichner oder
    /// bei einer Zahl.</summary>
    class function WordAt(const AText: string; AIndex: Integer; out AStart, AStop: Integer): Boolean; static;
    /// <summary>Schlüssel des Bezeichners ab AStart in Zeile ALine (1-basiert).</summary>
    class function WordKey(const AFileName: string; ALine, AStart: Integer): string; static;
    /// <summary>Schlüssel eines Problems ohne Bezeichner an AIndex in Zeile ALine.</summary>
    class function ProblemKey(const AFileName: string; ALine, AIndex: Integer): string; static;
    /// <summary>Hat der Tooltip etwas zu zeigen: Deklaration, Probleme oder Wert im Debugger?</summary>
    class function HasContent(AFound: Boolean; AProblemCount: Integer; ADebugVisible: Boolean): Boolean; static;
    /// <summary>Neu zugewiesen (#712) zeigen: eingeschaltet und AReassignedTarget unter den gewählten Arten
    /// ATargets (Text der Einstellung).</summary>
    class function ShowsReassigned(AEnabled: Boolean; const ATargets, AReassignedTarget: string): Boolean; static;
    /// <summary>Typ der Deklaration, dann seine Vorfahren (für die Visualisierer, #835).</summary>
    class function TypeChain(const AData: TAtlasHoverData): TArray<string>; static;
    /// <summary>Schlüssel für einmal Visualisieren je Wert und Typ (#835).</summary>
    class function VisualizeKey(const AValue: TAtlasDebugValue; const ADeclaration: string): string; static;
    /// <summary>Gescheiterte Auswertung ohne Erklärung: „kein Zugriff“ erklären lassen (#840).</summary>
    class function NeedsExplanation(const AValue: TAtlasDebugValue): Boolean; static;
    /// <summary>Wert, auf den die Aktionen wirken: die gewählte Zeile ARow des aufgeklappten Werts (#895), sonst
    /// AValue. Ausstehende Zeilen und nicht ausgewertete Getter gelten als ausstehend.</summary>
    class function Subject(const AValue: TAtlasDebugValue; ARow: Integer): TAtlasDebugValue; static;
    /// <summary>Aufzuklappendes Beispiel (#145): ohne Katalogeintrag mit der Regel als Kennung, damit der Tooltip
    /// sagt, dass der Katalog nichts zur Regel hat.</summary>
    class function ExampleOf(const ARule: string; const AExplanation: TAtlasRuleExplanation):
      TAtlasRuleExplanation; static;
    /// <summary>Quelle für Strg+C.</summary>
    class function CopySource(AHasSelection: Boolean; AMemberCount: Integer): TAtlasHoverCopySource; static;
    /// <summary>Kennung der Code-Aktion unter einem Problem (#621); bei Related mit der Stelle AItem (#896). ''
    /// für Aktionen ohne Kennung (DocWiki, Example).</summary>
    class function ProblemActionTag(AAction: TAtlasHoverProblemAction; AItem: Integer): string; static;
    /// <summary>Öffnet der Tooltip den Link (#654)? Nur Web- und Mail-Adressen.</summary>
    class function OpensUrl(const AUrl: string): Boolean; static;
  end;

  /// <summary>Tasten und Zeitgeber des Tooltips.</summary>
  TAtlasHoverKeys = record
  public const
    /// <summary>Tastencodes wie in Winapi.Windows.</summary>
    cVkBack = $08;
    cVkTab = $09;
    cVkReturn = $0D;
    cVkShift = $10;
    cVkControl = $11;
    cVkMenu = $12;
    cVkEscape = $1B;
    cVkLeft = $25;
    cVkUp = $26;
    cVkRight = $27;
    cVkDown = $28;
    cVkF1 = $70;
    cVkF12 = $7B;
  public
    /// <summary>Befehl der Taste AKey mit AShift; None, wenn der Tooltip sie nicht nimmt.</summary>
    class function Command(AKey: Word; AShift: TShiftState; const AState: TAtlasHoverKeyState):
      TAtlasHoverKeyCommand; static;
    /// <summary>Umschalt, Strg oder Alt allein: schließt den Tooltip nicht (Strg+Klick und Kürzel brauchen sie).
    /// </summary>
    class function IsModifier(AKey: Word): Boolean; static;
    /// <summary>Schließt die Taste den Tooltip nach der Verarbeitung (Delphi 12 ohne Tastatur-Ereignisse)?</summary>
    class function ClosesAfter(AKey: Word; AWanted, APinned: Boolean): Boolean; static;
    /// <summary>Zeitgeber nach dem Schlüssel AKey unter der Maus, dem des offenen Tooltips und dem, auf den gewartet
    /// wird.</summary>
    class function Track(const AKey, AShownKey, AWaitingKey: string): TAtlasHoverTrack; static;
    /// <summary>Zeitgeber zum Schließen: angeheftet bleibt der Tooltip, die Maus darf in ihn wandern (#442).</summary>
    class function HideStep(AShown, APinned, AMouseOverTip, AAppActive: Boolean): TAtlasHoverHideStep; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Core.Completion.Word,
  Atlas.Core.Hover.Declaration,
  Atlas.Core.Settings.Reassigned;

const
  // Related und ShowGraph (#896) sind Client-Aktionen: „related:<Stelle>“ springt an Problem.Related[Stelle].
  // Explain (#54) öffnet den Dialog „Erklären“; DocWiki öffnet der Tooltip selbst; Example (#145) bleibt im
  // Tooltip und hat keine Kennung; Compare (#1779) zeigt erwartet und erhalten des Tests.
  cProblemActionTags: array[TAtlasHoverProblemAction] of string = ('uses.remove', 'uses.removeAll', 'uses.move',
    'rule.fix', 'rule.suppressLine', 'rule.configure', 'related:', 'cycle.showGraph', 'problem.explain', '', '',
    'test.compare');

{ TAtlasHoverPlan }

class function TAtlasHoverPlan.WordAt(const AText: string; AIndex: Integer; out AStart, AStop: Integer): Boolean;
begin
  AStart := 0;
  AStop := 0;
  Result := (AIndex >= 0) and (AIndex < Length(AText)) and TAtlasWord.IsIdentifierChar(AText[AIndex + 1]);
  if not Result then
  begin
    Exit;
  end;
  AStart := TAtlasWord.StartBefore(AText, AIndex + 1);
  // Zahlen sind keine Bezeichner (1E5, $FF).
  Result := not CharInSet(AText[AStart + 1], ['0'..'9']);
  if Result then
  begin
    AStop := TAtlasWord.EndAfter(AText, AIndex);
  end
  else
  begin
    AStart := 0;
  end;
end;

class function TAtlasHoverPlan.WordKey(const AFileName: string; ALine, AStart: Integer): string;
begin
  Result := Format('%s|%d|%d', [AFileName, ALine, AStart]);
end;

class function TAtlasHoverPlan.ProblemKey(const AFileName: string; ALine, AIndex: Integer): string;
begin
  Result := Format('%s|%d|p%d', [AFileName, ALine, AIndex]);
end;

class function TAtlasHoverPlan.HasContent(AFound: Boolean; AProblemCount: Integer; ADebugVisible: Boolean): Boolean;
begin
  Result := AFound or (AProblemCount > 0) or ADebugVisible;
end;

class function TAtlasHoverPlan.ShowsReassigned(AEnabled: Boolean; const ATargets, AReassignedTarget: string):
  Boolean;
var
  mTarget: TAtlasReassignedTarget;
begin
  // Der Server kennt die Einstellung nicht und meldet jede Art.
  Result := AEnabled and TAtlasReassignedNames.TryTarget(AReassignedTarget, mTarget) and
    (mTarget in TAtlasReassignedNames.ParseTargets(ATargets));
end;

class function TAtlasHoverPlan.TypeChain(const AData: TAtlasHoverData): TArray<string>;
var
  mAncestor: TAtlasHoverTypeRef;
begin
  Result := TArray<string>.Create(TAtlasHoverDeclaration.DeclaredType(AData.Declaration));
  for mAncestor in AData.Ancestors do
  begin
    Result := Result + [mAncestor.Name];
  end;
end;

class function TAtlasHoverPlan.VisualizeKey(const AValue: TAtlasDebugValue; const ADeclaration: string): string;
begin
  Result := AValue.Expression + #0 + AValue.Text + #0 + ADeclaration;
end;

class function TAtlasHoverPlan.NeedsExplanation(const AValue: TAtlasDebugValue): Boolean;
begin
  Result := (AValue.State = TAtlasDebugValueState.Failed) and (AValue.Note.Caption = '');
end;

class function TAtlasHoverPlan.Subject(const AValue: TAtlasDebugValue; ARow: Integer): TAtlasDebugValue;
var
  mRow: TAtlasDebugValueRow;
begin
  Result := AValue;
  if (ARow < 0) or (ARow > High(AValue.Rows)) or AValue.Rows[ARow].More then
  begin
    Exit;
  end;
  mRow := AValue.Rows[ARow];
  Result.Expression := mRow.Expression;
  Result.Text := mRow.Text;
  Result.OldText := mRow.OldText;
  Result.Expandable := mRow.Expandable;
  Result.Expanded := mRow.Expanded;
  Result.Rows := nil;
  // Ausstehender Wert oder nicht ausgewerteter Getter: noch nichts zum Kopieren, Anheften oder Ändern.
  if mRow.Pending or mRow.Lazy then
  begin
    Result.State := TAtlasDebugValueState.Pending;
  end;
end;

class function TAtlasHoverPlan.ExampleOf(const ARule: string; const AExplanation: TAtlasRuleExplanation):
  TAtlasRuleExplanation;
begin
  Result := AExplanation;
  if Result.Id = '' then
  begin
    Result.Id := ARule;
  end;
end;

class function TAtlasHoverPlan.CopySource(AHasSelection: Boolean; AMemberCount: Integer): TAtlasHoverCopySource;
begin
  if AHasSelection then
  begin
    Result := TAtlasHoverCopySource.Selection;
  end
  else if AMemberCount > 0 then
  begin
    Result := TAtlasHoverCopySource.Members;
  end
  else
  begin
    Result := TAtlasHoverCopySource.Declaration;
  end;
end;

class function TAtlasHoverPlan.ProblemActionTag(AAction: TAtlasHoverProblemAction; AItem: Integer): string;
begin
  Result := cProblemActionTags[AAction];
  if AAction = TAtlasHoverProblemAction.Related then
  begin
    Result := Result + IntToStr(AItem);
  end;
end;

class function TAtlasHoverPlan.OpensUrl(const AUrl: string): Boolean;
begin
  // Andere Schemata (file:, Programme) öffnet der Tooltip nicht.
  Result := StartsText('http://', AUrl) or StartsText('https://', AUrl) or StartsText('mailto:', AUrl);
end;

{ TAtlasHoverKeys }

/// <summary>Zurück im angehefteten Tooltip: Rücktaste oder Alt+Links.</summary>
function IsBackKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := ((AKey = TAtlasHoverKeys.cVkBack) and (AShift = [])) or
    ((AKey = TAtlasHoverKeys.cVkLeft) and (AShift = [ssAlt]));
end;

/// <summary>Pfeiltaste ohne Umschalter: bewegt im aufgeklappten Debug-Wert (#895).</summary>
function IsTreeKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (AShift = []) and ((AKey = TAtlasHoverKeys.cVkUp) or (AKey = TAtlasHoverKeys.cVkDown) or
    (AKey = TAtlasHoverKeys.cVkLeft) or (AKey = TAtlasHoverKeys.cVkRight));
end;

function NoneOrShift(AShift: TShiftState): Boolean;
begin
  Result := (AShift = []) or (AShift = [ssShift]);
end;

/// <summary>Kürzel der Aktionsleiste mit Fundort: F12/Umschalt+F12, Strg+C, F1 nur mit Hilfe.</summary>
function IsActionKey(AKey: Word; AShift: TShiftState; AHasHelp: Boolean): Boolean;
begin
  Result := ((AKey = TAtlasHoverKeys.cVkF12) and NoneOrShift(AShift)) or ((AKey = Ord('C')) and (AShift = [ssCtrl]))
    or ((AKey = TAtlasHoverKeys.cVkF1) and (AShift = []) and AHasHelp);
end;

/// <summary>Kürzel, die nur gelten, wenn der Tooltip gemeint ist (angeheftet oder Maus darüber).</summary>
function IsTipKey(AKey: Word; AShift: TShiftState; const AState: TAtlasHoverKeyState): Boolean;
begin
  // Markierter Doku-Text lässt sich auch ohne Fundort kopieren (#654).
  Result := AState.HasSelection and (AKey = Ord('C')) and (AShift = [ssCtrl]);
  // Aktionen unter Befunden (#909), auch ohne Fundort (Hover nur mit Problem).
  Result := Result or ((AKey = TAtlasHoverKeys.cVkReturn) and (AShift = [ssAlt]) and AState.HasFix);
  Result := Result or ((AKey = TAtlasHoverKeys.cVkTab) and NoneOrShift(AShift) and AState.HasProblemActions);
  Result := Result or ((AKey = TAtlasHoverKeys.cVkReturn) and (AShift = []) and AState.ProblemActionMarked);
  Result := Result or (AState.DebugExpandable and IsTreeKey(AKey, AShift));
  Result := Result or (AState.HasLocation and IsActionKey(AKey, AShift, AState.HasHelp));
end;

function IsWanted(AKey: Word; AShift: TShiftState; const AState: TAtlasHoverKeyState): Boolean;
begin
  Result := AState.Shown and (((AKey = TAtlasHoverKeys.cVkEscape) and (AShift = [])) or
    (AState.Pinned and AState.CanGoBack and IsBackKey(AKey, AShift)) or
    ((AState.Pinned or AState.MouseOverTip) and IsTipKey(AKey, AShift, AState)));
end;

function TreeCommand(AKey: Word): TAtlasHoverKeyCommand;
begin
  case AKey of
    TAtlasHoverKeys.cVkUp:
      Result := TAtlasHoverKeyCommand.DebugUp;
    TAtlasHoverKeys.cVkDown:
      Result := TAtlasHoverKeyCommand.DebugDown;
    TAtlasHoverKeys.cVkRight:
      Result := TAtlasHoverKeyCommand.DebugExpand;
  else
    Result := TAtlasHoverKeyCommand.DebugCollapse;
  end;
end;

function Choose(AWith: Boolean; AYes, ANo: TAtlasHoverKeyCommand): TAtlasHoverKeyCommand;
begin
  if AWith then
  begin
    Result := AYes;
  end
  else
  begin
    Result := ANo;
  end;
end;

class function TAtlasHoverKeys.Command(AKey: Word; AShift: TShiftState; const AState: TAtlasHoverKeyState):
  TAtlasHoverKeyCommand;
begin
  Result := TAtlasHoverKeyCommand.None;
  if not IsWanted(AKey, AShift, AState) then
  begin
    Exit;
  end;
  if AState.DebugExpandable and IsTreeKey(AKey, AShift) then
  begin
    Exit(TreeCommand(AKey));
  end;
  case AKey of
    cVkEscape:
      Result := TAtlasHoverKeyCommand.Close;
    cVkBack, cVkLeft:
      Result := TAtlasHoverKeyCommand.Back;
    cVkF12:
      Result := Choose(ssShift in AShift, TAtlasHoverKeyCommand.Usages, TAtlasHoverKeyCommand.Navigate);
    cVkF1:
      Result := TAtlasHoverKeyCommand.Help;
    cVkTab:
      Result := Choose(ssShift in AShift, TAtlasHoverKeyCommand.PreviousAction, TAtlasHoverKeyCommand.NextAction);
    cVkReturn:
      Result := Choose(ssAlt in AShift, TAtlasHoverKeyCommand.ApplyFix, TAtlasHoverKeyCommand.ActivateAction);
    Ord('C'):
      Result := TAtlasHoverKeyCommand.Copy;
  end;
end;

class function TAtlasHoverKeys.IsModifier(AKey: Word): Boolean;
begin
  Result := (AKey = cVkShift) or (AKey = cVkControl) or (AKey = cVkMenu);
end;

class function TAtlasHoverKeys.ClosesAfter(AKey: Word; AWanted, APinned: Boolean): Boolean;
begin
  Result := not AWanted and not IsModifier(AKey) and not APinned;
end;

class function TAtlasHoverKeys.Track(const AKey, AShownKey, AWaitingKey: string): TAtlasHoverTrack;
begin
  if AKey = '' then
  begin
    Result := TAtlasHoverTrack.Leave;
  end
  else if AKey = AShownKey then
  begin
    Result := TAtlasHoverTrack.Stay;
  end
  else if AKey <> AWaitingKey then
  begin
    Result := TAtlasHoverTrack.Restart;
  end
  else
  begin
    Result := TAtlasHoverTrack.Wait;
  end;
end;

class function TAtlasHoverKeys.HideStep(AShown, APinned, AMouseOverTip, AAppActive: Boolean): TAtlasHoverHideStep;
begin
  Result := TAtlasHoverHideStep.Close;
  if not AShown or not AAppActive then
  begin
    Exit;
  end;
  if APinned then
  begin
    Result := TAtlasHoverHideStep.KeepPinned;
  end
  else if AMouseOverTip then
  begin
    Result := TAtlasHoverHideStep.Recheck;
  end;
end;

end.
