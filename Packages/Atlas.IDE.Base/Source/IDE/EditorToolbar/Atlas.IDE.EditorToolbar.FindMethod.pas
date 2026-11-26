unit Atlas.IDE.EditorToolbar.FindMethod;

// „Methode suchen“ der Editorleiste (#1101): Atlas-Popup mit den Routinen der
// Datei aus der Gliederung (TAtlasIdeOutlineCache), lokale Routinen als
// „TFoo.Bar › Lokal“ hinter ihrer Routine; ohne Eingabe in
// Quelltextreihenfolge mit der innersten Routine am Caret vorgewählt; Enter
// springt zur Implementierung, Umschalt+Enter zur Deklaration. Nur im
// Hauptthread.

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
  Atlas.UI.EditorToolbar.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Foundation.Host;

/// <summary>Ein Eintrag je Routine: Kennung ist der Knoten, Text der qualifizierte Name (lokale Routinen mit ihrer
/// Routine davor).</summary>
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
    mCommand.Caption := TAtlasBreadcrumbs.RoutineName(ANodes, mNode);
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

{ TAtlasIdeFindMethod }

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
  mLine, mCharacter, mCurrent: Integer;
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
  mCurrent := -1;
  if CaretOf(mView, mLine, mCharacter) then
  begin
    mCurrent := TAtlasBreadcrumbs.RoutineAt(mSnapshot.Nodes, mRoutines, mLine);
  end;
  mCommands := RoutineCommands(mSnapshot.Nodes, mRoutines);
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, mCommands, nil, TAtlasIdeStyle.Colors);
  mWindow.Prompt := Format(TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.FindMethodPrompt),
    [ExtractFileName(mSnapshot.FileName)]);
  // Ohne Eingabe in Quelltextreihenfolge, die innerste Routine am Caret vorgewählt.
  mWindow.KeepOrder := True;
  if mCurrent >= 0 then
  begin
    mWindow.InitialId := IntToStr(mCurrent);
  end;
  mWindow.OnExecuteShift := GoToRoutine(mSnapshot.FileName, mSnapshot.Nodes);
  mWindow.ShowOver(TAtlasIdeHost.PopupArea);
end;

end.
