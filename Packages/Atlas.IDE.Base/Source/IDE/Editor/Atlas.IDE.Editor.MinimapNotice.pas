unit Atlas.IDE.Editor.MinimapNotice;

// Hinweis „Zwei Minimaps sichtbar“ der Minimap (#873): Ist neben der
// Atlas-Minimap ein sichtbares Steuerelement mit „Minimap“ im Klassennamen im
// Editorfenster, kommt einmal (gemerkt in MinimapNoticeShown) der Hinweis mit
// „IDE-Minimap ausblenden“ (für diese Sitzung) und „Atlas-Minimap aus“. Eine
// Schnittstelle zum Abfragen oder Abschalten bietet die Open Tools API nicht.
// Was die beiden Knöpfe tun, gibt die Minimap als Methodenreferenzen mit; sie
// prüfen selbst, ob die Minimap noch läuft (die Benachrichtigungszentrale
// hält sie länger). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Notifications.Notice;

type
  TAtlasIdeMinimapNotice = class
  private
    FNotice: TAtlasNoticeWindow;
    FHideIde: Boolean;
    FOnHideIde: TProc;
    FOnTurnOff: TProc;
    procedure Notify;
    procedure ShowWindow(const ATitle, AText: string);
  public
    /// <summary>AOnHideIde: IDE-Minimap ausblenden; AOnTurnOff: Atlas-Minimap ausschalten.</summary>
    constructor Create(const AOnHideIde, AOnTurnOff: TProc);
    destructor Destroy; override;
    /// <summary>Sichtbare Minimap der IDE im Formular von AParent (bis MaxSearchDepth tief) oder nil.</summary>
    class function IdeMinimap(AParent: TWinControl): TControl; static;
    /// <summary>Nach jedem Takt mit der Atlas-Minimap AMinimap: ausblenden, wenn gewünscht, sonst einmal den
    /// Hinweis zeigen.</summary>
    procedure Check(AMinimap: TControl);
    /// <summary>Für diese Sitzung die IDE-Minimap neben jeder Atlas-Minimap ausblenden.</summary>
    property HideIde: Boolean read FHideIde write FHideIde;
  end;

implementation

uses
  System.Types,
  Vcl.Forms,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Editor.Minimap,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.UI.Editor.Minimap,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  /// <summary>So tief sucht der Hinweis die Minimap der IDE im Editorfenster.</summary>
  cMaxSearchDepth = 6;

function FindIn(AControl: TWinControl; ADepth: Integer): TControl;
var
  mIndex: Integer;
  mChild: TControl;
begin
  Result := nil;
  if ADepth > cMaxSearchDepth then
  begin
    Exit;
  end;
  for mIndex := 0 to AControl.ControlCount - 1 do
  begin
    mChild := AControl.Controls[mIndex];
    if (mChild is TAtlasMinimapView) or not mChild.Visible then
    begin
      Continue;
    end;
    if Pos('MINIMAP', UpperCase(mChild.ClassName)) > 0 then
    begin
      Exit(mChild);
    end;
    if mChild is TWinControl then
    begin
      Result := FindIn(TWinControl(mChild), ADepth + 1);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
end;

{ TAtlasIdeMinimapNotice }

constructor TAtlasIdeMinimapNotice.Create(const AOnHideIde, AOnTurnOff: TProc);
begin
  inherited Create;
  FOnHideIde := AOnHideIde;
  FOnTurnOff := AOnTurnOff;
end;

destructor TAtlasIdeMinimapNotice.Destroy;
begin
  FreeAndNil(FNotice);
  FOnHideIde := nil;
  FOnTurnOff := nil;
  inherited Destroy;
end;

class function TAtlasIdeMinimapNotice.IdeMinimap(AParent: TWinControl): TControl;
var
  mForm: TCustomForm;
begin
  Result := nil;
  if AParent = nil then
  begin
    Exit;
  end;
  mForm := GetParentForm(AParent);
  if mForm <> nil then
  begin
    Result := FindIn(mForm, 0);
  end
  else
  begin
    Result := FindIn(AParent, 0);
  end;
end;

procedure TAtlasIdeMinimapNotice.Check(AMinimap: TControl);
var
  mIde: TControl;
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Stored;
  // Schon gezeigt und nichts auszublenden: den Fensterbaum nicht durchsuchen.
  if mSettings.MinimapNoticeShown and not FHideIde then
  begin
    Exit;
  end;
  mIde := IdeMinimap(AMinimap.Parent);
  if (mIde <> nil) and FHideIde then
  begin
    mIde.Visible := False;
    Exit;
  end;
  if TAtlasMinimap.ShouldNotice(AMinimap.Visible, mIde <> nil, mSettings.MinimapNoticeShown) then
  begin
    // Nur einmal: gleich merken, auch wenn der Hinweis nur gesammelt wird.
    mSettings.MinimapNoticeShown := True;
    TAtlasIdeSettings.Update(mSettings);
    Notify;
  end;
end;

procedure TAtlasIdeMinimapNotice.Notify;
var
  mActions: TArray<TAtlasNotificationAction>;
  mAction: TAtlasNotificationAction;
  mTitle, mText: string;
begin
  mTitle := TAtlasStrings.Text(TAtlasTextId.MinimapNoticeTitle);
  mText := TAtlasStrings.Text(TAtlasTextId.MinimapNoticeText);
  mAction.Caption := TAtlasStrings.Text(TAtlasTextId.MinimapHideIde);
  mAction.Run := FOnHideIde;
  mActions := [mAction];
  mAction.Caption := TAtlasStrings.Text(TAtlasTextId.MinimapTurnOff);
  mAction.Run := FOnTurnOff;
  mActions := mActions + [mAction];
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cMinimap, TAtlasNotificationSeverity.Info,
    mTitle, mText, mActions) = TAtlasNotificationMode.Show then
  begin
    ShowWindow(mTitle, mText);
  end;
end;

procedure TAtlasIdeMinimapNotice.ShowWindow(const ATitle, AText: string);
var
  mArea: TRect;
begin
  if FNotice = nil then
  begin
    FNotice := TAtlasNoticeWindow.Create(nil);
  end;
  FNotice.OnAction :=
    procedure(AIndex: Integer)
    begin
      if AIndex = 0 then
      begin
        FOnHideIde();
      end
      else if AIndex = 1 then
      begin
        FOnTurnOff();
      end;
    end;
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end;
  FNotice.Colors := TAtlasIdeStyle.Colors;
  FNotice.SetScaling(TAtlasPopupWindow.MonitorPPI(mArea.BottomRight), 1, '', 10);
  FNotice.ShowNotice(ATitle, AText, [TAtlasStrings.Text(TAtlasTextId.MinimapHideIde),
    TAtlasStrings.Text(TAtlasTextId.MinimapTurnOff)], mArea);
end;

end.
