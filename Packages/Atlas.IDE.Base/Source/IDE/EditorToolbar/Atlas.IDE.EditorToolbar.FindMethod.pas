unit Atlas.IDE.EditorToolbar.FindMethod;

// „Methode suchen“ der Editorleiste (#1101): Atlas-Popup mit den Routinen der
// Datei aus der Gliederung (TAtlasIdeOutlineCache), ohne Eingabe in
// Quelltextreihenfolge mit der Methode am Caret vorgewählt; Enter springt zur
// Implementierung, Umschalt+Enter zur Deklaration. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI;

type
  TAtlasIdeFindMethod = class
  public
    /// <summary>Caret der Ansicht als 0-basierte Zeile und Zeichenindex; False ohne Ansicht.</summary>
    class function CaretOf(const AView: IOTAEditView; out ALine, ACharacter: Integer): Boolean; static;
    /// <summary>Popup für die aktive Ansicht; ohne Gliederung meldet ASay den Grund.</summary>
    class procedure Show(const ASay: TProc<string>); static;
  end;

implementation

uses
  System.Types,
  Vcl.Forms,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.EditorToolbar.ReturnPoint,
  Atlas.UI.EditorToolbar.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Outline.Cache;

/// <summary>Ein Eintrag je Routine: Kennung ist der Knoten, Text der qualifizierte Name.</summary>
function RoutineCommands(const ANodes: TAtlasOutlineNodes; const ARoutines: TArray<Integer>): TArray<TAtlasCommand>;
var
  mNode: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mNode in ARoutines do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mNode);
    mCommand.Caption := TAtlasBreadcrumbs.QualifiedName(ANodes, mNode);
    mCommand.Path := ANodes[mNode].Detail;
    Result := Result + [mCommand];
  end;
end;

/// <summary>Sprung zum gewählten Knoten: Enter zur Implementierung, Umschalt+Enter zur Deklaration.</summary>
function GoToRoutine(const AFileName: string; const ANodes: TAtlasOutlineNodes): TProc<TAtlasCommand, Boolean>;
begin
  Result :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      mChosen, mTarget: Integer;
    begin
      mChosen := StrToIntDef(ACommand.Id, -1);
      mTarget := -1;
      if (mChosen >= 0) and (mChosen <= High(ANodes)) then
      begin
        mTarget := TAtlasBreadcrumbs.Target(ANodes, mChosen, not AShifted);
      end;
      if mTarget >= 0 then
      begin
        TAtlasIdeNavigation.GoToLocation(AFileName, ANodes[mTarget].NameLine, ANodes[mTarget].NameCharacter);
      end;
    end;
end;

/// <summary>Fläche, über der das Popup steht: aktives Fenster, Hauptfenster oder Arbeitsbereich.</summary>
function PopupArea: TRect;
begin
  if Screen.ActiveForm <> nil then
  begin
    Result := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    Result := Application.MainForm.BoundsRect;
  end
  else
  begin
    Result := Screen.WorkAreaRect;
  end;
end;

class function TAtlasIdeFindMethod.CaretOf(const AView: IOTAEditView; out ALine, ACharacter: Integer): Boolean;
var
  mCursor: TOTAEditPos;
begin
  Result := False;
  ALine := -1;
  ACharacter := -1;
  if AView = nil then
  begin
    Exit;
  end;
  mCursor := AView.CursorPos;
  if mCursor.Line < 1 then
  begin
    Exit;
  end;
  ALine := mCursor.Line - 1;
  ACharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, mCursor.Line), mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  Result := True;
end;

class procedure TAtlasIdeFindMethod.Show(const ASay: TProc<string>);
var
  mView: IOTAEditView;
  mSnapshot: TAtlasOutlineSnapshot;
  mRoutines: TArray<Integer>;
  mCommand: TAtlasCommand;
  mLine, mCharacter: Integer;
  mCurrent: string;
  mCommands: TArray<TAtlasCommand>;
  mWindow: TAtlasPaletteWindow;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if mView = nil then
  begin
    Exit;
  end;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(mView);
  mRoutines := nil;
  if mSnapshot.Status = TAtlasOutlineStatus.Ready then
  begin
    mRoutines := TAtlasBreadcrumbs.Routines(mSnapshot.Nodes);
  end;
  if Length(mRoutines) = 0 then
  begin
    ASay(TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.FindMethodNoOutline));
    Exit;
  end;
  // Kopien: Das Popup lebt länger als der aktuelle Stand.
  mCurrent := '';
  if CaretOf(mView, mLine, mCharacter) then
  begin
    mCurrent := TAtlasReturnPoints.ContextAt(mSnapshot.Nodes, mLine);
  end;
  mCommands := RoutineCommands(mSnapshot.Nodes, mRoutines);
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, mCommands, nil, TAtlasIdeStyle.Colors);
  mWindow.Prompt := Format(TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.FindMethodPrompt),
    [ExtractFileName(mSnapshot.FileName)]);
  // Ohne Eingabe in Quelltextreihenfolge, die Methode am Caret vorgewählt.
  mWindow.KeepOrder := True;
  for mCommand in mCommands do
  begin
    if (mCurrent <> '') and SameText(mCommand.Caption, mCurrent) then
    begin
      mWindow.InitialId := mCommand.Id;
    end;
  end;
  mWindow.OnExecuteShift := GoToRoutine(mSnapshot.FileName, mSnapshot.Nodes);
  mWindow.ShowOver(PopupArea);
end;

end.
