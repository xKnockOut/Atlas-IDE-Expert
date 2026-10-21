unit Atlas.IDE.Commands.Editor;

// Befehle im Editor (#399) für das Menü Atlas, das Kontextmenü des Editors,
// die Tastenkürzel und die Befehlspalette:
// - Code-Aktionen für die Auswahl bzw. den Cursor (textDocument/codeAction)
//   in einem Fenster wie die Befehlspalette, in der Reihenfolge des Servers,
//   bevorzugte zuerst (Ersatz für die Glühbirne). Die gewählte ändert die
//   Puffer über TAtlasIdeWorkspaceEdit (je Datei ein Rückgängig-Schritt, #397)
//   und führt danach ihren Befehl aus: atlas.copyText legt das erste Argument
//   in die Zwischenablage, atlas.openFile öffnet die Datei der URI im ersten
//   Argument (Testunit, #274/#189), atlas.changeSignature (#100) und
//   atlas.moveClass (#103) öffnen ihren Dialog, alle anderen gehen als
//   workspace/executeCommand an den Server.
// - Auswahl erweitern und verkleinern (textDocument/selectionRange).
// - Gehe zu Typdefinition (textDocument/typeDefinition); Gehe zu
//   Implementierung liegt im Ergebnisfenster (#400).
// - Zwischen Deklaration und Implementierung wechseln (#775): ohne Server,
//   direkt aus dem Puffer (Atlas.Core.Editor.MethodToggle).
// - Qualifizierten Namen kopieren (atlas.server.qualifiedName, #128).
// - Zwischen Unit und Testunit wechseln (atlas.server.testUnit, #189): öffnet
//   das Gegenstück; fehlt die Testunit, legt das Edit des Servers sie an und
//   trägt sie ins Testprojekt ein (#274), danach wird sie geöffnet.
// - Formatieren (#43): ganze Datei (textDocument/formatting) bzw. die Zeilen
//   der Auswahl (textDocument/rangeFormatting), ein Rückgängig-Schritt.
// - Schnellbefehle mit „/“ nach Enter (#293) und ///-Gerüste (#88): Nach jeder
//   Änderung im Editor prüft TAtlasSlashTrigger die Cursorzeile; passt sie,
//   geht textDocument/onTypeFormatting an den Server, und zwar nach der
//   Nachrichtenverarbeitung (ForceQueue), nie im Notifier selbst. Das
//   eingesetzte Gerüst füllt der Platzhalter-Modus der Vervollständigung
//   (OnPlaceholders, setzt die Composition); über einer Methodenimplementierung
//   steht es an der Deklaration in der Klasse.
// - Test am Cursor ausführen bzw. debuggen (#585): nur Einträge im
//   Kontextmenü; was sie tun, setzt die Composition über OnRunTest und
//   OnDebugTest (A-09: die Befehle importieren die Tests nicht).
// - „Element ausblenden …“ (#628): Menü zum gezeichneten Element an der Stelle
//   des Rechtsklicks bzw. in der Zeile der Schreibmarke (TAtlasIdeHide).
// - Nächster bzw. vorheriger Befund in der oberen Datei (#509): alle Atlas-
//   Diagnosen der Datei aus OnProblemsOf (setzt die Composition aus dem
//   Problemspeicher), am Ende wieder von vorn; ohne Server.
// Vor jeder Anfrage bekommt der Server den aktuellen Text der Datei.
// Meldungen nur als Zeile in der Meldungsansicht, nie als Dialog.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.SlashTrigger,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Problems.Contract,
  Atlas.IDE.Commands.ContextMenu;

type
  /// <summary>Platzhalter-Modus für eingesetzten Text (#88): ABefore = Puffertext vorher, AOffset = Anfang im
  /// Puffer.</summary>
  TAtlasPlaceholdersProc = reference to procedure(const AView: IOTAEditView; const ABefore: string;
    AOffset: Integer; const AExpansion: TAtlasSnippetExpansion);

  /// <summary>Befunde einer Datei (#509).</summary>
  TAtlasProblemsOfFunc = reference to function(const AFileName: string): TArray<TAtlasProblem>;

type
  TAtlasIdeEditorCommands = class
  private class var
    FSessionOf: TFunc<TLspSession>;
    FMessage: TProc<string>;
    FNotifier: INTAEditServicesNotifier;
    FNotifierIndex: Integer;
    FContextMenu: TAtlasIdeContextMenu;
    /// <summary>Letzter Auslöser eines Schnellbefehls; gegen wiederholtes Fragen an derselben Stelle.</summary>
    FLastSlash: string;
    /// <summary>Cursor beim ersten Erweitern der Auswahl.</summary>
    FAnchorFile: string;
    FAnchor: TLspTextPosition;
    FOnRunTest: TProc;
    FOnDebugTest: TProc;
    FProblemsOf: TAtlasProblemsOfFunc;
    FOnPlaceholders: TAtlasPlaceholdersProc;
  private
    class function Session: TLspSession; static;
    class procedure Say(const AText: string); static;
    /// <summary>Oberste Editoransicht, ihr Text (an den Server abgeglichen) und die Auswahl als Bereich
    /// (leer am Cursor ohne Auswahl). False mit Meldung ohne Server oder Editor.</summary>
    class function Current(out AView: IOTAEditView; out AFileName: string; out ALines: TArray<string>;
      out ASelection: TLspRange): Boolean; static;
    class function EditPos(const ALines: TArray<string>; const APosition: TLspTextPosition;
      ATabWidth: Integer): TOTAEditPos; static;
    class procedure Select(const AView: IOTAEditView; const ALines: TArray<string>; const ARange: TLspRange); static;
    class procedure Step(AExpand: Boolean); static;
    class procedure Apply(const AAction: TLspCodeAction); static;
    class procedure RunCommand(const ACommand, AArgumentsJson: string); static;
    class procedure RunSlash(const AView: IOTAEditView; AKind: TAtlasSlashKind); static;
  public
    /// <summary>ASessionOf: laufende Sitzung (Server bei Bedarf gestartet) oder nil; AMessage: Zeile für
    /// die Meldungsansicht.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    class procedure CodeActions; static;
    /// <summary>Code-Aktion anwenden: erst die Änderung, dann der Befehl; auch für das Erzeugen-Menü (#719).
    /// </summary>
    class procedure ApplyAction(const AAction: TLspCodeAction); static;
    /// <summary>Code-Aktion mit Kennung ATag (data.tag) für ARange der oberen Datei holen und anwenden, etwa
    /// „Entfernen“ aus dem Tooltip eines uses-Eintrags (#621). Ohne solche Aktion eine Zeile in der
    /// Meldungsansicht.</summary>
    class procedure ApplyTagged(const ARange: TLspRange; const ATag: string); static;
    class procedure ExpandSelection; static;
    class procedure ShrinkSelection; static;
    class procedure GoToTypeDefinition; static;
    /// <summary>Cursor zum Gegenstück der Methode am Cursor (Deklaration ⇄ Implementierung, #775); False ohne
    /// Gegenstück, dann ohne Meldung (die Taste geht an die IDE weiter).</summary>
    class function TryToggleMethod: Boolean; static;
    /// <summary>Wie TryToggleMethod, für Menü und Palette: ohne Gegenstück eine Zeile in der Meldungsansicht.</summary>
    class procedure ToggleMethod; static;
    /// <summary>Sprung zum Gegenstück (#635) reihum; mit ASelect vom Cursor bis zum Gegenstück markieren. Ohne
    /// eindeutiges Gegenstück passiert nichts.</summary>
    class procedure JumpToMatch(ASelect: Boolean); static;
    /// <summary>F3 bzw. Umschalt+F3 mit einzeiliger Markierung: nächstes bzw. vorheriges Vorkommen markieren
    /// und als Suchtext der IDE übernehmen. False ohne solche Markierung (die Taste geht an die IDE). Mit
    /// „Gleichen Text hervorheben“ (#709) gelten dessen Optionen; ist dort F3 abgeschaltet, geht die Taste bei
    /// passender Markierung an die IDE.</summary>
    class function TryFindSelection(ABackward: Boolean): Boolean; static;
    class procedure CopyQualifiedName(AWithParameters: Boolean); static;
    /// <summary>Zur Testunit bzw. getesteten Unit der oberen Datei; legt eine fehlende Testunit an (#189).</summary>
    class procedure SwitchTestUnit; static;
    /// <summary>Obere Datei formatieren (#43): mit Auswahl nur deren Zeilen. Ausgeschaltet oder ohne Änderung eine
    /// Zeile in der Meldungsansicht.</summary>
    class procedure FormatCode; static;
    /// <summary>Nach jeder Änderung im Editor (Notifier): Schnellbefehle und ///-Gerüste auslösen.</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
    /// <summary>Untermenü Atlas in die Kontextmenüs der Editorfenster hängen.</summary>
    class procedure EnsureContextMenus; static;
    /// <summary>Kontextmenü „Test am Cursor ausführen“ (#585); setzt die Composition, nil = ausgeschaltet (der
    /// Eintrag meldet das).</summary>
    class property OnRunTest: TProc read FOnRunTest write FOnRunTest;
    /// <summary>Kontextmenü „Test am Cursor debuggen“ (#585); nil = ausgeschaltet.</summary>
    class property OnDebugTest: TProc read FOnDebugTest write FOnDebugTest;
    /// <summary>Cursor zum nächsten (AForward) bzw. vorherigen Befund der oberen Datei (#509); ohne Befund eine
    /// Zeile in der Meldungsansicht.</summary>
    class procedure StepProblem(AForward: Boolean); static;
    /// <summary>Befunde einer Datei für StepProblem; setzt die Composition, nil = keine.</summary>
    class property OnProblemsOf: TAtlasProblemsOfFunc read FProblemsOf write FProblemsOf;
    /// <summary>Platzhalter-Modus für ///-Gerüste (#88); setzt die Composition, nil = nur der Cursor in die
    /// Zusammenfassung.</summary>
    class property OnPlaceholders: TAtlasPlaceholdersProc read FOnPlaceholders write FOnPlaceholders;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.Types,
  System.JSON,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.Clipbrd,
  DockForm,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Editor.Selection,
  Atlas.Core.Editor.MethodToggle,
  Atlas.Core.Editor.Match,
  Atlas.Core.Editor.SelectionMatches,
  Atlas.Core.Editor.TestUnit,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Editor.Hide,
  Atlas.Core.Problems.InlineHints,
  Atlas.IDE.Editor.ChangeSignature,
  Atlas.IDE.Editor.MoveClass,
  Atlas.IDE.Editor.PropertyFromAccessors,
  Atlas.IDE.Editor.InvertBoolean,
  Atlas.IDE.Editor.EnterWatch,
  Atlas.IDE.Editor.PatternContinuation,
  Atlas.IDE.Editor.MultiCursor,
  Atlas.IDE.Editor.LinkedEditing,
  Atlas.IDE.Editor.SmartPaste,
  Atlas.IDE.Editor.Unwrap,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.IDE.Foundation.Navigation;

const
  // Code-Aktionen und Befehle des Servers; Befehle können projektweit arbeiten.
  CommandTimeoutMs = 30000;
  // Beim Tippen: lieber nichts tun als die IDE aufhalten.
  SlashTimeoutMs = 3000;
  CopyTextCommand = 'atlas.copyText';
  OpenFileCommand = 'atlas.openFile';
  QualifiedNameCommand = 'atlas.server.qualifiedName';
  TestUnitCommand = 'atlas.server.testUnit';

type
  TEditorNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  public
    procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

{ TEditorNotifier }

procedure TEditorNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
  if Show then
    TAtlasGuard.Run(TAtlasFeature.EditorCommands,
      procedure
      begin
        TAtlasIdeEditorCommands.EnsureContextMenus;
      end);
end;

procedure TEditorNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TEditorNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TEditorNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TEditorNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeEditorCommands.EnsureContextMenus;
      // Ein Mustervorschlag gilt nur in seiner Ansicht (#671), ebenso Zusatzmarken (#589) und das Mitziehen von
      // Bezeichnern (#658).
      TAtlasIdePatternContinuation.Dismiss;
      TAtlasIdeMultiCursor.Dismiss;
      TAtlasIdeLinkedEditing.Dismiss;
      // Einfügen mit uses-Ergänzung (#515): Das Fenster gilt nur in seiner Ansicht.
      TAtlasIdeSmartPaste.Dismiss;
      // Umschließung entfernen (#657): Liste und Vorschau ebenso.
      TAtlasIdeUnwrap.Dismiss;
    end);
end;

procedure TEditorNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
var
  View: IOTAEditView;
begin
  View := EditView;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeEditorCommands.EditorModified(View);
    end);
  // Zeilenumbruch für Kommentar und Muster fortsetzen (#696, #671), unabhängig von den Schrägstrich-Befehlen;
  // ein sichtbarer Mustervorschlag verschwindet mit jeder Änderung.
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdePatternContinuation.EditorModified(View);
      TAtlasEnterWatch.EditorModified(View);
    end);
  // Mehrfachmarken (#589): fremde Änderungen an allen Marken nachziehen.
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeMultiCursor.EditorModified(View);
    end);
  // Bezeichner live mitziehen (#658): Änderungen der IDE am Namen nachziehen, sonst die Antwort verwerfen.
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeLinkedEditing.EditorModified(View);
    end);
  // Einfügen mit uses-Ergänzung (#515): nach einem Einfügen sehen, ein offenes Fenster schließen.
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeSmartPaste.EditorModified(View);
    end);
  // Umschließung entfernen (#657): Jede Änderung schließt die Liste ohne Änderung.
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeUnwrap.EditorModified(View);
    end);
end;

procedure TEditorNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TEditorNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TEditorNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TAtlasIdeEditorCommands }

class procedure TAtlasIdeEditorCommands.Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>);
var
  Editors: IOTAEditorServices;
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
  FLastSlash := '';
  FAnchorFile := '';
  FNotifierIndex := -1;
  FContextMenu := TAtlasIdeContextMenu.Create;
  FContextMenu.Add('Atlas.CodeActions', TAtlasStrings.Text(TAtlasTextId.EditorActions),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ActionsKey;
    end,
    procedure
    begin
      CodeActions;
    end);
  // Erzeugen-Menü (#719); aus = ohne Kürzel, der Aufruf meldet, dass es abgeschaltet ist.
  FContextMenu.Add('Atlas.GenerateMenu', TAtlasStrings.Text(TAtlasTextId.GenerateMenuCommand),
    function: Integer
    begin
      Result := 0;
      if TAtlasIdeSettings.Current.GenerateMenu then
        Result := TAtlasIdeSettings.Current.GenerateMenuKey;
    end,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          TAtlasIdeGenerate.Show;
        end);
    end);
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add('Atlas.ExpandSelection', TAtlasStrings.Text(TAtlasTextId.EditorExpand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ExpandKey;
    end,
    procedure
    begin
      ExpandSelection;
    end);
  FContextMenu.Add('Atlas.ShrinkSelection', TAtlasStrings.Text(TAtlasTextId.EditorShrink),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ShrinkKey;
    end,
    procedure
    begin
      ShrinkSelection;
    end);
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add('Atlas.Implementations', TAtlasStrings.Text(TAtlasTextId.MenuImplementations),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ImplementationKey;
    end,
    procedure
    begin
      // Über das Ergebnisfenster (#400): eine einzige Implementierung springt direkt.
      TAtlasIdeResults.FindImplementations;
    end);
  FContextMenu.Add('Atlas.TypeDefinition', TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.TypeDefinitionKey;
    end,
    procedure
    begin
      GoToTypeDefinition;
    end);
  FContextMenu.Add('Atlas.ToggleMethod', TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
    function: Integer
    begin
      Result := 0;
      if TAtlasIdeSettings.Current.MethodToggle then
        Result := TAtlasIdeSettings.Current.MethodToggleUpKey;
    end,
    procedure
    begin
      ToggleMethod;
    end);
  // Formatieren (#43); aus = ohne Kürzel, der Aufruf meldet, dass es abgeschaltet ist.
  FContextMenu.Add('Atlas.FormatCode', TAtlasStrings.Text(TAtlasTextId.FormatCodeCommand),
    function: Integer
    begin
      Result := 0;
      if TAtlasIdeSettings.Current.FormatCode then
        Result := TAtlasIdeSettings.Current.FormatCodeKey;
    end,
    procedure
    begin
      FormatCode;
    end);
  FContextMenu.Add('Atlas.References', TAtlasStrings.Text(TAtlasTextId.MenuReferences), nil,
    procedure
    begin
      TAtlasIdeResults.FindReferences;
    end);
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add('Atlas.SwitchTestUnit', TAtlasStrings.Text(TAtlasTextId.EditorTestUnit),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.TestUnitKey;
    end,
    procedure
    begin
      SwitchTestUnit;
    end);
  // Test am Cursor (#585): ohne Tests bzw. ohne „Test debuggen“ meldet der Eintrag, dass es aus ist.
  FContextMenu.Add('Atlas.RunTest', TAtlasStrings.Text(TAtlasTextId.TestsRunHereCommand), nil,
    procedure
    begin
      if Assigned(FOnRunTest) then
        FOnRunTest()
      else
        Say(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
    end);
  FContextMenu.Add('Atlas.DebugTest', TAtlasStrings.Text(TAtlasTextId.TestsDebugCommand), nil,
    procedure
    begin
      if Assigned(FOnDebugTest) then
        FOnDebugTest()
      else
        Say(TAtlasStrings.Text(TAtlasTextId.TestsDebugOff));
    end);
  FContextMenu.Add('Atlas.CopyQualifiedName', TAtlasStrings.Text(TAtlasTextId.EditorCopyQualified), nil,
    procedure
    begin
      CopyQualifiedName(False);
    end);
  FContextMenu.Add('Atlas.CopyQualifiedNameParams', TAtlasStrings.Text(TAtlasTextId.EditorCopyQualifiedParams), nil,
    procedure
    begin
      CopyQualifiedName(True);
    end);
  // Atlas-Änderungen über mehrere Dateien (#721).
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add('Atlas.UndoChange', TAtlasStrings.Text(TAtlasTextId.UndoMenu),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.UndoKey;
    end,
    procedure
    begin
      TAtlasIdeUndo.UndoLast;
    end);
  FContextMenu.Add('Atlas.RedoChange', TAtlasStrings.Text(TAtlasTextId.RedoMenu),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.RedoKey;
    end,
    procedure
    begin
      TAtlasIdeUndo.RedoLast;
    end);
  // Persönliche Notizen (#545): nach Rechtsklick in die Rinne für die angeklickte Zeile, sonst für den Cursor.
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add('Atlas.NoteAdd', TAtlasStrings.Text(TAtlasTextId.NotesMenuAdd), nil,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Notes,
        procedure
        begin
          TAtlasIdeNotes.AddOrEdit;
        end);
    end);
  FContextMenu.Add('Atlas.NoteDelete', TAtlasStrings.Text(TAtlasTextId.NotesMenuDelete), nil,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Notes,
        procedure
        begin
          TAtlasIdeNotes.DeleteAtLine;
        end);
    end);
  FContextMenu.Add('Atlas.NoteList', TAtlasStrings.Text(TAtlasTextId.NotesMenuList), nil,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Notes,
        procedure
        begin
          TAtlasIdeNotes.ShowList;
        end);
    end);
  // Benannte Lesezeichen (#622): wie die Notizen nach Rechtsklick in die Rinne für die angeklickte Zeile.
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add('Atlas.BookmarkAdd', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd),
    function: Integer
    begin
      Result := 0;
      if TAtlasIdeSettings.Current.BookmarksNamed then
        Result := TAtlasIdeSettings.Current.BookmarkKey;
    end,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.AddBookmark;
        end);
    end);
  FContextMenu.Add('Atlas.BookmarkGoTo', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuGoTo), nil,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.GoToBookmark;
        end);
    end);
  // Nächster/vorheriger Befund (#509).
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add('Atlas.NextProblem', TAtlasStrings.Text(TAtlasTextId.ProblemNextCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.NextProblemKey;
    end,
    procedure
    begin
      StepProblem(True);
    end);
  FContextMenu.Add('Atlas.PreviousProblem', TAtlasStrings.Text(TAtlasTextId.ProblemPreviousCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.PreviousProblemKey;
    end,
    procedure
    begin
      StepProblem(False);
    end);
  // Ausblenden am Element (#628): nach einem Rechtsklick auf ein Element im Text oder in der Rinne für dieses.
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add('Atlas.HideElement', TAtlasStrings.Text(TAtlasTextId.HideElementCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.HideElementKey;
    end,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          TAtlasIdeHide.ShowForCommand;
        end);
    end);
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
  begin
    FNotifier := TEditorNotifier.Create;
    FNotifierIndex := Editors.AddNotifier(FNotifier);
  end;
  EnsureContextMenus;
end;

class procedure TAtlasIdeEditorCommands.Uninstall;
var
  Editors: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Editors.RemoveNotifier(FNotifierIndex);
  FNotifierIndex := -1;
  FNotifier := nil;
  FreeAndNil(FContextMenu);
  FSessionOf := nil;
  FMessage := nil;
  FProblemsOf := nil;
  FOnPlaceholders := nil;
end;

class procedure TAtlasIdeEditorCommands.EnsureContextMenus;
begin
  if FContextMenu <> nil then
    FContextMenu.EnsureAll;
end;

class function TAtlasIdeEditorCommands.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
    Result := FSessionOf();
end;

class procedure TAtlasIdeEditorCommands.Say(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class function TAtlasIdeEditorCommands.Current(out AView: IOTAEditView; out AFileName: string;
  out ALines: TArray<string>; out ASelection: TLspRange): Boolean;
var
  Running: TLspSession;
  Editors: IOTAEditorServices;
  Text: string;
  Block: IOTAEditBlock;
  Cursor: TOTAEditPos;
  TabWidth: Integer;

  function Position(ARow, AColumn: Integer): TLspTextPosition;
  var
    LineText: string;
  begin
    LineText := '';
    if (ARow >= 1) and (ARow <= Length(ALines)) then
      LineText := ALines[ARow - 1];
    Result := TLspTextPosition.Create(ARow - 1, TLspSession.ColumnToIndex(LineText, AColumn, TabWidth));
  end;

begin
  Result := False;
  AView := nil;
  AFileName := '';
  ALines := nil;
  ASelection := Default(TLspRange);
  Running := Session;
  if Running = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    AView := Editors.TopView;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  AFileName := AView.Buffer.FileName;
  Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Running.Sync(AFileName, Text);
  ALines := Text.Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  Cursor := AView.CursorPos;
  ASelection.StartPos := Position(Cursor.Line, Cursor.Col);
  ASelection.EndPos := ASelection.StartPos;
  Block := AView.Block;
  if (Block <> nil) and Block.IsValid and (Block.Size > 0) then
  begin
    ASelection.StartPos := Position(Block.StartingRow, Block.StartingColumn);
    ASelection.EndPos := Position(Block.EndingRow, Block.EndingColumn);
  end;
  Result := True;
end;

class function TAtlasIdeEditorCommands.EditPos(const ALines: TArray<string>; const APosition: TLspTextPosition;
  ATabWidth: Integer): TOTAEditPos;
var
  LineText: string;
begin
  LineText := '';
  if (APosition.Line >= 0) and (APosition.Line < Length(ALines)) then
    LineText := ALines[APosition.Line];
  Result.Line := APosition.Line + 1;
  Result.Col := TLspSession.IndexToColumn(LineText, APosition.Character, ATabWidth);
end;

class procedure TAtlasIdeEditorCommands.Select(const AView: IOTAEditView; const ALines: TArray<string>;
  const ARange: TLspRange);
var
  TabWidth: Integer;
begin
  TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  AView.Block.Style := btNonInclusive;
  AView.CursorPos := EditPos(ALines, ARange.StartPos, TabWidth);
  // Anfang markieren, Cursor ans Ende, Ende markieren: Der Cursor steht danach am Ende der Auswahl.
  AView.Block.BeginBlock;
  AView.CursorPos := EditPos(ALines, ARange.EndPos, TabWidth);
  AView.Block.EndBlock;
  AView.MoveViewToCursor;
  AView.Paint;
end;

class procedure TAtlasIdeEditorCommands.Step(AExpand: Boolean);
var
  View: IOTAEditView;
  FileName: string;
  Lines: TArray<string>;
  Selection, Next: TLspRange;
  Position: TLspTextPosition;
  Chain: TArray<TLspRange>;
  Moved: Boolean;
begin
  if not Current(View, FileName, Lines, Selection) then
    Exit;
  // Erstes Erweitern an dieser Stelle: Der Cursor wird zum Anker.
  if Selection.IsEmpty and AExpand then
  begin
    FAnchorFile := FileName;
    FAnchor := Selection.StartPos;
  end;
  Position := TAtlasSelectionSteps.ChainPosition(Selection, SameText(FAnchorFile, FileName), FAnchor);
  try
    Chain := Session.SelectionRanges(FileName, Position.Line, Position.Character);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  if AExpand then
    Moved := TAtlasSelectionSteps.Expand(Chain, Selection, Next)
  else
    Moved := TAtlasSelectionSteps.Shrink(Chain, Selection, Next);
  if Moved then
    Select(View, Lines, Next);
end;

class procedure TAtlasIdeEditorCommands.ExpandSelection;
begin
  Step(True);
end;

class procedure TAtlasIdeEditorCommands.ShrinkSelection;
begin
  Step(False);
end;

class procedure TAtlasIdeEditorCommands.GoToTypeDefinition;
var
  View: IOTAEditView;
  FileName: string;
  Lines: TArray<string>;
  Selection: TLspRange;
  Found: TArray<TLspLocation>;
begin
  if not Current(View, FileName, Lines, Selection) then
    Exit;
  try
    Found := Session.TypeDefinition(FileName, Selection.StartPos.Line, Selection.StartPos.Character);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  if Length(Found) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  // Ein Typ hat eine Deklaration; bei mehreren (Forward-Deklaration) die erste.
  TAtlasIdeNavigation.GoToLocation(Found[0].FileName, Found[0].Line, Found[0].Character);
end;

class function TAtlasIdeEditorCommands.TryToggleMethod: Boolean;
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Text, LineText: string;
  Lines: TArray<string>;
  Cursor: TOTAEditPos;
  TabWidth, Row: Integer;
  Target: TAtlasMethodPlace;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Exit;
  View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := Text.Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  Cursor := View.CursorPos;
  Row := Cursor.Line - 1;
  LineText := '';
  if (Row >= 0) and (Row < Length(Lines)) then
    LineText := Lines[Row];
  if not TAtlasMethodToggle.Counterpart(Text, Row, TLspSession.ColumnToIndex(LineText, Cursor.Col, TabWidth),
    Target) then
    Exit;
  View.CursorPos := EditPos(Lines, TLspTextPosition.Create(Target.Line, Target.Character), TabWidth);
  View.MoveViewToCursor;
  View.Paint;
  Result := True;
end;

class procedure TAtlasIdeEditorCommands.JumpToMatch(ASelect: Boolean);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Text, LineText: string;
  Lines: TArray<string>;
  Cursor: TOTAEditPos;
  TabWidth, Row, Character: Integer;
  Target, Start, Stop: TAtlasMatchSpot;
begin
  if not TAtlasIdeSettings.Current.JumpToMatch then
    Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Exit;
  View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := Text.Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  Cursor := View.CursorPos;
  Row := Cursor.Line - 1;
  LineText := '';
  if (Row >= 0) and (Row < Length(Lines)) then
    LineText := Lines[Row];
  Character := TLspSession.ColumnToIndex(LineText, Cursor.Col, TabWidth);
  if ASelect then
  begin
    if TAtlasJumpToMatch.Selection(Text, Row, Character, Start, Stop) then
      Select(View, Lines, TLspRange.Create(Start.Line, Start.Character, Stop.Line, Stop.Character));
    Exit;
  end;
  if not TAtlasJumpToMatch.Target(Text, Row, Character, Target) then
    Exit;
  View.CursorPos := EditPos(Lines, TLspTextPosition.Create(Target.Line, Target.Character), TabWidth);
  View.MoveViewToCursor;
  View.Paint;
end;

class procedure TAtlasIdeEditorCommands.StepProblem(AForward: Boolean);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Lines: TArray<string>;
  LineText: string;
  Problems: TArray<TAtlasProblem>;
  Target: TAtlasProblem;
  Cursor: TOTAEditPos;
  TabWidth, Row: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Exit;
  View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Problems := nil;
  if Assigned(FProblemsOf) and TAtlasIdeSettings.ProblemMarksOn then
    Problems := FProblemsOf(View.Buffer.FileName);
  Lines := TAtlasEditorBuffer.Text(View.Buffer).Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  Cursor := View.CursorPos;
  Row := Cursor.Line - 1;
  LineText := '';
  if (Row >= 0) and (Row < Length(Lines)) then
    LineText := Lines[Row];
  if not TAtlasInlineDiagnostics.Next(Problems, Row, TLspSession.ColumnToIndex(LineText, Cursor.Col, TabWidth),
    AForward, Target) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ProblemNoneInFile));
    Exit;
  end;
  View.CursorPos := EditPos(Lines, TLspTextPosition.Create(Target.StartLine, Target.StartCharacter), TabWidth);
  View.MoveViewToCursor;
  View.Paint;
end;

class function TAtlasIdeEditorCommands.TryFindSelection(ABackward: Boolean): Boolean;
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Block: IOTAEditBlock;
  Lines: TArray<string>;
  Needle, LineText: string;
  TabWidth, Row, StartIndex, EndIndex: Integer;
  From: TLspTextPosition;
  Found: TLspRange;
  Options: TAtlasSelectionMatchOptions;
  Matching, NavigateF3: Boolean;
  Term: string;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Exit;
  View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Block := View.Block;
  if (Block = nil) or not Block.IsValid or (Block.Size = 0) or (Block.StartingRow <> Block.EndingRow) then
    Exit;
  Needle := Block.Text;
  if (Needle = '') or (Pos(#10, Needle) > 0) or (Pos(#13, Needle) > 0) then
    Exit;
  // Gleichen Text hervorheben (#709): F3 springt zwischen dessen Treffern, mit denselben Optionen.
  Matching := TAtlasIdeSettings.SelectionMatchesOn(Options, NavigateF3) and
    TAtlasSelectionMatches.Term(Needle, Options, Term);
  if Matching and not NavigateF3 then
    Exit;
  Lines := TAtlasEditorBuffer.Text(View.Buffer).Split([#13#10, #10]);
  Row := Block.StartingRow - 1;
  if (Row < 0) or (Row >= Length(Lines)) then
    Exit;
  LineText := Lines[Row];
  TabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  StartIndex := TLspSession.ColumnToIndex(LineText, Block.StartingColumn, TabWidth);
  EndIndex := TLspSession.ColumnToIndex(LineText, Block.EndingColumn, TabWidth);
  if ABackward then
    From := TLspTextPosition.Create(Row, StartIndex)
  else
    From := TLspTextPosition.Create(Row, EndIndex);
  if Matching then
  begin
    if not TAtlasSelectionMatches.Next(Lines, Needle, Options, From, ABackward, Found) then
      Exit;
  end
  else if not TAtlasSelectionSearch.Find(Lines, Needle, From, ABackward, Found) then
    Exit;
  // Suchtext der IDE: Strg+F und „Erneut suchen“ ohne Markierung machen damit weiter.
  try
    View.Position.SearchOptions.SearchText := Needle;
  except
    on Exception do
      ;
  end;
  Select(View, Lines, Found);
  Result := True;
end;

class procedure TAtlasIdeEditorCommands.ToggleMethod;
begin
  if not TryToggleMethod then
    Say(TAtlasStrings.Text(TAtlasTextId.EditorMethodToggleNone));
end;

class procedure TAtlasIdeEditorCommands.CopyQualifiedName(AWithParameters: Boolean);
var
  View: IOTAEditView;
  FileName, Arguments: string;
  Lines: TArray<string>;
  Selection: TLspRange;
  Values: TJSONArray;
  Answer: TJSONValue;
begin
  if not Current(View, FileName, Lines, Selection) then
    Exit;
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(FileName));
    Values.AddElement(TJSONObject.Create.AddPair('line', TJSONNumber.Create(Selection.StartPos.Line))
      .AddPair('character', TJSONNumber.Create(Selection.StartPos.Character)));
    Values.AddElement(TJSONBool.Create(AWithParameters));
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  try
    Answer := Session.RunCommand(QualifiedNameCommand, Arguments, CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  try
    if not (Answer is TJSONString) or (Answer.Value = '') then
    begin
      Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
      Exit;
    end;
    Clipboard.AsText := Answer.Value;
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditorCopied, [Answer.Value]));
  finally
    Answer.Free;
  end;
end;

class procedure TAtlasIdeEditorCommands.FormatCode;
var
  View: IOTAEditView;
  FileName: string;
  Lines: TArray<string>;
  Selection: TLspRange;
  Indent: Integer;
  Edits: TArray<TLspTextEdit>;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
begin
  if not TAtlasIdeSettings.Current.FormatCode then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.FormatCodeOff));
    Exit;
  end;
  if not Current(View, FileName, Lines, Selection) then
    Exit;
  // Breite einer Ebene aus dem Editor; .editorconfig und atlas.json gehen beim Server vor.
  Indent := TAtlasEditorBuffer.BlockIndent(View.Buffer);
  try
    if Selection.IsEmpty then
      Edits := Session.Formatting(FileName, Indent, True, CommandTimeoutMs)
    else
      Edits := Session.Formatting(FileName, Selection, Indent, True, CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  if Length(Edits) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.FormatCodeNothing));
    Exit;
  end;
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [Default(TLspFileEdits)];
  Edit.Files[0].FileName := FileName;
  Edit.Files[0].Edits := Edits;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, TAtlasUnopenedPolicy.WriteToDisk,
    TAtlasStrings.Text(TAtlasTextId.UndoActionFormat));
  if Outcome.Error <> '' then
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
end;

class procedure TAtlasIdeEditorCommands.SwitchTestUnit;
var
  View: IOTAEditView;
  FileName, Arguments: string;
  Lines: TArray<string>;
  Selection: TLspRange;
  Values: TJSONArray;
  Answer, EditValue: TJSONValue;
  Info: TAtlasTestUnitInfo;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
begin
  if not Current(View, FileName, Lines, Selection) then
    Exit;
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(FileName));
    Values.Add(Selection.StartPos.Line);
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  try
    Answer := Session.RunCommand(TestUnitCommand, Arguments, CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  try
    Info := TAtlasTestUnitInfo.FromJson(Answer,
      function(AUri: string): string
      begin
        Result := TLspSession.UriToPath(AUri);
      end);
    Edit := Default(TLspWorkspaceEdit);
    if (Answer is TJSONObject) and Info.CanCreate then
    begin
      EditValue := TJSONObject(Answer).GetValue('edit');
      Edit := TLspWorkspaceEdit.FromJson(EditValue);
    end;
  finally
    Answer.Free;
  end;
  if Info.CounterpartFile <> '' then
  begin
    TAtlasIdeNavigation.GoToLocation(Info.CounterpartFile, 0, 0);
    Exit;
  end;
  if not Info.CanCreate or Edit.IsEmpty then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestUnitNone, [Info.Reason]));
    Exit;
  end;
  // Anlegen und ins Testprojekt eintragen (#274), dann öffnen.
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    TAtlasStrings.Fmt(TAtlasTextId.TestUnitLensCreate, [Info.Counterpart]));
  if Outcome.Error <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(Info.NewFile, 0, 0);
end;

function KindCaption(const AKind: string): string;
begin
  if AKind.StartsWith('quickfix') then
    Result := TAtlasStrings.Text(TAtlasTextId.EditorKindFix)
  else if AKind.StartsWith('refactor') then
    Result := TAtlasStrings.Text(TAtlasTextId.EditorKindRefactor)
  else if AKind.StartsWith('source') then
    Result := TAtlasStrings.Text(TAtlasTextId.EditorKindSource)
  else
    Result := '';
end;

class procedure TAtlasIdeEditorCommands.CodeActions;
var
  View: IOTAEditView;
  FileName: string;
  Lines: TArray<string>;
  Selection: TLspRange;
  Found, Usable: TArray<TLspCodeAction>;
  Action: TLspCodeAction;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Index: Integer;
  Window: TAtlasPaletteWindow;
  Area: TRect;
begin
  if not Current(View, FileName, Lines, Selection) then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    try
      Found := Session.CodeActions(FileName, Selection);
    except
      on E: ELspClientError do
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  // Bevorzugte zuerst, sonst die Reihenfolge des Servers; gesperrte entfallen.
  Usable := nil;
  for Action in Found do
    if Action.Preferred and (Action.Disabled = '') then
      Usable := Usable + [Action];
  for Action in Found do
    if not Action.Preferred and (Action.Disabled = '') then
      Usable := Usable + [Action];
  if Length(Usable) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.EditorNoActions));
    Exit;
  end;
  Commands := nil;
  for Index := 0 to High(Usable) do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := IntToStr(Index);
    Command.Caption := Usable[Index].Title;
    Command.Path := KindCaption(Usable[Index].Kind);
    if Usable[Index].Preferred then
      Command.ShortCut := '★';
    Commands := Commands + [Command];
  end;
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.KeepOrder := True;
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      Chosen: Integer;
    begin
      Chosen := StrToIntDef(ACommand.Id, -1);
      if (Chosen >= 0) and (Chosen <= High(Usable)) then
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            Apply(Usable[Chosen]);
          end);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

class procedure TAtlasIdeEditorCommands.ApplyAction(const AAction: TLspCodeAction);
begin
  Apply(AAction);
end;

class procedure TAtlasIdeEditorCommands.ApplyTagged(const ARange: TLspRange; const ATag: string);
var
  View: IOTAEditView;
  FileName: string;
  Lines: TArray<string>;
  Selection: TLspRange;
  Found: TArray<TLspCodeAction>;
  Action: TLspCodeAction;
begin
  // Current gleicht den Text ab; der Bereich stammt aus den Diagnosen desselben Stands.
  if not Current(View, FileName, Lines, Selection) then
    Exit;
  try
    Found := Session.CodeActions(FileName, ARange);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  for Action in Found do
    if SameText(Action.Tag, ATag) and (Action.Disabled = '') then
    begin
      Apply(Action);
      Exit;
    end;
  Say(TAtlasStrings.Text(TAtlasTextId.UsesActionMissing));
end;

class procedure TAtlasIdeEditorCommands.Apply(const AAction: TLspCodeAction);
var
  Outcome: TAtlasWorkspaceEditResult;
begin
  // LSP: erst die Änderung, dann der Befehl.
  if not AAction.Edit.IsEmpty then
  begin
    Outcome := TAtlasIdeWorkspaceEdit.Apply(AAction.Edit,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      AAction.Title);
    if Outcome.Error <> '' then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
      Exit;
    end;
    if Outcome.Written > 0 then
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
  end;
  if AAction.Edit.Unsupported > 0 then
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditUnsupported, [AAction.Edit.Unsupported]));
  if AAction.Command <> '' then
    RunCommand(AAction.Command, AAction.ArgumentsJson);
end;

class procedure TAtlasIdeEditorCommands.RunCommand(const ACommand, AArgumentsJson: string);
var
  Arguments, Answer: TJSONValue;
  Running: TLspSession;
begin
  if ACommand = CopyTextCommand then
  begin
    // Client-Befehl: das erste Argument in die Zwischenablage.
    Arguments := TJSONObject.ParseJSONValue(AArgumentsJson);
    try
      if (Arguments is TJSONArray) and (TJSONArray(Arguments).Count > 0) and
        (TJSONArray(Arguments).Items[0] is TJSONString) then
      begin
        Clipboard.AsText := TJSONArray(Arguments).Items[0].Value;
        Say(TAtlasStrings.Text(TAtlasTextId.EditorTextCopied));
      end;
    finally
      Arguments.Free;
    end;
    Exit;
  end;
  if ACommand = OpenFileCommand then
  begin
    // Client-Befehl: Datei der URI im ersten Argument öffnen.
    Arguments := TJSONObject.ParseJSONValue(AArgumentsJson);
    try
      if (Arguments is TJSONArray) and (TJSONArray(Arguments).Count > 0) then
        TAtlasIdeNavigation.GoToLocation(TLspSession.UriToPath(TJSONArray(Arguments).Items[0].Value), 0, 0);
    finally
      Arguments.Free;
    end;
    Exit;
  end;
  if ACommand = TAtlasIdeChangeSignature.ClientCommand then
  begin
    // Client-Befehl: Dialog „Signatur ändern“ (#100); er fragt den Server selbst.
    TAtlasIdeChangeSignature.Execute(Session, AArgumentsJson,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      procedure(AText: string)
      begin
        Say(AText);
      end);
    Exit;
  end;
  if ACommand = TAtlasIdePropertyFromAccessors.ClientCommand then
  begin
    // Client-Befehl: Vorschau „Property aus Getter und Setter“ (#682); er fragt den Server selbst.
    TAtlasIdePropertyFromAccessors.Execute(Session, AArgumentsJson,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      procedure(AText: string)
      begin
        Say(AText);
      end);
    Exit;
  end;
  if ACommand = TAtlasIdeInvertBoolean.ClientCommand then
  begin
    // Client-Befehl: Namen abfragen und „Boolean umkehren“ (#715); er fragt den Server selbst.
    TAtlasIdeInvertBoolean.Execute(Session, AArgumentsJson,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      procedure(AText: string)
      begin
        Say(AText);
      end);
    Exit;
  end;
  if ACommand = TAtlasIdeMoveClass.ClientCommand then
  begin
    // Client-Befehl: Name abfragen und „Klasse verschieben“ (#103); er fragt den Server selbst.
    TAtlasIdeMoveClass.Execute(Session, AArgumentsJson,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      procedure(AText: string)
      begin
        Say(AText);
      end);
    Exit;
  end;
  Running := Session;
  if Running = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  try
    Answer := Running.RunCommand(ACommand, AArgumentsJson, CommandTimeoutMs);
    // Ein workspace/applyEdit des Servers (#397) läuft erst nach dieser Antwort im Hauptthread.
    // Eine Antwort als Text zeigen.
    try
      if (Answer is TJSONString) and (Answer.Value <> '') then
        Say(Answer.Value);
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
  end;
end;

class procedure TAtlasIdeEditorCommands.EditorModified(const AView: IOTAEditView);
var
  Cursor: TOTAEditPos;
  LineText, Previous, Before, FileName, Key: string;
  Kind: TAtlasSlashKind;
  View: IOTAEditView;
begin
  if (AView = nil) or (AView.Buffer = nil) or not TAtlasIdeSettings.Current.Enabled or
    not TAtlasIdeSettings.Current.SlashCommands then
    Exit;
  Cursor := AView.CursorPos;
  LineText := TAtlasEditorBuffer.LineText(AView, Cursor.Line);
  Before := Copy(LineText, 1, TLspSession.ColumnToIndex(LineText, Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer)));
  Previous := '';
  if Cursor.Line > 1 then
    Previous := TAtlasEditorBuffer.LineText(AView, Cursor.Line - 1);
  Kind := TAtlasSlashTrigger.Detect(Previous, Before);
  if Kind = TAtlasSlashKind.None then
  begin
    FLastSlash := '';
    Exit;
  end;
  FileName := AView.Buffer.FileName;
  Key := TAtlasSlashTrigger.Key(FileName, Cursor.Line, Kind, Previous);
  if Key = FLastSlash then
    Exit;
  FLastSlash := Key;
  // Erst nach der Änderung, wenn die IDE den Cursor gesetzt hat; nie im Notifier.
  View := AView;
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          RunSlash(View, Kind);
        end);
    end);
end;

class procedure TAtlasIdeEditorCommands.RunSlash(const AView: IOTAEditView; AKind: TAtlasSlashKind);
var
  Running: TLspSession;
  FileName, Text: string;
  Lines: TArray<string>;
  Cursor: TOTAEditPos;
  Line, Character: Integer;
  Edits: TArray<TLspTextEdit>;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Target: TOTAEditPos;
  Expansion: TAtlasSnippetExpansion;
  Document: string;
begin
  Running := Session;
  if (Running = nil) or (AView.Buffer = nil) then
    Exit;
  FileName := AView.Buffer.FileName;
  Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Running.Sync(FileName, Text);
  Lines := Text.Split([#13#10, #10]);
  Cursor := AView.CursorPos;
  Line := Cursor.Line - 1;
  if (Line < 0) or (Line >= Length(Lines)) then
    Exit;
  Character := TLspSession.ColumnToIndex(Lines[Line], Cursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  try
    Edits := Running.OnTypeFormatting(FileName, Line, Character, TAtlasSlashTrigger.TriggerChar(AKind),
      TAtlasEditorBuffer.BlockIndent(AView.Buffer), True, SlashTimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Beim Tippen keine Meldung; nur ins Protokoll.
      TAtlasGuard.Log('Schnellbefehl: ' + E.Message);
      Exit;
    end;
  end;
  if Length(Edits) = 0 then
    Exit;
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [Default(TLspFileEdits)];
  Edit.Files[0].FileName := FileName;
  Edit.Files[0].Edits := Edits;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, TAtlasUnopenedPolicy.WriteToDisk,
    TAtlasStrings.Text(TAtlasTextId.UndoActionSlash));
  if Outcome.Error <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  if AKind <> TAtlasSlashKind.DocComment then
    Exit;
  // ///-Gerüst: Platzhalter-Modus über die Beschreibungen. Das Gerüst ist die erste Änderung; über einer
  // Methodenimplementierung steht es weiter oben, das Löschen der "///"-Zeile darunter verschiebt es nicht.
  Expansion := TAtlasSlashTrigger.DocCommentExpansion(Edits[0].NewText);
  if not Expansion.HasPlaceholders then
    Exit;
  Document := TAtlasEditorBuffer.Text(AView.Buffer);
  if Assigned(FOnPlaceholders) then
  begin
    FOnPlaceholders(AView, Text, TAtlasEditorBuffer.CharOffset(Document, Edits[0].StartPos.Line,
      Edits[0].StartPos.Character), Expansion);
    Exit;
  end;
  // Ohne Platzhalter-Modus: Cursor in die Zusammenfassung.
  Lines := Document.Split([#13#10, #10]);
  Target := EditPos(Lines, TLspTextPosition.Create(Edits[0].StartPos.Line, Edits[0].StartPos.Character +
    Expansion.Stops[0].Start), TAtlasEditorBuffer.TabWidth(AView.Buffer));
  AView.CursorPos := Target;
  AView.Paint;
end;

end.
