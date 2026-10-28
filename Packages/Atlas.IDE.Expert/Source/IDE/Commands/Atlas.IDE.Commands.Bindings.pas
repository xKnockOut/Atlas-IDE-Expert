unit Atlas.IDE.Commands.Bindings;

// Tastenkürzel der Editorbefehle (#399) als eine Tastaturbindung der IDE
// (IOTAKeyboardBinding): Code-Aktionen (Alt+Enter), Auswahl erweitern
// (Strg+W) und verkleinern (Strg+Umschalt+W), Gehe zu Implementierung
// (Strg+Alt+I), Gehe zu Typdefinition (ohne Vorgabe), letzte
// Atlas-Änderung zurücknehmen (Strg+Alt+Z) und wiederherstellen
// (Strg+Alt+Umschalt+Z, #721) sowie Deklaration ⇄ Implementierung
// (Strg+Umschalt+↑/↓, #775), Unit ⇄ Testunit (#189), Units suchen (#777,
// nur solange unitSearch.enabled an ist) und „Lesezeichen setzen…“ (#622,
// Strg+Alt+K, nur solange bookmarks.named an ist) sowie die Liste der
// Benachrichtigungen (#601, Strg+Umschalt+Alt+N, nur solange
// notifications.enabled an ist) und die Brotkrumenleiste (#590,
// Strg+Umschalt+., nur solange editor.breadcrumbs an ist) sowie der Sprung
// zum Gegenstück (#635, Strg+Ü bzw. Strg+Umschalt+Ü zum Markieren, nur
// solange keys.jumpToMatch an ist) und Zeilen verschieben bzw. duplizieren
// (#634, Alt+↑/↓ und Umschalt+Alt+↑/↓ mit Vorrang, nur solange keys.moveLines
// an ist) sowie die Mehrfachmarken (#589, Strg+D, Alt+Umschalt+I,
// Strg+Alt+↑/↓ mit Rückfall an die IDE, nur solange editor.multiCursor an
// ist), Blockkommentar umschalten (#703, Umschalt+Alt+A, nur solange
// keys.toggleBlockComment an ist), Neue Zeile ober- oder unterhalb (#700,
// Umschalt+Enter und Strg+Alt+Enter, nur solange keys.newLineAround an
// ist) und Umschließung entfernen (#657, Strg+Umschalt+Entf, nur solange
// keys.unwrap an ist) sowie die schnellen Lesezeichen (#1104, nur solange
// bookmarks.quick an ist): Strg+Umschalt+1…9 und Strg+1…9 aus einer
// Grundtaste mit eigenem Vorrang (bookmarks.quick.numberedKeys), Strg+Umschalt+K
// als erster Teil neben den Faltungsakkorden der IDE (TAtlasIdeQuickChord,
// mit Rückfall an die IDE für den selbst weitergereichten Akkord) und
// nächstes/voriges Lesezeichen ohne Vorgabe. Jede Taste wird wie
// die der Befehlspalette vorher auf Konflikte geprüft (#494); ohne Vorrang
// bleibt eine fremde Belegung aktiv. Jede Taste läuft unter der Sicherung
// (#493) ihrer Funktion; Fehler einer Funktion schalten die Tasten der
// übrigen nicht ab. Nach geänderten Einstellungen meldet
// Rebind die Bindung neu an. Der Befehl läuft nach der Tastenverarbeitung
// (ForceQueue), nicht in der Bindung selbst. Ausnahme sind Befehle mit
// Rückfall (AddAttemptKey): Sie laufen sofort, und ohne Treffer geht die
// Taste an die nächste Bindung (krNextProc), beim Wechsel Deklaration ⇄
// Implementierung also an die Klassennavigation der IDE. F3 und Umschalt+F3
// suchen eine einzeilige Markierung vorwärts bzw. rückwärts; ohne Markierung
// bleibt es bei „Erneut suchen“ der IDE. Strg+. (HideElementKey, #628) öffnet
// das Menü „Ausblenden“ zu den Elementen der Zeile; ohne Element geht die Taste
// an die IDE (IDE Insight).
// Atlas-Suche (#878, search.replaceIdeSearch): Strg+F öffnet die
// Suchleiste unter dem Editor, F3/Umschalt+F3 springen in der letzten Atlas-Suche; ohne
// letzte Atlas-Suche bleibt es bei Markierung suchen bzw. der IDE. Die Tasten
// sind bewusst übernommen (ohne Konfliktprüfung, wie Strg+F12 bei „Units
// suchen“); mit dem Schalter aus belegt Atlas sie nicht. „In Methode suchen“
// (#877, SearchMethodKey) ist ein gewöhnlicher Editorbefehl.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

type
  TAtlasIdeEditorKeys = class
  private type
    TKey = record
      Key: Word;
      /// <summary>Sicherung (#493), unter der die Taste läuft: Fehler anderer Funktionen schalten sie nicht ab.
      /// </summary>
      Feature: TAtlasFeature;
      Proc: TProc;
      /// <summary>Statt Proc: sofort ausführen; False gibt die Taste an die nächste Bindung weiter.</summary>
      Attempt: TFunc<Boolean>;
    end;

    TBinding = class(TNotifierObject, IOTAKeyboardBinding)
    private
      FOwner: TAtlasIdeEditorKeys;
      procedure Pressed(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
    public
      function GetBindingType: TBindingType;
      function GetDisplayName: string;
      function GetName: string;
      procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    end;
  private
    FBinding: TBinding;
    // Hält das Binding am Leben: Abmelden gibt die Referenz der IDE frei, Rebind meldet es neu an.
    FBindingRef: IOTAKeyboardBinding;
    FBindingIndex: Integer;
    FKeys: TArray<TKey>;
    FBound: string;
    /// <summary>AFeature: Sicherung, unter der die Taste läuft.</summary>
    procedure AddKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string; const AProc: TProc);
    /// <summary>Wie AddKey mit eigenem Vorrang statt des gemeinsamen (Zurück/Vor, #504). Eigener Name statt
    /// Überladung: anonyme Methoden als Argument vertragen keine Überladungen.</summary>
    procedure AddPriorityKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string; const AProc: TProc;
      APriority: Boolean);
    /// <summary>ACheck False: ohne Konfliktprüfung, weil die Taste ohne Treffer ohnehin an die IDE weitergeht.</summary>
    procedure AddAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
      const AAttempt: TFunc<Boolean>; ACheck: Boolean = True);
    /// <summary>Wie AddAttemptKey mit Konfliktprüfung und eigenem Vorrang (#1104).</summary>
    procedure AddPriorityAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
      const AAttempt: TFunc<Boolean>; APriority: Boolean);
    /// <summary>Strg+Umschalt+1…9 bzw. Strg+1…9 aus der Grundtaste ABase (#1104).</summary>
    procedure AddNumberKeys(ABase: Integer; APriority, AJump: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Tasten nach den Einstellungen (neu) belegen; bei Konflikt ohne Vorrang nicht (#494).</summary>
    procedure Rebind;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Commands.QuickOpen,
  Atlas.IDE.Editor.NavHistory,
  Atlas.IDE.Results.Peek,
  Atlas.IDE.UnitSearch.Commands,
  Atlas.IDE.Search.Commands,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Bookmarks.QuickChord,
  Atlas.Core.Bookmarks.Quick,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Editor.Hide,
  Atlas.IDE.Editor.ExitPoints,
  Atlas.IDE.Notifications.Service,
  Atlas.IDE.Outline.Breadcrumbs,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.Editor.LineChanges,
  Atlas.Core.Editor.LineMove,
  Atlas.IDE.Editor.LineMove,
  Atlas.IDE.Editor.StatementCompletion,
  Atlas.IDE.Editor.MultiCursor,
  Atlas.IDE.Editor.BlockComment,
  Atlas.Core.Editor.NewLine,
  Atlas.IDE.Editor.NewLine,
  Atlas.IDE.Editor.Unwrap,
  Atlas.IDE.Debug.StepInto,
  Atlas.IDE.Editor.ExpressionType,
  Atlas.IDE.Problems.Service;

/// <summary>Zeilen verschieben bzw. duplizieren (#634), gesichert.</summary>
procedure RunLineMove(AKind: TAtlasLineMoveKind);
begin
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeLineMove.Run(AKind);
    end);
end;

{ TAtlasIdeEditorKeys.TBinding }

function TAtlasIdeEditorKeys.TBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TAtlasIdeEditorKeys.TBinding.GetDisplayName: string;
begin
  Result := 'Atlas-Editorbefehle';
end;

function TAtlasIdeEditorKeys.TBinding.GetName: string;
begin
  Result := 'Atlas.EditorCommands';
end;

procedure TAtlasIdeEditorKeys.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
var
  Key: TKey;
begin
  if FOwner <> nil then
    for Key in FOwner.FKeys do
      BindingServices.AddKeyBinding([Key.Key], Pressed, nil);
end;

procedure TAtlasIdeEditorKeys.TBinding.Pressed(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
var
  Key: TKey;
  Feature: TAtlasFeature;
  Proc: TProc;
  Attempt: TFunc<Boolean>;
  Done: Boolean;
begin
  BindingResult := krUnhandled;
  if FOwner = nil then
    Exit;
  for Key in FOwner.FKeys do
    if Key.Key = KeyCode then
    begin
      Feature := Key.Feature;
      if Assigned(Key.Attempt) then
      begin
        Attempt := Key.Attempt;
        Done := False;
        TAtlasGuard.Run(Feature,
          procedure
          begin
            Done := Attempt();
          end);
        if Done then
          BindingResult := krHandled
        else
          BindingResult := krNextProc;
        Exit;
      end;
      BindingResult := krHandled;
      Proc := Key.Proc;
      // Keine Exception an die IDE (#493); erst nach der Tastenverarbeitung.
      TAtlasMainThread.ForceQueue(Feature,
        procedure
        begin
          TAtlasGuard.Run(Feature, Proc);
        end);
      Exit;
    end;
end;

{ TAtlasIdeEditorKeys }

constructor TAtlasIdeEditorKeys.Create;
var
  Keyboard: IOTAKeyboardServices;
begin
  inherited Create;
  FBindingIndex := -1;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    FBinding := TBinding.Create;
    FBindingRef := FBinding;
    FBinding.FOwner := Self;
    Rebind;
  end;
end;

destructor TAtlasIdeEditorKeys.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  if FBinding <> nil then
    FBinding.FOwner := nil;
  TAtlasIdeKeys.Unbind(FBindingIndex);
  inherited;
end;

procedure TAtlasIdeEditorKeys.AddKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AProc: TProc);
begin
  AddPriorityKey(AFeature, AKey, AWhat, AProc, TAtlasIdeSettings.Current.EditorKeysPriority);
end;

procedure TAtlasIdeEditorKeys.AddPriorityKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AProc: TProc; APriority: Boolean);
var
  Key: TKey;
begin
  if not TAtlasIdeKeys.Decide(Word(AKey), APriority, AWhat) then
    Exit;
  Key.Key := Word(AKey);
  Key.Feature := AFeature;
  Key.Proc := AProc;
  Key.Attempt := nil;
  FKeys := FKeys + [Key];
  FBound := FBound + IntToStr(AKey) + ';';
end;

procedure TAtlasIdeEditorKeys.AddAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AAttempt: TFunc<Boolean>; ACheck: Boolean);
var
  Existing, Key: TKey;
begin
  // 0 = keine Taste.
  if AKey = 0 then
    Exit;
  // Dieselbe Taste zweimal (beide Felder gleich belegt) nur einmal binden.
  for Existing in FKeys do
    if Existing.Key = Word(AKey) then
      Exit;
  if ACheck and not TAtlasIdeKeys.Decide(Word(AKey), TAtlasIdeSettings.Current.EditorKeysPriority, AWhat) then
    Exit;
  Key.Key := Word(AKey);
  Key.Feature := AFeature;
  Key.Proc := nil;
  Key.Attempt := AAttempt;
  FKeys := FKeys + [Key];
  FBound := FBound + IntToStr(AKey) + ';';
end;

procedure TAtlasIdeEditorKeys.AddPriorityAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AAttempt: TFunc<Boolean>; APriority: Boolean);
var
  Existing, Key: TKey;
begin
  if AKey = 0 then
    Exit;
  for Existing in FKeys do
    if Existing.Key = Word(AKey) then
      Exit;
  if not TAtlasIdeKeys.Decide(Word(AKey), APriority, AWhat) then
    Exit;
  Key.Key := Word(AKey);
  Key.Feature := AFeature;
  Key.Proc := nil;
  Key.Attempt := AAttempt;
  FKeys := FKeys + [Key];
  FBound := FBound + IntToStr(AKey) + ';';
end;

/// <summary>Befehl für Nummer ANumber: eigene Funktion, damit jede anonyme Methode ihre Nummer behält.</summary>
function NumberProc(ANumber: Integer; AJump: Boolean): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
        procedure
        begin
          if AJump then
            TAtlasIdeBookmarks.QuickJump(ANumber)
          else
            TAtlasIdeBookmarks.QuickSetNumber(ANumber);
        end);
    end;
end;

procedure TAtlasIdeEditorKeys.AddNumberKeys(ABase: Integer; APriority, AJump: Boolean);
var
  Number: Integer;
  Key: Word;
  What: string;
begin
  for Number := 1 to TAtlasQuickBookmarks.MaxNumber do
  begin
    Key := TAtlasQuickBookmarks.KeyFor(Word(ABase), Number);
    if Key = 0 then
      Exit;
    if AJump then
      What := TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkJumpN, [Number])
    else
      What := TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkSetN, [Number]);
    AddPriorityKey(TAtlasFeature.QuickBookmarks, Key, What, NumberProc(Number, AJump), APriority);
  end;
end;

procedure TAtlasIdeEditorKeys.Rebind;
var
  Settings: TAtlasPluginSettings;
  Previous: string;
begin
  if FBinding = nil then
    Exit;
  Settings := TAtlasIdeSettings.Current;
  Previous := FBound;
  FKeys := nil;
  FBound := '';
  AddKey(TAtlasFeature.EditorCommands, Settings.ActionsKey, TAtlasStrings.Text(TAtlasTextId.EditorActions),
    procedure
    begin
      TAtlasIdeEditorCommands.CodeActions;
    end);
  AddKey(TAtlasFeature.EditorCommands, Settings.ExpandKey, TAtlasStrings.Text(TAtlasTextId.EditorExpand),
    procedure
    begin
      TAtlasIdeEditorCommands.ExpandSelection;
    end);
  AddKey(TAtlasFeature.EditorCommands, Settings.ShrinkKey, TAtlasStrings.Text(TAtlasTextId.EditorShrink),
    procedure
    begin
      TAtlasIdeEditorCommands.ShrinkSelection;
    end);
  AddKey(TAtlasFeature.EditorCommands, Settings.ImplementationKey, TAtlasStrings.Text(TAtlasTextId.MenuImplementations),
    procedure
    begin
      TAtlasIdeResults.FindImplementations;
    end);
  AddKey(TAtlasFeature.EditorCommands, Settings.TypeDefinitionKey, TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition),
    procedure
    begin
      TAtlasIdeEditorCommands.GoToTypeDefinition;
    end);
  // Deklaration ⇄ Implementierung (#775): aus = Taste bleibt bei der Klassennavigation der IDE.
  if Settings.MethodToggle then
  begin
    AddAttemptKey(TAtlasFeature.EditorCommands, Settings.MethodToggleUpKey, TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
      function: Boolean
      begin
        Result := TAtlasIdeEditorCommands.TryToggleMethod;
      end);
    AddAttemptKey(TAtlasFeature.EditorCommands, Settings.MethodToggleDownKey, TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
      function: Boolean
      begin
        Result := TAtlasIdeEditorCommands.TryToggleMethod;
      end);
  end;
  // Atlas-Suche (#878): vor F3 der Markierungssuche angemeldet, damit sie bei gleicher Taste gewinnt (AddAttemptKey
  // bindet jede Taste nur einmal); ohne letzte Atlas-Suche weiter wie bisher.
  if Settings.SearchReplaceIde then
  begin
    if Settings.SearchKey <> 0 then
      AddAttemptKey(TAtlasFeature.Search, Settings.SearchKey, TAtlasStrings.Text(TAtlasTextId.SearchCommand),
        function: Boolean
        begin
          // Die Leiste erst nach der Tastenverarbeitung (sie nimmt den Fokus).
          TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
            procedure
            begin
              TAtlasGuard.Run(TAtlasFeature.Search, TAtlasIdeSearch.Show);
            end);
          Result := True;
        end, False);
    // Strg+H (#893): nur mit search.replace, sonst gehört die Taste der IDE.
    if Settings.SearchReplace and (Settings.SearchReplaceKey <> 0) then
      AddAttemptKey(TAtlasFeature.Search, Settings.SearchReplaceKey,
        TAtlasStrings.Text(TAtlasTextId.SearchReplaceCommand),
        function: Boolean
        begin
          TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
            procedure
            begin
              TAtlasGuard.Run(TAtlasFeature.Search, TAtlasIdeSearch.ShowReplace);
            end);
          Result := True;
        end, False);
    if Settings.SearchNextKey <> 0 then
      AddAttemptKey(TAtlasFeature.Search, Settings.SearchNextKey, TAtlasStrings.Text(TAtlasTextId.SearchNextCommand),
        function: Boolean
        begin
          Result := TAtlasIdeExitPoints.TryJump(False) or TAtlasIdeSearch.TryNext(False) or
            TAtlasIdeEditorCommands.TryFindSelection(False);
        end, False);
    if Settings.SearchPreviousKey <> 0 then
      AddAttemptKey(TAtlasFeature.Search, Settings.SearchPreviousKey, TAtlasStrings.Text(TAtlasTextId.SearchPreviousCommand),
        function: Boolean
        begin
          Result := TAtlasIdeExitPoints.TryJump(True) or TAtlasIdeSearch.TryNext(True) or
            TAtlasIdeEditorCommands.TryFindSelection(True);
        end, False);
  end;
  AddKey(TAtlasFeature.Search, Settings.SearchMethodKey, TAtlasStrings.Text(TAtlasTextId.SearchInMethodCommand),
    procedure
    begin
      TAtlasIdeSearch.ShowInMethod;
    end);
  // Austrittspunkte (#698): F3 bzw. Umschalt+F3 springt reihum, solange die Hervorhebung steht und der Cursor auf
  // einer ihrer Stellen liegt (dann gibt es keine Markierung). Markierung suchen: mit einzeiliger Markierung; sonst
  // „Erneut suchen“ der IDE.
  AddAttemptKey(TAtlasFeature.EditorCommands, ShortCut(VK_F3, []), 'F3',
    function: Boolean
    begin
      Result := TAtlasIdeExitPoints.TryJump(False) or TAtlasIdeEditorCommands.TryFindSelection(False);
    end, False);
  AddAttemptKey(TAtlasFeature.EditorCommands, ShortCut(VK_F3, [ssShift]), 'Umschalt+F3',
    function: Boolean
    begin
      Result := TAtlasIdeExitPoints.TryJump(True) or TAtlasIdeEditorCommands.TryFindSelection(True);
    end, False);
  // Issue anlegen (#1268): frei belegbar, ohne Vorgabe.
  if Settings.CreateIssueKey <> 0 then
    AddKey(TAtlasFeature.WelcomePage, Settings.CreateIssueKey, TAtlasStrings.Text(TAtlasTextId.CreateIssueCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.CreateIssue;
      end);
  // Ausblenden am Element (#628): mit Rückfall, ohne Element behält die IDE die Taste (Strg+. = IDE Insight).
  if Settings.HideElementKey <> 0 then
    AddAttemptKey(TAtlasFeature.Hide, Settings.HideElementKey, TAtlasStrings.Text(TAtlasTextId.HideElementCommand),
      function: Boolean
      begin
        Result := False;
        try
          Result := TAtlasIdeHide.ShowForCaret;
        except
          on E: Exception do
            TAtlasGuard.Report(TAtlasFeature.Hide, E);
        end;
      end, False);
  // Nächster/vorheriger Befund (#509): nur mit Problemen im Editor.
  if Settings.Problems then
  begin
    AddKey(TAtlasFeature.EditorCommands, Settings.NextProblemKey, TAtlasStrings.Text(TAtlasTextId.ProblemNextCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.StepProblem(True);
      end);
    AddKey(TAtlasFeature.EditorCommands, Settings.PreviousProblemKey, TAtlasStrings.Text(TAtlasTextId.ProblemPreviousCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.StepProblem(False);
      end);
  end;
  // Fenster „Atlas-Prüfung“ (#909): aus = das Kürzel gehört der IDE.
  if Settings.Problems and Settings.ProblemsWindow then
    AddKey(TAtlasFeature.Problems, Settings.ProblemsWindowKey, TAtlasStrings.Text(TAtlasTextId.ProblemsWindowCommand),
      procedure
      begin
        TAtlasIdeProblems.ShowWindow;
      end);
  AddKey(TAtlasFeature.EditorCommands, Settings.TestUnitKey, TAtlasStrings.Text(TAtlasTextId.EditorTestUnit),
    procedure
    begin
      TAtlasIdeEditorCommands.SwitchTestUnit;
    end);
  // Abschnittssprünge der Editorleiste (#1101); Vorgabe ohne Taste, auch ohne die Leiste.
  AddKey(TAtlasFeature.EditorToolbar, Settings.GotoInterfaceKey, TAtlasStrings.Text(TAtlasTextId.GotoInterfaceCommand),
    procedure
    begin
      TAtlasIdeEditorToolbar.GotoInterface;
    end);
  AddKey(TAtlasFeature.EditorToolbar, Settings.GotoImplementationKey,
    TAtlasStrings.Text(TAtlasTextId.GotoImplementationCommand),
    procedure
    begin
      TAtlasIdeEditorToolbar.GotoImplementation;
    end);
  // Formatieren (#43): aus = keine Taste.
  if Settings.FormatCode then
    AddKey(TAtlasFeature.EditorCommands, Settings.FormatCodeKey, TAtlasStrings.Text(TAtlasTextId.FormatCodeCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.FormatCode;
      end);
  // Blockkommentar umschalten (#703): aus = Kürzel frei.
  if Settings.ToggleBlockComment then
    AddKey(TAtlasFeature.EditorCommands, Settings.ToggleBlockCommentKey, TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeBlockComment.Run;
          end);
      end);
  // Neue Zeile ober- oder unterhalb (#700): aus = die Tasten gehören der IDE.
  if Settings.NewLineAround then
  begin
    AddKey(TAtlasFeature.EditorCommands, Settings.NewLineBelowKey, TAtlasStrings.Text(TAtlasTextId.NewLineBelowCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeNewLine.Run(TAtlasNewLineDirection.Below);
          end);
      end);
    AddKey(TAtlasFeature.EditorCommands, Settings.NewLineAboveKey, TAtlasStrings.Text(TAtlasTextId.NewLineAboveCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeNewLine.Run(TAtlasNewLineDirection.Above);
          end);
      end);
  end;
  // Umschließung entfernen (#657): aus = das Kürzel gehört der IDE.
  if Settings.Unwrap then
    AddKey(TAtlasFeature.Unwrap, Settings.UnwrapKey, TAtlasStrings.Text(TAtlasTextId.UnwrapCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Unwrap,
          procedure
          begin
            TAtlasIdeUnwrap.Run;
          end);
      end);
  // Gezielt hineinspringen (#836): nur im angehaltenen Zustand; sonst geht die Taste an die IDE weiter.
  if Settings.DebugStepIntoTarget then
    AddAttemptKey(TAtlasFeature.Debugger, Settings.DebugStepIntoTargetKey,
      TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand),
      function: Boolean
      begin
        Result := TAtlasIdeStepInto.TryRun;
      end);
  // Typ des markierten Ausdrucks (#689): Strg+Umschalt+T ist in der IDE „To-Do-Eintrag hinzufügen“; mit Vorrang
  // übernommen. Aus = das Kürzel gehört der IDE.
  if Settings.ExpressionType then
    AddPriorityKey(TAtlasFeature.ExpressionType, Settings.ExpressionTypeKey,
      TAtlasStrings.Text(TAtlasTextId.ExpressionTypeCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.ExpressionType,
          procedure
          begin
            TAtlasIdeExpressionType.Run;
          end);
      end, True);
  // Sicher löschen (#716): aus = das Kürzel gehört der IDE.
  if Settings.SafeDelete then
    AddKey(TAtlasFeature.EditorCommands, Settings.SafeDeleteKey, TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.SafeDelete;
      end);
  // Units suchen (#777): aus = keine eigene Taste (die IDE behält Strg+F12 für ihren Dialog).
  if Settings.UnitSearchEnabled then
    AddKey(TAtlasFeature.UnitSearch, Settings.UnitSearchKey, TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle),
      procedure
      begin
        TAtlasIdeUnitSearch.Show;
      end);
  // Schnell öffnen (#503): aus = Strg+P bleibt der IDE.
  if Settings.QuickOpen then
    AddKey(TAtlasFeature.Palette, Settings.QuickOpenKey, TAtlasStrings.Text(TAtlasTextId.QuickOpenTitle),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Palette,
          procedure
          begin
            TAtlasIdeQuickOpen.Show;
          end);
      end);
  // Navigationsverlauf (#504): aus = Alt+Links/Rechts bleiben Zurück/Vor der IDE.
  if Settings.NavHistory then
  begin
    AddPriorityKey(TAtlasFeature.NavHistory, Settings.NavBackKey, TAtlasStrings.Text(TAtlasTextId.NavBackCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.NavHistory,
          procedure
          begin
            TAtlasIdeNavHistory.GoBack;
          end);
      end, True);
    AddPriorityKey(TAtlasFeature.NavHistory, Settings.NavForwardKey, TAtlasStrings.Text(TAtlasTextId.NavForwardCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.NavHistory,
          procedure
          begin
            TAtlasIdeNavHistory.GoForward;
          end);
      end, True);
    AddKey(TAtlasFeature.NavHistory, Settings.LastEditKey, TAtlasStrings.Text(TAtlasTextId.NavLastEditCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.NavHistory,
          procedure
          begin
            TAtlasIdeNavHistory.GoLastEdit;
          end);
      end);
  end;
  // Definition und Referenzen einblenden (#505).
  if Settings.Peek then
  begin
    AddKey(TAtlasFeature.Peek, Settings.PeekDefinitionKey, TAtlasStrings.Text(TAtlasTextId.PeekDefinitionCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Peek,
          procedure
          begin
            TAtlasIdePeek.PeekDefinition;
          end);
      end);
    AddKey(TAtlasFeature.Peek, Settings.PeekReferencesKey, TAtlasStrings.Text(TAtlasTextId.PeekReferencesCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Peek,
          procedure
          begin
            TAtlasIdePeek.PeekReferences;
          end);
      end);
  end;
  // Benannte Lesezeichen (#622): aus = keine Taste, die IDE-Lesezeichen bleiben unberührt.
  if Settings.BookmarksNamed then
    AddKey(TAtlasFeature.Bookmarks, Settings.BookmarkKey, TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Bookmarks,
          procedure
          begin
            TAtlasIdeBookmarks.AddBookmark;
          end);
      end);
  // Schnelle Lesezeichen (#1104): aus = alle Tasten gehören wieder der IDE.
  if Settings.QuickBookmarks then
  begin
    if Settings.QuickBookmarksNumberedKeys then
    begin
      AddNumberKeys(Settings.QuickBookmarkSetKey, Settings.QuickBookmarkSetKeyPriority, False);
      AddNumberKeys(Settings.QuickBookmarkJumpKey, Settings.QuickBookmarkJumpKeyPriority, True);
    end;
    // Wartezeit 0: Strg+Umschalt+K bleibt bei der IDE.
    if Settings.QuickBookmarkChordWait > 0 then
      AddPriorityAttemptKey(TAtlasFeature.QuickBookmarks, Settings.QuickBookmarkKey,
        TAtlasStrings.Text(TAtlasTextId.QuickBookmarkToggleCommand),
        function: Boolean
        begin
          Result := TAtlasIdeQuickChord.Pressed;
        end,
        Settings.QuickBookmarkKeyPriority);
    AddKey(TAtlasFeature.QuickBookmarks, Settings.NextBookmarkKey, TAtlasStrings.Text(TAtlasTextId.NextBookmarkCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.QuickBookmarks, TAtlasIdeBookmarks.NextBookmark);
      end);
    AddKey(TAtlasFeature.QuickBookmarks, Settings.PreviousBookmarkKey,
      TAtlasStrings.Text(TAtlasTextId.PreviousBookmarkCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.QuickBookmarks, TAtlasIdeBookmarks.PreviousBookmark);
      end);
  end
  else
    TAtlasIdeQuickChord.Release;
  // Erzeugen-Menü (#719): aus = Alt+Einfg bleibt frei.
  if Settings.GenerateMenu then
    AddKey(TAtlasFeature.Generate, Settings.GenerateMenuKey, TAtlasStrings.Text(TAtlasTextId.GenerateMenuCommand),
      procedure
      begin
        TAtlasIdeGenerate.Show;
      end);
  // Benachrichtigungen (#601): aus = Strg+Umschalt+Alt+N bleibt frei.
  if Settings.Notifications then
    AddKey(TAtlasFeature.Notifications, Settings.NotificationsKey, TAtlasStrings.Text(TAtlasTextId.NotificationsCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Notifications,
          procedure
          begin
            TAtlasIdeNotifications.ShowList;
          end);
      end);
  // Sprung zum Gegenstück (#635): aus = Strg+Ü und Strg+Umschalt+Ü bleiben frei.
  if Settings.JumpToMatch then
  begin
    AddKey(TAtlasFeature.EditorCommands, Settings.JumpToMatchKey, TAtlasStrings.Text(TAtlasTextId.JumpToMatchCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.JumpToMatch(False);
      end);
    AddKey(TAtlasFeature.EditorCommands, Settings.JumpToMatchSelectKey, TAtlasStrings.Text(TAtlasTextId.JumpToMatchSelectCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.JumpToMatch(True);
      end);
  end;
  // Brotkrumenleiste (#590): aus = Strg+Umschalt+. bleibt frei.
  if Settings.Breadcrumbs then
    AddKey(TAtlasFeature.Breadcrumbs, Settings.BreadcrumbsKey, TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
          procedure
          begin
            TAtlasIdeBreadcrumbs.Focus;
          end);
      end);
  // Nächste/vorherige Änderung (#507): aus = beide Tasten bleiben frei.
  if Settings.GitGutter then
  begin
    AddKey(TAtlasFeature.LineChanges, Settings.NextChangeKey, TAtlasStrings.Text(TAtlasTextId.NextChangeCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.LineChanges,
          procedure
          begin
            TAtlasIdeLineChanges.GoToChange(True);
          end);
      end);
    AddKey(TAtlasFeature.LineChanges, Settings.PreviousChangeKey, TAtlasStrings.Text(TAtlasTextId.PreviousChangeCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.LineChanges,
          procedure
          begin
            TAtlasIdeLineChanges.GoToChange(False);
          end);
      end);
  end;
  // Zeilen verschieben und duplizieren (#634): Die Tasten gehören in der IDE dem Code-Browsing und der
  // Spaltenmarkierung; bewusst übernommen, darum mit Vorrang. Aus = die IDE behält sie.
  if Settings.MoveLines then
  begin
    AddPriorityKey(TAtlasFeature.EditorCommands, Settings.MoveLinesUpKey, TAtlasStrings.Text(TAtlasTextId.MoveLinesUpCommand),
      procedure
      begin
        RunLineMove(TAtlasLineMoveKind.MoveUp);
      end, True);
    AddPriorityKey(TAtlasFeature.EditorCommands, Settings.MoveLinesDownKey, TAtlasStrings.Text(TAtlasTextId.MoveLinesDownCommand),
      procedure
      begin
        RunLineMove(TAtlasLineMoveKind.MoveDown);
      end, True);
    AddPriorityKey(TAtlasFeature.EditorCommands, Settings.DuplicateLinesUpKey, TAtlasStrings.Text(TAtlasTextId.DuplicateLinesUpCommand),
      procedure
      begin
        RunLineMove(TAtlasLineMoveKind.DuplicateUp);
      end, True);
    AddPriorityKey(TAtlasFeature.EditorCommands, Settings.DuplicateLinesDownKey, TAtlasStrings.Text(TAtlasTextId.DuplicateLinesDownCommand),
      procedure
      begin
        RunLineMove(TAtlasLineMoveKind.DuplicateDown);
      end, True);
  end;
  // Anweisung vervollständigen (#697): Strg+Umschalt+Enter sucht in der IDE Referenzen; mit Vorrang übernommen.
  if Settings.CompleteStatement then
    AddPriorityKey(TAtlasFeature.EditorCommands, Settings.CompleteStatementKey, TAtlasStrings.Text(TAtlasTextId.CompleteStatementCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeStatementCompletion.Run;
          end);
      end, True);
  // Mehrere Einfügemarken (#589, experimentell): mit Rückfall, ohne Treffer behält die IDE die Taste (Strg+D =
  // Quelltext formatieren). Bewusst eingeschaltet, darum ohne Konfliktprüfung.
  if Settings.MultiCursor then
  begin
    AddAttemptKey(TAtlasFeature.MultiCursor, Settings.MultiCursorNextKey, TAtlasStrings.Text(TAtlasTextId.MultiCursorNextCommand),
      function: Boolean
      begin
        Result := TAtlasIdeMultiCursor.TryNext;
      end, False);
    AddAttemptKey(TAtlasFeature.MultiCursor, Settings.MultiCursorLineEndsKey, TAtlasStrings.Text(TAtlasTextId.MultiCursorLineEndsCommand),
      function: Boolean
      begin
        Result := TAtlasIdeMultiCursor.TryLineEnds;
      end, False);
    AddAttemptKey(TAtlasFeature.MultiCursor, Settings.MultiCursorAboveKey, TAtlasStrings.Text(TAtlasTextId.MultiCursorAboveCommand),
      function: Boolean
      begin
        Result := TAtlasIdeMultiCursor.TryVertical(True);
      end, False);
    AddAttemptKey(TAtlasFeature.MultiCursor, Settings.MultiCursorBelowKey, TAtlasStrings.Text(TAtlasTextId.MultiCursorBelowCommand),
      function: Boolean
      begin
        Result := TAtlasIdeMultiCursor.TryVertical(False);
      end, False);
  end;
  AddKey(TAtlasFeature.EditorCommands, Settings.UndoKey, TAtlasStrings.Text(TAtlasTextId.UndoMenu),
    procedure
    begin
      TAtlasIdeUndo.UndoLast;
    end);
  AddKey(TAtlasFeature.EditorCommands, Settings.RedoKey, TAtlasStrings.Text(TAtlasTextId.RedoMenu),
    procedure
    begin
      TAtlasIdeUndo.RedoLast;
    end);
  if (FBound = Previous) and ((FBindingIndex >= 0) = (FBound <> '')) then
    Exit;
  if FBound = '' then
    TAtlasIdeKeys.Unbind(FBindingIndex)
  else
    TAtlasIdeKeys.Bind(FBinding, FBindingIndex);
end;

end.
