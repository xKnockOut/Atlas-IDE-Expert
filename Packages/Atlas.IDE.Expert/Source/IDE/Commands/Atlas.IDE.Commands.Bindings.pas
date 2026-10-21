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
// keys.toggleBlockComment an ist) und Neue Zeile ober- oder unterhalb (#700,
// Umschalt+Enter und Strg+Alt+Enter, nur solange keys.newLineAround an
// ist). Jede Taste wird wie
// die der Befehlspalette vorher auf Konflikte geprüft (#494); ohne Vorrang
// bleibt eine fremde Belegung aktiv. Nach geänderten Einstellungen meldet
// Rebind die Bindung neu an. Der Befehl läuft nach der Tastenverarbeitung
// (ForceQueue), nicht in der Bindung selbst. Ausnahme sind Befehle mit
// Rückfall (AddAttemptKey): Sie laufen sofort, und ohne Treffer geht die
// Taste an die nächste Bindung (krNextProc), beim Wechsel Deklaration ⇄
// Implementierung also an die Klassennavigation der IDE. F3 und Umschalt+F3
// suchen eine einzeilige Markierung vorwärts bzw. rückwärts; ohne Markierung
// bleibt es bei „Erneut suchen“ der IDE. Strg+. (HideElementKey, #628) öffnet
// das Menü „Ausblenden“ zu den Elementen der Zeile; ohne Element geht die Taste
// an die IDE (IDE Insight).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Menus,
  ToolsAPI;

type
  TAtlasIdeEditorKeys = class
  private type
    TKey = record
      Key: Word;
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
    procedure AddKey(AKey: Integer; const AWhat: string; const AProc: TProc);
    /// <summary>Wie AddKey mit eigenem Vorrang statt des gemeinsamen (Zurück/Vor, #504). Eigener Name statt
    /// Überladung: anonyme Methoden als Argument vertragen keine Überladungen.</summary>
    procedure AddPriorityKey(AKey: Integer; const AWhat: string; const AProc: TProc; APriority: Boolean);
    /// <summary>ACheck False: ohne Konfliktprüfung, weil die Taste ohne Treffer ohnehin an die IDE weitergeht.</summary>
    procedure AddAttemptKey(AKey: Integer; const AWhat: string; const AAttempt: TFunc<Boolean>;
      ACheck: Boolean = True);
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
  Atlas.Core.Diagnostics.Guard,
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
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Editor.Hide,
  Atlas.IDE.Notifications.Service,
  Atlas.IDE.Outline.Breadcrumbs,
  Atlas.IDE.Editor.LineChanges,
  Atlas.Core.Editor.LineMove,
  Atlas.IDE.Editor.LineMove,
  Atlas.IDE.Editor.StatementCompletion,
  Atlas.IDE.Editor.MultiCursor,
  Atlas.IDE.Editor.BlockComment,
  Atlas.Core.Editor.NewLine,
  Atlas.IDE.Editor.NewLine;

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
      if Assigned(Key.Attempt) then
      begin
        Attempt := Key.Attempt;
        Done := False;
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
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
      TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.EditorCommands, Proc);
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

procedure TAtlasIdeEditorKeys.AddKey(AKey: Integer; const AWhat: string; const AProc: TProc);
begin
  AddPriorityKey(AKey, AWhat, AProc, TAtlasIdeSettings.Current.EditorKeysPriority);
end;

procedure TAtlasIdeEditorKeys.AddPriorityKey(AKey: Integer; const AWhat: string; const AProc: TProc;
  APriority: Boolean);
var
  Key: TKey;
begin
  if not TAtlasIdeKeys.Decide(Word(AKey), APriority, AWhat) then
    Exit;
  Key.Key := Word(AKey);
  Key.Proc := AProc;
  Key.Attempt := nil;
  FKeys := FKeys + [Key];
  FBound := FBound + IntToStr(AKey) + ';';
end;

procedure TAtlasIdeEditorKeys.AddAttemptKey(AKey: Integer; const AWhat: string; const AAttempt: TFunc<Boolean>;
  ACheck: Boolean);
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
  Key.Proc := nil;
  Key.Attempt := AAttempt;
  FKeys := FKeys + [Key];
  FBound := FBound + IntToStr(AKey) + ';';
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
  AddKey(Settings.ActionsKey, TAtlasStrings.Text(TAtlasTextId.EditorActions),
    procedure
    begin
      TAtlasIdeEditorCommands.CodeActions;
    end);
  AddKey(Settings.ExpandKey, TAtlasStrings.Text(TAtlasTextId.EditorExpand),
    procedure
    begin
      TAtlasIdeEditorCommands.ExpandSelection;
    end);
  AddKey(Settings.ShrinkKey, TAtlasStrings.Text(TAtlasTextId.EditorShrink),
    procedure
    begin
      TAtlasIdeEditorCommands.ShrinkSelection;
    end);
  AddKey(Settings.ImplementationKey, TAtlasStrings.Text(TAtlasTextId.MenuImplementations),
    procedure
    begin
      TAtlasIdeResults.FindImplementations;
    end);
  AddKey(Settings.TypeDefinitionKey, TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition),
    procedure
    begin
      TAtlasIdeEditorCommands.GoToTypeDefinition;
    end);
  // Deklaration ⇄ Implementierung (#775): aus = Taste bleibt bei der Klassennavigation der IDE.
  if Settings.MethodToggle then
  begin
    AddAttemptKey(Settings.MethodToggleUpKey, TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
      function: Boolean
      begin
        Result := TAtlasIdeEditorCommands.TryToggleMethod;
      end);
    AddAttemptKey(Settings.MethodToggleDownKey, TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
      function: Boolean
      begin
        Result := TAtlasIdeEditorCommands.TryToggleMethod;
      end);
  end;
  // Markierung suchen: F3 bzw. Umschalt+F3 mit einzeiliger Markierung; sonst „Erneut suchen“ der IDE.
  AddAttemptKey(ShortCut(VK_F3, []), 'F3',
    function: Boolean
    begin
      Result := TAtlasIdeEditorCommands.TryFindSelection(False);
    end, False);
  AddAttemptKey(ShortCut(VK_F3, [ssShift]), 'Umschalt+F3',
    function: Boolean
    begin
      Result := TAtlasIdeEditorCommands.TryFindSelection(True);
    end, False);
  // Ausblenden am Element (#628): mit Rückfall, ohne Element behält die IDE die Taste (Strg+. = IDE Insight).
  if Settings.HideElementKey <> 0 then
    AddAttemptKey(Settings.HideElementKey, TAtlasStrings.Text(TAtlasTextId.HideElementCommand),
      function: Boolean
      begin
        Result := False;
        try
          Result := TAtlasIdeHide.ShowForCaret;
        except
          on E: Exception do
            TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
        end;
      end, False);
  // Nächster/vorheriger Befund (#509): nur mit Problemen im Editor.
  if Settings.Problems then
  begin
    AddKey(Settings.NextProblemKey, TAtlasStrings.Text(TAtlasTextId.ProblemNextCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.StepProblem(True);
      end);
    AddKey(Settings.PreviousProblemKey, TAtlasStrings.Text(TAtlasTextId.ProblemPreviousCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.StepProblem(False);
      end);
  end;
  AddKey(Settings.TestUnitKey, TAtlasStrings.Text(TAtlasTextId.EditorTestUnit),
    procedure
    begin
      TAtlasIdeEditorCommands.SwitchTestUnit;
    end);
  // Formatieren (#43): aus = keine Taste.
  if Settings.FormatCode then
    AddKey(Settings.FormatCodeKey, TAtlasStrings.Text(TAtlasTextId.FormatCodeCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.FormatCode;
      end);
  // Blockkommentar umschalten (#703): aus = Kürzel frei.
  if Settings.ToggleBlockComment then
    AddKey(Settings.ToggleBlockCommentKey, TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentCommand),
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
    AddKey(Settings.NewLineBelowKey, TAtlasStrings.Text(TAtlasTextId.NewLineBelowCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeNewLine.Run(TAtlasNewLineDirection.Below);
          end);
      end);
    AddKey(Settings.NewLineAboveKey, TAtlasStrings.Text(TAtlasTextId.NewLineAboveCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeNewLine.Run(TAtlasNewLineDirection.Above);
          end);
      end);
  end;
  // Units suchen (#777): aus = keine eigene Taste (die IDE behält Strg+F12 für ihren Dialog).
  if Settings.UnitSearchEnabled then
    AddKey(Settings.UnitSearchKey, TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle),
      procedure
      begin
        TAtlasIdeUnitSearch.Show;
      end);
  // Schnell öffnen (#503): aus = Strg+P bleibt der IDE.
  if Settings.QuickOpen then
    AddKey(Settings.QuickOpenKey, TAtlasStrings.Text(TAtlasTextId.QuickOpenTitle),
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
    AddPriorityKey(Settings.NavBackKey, TAtlasStrings.Text(TAtlasTextId.NavBackCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeNavHistory.GoBack;
          end);
      end, True);
    AddPriorityKey(Settings.NavForwardKey, TAtlasStrings.Text(TAtlasTextId.NavForwardCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeNavHistory.GoForward;
          end);
      end, True);
    AddKey(Settings.LastEditKey, TAtlasStrings.Text(TAtlasTextId.NavLastEditCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeNavHistory.GoLastEdit;
          end);
      end);
  end;
  // Definition und Referenzen einblenden (#505).
  if Settings.Peek then
  begin
    AddKey(Settings.PeekDefinitionKey, TAtlasStrings.Text(TAtlasTextId.PeekDefinitionCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdePeek.PeekDefinition;
          end);
      end);
    AddKey(Settings.PeekReferencesKey, TAtlasStrings.Text(TAtlasTextId.PeekReferencesCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdePeek.PeekReferences;
          end);
      end);
  end;
  // Benannte Lesezeichen (#622): aus = keine Taste, die IDE-Lesezeichen bleiben unberührt.
  if Settings.BookmarksNamed then
    AddKey(Settings.BookmarkKey, TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Bookmarks,
          procedure
          begin
            TAtlasIdeBookmarks.AddBookmark;
          end);
      end);
  // Erzeugen-Menü (#719): aus = Alt+Einfg bleibt frei.
  if Settings.GenerateMenu then
    AddKey(Settings.GenerateMenuKey, TAtlasStrings.Text(TAtlasTextId.GenerateMenuCommand),
      procedure
      begin
        TAtlasIdeGenerate.Show;
      end);
  // Benachrichtigungen (#601): aus = Strg+Umschalt+Alt+N bleibt frei.
  if Settings.Notifications then
    AddKey(Settings.NotificationsKey, TAtlasStrings.Text(TAtlasTextId.NotificationsCommand),
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
    AddKey(Settings.JumpToMatchKey, TAtlasStrings.Text(TAtlasTextId.JumpToMatchCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.JumpToMatch(False);
      end);
    AddKey(Settings.JumpToMatchSelectKey, TAtlasStrings.Text(TAtlasTextId.JumpToMatchSelectCommand),
      procedure
      begin
        TAtlasIdeEditorCommands.JumpToMatch(True);
      end);
  end;
  // Brotkrumenleiste (#590): aus = Strg+Umschalt+. bleibt frei.
  if Settings.Breadcrumbs then
    AddKey(Settings.BreadcrumbsKey, TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeBreadcrumbs.Focus;
          end);
      end);
  // Nächste/vorherige Änderung (#507): aus = beide Tasten bleiben frei.
  if Settings.GitGutter then
  begin
    AddKey(Settings.NextChangeKey, TAtlasStrings.Text(TAtlasTextId.NextChangeCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            TAtlasIdeLineChanges.GoToChange(True);
          end);
      end);
    AddKey(Settings.PreviousChangeKey, TAtlasStrings.Text(TAtlasTextId.PreviousChangeCommand),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
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
    AddPriorityKey(Settings.MoveLinesUpKey, TAtlasStrings.Text(TAtlasTextId.MoveLinesUpCommand),
      procedure
      begin
        RunLineMove(TAtlasLineMoveKind.MoveUp);
      end, True);
    AddPriorityKey(Settings.MoveLinesDownKey, TAtlasStrings.Text(TAtlasTextId.MoveLinesDownCommand),
      procedure
      begin
        RunLineMove(TAtlasLineMoveKind.MoveDown);
      end, True);
    AddPriorityKey(Settings.DuplicateLinesUpKey, TAtlasStrings.Text(TAtlasTextId.DuplicateLinesUpCommand),
      procedure
      begin
        RunLineMove(TAtlasLineMoveKind.DuplicateUp);
      end, True);
    AddPriorityKey(Settings.DuplicateLinesDownKey, TAtlasStrings.Text(TAtlasTextId.DuplicateLinesDownCommand),
      procedure
      begin
        RunLineMove(TAtlasLineMoveKind.DuplicateDown);
      end, True);
  end;
  // Anweisung vervollständigen (#697): Strg+Umschalt+Enter sucht in der IDE Referenzen; mit Vorrang übernommen.
  if Settings.CompleteStatement then
    AddPriorityKey(Settings.CompleteStatementKey, TAtlasStrings.Text(TAtlasTextId.CompleteStatementCommand),
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
    AddAttemptKey(Settings.MultiCursorNextKey, TAtlasStrings.Text(TAtlasTextId.MultiCursorNextCommand),
      function: Boolean
      begin
        Result := TAtlasIdeMultiCursor.TryNext;
      end, False);
    AddAttemptKey(Settings.MultiCursorLineEndsKey, TAtlasStrings.Text(TAtlasTextId.MultiCursorLineEndsCommand),
      function: Boolean
      begin
        Result := TAtlasIdeMultiCursor.TryLineEnds;
      end, False);
    AddAttemptKey(Settings.MultiCursorAboveKey, TAtlasStrings.Text(TAtlasTextId.MultiCursorAboveCommand),
      function: Boolean
      begin
        Result := TAtlasIdeMultiCursor.TryVertical(True);
      end, False);
    AddAttemptKey(Settings.MultiCursorBelowKey, TAtlasStrings.Text(TAtlasTextId.MultiCursorBelowCommand),
      function: Boolean
      begin
        Result := TAtlasIdeMultiCursor.TryVertical(False);
      end, False);
  end;
  AddKey(Settings.UndoKey, TAtlasStrings.Text(TAtlasTextId.UndoMenu),
    procedure
    begin
      TAtlasIdeUndo.UndoLast;
    end);
  AddKey(Settings.RedoKey, TAtlasStrings.Text(TAtlasTextId.RedoMenu),
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
