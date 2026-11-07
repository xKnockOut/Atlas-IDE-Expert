unit Atlas.IDE.Editor.Hide;

// „Ausblenden“ direkt am Element (#628) in der IDE.
// - Rechtsklick auf ein überlagertes Element (Code Lens, Inlay-Hint,
//   Blockende-Beschriftung) öffnet statt des Kontextmenüs der IDE das Menü
//   zum Element (TAtlasIdeElements.OnOverlayMenu). Für Elemente im Text und in
//   der Rinne (Befund, Klammerfarben, Notiz …) bleibt das Kontextmenü der IDE;
//   dort steht im Atlas-Untermenü „Element ausblenden …“ für die Stelle des
//   Rechtsklicks. Strg+. (Einstellung HideElementKey) öffnet das Menü für die
//   Elemente der Zeile mit der Schreibmarke; ohne Element geht die Taste an
//   die IDE weiter (IDE Insight).
// - Ausführen (Plan aus Atlas.Core.Editor.Hide): Unterdrückungskommentar in den
//   Puffer (ein Rückgängig-Schritt der IDE), Eintrag "hidden" in .atlas
//   (angelegt mit Gerüst, wenn es noch keine gibt) oder die Einstellung aus
//   (gespeichert; ein Sitzungswert der Schnellschalter fällt dabei weg).
// - Danach „Ausgeblendet · Rückgängig“ (TAtlasHideNoticeWindow) unter dem
//   Element, über die Benachrichtigungszentrale (#601, Quelle "hidden"):
//   „nur sammeln“ zeigt nichts, die Meldung mit „Rückgängig“ steht in der
//   Liste. Rückgängig nimmt genau diesen Schritt zurück.
// - „Einstellungen dazu …“ ruft OnShowSetting (setzt die Komposition:
//   Tools › Optionen › Atlas mit markierter Zeile).
// - HideSetting und ShowSetting nehmen nur einen Schlüssel: So nutzen auch
//   Bereiche der Willkommensseite (#767) denselben Weg.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Hide,
  Atlas.Core.Settings.HiddenPlaces,
  Atlas.UI.Editor.Hide;

type
  TAtlasIdeHide = class
  private type
    /// <summary>Der letzte ausgeführte Schritt, für „Rückgängig“.</summary>
    TStep = record
      Valid: Boolean;
      Kind: TAtlasHideKind;
      Insert: TAtlasTextInsert;
      FileName: string;
      Place: TAtlasHiddenPlace;
      Key: string;
      OldValue: string;
      Changed: Boolean;
      HadSession: Boolean;
      SessionValue: Boolean;
    end;
  private class var
    FInstance: TAtlasIdeHide;
    FOnShowSetting: TProc<string>;
  private
    FMenu: TAtlasHideMenu;
    FNotice: TAtlasHideNoticeWindow;
    FStep: TStep;
    FWhere: TPoint;
    procedure Choose(AChoice: TAtlasHideChoice);
    procedure NoticeUndo(Sender: TObject);
    procedure Done(const AStep: TStep; const ADetail: string);
    procedure Refused(const AText: string);
    procedure Notice(const ATitle, ADetail: string; ACanUndo: Boolean);
    function Run(const AChoice: TAtlasHideChoice; out AStep: TStep; out ADetail: string): Boolean;
    function RunText(const APlan: TAtlasHidePlan; out AStep: TStep; out ADetail: string): Boolean;
    function RunTeamFile(const APlan: TAtlasHidePlan; out AStep: TStep; out ADetail: string): Boolean;
    function RunSetting(const AKey: string; out AStep: TStep; out ADetail: string): Boolean;
    function UndoStep(const AStep: TStep): Boolean;
    class function RefusalText(ARefusal: TAtlasHideRefusal): string; static;
    class function SettingCaption(const AKey: string): string; static;
    class function CaretPoint: TPoint; static;
    class procedure Applied; static;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Start; static;
    class procedure Stop; static;
    /// <summary>Menü zu ATargets an der Bildschirmstelle APoint.</summary>
    class procedure ShowMenu(const ATargets: TArray<TAtlasHideTarget>; const APoint: TPoint); static;
    /// <summary>Strg+.: Menü für die Elemente der Zeile mit der Schreibmarke; False ohne Element.</summary>
    class function ShowForCaret: Boolean; static;
    /// <summary>Befehl „Element ausblenden …“ (Palette, Atlas-Untermenü): Stelle des letzten Rechtsklicks, sonst
    /// die Zeile mit der Schreibmarke; ohne Element ein Hinweis.</summary>
    class procedure ShowForCommand; static;
    /// <summary>Einstellung AKey ausschalten mit „Ausgeblendet · Rückgängig“ an APoint (#767); False, wenn sie
    /// schon aus ist oder es sie nicht gibt.</summary>
    class function HideSetting(const AKey: string; const APoint: TPoint): Boolean; static;
    /// <summary>Optionsseite mit der Einstellung AKey (OnShowSetting).</summary>
    class procedure ShowSetting(const AKey: string); static;
    /// <summary>Letzten Schritt zurücknehmen.</summary>
    class procedure Undo; static;
    class property OnShowSetting: TProc<string> read FOnShowSetting write FOnShowSetting;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Editor.HideTeamFile;

{ TAtlasIdeHide }

constructor TAtlasIdeHide.Create;
begin
  inherited Create;
  FMenu := TAtlasHideMenu.Create(nil);
  FMenu.OnChoose :=
    procedure(AChoice: TAtlasHideChoice)
    begin
      // Erst nach dem Schließen des Menüs: Ein Dialog oder das Schreiben in den Puffer soll nicht im Menü laufen.
      TAtlasMainThread.ForceQueue(TAtlasFeature.Hide,
        procedure
        begin
          if FInstance <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.Hide,
              procedure
              begin
                FInstance.Choose(AChoice);
              end);
          end;
        end);
    end;
end;

destructor TAtlasIdeHide.Destroy;
begin
  FNotice.Free;
  FMenu.Free;
  inherited Destroy;
end;

class procedure TAtlasIdeHide.Start;
begin
  if FInstance <> nil then
  begin
    Exit;
  end;
  FInstance := TAtlasIdeHide.Create;
  TAtlasIdeElements.OnOverlayMenu :=
    procedure(const ATargets: TArray<TAtlasHideTarget>; const AScreen: TPoint)
    begin
      TAtlasGuard.Run(TAtlasFeature.Hide,
        procedure
        begin
          ShowMenu(ATargets, AScreen);
        end);
    end;
end;

class procedure TAtlasIdeHide.Stop;
begin
  TAtlasIdeElements.OnOverlayMenu := nil;
  FreeAndNil(FInstance);
end;

class procedure TAtlasIdeHide.ShowMenu(const ATargets: TArray<TAtlasHideTarget>; const APoint: TPoint);
begin
  if (FInstance = nil) or (Length(ATargets) = 0) then
  begin
    Exit;
  end;
  FInstance.FWhere := APoint;
  FInstance.FMenu.Build(ATargets);
  FInstance.FMenu.Popup(APoint);
end;

class function TAtlasIdeHide.CaretPoint: TPoint;
var
  mFocus: HWND;
begin
  Result := Mouse.CursorPos;
  mFocus := GetFocus;
  if (mFocus <> 0) and GetCaretPos(Result) then
  begin
    // Unter die Zeile der Schreibmarke, nicht in sie hinein.
    Inc(Result.Y, 16);
    Winapi.Windows.ClientToScreen(mFocus, Result);
  end;
end;

/// <summary>Oberer Editor; nil ohne.</summary>
function TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
  if (Result <> nil) and (Result.Buffer = nil) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeHide.ShowForCaret: Boolean;
var
  mView: IOTAEditView;
  mTargets: TArray<TAtlasHideTarget>;
begin
  Result := False;
  mView := TopView;
  if (FInstance = nil) or (mView = nil) then
  begin
    Exit;
  end;
  mTargets := TAtlasIdeElements.OnLine(mView.Buffer.FileName, mView.CursorPos.Line - 1);
  if Length(mTargets) = 0 then
  begin
    Exit;
  end;
  ShowMenu(mTargets, CaretPoint);
  Result := True;
end;

class procedure TAtlasIdeHide.ShowForCommand;
var
  mView: IOTAEditView;
  mTargets: TArray<TAtlasHideTarget>;
begin
  mView := TopView;
  if (FInstance = nil) or (mView = nil) then
  begin
    Exit;
  end;
  if TAtlasIdeElements.TakeClick(mView.Buffer.FileName, mTargets) then
  begin
    ShowMenu(mTargets, Mouse.CursorPos);
    Exit;
  end;
  if ShowForCaret then
  begin
    Exit;
  end;
  FInstance.FWhere := CaretPoint;
  FInstance.Refused(TAtlasStrings.Text(TAtlasTextId.HideNoElement));
end;

class procedure TAtlasIdeHide.ShowSetting(const AKey: string);
begin
  if Assigned(FOnShowSetting) then
  begin
    FOnShowSetting(AKey);
  end;
end;

class function TAtlasIdeHide.HideSetting(const AKey: string; const APoint: TPoint): Boolean;
var
  mStep: TStep;
  mDetail: string;
begin
  Result := False;
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.FWhere := APoint;
  Result := FInstance.RunSetting(AKey, mStep, mDetail);
  if Result then
  begin
    FInstance.Done(mStep, mDetail);
  end
  else
  begin
    FInstance.Refused(mDetail);
  end;
end;

class procedure TAtlasIdeHide.Undo;
begin
  if FInstance <> nil then
  begin
    FInstance.NoticeUndo(nil);
  end;
end;

class function TAtlasIdeHide.RefusalText(ARefusal: TAtlasHideRefusal): string;
begin
  case ARefusal of
    TAtlasHideRefusal.NoProjectFolder:
      Result := TAtlasStrings.Text(TAtlasTextId.HideRefusedNoProject);
    TAtlasHideRefusal.OutsideProject:
      Result := TAtlasStrings.Text(TAtlasTextId.HideRefusedOutside);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.HideRefusedAlready);
  end;
end;

class function TAtlasIdeHide.SettingCaption(const AKey: string): string;
var
  mToggle: TAtlasQuickToggle;
begin
  if TAtlasQuickToggles.Find(TAtlasIdeSettings.QuickToggles, AKey, mToggle) and (mToggle.Caption <> '') then
  begin
    Result := mToggle.Caption;
  end
  else
  begin
    Result := AKey;
  end;
end;

class procedure TAtlasIdeHide.Applied;
begin
  // Wie die Schnellschalter: Strukturhervorhebung der IDE abgleichen, Treffer vergessen, neu zeichnen.
  TAtlasIdeStructureSwitch.Sync;
  TAtlasIdeElements.Reset;
end;

procedure TAtlasIdeHide.Choose(AChoice: TAtlasHideChoice);
var
  mStep: TStep;
  mDetail: string;
begin
  if AChoice.Settings then
  begin
    ShowSetting(AChoice.Target.SettingKey);
    Exit;
  end;
  if Run(AChoice, mStep, mDetail) then
  begin
    Done(mStep, mDetail);
  end
  else
  begin
    Refused(mDetail);
  end;
end;

function TAtlasIdeHide.Run(const AChoice: TAtlasHideChoice; out AStep: TStep; out ADetail: string): Boolean;
var
  mPlan: TAtlasHidePlan;
  mRefusal: TAtlasHideRefusal;
  mText, mFolder, mTeamFile: string;
  mView: IOTAEditView;
begin
  AStep := Default(TStep);
  ADetail := '';
  mText := '';
  mView := TopView;
  if (mView <> nil) and AnsiSameText(mView.Buffer.FileName, AChoice.Target.FileName) then
  begin
    mText := TAtlasEditorBuffer.Text(mView.Buffer);
  end;
  mFolder := TAtlasIdeHideTeamFile.Folder(mTeamFile);
  Result := TAtlasHide.Plan(AChoice.Target, AChoice.Scope, mText, mFolder, mPlan, mRefusal);
  if not Result then
  begin
    ADetail := RefusalText(mRefusal);
    Exit;
  end;
  case mPlan.Kind of
    TAtlasHideKind.LineComment, TAtlasHideKind.FileComment:
      Result := RunText(mPlan, AStep, ADetail);
    TAtlasHideKind.TeamFile:
      Result := RunTeamFile(mPlan, AStep, ADetail);
  else
    Result := RunSetting(mPlan.SettingKey, AStep, ADetail);
  end;
end;

/// <summary>Ersetzt in ABuffer (Text AText) die Zeichen AFrom bis ATill (0-basiert, ATill ausschließlich) durch
/// ANew; ein Rückgängig-Schritt der IDE.</summary>
procedure WriteRange(const ABuffer: IOTAEditBuffer; const AText: string; AFrom, ATill: Integer; const ANew: string);
var
  mWriter: IOTAEditWriter;
begin
  mWriter := ABuffer.CreateUndoableWriter;
  mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AFrom)));
  if ATill > AFrom then
  begin
    mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, ATill)));
  end;
  if ANew <> '' then
  begin
    mWriter.Insert(PAnsiChar(UTF8Encode(ANew)));
  end;
  mWriter := nil;
  // Eigener Schreibvorgang: Probleme und Inlay-Hints lesen den Puffer neu (P-04).
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function TAtlasIdeHide.RunText(const APlan: TAtlasHidePlan; out AStep: TStep; out ADetail: string): Boolean;
var
  mView: IOTAEditView;
  mText, mChanged: string;
  mLines: TArray<string>;
  mOffset: Integer;
begin
  AStep := Default(TStep);
  Result := False;
  mView := TopView;
  if (mView = nil) or not AnsiSameText(mView.Buffer.FileName, APlan.Target.FileName) or mView.Buffer.IsReadOnly then
  begin
    ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideFailed, [ExtractFileName(APlan.Target.FileName)]);
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mOffset := APlan.Insert.OffsetIn(mText);
  WriteRange(mView.Buffer, mText, mOffset, mOffset, APlan.Insert.Text);
  AStep.Valid := True;
  AStep.Kind := APlan.Kind;
  AStep.Insert := APlan.Insert;
  AStep.FileName := APlan.Target.FileName;
  // Zeige die Kommentarzeile, wie sie jetzt dasteht.
  mChanged := APlan.Insert.ApplyTo(mText);
  mLines := TTextLines.SplitLines(mChanged);
  ADetail := '';
  if (APlan.Insert.Line >= 0) and (APlan.Insert.Line <= High(mLines)) then
  begin
    ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideDoneLineComment, [Trim(mLines[APlan.Insert.Line])]);
  end;
  Result := True;
end;

function TAtlasIdeHide.RunTeamFile(const APlan: TAtlasHidePlan; out AStep: TStep; out ADetail: string): Boolean;
var
  mFileName: string;
begin
  AStep := Default(TStep);
  Result := TAtlasIdeHideTeamFile.Add(APlan.Place, mFileName, ADetail);
  if not Result then
  begin
    Exit;
  end;
  Applied;
  AStep.Valid := True;
  AStep.Kind := TAtlasHideKind.TeamFile;
  AStep.FileName := mFileName;
  AStep.Place := APlan.Place;
  ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideDoneTeamFile,
    [TAtlasHideMenu.ElementName(APlan.Target.Element, False), APlan.Place.FileName]);
end;

function TAtlasIdeHide.RunSetting(const AKey: string; out AStep: TStep; out ADetail: string): Boolean;
var
  mStored: TAtlasPluginSettings;
  mSession: TAtlasToggleSession;
  mValue: Boolean;
begin
  mValue := False;
  AStep := Default(TStep);
  AStep.Kind := TAtlasHideKind.Setting;
  AStep.Key := AKey;
  mStored := TAtlasIdeSettings.Stored;
  mSession := TAtlasIdeSettings.Session;
  AStep.HadSession := mSession.TryGet(AKey, mValue) and mValue;
  AStep.SessionValue := mValue;
  AStep.Changed := TAtlasHide.SwitchOff(mStored, AKey, AStep.OldValue);
  if not AStep.Changed and not AStep.HadSession then
  begin
    ADetail := TAtlasStrings.Text(TAtlasTextId.HideRefusedAlready);
    Exit(False);
  end;
  if AStep.Changed then
  begin
    TAtlasIdeSettings.Update(mStored);
  end;
  // Ein Schnellschalter „an für diese Sitzung“ hielte das Element sonst sichtbar.
  if AStep.HadSession then
  begin
    mSession.Drop(AKey);
    TAtlasIdeSettings.SetSession(mSession);
  end;
  Applied;
  AStep.Valid := True;
  ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideDoneSetting, [SettingCaption(AKey)]);
  Result := True;
end;

function TAtlasIdeHide.UndoStep(const AStep: TStep): Boolean;
var
  mView: IOTAEditView;
  mText, mReverted: string;
  mOffset: Integer;
  mStored: TAtlasPluginSettings;
  mSession: TAtlasToggleSession;
begin
  Result := False;
  case AStep.Kind of
    TAtlasHideKind.LineComment, TAtlasHideKind.FileComment:
      begin
        mView := TopView;
        if (mView = nil) or not AnsiSameText(mView.Buffer.FileName, AStep.FileName) then
        begin
          Exit;
        end;
        mText := TAtlasEditorBuffer.Text(mView.Buffer);
        if not AStep.Insert.RevertIn(mText, mReverted) then
        begin
          Exit;
        end;
        mOffset := AStep.Insert.OffsetIn(mText);
        WriteRange(mView.Buffer, mText, mOffset, mOffset + Length(AStep.Insert.Text), '');
      end;
    TAtlasHideKind.TeamFile:
      begin
        if not TAtlasIdeHideTeamFile.Remove(AStep.FileName, AStep.Place) then
        begin
          Exit;
        end;
      end;
  else
    begin
      if AStep.Changed then
      begin
        mStored := TAtlasIdeSettings.Stored;
        TAtlasHide.Restore(mStored, AStep.Key, AStep.OldValue);
        TAtlasIdeSettings.Update(mStored);
      end;
      if AStep.HadSession then
      begin
        mSession := TAtlasIdeSettings.Session;
        mSession.Put(AStep.Key, AStep.SessionValue);
        TAtlasIdeSettings.SetSession(mSession);
      end;
    end;
  end;
  Applied;
  Result := True;
end;

procedure TAtlasIdeHide.NoticeUndo(Sender: TObject);
var
  mStep: TStep;
begin
  mStep := FStep;
  FStep := Default(TStep);
  if not mStep.Valid then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Hide,
    procedure
    var
      Ok: Boolean;
    begin
      try
        Ok := UndoStep(mStep);
      except
        on E: Exception do
        begin
          TAtlasGuard.Log('Ausblenden: Rückgängig fehlgeschlagen (' + E.ClassName + ')');
          Ok := False;
        end;
      end;
      if Ok then
      begin
        Notice('', TAtlasStrings.Text(TAtlasTextId.HideUndone), False);
      end
      else
      begin
        Notice('', TAtlasStrings.Text(TAtlasTextId.HideUndoFailed), False);
      end;
    end);
end;

procedure TAtlasIdeHide.Notice(const ATitle, ADetail: string; ACanUndo: Boolean);
var
  mFontName: string;
  mFontSize: Integer;
  mEditors: IOTAEditorServices;
begin
  if FNotice = nil then
  begin
    FNotice := TAtlasHideNoticeWindow.Create(nil);
    FNotice.OnUndo := NoticeUndo;
  end;
  mFontName := FNotice.Font.Name;
  mFontSize := 10;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) and (mEditors.EditOptions <> nil) then
  begin
    mFontName := mEditors.EditOptions.FontName;
    mFontSize := mEditors.EditOptions.FontSize;
  end;
  FNotice.Colors := TAtlasIdeStyle.Colors;
  FNotice.SetScaling(TAtlasPopupWindow.MonitorPPI(FWhere), 1, mFontName, mFontSize);
  FNotice.ShowNotice(ATitle, ADetail, ACanUndo, FWhere);
end;

procedure TAtlasIdeHide.Done(const AStep: TStep; const ADetail: string);
var
  mMode: TAtlasNotificationMode;
  mAction: TAtlasNotificationAction;
begin
  FStep := AStep;
  mAction.Caption := TAtlasStrings.Text(TAtlasTextId.HideUndo);
  mAction.Run :=
    procedure
    begin
      TAtlasIdeHide.Undo;
    end;
  // Anonym: kein Dateiname, kein Quelltext.
  TAtlasGuard.Log('Element ausgeblendet (#628)');
  mMode := TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cHidden, TAtlasNotificationSeverity.Info,
    TAtlasStrings.Text(TAtlasTextId.HideNotice), ADetail, [mAction]);
  if mMode = TAtlasNotificationMode.Show then
  begin
    Notice(TAtlasStrings.Text(TAtlasTextId.HideNotice), ADetail, True);
  end;
end;

procedure TAtlasIdeHide.Refused(const AText: string);
begin
  if AText = '' then
  begin
    Exit;
  end;
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cHidden, TAtlasNotificationSeverity.Info,
    TAtlasStrings.Text(TAtlasTextId.HideElementCommand), AText) = TAtlasNotificationMode.Show then
  begin
    Notice('', AText, False);
  end;
end;

end.
