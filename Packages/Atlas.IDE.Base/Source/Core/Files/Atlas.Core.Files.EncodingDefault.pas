unit Atlas.Core.Files.EncodingDefault;

// Vorgabe-Kodierung für Dateien ohne offenen Puffer (#121): die Einstellung
// "encoding" aus der nächsten atlas.json über der Datei, wie der Server sie
// für seinen Arbeitsordner liest. Ohne atlas.json, ohne Eintrag oder mit
// unbekanntem Wert gilt UTF-8 (0); die Warnung zum unbekannten Wert meldet
// der Server.

interface

type
  TAtlasEncodingDefault = class
  public
    /// <summary>Wert von "encoding" aus dem Text einer atlas.json als Codepage; 0 ohne gültigen Eintrag.</summary>
    class function FromJson(const AText: string): Integer; static;
    /// <summary>Vorgabe für AFileName aus der nächsten atlas.json im Ordner der Datei oder darüber.</summary>
    class function CodePageFor(const AFileName: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Files.TextFile,
  Atlas.Text.Encoding,
  Atlas.Core.Settings.JsonText;

class function TAtlasEncodingDefault.FromJson(const AText: string): Integer;
var
  Root: TJSONObject;
  Value: TJSONValue;
begin
  Result := 0;
  Root := TAtlasJsonText.Parse(AText);
  if Root = nil then
    Exit;
  try
    Value := Root.GetValue('encoding');
    if (Value is TJSONString) and not TTextEncodingProbe.ParseCodePage(Value.Value, Result) then
      Result := 0;
  finally
    Root.Free;
  end;
end;

class function TAtlasEncodingDefault.CodePageFor(const AFileName: string): Integer;
var
  Folder, Parent, Settings: string;
begin
  Result := 0;
  Folder := ExtractFileDir(TPath.GetFullPath(AFileName));
  while Folder <> '' do
  begin
    Settings := TPath.Combine(Folder, 'atlas.json');
    if TFile.Exists(Settings) then
    begin
      try
        Result := FromJson(TAtlasTextFile.Load(Settings).Text);
      except
        on Exception do
          Result := 0;
      end;
      Exit;
    end;
    Parent := ExtractFileDir(Folder);
    if SameText(Parent, Folder) then
      Exit;
    Folder := Parent;
  end;
end;

end.
