unit Atlas.IDE.Designer.ShowComponent;

// „Im Designer zeigen“ (#511) in der IDE: vom Code-Editor zur Komponente im
// Formular-Designer, die Umkehrung des Doppelklicks.
// - Auslöser: Cursor auf einem Formularfeld (btnOk), einer Feldnutzung
//   (btnOk.Caption, frmMain.btnOk) oder in bzw. auf einem Handler, der im
//   Formular zugewiesen ist (TAtlasDesignerLink).
// - Wechselt auf das Register „Design“, aktiviert die Registerseiten der
//   TPageControls auf dem Weg zur Komponente und wählt sie aus; der
//   Objektinspektor zeigt sie. Ein Handler mehrerer Komponenten bietet sie
//   in einem Menü am Cursor zur Auswahl an.
// - Geerbte Komponenten stehen im Formular selbst; in einem Frame zeigt der
//   Befehl in der Unit des Frames dessen Designer. Reveal und FindComponent
//   nutzt auch die Komponentensuche (#539).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Designer.CodeLink;

type
  TAtlasIdeShowComponent = class
  private class var
    FMenu: TComponent;
    FOnMessage: TProc<string>;
    class procedure Say(const AText: string); static;
    class procedure PickTarget(const AEditor: IOTAFormEditor; const ATargets: TArray<TAtlasDesignerTarget>); static;
  public
    /// <summary>Komponente unter dem Cursor des aktiven Code-Editors im Designer zeigen.</summary>
    class procedure Run; static;
    /// <summary>AComponent im Designer von AEditor zeigen und als einzige auswählen.</summary>
    class function Show(const AEditor: IOTAFormEditor; AComponent: TComponent): Boolean; static;
    /// <summary>Registerseiten auf dem Weg zu AComponent aktivieren; True, wenn sich eine geändert hat.</summary>
    class function Reveal(AComponent: TComponent): Boolean; static;
    /// <summary>Komponente AName im Formular ARoot, auch in eingebetteten Frames; nil ohne.</summary>
    class function FindComponent(ARoot: TComponent; const AName: string): TComponent; static;
    /// <summary>Meldungen gehen an AOnMessage (Meldungsansicht).</summary>
    class procedure Install(const AOnMessage: TProc<string>); static;
    class procedure Uninstall; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.Menus,
  DesignIntf,
  Atlas.Core.Designer.Components,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.SearchItems,
  Atlas.IDE.Foundation.DesignerView,
  Atlas.IDE.Foundation.EditorBuffer;

type
  /// <summary>Menüeintrag mit seinem Ziel.</summary>
  TTargetItem = class(TMenuItem)
  private
    FEditor: IOTAFormEditor;
    FTarget: TAtlasDesignerTarget;
  public
    procedure Click; override;
  end;

procedure TTargetItem.Click;
var
  mEditor: IOTAFormEditor;
  mName: string;
begin
  inherited Click;
  mEditor := FEditor;
  mName := FTarget.Component;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    var
      mRoot: TComponent;
    begin
      mRoot := TAtlasIdeDesignerView.RootOf(mEditor);
      if mRoot <> nil then
      begin
        TAtlasIdeShowComponent.Show(mEditor, TAtlasIdeShowComponent.FindComponent(mRoot, mName));
      end;
    end);
end;

/// <summary>Komponenten des Formulars samt Formular selbst (für dessen Ereignisse).</summary>
function ItemsWithRoot(ARoot: TComponent; const ADesigner: IDesigner): TArray<TAtlasDesignerItem>;
begin
  // Das Formular als eigener Eintrag: ItemsOf liefert nur, was ihm gehört.
  Result := [TAtlasDesignerSearchItems.RootItem(ARoot, ADesigner)] +
    TAtlasDesignerSearchItems.ItemsOf(ARoot, ADesigner);
end;

const
  /// <summary>Abstand unter der Oberkante der Schreibmarke: unter die Zeile, nicht in sie hinein.</summary>
  cBelowCaret = 18;

/// <summary>Bildschirmpunkt unter dem Cursor des Editors (Caret), sonst die Maus.</summary>
function CaretPoint: TPoint;
var
  mFocus: HWND;
begin
  mFocus := GetFocus;
  if (mFocus <> 0) and GetCaretPos(Result) then
  begin
    Winapi.Windows.ClientToScreen(mFocus, Result);
    Inc(Result.Y, cBelowCaret);
  end
  else
  begin
    GetCursorPos(Result);
  end;
end;

{ TAtlasIdeShowComponent }

class procedure TAtlasIdeShowComponent.Install(const AOnMessage: TProc<string>);
begin
  FOnMessage := AOnMessage;
end;

class procedure TAtlasIdeShowComponent.Uninstall;
begin
  FreeAndNil(FMenu);
  FOnMessage := nil;
end;

class procedure TAtlasIdeShowComponent.Say(const AText: string);
begin
  TAtlasGuard.Log('Im Designer zeigen: ' + AText);
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

class function TAtlasIdeShowComponent.FindComponent(ARoot: TComponent; const AName: string): TComponent;
var
  mIndex: Integer;
  mChild: TComponent;
begin
  Result := nil;
  if (ARoot = nil) or (AName = '') then
  begin
    Exit;
  end;
  if SameText(ARoot.Name, AName) then
  begin
    Exit(ARoot);
  end;
  Result := ARoot.FindComponent(AName);
  if Result <> nil then
  begin
    Exit;
  end;
  // Eingebettete Frames besitzen ihre Komponenten selbst.
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mChild := ARoot.Components[mIndex];
    if csInline in mChild.ComponentState then
    begin
      Result := FindComponent(mChild, AName);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
end;

class function TAtlasIdeShowComponent.Reveal(AComponent: TComponent): Boolean;
var
  mControl: TControl;
  mSheet: TTabSheet;
begin
  Result := False;
  if not (AComponent is TControl) then
  begin
    Exit;
  end;
  mControl := TControl(AComponent);
  while mControl <> nil do
  begin
    if mControl is TTabSheet then
    begin
      mSheet := TTabSheet(mControl);
      if (mSheet.PageControl <> nil) and (mSheet.PageControl.ActivePage <> mSheet) then
      begin
        mSheet.PageControl.ActivePage := mSheet;
        Result := True;
      end;
    end;
    mControl := mControl.Parent;
  end;
end;

class function TAtlasIdeShowComponent.Show(const AEditor: IOTAFormEditor; AComponent: TComponent): Boolean;
var
  mDesigner: IDesigner;
  mRoot: TComponent;
begin
  Result := False;
  if (AEditor = nil) or (AComponent = nil) then
  begin
    Exit;
  end;
  // Register „Design“; der Designer entsteht erst dabei.
  AEditor.Show;
  mDesigner := TAtlasDesignerAccess.DesignerOf(AEditor);
  mRoot := TAtlasIdeDesignerView.RootOf(AEditor);
  if (mDesigner = nil) or (mRoot = nil) then
  begin
    Exit;
  end;
  if Reveal(AComponent) then
  begin
    mDesigner.Modified;
  end;
  mDesigner.SelectComponent(AComponent);
  Result := True;
end;

class procedure TAtlasIdeShowComponent.PickTarget(const AEditor: IOTAFormEditor;
  const ATargets: TArray<TAtlasDesignerTarget>);
var
  mMenu: TPopupMenu;
  mItem: TTargetItem;
  mTarget: TAtlasDesignerTarget;
  mPoint: TPoint;
begin
  FreeAndNil(FMenu);
  mMenu := TPopupMenu.Create(nil);
  FMenu := mMenu;
  for mTarget in ATargets do
  begin
    mItem := TTargetItem.Create(mMenu);
    mItem.Caption := mTarget.Text;
    mItem.FEditor := AEditor;
    mItem.FTarget := mTarget;
    mMenu.Items.Add(mItem);
  end;
  mPoint := CaretPoint;
  mMenu.Popup(mPoint.X, mPoint.Y);
end;

class procedure TAtlasIdeShowComponent.Run;
var
  mView: IOTAEditView;
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mLines: TArray<string>;
  mLine: Integer;
  mTargets: TArray<TAtlasDesignerTarget>;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mEditor := TAtlasDesignerAccess.FormEditorOf(mView.Buffer.FileName);
  mRoot := TAtlasIdeDesignerView.RootOf(mEditor);
  if mRoot = nil then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerShowNoForm));
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mLines := TAtlasEditorBuffer.Text(mView.Buffer).Split([#13#10, #10]);
  mLine := mView.CursorPos.Line - 1;
  if (mLine < 0) or (mLine > High(mLines)) then
  begin
    Exit;
  end;
  mTargets := TAtlasDesignerLink.Targets(ItemsWithRoot(mRoot, mDesigner),
    TAtlasDesignerLink.ChainAt(mLines[mLine], mView.CursorPos.Col - 1), TAtlasDesignerLink.MethodAt(mLines, mLine));
  case Length(mTargets) of
    0:
      Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerShowNothing));
    1:
      Show(mEditor, FindComponent(mRoot, mTargets[0].Component));
  else
    PickTarget(mEditor, mTargets);
  end;
end;

end.
