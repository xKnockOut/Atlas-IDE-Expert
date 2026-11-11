unit Atlas.IDE.Designer.ButtonBar;

// Befehl „Knopfleiste anordnen“ (#732) im Menü „Anordnen“ in der IDE: die
// markierten Knöpfe (TButton und Nachfahren, Geschwister der ersten Auswahl)
// bekommen eine Rolle (TAtlasButtonBar), werden nach designer.buttonBar.order
// sortiert, gleich breit (Breite nach Text, #730) und gleich hoch (die
// häufigste Höhe) an den Rand des Elternelements gestellt (Innenrand samt
// Padding) und passend verankert. TabOrder fortlaufend nach den übrigen
// Steuerelementen.
// - Mit designer.buttonBar.setModalResult: Default beim ok-Knopf, Cancel beim
//   cancel-Knopf, solange kein anderer Knopf des Formulars sie hat (sonst ein
//   Hinweis); ModalResult mrOk bzw. mrCancel, wenn leer und der OnClick-Handler
//   ModalResult nicht selbst setzt oder Close aufruft (sonst ein Hinweis).
// - Die erkannten Rollen stehen in der Meldungsansicht.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.StdCtrls;

type
  TAtlasIdeButtonBar = class
  public
    /// <summary>Knöpfe unter ASelected (Geschwister des ersten).</summary>
    class function Candidates(const ASelected: TArray<TComponent>): TArray<TButton>; static;
    /// <summary>Befehl ausführen; Meldungen über AOnMessage.</summary>
    class procedure Execute(const AOnMessage: TProc<string>); static;
  end;

implementation

uses
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.ButtonBar,
  Atlas.Core.Localization.Language,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FitText,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Settings;

const
  cDefaultPpi = 96;

class function TAtlasIdeButtonBar.Candidates(const ASelected: TArray<TComponent>): TArray<TButton>;
var
  mComponent: TComponent;
  mParent: TWinControl;
begin
  Result := nil;
  mParent := nil;
  for mComponent in ASelected do
  begin
    if not (mComponent is TButton) or (TButton(mComponent).Parent = nil) then
    begin
      Continue;
    end;
    if mParent = nil then
    begin
      mParent := TButton(mComponent).Parent;
    end;
    if TButton(mComponent).Parent = mParent then
    begin
      Result := Result + [TButton(mComponent)];
    end;
  end;
end;

function AnchorsOf(APosition: TAtlasButtonBarPosition): TAnchors;
var
  mAnchors: TAtlasButtonAnchors;
begin
  mAnchors := TAtlasButtonBar.AnchorsOf(APosition);
  Result := [];
  if TAtlasButtonAnchor.Left in mAnchors then
  begin
    Include(Result, akLeft);
  end;
  if TAtlasButtonAnchor.Top in mAnchors then
  begin
    Include(Result, akTop);
  end;
  if TAtlasButtonAnchor.Right in mAnchors then
  begin
    Include(Result, akRight);
  end;
  if TAtlasButtonAnchor.Bottom in mAnchors then
  begin
    Include(Result, akBottom);
  end;
end;

/// <summary>Innenrand des Elternelements: Client ohne Padding.</summary>
function InnerRect(AParent: TWinControl): TRect;
begin
  Result := AParent.ClientRect;
  Inc(Result.Left, AParent.Padding.Left);
  Inc(Result.Top, AParent.Padding.Top);
  Dec(Result.Right, AParent.Padding.Right);
  Dec(Result.Bottom, AParent.Padding.Bottom);
end;

function PpiOf(ARoot: TComponent): Integer;
begin
  Result := cDefaultPpi;
  if (ARoot is TCustomForm) and (TCustomForm(ARoot).PixelsPerInch > 0) then
  begin
    Result := TCustomForm(ARoot).PixelsPerInch;
  end;
end;

/// <summary>Hat ein anderer Knopf des Formulars schon Default (ACancel = False) bzw. Cancel?</summary>
function OtherHas(ARoot: TComponent; AButton: TButton; ACancel: Boolean): string;
var
  mIndex: Integer;
  mOther: TButton;
begin
  Result := '';
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if not (ARoot.Components[mIndex] is TButton) or (ARoot.Components[mIndex] = AButton) then
    begin
      Continue;
    end;
    mOther := TButton(ARoot.Components[mIndex]);
    if (ACancel and mOther.Cancel) or (not ACancel and mOther.Default) then
    begin
      Exit(mOther.Name);
    end;
  end;
end;

type
  /// <summary>Ein Durchlauf: Formular, Designer, Quelltext der Unit und Meldungen.</summary>
  TBarRun = record
    Root: TComponent;
    Designer: IDesigner;
    Source: string;
    Say: TProc<string>;
    procedure Note(const AText: string);
    procedure Flag(AButton: TButton; ARole: TAtlasButtonRole);
    procedure SetModalResult(AButton: TButton; ARole: TAtlasButtonRole);
  end;

procedure TBarRun.Note(const AText: string);
begin
  if Assigned(Say) then
  begin
    Say(AText);
  end;
end;

procedure TBarRun.Flag(AButton: TButton; ARole: TAtlasButtonRole);
var
  mOther: string;
begin
  if not (ARole in [TAtlasButtonRole.Ok, TAtlasButtonRole.Cancel]) then
  begin
    Exit;
  end;
  mOther := OtherHas(Root, AButton, ARole = TAtlasButtonRole.Cancel);
  if (mOther <> '') and (ARole = TAtlasButtonRole.Ok) then
  begin
    Note(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerBarDefaultTaken, [AButton.Name, mOther]));
  end
  else if mOther <> '' then
  begin
    Note(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerBarCancelTaken, [AButton.Name, mOther]));
  end
  else if ARole = TAtlasButtonRole.Ok then
  begin
    AButton.Default := True;
  end
  else
  begin
    AButton.Cancel := True;
  end;
end;

procedure TBarRun.SetModalResult(AButton: TButton; ARole: TAtlasButtonRole);
var
  mMethod: string;
  mEvent: TNotifyEvent;
begin
  if not (ARole in [TAtlasButtonRole.Ok, TAtlasButtonRole.Cancel]) or (AButton.ModalResult <> mrNone) then
  begin
    Exit;
  end;
  mMethod := '';
  mEvent := AButton.OnClick;
  if Assigned(mEvent) then
  begin
    mMethod := Designer.GetMethodName(TMethod(mEvent));
  end;
  if TAtlasButtonBar.HandlerCloses(Source, mMethod) then
  begin
    Note(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerBarHandlerCloses, [AButton.Name, mMethod]));
  end
  else if ARole = TAtlasButtonRole.Ok then
  begin
    AButton.ModalResult := mrOk;
  end
  else
  begin
    AButton.ModalResult := mrCancel;
  end;
end;

/// <summary>Rollen der Knöpfe und ihre Zeile für die Meldung („btnOk: ok“).</summary>
function RolesOf(const AButtons: TArray<TButton>; const ATerms: string; out AText: string): TArray<TAtlasButtonRole>;
var
  mButton: TButton;
  mRole: TAtlasButtonRole;
begin
  Result := nil;
  AText := '';
  for mButton in AButtons do
  begin
    mRole := TAtlasButtonBar.RoleOf(mButton.Name, mButton.Caption, Ord(mButton.ModalResult), ATerms);
    Result := Result + [mRole];
    if AText <> '' then
    begin
      AText := AText + ', ';
    end;
    AText := AText + mButton.Name + ': ' + TAtlasButtonBar.RoleName(mRole);
  end;
end;

/// <summary>Lage, Anchors und TabOrder in der Reihenfolge AOrder.</summary>
procedure Place(const AButtons: TArray<TButton>; const AOrder: TArray<Integer>; ARoot: TComponent;
  const ASettings: TAtlasPluginSettings);
var
  mHeights: TArray<Integer>;
  mControls: TArray<TControl>;
  mButton: TButton;
  mRects: TArray<TRect>;
  mPosition: TAtlasButtonBarPosition;
  mPpi, mIndex: Integer;
begin
  mHeights := nil;
  mControls := nil;
  for mButton in AButtons do
  begin
    mHeights := mHeights + [mButton.Height];
    mControls := mControls + [TControl(mButton)];
  end;
  mPpi := PpiOf(ARoot);
  mPosition := TAtlasButtonBar.PositionOf(ASettings.DesignerButtonBarPosition);
  mRects := TAtlasButtonBar.Layout(Length(AButtons), TSize.Create(TAtlasIdeFitText.CommonWidth(mControls, ARoot),
    TAtlasButtonBar.CommonHeight(mHeights)), mPosition, InnerRect(AButtons[0].Parent),
    MulDiv(ASettings.DesignerButtonBarMargin, mPpi, cDefaultPpi), MulDiv(ASettings.DesignerButtonBarGap, mPpi,
    cDefaultPpi));
  for mIndex := 0 to High(AOrder) do
  begin
    mButton := AButtons[AOrder[mIndex]];
    mButton.Anchors := AnchorsOf(mPosition);
    mButton.BoundsRect := mRects[mIndex];
    // Ans Ende der Tab-Reihenfolge, in der neuen Folge.
    mButton.TabOrder := mButton.Parent.ControlCount;
  end;
end;

class procedure TAtlasIdeButtonBar.Execute(const AOnMessage: TProc<string>);
var
  mEditor: IOTAFormEditor;
  mRun: TBarRun;
  mButtons: TArray<TButton>;
  mRoles: TArray<TAtlasButtonRole>;
  mSettings: TAtlasPluginSettings;
  mText: string;
  mIndex: Integer;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not mSettings.DesignerButtonBar or not TAtlasDesignerAccess.Current(mEditor, mRun.Root) then
  begin
    Exit;
  end;
  mRun.Designer := TAtlasDesignerAccess.DesignerOf(mEditor);
  mButtons := Candidates(TAtlasDesignerAccess.Selection(mEditor, mRun.Root));
  if (mRun.Designer = nil) or (Length(mButtons) = 0) then
  begin
    AOnMessage(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNoButtons));
    Exit;
  end;
  mRun.Say := AOnMessage;
  mRoles := RolesOf(mButtons, mSettings.DesignerButtonBarRoles + ';' +
    TAtlasDesignerStrings.TextIn(TAtlasLanguage.German, TAtlasDesignerTextId.DesignerBarRoleTerms) + ';' +
    TAtlasDesignerStrings.TextIn(TAtlasLanguage.English, TAtlasDesignerTextId.DesignerBarRoleTerms), mText);
  Place(mButtons, TAtlasButtonBar.Order(mRoles, mSettings.DesignerButtonBarOrder), mRun.Root, mSettings);
  if mSettings.DesignerButtonBarSetModalResult then
  begin
    mRun.Source := TAtlasIdeWorkspaceEdit.CurrentText(ChangeFileExt(mEditor.FileName, '.pas'));
    for mIndex := 0 to High(mButtons) do
    begin
      mRun.Flag(mButtons[mIndex], mRoles[mIndex]);
      mRun.SetModalResult(mButtons[mIndex], mRoles[mIndex]);
    end;
  end;
  mRun.Designer.Modified;
  AOnMessage(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerBarArranged, [mText]));
end;

end.
