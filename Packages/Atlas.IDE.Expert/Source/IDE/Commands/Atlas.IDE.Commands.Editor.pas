unit Atlas.IDE.Commands.Editor;

// Befehle im Editor (#399) für das Menü Atlas, das Kontextmenü des Editors,
// die Tastenkürzel und die Befehlspalette:
// - Code-Aktionen für die Auswahl bzw. den Cursor (textDocument/codeAction)
//   in einem Fenster wie die Befehlspalette, in der Reihenfolge des Servers,
//   bevorzugte zuerst (Ersatz für die Glühbirne). Die gewählte ändert die
//   Puffer über TAtlasIdeWorkspaceEdit (je Datei ein Rückgängig-Schritt, #397)
//   und führt danach ihren Befehl aus: atlas.copyText legt das erste Argument
//   in die Zwischenablage, atlas.openFile öffnet die Datei der URI im ersten
//   Argument (Testunit, #274/#189), alle anderen gehen als
//   workspace/executeCommand an den Server.
// - Auswahl erweitern und verkleinern (textDocument/selectionRange).
// - Gehe zu Typdefinition (textDocument/typeDefinition); Gehe zu
//   Implementierung liegt im Ergebnisfenster (#400).
// - Zwischen Deklaration und Implementierung wechseln (#775): ohne Server,
//   direkt aus dem Puffer (Atlas.Core.Editor.MethodToggle).
// - Qualifizierten Namen kopieren (atlas.server.qualifiedName, #128).
// - Schnellbefehle mit „/“ nach Enter (#293) und ///-Gerüste (#88): Nach jeder
//   Änderung im Editor prüft TAtlasSlashTrigger die Cursorzeile; passt sie,
//   geht textDocument/onTypeFormatting an den Server, und zwar nach der
//   Nachrichtenverarbeitung (ForceQueue), nie im Notifier selbst.
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
  Atlas.IDE.Commands.ContextMenu;

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
    class procedure ExpandSelection; static;
    class procedure ShrinkSelection; static;
    class procedure GoToTypeDefinition; static;
    /// <summary>Cursor zum Gegenstück der Methode am Cursor (Deklaration ⇄ Implementierung, #775); False ohne
    /// Gegenstück, dann ohne Meldung (die Taste geht an die IDE weiter).</summary>
    class function TryToggleMethod: Boolean; static;
    /// <summary>Wie TryToggleMethod, für Menü und Palette: ohne Gegenstück eine Zeile in der Meldungsansicht.</summary>
    class procedure ToggleMethod; static;
    class procedure CopyQualifiedName(AWithParameters: Boolean); static;
    /// <summary>Nach jeder Änderung im Editor (Notifier): Schnellbefehle und ///-Gerüste auslösen.</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
    /// <summary>Untermenü Atlas in die Kontextmenüs der Editorfenster hängen.</summary>
    class procedure EnsureContextMenus; static;
  end;

implementation

uses
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
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Undo.Changes;

const
  // Code-Aktionen und Befehle des Servers; Befehle können projektweit arbeiten.
  CommandTimeoutMs = 30000;
  // Beim Tippen: lieber nichts tun als die IDE aufhalten.
  SlashTimeoutMs = 3000;
  CopyTextCommand = 'atlas.copyText';
  OpenFileCommand = 'atlas.openFile';
  QualifiedNameCommand = 'atlas.server.qualifiedName';

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
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.EditorActions),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ActionsKey;
    end,
    procedure
    begin
      CodeActions;
    end);
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.EditorExpand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ExpandKey;
    end,
    procedure
    begin
      ExpandSelection;
    end);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.EditorShrink),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ShrinkKey;
    end,
    procedure
    begin
      ShrinkSelection;
    end);
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.MenuImplementations),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ImplementationKey;
    end,
    procedure
    begin
      // Über das Ergebnisfenster (#400): eine einzige Implementierung springt direkt.
      TAtlasIdeResults.FindImplementations;
    end);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.TypeDefinitionKey;
    end,
    procedure
    begin
      GoToTypeDefinition;
    end);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
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
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.MenuReferences), nil,
    procedure
    begin
      TAtlasIdeResults.FindReferences;
    end);
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.EditorCopyQualified), nil,
    procedure
    begin
      CopyQualifiedName(False);
    end);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.EditorCopyQualifiedParams), nil,
    procedure
    begin
      CopyQualifiedName(True);
    end);
  // Atlas-Änderungen über mehrere Dateien (#721).
  FContextMenu.Add('-', nil, nil);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.UndoMenu),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.UndoKey;
    end,
    procedure
    begin
      TAtlasIdeUndo.UndoLast;
    end);
  FContextMenu.Add(TAtlasStrings.Text(TAtlasTextId.RedoMenu),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.RedoKey;
    end,
    procedure
    begin
      TAtlasIdeUndo.RedoLast;
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
  TAtlasEditorHover.GoToLocation(Found[0].FileName, Found[0].Line, Found[0].Character);
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

class procedure TAtlasIdeEditorCommands.Apply(const AAction: TLspCodeAction);
var
  Outcome: TAtlasWorkspaceEditResult;
begin
  // LSP: erst die Änderung, dann der Befehl.
  if not AAction.Edit.IsEmpty then
  begin
    Outcome := TAtlasIdeWorkspaceEdit.Apply(AAction.Edit, TAtlasIdeSettings.Current.OpenForEdits, AAction.Title);
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
        TAtlasEditorHover.GoToLocation(TLspSession.UriToPath(TJSONArray(Arguments).Items[0].Value), 0, 0);
    finally
      Arguments.Free;
    end;
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
  TThread.ForceQueue(nil,
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
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, False, TAtlasStrings.Text(TAtlasTextId.UndoActionSlash));
  if Outcome.Error <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  // ///-Gerüst: Cursor ans Ende der zweiten Zeile, in den Text der Zusammenfassung.
  if (AKind = TAtlasSlashKind.DocComment) and (Edits[0].NewText.Contains(#10)) then
  begin
    Target.Line := Edits[0].StartPos.Line + 2;
    Target.Col := Length(TAtlasEditorBuffer.LineText(AView, Target.Line)) + 1;
    AView.CursorPos := Target;
    AView.Paint;
  end;
end;

end.
