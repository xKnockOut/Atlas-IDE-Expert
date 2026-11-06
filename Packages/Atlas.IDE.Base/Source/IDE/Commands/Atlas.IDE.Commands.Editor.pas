unit Atlas.IDE.Commands.Editor;

// Befehle im Editor (#399) für das Menü Atlas, das Kontextmenü des Editors,
// die Tastenkürzel und die Befehlspalette:
// - Code-Aktionen für die Auswahl bzw. den Cursor (textDocument/codeAction)
//   in einem Fenster wie die Befehlspalette, in der Reihenfolge des Servers,
//   bevorzugte zuerst (Ersatz für die Glühbirne). Die gewählte ändert die
//   Puffer über TAtlasIdeWorkspaceEdit (je Datei ein Rückgängig-Schritt, #397)
//   und führt danach ihren Befehl aus. Trägt die Aktion eine Vorschau
//   (data.preview, #663), zeigt Atlas vorher die Änderungen mit diesem Text wie
//   beim Umbenennen und übernimmt erst nach Bestätigung. Gesperrte Aktionen
//   (disabled) stehen als Hinweis am Ende und nennen beim Wählen den Grund.
//   Befehle: atlas.copyText legt das erste Argument in die Zwischenablage,
//   atlas.openFile öffnet die Datei der URI im ersten Argument (Testunit, #274/#189),
//   atlas.goToPosition setzt den Cursor im oberen Editor auf Zeile und Zeichen aus den Argumenten (Sprung zur
//   Freigabe, #915), atlas.showSignatureHelp setzt ihn ebenso und öffnet
//   den Parameter-Hint (OnSignatureHelp, setzt die Composition; #1007),
//   atlas.showUnitRelations zeigt die Unit-Beziehungen der Unit im Editor
//   („Graph zeigen“ an einem Unit-Zyklus, OnUnitRelations; #896),
//   atlas.changeSignature (#100), atlas.moveClass (#103),
//   atlas.extractInterface (#664), atlas.extractSuperclass (#713) und
//   atlas.moveMember (#675) öffnen ihren Dialog, atlas.invertBoolean (#715) und
//   atlas.promoteVariable (#668) fragen einen Namen, alle anderen gehen als
//   workspace/executeCommand an den Server.
// - Auswahl erweitern und verkleinern (textDocument/selectionRange).
// - Gehe zu Typdefinition (textDocument/typeDefinition); Gehe zu
//   Implementierung liegt im Ergebnisfenster (#400).
// - Zwischen Deklaration und Implementierung wechseln (#775): ohne Server,
//   direkt aus dem Puffer (Atlas.Core.Editor.MethodToggle).
// - Qualifizierten Namen kopieren (atlas.server.qualifiedName, #128).
// - „Weg von hier nach …“ (#1117): Dialog „Weg zwischen Symbolen“ mit dem
//   qualifizierten Namen am Cursor als „Von“; nur sichtbar, solange
//   navigation.symbolPath an ist (ApplySettings).
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
// - Test am Cursor ausführen bzw. debuggen (#585): Einträge des Moduls Tests
//   im Kontextmenü (#1455), nicht mehr hier.
// - „Element ausblenden …“ (#628): Menü zum gezeichneten Element an der Stelle
//   des Rechtsklicks bzw. in der Zeile der Schreibmarke (TAtlasIdeHide).
// - Nächster bzw. vorheriger Befund in der oberen Datei (#509): alle Atlas-
//   Diagnosen der Datei aus OnProblemsOf (setzt die Composition aus dem
//   Problemspeicher), am Ende wieder von vorn; ohne Server.
//   Ist das Fenster „Atlas-Prüfung“ sichtbar, geht es durch dessen gefilterte
//   Liste (OnStepList, #909), auch in andere Dateien.
// Vor jeder Anfrage bekommt der Server den aktuellen Text der Datei.
// Meldungen nur als Zeile in der Meldungsansicht, nie als Dialog.
// Aufgeteilt (Vorfahren je eine Unit): EditorContext (Stand, obere Ansicht),
// EditorSelection (Auswahl, Sprünge), EditorServer (Anfragen an den Server,
// Schnellbefehle), EditorActions (Code-Aktionen, Client-Befehle in
// ClientCommands); das Kontextmenü füllt EditorMenu.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Commands.ContextMenu,
  Atlas.IDE.Commands.EditorActions;

type
  /// <summary>Befehle im Editor: Anmeldung, Kontextmenü und Notifier; die Befehle selbst kommen von den Vorfahren.
  /// </summary>
  TAtlasIdeEditorCommands = class(TAtlasEditorActionCommands)
  private class var
    FNotifier: INTAEditServicesNotifier;
    FNotifierIndex: Integer;
    FContextMenu: TAtlasIdeContextMenu;
  public
    /// <summary>ASessionOf: laufende Sitzung (Server bei Bedarf gestartet) oder nil; AMessage: Zeile für
    /// die Meldungsansicht.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Nach geänderten Einstellungen: Sichtbarkeit der Kontextmenüeinträge.</summary>
    class procedure ApplySettings; static;
    /// <summary>Untermenü Atlas in die Kontextmenüs der Editorfenster hängen.</summary>
    class procedure EnsureContextMenus; static;
    /// <summary>Nach einer Einstellungsänderung: abschaltbare Einträge des Kontextmenüs (#1120) ein- bzw. ausblenden.
    /// </summary>
    class procedure UpdateContextMenus; static;
  end;

implementation

uses
  System.Classes,
  DockForm,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Editor.EnterWatch,
  Atlas.IDE.Editor.PatternContinuation,
  Atlas.IDE.Editor.MultiCursor,
  Atlas.IDE.Editor.LinkedEditing,
  Atlas.IDE.Editor.SmartPaste,
  Atlas.IDE.Editor.Unwrap,
  Atlas.IDE.Editor.ExpressionType,
  Atlas.IDE.Editor.MethodPlacement,
  Atlas.IDE.Editor.RegionFolds,
  Atlas.IDE.Commands.EditorMenu;

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
  begin
    TAtlasGuard.Run(TAtlasFeature.EditorCommands,
      procedure
      begin
        TAtlasIdeEditorCommands.EnsureContextMenus;
      end);
  end;
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
var
  mFailure: string;
begin
  // Je Funktion mit ihrer eigenen Sicherung: Ein Fehler beim Schließen der einen lässt die übrigen nicht aus.
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeEditorCommands.EnsureContextMenus;
    end);
  // Ein Mustervorschlag gilt nur in seiner Ansicht (#671), ebenso Zusatzmarken (#589) und das Mitziehen von
  // Bezeichnern (#658).
  TAtlasGuard.Run(TAtlasFeature.ContinueLines,
    procedure
    begin
      TAtlasIdePatternContinuation.Dismiss;
    end);
  TAtlasGuard.Run(TAtlasFeature.MultiCursor,
    procedure
    begin
      TAtlasIdeMultiCursor.Dismiss;
    end);
  TAtlasGuard.Run(TAtlasFeature.LinkedEditing,
    procedure
    begin
      TAtlasIdeLinkedEditing.Dismiss;
    end);
  // Einfügen mit uses-Ergänzung (#515): Das Fenster gilt nur in seiner Ansicht.
  TAtlasGuard.Run(TAtlasFeature.SmartPaste,
    procedure
    begin
      TAtlasIdeSmartPaste.Dismiss;
    end);
  // Umschließung entfernen (#657): Liste und Vorschau ebenso.
  TAtlasGuard.Run(TAtlasFeature.Unwrap,
    procedure
    begin
      TAtlasIdeUnwrap.Dismiss;
    end);
  // Module (#1455), z. B. „Gezielt hineinspringen“: Listen gehören zur bisherigen Ansicht.
  for mFailure in TAtlasModuleContributions.EditorViewActivated(AtlasModuleRegistry) do
  begin
    TAtlasGuard.Log('Ansichtswechsel im Modul: ' + mFailure);
  end;
  // Typ des Ausdrucks (#689): Der Tooltip gilt nur in seiner Ansicht.
  TAtlasGuard.Run(TAtlasFeature.ExpressionType,
    procedure
    begin
      TAtlasIdeExpressionType.Dismiss;
    end);
  // Methodenreihenfolge (#660): Neue Rümpfe zählen gegen den Stand der neuen Ansicht.
  TAtlasGuard.Run(TAtlasFeature.MethodPlacement,
    procedure
    begin
      TAtlasIdeMethodPlacement.Dismiss;
    end);
  // Regionen beim Öffnen (#1814): eine frisch geöffnete Datei bei ihrer ersten Anzeige falten.
  TAtlasGuard.Run(TAtlasFeature.RegionFolds, TAtlasIdeRegionFolds.ViewActivated);
end;

procedure TEditorNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
var
  mView: IOTAEditView;
begin
  mView := EditView;
  TAtlasGuard.Run(TAtlasFeature.SlashCommands,
    procedure
    begin
      TAtlasIdeEditorCommands.EditorModified(mView);
    end);
  // Zeilenumbruch für Kommentar und Muster fortsetzen (#696, #671), unabhängig von den Schrägstrich-Befehlen;
  // ein sichtbarer Mustervorschlag verschwindet mit jeder Änderung.
  TAtlasGuard.Run(TAtlasFeature.ContinueLines,
    procedure
    begin
      TAtlasIdePatternContinuation.EditorModified;
      TAtlasEnterWatch.EditorModified(mView);
    end);
  // Mehrfachmarken (#589): fremde Änderungen an allen Marken nachziehen.
  TAtlasGuard.Run(TAtlasFeature.MultiCursor,
    procedure
    begin
      TAtlasIdeMultiCursor.EditorModified(mView);
    end);
  // Bezeichner live mitziehen (#658): Änderungen der IDE am Namen nachziehen, sonst die Antwort verwerfen.
  TAtlasGuard.Run(TAtlasFeature.LinkedEditing,
    procedure
    begin
      TAtlasIdeLinkedEditing.EditorModified(mView);
    end);
  // Einfügen mit uses-Ergänzung (#515): nach einem Einfügen sehen, ein offenes Fenster schließen.
  TAtlasGuard.Run(TAtlasFeature.SmartPaste,
    procedure
    begin
      TAtlasIdeSmartPaste.EditorModified;
    end);
  // Umschließung entfernen (#657): Jede Änderung schließt die Liste ohne Änderung.
  TAtlasGuard.Run(TAtlasFeature.Unwrap,
    procedure
    begin
      TAtlasIdeUnwrap.EditorModified;
    end);
  // Typ des Ausdrucks (#689): Jede Änderung schließt den Tooltip.
  TAtlasGuard.Run(TAtlasFeature.ExpressionType,
    procedure
    begin
      TAtlasIdeExpressionType.EditorModified;
    end);
  // Methodenreihenfolge (#660): nach der Ruhezeit auf neue Rümpfe sehen.
  TAtlasGuard.Run(TAtlasFeature.MethodPlacement,
    procedure
    begin
      TAtlasIdeMethodPlacement.EditorModified;
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
  mEditors: IOTAEditorServices;
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
  FLastSlash := '';
  FAnchorFile := '';
  FNotifierIndex := -1;
  FContextMenu := TAtlasIdeContextMenu.Create;
  TAtlasEditorMenu.Fill(FContextMenu);
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    FNotifier := TEditorNotifier.Create;
    FNotifierIndex := mEditors.AddNotifier(FNotifier);
  end;
  EnsureContextMenus;
end;

class procedure TAtlasIdeEditorCommands.Uninstall;
var
  mEditors: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mEditors.RemoveNotifier(FNotifierIndex);
  end;
  FNotifierIndex := -1;
  FNotifier := nil;
  // Wartet eine laufende Anfrage ab und verwirft ihre Antwort.
  FreeAndNil(FSlashRequest);
  FreeAndNil(FTestUnitRequest);
  FreeAndNil(FContextMenu);
  FSessionOf := nil;
  FMessage := nil;
  FProblemsOf := nil;
  FOnPlaceholders := nil;
  FOnSignatureHelp := nil;
  FOnUnitRelations := nil;
end;

class procedure TAtlasIdeEditorCommands.EnsureContextMenus;
begin
  if FContextMenu <> nil then
  begin
    FContextMenu.EnsureAll;
  end;
end;

class procedure TAtlasIdeEditorCommands.UpdateContextMenus;
begin
  if FContextMenu <> nil then
  begin
    FContextMenu.UpdateVisibility;
  end;
end;

class procedure TAtlasIdeEditorCommands.ApplySettings;
begin
  if FContextMenu <> nil then
  begin
    FContextMenu.UpdateVisibility;
  end;
end;

end.
