unit Atlas.IDE.Settings.Project;

// Atlas > Projekt-Einstellungen (#227): atlas.json neben der .dproj des
// aktiven Projekts im Dialog bearbeiten. Geschrieben werden nur die geänderten
// Werte (TAtlasJsonText); Kommentare, unbekannte Schlüssel und Reihenfolge
// bleiben. Die Datei behält ihr BOM; neue Dateien entstehen ohne BOM wie bei
// VS Code. Der Server liest die Datei über den Dateibeobachter neu ein.
// Die Schnellschalter (#604) lesen und setzen einzelne Werte über
// ReadProject und WriteValue.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasProjectSettings = class
  public
    /// <summary>atlas.json des aktiven Projekts; '' ohne Projekt.</summary>
    class function SettingsFile: string; static;
    /// <summary>Dialog zeigen und Änderungen schreiben.</summary>
    class procedure Execute; static;
    /// <summary>Inhalt der Datei als Text (ohne BOM); '' wenn es sie nicht gibt.</summary>
    class function ReadText(const AFileName: string; out AHasBom: Boolean): string; static;
    /// <summary>atlas.json des aktiven Projekts als Objekt; nil ohne Projekt, ohne Datei oder bei ungültigem
    /// Inhalt. Der Aufrufer gibt es frei.</summary>
    class function ReadProject: TJSONObject; static;
    /// <summary>Setzt APath in atlas.json des aktiven Projekts auf AJson; Kommentare, Reihenfolge und BOM
    /// bleiben. False ohne Projekt.</summary>
    class function WriteValue(const APath, AJson: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ProjectDialog;

{ TAtlasProjectSettings }

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

class function TAtlasProjectSettings.ReadText(const AFileName: string; out AHasBom: Boolean): string;
var
  Bytes: TBytes;
begin
  Result := '';
  AHasBom := False;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;
  Bytes := TFile.ReadAllBytes(AFileName);
  AHasBom := (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF);
  if AHasBom then
    Result := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(Bytes);
end;

class function TAtlasProjectSettings.ReadProject: TJSONObject;
var
  HasBom: Boolean;
begin
  Result := TAtlasJsonText.Parse(ReadText(SettingsFile, HasBom));
end;

class function TAtlasProjectSettings.WriteValue(const APath, AJson: string): Boolean;
var
  FileName, Text, NewText: string;
  HasBom: Boolean;
  Bytes: TBytes;
begin
  FileName := SettingsFile;
  Result := FileName <> '';
  if not Result then
    Exit;
  Text := ReadText(FileName, HasBom);
  NewText := TAtlasJsonText.SetValue(Text, APath, AJson);
  if NewText = Text then
    Exit;
  Bytes := TEncoding.UTF8.GetBytes(NewText);
  if HasBom then
    Bytes := TEncoding.UTF8.GetPreamble + Bytes;
  TFile.WriteAllBytes(FileName, Bytes);
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
  Text := ReadText(FileName, HasBom);
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
