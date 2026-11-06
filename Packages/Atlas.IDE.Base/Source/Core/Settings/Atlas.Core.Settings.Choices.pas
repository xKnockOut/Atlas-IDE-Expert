unit Atlas.Core.Settings.Choices;

// Auswahllisten des Einstellungsdialogs (#227), die nicht im Schema stehen:
//   - delphiVersion: installierte Versionen als „Delphi 12 (23.0)“, gespeichert
//     wird die Registry-Nummer ("23.0").
//   - minDelphiVersion (#1126): alle bekannten Versionen, auch nicht installierte,
//     denn das Projekt muss mit ihnen übersetzen, nicht diese IDE.
//   - config und platform: aus der .dproj des Projekts (BuildConfiguration,
//     Platforms).
//   - profile und testProfile: eingebaute Profile und die eigenen aus "profiles".
// Ohne VCL und ohne Registry: Die IDE-Schicht liefert installierte Versionen
// und den Text der .dproj.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Eintrag einer Auswahl: Anzeige und gespeicherter JSON-Text.</summary>
  TAtlasSettingChoice = record
    Caption: string;
    Json: string;
    class function Create(const ACaption, AJson: string): TAtlasSettingChoice; static;
  end;

  TAtlasSettingChoices = class
  public
    /// <summary>"Delphi 12" zu "23.0"; '' für unbekannte Nummern.</summary>
    class function DelphiProduct(const ARegistryVersion: string): string; static;
    /// <summary>"Delphi 12 (23.0)" bzw. nur die Nummer, wenn das Produkt unbekannt ist.</summary>
    class function DelphiCaption(const ARegistryVersion: string): string; static;
    /// <summary>Installierte Versionen (Registry-Nummern), neueste zuerst, ohne Doppelte.</summary>
    class function DelphiVersions(const AInstalled: TArray<string>): TArray<TAtlasSettingChoice>; static;
    /// <summary>Alle bekannten Versionen (Registry-Nummern), neueste zuerst; für minDelphiVersion (#1126).</summary>
    class function KnownVersions: TArray<string>; static;
    /// <summary>Build-Konfigurationen der .dproj ohne "Base", in der Reihenfolge der Datei.</summary>
    class function DprojConfigs(const ADprojText: string): TArray<string>; static;
    /// <summary>Aktive Plattformen der .dproj (Platform value="…" mit True).</summary>
    class function DprojPlatforms(const ADprojText: string): TArray<string>; static;
    /// <summary>Eingebaute Profile und die Namen aus "profiles" (JSON-Text eines Objekts).</summary>
    class function Profiles(const AProfilesJson: string): TArray<string>; static;
    /// <summary>Texte als Auswahl mit String-JSON.</summary>
    class function FromTexts(const ATexts: TArray<string>): TArray<TAtlasSettingChoice>; static;
    /// <summary>Index von AJson in AChoices; -1 ohne.</summary>
    class function IndexOf(const AChoices: TArray<TAtlasSettingChoice>; const AJson: string): Integer; static;
  end;

const
  /// <summary>Eingebaute Regelprofile des Servers.</summary>
  AtlasBuiltInProfiles: array[0..4] of string = ('standard', 'fast', 'strict', 'security', 'style');

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Settings.JsonText;

type
  TDelphiProduct = record
    Version: string;
    Product: string;
  end;

const
  Products: array[0..9] of TDelphiProduct = (
    (Version: '37.0'; Product: 'Delphi 13'),
    (Version: '23.0'; Product: 'Delphi 12'),
    (Version: '22.0'; Product: 'Delphi 11'),
    (Version: '21.0'; Product: 'Delphi 10.4'),
    (Version: '20.0'; Product: 'Delphi 10.3'),
    (Version: '19.0'; Product: 'Delphi 10.2'),
    (Version: '18.0'; Product: 'Delphi 10.1'),
    (Version: '17.0'; Product: 'Delphi 10'),
    (Version: '16.0'; Product: 'Delphi XE8'),
    (Version: '15.0'; Product: 'Delphi XE7'));

function VersionNumber(const AVersion: string): Double;
var
  Settings: TFormatSettings;
begin
  Settings := TFormatSettings.Invariant;
  Result := StrToFloatDef(AVersion, 0, Settings);
end;

/// <summary>Wert des Attributs AName im Tag ab APos; '' ohne.</summary>
function AttributeAfter(const AText, AName: string; APos: Integer): string;
var
  Start, Stop, TagEnd: Integer;
begin
  Result := '';
  TagEnd := Pos('>', AText, APos);
  Start := Pos(AName + '="', AText, APos);
  if (Start = 0) or ((TagEnd > 0) and (Start > TagEnd)) then
  begin
    Exit;
  end;
  Inc(Start, Length(AName) + 2);
  Stop := Pos('"', AText, Start);
  if Stop > Start then
  begin
    Result := Copy(AText, Start, Stop - Start);
  end;
end;

procedure AddUnique(var AList: TArray<string>; const AValue: string);
var
  Item: string;
begin
  if AValue = '' then
  begin
    Exit;
  end;
  for Item in AList do
  begin
    if SameText(Item, AValue) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AValue];
end;

{ TAtlasSettingChoice }

class function TAtlasSettingChoice.Create(const ACaption, AJson: string): TAtlasSettingChoice;
begin
  Result.Caption := ACaption;
  Result.Json := AJson;
end;

{ TAtlasSettingChoices }

class function TAtlasSettingChoices.DelphiProduct(const ARegistryVersion: string): string;
var
  Product: TDelphiProduct;
begin
  Result := '';
  for Product in Products do
  begin
    if Product.Version = Trim(ARegistryVersion) then
    begin
      Exit(Product.Product);
    end;
  end;
end;

class function TAtlasSettingChoices.DelphiCaption(const ARegistryVersion: string): string;
var
  Product: string;
begin
  Product := DelphiProduct(ARegistryVersion);
  if Product = '' then
  begin
    Result := Trim(ARegistryVersion);
  end
  else
  begin
    Result := Format('%s (%s)', [Product, Trim(ARegistryVersion)]);
  end;
end;

class function TAtlasSettingChoices.KnownVersions: TArray<string>;
var
  Product: TDelphiProduct;
begin
  Result := nil;
  for Product in Products do
  begin
    Result := Result + [Product.Version];
  end;
end;

class function TAtlasSettingChoices.DelphiVersions(const AInstalled: TArray<string>): TArray<TAtlasSettingChoice>;
var
  Versions: TArray<string>;
  Version: string;
  List: TList<string>;
begin
  Versions := nil;
  for Version in AInstalled do
  begin
    AddUnique(Versions, Trim(Version));
  end;
  List := TList<string>.Create(TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      // Neueste zuerst.
      if VersionNumber(A) > VersionNumber(B) then
      begin
        Result := -1;
      end
      else if VersionNumber(A) < VersionNumber(B) then
      begin
        Result := 1;
      end
      else
      begin
        Result := CompareText(A, B);
      end;
    end));
  try
    List.AddRange(Versions);
    List.Sort;
    Result := nil;
    for Version in List do
    begin
      Result := Result + [TAtlasSettingChoice.Create(DelphiCaption(Version), TAtlasJsonText.Quote(Version))];
    end;
  finally
    List.Free;
  end;
end;

class function TAtlasSettingChoices.DprojConfigs(const ADprojText: string): TArray<string>;
var
  Position: Integer;
  Name: string;
begin
  Result := nil;
  Position := Pos('<BuildConfiguration ', ADprojText);
  while Position > 0 do
  begin
    Name := AttributeAfter(ADprojText, 'Include', Position);
    if not SameText(Name, 'Base') then
    begin
      AddUnique(Result, Name);
    end;
    Position := Pos('<BuildConfiguration ', ADprojText, Position + 1);
  end;
end;

class function TAtlasSettingChoices.DprojPlatforms(const ADprojText: string): TArray<string>;
var
  Position, Close, Stop: Integer;
  Name, Value: string;
begin
  Result := nil;
  Position := Pos('<Platform value=', ADprojText);
  while Position > 0 do
  begin
    Name := AttributeAfter(ADprojText, 'value', Position);
    Close := Pos('>', ADprojText, Position);
    Stop := Pos('</Platform>', ADprojText, Close);
    Value := '';
    if (Close > 0) and (Stop > Close) then
    begin
      Value := Trim(Copy(ADprojText, Close + 1, Stop - Close - 1));
    end;
    if SameText(Value, 'True') then
    begin
      AddUnique(Result, Name);
    end;
    Position := Pos('<Platform value=', ADprojText, Position + 1);
  end;
end;

class function TAtlasSettingChoices.Profiles(const AProfilesJson: string): TArray<string>;
var
  Name: string;
  Value: TJSONValue;
  Pair: TJSONPair;
begin
  Result := nil;
  for Name in AtlasBuiltInProfiles do
  begin
    AddUnique(Result, Name);
  end;
  if AProfilesJson = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AProfilesJson);
  try
    if Value is TJSONObject then
    begin
      for Pair in TJSONObject(Value) do
      begin
        AddUnique(Result, Pair.JsonString.Value);
      end;
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasSettingChoices.FromTexts(const ATexts: TArray<string>): TArray<TAtlasSettingChoice>;
var
  Text: string;
begin
  Result := nil;
  for Text in ATexts do
  begin
    Result := Result + [TAtlasSettingChoice.Create(Text, TAtlasJsonText.Quote(Text))];
  end;
end;

class function TAtlasSettingChoices.IndexOf(const AChoices: TArray<TAtlasSettingChoice>; const AJson: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AChoices) do
  begin
    if AChoices[Index].Json = AJson then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

end.
