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
    class function TeamFolder(out AFileName: string): string; static;
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
  System.IOUtils,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Files.Contract,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.StructureSwitch;

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
            TAtlasGuard.Run(TAtlasFeature.Hide,
              procedure
              begin
                FInstance.Choose(AChoice);
              end);
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
    Exit;
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
    Exit;
  FInstance.FWhere := APoint;
  FInstance.FMenu.Build(ATargets);
  FInstance.FMenu.Popup(APoint);
end;

class function TAtlasIdeHide.CaretPoint: TPoint;
var
  Focus: HWND;
begin
  Result := Mouse.CursorPos;
  Focus := GetFocus;
  if (Focus <> 0) and GetCaretPos(Result) then
  begin
    // Unter die Zeile der Schreibmarke, nicht in sie hinein.
    Inc(Result.Y, 16);
    Winapi.Windows.ClientToScreen(Focus, Result);
  end;
end;

/// <summary>Oberer Editor; nil ohne.</summary>
function TopView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Result := Editors.TopView;
  if (Result <> nil) and (Result.Buffer = nil) then
    Result := nil;
end;

class function TAtlasIdeHide.ShowForCaret: Boolean;
var
  View: IOTAEditView;
  Targets: TArray<TAtlasHideTarget>;
begin
  Result := False;
  View := TopView;
  if (FInstance = nil) or (View = nil) then
    Exit;
  Targets := TAtlasIdeElements.OnLine(View.Buffer.FileName, View.CursorPos.Line - 1);
  if Length(Targets) = 0 then
    Exit;
  ShowMenu(Targets, CaretPoint);
  Result := True;
end;

class procedure TAtlasIdeHide.ShowForCommand;
var
  View: IOTAEditView;
  Targets: TArray<TAtlasHideTarget>;
begin
  View := TopView;
  if (FInstance = nil) or (View = nil) then
    Exit;
  if TAtlasIdeElements.TakeClick(View.Buffer.FileName, Targets) then
  begin
    ShowMenu(Targets, Mouse.CursorPos);
    Exit;
  end;
  if ShowForCaret then
    Exit;
  FInstance.FWhere := CaretPoint;
  FInstance.Refused(TAtlasStrings.Text(TAtlasTextId.HideNoElement));
end;

class procedure TAtlasIdeHide.ShowSetting(const AKey: string);
begin
  if Assigned(FOnShowSetting) then
    FOnShowSetting(AKey);
end;

class function TAtlasIdeHide.HideSetting(const AKey: string; const APoint: TPoint): Boolean;
var
  Step: TStep;
  Detail: string;
begin
  Result := False;
  if FInstance = nil then
    Exit;
  FInstance.FWhere := APoint;
  Result := FInstance.RunSetting(AKey, Step, Detail);
  if Result then
    FInstance.Done(Step, Detail)
  else
    FInstance.Refused(Detail);
end;

class procedure TAtlasIdeHide.Undo;
begin
  if FInstance <> nil then
    FInstance.NoticeUndo(nil);
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
  Toggle: TAtlasQuickToggle;
begin
  if TAtlasQuickToggles.Find(TAtlasIdeSettings.QuickToggles, AKey, Toggle) and (Toggle.Caption <> '') then
    Result := Toggle.Caption
  else
    Result := AKey;
end;

class function TAtlasIdeHide.TeamFolder(out AFileName: string): string;
var
  Team: TAtlasTeamSettings;
  Project: string;
begin
  // Vorhandene .atlas des aktiven Projekts, sonst neben der .dproj (wie „Projektdatei öffnen“).
  Team := TAtlasIdeTeamFile.Current;
  if Team.FileName <> '' then
  begin
    AFileName := Team.FileName;
    Exit(Team.Folder);
  end;
  Project := TAtlasIdeTeamFile.ActiveProject;
  if Project = '' then
  begin
    AFileName := '';
    Exit('');
  end;
  Result := ExtractFileDir(Project);
  AFileName := TPath.Combine(Result, TAtlasTeamFile.FileName);
end;

class procedure TAtlasIdeHide.Applied;
begin
  // Wie die Schnellschalter: Strukturhervorhebung der IDE abgleichen, Treffer vergessen, neu zeichnen.
  TAtlasIdeStructureSwitch.Sync;
  TAtlasIdeElements.Reset;
end;

procedure TAtlasIdeHide.Choose(AChoice: TAtlasHideChoice);
var
  Step: TStep;
  Detail: string;
begin
  if AChoice.Settings then
  begin
    ShowSetting(AChoice.Target.SettingKey);
    Exit;
  end;
  if Run(AChoice, Step, Detail) then
    Done(Step, Detail)
  else
    Refused(Detail);
end;

function TAtlasIdeHide.Run(const AChoice: TAtlasHideChoice; out AStep: TStep; out ADetail: string): Boolean;
var
  Plan: TAtlasHidePlan;
  Refusal: TAtlasHideRefusal;
  Text, Folder, TeamFile: string;
  View: IOTAEditView;
begin
  AStep := Default(TStep);
  ADetail := '';
  Text := '';
  View := TopView;
  if (View <> nil) and AnsiSameText(View.Buffer.FileName, AChoice.Target.FileName) then
    Text := TAtlasEditorBuffer.Text(View.Buffer);
  Folder := TeamFolder(TeamFile);
  Result := TAtlasHide.Plan(AChoice.Target, AChoice.Scope, Text, Folder, Plan, Refusal);
  if not Result then
  begin
    ADetail := RefusalText(Refusal);
    Exit;
  end;
  case Plan.Kind of
    TAtlasHideKind.LineComment, TAtlasHideKind.FileComment:
      Result := RunText(Plan, AStep, ADetail);
    TAtlasHideKind.TeamFile:
      Result := RunTeamFile(Plan, AStep, ADetail);
  else
    Result := RunSetting(Plan.SettingKey, AStep, ADetail);
  end;
end;

/// <summary>Ersetzt in ABuffer (Text AText) die Zeichen AFrom bis ATill (0-basiert, ATill ausschließlich) durch
/// ANew; ein Rückgängig-Schritt der IDE.</summary>
procedure WriteRange(const ABuffer: IOTAEditBuffer; const AText: string; AFrom, ATill: Integer; const ANew: string);
var
  Writer: IOTAEditWriter;
begin
  Writer := ABuffer.CreateUndoableWriter;
  Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AFrom)));
  if ATill > AFrom then
    Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, ATill)));
  if ANew <> '' then
    Writer.Insert(PAnsiChar(UTF8Encode(ANew)));
  Writer := nil;
  // Eigener Schreibvorgang: Probleme und Inlay-Hints lesen den Puffer neu (P-04).
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function TAtlasIdeHide.RunText(const APlan: TAtlasHidePlan; out AStep: TStep; out ADetail: string): Boolean;
var
  View: IOTAEditView;
  Text, Changed: string;
  Lines: TArray<string>;
  Offset: Integer;
begin
  AStep := Default(TStep);
  Result := False;
  View := TopView;
  if (View = nil) or not AnsiSameText(View.Buffer.FileName, APlan.Target.FileName) or View.Buffer.IsReadOnly then
  begin
    ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideFailed, [ExtractFileName(APlan.Target.FileName)]);
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Offset := APlan.Insert.OffsetIn(Text);
  WriteRange(View.Buffer, Text, Offset, Offset, APlan.Insert.Text);
  AStep.Valid := True;
  AStep.Kind := APlan.Kind;
  AStep.Insert := APlan.Insert;
  AStep.FileName := APlan.Target.FileName;
  // Zeige die Kommentarzeile, wie sie jetzt dasteht.
  Changed := APlan.Insert.ApplyTo(Text);
  Lines := TTextLines.SplitLines(Changed);
  ADetail := '';
  if (APlan.Insert.Line >= 0) and (APlan.Insert.Line <= High(Lines)) then
    ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideDoneLineComment, [Trim(Lines[APlan.Insert.Line])]);
  Result := True;
end;

function TAtlasIdeHide.RunTeamFile(const APlan: TAtlasHidePlan; out AStep: TStep; out ADetail: string): Boolean;
var
  FileName, Updated: string;
  Content: TAtlasTextFileContent;
begin
  AStep := Default(TStep);
  Result := False;
  if not (TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.TeamFile) then
  begin
    ADetail := TAtlasStrings.Text(TAtlasTextId.HideRefusedTeamFileOff);
    Exit;
  end;
  TeamFolder(FileName);
  if FileName = '' then
  begin
    ADetail := TAtlasStrings.Text(TAtlasTextId.HideRefusedNoProject);
    Exit;
  end;
  try
    if FileExists(FileName) then
      Content := TAtlasTextFile.Load(FileName)
    else
    begin
      // Neue Datei wie „Projektdatei öffnen“: UTF-8 ohne BOM.
      Content := Default(TAtlasTextFileContent);
      Content.Encoding := TAtlasTextEncoding.Utf8;
    end;
    Updated := TAtlasHiddenPlaces.AddTo(Content.Text, TAtlasTeamFile.Skeleton, APlan.Place);
    if Updated = Content.Text then
    begin
      ADetail := TAtlasStrings.Text(TAtlasTextId.HideRefusedAlready);
      Exit;
    end;
    Content.Text := Updated;
    TAtlasTextFile.Save(FileName, Content);
  except
    on E: Exception do
    begin
      ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideFailed, [E.Message]);
      Exit;
    end;
  end;
  TAtlasIdeTeamFile.Refresh;
  Applied;
  AStep.Valid := True;
  AStep.Kind := TAtlasHideKind.TeamFile;
  AStep.FileName := FileName;
  AStep.Place := APlan.Place;
  ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideDoneTeamFile,
    [TAtlasHideMenu.ElementName(APlan.Target.Element, False), APlan.Place.FileName]);
  Result := True;
end;

function TAtlasIdeHide.RunSetting(const AKey: string; out AStep: TStep; out ADetail: string): Boolean;
var
  Stored: TAtlasPluginSettings;
  Session: TAtlasToggleSession;
  Value: Boolean;
begin
  Value := False;
  AStep := Default(TStep);
  AStep.Kind := TAtlasHideKind.Setting;
  AStep.Key := AKey;
  Stored := TAtlasIdeSettings.Stored;
  Session := TAtlasIdeSettings.Session;
  AStep.HadSession := Session.TryGet(AKey, Value) and Value;
  AStep.SessionValue := Value;
  AStep.Changed := TAtlasHide.SwitchOff(Stored, AKey, AStep.OldValue);
  if not AStep.Changed and not AStep.HadSession then
  begin
    ADetail := TAtlasStrings.Text(TAtlasTextId.HideRefusedAlready);
    Exit(False);
  end;
  if AStep.Changed then
    TAtlasIdeSettings.Update(Stored);
  // Ein Schnellschalter „an für diese Sitzung“ hielte das Element sonst sichtbar.
  if AStep.HadSession then
  begin
    Session.Drop(AKey);
    TAtlasIdeSettings.SetSession(Session);
  end;
  Applied;
  AStep.Valid := True;
  ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideDoneSetting, [SettingCaption(AKey)]);
  Result := True;
end;

function TAtlasIdeHide.UndoStep(const AStep: TStep): Boolean;
var
  View: IOTAEditView;
  Text, Reverted, Updated: string;
  Offset: Integer;
  Content: TAtlasTextFileContent;
  Stored: TAtlasPluginSettings;
  Session: TAtlasToggleSession;
begin
  Result := False;
  case AStep.Kind of
    TAtlasHideKind.LineComment, TAtlasHideKind.FileComment:
      begin
        View := TopView;
        if (View = nil) or not AnsiSameText(View.Buffer.FileName, AStep.FileName) then
          Exit;
        Text := TAtlasEditorBuffer.Text(View.Buffer);
        if not AStep.Insert.RevertIn(Text, Reverted) then
          Exit;
        Offset := AStep.Insert.OffsetIn(Text);
        WriteRange(View.Buffer, Text, Offset, Offset + Length(AStep.Insert.Text), '');
      end;
    TAtlasHideKind.TeamFile:
      begin
        if not FileExists(AStep.FileName) then
          Exit;
        Content := TAtlasTextFile.Load(AStep.FileName);
        Updated := TAtlasHiddenPlaces.RemoveFrom(Content.Text, AStep.Place);
        if Updated <> Content.Text then
        begin
          Content.Text := Updated;
          TAtlasTextFile.Save(AStep.FileName, Content);
        end;
        TAtlasIdeTeamFile.Refresh;
      end;
  else
    begin
      if AStep.Changed then
      begin
        Stored := TAtlasIdeSettings.Stored;
        TAtlasHide.Restore(Stored, AStep.Key, AStep.OldValue);
        TAtlasIdeSettings.Update(Stored);
      end;
      if AStep.HadSession then
      begin
        Session := TAtlasIdeSettings.Session;
        Session.Put(AStep.Key, AStep.SessionValue);
        TAtlasIdeSettings.SetSession(Session);
      end;
    end;
  end;
  Applied;
  Result := True;
end;

procedure TAtlasIdeHide.NoticeUndo(Sender: TObject);
var
  Step: TStep;
begin
  Step := FStep;
  FStep := Default(TStep);
  if not Step.Valid then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.Hide,
    procedure
    var
      Ok: Boolean;
    begin
      try
        Ok := UndoStep(Step);
      except
        on E: Exception do
        begin
          TAtlasGuard.Log('Ausblenden: Rückgängig fehlgeschlagen (' + E.ClassName + ')');
          Ok := False;
        end;
      end;
      if Ok then
        Notice('', TAtlasStrings.Text(TAtlasTextId.HideUndone), False)
      else
        Notice('', TAtlasStrings.Text(TAtlasTextId.HideUndoFailed), False);
    end);
end;

procedure TAtlasIdeHide.Notice(const ATitle, ADetail: string; ACanUndo: Boolean);
var
  FontName: string;
  FontSize: Integer;
  Editors: IOTAEditorServices;
begin
  if FNotice = nil then
  begin
    FNotice := TAtlasHideNoticeWindow.Create(nil);
    FNotice.OnUndo := NoticeUndo;
  end;
  FontName := FNotice.Font.Name;
  FontSize := 10;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) and (Editors.EditOptions <> nil) then
  begin
    FontName := Editors.EditOptions.FontName;
    FontSize := Editors.EditOptions.FontSize;
  end;
  FNotice.Colors := TAtlasIdeStyle.Colors;
  FNotice.SetScaling(TAtlasPopupWindow.MonitorPPI(FWhere), 1, FontName, FontSize);
  FNotice.ShowNotice(ATitle, ADetail, ACanUndo, FWhere);
end;

procedure TAtlasIdeHide.Done(const AStep: TStep; const ADetail: string);
var
  Mode: TAtlasNotificationMode;
  Action: TAtlasNotificationAction;
begin
  FStep := AStep;
  Action.Caption := TAtlasStrings.Text(TAtlasTextId.HideUndo);
  Action.Run :=
    procedure
    begin
      TAtlasIdeHide.Undo;
    end;
  // Anonym: kein Dateiname, kein Quelltext.
  TAtlasGuard.Log('Element ausgeblendet (#628)');
  Mode := TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Hidden, TAtlasNotificationSeverity.Info,
    TAtlasStrings.Text(TAtlasTextId.HideNotice), ADetail, [Action]);
  if Mode = TAtlasNotificationMode.Show then
    Notice(TAtlasStrings.Text(TAtlasTextId.HideNotice), ADetail, True);
end;

procedure TAtlasIdeHide.Refused(const AText: string);
begin
  if AText = '' then
    Exit;
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Hidden, TAtlasNotificationSeverity.Info,
    TAtlasStrings.Text(TAtlasTextId.HideElementCommand), AText) = TAtlasNotificationMode.Show then
    Notice('', AText, False);
end;

end.
