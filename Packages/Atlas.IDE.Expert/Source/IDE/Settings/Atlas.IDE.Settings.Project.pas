unit Atlas.IDE.Settings.Project;

// Projekt > Atlas-Einstellungen… (#227): atlas.json neben der .dproj des
// aktiven Projekts im Dialog bearbeiten. Geschrieben werden nur die geänderten
// Werte (TAtlasJsonText); Kommentare, unbekannte Schlüssel und Reihenfolge
// bleiben. Die Datei behält ihr BOM; neue Dateien entstehen ohne BOM wie bei
// VS Code. Der Server liest die Datei über den Dateibeobachter neu ein.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ActnList,
  Vcl.Menus;

type
  TAtlasProjectSettings = class
  private
    FAction: TAction;
    FMenuItem: TMenuItem;
    procedure ActionExecute(Sender: TObject);
    procedure ActionUpdate(Sender: TObject);
  public
    /// <summary>Menüpunkt hinter „Optionen…“ im Projekt-Menü; ohne dieses nur über Execute.</summary>
    constructor Create;
    destructor Destroy; override;
    /// <summary>atlas.json des aktiven Projekts; '' ohne Projekt.</summary>
    class function SettingsFile: string; static;
    /// <summary>Dialog zeigen und Änderungen schreiben.</summary>
    class procedure Execute; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ProjectDialog;

const
  // Name des Menüpunkts „Projekt > Optionen…“ in der IDE.
  ProjectOptionsItem = 'ProjectOptionsItem';

{ TAtlasProjectSettings }

constructor TAtlasProjectSettings.Create;
var
  Services: INTAServices;
begin
  inherited Create;
  if not Supports(BorlandIDEServices, INTAServices, Services) then
    Exit;
  FAction := TAction.Create(nil);
  FAction.Name := 'AtlasProjectSettingsAction';
  FAction.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsMenu);
  FAction.Category := 'Atlas';
  FAction.OnExecute := ActionExecute;
  FAction.OnUpdate := ActionUpdate;
  FMenuItem := TMenuItem.Create(nil);
  FMenuItem.Name := 'AtlasProjectSettingsItem';
  FMenuItem.Action := FAction;
  try
    Services.AddActionMenu(ProjectOptionsItem, FAction, FMenuItem, True);
  except
    // Menüpunkt nicht gefunden (andere IDE-Version): dann nur über die Befehlspalette.
    FreeAndNil(FMenuItem);
    try
      Services.AddActionMenu('', FAction, nil);
    except
    end;
  end;
end;

destructor TAtlasProjectSettings.Destroy;
begin
  FreeAndNil(FMenuItem);
  FreeAndNil(FAction);
  inherited;
end;

procedure TAtlasProjectSettings.ActionExecute(Sender: TObject);
begin
  Execute;
end;

procedure TAtlasProjectSettings.ActionUpdate(Sender: TObject);
begin
  FAction.Enabled := SettingsFile <> '';
end;

class function TAtlasProjectSettings.SettingsFile: string;
var
  Modules: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Project := Modules.GetActiveProject;
  if (Project <> nil) and (Project.FileName <> '') then
    Result := TPath.Combine(ExtractFileDir(Project.FileName), 'atlas.json');
end;

class procedure TAtlasProjectSettings.Execute;
var
  FileName, Text, NewText: string;
  HasBom: Boolean;
  Root: TJSONObject;
  Dialog: TAtlasProjectSettingsDialog;
  Changes: TArray<TPair<string, string>>;
  Bytes: TBytes;
  OpenFile: Boolean;
  Actions: IOTAActionServices;
begin
  FileName := SettingsFile;
  if FileName = '' then
  begin
    MessageBox(Application.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject)),
      PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle)), MB_ICONINFORMATION or MB_OK);
    Exit;
  end;
  Text := '';
  HasBom := False;
  if TFile.Exists(FileName) then
  begin
    Bytes := TFile.ReadAllBytes(FileName);
    HasBom := (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF);
    if HasBom then
      Text := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
    else
      Text := TEncoding.UTF8.GetString(Bytes);
  end;
  Root := TAtlasJsonText.Parse(Text);
  try
    if (Root = nil) and (Trim(Text) <> '') then
    begin
      MessageBox(Application.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsInvalid)),
        PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle)), MB_ICONWARNING or MB_OK);
      if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
        Actions.OpenFile(FileName);
      Exit;
    end;
    OpenFile := False;
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, TAtlasSettingsSchema.Fields(AtlasSchemaJson), Root,
      FileName);
    try
      Dialog.OnOpenFile :=
        procedure
        begin
          OpenFile := True;
        end;
      if Dialog.ShowModal = mrOk then
        Changes := Dialog.Changes
      else
        Changes := nil;
    finally
      Dialog.Free;
    end;
  finally
    Root.Free;
  end;
  if Length(Changes) > 0 then
  begin
    NewText := TAtlasJsonText.ApplyChanges(Text, Changes);
    if NewText <> Text then
    begin
      Bytes := TEncoding.UTF8.GetBytes(NewText);
      if HasBom then
        Bytes := TEncoding.UTF8.GetPreamble + Bytes;
      TFile.WriteAllBytes(FileName, Bytes);
    end;
  end;
  if OpenFile and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
  begin
    if not TFile.Exists(FileName) then
      TFile.WriteAllBytes(FileName, TEncoding.UTF8.GetBytes('{' + sLineBreak + '}' + sLineBreak));
    Actions.OpenFile(FileName);
  end;
end;

end.
