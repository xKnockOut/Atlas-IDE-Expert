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
  mRoot: TJSONObject;
  mValue: TJSONValue;
begin
  Result := 0;
  mRoot := TAtlasJsonText.Parse(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    mValue := mRoot.GetValue('encoding');
    if (mValue is TJSONString) and not TTextEncodingProbe.ParseCodePage(mValue.Value, Result) then
    begin
      Result := 0;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasEncodingDefault.CodePageFor(const AFileName: string): Integer;
var
  mFolder, mParent, mSettings: string;
begin
  Result := 0;
  mFolder := ExtractFileDir(TPath.GetFullPath(AFileName));
  while mFolder <> '' do
  begin
    mSettings := TPath.Combine(mFolder, 'atlas.json');
    if TFile.Exists(mSettings) then
    begin
      try
        Result := FromJson(TAtlasTextFile.Load(mSettings).Text);
      except
        on Exception do
          Result := 0;
      end;
      Exit;
    end;
    mParent := ExtractFileDir(mFolder);
    if SameText(mParent, mFolder) then
    begin
      Exit;
    end;
    mFolder := mParent;
  end;
end;

end.
